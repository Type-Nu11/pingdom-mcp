-- src/mcp/controller/mcpController.lua
local json_params = require("lapis.application").json_params
local MCPServer = require("src.mcp.server")

return function(app)
    app:post("/mcp", json_params(function(self)
        local request = self.params or {}
        local response = MCPServer.handleRequest(request)

        return {
            json = response,
        }
    end))
end
