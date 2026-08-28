require("config")

local db = require("lapis.db")
local geohash = require("src.modules.geohash")
local repository = require("src.global.repository.locationRepository")

local CENTER_LNG = 128.5955669
local CENTER_LAT = 35.9235922
local RADIUS_M = 1500
local PRECISION = 7

local function rows_by_cell(rows)
    local indexed = {}
    for _, row in ipairs(rows) do
        indexed[row.cell] = row
    end
    return indexed
end

local function assert_number_equal(actual, expected, field, cell, tolerance)
    local actual_number = tonumber(actual)
    local expected_number = tonumber(expected)
    assert(actual_number ~= nil, string.format("%s is not numeric for cell %s", field, cell))
    assert(expected_number ~= nil, string.format("legacy %s is not numeric for cell %s", field, cell))
    assert(
        math.abs(actual_number - expected_number) <= tolerance,
        string.format(
            "%s mismatch for cell %s: sql=%s legacy=%s",
            field, cell, tostring(actual), tostring(expected)
        )
    )
end

local function compare_legacy_and_sql(by_min, by_max, gender)
    local raw_rows, raw_error = repository:findInRadius(CENTER_LNG, CENTER_LAT, RADIUS_M)
    assert(raw_rows, raw_error)

    local legacy_rows = geohash.aggregate(raw_rows, {
        precision = PRECISION,
        by_min = by_min,
        by_max = by_max,
        gender = gender,
    })
    local sql_rows, sql_error = repository:aggregateInRadius(
        CENTER_LNG, CENTER_LAT, RADIUS_M, by_min, by_max, gender, PRECISION
    )
    assert(sql_rows, sql_error)
    assert(#sql_rows == #legacy_rows, "SQL and legacy aggregation should return the same cells")

    local legacy_by_cell = rows_by_cell(legacy_rows)
    for _, sql_row in ipairs(sql_rows) do
        local legacy_row = legacy_by_cell[sql_row.cell]
        assert(legacy_row, "legacy aggregation is missing SQL cell " .. tostring(sql_row.cell))
        assert_number_equal(sql_row.total_foot, legacy_row.total_foot, "total_foot", sql_row.cell, 0)
        assert_number_equal(sql_row.age_match, legacy_row.age_match, "age_match", sql_row.cell, 0)
        assert_number_equal(sql_row.gender_match, legacy_row.gender_match, "gender_match", sql_row.cell, 0)
        assert_number_equal(sql_row.avg_hour, legacy_row.avg_hour, "avg_hour", sql_row.cell, 0.000001)
        assert_number_equal(sql_row.lat, legacy_row.lat, "lat", sql_row.cell, 0.000000001)
        assert_number_equal(sql_row.lng, legacy_row.lng, "lng", sql_row.cell, 0.000000001)
    end
end

local ok, test_error = xpcall(function()
    db.query("BEGIN")
    db.query([[
        CREATE TEMP TABLE mcp_spatial_raw_data (
            account_id BIGINT,
            birth_year INTEGER,
            gender VARCHAR(8),
            longitude DOUBLE PRECISION NOT NULL,
            latitude DOUBLE PRECISION NOT NULL,
            geom geometry(Point, 4326) NOT NULL,
            created_at TIMESTAMP NOT NULL,
            observed_at TIMESTAMP NOT NULL
        ) ON COMMIT DROP
    ]])
    db.query([[
        INSERT INTO mcp_spatial_raw_data
            (account_id, birth_year, gender, longitude, latitude, geom, created_at, observed_at)
        SELECT
            point_number,
            1980 + (point_number % 35),
            CASE WHEN point_number % 2 = 0 THEN 'M' ELSE 'F' END,
            128.5955669 + (((point_number % 20) - 10) * 0.0003),
            35.9235922 + (((point_number / 20) - 5) * 0.0003),
            ST_SetSRID(
                ST_MakePoint(
                    128.5955669 + (((point_number % 20) - 10) * 0.0003),
                    35.9235922 + (((point_number / 20) - 5) * 0.0003)
                ),
                4326
            ),
            TIMESTAMP '2026-08-20 00:00:00' + ((point_number % 24) || ' hours')::interval,
            TIMESTAMP '2026-08-20 00:00:00' + ((point_number % 24) || ' hours')::interval
        FROM generate_series(0, 199) AS point_number
    ]])

    compare_legacy_and_sql(1987, 2006, "ANY")
    compare_legacy_and_sql(1990, 2000, "F")
    compare_legacy_and_sql(1980, 2014, "M")
    compare_legacy_and_sql(2100, 2200, "ANY")
end, debug.traceback)

pcall(db.query, "ROLLBACK")
assert(ok, test_error)

print("Location repository legacy parity integration OK")
