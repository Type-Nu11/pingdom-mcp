-- src/ai/llmClient.lua
-- AI provider abstraction layer.
-- Today: Gemini (3.1 Flash-Lite) via the OpenAI-compatible HTTP API.
-- Later: swap implementation behind the same interface for a local MCP server.

local gemini = require("src.modules.geminiClient")
local env = require("src.global.config.env")

if type(env.load) == "function" then env.load() end

local DEFAULT_PROVIDER = "gemini"
local DEFAULT_MODEL    = "gemini-3.1-flash-lite"

local LLMClient = {}
LLMClient.__index = LLMClient

function LLMClient.new(provider)
    local self = setmetatable({}, LLMClient)
    self.provider = provider or DEFAULT_PROVIDER
    return self
end

function LLMClient:getProviderName()
    return self.provider
end

function LLMClient:chat(payload)
    if self.provider == "gemini" then
        local api_key = env.get("GEMINI_API_KEY")
        if not api_key or api_key == "" then
            return nil, "LLM_NO_KEY"
        end

        local model = env.get("GEMINI_MODEL", DEFAULT_MODEL)
        local body = payload or {}
        body.model = body.model or model

        return gemini.chat(body, api_key)
    end

    if self.provider == "mcp" then
        return nil, "MCP_PROVIDER_NOT_IMPLEMENTED"
    end

    return nil, "UNKNOWN_LLM_PROVIDER"
end

function LLMClient.createClient(provider)
    return LLMClient.new(provider)
end

return {
    new = LLMClient.new,
    createClient = LLMClient.createClient,
    getProviderName = function()
        return DEFAULT_PROVIDER
    end,
}
