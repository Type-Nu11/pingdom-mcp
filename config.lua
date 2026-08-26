-- config.lua
-- Lapis application configuration
local config = require("lapis.config")

local function getenv(name, default)
  local value = os.getenv(name)
  if value == nil or value == "" then
    return default
  end
  return value
end

local function tonumber_or(value, default)
  local n = tonumber(value)
  return n ~= nil and n or default
end

local default_port = tonumber_or(getenv("PORT"), 8080)

config("development", {
  postgres = {
    host     = getenv("DB_HOST", "127.0.0.1"),
    port     = tonumber_or(getenv("DB_PORT"), 5432),
    user     = getenv("DB_USER", "postgres"),
    password = getenv("DB_PASSWORD", ""),
    database = getenv("DB_NAME", "pingdom_dev"),
  },
  server         = "cqueues",   -- OpenResty 없이 구동
  port           = default_port,
  secret         = getenv("SESSION_SECRET", "changeme"),
  code_cache     = false,
  reload_modules = true,
})

config("production", {
  postgres = {
    host     = getenv("DB_HOST", "127.0.0.1"),
    port     = tonumber_or(getenv("DB_PORT"), 5432),
    user     = getenv("DB_USER", "postgres"),
    password = getenv("DB_PASSWORD", ""),
    database = getenv("DB_NAME", "pingdom_prod"),
  },
  server         = "cqueues",
  port           = default_port,
  secret         = getenv("SESSION_SECRET"),
  code_cache     = true,
  reload_modules = false,
})
