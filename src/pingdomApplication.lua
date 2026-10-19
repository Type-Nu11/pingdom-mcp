local lapis = require("lapis")
local app = lapis.Application()

-- 외부 로드밸런서와 배포 스크립트가 애플리케이션 생존 여부를 확인하는 경량 엔드포인트.
app:get("/health", function()
    return {
        status = 200,
        json = { status = "ok" },
    }
end)

-- location/controller/locationController.lua
require("src.domain.location.controller.locationController")(app)

-- recommendation/controller/recommendationController.lua
require("src.domain.recommendation.controller.recommendationController")(app)

-- mcp/controller/mcpController.lua
require("src.mcp.controller.mcpController")(app)

return app
