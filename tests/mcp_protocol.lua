-- tests/mcp_protocol.lua
-- MCP 메시지 계층 검증. DB/LLM 없이 돌도록 서비스는 스텁으로 갈아끼운다.
--   lua tests/mcp_protocol.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

package.loaded["src.domain.recommendation.service.recommendationService"] = {
    recommend = function(input)
        if not input.region then
            return nil, "INVALID_INPUT"
        end
        return {
            answer = "stub",
            target = { region = input.region, gender = input.gender or "ANY" },
            center = { lat = 0, lng = 0 },
            searched_radius_m = input.radius_m or 1500,
            recommendations = {},
        }
    end,
}

local cjson  = require("cjson")
local server = require("src.mcp.server")

local function check(name, ok)
    if not ok then
        error("FAIL: " .. name, 2)
    end
    print("ok - " .. name)
end

-- initialize: 클라이언트가 아는 버전이면 그대로 되돌려준다
local init = server.handleRequest({
    jsonrpc = "2.0", id = 1, method = "initialize",
    params = { protocolVersion = "2025-03-26" },
})
check("initialize 는 요청한 버전으로 협상한다", init.result.protocolVersion == "2025-03-26")
check("initialize 는 serverInfo 를 담는다", init.result.serverInfo.name == "pingdom-mcp-server")

-- 모르는 버전이면 서버의 최신 버전으로 응답
local init2 = server.handleRequest({
    jsonrpc = "2.0", id = 2, method = "initialize",
    params = { protocolVersion = "1999-01-01" },
})
check("모르는 버전은 최신 버전으로 대체된다", init2.result.protocolVersion == server.LATEST_PROTOCOL_VERSION)

-- 알림에는 회신하지 않는다
check("notifications/initialized 에 회신하지 않는다",
    server.handleRequest({ jsonrpc = "2.0", method = "notifications/initialized" }) == nil)
check("notifications/cancelled 에 회신하지 않는다",
    server.handleRequest({ jsonrpc = "2.0", method = "notifications/cancelled", params = {} }) == nil)
check("클라이언트가 보낸 응답에 회신하지 않는다",
    server.handleRequest({ jsonrpc = "2.0", id = 7, result = {} }) == nil)

-- tools/list 는 MCP 스키마
local tools = server.handleRequest({ jsonrpc = "2.0", id = 3, method = "tools/list" }).result.tools
check("tools/list 는 name/inputSchema 형식", tools[1].name == "recommend_location" and tools[1].inputSchema ~= nil)

-- tools/call
local call = server.handleRequest({
    jsonrpc = "2.0", id = 4, method = "tools/call",
    params = { name = "recommend_location", arguments = { region = "대구 중구", gender = "F" } },
})
check("tools/call 은 content 를 돌려준다", call.result.content[1].type == "text")
check("tools/call 은 인자를 그대로 전달한다",
    cjson.decode(call.result.content[1].text).target.gender == "F")
check("tools/call 성공 시 isError=false", call.result.isError == false)

-- tool 에러는 JSON-RPC 에러가 아니라 isError 결과로 (MCP 규약)
local failed = server.handleRequest({
    jsonrpc = "2.0", id = 5, method = "tools/call",
    params = { name = "recommend_location", arguments = {} },
})
check("tool 실패는 isError 로 표현된다", failed.result.isError == true and failed.error == nil)

local unknown_tool = server.handleRequest({
    jsonrpc = "2.0", id = 6, method = "tools/call",
    params = { name = "nope", arguments = {} },
})
check("없는 tool 은 isError", unknown_tool.result.isError == true)

-- ping / 없는 메서드
local ping = server.handleRequest({ jsonrpc = "2.0", id = 8, method = "ping" })
check("ping 은 빈 객체를 돌려준다", cjson.encode(ping.result) == "{}")
check("없는 메서드는 -32601",
    server.handleRequest({ jsonrpc = "2.0", id = 9, method = "nope" }).error.code == -32601)

-- 배치: 알림만 있으면 회신 없음, 섞여 있으면 요청 것만
check("알림만 담긴 배치는 회신 없음",
    server.handleMessage({ { jsonrpc = "2.0", method = "notifications/initialized" } }) == nil)
local batch = server.handleMessage({
    { jsonrpc = "2.0", method = "notifications/initialized" },
    { jsonrpc = "2.0", id = 10, method = "ping" },
})
check("배치는 요청에 대해서만 회신한다", #batch == 1 and batch[1].id == 10)

print("\nMCP protocol OK")
