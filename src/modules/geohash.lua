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

return {
    encode = encode
}


