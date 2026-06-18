-- src/domain/location/controller/locationController.lua
local wrapService = require("src.domain.location.service.locationService")
local ERROR_MAP = require("src.global.exceptions.errorMap")
local json_params = require("lapis.application").json_params

local function fail(err)
    local e = ERROR_MAP[err] or ERROR_MAP.INTERNAL_SERVER_ERROR
    return { status = e.status, json = { message = e.message } }
end

return function(app)
    -- 저장 (JSON body → json_params로 파싱)
    app:post("/location/wrap", json_params(function(self)
        local result, err = wrapService.wrap(self.params)
        if err then
            return fail(err)
        end
        return { json = { id = result[1] and result[1].id } }
    end))

    -- 조회 (쿼리스트링도 self.params로 들어옴)
    app:get("/location/search", function(self)
        local result, err = wrapService.search(self.params)
        if err then
            return fail(err)
        end
        return { json = { data = result } }
    end)
end