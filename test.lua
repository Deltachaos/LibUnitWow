-- require("test") loads the LibUnitWow runner.
local source = debug.getinfo(1, "S").source
if source:sub(1, 1) == "@" then source = source:sub(2) end
local directory = source:match("^(.*)[/\\][^/\\]+$") or "."
local sep = package.config:sub(1, 1)
return dofile(directory .. sep .. "LibUnitWow.lua")
