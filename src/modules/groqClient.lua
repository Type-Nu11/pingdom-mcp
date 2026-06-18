-- src/modules/groqClient.lua
-- Groq Chat Completions (OpenAI 호환) 호출.
-- 블로킹 luasec 사용 (lapis cqueues 서버 루프 오염 방지)
local https = require("ssl.https")
local ltn12 = require("ltn12")
local cjson = require("cjson")

local ENDPOINT = "https://api.groq.com/openai/v1/chat/completions"

local M = {}

-- payload: { model, messages, tools, tool_choice }
-- 성공: decoded(table), 실패: nil, err_key(string)
function M.chat(payload, api_key)
    local reqbody = cjson.encode(payload)
    local resp    = {}

    local ok = https.request({
        url     = ENDPOINT,
        method  = "POST",
        headers = {
            ["content-type"]   = "application/json",
            ["authorization"]  = "Bearer " .. api_key,
            ["content-length"] = tostring(#reqbody),
        },
        source = ltn12.source.string(reqbody),
        sink   = ltn12.sink.table(resp),
    })

    if not ok then
        return nil, "LLM_CONNECT_FAILED"
    end

    -- 4xx/5xx 여도 본문에 error JSON 이 오므로 그대로 디코드 (호출부에서 .error 처리)
    local pok, decoded = pcall(cjson.decode, table.concat(resp))
    if not pok then
        return nil, "LLM_BAD_JSON"
    end

    return decoded
end

return M
