-- /psg export gear: the gear string for the website's Armory (GearString.lua, GearExport.lua).
-- PSGG1:<class>:<spec>:<level>:<race id>:<A|H>:<items>, items in equipment-slot order
-- 1,2,3,5,...,18 (no shirt, no tabard), "<id>" or "<id>.<suffix bonus id>", trailing empties dropped.
local T = require("t")
local RF = require("recfix")

-- an item link the way the client writes it: bonus-ID list after field 13 (numBonusIDs)
local function link(id, bonus, enchant, name)
	local s = "item:" .. id .. ":" .. (enchant or "") .. (":"):rep(11) .. (bonus and ("1:" .. bonus) or "")
	return "|cff1eff00|H" .. s .. "|h[" .. (name or "Thing") .. "]|h|r"
end
local WORN = {
	[3] = link(9796, 12761, nil, "Ivycloth Mantle of Shadow Wrath"),
	[4] = link(2575, nil, nil, "Red Linen Shirt"), -- shirt: never exported
	[5] = link(6536, 12720, 1843, "Willow Vest of the Owl"), -- enchanted: the enchant is not exported
	[16] = link(1405, nil, nil, "Foamspittle Staff"),
	[18] = link(5069, nil, nil, "Fire Wand"),
	[19] = link(5976, nil, nil, "Guild Tabard"),
}
local WANT = "PSGG1:priest:shadow:24:5:H:,,9796.12761,6536.12720,,,,,,,,,,,1405,,5069"

local function setup()
	local R = RF.setup({ level = 24 })
	R.login()
	_G.GetInventoryItemLink = function(_, slot) return WORN[slot] end
	return R
end

return {
	make_is_positional_with_suffixes_and_empty_slots = function()
		local G = T.addon({ "Core.lua", "GearString.lua" }).GearString
		T.eq(G.Make({ cls = "priest", spec = "shadow", level = 24, raceID = 5, faction = "H",
			items = { [3] = { id = 9796, bonus = 12761 }, [16] = { id = 1405 } } }),
			"PSGG1:priest:shadow:24:5:H:,,9796.12761,,,,,,,,,,,,1405")
	end,

	trailing_empty_slots_are_dropped = function()
		local G = T.addon({ "Core.lua", "GearString.lua" }).GearString
		T.eq(G.Make({ cls = "mage", spec = "frost", level = 12, raceID = 8, faction = "H", items = {} }),
			"PSGG1:mage:frost:12:8:H:")
		T.eq(G.Make({ cls = "mage", spec = "frost", level = 12, raceID = 8, faction = "H", items = { [1] = { id = 7 } } }),
			"PSGG1:mage:frost:12:8:H:7")
	end,

	skyborne_keeps_its_race_id = function()
		local G = T.addon({ "Core.lua", "GearString.lua" }).GearString
		T.eq(G.Make({ cls = "druid", spec = "balance", level = 30, raceID = 96, faction = "H", items = {} }),
			"PSGG1:druid:balance:30:96:H:")
	end,

	collect_reads_the_worn_links = function()
		local R = setup()
		local s = R.ns.GearString.Text()
		T.eq(s, WANT)
		T.ok(not s:find("Ivycloth") and not s:find("Pelleas") and not s:find("1843"), "no names, no enchant")
		T.ok(s:match("^[A-Za-z0-9:,._]+$"), "URL-safe")
		R.done()
	end,

	an_unknown_suffix_is_left_out = function()
		local R = setup()
		WORN[7] = link(6568, 99999, nil, "Shimmering Trousers of Nothing")
		local s = R.ns.GearString.Text()
		WORN[7] = nil
		T.ok(s:find(",6568,", 1, true), "item kept, bonus dropped: " .. s)
		R.done()
	end,

	slash_export_gear_opens_one_highlighted_line = function()
		local R = setup()
		SlashCmdList.POLESIMGEAR("export gear")
		R.fx.settle()
		local w = R.ns.GearExport.Frame()
		T.ok(w and w:IsShown(), "window shown")
		T.eq(w.box.text, WANT)
		T.ok(w.box.focused, "focused")
		T.ok(w.box.highlighted, "highlighted")
		T.ok(R.U.texts(w):find("polesim.petllama.com", 1, true), "where to paste")
		-- an edit puts the text back (it is for copying)
		w.box:SetText("x")
		local fn = w.box:GetScript("OnTextChanged")
		fn(w.box, true)
		T.eq(w.box.text, WANT)
		-- plain /psg export is still the recorder's export
		T.ok(not R.ns.RecordUI.ExportFrame() or not R.ns.RecordUI.ExportFrame():IsShown(), "recorder window not opened")
		R.done()
	end,
}
