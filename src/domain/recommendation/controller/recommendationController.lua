-- src/domain/recommendation/controller/recommendationController.lua
-- AI 가 부르는 REST 입구. 받은 요청을 MCP tools/call 메시지로 감싸 MCP 계층에 넘기고,
-- 돌아온 MCP tool result 를 그대로 응답한다. (전송 계층을 거치지 않고 같은 프로세스에서 직접 호출)
local json_params = require("lapis.application").json_params
local MCPServer   = require("src.mcp.server")

local TOOL_NAME = "recommend_location"

-- REST 본문 → MCP tool arguments. 한국어 키도 받아준다.
local function to_arguments(params)
    params = params or {}
    return {
        region   = params.region   or params["지역"],
        business = params.business or params["업종"],
        message  = params.message  or params["질문"],
        age_min  = params.age_min,
        age_max  = params.age_max,
        gender   = params.gender,
        radius_m = params.radius_m,
    }
end

return function(app)
    -- 입지 추천: { "business": "헬스장", "region": "서울 마포구" }
    -- 응답: MCP tool result → { content = { { type = "text", text = "<json>" } }, isError = ... }
    app:post("/recommend", json_params(function(self)
        local response = MCPServer.handleRequest({
            jsonrpc = "2.0",
            id      = 1,
            method  = "tools/call",
            params  = {
                name      = TOOL_NAME,
                arguments = to_arguments(self.params),
            },
        })

        -- tool 실행 실패는 result.isError 로 전달되므로 200 이다.
        -- 여기 걸리는 것은 MCP 계층 자체의 오류(JSON-RPC error)뿐이다.
        if response.error then
            return { status = 500, json = response.error }
        end

        return { json = response.result }
    end))
end
