-- src/mcp/controller/mcpController.lua
-- MCP Streamable HTTP 전송 계층. (Spring AI MCP Client 가 붙는 엔드포인트)
--   POST   /mcp  JSON-RPC 메시지. 요청이면 200 + JSON, 알림/응답이면 202 Accepted(본문 없음).
--   GET    /mcp  서버 주도 SSE 스트림 — 제공하지 않으므로 405.
--   DELETE /mcp  세션 종료.
local lapis_app  = require("lapis.application")
local json_params = lapis_app.json_params
local respond_to  = lapis_app.respond_to
local MCPServer   = require("src.mcp.server")
local sessionStore = require("src.mcp.sessionStore")
local env          = require("src.global.config.env")

local SESSION_HEADER  = "mcp-session-id"
local PROTOCOL_HEADER = "mcp-protocol-version"

-- 세션 헤더가 없는 구(2025-03-26) 클라이언트를 위한 기본값
local DEFAULT_PROTOCOL_VERSION = "2025-03-26"

-- MCP_AUTH_TOKEN 이 설정돼 있으면 Authorization: Bearer <token> 을 요구한다.
-- Gemini Remote MCP 는 tools[].headers 로 이 값을 실어 보낸다.
-- 공개 URL 로 노출되는 순간 무인증이면 누구나 DB/LLM 을 호출할 수 있으므로 운영에서는 필수.
local function authorized(self)
    local expected = env.get("MCP_AUTH_TOKEN")
    if not expected or expected == "" then
        return true   -- 미설정 = 로컬 개발
    end
    local header = self.req.headers["authorization"]
    return header == "Bearer " .. expected
end

local function jsonrpc_error(status, code, message, id)
    return {
        status = status,
        json = {
            jsonrpc = "2.0",
            id = id,
            error = { code = code, message = message },
        },
    }
end

-- 본문이 initialize 요청을 담고 있는지. (배치로 올 수도 있다)
local function contains_initialize(body)
    if body[1] ~= nil then
        for _, message in ipairs(body) do
            if type(message) == "table" and message.method == "initialize" then
                return true
            end
        end
        return false
    end
    return body.method == "initialize"
end

local function handle_post(self)
    if not authorized(self) then
        return jsonrpc_error(401, -32001, "Unauthorized")
    end

    local body = self.params or {}

    -- json_params 는 파싱에 실패하면 빈 테이블을 남긴다.
    if next(body) == nil then
        return jsonrpc_error(400, -32700, "Parse error")
    end

    local now = os.time()
    sessionStore.prune(now)

    local issued_session_id

    if contains_initialize(body) then
        -- 새 세션 발급. 클라이언트는 이후 요청에 이 값을 실어 보내야 한다.
        issued_session_id = sessionStore.create(now)
    else
        -- 세션은 스펙상 선택 사항이다. 헤더를 보내오면 검증하고, 없으면 무상태로 처리한다.
        -- (Gemini Remote MCP 처럼 세션을 되돌려주지 않는 클라이언트도 붙을 수 있게)
        local session_id = self.req.headers[SESSION_HEADER]
        if session_id then
            -- 404 를 받으면 클라이언트는 새 세션으로 다시 initialize 한다.
            local session = sessionStore.touch(session_id, now)
            if not session then
                return jsonrpc_error(404, -32001, "Session not found")
            end
            session.protocol_version = self.req.headers[PROTOCOL_HEADER]
        end

        -- 2025-06-18 부터 클라이언트가 협상된 버전을 헤더로 실어 보낸다.
        local version = self.req.headers[PROTOCOL_HEADER]
        if version and not MCPServer.SUPPORTED_PROTOCOL_VERSIONS[version] then
            return jsonrpc_error(400, -32600, "Unsupported MCP-Protocol-Version: " .. tostring(version))
        end
    end

    local response = MCPServer.handleMessage(body)
    local headers = issued_session_id and { ["Mcp-Session-Id"] = issued_session_id } or nil

    -- 알림/응답만 들어온 경우 회신할 것이 없다.
    if response == nil then
        return { status = 202, layout = false, headers = headers }
    end

    return { json = response, headers = headers }
end

-- 서버가 먼저 말을 걸 일이 없으므로 SSE 스트림은 열지 않는다.
local function handle_get()
    return {
        status = 405,
        layout = false,
        headers = { ["Allow"] = "POST, DELETE" },
    }
end

local function handle_delete(self)
    if not authorized(self) then
        return jsonrpc_error(401, -32001, "Unauthorized")
    end

    local session_id = self.req.headers[SESSION_HEADER]
    if not session_id then
        return jsonrpc_error(400, -32600, "Missing Mcp-Session-Id header")
    end
    if not sessionStore.destroy(session_id) then
        return jsonrpc_error(404, -32001, "Session not found")
    end
    return { status = 204, layout = false }
end

return function(app)
    app:match("/mcp", respond_to({
        POST   = json_params(handle_post),
        GET    = handle_get,
        DELETE = handle_delete,
    }))
end
