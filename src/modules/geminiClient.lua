-- src/modules/geminiClient.lua
-- Gemini Chat Completions (OpenAI 호환 엔드포인트) 호출.
-- 요청/응답 스키마가 OpenAI 와 동일하므로 상위 계층(choices[1].message.tool_calls)은 그대로 사용.
-- 블로킹 luasec 사용 (lapis cqueues 서버 루프 오염 방지)
local https = require("ssl.https")
local ltn12 = require("ltn12")
local cjson = require("cjson")

local ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"

local M = {}

M.ENDPOINT = ENDPOINT

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

    -- 이 엔드포인트의 에러 본문은 [{"error":{...}}] 처럼 배열로 감싸여 온다.
    -- 호출부가 resp.error 로 판별할 수 있게 벗겨서 넘긴다.
    if type(decoded) == "table" and decoded.error == nil
        and type(decoded[1]) == "table" and decoded[1].error then
        return decoded[1]
    end

    return decoded
end

return M
