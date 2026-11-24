-- /psg drift (Drift.lua): the shipped stats (Data/Items.lua) against the client's live stats (the
-- tooltip's path: Live.Stats with the same family filling) for worn and bagged items, or one item id.
local T = require("t")
local FILES = { "Core.lua", "Data/Weights.lua", "Data/Suffixes.lua", "Data/Items.lua", "Items.lua", "Score.lua",
	"Equip.lua", "Live.lua", "Drift.lua" }

-- A client: items[link] = { loc, stats } (stats nil: no stats yet); a link not listed is not cached.
local function client(items)
	return {
		Info = function(link)
			local e = items[link]
			if not e then return nil end
			return e.loc, 1, 4, 1, 2, 1, "x"
		end,
		Stats = function(link)
			local e = items[link]
			return e and e.stats
		end,
	}
end
-- Ambassador's Boots (2033): sta 5, agi 3, spi 4, armor 62. Sizzle Stick (8071): sp 2, 17.65 dps.
local BOOTS = { ITEM_MOD_STAMINA_SHORT = 5, ITEM_MOD_AGILITY_SHORT = 3, ITEM_MOD_SPIRIT_SHORT = 4, RESISTANCE0_NAME = 62 }

local function capture(ns)
	local out = {}
	ns.Print = function(...) out[#out + 1] = table.concat({ ... }, " ") end
	return out
end

return {
	-- the same stats: no difference; a changed stat, a new one and a removed one are listed shipped -> live
	diff = function()
		local ns = T.addon(FILES)
		local D = ns.Drift
		local c = client({ ["item:2033"] = { loc = "INVTYPE_FEET", stats = BOOTS } })
		T.eq(D.Diff("item:2033", c), nil, "same stats")
		local changed = {}
		for k, v in pairs(BOOTS) do changed[k] = v end
		changed.ITEM_MOD_SPIRIT_SHORT = 6; changed.ITEM_MOD_AGILITY_SHORT = nil; changed.ITEM_MOD_INTELLECT_SHORT = 2
		changed.RESISTANCE0_NAME = 70
		c = client({ ["item:2033"] = { loc = "INVTYPE_FEET", stats = changed } })
		local d = D.Diff("item:2033", c)
		T.eq(D.Text(d), "agi 3 -> 0, armor 62 -> 70, int 0 -> 2, spi 4 -> 6")
		T.eq(D.Diff("item:999999", c), nil, "not shipped: nothing to compare")
		T.eq(D.Diff("item:2033", client({})), "pending", "not cached")
		T.eq(D.Diff("item:2033", client({ ["item:2033"] = { loc = "INVTYPE_FEET" } })), "pending", "no stats yet")
		T.eq(D.Diff("item:2033", client({ ["item:2033"] = { loc = "INVTYPE_BAG" } })), nil, "not gear")
	end,
	-- weapons: DPS within rounding is the same; a hotfixed spell power shows; a family the client does not
	-- report comes from the table (as in the tooltip), so it is not a difference
	weapon = function()
		local ns = T.addon(FILES)
		local D = ns.Drift
		local stick = { ITEM_MOD_SPELL_POWER_SHORT = 2, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 17.7 }
		T.eq(D.Diff("item:8071", client({ ["item:8071"] = { loc = "INVTYPE_RANGEDRIGHT", stats = stick } })), nil)
		stick.ITEM_MOD_SPELL_POWER_SHORT = nil
		stick.ITEM_MOD_STAMINA_SHORT = 1
		T.eq(D.Text(D.Diff("item:8071", client({ ["item:8071"] = { loc = "INVTYPE_RANGEDRIGHT", stats = stick } }))), "sta 0 -> 1")
		stick.ITEM_MOD_SPELL_POWER_SHORT, stick.ITEM_MOD_STAMINA_SHORT, stick.ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 4, nil, 19
		T.eq(D.Text(D.Diff("item:8071", client({ ["item:8071"] = { loc = "INVTYPE_RANGEDRIGHT", stats = stick } }))),
			"dps 17.65 -> 19, sp 2 -> 4")
	end,
	-- /psg drift: worn + bags (each link once), a compact line per item, 'no differences', items not
	-- loaded are requested and counted; /psg drift <id> checks one; runs at most every few seconds
	command = function()
		local ns = T.addon(FILES)
		local W = require("wow")
		local out = capture(ns)
		local changed = {}
		for k, v in pairs(BOOTS) do changed[k] = v end
		changed.ITEM_MOD_SPIRIT_SHORT = 6
		local items = { ["item:2033"] = { loc = "INVTYPE_FEET", stats = changed } }
		ns.Drift.client = client(items)
		local worn = { [8] = "item:2033" }
		_G.GetInventoryItemLink = function(_, slot) return worn[slot] end
		local bag = { "item:2033", "item:8071", "item:999999" }
		_G.C_Container = {
			GetContainerNumSlots = function(b) return b == 0 and #bag or 0 end,
			GetContainerItemInfo = function(b, s) return b == 0 and bag[s] and { hyperlink = bag[s] } or nil end,
		}
		local asked = {}
		_G.C_Item = { RequestLoadItemDataByID = function(id) asked[#asked + 1] = id end }
		W.time = 100
		SlashCmdList.POLESIMGEAR("drift")
		local all = table.concat(out, "\n")
		T.ok(all:find("Ambassador's Boots (2033): spi 4 -> 6", 1, true), all)
		T.eq(select(2, all:gsub("Ambassador's Boots", "")), 1, "the same link once")
		T.ok(all:find("1 item not loaded yet, run again", 1, true), all)
		T.eq(asked[1], 8071)
		-- throttled: a second run right away prints one short line
		out = capture(ns)
		W.time = 101
		SlashCmdList.POLESIMGEAR("drift")
		T.eq(#out, 1); T.ok(out[1]:find("again in", 1, true), out[1])
		-- now everything is loaded and the same
		items["item:2033"].stats = BOOTS
		items["item:8071"] = { loc = "INVTYPE_RANGEDRIGHT", stats = { ITEM_MOD_SPELL_POWER_SHORT = 2, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 17.6 } }
		out = capture(ns)
		W.time = 110
		SlashCmdList.POLESIMGEAR("drift")
		T.eq(#out, 1); T.ok(out[1]:find("no differences", 1, true), out[1]); T.ok(out[1]:find("2 items", 1, true), out[1])
		-- one item by id (not worn or bagged: item:<id>)
		items["item:6631"] = { loc = "INVTYPE_2HWEAPON", stats = { ITEM_MOD_SPIRIT_SHORT = 5, ITEM_MOD_STAMINA_SHORT = 3,
			ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 14.7, RESISTANCE3_NAME = 9 } }
		out = capture(ns)
		W.time = 120
		SlashCmdList.POLESIMGEAR("drift 6631")
		all = table.concat(out, "\n")
		T.ok(all:find("Living Root (6631): sta 2 -> 3", 1, true), all)
		out = capture(ns)
		W.time = 130
		SlashCmdList.POLESIMGEAR("drift 999999")
		T.ok(out[1]:find("not in PoleSim's item table", 1, true), out[1])
		_G.GetInventoryItemLink, _G.C_Container, _G.C_Item = nil, nil, nil
	end,
	-- a long list is cut: at most MAX_LINES item lines plus "and N more"
	long_list_is_cut = function()
		local ns = T.addon(FILES)
		local out = capture(ns)
		local links = {}
		local n = ns.Drift.MAX_LINES + 3
		for i = 1, n do links[i] = "item:2033:" .. i end -- distinct links of one item
		local changed = {}
		for k, v in pairs(BOOTS) do changed[k] = v end
		changed.ITEM_MOD_STAMINA_SHORT = 9
		ns.Drift.client = { Info = function() return "INVTYPE_FEET" end, Stats = function() return changed end }
		ns.Drift.Report(links)
		local all = table.concat(out, "\n")
		T.eq(select(2, all:gsub("sta 5 %-> 9", "")), ns.Drift.MAX_LINES)
		T.ok(all:find("and 3 more", 1, true), all)
	end,
}
