require("config")
local db = require("lapis.db")

-- 운영 앱을 교체하기 전에 실제 연결 대상의 스키마와 SELECT 권한을 검사한다.
-- 원시 데이터는 가져오지 않으며 테이블 생성이나 마이그레이션도 수행하지 않는다.
local ok = pcall(function()
    db.query("BEGIN READ ONLY")
    db.query("SET LOCAL statement_timeout = '10s'")
    db.query("SELECT PostGIS_Version()")
    db.query([[
        SELECT id, account_id, birth_year, gender, longitude, latitude,
               geom, created_at, observed_at
        FROM mcp_spatial_raw_data
        LIMIT 0
    ]])
    db.query([[
        SELECT map_place_id, place_name, address, category, longitude, latitude,
               operating_status, discovery_status
        FROM map_place
        LIMIT 0
    ]])
end)

pcall(function() db.query("ROLLBACK") end)

if not ok then
    -- 드라이버 예외에는 연결 정보가 포함될 수 있어 그대로 출력하지 않는다.
    io.stderr:write("MCP database check failed. Check DB connection, PostGIS, tables and SELECT permissions.\n")
    os.exit(1)
end

print("MCP database check passed (read-only schema and SELECT permission check).")
