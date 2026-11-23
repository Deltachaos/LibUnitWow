-- Lua 5.1 loader and test runner for WoW addon libraries.
-- Loads TOC entries and XML Script/Include files, then runs suites.
-- Provides suite registration, slug filters, snapshots, discovery,
-- and parallel workers.

local source = debug.getinfo(1, "S").source
if source:sub(1, 1) == "@" then source = source:sub(2) end
local moduleDir = source:match("^(.*)[/\\][^/\\]+$") or "."
local sep = package.config:sub(1, 1)
local File = dofile(moduleDir .. sep .. "file.lua")
if package and package.loaded then package.loaded["file"] = package.loaded["file"] or File end

local Test = {}
Test.passed = 0
Test.failed = 0
Test.currentSuite = nil
Test.currentSlug = nil
Test.suites = {}
Test.tests = {}
Test.onlySlugs = {}
Test.ignoreSlugs = {}
Test.file = File

local function envValue(name)
    if not os or not os.getenv then return nil end
    return os.getenv(name)
end

Test.workerId = tonumber(envValue("TEST_WORKER"))
Test.totalWorkers = tonumber(envValue("TEST_WORKERS")) or 1
Test.parallelMode = Test.totalWorkers > 1

local UPDATE_SNAPSHOTS = envValue("UPDATE_SNAPSHOTS") == "1"

local function show(value)
    if type(value) ~= "string" then return tostring(value) end
    if value:find("[^%g ]") then
        return (value:gsub(".", function(char) return string.format("%02x", char:byte()) end))
    end
    return value
end

local function directoryOf(path)
    return path:match("^(.*)[/\\][^/\\]+$") or "."
end

local function join(directory, file)
    if directory == "." or directory == "" then return file end
    local slash = directory:find("\\", 1, true) and "\\" or "/"
    return directory .. slash .. file
end

local function environment(env)
    if not env then
        if not strmatch then
            function strmatch(s, pattern, init)
                return string.match(tostring(s), pattern, init)
            end
        end
        return _G
    end
    if not env.strmatch then
        function env.strmatch(s, pattern, init)
            return string.match(tostring(s), pattern, init)
        end
    end
    return env
end

function Test.read(path)
    return File.read(path)
end

function Test.load(path, env)
    local chunk, err = loadfile(path)
    if not chunk then error(err) end
    setfenv(chunk, environment(env))
    return chunk()
end

function Test.loadXml(path, env)
    local xml, err = File.read(path)
    if not xml then error(err) end
    local directory = directoryOf(path)
    local cursor = 1
    while true do
        local startAt, stopAt, tag, file = xml:find("<%s*(%a+)%s+file%s*=%s*\"([^\"]+)\"", cursor)
        if not startAt then break end
        cursor = stopAt + 1
        local child = join(directory, file)
        if tag == "Script" then
            Test.load(child, env)
        elseif tag == "Include" then
            Test.loadXml(child, env)
        end
    end
end

function Test.loadToc(path, env)
    local toc, err = File.read(path)
    if not toc then error(err) end
    local directory = directoryOf(path)
    for rawLine in toc:gmatch("[^\r\n]+") do
        local line = rawLine:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and not line:match("^#") then
            local child = join(directory, line)
            if line:match("%.xml$") then
                Test.loadXml(child, env)
            else
                Test.load(child, env)
            end
        end
    end
end

function Test.assertEq(got, expected, msg)
    if got ~= expected then
        error((msg or "assertion failed") .. ": expected " .. show(expected) .. ", got " .. show(got))
    end
end

function Test.assertTrue(cond, msg)
    if not cond then error(msg or "expected true, got false") end
end

function Test.assertFalse(cond, msg)
    if cond then error(msg or "expected false, got true") end
end

function Test.assertNil(val, msg)
    if val ~= nil then error((msg or "expected nil") .. ", got " .. show(val)) end
end

function Test.assertNotNil(val, msg)
    if val == nil then error(msg or "expected non-nil value, got nil") end
end

function Test.assertError(fn, msg)
    if pcall(fn) then error(msg or "expected function to throw an error") end
end

function Test.assertTableEq(got, expected, msg)
    if type(got) ~= "table" or type(expected) ~= "table" then
        error((msg or "assertion failed") .. ": both values must be tables")
    end
    for key, value in pairs(expected) do
        if got[key] ~= value then
            error((msg or "assertion failed") .. ": key '" .. tostring(key) .. "' expected " .. show(value) .. ", got " .. show(got[key]))
        end
    end
    for key, value in pairs(got) do
        if expected[key] == nil then
            error((msg or "assertion failed") .. ": unexpected key '" .. tostring(key) .. "' with value " .. show(value))
        end
    end
end

function Test.sleep(seconds)
    local start = os.time()
    while os.time() - start < seconds do end
end

local function snapshotNameToFilename(name)
    if type(name) ~= "string" or name == "" then return "snapshot" end
    local safe = name:gsub("[^%w_-]", "_"):gsub("_+", "_"):gsub("^_", ""):gsub("_$", ""):lower()
    return (safe == "" and "snapshot") or safe
end

function Test.assertSnapshot(snapshotDir, name, currentValue)
    Test.assertNotNil(snapshotDir, "assertSnapshot: snapshotDir required")
    Test.assertNotNil(name, "assertSnapshot: name required")
    local valueStr = (currentValue == nil and "" or tostring(currentValue))
    local filename = snapshotNameToFilename(name) .. ".txt"
    local path = snapshotDir .. sep .. filename
    if UPDATE_SNAPSHOTS or not File.exists(path) then
        File.mkdir(snapshotDir)
        File.write(path, valueStr)
        return
    end
    local expected, err = File.read(path)
    if err then
        error("assertSnapshot: could not read snapshot '" .. name .. "': " .. tostring(err))
    end
    Test.assertEq(valueStr, expected, "Snapshot mismatch for '" .. name .. "'")
end

local function runCase(name, fn, suite)
    local ok, err = xpcall(fn, debug.traceback)
    local prefix = suite and (suite .. ": ") or ""
    if ok then
        print("PASS: " .. prefix .. name)
        Test.passed = Test.passed + 1
    else
        print("FAIL: " .. prefix .. name)
        print("  " .. tostring(err))
        Test.failed = Test.failed + 1
    end
end

function Test.shouldSkipSlug(slug)
    if #Test.onlySlugs > 0 then
        local found = false
        for i = 1, #Test.onlySlugs do
            if Test.onlySlugs[i] == slug then
                found = true
                break
            end
        end
        if not found then return true end
    end
    for i = 1, #Test.ignoreSlugs do
        if Test.ignoreSlugs[i] == slug then return true end
    end
    return false
end

function Test.test(name, fn)
    if Test.parallelMode then
        table.insert(Test.tests, { name = name, fn = fn, suite = Test.currentSuite, slug = Test.currentSlug })
        return
    end
    if Test.shouldSkipSlug(Test.currentSlug) then return end
    runCase(name, fn, Test.currentSuite)
end

function Test.suite(name, slug)
    Test.currentSuite = name
    Test.currentSlug = slug
    table.insert(Test.suites, { name = name, slug = slug })
end

function Test.reset()
    Test.passed = 0
    Test.failed = 0
    Test.currentSuite = nil
    Test.currentSlug = nil
    Test.suites = {}
    Test.tests = {}
end

function Test.summary()
    print("")
    print("=====================================")
    print(string.format("Tests: %d passed, %d failed", Test.passed, Test.failed))
    print("=====================================")
    return Test.failed == 0
end

function Test.exit()
    if Test.failed > 0 then os.exit(1) end
end

function Test.finish()
    Test.summary()
    Test.exit()
end

function Test.runFile(filepath)
    local chunk, err = loadfile(filepath)
    if not chunk then
        print("ERROR: Could not load " .. filepath)
        print("  " .. tostring(err))
        Test.failed = Test.failed + 1
        return false
    end
    local ok, runErr = pcall(chunk)
    if not ok then
        print("ERROR: Failed to run " .. filepath)
        print("  " .. tostring(runErr))
        Test.failed = Test.failed + 1
        return false
    end
    return true
end

function Test.discoverTests(dir)
    local tests = {}
    local pathForShell = dir:gsub("/", sep):gsub(sep .. "$", "")
    local names = File.listDir(pathForShell)
    if not names then return tests end
    for i = 1, #names do
        if names[i]:match("_test%.lua$") then
            table.insert(tests, pathForShell .. sep .. names[i])
        end
    end
    table.sort(tests)
    return tests
end

function Test.runWorkerSlice(workerId, totalWorkers)
    workerId = workerId or Test.workerId or 0
    totalWorkers = totalWorkers or Test.totalWorkers or 1
    for i, case in ipairs(Test.tests) do
        if (i - 1) % totalWorkers == workerId and not Test.shouldSkipSlug(case.slug) then
            runCase(case.name, case.fn, case.suite)
        end
    end
end

function Test.runAll(dir)
    local testFiles = Test.discoverTests(dir)
    if #testFiles == 0 then
        print("No test files found in " .. dir)
        return false
    end
    if not Test.parallelMode then
        print("Discovered " .. #testFiles .. " test file(s)")
        print("")
    end
    for i = 1, #testFiles do
        if not Test.parallelMode then
            print("--- Running: " .. testFiles[i] .. " ---")
        end
        Test.runFile(testFiles[i])
        if not Test.parallelMode then print("") end
    end
    if Test.parallelMode then return true end
    return Test.summary()
end

local function addSlugs(list, text)
    if not text or text == "" then return end
    for slug in text:gmatch("[^,]+") do
        local trimmed = slug:gsub("^%s+", ""):gsub("%s+$", "")
        if trimmed ~= "" then list[#list + 1] = trimmed end
    end
end

local onlyEnv = envValue("TEST_ONLY_SLUGS")
local ignoreEnv = envValue("TEST_IGNORE_SLUGS")
if onlyEnv and onlyEnv ~= "" then
    addSlugs(Test.onlySlugs, onlyEnv)
elseif type(arg) == "table" then
    for i = 1, #arg do
        addSlugs(Test.onlySlugs, arg[i]:match("^%-%-only=(.+)$"))
    end
end
if ignoreEnv and ignoreEnv ~= "" then
    addSlugs(Test.ignoreSlugs, ignoreEnv)
elseif type(arg) == "table" then
    for i = 1, #arg do
        addSlugs(Test.ignoreSlugs, arg[i]:match("^%-%-ignore=(.+)$"))
    end
end

return Test
