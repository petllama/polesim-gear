-- Offline tests: luajit tests/run.lua [file-name-part]   (LuaJIT = Lua 5.1 + bit, like the client)
package.path = "./tests/?.lua;" .. package.path
local T = require("t")
local want = arg[1] or ""
local p = io.popen("ls tests/test_*.lua")
for f in p:lines() do
	if f:find(want, 1, true) then T.file(f) end
end
p:close()
print(string.format("%d passed, %d failed", T.passed, T.failed))
os.exit(T.failed == 0 and 0 or 1)
