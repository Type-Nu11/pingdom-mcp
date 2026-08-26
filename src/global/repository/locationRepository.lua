local db = require("lapis.db")
local BaseRepository = require("src.modules.baseRepository")
local unpack = table.unpack or unpack

local LocationRepository = setmetatable({}, { __index = BaseRepository })
LocationRepository.__index = LocationRepository

function LocationRepository:save(data)
    if not data.account_id then
        return nil, "INVALID_INPUT"
    end

    return db.query([[
        INSERT INTO mcp_spatial_raw_data (account_id, birth_year, gender, geom, created_at)
        VALUES (?, ?, ?, ST_SetSRID(ST_MakePoint(?, ?), 4326), now())
        RETURNING id
    ]], data.account_id, tonumber(data.birth_year), data.gender, tonumber(data.lng), tonumber(data.lat))
end

-- 조회
function LocationRepository:findByFilters(gender, birth_year, created_at)
    if not gender and not birth_year and not created_at then
        return nil, "INVALID_INPUT"
    end

    local where, params = {}, {}

    if gender then
        table.insert(where, "gender = ?")
        table.insert(params, gender)
    end
    if birth_year then
        table.insert(where, "birth_year = ?")
        table.insert(params, tonumber(birth_year))
    end
    if created_at then
        table.insert(where, "created_at::date = ?")
        table.insert(params, created_at)   -- "2026-06-04"
    end

    local sql = [[
        SELECT account_id, birth_year, gender,
               ST_X(geom) AS lng,
               ST_Y(geom) AS lat,
               created_at
        FROM mcp_spatial_raw_data
        WHERE ]] .. table.concat(where, " AND ")

    return db.query(sql, unpack(params))
end

-- 입지 추천: 중심좌표 반경 내 원시 포인트 반환. (geohash 셀 묶기/집계는 geohash 모듈이 담당)
-- 반환 row: { lng, lat, birth_year, gender, hour }
function LocationRepository:findInRadius(center_lng, center_lat, radius_m)
    if not (center_lng and center_lat) then
        return nil, "INVALID_INPUT"
    end

    local radius = tonumber(radius_m) or 1500

    local sql = [[
        SELECT
            ST_X(geom)                    AS lng,
            ST_Y(geom)                    AS lat,
            birth_year,
            gender,
            EXTRACT(HOUR FROM created_at) AS hour
        FROM mcp_spatial_raw_data
        WHERE ST_DWithin(
            geom::geography,
            ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography,
            ?
        )
    ]]

    return db.query(sql, tonumber(center_lng), tonumber(center_lat), radius)
end

-- 입지 추천용 공간 집계. 원시 포인트를 애플리케이션으로 전송하지 않고 DB에서 geohash 셀로 집계한다.
function LocationRepository:aggregateInRadius(
    center_lng, center_lat, radius_m, birth_year_min, birth_year_max, gender, precision
)
    if not (center_lng and center_lat) then
        return nil, "INVALID_INPUT"
    end

    local radius = tonumber(radius_m) or 1500
    local geohash_precision = tonumber(precision) or 7
    local by_min = tonumber(birth_year_min)
    local by_max = tonumber(birth_year_max)

    local sql = [[
        SELECT
            ST_GeoHash(geom, ?) AS cell,
            COUNT(*) AS total_foot,
            COUNT(*) FILTER (
                WHERE ? IS NOT NULL
                  AND ? IS NOT NULL
                  AND birth_year BETWEEN ? AND ?
            ) AS age_match,
            COUNT(*) FILTER (
                WHERE COALESCE(?, 'ANY') = 'ANY' OR gender = ?
            ) AS gender_match,
            ROUND(AVG(EXTRACT(HOUR FROM created_at))::numeric, 1) AS avg_hour,
            AVG(ST_Y(geom)) AS lat,
            AVG(ST_X(geom)) AS lng
        FROM mcp_spatial_raw_data
        WHERE ST_DWithin(
            geom::geography,
            ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography,
            ?
        )
        GROUP BY 1
    ]]

    return db.query(
        sql,
        geohash_precision,
        by_min, by_max, by_min, by_max,
        gender, gender,
        tonumber(center_lng), tonumber(center_lat), radius
    )
end

return LocationRepository
