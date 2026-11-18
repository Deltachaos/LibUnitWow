#!/usr/bin/env lua
-- Discover *_test.lua files and run them.
--   lua5.1 LibUnitWow/run.lua [dir ...]
--   lua5.1 LibUnitWow/run.lua --toc=LibCrypto.toc
--   lua5.1 LibUnitWow/run.lua --no-toc
--   lua5.1 LibUnitWow/run.lua tests --only=crypto
--   lua5.1 LibUnitWow/run.lua tests --ignore=reliable
--   TEST_WORKERS=4 lua5.1 LibUnitWow/run.lua tests
-- Without --toc or --no-toc, the single *.toc in the working directory is used.
-- A selected TOC is loaded before the tests. --no-toc skips that load.

local scriptSource = debug.getinfo(1, "S").source
if scriptSource:sub(1, 1) == "@" then scriptSource = scriptSource:sub(2) end
local sep = package.config:sub(1, 1)
local isWindows = sep == "\\"
local scriptDir = scriptSource:match("^(.*)[/\\][^/\\]+$") or "."
package.path = scriptDir .. sep .. "?.lua;" .. package.path

local function shellQuote(value)
    value = tostring(value)
    if isWindows then return '"' .. value:gsub('"', '""') .. '"' end
    return '"' .. value:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

local function readCommand(command)
    local handle = io.popen(command)
    if not handle then return "" end
    local content = handle:read("*a") or ""
    handle:close()
    return content
end

local luaBin = os.getenv("LUA_BIN") or os.getenv("LUA") or arg[-1] or "lua5.1"
local dirs = {}
local tocPath = nil
local noToc = false
if type(arg) == "table" then
    for i = 1, #arg do
        local luaPath = arg[i]:match("^%-%-lua=(.+)$")
        local toc = arg[i]:match("^%-%-toc=(.+)$")
        if luaPath then luaBin = luaPath
        elseif arg[i] == "--no-toc" then noToc = true
        elseif toc then tocPath = toc
        elseif arg[i] == "--toc" then
            tocPath = arg[i + 1]
            if not tocPath or tocPath:sub(1, 2) == "--" then
                io.write("--toc needs a path\n")
                os.exit(1)
            end
        elseif arg[i]:sub(1, 2) ~= "--" and arg[i - 1] ~= "--toc" then
            dirs[#dirs + 1] = arg[i]
        end
    end
end
if #dirs == 0 then dirs[1] = "tests" end

local Test = require("test")

local function resolveToc()
    if noToc then return nil end
    if tocPath and tocPath ~= "" then return tocPath end
    local names = Test.file.listDir(".") or {}
    local found = {}
    for i = 1, #names do
        if names[i]:match("%.toc$") then found[#found + 1] = names[i] end
    end
    table.sort(found)
    if #found == 1 then return found[1] end
    if #found == 0 then
        io.write("No .toc file in the working directory. Pass --toc or --no-toc.\n")
    else
        io.write("More than one .toc file. Pass --toc:\n")
        for i = 1, #found do io.write("  " .. found[i] .. "\n") end
    end
    os.exit(1)
end

if noToc and tocPath and tocPath ~= "" then
    io.write("Pass either --toc or --no-toc.\n")
    os.exit(1)
end
tocPath = resolveToc()
if tocPath then
    if not Test.file.exists(tocPath) then
        io.write("TOC not found: " .. tocPath .. "\n")
        os.exit(1)
    end
    Test.toc = tocPath
    Test.root = tocPath:match("^(.*)[/\\][^/\\]+$") or "."
end

if #Test.onlySlugs > 0 then
    print("Only running tests with slugs: " .. table.concat(Test.onlySlugs, ", "))
end
if #Test.ignoreSlugs > 0 then
    print("Ignoring tests with slugs: " .. table.concat(Test.ignoreSlugs, ", "))
end

local function listSubdirs(path)
    local command
    if isWindows then
        command = "dir /b /ad " .. shellQuote(path) .. " 2>nul"
    else
        command = "find " .. shellQuote(path) .. " -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort"
    end
    local found = {}
    for line in readCommand(command):gmatch("[^\r\n]+") do
        local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
        if trimmed ~= "" then
            local prefix = path:gsub("[/\\]$", "") .. sep
            if trimmed:sub(1, #prefix) == prefix
                or trimmed:sub(1, 1) == "/" or trimmed:sub(1, 1) == "\\"
                or trimmed:match("^%a:[/\\]") then
                found[#found + 1] = trimmed
            else
                found[#found + 1] = prefix .. trimmed
            end
        end
    end
    return found
end

local function targetsFor(dir)
    local list = {}
    if #Test.discoverTests(dir) > 0 then list[#list + 1] = dir end
    local subs = listSubdirs(dir)
    for i = 1, #subs do
        if #Test.discoverTests(subs[i]) > 0 then list[#list + 1] = subs[i] end
    end
    return list
end

local totalWorkers = tonumber(os.getenv("TEST_WORKERS")) or 1
local workerId = os.getenv("TEST_WORKER")

local function childEnv(id, resultDir)
    local lines = {
        "TEST_WORKER=" .. id,
        "TEST_WORKERS=" .. totalWorkers,
        "TEST_RESULT_DIR=" .. resultDir,
    }
    if #Test.onlySlugs > 0 then
        lines[#lines + 1] = "TEST_ONLY_SLUGS=" .. table.concat(Test.onlySlugs, ",")
    end
    if #Test.ignoreSlugs > 0 then
        lines[#lines + 1] = "TEST_IGNORE_SLUGS=" .. table.concat(Test.ignoreSlugs, ",")
    end
    if luaBin ~= "lua" then lines[#lines + 1] = "LUA_BIN=" .. luaBin end
    return table.concat(lines, " ")
end

if totalWorkers > 1 and workerId == nil then
    local stamp = tostring(math.random(100000, 999999))
    local resultDir = (os.getenv("TEMP") or os.getenv("TMP") or (isWindows and "." or "/tmp")) .. sep .. "libunitwow_test_" .. stamp
    os.execute((isWindows and "mkdir " or "mkdir -p ") .. shellQuote(resultDir) .. (isWindows and " 2>nul" or " 2>/dev/null"))
    print("=====================================")
    print(" LibUnitWow (" .. totalWorkers .. " workers)")
    print("=====================================")
    local dirArgs = {}
    for i = 1, #dirs do dirArgs[i] = shellQuote(dirs[i]) end
    local workers = {}
    for id = 0, totalWorkers - 1 do
        local logPath = resultDir .. sep .. "worker_" .. id .. ".log"
        local exitPath = resultDir .. sep .. "exit_" .. id
        local tocArg = noToc and "--no-toc" or ("--toc=" .. Test.toc)
        local command = childEnv(id, resultDir) .. " " .. shellQuote(luaBin) .. " " .. shellQuote(scriptSource) .. " " .. shellQuote(tocArg) .. " " .. table.concat(dirArgs, " ")
        command = command .. " > " .. shellQuote(logPath) .. " 2>&1; echo $? > " .. shellQuote(exitPath)
        workers[id] = io.popen(isWindows and ("cmd /c " .. shellQuote(command)) or command)
    end
    local function busy()
        for id = 0, totalWorkers - 1 do
            local handle = io.open(resultDir .. sep .. "exit_" .. id, "r")
            if handle then handle:close() else return true end
        end
        return false
    end
    while busy() do os.execute(isWindows and "ping -n 2 127.0.0.1 >nul" or "sleep 1") end
    for id = 0, totalWorkers - 1 do
        if workers[id] then workers[id]:close() end
    end
    local passed, failed = 0, 0
    for id = 0, totalWorkers - 1 do
        local log = io.open(resultDir .. sep .. "worker_" .. id .. ".log", "r")
        if log then
            io.write(log:read("*a") or "")
            log:close()
        end
        local handle = io.open(resultDir .. sep .. "stats_" .. id, "r")
        if handle then
            local content = handle:read("*a") or ""
            handle:close()
            local okCount, failCount = content:match("^(%d+)\r?\n(%d+)")
            passed = passed + (tonumber(okCount) or 0)
            failed = failed + (tonumber(failCount) or 0)
        else
            failed = failed + 1
        end
    end
    os.execute((isWindows and "rmdir /s /q " or "rm -rf ") .. shellQuote(resultDir))
    print("")
    print("=====================================")
    print(string.format("Tests: %d passed, %d failed", passed, failed))
    print("=====================================")
    os.exit(failed > 0 and 1 or 0)
end

print("=====================================")
print(" LibUnitWow" .. (workerId and (" (worker " .. (tonumber(workerId) + 1) .. "/" .. Test.totalWorkers .. ")") or ""))
print("=====================================")
print("")

if Test.toc then Test.loadToc(Test.toc) end

local ran = false
for i = 1, #dirs do
    local targets = targetsFor(dirs[i])
    for j = 1, #targets do
        ran = true
        Test.runAll(targets[j])
    end
end
if not ran then
    print("No test files found")
    os.exit(1)
end
if Test.parallelMode then Test.runWorkerSlice(Test.workerId, Test.totalWorkers) end

local resultDir = os.getenv("TEST_RESULT_DIR")
if resultDir and workerId and workerId ~= "" then
    local handle = io.open(resultDir .. sep .. "stats_" .. workerId, "w")
    if handle then
        handle:write(tostring(Test.passed), "\n", tostring(Test.failed))
        handle:close()
    end
end
Test.exit()
