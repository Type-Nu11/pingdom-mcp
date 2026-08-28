-- src/global/config/env.lua
-- 환경 변수를 안전하게 가져오는 config 모듈
-- 우선 `lua-dotenv` 또는 `dotenv` 모듈을 시도해 로드하고,
-- 없으면 `os.getenv`로 폴백합니다.

local M = {}

local dotenv_mod = nil
local ok, mod = pcall(require, "dotenv")
if not ok then
    ok, mod = pcall(require, "lua-dotenv")
end
if ok and type(mod) == "table" then
    dotenv_mod = mod
    if type(mod.load) == "function" then
        pcall(mod.load)
    elseif type(mod.config) == "function" then
        pcall(mod.config)
    end
end

local function getenv(name)
    if dotenv_mod and type(dotenv_mod.get) == "function" then
        local v = dotenv_mod.get(name)
        if v ~= nil and v ~= "" then return v end
    end
    return os.getenv(name)
end

function M.get(key, default)
    if not key or type(key) ~= "string" then
        return default
    end
    local value = getenv(key)
    if value == nil or value == "" then
        return default
    end
    return value
end

function M.load()
    if dotenv_mod and type(dotenv_mod.load) == "function" then
        return dotenv_mod.load()
    elseif dotenv_mod and type(dotenv_mod.config) == "function" then
        return dotenv_mod.config()
    end
    return nil
end

return M
