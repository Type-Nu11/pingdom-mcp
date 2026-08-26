-- src/mcp/server.lua
-- MCP(JSON-RPC 2.0) 메시지 처리기. 전송 계층(Streamable HTTP)은 mcpController 가 담당하고,
-- 여기서는 순수하게 "메시지 → 응답" 변환만 한다.

local cjson = require("cjson")
local recommendationTool = require("src.domain.recommendation.tool.recommendationTool")
local recommendationService = require("src.domain.recommendation.service.recommendationService")

local MCPServer = {}

-- 클라이언트가 요청한 버전이 이 목록에 있으면 그대로, 없으면 LATEST 로 응답한다.
MCPServer.LATEST_PROTOCOL_VERSION = "2025-06-18"
MCPServer.SUPPORTED_PROTOCOL_VERSIONS = {
    ["2025-06-18"] = true,
    ["2025-03-26"] = true,
    ["2024-11-05"] = true,
}

MCPServer.SERVER_INFO = {
    name    = "pingdom-mcp-server",
    version = "0.1.0",
}

function MCPServer.listTools()
    return recommendationTool.getMcpTools()
end

function MCPServer.callTool(name, args)
    if name == "recommend_location" then
        local payload = args or {}
        local result, err = recommendationService.recommend({
            region = payload.region,
            age_min = payload.age_min,
            age_max = payload.age_max,
            gender = payload.gender,
            radius_m = payload.radius_m,
            business = payload.business,
            message = payload.message,
        })

        if err then
            return {
                content = {
                    {
                        type = "text",
                        text = "Tool error: " .. tostring(err),
                    },
                },
                isError = true,
            }
        end

        return {
            content = {
                {
                    type = "text",
                    text = cjson.encode({
                        answer = result.answer,
                        target = result.target,
                        center = result.center,
                        searched_radius_m = result.searched_radius_m,
                        recommendations = result.recommendations,
                    }),
                },
            },
            isError = false,   -- 생략해도 false 로 간주되지만, 소비하는 쪽이 분기하기 쉽게 명시한다
        }
    end

    return {
        content = {
            {
                type = "text",
                text = "Unknown tool: " .. tostring(name),
            },
        },
        isError = true,
    }
end

local function error_response(id, code, message)
    return {
        jsonrpc = "2.0",
        id = id,
        error = {
            code = code,
            message = message,
        },
    }
end

-- 알림(notification)과 클라이언트가 보낸 응답에는 절대 회신하지 않는다 (JSON-RPC 2.0).
-- 회신하면 엄격한 MCP 클라이언트는 프로토콜 위반으로 보고 연결을 끊는다.
local function is_notification(request)
    if type(request.method) ~= "string" then
        return true   -- method 없음 = 클라이언트가 보낸 응답
    end
    return request.id == nil
end

-- 단일 JSON-RPC 메시지 처리. 회신할 필요가 없으면 nil 을 반환한다.
function MCPServer.handleRequest(request)
    if type(request) ~= "table" then
        return error_response(nil, -32600, "Invalid Request")
    end

    if is_notification(request) then
        return nil
    end

    local method = request.method
    local id = request.id

    if method == "initialize" then
        local params = request.params or {}
        local requested = params.protocolVersion
        local negotiated = (type(requested) == "string" and MCPServer.SUPPORTED_PROTOCOL_VERSIONS[requested])
            and requested
            or MCPServer.LATEST_PROTOCOL_VERSION

        return {
            jsonrpc = "2.0",
            id = id,
            result = {
                protocolVersion = negotiated,
                capabilities = {
                    tools = {
                        listChanged = false,   -- 툴 목록 변경 알림을 보내지 않는다
                    },
                },
                serverInfo = MCPServer.SERVER_INFO,
            },
        }
    end

    if method == "tools/list" then
        return {
            jsonrpc = "2.0",
            id = id,
            result = {
                tools = MCPServer.listTools(),
            },
        }
    end

    if method == "tools/call" then
        local params = request.params or {}
        return {
            jsonrpc = "2.0",
            id = id,
            result = MCPServer.callTool(params.name, params.arguments or {}),
        }
    end

    if method == "ping" then
        return {
            jsonrpc = "2.0",
            id = id,
            result = {},   -- 빈 객체로 직렬화된다
        }
    end

    return error_response(id, -32601, "Method not found: " .. tostring(method))
end

-- 요청 본문 전체 처리. 배열(JSON-RPC 배치)도 받아준다.
-- 반환: 회신할 메시지(테이블) 또는 nil(= 202 Accepted, 본문 없음)
function MCPServer.handleMessage(body)
    if type(body) ~= "table" then
        return error_response(nil, -32600, "Invalid Request")
    end

    -- 배치: 2025-03-26 스펙에만 있고 2025-06-18 에서 빠졌지만, 받아두면 손해는 없다.
    if body[1] ~= nil then
        local responses = {}
        for _, message in ipairs(body) do
            local response = MCPServer.handleRequest(message)
            if response then
                responses[#responses + 1] = response
            end
        end
        if #responses == 0 then
            return nil
        end
        return responses
    end

    return MCPServer.handleRequest(body)
end

return MCPServer
