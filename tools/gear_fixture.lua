-- The gear string as a fixture for PoleSim's website tests (forever/web/tests/fixtures/gearstring/):
-- a level 24 Undead Shadow priest (Horde) through the test client (tests/recfix.lua), wearing random-
-- suffix greens with empty slots between them, a staff and a wand. Writes in DIR:
--   gear.txt   the string /psg export gear shows (GearString.Text)
--   gear.json  what the website must parse it to: cls, spec, level, raceId, faction, items {slot: [id, bonus?]}
--   luajit tools/gear_fixture.lua DIR
package.path = "./tests/?.lua;" .. package.path
local dir = assert(arg[1], "usage: tools/gear_fixture.lua DIR")
local RF = require("recfix")
local R = RF.setup({ level = 24 })
R.login()
local function link(id, bonus)
	return "|cff1eff00|Hitem:" .. id .. (":"):rep(12) .. (bonus and ("1:" .. bonus) or "") .. "|h[x]|h|r"
end
-- slot -> { item, random suffix }: Ivycloth Mantle / Shimmering Trousers / Shimmering Cloak "of Shadow
-- Wrath", Willow Vest / Shimmering Boots / Quartz Ring "of the Owl", Foamspittle Staff, Fire Wand
local WORN = { [3] = { 9796, 12761 }, [5] = { 6536, 12720 }, [7] = { 6568, 12761 }, [8] = { 6562, 12720 },
	[11] = { 11965, 12720 }, [15] = { 6564, 12761 }, [16] = { 1405 }, [18] = { 5069 } }
_G.GetInventoryItemLink = function(_, slot)
	local w = WORN[slot]
	return w and link(w[1], w[2])
end
local G = R.ns.GearString
local t = assert(G.Collect())
local text = G.Make(t)
local keys = {}
for slot in pairs(t.items) do keys[#keys + 1] = slot end
table.sort(keys)
local items = {}
for _, slot in ipairs(keys) do
	local it = t.items[slot]
	items[#items + 1] = ('"%d": [%d%s]'):format(slot, it.id, it.bonus and (", " .. it.bonus) or "")
end
local json = ('{"cls": "%s", "spec": "%s", "level": %d, "raceId": %d, "faction": "%s", "items": {%s}}\n'):format(
	t.cls, t.spec, t.level, t.raceID, t.faction, table.concat(items, ", "))
local function write(name, s)
	local f = assert(io.open(dir .. "/" .. name, "wb"))
	f:write(s)
	f:close()
end
write("gear.txt", text .. "\n")
write("gear.json", json)
print(text)
R.done()
