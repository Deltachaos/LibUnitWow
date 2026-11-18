-- File and directory operations for tests.
-- Uses os.execute and io.popen so a WoW host can replace this file.
-- Lua 5.1: file reads use "*a".

local sep = package.config:sub(1, 1)
local isWindows = (sep == "\\")

local File = {}

local function shellQuote(path)
    path = tostring(path)
    if isWindows then return '"' .. path:gsub('"', '""') .. '"' end
    return '"' .. path:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

function File.read(path)
    if not path or path == "" then return nil, "empty path" end
    local handle, err = io.open(path, "rb")
    if not handle then return nil, err or "read failed" end
    local content = handle:read("*a")
    handle:close()
    if content == nil then return nil, "read failed" end
    return content
end

function File.write(path, content)
    if not path or path == "" then return nil, "empty path" end
    local handle, err = io.open(path, "wb")
    if not handle then return nil, err or "open for write failed" end
    handle:write(content or "")
    handle:close()
    return true
end

function File.exists(path)
    if not path or path == "" then return false end
    local command
    if isWindows then
        command = "dir /b " .. shellQuote(path) .. " >nul 2>nul"
    else
        command = "test -e " .. shellQuote(path)
    end
    local ok = os.execute(command)
    return ok == true or ok == 0
end

function File.mkdir(path)
    if not path or path == "" then return nil, "empty path" end
    local command
    if isWindows then
        command = "mkdir " .. shellQuote(path:gsub("/", sep)) .. " 2>nul"
    else
        command = "mkdir -p " .. shellQuote(path) .. " 2>/dev/null"
    end
    local ok = os.execute(command)
    if ok == true or ok == 0 then return true end
    return nil, "mkdir failed"
end

function File.listDir(path)
    if not path or path == "" then return nil, "empty path" end
    local command
    if isWindows then
        command = "dir /b " .. shellQuote(path:gsub("/", sep)) .. " 2>nul"
    else
        command = "ls -1 " .. shellQuote(path) .. " 2>/dev/null"
    end
    local handle = io.popen(command)
    if not handle then return nil, "popen failed" end
    local names = {}
    for line in handle:lines() do
        local trimmed = line:gsub("^%s+", ""):gsub("%s+$", ""):gsub("\r", "")
        if trimmed ~= "" then names[#names + 1] = trimmed end
    end
    handle:close()
    return names
end

return File
