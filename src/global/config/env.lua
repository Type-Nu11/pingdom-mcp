local Environment = {}

local loaded = false

function Environment.load()
    if loaded then
        return
    end
    loaded = true

    local ok, dotenv = pcall(require, "dotenv")
    if ok and type(dotenv.load) == "function" then
        dotenv.load()
    end
end

function Environment.get(name, default)
    local value = os.getenv(name)
    if value == nil or value == "" then
        return default
    end
    return value
end

return Environment
