local db = require("lapis.db")
local BaseRepository = require("src.modules.baseRepository")

local LocationRepository = setmetatable({}, { __index = BaseRepository })
LocationRepository.__index = LocationRepository

function LocationRepository:save(data)
    if not data.account_id then
        return nil, "INVALID_INPUT"
    end

    local lng = tonumber(data.lng)
    local lat = tonumber(data.lat)
    -- nil 을 그대로 넘기면 Lua 가변인자에서 잘려 interpolate_query 가 실패한다. NULL 로 넘긴다.
    local observed_at = data.observed_at or db.NULL

    -- geom 이 공간 인덱스의 기준이고, longitude/latitude 는 같은 좌표를 그대로 보관하는 편의 컬럼이다.
    -- observed_at 은 실제 관측 시각(미지정이면 적재 시각과 동일).
    return db.query([[
        INSERT INTO mcp_spatial_raw_data
            (account_id, birth_year, gender, longitude, latitude, geom, created_at, observed_at)
        VALUES (?, ?, ?, ?, ?, ST_SetSRID(ST_MakePoint(?, ?), 4326), now(), COALESCE(?, now()))
        RETURNING id
    ]], data.account_id, tonumber(data.birth_year), data.gender,
        lng, lat, lng, lat, observed_at)
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
               COALESCE(longitude, ST_X(geom)) AS lng,
               COALESCE(latitude,  ST_Y(geom)) AS lat,
               created_at,
               observed_at
        FROM mcp_spatial_raw_data
        WHERE ]] .. table.concat(where, " AND ")

    return db.query(sql, table.unpack(params))
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
            COALESCE(longitude, ST_X(geom)) AS lng,
            COALESCE(latitude,  ST_Y(geom)) AS lat,
            birth_year,
            gender,
            -- 활동 시각은 관측 시각 기준. observed_at 이 비면 적재 시각으로 대체한다.
            EXTRACT(HOUR FROM COALESCE(observed_at, created_at)) AS hour
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

    -- 위·경도 covering B-tree 인덱스만 읽어 후보를 집계한다.
    -- 경도 1도의 실제 거리는 위도에 따라 달라지므로 위도별 보정값을 적용한다.
    local latitude = tonumber(center_lat)
    local longitude = tonumber(center_lng)
    if not latitude or not longitude then
        return nil, "INVALID_INPUT"
    end
    local latitude_delta = radius / 111320.0
    local longitude_delta = radius / (111320.0 * math.max(math.abs(math.cos(math.rad(latitude))), 0.01))
    local min_latitude, max_latitude = latitude - latitude_delta, latitude + latitude_delta
    local min_longitude, max_longitude = longitude - longitude_delta, longitude + longitude_delta
    local meters_per_longitude = 111320.0 * math.max(math.abs(math.cos(math.rad(latitude))), 0.01)

    local sql = [[
        SELECT
            ST_GeoHash(ST_SetSRID(ST_MakePoint(longitude, latitude), 4326), ?) AS cell,
            COUNT(*) AS total_foot,
            COUNT(*) FILTER (
                WHERE ? IS NOT NULL
                  AND ? IS NOT NULL
                  AND birth_year BETWEEN ? AND ?
            ) AS age_match,
            COUNT(*) FILTER (
                WHERE COALESCE(?, 'ANY') = 'ANY'
                   OR gender = CASE UPPER(?)
                       WHEN 'M' THEN 'MALE'
                       WHEN 'F' THEN 'FEMALE'
                       ELSE ?
                   END
            ) AS gender_match,
            ROUND(AVG(EXTRACT(HOUR FROM COALESCE(observed_at, created_at)))::numeric, 1) AS avg_hour,
            AVG(latitude) AS lat,
            AVG(longitude) AS lng
        FROM mcp_spatial_raw_data
        WHERE latitude BETWEEN ? AND ?
          AND longitude BETWEEN ? AND ?
          AND POWER((longitude - ?) * ?, 2)
              + POWER((latitude - ?) * 111320.0, 2) <= POWER(?, 2)
        GROUP BY 1
    ]]

    return db.query(
        sql,
        geohash_precision,
        by_min, by_max, by_min, by_max,
        gender, gender, gender,
        min_latitude, max_latitude, min_longitude, max_longitude,
        longitude, meters_per_longitude, latitude, radius
    )
end

-- 반경 내 원천 데이터를 보고서용 분포로 집계한다. 원시 행은 MCP 밖으로 전송하지 않는다.
function LocationRepository:summarizeInRadius(
    center_lng, center_lat, radius_m, birth_year_min, birth_year_max
)
    if not (center_lng and center_lat) then
        return nil, "INVALID_INPUT"
    end

    local radius = tonumber(radius_m) or 1500
    local latitude = tonumber(center_lat)
    local longitude = tonumber(center_lng)
    if not latitude or not longitude then
        return nil, "INVALID_INPUT"
    end

    local latitude_delta = radius / 111320.0
    local longitude_delta = radius / (111320.0 * math.max(math.abs(math.cos(math.rad(latitude))), 0.01))
    local min_latitude, max_latitude = latitude - latitude_delta, latitude + latitude_delta
    local min_longitude, max_longitude = longitude - longitude_delta, longitude + longitude_delta
    local meters_per_longitude = 111320.0 * math.max(math.abs(math.cos(math.rad(latitude))), 0.01)
    local by_min = tonumber(birth_year_min)
    local by_max = tonumber(birth_year_max)

    local sql = [[
        WITH filtered AS MATERIALIZED (
            SELECT birth_year, gender, COALESCE(observed_at, created_at) AS observed_at
            FROM mcp_spatial_raw_data
            WHERE latitude BETWEEN ? AND ?
              AND longitude BETWEEN ? AND ?
              AND POWER((longitude - ?) * ?, 2)
                  + POWER((latitude - ?) * 111320.0, 2) <= POWER(?, 2)
        ), total AS (
            SELECT COUNT(*)::bigint AS value FROM filtered
        ), gender_distribution AS (
            SELECT CASE UPPER(gender)
                       WHEN 'MALE' THEN '남성'
                       WHEN 'M' THEN '남성'
                       WHEN 'FEMALE' THEN '여성'
                       WHEN 'F' THEN '여성'
                       ELSE '기타'
                   END AS label,
                   COUNT(*)::bigint AS value
            FROM filtered
            GROUP BY 1
        ), age_distribution AS (
            SELECT CONCAT((FLOOR(GREATEST(EXTRACT(YEAR FROM CURRENT_DATE)::int - birth_year, 0) / 10) * 10)::int, '대') AS label,
                   COUNT(*)::bigint AS value
            FROM filtered
            GROUP BY 1
            ORDER BY 1
        ), time_distribution AS (
            SELECT CONCAT(LPAD(EXTRACT(HOUR FROM observed_at)::int::text, 2, '0'), '시') AS label,
                   COUNT(*)::bigint AS value
            FROM filtered
            GROUP BY 1
            ORDER BY 1
        ), day_distribution AS (
            SELECT CASE EXTRACT(ISODOW FROM observed_at)::int
                       WHEN 1 THEN '월요일' WHEN 2 THEN '화요일' WHEN 3 THEN '수요일'
                       WHEN 4 THEN '목요일' WHEN 5 THEN '금요일' WHEN 6 THEN '토요일'
                       ELSE '일요일'
                   END AS label,
                   COUNT(*)::bigint AS value
            FROM filtered
            GROUP BY EXTRACT(ISODOW FROM observed_at)::int
            ORDER BY EXTRACT(ISODOW FROM observed_at)::int
        ), month_distribution AS (
            SELECT TO_CHAR(observed_at, 'YYYY-MM') AS label,
                   COUNT(*)::bigint AS value
            FROM filtered
            GROUP BY 1
            ORDER BY 1
        )
        SELECT
            (SELECT value FROM total) AS total,
            (SELECT COUNT(*)::bigint FROM filtered WHERE ? IS NOT NULL AND ? IS NOT NULL AND birth_year BETWEEN ? AND ?) AS age_match,
            COALESCE((SELECT jsonb_agg(jsonb_build_object('label', label, 'value', value, 'unit', '명')) FROM gender_distribution), '[]'::jsonb) AS gender,
            COALESCE((SELECT jsonb_agg(jsonb_build_object('label', label, 'value', value, 'unit', '명')) FROM age_distribution), '[]'::jsonb) AS age,
            COALESCE((SELECT jsonb_agg(jsonb_build_object('label', label, 'value', value, 'unit', '건')) FROM time_distribution), '[]'::jsonb) AS by_time,
            COALESCE((SELECT jsonb_agg(jsonb_build_object('label', label, 'value', value, 'unit', '건')) FROM day_distribution), '[]'::jsonb) AS by_day,
            COALESCE((SELECT jsonb_agg(jsonb_build_object('label', label, 'value', value, 'unit', '건')) FROM month_distribution), '[]'::jsonb) AS by_month
    ]]

    return db.query(
        sql,
        min_latitude, max_latitude, min_longitude, max_longitude,
        longitude, meters_per_longitude, latitude, radius,
        by_min, by_max, by_min, by_max
    )
end

-- 주변 장소 데이터는 map_place 원천에서 읽어 AI가 경쟁·편의·교통 시설로 분류할 수 있게 한다.
function LocationRepository:findNearbyPlaces(center_lng, center_lat, radius_m)
    if not (center_lng and center_lat) then
        return nil, "INVALID_INPUT"
    end

    local radius = tonumber(radius_m) or 1500
    local latitude = tonumber(center_lat)
    local longitude = tonumber(center_lng)
    if not latitude or not longitude then
        return nil, "INVALID_INPUT"
    end

    local latitude_delta = radius / 111320.0
    local longitude_delta = radius / (111320.0 * math.max(math.abs(math.cos(math.rad(latitude))), 0.01))
    local min_latitude, max_latitude = latitude - latitude_delta, latitude + latitude_delta
    local min_longitude, max_longitude = longitude - longitude_delta, longitude + longitude_delta
    local meters_per_longitude = 111320.0 * math.max(math.abs(math.cos(math.rad(latitude))), 0.01)

    local sql = [[
        SELECT map_place_id AS place_id,
               place_name AS name,
               address,
               category,
               ROUND(((POWER((longitude - ?) * ?, 2)
                    + POWER((latitude - ?) * 111320.0, 2)) ^ 0.5)::numeric, 1) AS distance_m
        FROM map_place
        WHERE latitude BETWEEN ? AND ?
          AND longitude BETWEEN ? AND ?
          AND POWER((longitude - ?) * ?, 2)
              + POWER((latitude - ?) * 111320.0, 2) <= POWER(?, 2)
          AND COALESCE(operating_status, 'OPERATING') = 'OPERATING'
          AND COALESCE(discovery_status, 'VISIBLE') = 'VISIBLE'
        ORDER BY distance_m, map_place_id
        LIMIT 100
    ]]

    return db.query(
        sql,
        longitude, meters_per_longitude, latitude,
        min_latitude, max_latitude, min_longitude, max_longitude,
        longitude, meters_per_longitude, latitude, radius
    )
end

return LocationRepository
