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
-- one worn item whose live stats differ from the shipped table (Ambassador's Boots, spirit 4 -> 6): a
-- drift row for the website's parser and its aggregate
R.U.equipped[8] = "item:2033"
R.ns.Drift.client = {
	Info = function(link) if link == "item:2033" then return "INVTYPE_FEET", 1, 4, 1, 2, 1, "x" end end,
	Stats = function(link)
		if link == "item:2033" then
			return { ITEM_MOD_STAMINA_SHORT = 5, ITEM_MOD_AGILITY_SHORT = 3, ITEM_MOD_SPIRIT_SHORT = 6, RESISTANCE0_NAME = 62 }
		end
	end,
}
R.login()
RF.session(R, seconds)
-- then a short Blackfathom Deeps run as a level 23 priest healing a warrior and a mage (0.7.14 groups):
-- trash pulls with mana readable, a boss encounter, and two pulls where the client keeps mana secret
R.level = 23
R.instance = true
R.member("party1", "WARRIOR", 24, { role = "TANK", name = RF.NAMES[6] })
R.member("party2", "MAGE", 22, { role = "DAMAGER", name = RF.NAMES[7] })
R.tick()
local meter = RF.fakeMeter(R)
for i = 1, 5 do
	R.mana = i <= 3 and 780 or nil
	local boss = i == 3
	local mobs = boss and { { "boss1", 4887, 25, "worldboss", RF.NAMES[9] } }
		or { { "target", 4789, 24, "elite", RF.NAMES[9] }, { "nameplate2", 4798, 23, "elite" } }
	RF.groupFight(R, mobs, 20 + i * 5, function(R2, s)
		if R2.mana then R2.mana = 780 - s * 12 end
		if boss and s == 1 then R2.gevent("ENCOUNTER_START", 1667, RF.NAMES[9], 1, 5) end
		if s % 4 == 0 then R2.cast(s % 8 == 0 and 2061 or 139) end
		if s == 3 then R2.gevent("UNIT_COMBAT", "party1", "WOUND", "", 140 + i, 1) end
	end, function(R2)
		if boss then R2.gevent("ENCOUNTER_END", 1667, RF.NAMES[9], 1, 5, 1) end
		RF.meterFor(meter, i)
	end)
	R.play(20)
end
_G.C_DamageMeter = nil
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
print(("%d pulls, %d group fights, %d drift rows, %d chars in %d part(s), checksum %s, code %s"):format(#doc.pulls.rows, #doc.groups.fights, #doc.drift.rows, #table.concat(parts), #parts, crc, E.CodeFor(crc)))
R.done()
