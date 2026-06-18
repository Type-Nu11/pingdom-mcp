local BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz"

local function encode(lat, lng, precision)
    local precision = precision or 9 -- 지오해시 문자열의 길이, 기본값은 9 (약 4.7m x 4.7m)
    local min_lat, max_lat = -90, 90
    local min_lng, max_lng = -180, 180 -- 경도는 -180 ~ 180, 위도는 -90 ~ 90
    local hash = "" -- 지오해시 문자열
    local bit = 0 -- 5개 비트 중 몇번쨰인지(인덱스)
    local ch = 0 -- 비트 묶음
    local even = true -- 짝수 비트인지 홀수 비트인지 / 짝수면 경도, 홀수면 위도 경도 비트 하나 검사하고 다음은 위도 비트 검사함

    -- 검증 단계 길이만큼 반복
    while #hash < precision do
        if even then
            local mid = (min_lng + max_lng) / 2 -- 경도의 중간값 계산
            if lng >= mid then
                -- 경도가 중간값보다 크거나 같으면 1 비트 추가
                -- 그 이후로 경도의 최소값을 중간값으로 업데이트
                ch = ch * 2 + 1
                min_lng = mid
            else
                -- 경도가 중간값보다 작으면 0 비트 추가
                ch = ch * 2
                max_lng = mid
            end
        else
            local mid = (min_lat + max_lat) / 2
            if lat > mid then
                ch = ch * 2 + 1
                min_lat = mid
            else
                ch = ch * 2
                max_lat = mid
            end
        end

        even = not even -- 짝수/홀수 비트 토글
        bit = bit + 1 -- 비트 인덱스값 더함
        if bit == 5 then -- 인덱스 5를 만났을 때, BASE32에서 해당 인덱스에 해당하는 문자 추가
            hash = hash .. BASE32:sub(ch + 1, ch + 1)
            -- 초기화
            ch = 0
            bit = 0
        end
    end
    return hash
end

local M = {
    encode = encode,
    -- precision 단일 관리처: 셀 크기 결정 (6≈1.2km, 7≈150m). city-wide 데이터엔 6 권장.
    DEFAULT_PRECISION = 7,
}

-- 반경 내 포인트들을 geohash 셀로 묶어 인구통계 집계
-- rows: { {lng, lat, birth_year, gender, hour}, ... }
-- opts: { precision?, by_min, by_max, gender('M'|'F'|'ANY') }
-- 반환: { {cell, total_foot, age_match, gender_match, avg_hour, lat, lng}, ... }
function M.aggregate(rows, opts)
    opts = opts or {}
    local p = opts.precision or M.DEFAULT_PRECISION
    local by_min, by_max, gender = opts.by_min, opts.by_max, opts.gender

    local cells = {}
    for _, r in ipairs(rows) do
        local lat = tonumber(r.lat)
        local lng = tonumber(r.lng)
        if lat and lng then
            local key = encode(lat, lng, p)
            local c = cells[key]
            if not c then
                c = { cell = key, total_foot = 0, age_match = 0, gender_match = 0,
                      hour_sum = 0, lat_sum = 0, lng_sum = 0 }
                cells[key] = c
            end
            c.total_foot = c.total_foot + 1

            local by = tonumber(r.birth_year)
            if by_min and by_max and by and by >= by_min and by <= by_max then
                c.age_match = c.age_match + 1
            end
            if (not gender) or gender == "ANY" or r.gender == gender then
                c.gender_match = c.gender_match + 1
            end

            c.hour_sum = c.hour_sum + (tonumber(r.hour) or 0)
            c.lat_sum  = c.lat_sum + lat
            c.lng_sum  = c.lng_sum + lng
        end
    end

    local out = {}
    for _, c in pairs(cells) do
        out[#out + 1] = {
            cell         = c.cell,
            total_foot   = c.total_foot,
            age_match    = c.age_match,
            gender_match = c.gender_match,
            avg_hour     = math.floor(c.hour_sum / c.total_foot * 10 + 0.5) / 10,
            lat          = c.lat_sum / c.total_foot,   -- 셀 내 실제 포인트 중심(centroid)
            lng          = c.lng_sum / c.total_foot,
        }
    end
    return out
end

return M
