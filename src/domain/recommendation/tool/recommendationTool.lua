-- src/domain/recommendation/tool/recommendationTool.lua
-- MCP/LLM tool contract for location recommendation domain.

local M = {}

M.SYSTEM_PROMPT = [[
너는 상권 입지 분석 챗봇이다. 직원의 질문에서 조건을 파악해 recommend_location 툴을
반드시 1회 호출하라. (설명 문장 출력 금지, 툴 호출만)

조건 파악:
- 지역(region): 질문에 나온 지역명을 그대로.
- 연령(age_min/age_max): 질문에 나이대가 있으면 그대로 사용. 없고 업종만 있으면 그 업종의
  핵심 고객 나이대를 추론. (age_min ≤ age_max, 정수)
- 성별(gender): 질문에 있으면 'M'/'F', 없으면 'ANY'.
- radius_m 기본 1500.
]]

M.TOOL = {
    type = "function",
    ["function"] = {
        name = "recommend_location",
        description = "업종 타깃 인구통계로 지역 내 입지를 조회한다",
        parameters = {
            type = "object",
            properties = {
                region   = { type = "string",  description = "예: '대구 북구'" },
                radius_m = { type = "integer", description = "검색 반경(m), 기본 1500" },
                age_min  = { type = "integer", description = "타깃 최소 나이 (예: 20)" },
                age_max  = { type = "integer", description = "타깃 최대 나이 (예: 45)" },
                gender   = { type = "string",  enum = { "M", "F", "ANY" } },
            },
            required = { "region", "age_min", "age_max", "gender" },
        },
    },
}

-- OpenAI/Gemini 호환 함수 스키마 (LLM 호출용)
function M.getTools()
    return { M.TOOL }
end

-- MCP tools/list 스키마 (name/description/inputSchema)
function M.getMcpTools()
    local fn = M.TOOL["function"]
    return {
        {
            name        = fn.name,
            description = fn.description,
            inputSchema = fn.parameters,
        },
    }
end

function M.buildUserMessage(input)
    local business = input.business or input["업종"]
    local region   = input.region   or input["지역"]
    local message  = input.message  or input["질문"]

    if message then
        return message
    end

    return ("업종: %s\n지역: %s"):format(business or "", region or "")
end

function M.parseToolCall(message)
    if not message then
        return nil
    end

    if message.tool_calls and message.tool_calls[1] then
        return message.tool_calls[1]
    end

    if type(message.content) == "string" then
        local name, args = message.content:match("<function=([%w_]+)>%s*(%b{})")
        if name then
            return { ["function"] = { name = name, arguments = args } }
        end
    end

    return nil
end

return M
