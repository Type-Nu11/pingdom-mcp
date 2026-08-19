-- src/bootstrap.lua
-- Add project root to the Lua module search path so project modules can be required
-- as `src.*` from the repository root or container working directory.

local function project_root_from_current_file()
    local source = debug.getinfo(1, "S").source
    if not source then
        return "."
    end

    local path = source:match("^@(.+)") or source
    path = path:gsub("[/\\]src[/\\]bootstrap.lua$", "")
    path = path:gsub("[/\\]bootstrap.lua$", "")
    if path == "" then
        return "."
    end
    return path
end

local root = project_root_from_current_file()
local entries = {
    root .. "/?.lua",
    root .. "/?/init.lua",
    root .. "/src/?.lua",
    root .. "/src/?/init.lua",
}

for _, entry in ipairs(entries) do
    if not package.path:find(entry, 1, true) then
        package.path = package.path .. ";" .. entry
    end
end

return true
