local http = require("lapis.nginx.http")
local cjson = require("cjson")

local function geocode(address)
    local res = http.simple({
        url = "https://nominatim.openstreetmap.org/search",
        method = "GET",
        headers = { ["User-Agent"] = "{Pingdom/1.0}" },
    })
    local data = cjson.decode(res)
    if data[1] then
        return tonumber(data[1].lon), tonumber(data[1].lat)
    end
    return nil
end

return geocode