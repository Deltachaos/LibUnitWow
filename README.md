# LibUnitWow

LibUnitWow loads a WoW addon TOC and runs Lua 5.1 tests. Suites are `*_test.lua` files. The runner discovers them and loads `test.lua`, so a suite starts with `require("test")`.

From the addon directory:

```
lua5.1 ../LibUnitWow/run.lua
```

That uses the only `*.toc` in the working directory and loads it before the tests. `LibStub` is available when a suite file runs.

```
lua5.1 ../LibUnitWow/run.lua --toc LibCrypto.toc
lua5.1 ../LibUnitWow/run.lua --no-toc
```

`--toc` selects the TOC. `--no-toc` skips the lookup and the load. `Test.toc` is the TOC path and `Test.root` is its directory. A suite that builds its own environment loads that TOC with `Test.loadToc(Test.toc, env)`.

## Suite

```lua
local Test = require("test")

Test.suite("LibCrypto", "crypto")

Test.test("BLAKE2s matches RFC 7693", function()
    Test.assertEq(Crypto:Blake2s(""), expected)
end)
```

Assertions are `assertEq`, `assertTrue`, `assertFalse`, `assertNil`, `assertNotNil`, `assertError`, `assertTableEq`, and `assertSnapshot`. `Test.sleep` waits on the wall clock.

`--only` and `--ignore` select suite slugs, and so do `TEST_ONLY_SLUGS` and `TEST_IGNORE_SLUGS`. `TEST_WORKERS` splits the tests across processes. `UPDATE_SNAPSHOTS=1` rewrites snapshot files.

`run.lua` also accepts a test directory. The default is `tests`.
