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

local function search_candidates(address)
    local candidates = { address }
    local normalized = address

    for abbreviated, full_name in pairs(REGION_PREFIXES) do
        if normalized:sub(1, #abbreviated) == abbreviated then
            normalized = full_name .. normalized:sub(#abbreviated + 1)
            break
        end
    end

    if normalized ~= address then
        candidates[#candidates + 1] = normalized
    end

    -- 예: "검복리 산 17"은 지번까지 등록되지 않은 경우가 있어, 리 단위 후보도 조회한다.
    local without_lot = normalized:gsub("%s+산%s+%d+.*$", "")
    if without_lot ~= normalized then
        candidates[#candidates + 1] = without_lot
    end

    return candidates
end

-- 주소 → (lng, lat)
function M.geocode(address)
    if not address or address == "" then return nil end
    for _, candidate in ipairs(search_candidates(address)) do
        local data = request_json(
            "https://nominatim.openstreetmap.org/search?format=json&limit=1&accept-language=ko&q="
            .. url_util.escape(candidate))
        if data and data[1] then
            return tonumber(data[1].lon), tonumber(data[1].lat)
        end
    end
    return nil
end

-- (lat, lng) → 한국어 주소 문자열
function M.reverse(lat, lng)
    if not lat or not lng then return nil end
    local data = request_json(string.format(
        "https://nominatim.openstreetmap.org/reverse?format=json&accept-language=ko&lat=%s&lon=%s",
        tostring(lat), tostring(lng)))
    if not data or not data.display_name then return nil end
    return data.display_name
end

return M
