-- src/mcp/server.lua
-- Minimal MCP-style JSON-RPC server wrapper for tool exposure.
-- This keeps the project compatible with Lapis while exposing an AI-tool contract.

local cjson = require("cjson")
local recommendationTool = require("src.domain.recommendation.tool.recommendationTool")
local recommendationService = require("src.domain.recommendation.service.recommendationService")

local MCPServer = {}

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

function MCPServer.handleRequest(request)
    if not request then
        return {
            jsonrpc = "2.0",
            error = {
                code = -32600,
                message = "Invalid Request",
            },
        }
    end

    local method = request.method
    local id = request.id

    if method == "initialize" then
        return {
            jsonrpc = "2.0",
            id = id,
            result = {
                protocolVersion = "2024-11-05",
                capabilities = {
                    tools = {
                        listChanged = true,
                    },
                },
                serverInfo = {
                    name = "pingdom-mcp-server",
                    version = "0.1.0",
                },
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
        local tool_name = params.name
        local tool_args = params.arguments or {}

        return {
            jsonrpc = "2.0",
            id = id,
            result = MCPServer.callTool(tool_name, tool_args),
        }
    end

    if method == "ping" then
        return {
            jsonrpc = "2.0",
            id = id,
            result = {},
        }
    end

    return {
        jsonrpc = "2.0",
        id = id,
        error = {
            code = -32601,
            message = "Method not found: " .. tostring(method),
        },
    }
end

function MCPServer.serveStdio()
    while true do
        local line = io.stdin:read("*l")
        if not line or line == "" then
            if not line then
                break
            end
            goto continue
        end

        local ok, request = pcall(cjson.decode, line)
        if ok and request then
            local response = MCPServer.handleRequest(request)
            io.stdout:write(cjson.encode(response) .. "\n")
            io.stdout:flush()
        end

        ::continue::
    end
end

return MCPServer
