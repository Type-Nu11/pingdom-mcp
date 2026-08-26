-- 더미 데이터: 대구시 전역(8개 구·군) × 업종 5종, 약 2000건
-- 업종 컬럼 추가 + 한 번에 클린 재실행
ALTER TABLE mcp_spatial_raw_data ADD COLUMN IF NOT EXISTS business_type text;
TRUNCATE mcp_spatial_raw_data RESTART IDENTITY;

WITH
-- 설정: 구 좌표 배열 + 업종별 연령/남성비율 배열 (배열은 1-인덱스)
cfg AS (
    SELECT
        ARRAY[128.5910,128.6330,128.5590,128.5880,128.5830,128.6300,128.5320,128.4310]::float8[] AS dlng,
        ARRAY[35.8690, 35.8870, 35.8720, 35.8460, 35.8860, 35.8580, 35.8270, 35.7740]::float8[]  AS dlat,
        ARRAY['카페','헬스장','음식점','술집','병원']::text[]                                       AS btype,
        ARRAY[20, 20, 20, 20, 40]::int[]                                                          AS alo,
        ARRAY[35, 45, 60, 38, 75]::int[]                                                          AS ahi,
        ARRAY[0.40, 0.50, 0.50, 0.55, 0.45]::float8[]                                             AS mr
),
-- 행마다 구 인덱스(1~8)·업종 인덱스(1~5) 랜덤 배정 (MATERIALIZED: 한 번만 계산해 고정)
picks AS MATERIALIZED (
    SELECT g,
           floor(random() * 8)::int + 1 AS di,
           floor(random() * 5)::int + 1 AS bi
    FROM generate_series(1, 2000) AS g
),
-- 좌표를 한 번만 뽑아 longitude/latitude/geom 이 서로 어긋나지 않게 한다.
coords AS MATERIALIZED (
    SELECT p.g, p.di, p.bi,
           c.dlng[p.di] + (random() - 0.5) * 0.03 AS lng,   -- 구 내 약 ±1.3km 분산
           c.dlat[p.di] + (random() - 0.5) * 0.03 AS lat,
           now() - (random() * interval '30 days')  AS observed_at
    FROM picks p CROSS JOIN cfg c
)
INSERT INTO mcp_spatial_raw_data
    (account_id, birth_year, gender, longitude, latitude, geom, created_at, observed_at, business_type)
SELECT
    'dummy_' || x.g,
    2026 - (c.alo[x.bi] + floor(random() * (c.ahi[x.bi] - c.alo[x.bi] + 1)))::int,   -- 연령 → 출생연도
    CASE WHEN random() < c.mr[x.bi] THEN 'M' ELSE 'F' END,
    x.lng,
    x.lat,
    ST_SetSRID(ST_MakePoint(x.lng, x.lat), 4326),
    now(),            -- 적재 시각
    x.observed_at,    -- 관측 시각(최근 30일 내)
    c.btype[x.bi]
FROM coords x CROSS JOIN cfg c;
