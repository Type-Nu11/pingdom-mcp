-- src/modules/GeoEncoder.lua
-- 주소 ↔ 좌표 변환 (Nominatim/OSM). 블로킹 luasec (cqueues 서버 루프 오염 방지)
local https    = require("ssl.https")
local ltn12    = require("ltn12")
local url_util = require("socket.url")
local cjson    = require("cjson")

local M = {}

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

-- 주소 → (lng, lat)
function M.geocode(address)
    if not address or address == "" then return nil end
    local data = request_json(
        "https://nominatim.openstreetmap.org/search?format=json&limit=1&accept-language=ko&q="
        .. url_util.escape(address))
    if not data or not data[1] then return nil end
    return tonumber(data[1].lon), tonumber(data[1].lat)
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
