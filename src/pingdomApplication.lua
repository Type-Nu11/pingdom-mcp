local lapis = require("lapis")
local app = lapis.Application()

-- location/controller/locationController.lua
require("src.domain.location.controller.locationController")(app)

-- recommendation/controller/recommendationController.lua
require("src.domain.recommendation.controller.recommendationController")(app)

-- mcp/controller/mcpController.lua
require("src.mcp.controller.mcpController")(app)

return app