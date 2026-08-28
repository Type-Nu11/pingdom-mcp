-- 초기 스키마. 새 환경에서는 시드(seed_locations.sql) 전에 한 번 실행한다.
--   docker compose exec -T db psql -U postgres -d pingdom_dev -f /dev/stdin < sql/schema.sql
CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE IF NOT EXISTS mcp_spatial_raw_data (
    id            serial PRIMARY KEY,
    account_id    text NOT NULL,
    birth_year    int,
    gender        text,
    longitude     double precision,
    latitude      double precision,
    geom          geometry(Point, 4326),
    created_at    timestamptz NOT NULL DEFAULT now(),   -- 적재 시각
    observed_at   timestamptz,                          -- 실제 관측 시각
    business_type text
);

-- ST_DWithin 반경 검색용
CREATE INDEX IF NOT EXISTS mcp_spatial_raw_data_geom_idx
    ON mcp_spatial_raw_data USING GIST (geom);

-- 입지 반경 조회 시 위·경도 사각 범위 선필터에 사용하는 복합 인덱스
CREATE INDEX IF NOT EXISTS mcp_spatial_raw_data_latitude_longitude_idx
    ON mcp_spatial_raw_data (latitude, longitude);
