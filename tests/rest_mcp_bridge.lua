-- tests/rest_mcp_bridge.lua
-- REST 요청 → MCP tools/call 래핑 → MCP tool result 반환 경로 검증.
-- 컨트롤러가 만드는 MCP 메시지가 tool 에 그대로 도달하는지를 본다. (DB/LLM 없이 스텁)
--   lua tests/rest_mcp_bridge.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local received   -- tool 에 실제로 도달한 입력
package.loaded["src.domain.recommendation.service.recommendationService"] = {
    recommend = function(input)
        received = input
        if not (input.region or input.message or input.business) then
            return nil, "INVALID_INPUT"
        end
        return {
            answer = "stub answer",
            target = { region = input.region, gender = input.gender or "ANY" },
            center = { lat = 0, lng = 0 },
            searched_radius_m = input.radius_m or 1500,
            recommendations = {},
        }
    end,
}

local cjson     = require("cjson")
local MCPServer = require("src.mcp.server")

local function check(name, ok)
    if not ok then error("FAIL: " .. name, 2) end
    print("ok - " .. name)
end

-- 컨트롤러와 동일한 래핑을 재현한다.
local function rest_call(body)
    local response = MCPServer.handleRequest({
        jsonrpc = "2.0", id = 1, method = "tools/call",
        params = {
            name = "recommend_location",
            arguments = {
                region   = body.region   or body["지역"],
                business = body.business or body["업종"],
                message  = body.message  or body["질문"],
                age_min  = body.age_min,
                age_max  = body.age_max,
                gender   = body.gender,
                radius_m = body.radius_m,
            },
        },
    })
    return response
end

-- 정상 요청
local ok_resp = rest_call({ business = "카페", region = "대구 중구" })
check("JSON-RPC error 가 아니다", ok_resp.error == nil)
local result = ok_resp.result
check("MCP tool result 형태로 반환된다", result.content[1].type == "text")
check("성공 시 isError=false", result.isError == false)

local payload = cjson.decode(result.content[1].text)
check("tool result 안에 answer 가 있다", payload.answer == "stub answer")
check("tool result 안에 recommendations 가 있다", payload.recommendations ~= nil)

-- REST 본문의 인자가 tool 까지 그대로 전달되는지
rest_call({ region = "대구 수성구", age_min = 20, age_max = 39, gender = "F", radius_m = 2000 })
check("region 전달", received.region == "대구 수성구")
check("age_min/age_max 전달", received.age_min == 20 and received.age_max == 39)
check("gender 전달", received.gender == "F")
check("radius_m 전달", received.radius_m == 2000)

-- 한국어 키
rest_call({ ["업종"] = "헬스장", ["지역"] = "대구 북구" })
check("한국어 키(업종/지역) 전달", received.business == "헬스장" and received.region == "대구 북구")
rest_call({ ["질문"] = "20대 여성이 많은 곳" })
check("한국어 키(질문) 전달", received.message == "20대 여성이 많은 곳")

-- 실패는 HTTP 에러가 아니라 isError 로
local failed = rest_call({}).result
check("입력 부족은 isError 로 표현된다", failed.isError == true)
check("에러 사유가 본문에 실린다", failed.content[1].text:find("INVALID_INPUT") ~= nil)

print("\nREST→MCP bridge OK")
