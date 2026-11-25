-- The gear string for PoleSim's website (/psg export gear -> paste in the Armory at polesim.petllama.com):
--   PSGG1:<class>:<spec>:<level>:<race id>:<A|H>:<items>
-- items = 17 entries in equipment-slot order 1,2,3,5,6,7,8,9,10,11,12,13,14,15,16,17,18 (no shirt,
-- no tabard), comma separated: "<itemID>" or "<itemID>.<random-suffix bonus id>", empty = nothing worn,
-- trailing empties dropped. Race id = ChrRaces id (Skyborne 95 / 96). Only [A-Za-z0-9:,._], so it goes
-- into a URL as it is. No enchants (not scored here or on the site), no character/realm/guild names.
-- The website's parser: PoleSim forever/web/armory.py parse_gear_string (README "Gear string").
local ADDON, ns = ...
local GearString = {}
ns.GearString = GearString

GearString.PREFIX = "PSGG1"
GearString.SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }

-- t = { cls, spec, level, raceID, faction = "A" | "H", items = { [slot id] = { id, bonus } } } -> string
function GearString.Make(t)
	local toks = {}
	for i, slot in ipairs(GearString.SLOTS) do
		local it = t.items and t.items[slot]
		toks[i] = it and it.id and (tostring(it.id) .. (it.bonus and ("." .. it.bonus) or "")) or ""
	end
	local n = #toks
	while n > 0 and toks[n] == "" do
		toks[n] = nil
		n = n - 1
	end
	return table.concat({ GearString.PREFIX, t.cls, t.spec, tostring(t.level), tostring(t.raceID or 0), t.faction,
		table.concat(toks, ",") }, ":")
end

-- The character from the client: -> t | nil, why
function GearString.Collect()
	local _, file = UnitClass("player")
	local cls = file and file:lower()
	if not cls then return nil, "class not known yet" end
	local spec = ns.Spec and ns.Spec.ORDER[cls] and ns.Spec.Current(cls)
	if not spec then return nil, "no PoleSim spec for this class" end
	local faction = ({ Alliance = "A", Horde = "H" })[UnitFactionGroup("player") or ""]
	if not faction then return nil, "faction not known yet" end
	local _, _, raceID = UnitRace("player")
	local items = {}
	for _, slot in ipairs(GearString.SLOTS) do
		local link = GetInventoryItemLink("player", slot)
		local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
		if id then
			-- only a random suffix the shipped table knows for this item (Live.Bonus reads the bonus list)
			items[slot] = { id = id, bonus = ns.Live.Bonus(link, ns.Items.Peek(id)) }
		end
	end
	return { cls = cls, spec = spec, level = UnitLevel("player") or 1, raceID = raceID, faction = faction, items = items }
end

-- -> string | nil, why
function GearString.Text()
	local t, why = GearString.Collect()
	if not t then return nil, why end
	return GearString.Make(t)
end
