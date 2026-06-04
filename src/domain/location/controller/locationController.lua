local wrapService = require("src.domain.location.service.locationService")
local ERROR_MAP = require("src.global.exceptions.errorMap")

local function savegis()

end
local function wrap()
    
end

return function(app)
    app:post("/location/wrap", function(req, res)
        local result, err = wrapService.wrap(req.body)

        if err then
            return res:status(500).json({ error = ERROR_MAP[err] or "INTERNAL_SERVER_ERROR" })
        end

        res:json(result)
    end),
    
end