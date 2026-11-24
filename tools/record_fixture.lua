-- The recorder's export as a fixture for PoleSim's website tests (forever/web/tests): a synthetic
-- session through the test client (tests/recfix.lua), written as three files in DIR:
--   export.txt  the export string (PSG1:...), as /psg export shows it
--   summary.json the same summary as plain JSON (what the website must decode it to)
--   code.txt    the confirmation code the addon expects for it
--   luajit tools/record_fixture.lua DIR [seconds of play, default 1800]
package.path = "./tests/?.lua;" .. package.path
local dir = assert(arg[1], "usage: tools/record_fixture.lua DIR [seconds]")
local seconds = tonumber(arg[2] or "1800")
local RF = require("recfix")
local R = RF.setup({ record = true })
R.login()
RF.session(R, seconds)
local E = R.ns.RecordExport
local doc = E.Summary()
local parts, crc = E.Build(doc)
local function write(name, text)
	local f = assert(io.open(dir .. "/" .. name, "wb"))
	f:write(text)
	f:close()
end
write("export.txt", table.concat(parts, "\n") .. "\n")
write("summary.json", E.Json(doc) .. "\n")
write("code.txt", E.CodeFor(crc) .. "\n")
print(("%d pulls, %d chars in %d part(s), checksum %s, code %s"):format(#doc.pulls.rows, #table.concat(parts), #parts, crc, E.CodeFor(crc)))
R.done()
