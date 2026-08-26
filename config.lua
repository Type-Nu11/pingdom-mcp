local config = require("lapis.config")

local function postgres()
    return {
        host = os.getenv("DB_HOST") or "db",
        port = tonumber(os.getenv("DB_PORT")) or 5432,
        user = os.getenv("DB_USER") or "postgres",
        password = os.getenv("DB_PASSWORD") or "postgres",
        database = os.getenv("DB_NAME") or "pingdom_dev",
    }
end

config("development", {
    server = "nginx",
    code_cache = "off",
    num_workers = "1",
    postgres = postgres(),
})

config("production", {
    server = "nginx",
    num_workers = "1",
    postgres = postgres(),
})
