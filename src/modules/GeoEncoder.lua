-- src/modules/GeoEncoder.lua
-- 주소 ↔ 좌표 변환 (Nominatim/OSM). 블로킹 luasec (cqueues 서버 루프 오염 방지)
local https    = require("ssl.https")
local ltn12    = require("ltn12")
local url_util = require("socket.url")
local cjson    = require("cjson")

local M = {}

-- 사용자가 입력하는 시·도 약칭은 Nominatim이 주소로 인식하지 못하는 경우가 있다.
-- 원문을 먼저 조회하고, 실패했을 때만 정식 행정구역명 및 지번을 생략한 후보를 재시도한다.
local REGION_PREFIXES = {
    ["경기 "] = "경기도 ",
    ["강원 "] = "강원특별자치도 ",
    ["충북 "] = "충청북도 ",
    ["충남 "] = "충청남도 ",
    ["전북 "] = "전북특별자치도 ",
    ["전남 "] = "전라남도 ",
    ["경북 "] = "경상북도 ",
    ["경남 "] = "경상남도 ",
    ["서울 "] = "서울특별시 ",
    ["부산 "] = "부산광역시 ",
    ["대구 "] = "대구광역시 ",
    ["인천 "] = "인천광역시 ",
    ["광주 "] = "광주광역시 ",
    ["대전 "] = "대전광역시 ",
    ["울산 "] = "울산광역시 ",
    ["세종 "] = "세종특별자치시 ",
    ["제주 "] = "제주특별자치도 ",
}

local function request_json(url)
    local resp = {}
    local ok = https.request({
        url     = url,
        method  = "GET",
        headers = { ["user-agent"] = "Pingdom/1.0 (contact: dev@ecoblox.build)" }, -- Nominatim 필수
        sink    = ltn12.sink.table(resp),
    })
    if not ok then return nil end
    local pok, data = pcall(cjson.decode, table.concat(resp))
    if not pok then return nil end
    return data
end

-- 번지(지번)까지 붙은 주소는 OSM 에 등록되지 않은 경우가 많다.
-- 원문 → 정식 행정구역명 → 번지 제거 → 마지막 토큰 제거 순으로 단계적으로 넓혀가며 조회한다.
local function strip_lot_number(address)
    local stripped = address
    stripped = stripped:gsub("%s+산%s*%d+[%-%d]*%s*번?지?%s*$", "")   -- "... 산 17", "산17번지"
    stripped = stripped:gsub("%s+%d+[%-%d]*%s*번지%s*$", "")          -- "... 123-4번지"
    stripped = stripped:gsub("%s+%d+%s*%-%s*%d+%s*$", "")             -- "... 123-4"
    stripped = stripped:gsub("%s+%d+%s*$", "")                        -- "... 123"
    return (stripped:gsub("%s+$", ""))
end

local function search_candidates(address)
    local candidates = {}
    local seen = {}

    local function add(value)
        if not value or value == "" then return end
        value = value:gsub("^%s+", ""):gsub("%s+$", "")
        if value == "" or seen[value] then return end
        seen[value] = true
        candidates[#candidates + 1] = value
    end

    add(address)

    local normalized = address
    for abbreviated, full_name in pairs(REGION_PREFIXES) do
        if normalized:sub(1, #abbreviated) == abbreviated then
            normalized = full_name .. normalized:sub(#abbreviated + 1)
            break
        end
    end
    add(normalized)

    -- 번지를 떼어낸 형태(원문/정식명 양쪽)
    add(strip_lot_number(address))
    add(strip_lot_number(normalized))

    -- 그래도 못 찾으면 뒤에서부터 한 토큰씩 줄여 상위 행정구역으로 넓힌다.
    local base = strip_lot_number(normalized)
    for _ = 1, 2 do
        local shorter = base:gsub("%s+%S+$", "")
        if shorter == base or shorter == "" then break end
        base = shorter
        add(base)
    end

    return candidates
end

-- countrycodes=kr 로 걸러도 해외 지명은 그 이름을 쓰는 국내 상호(예: "Paris" → 부산의 카페,
-- "Tokyo" → 서울의 식당)로 매칭된다. 행정구역/장소/도로 계열만 지역으로 인정해 걸러낸다.
local PLACE_CLASSES = {
    boundary = true,   -- 행정경계 (구/동)
    place    = true,   -- 동/리/가/house
    highway  = true,   -- 도로명 주소
    building = true,
    landuse  = true,
}

-- 대한민국 영역(위경도 범위). countrycodes 필터를 통과해도 좌표로 한 번 더 검증한다.
local KR_BOUNDS = { lng_min = 124.0, lng_max = 132.5, lat_min = 32.5, lat_max = 39.0 }

local function inside_korea(lng, lat)
    if not (lng and lat) then return false end
    return lng >= KR_BOUNDS.lng_min and lng <= KR_BOUNDS.lng_max
       and lat >= KR_BOUNDS.lat_min and lat <= KR_BOUNDS.lat_max
end

M.inside_korea = inside_korea

-- 주소 → (lng, lat). 대한민국 주소만 인정한다.
function M.geocode(address)
    -- 호출부에서 숫자/테이블이 흘러들어와도 문자열 메서드에서 터지지 않게 막는다.
    if type(address) ~= "string" or address == "" then return nil end
    for _, candidate in ipairs(search_candidates(address)) do
        local data = request_json(
            "https://nominatim.openstreetmap.org/search?format=json&limit=1&countrycodes=kr&accept-language=ko&q="
            .. url_util.escape(candidate))
        local hit = data and data[1]
        if hit and PLACE_CLASSES[hit.class] then
            local lng, lat = tonumber(hit.lon), tonumber(hit.lat)
            if inside_korea(lng, lat) then
                return lng, lat
            end
        end
    end
    return nil
end

-- (lat, lng) → 한국어 주소 문자열
function M.reverse(lat, lng)
    lat, lng = tonumber(lat), tonumber(lng)
    if not lat or not lng then return nil end
    local data = request_json(string.format(
        "https://nominatim.openstreetmap.org/reverse?format=json&accept-language=ko&lat=%s&lon=%s",
        tostring(lat), tostring(lng)))
    if not data or not data.display_name then return nil end
    return data.display_name
end

return M
