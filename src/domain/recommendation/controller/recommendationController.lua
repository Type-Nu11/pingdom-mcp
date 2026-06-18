-- src/domain/recommendation/controller/recommendationController.lua
local service     = require("src.domain.recommendation.service.recommendationService")
local ERROR_MAP   = require("src.global.exceptions.errorMap")
local json_params = require("lapis.application").json_params

local function fail(err)
    local base = err:match("^([^:]+)") or err   -- "OPENAI_ERROR:..." → "OPENAI_ERROR"
    local e = ERROR_MAP[base] or ERROR_MAP.INTERNAL_SERVER_ERROR
    return { status = e.status, json = { message = e.message } }
end

return function(app)
    -- 입지 추천: { "business": "헬스장", "region": "서울 마포구" }
    app:post("/recommend", json_params(function(self)
        local result, err = service.recommend(self.params)
        if err then
            return fail(err)
        end
        return { json = result }
    end))
end
