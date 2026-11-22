local T = require("t")
local FILES = { "Core.lua", "Data/Weights.lua", "Data/Suffixes.lua", "Data/Items.lua", "Items.lua" }
local function loaded(db)
	_G.PoleSimGearDB, _G.PoleSimGearCharDB = db, {}
	local ns = T.addon(FILES)
	ns._frame.scripts.OnEvent(ns._frame, "ADDON_LOADED", "PoleSimGear")
	return ns, function(e, ...) ns._frame.scripts.OnEvent(ns._frame, e, ...) end
end
return {
	-- An item the client cannot load (Forever's server has no such item: its tooltip stays at
	-- "Retrieving item information") arrives as ITEM_DATA_LOAD_RESULT or GET_ITEM_INFO_RECEIVED with
	-- success false. It is remembered account-wide and the shipped table no longer gives it (every list,
	-- the AH and arrows read it through Get/Peek), until a new addon version (new data) clears the list.
	missing_items = function()
		local ns, ev = loaded({})
		local fired = {}
		ns.On("ITEMS_MISSING", function(id) fired[#fired + 1] = id end)
		T.ok(ns.Items.Get(6540), "shipped")
		ev("GET_ITEM_INFO_RECEIVED", 6540, true)
		T.eq(#fired, 0, "loaded fine")
		ev("ITEM_DATA_LOAD_RESULT", 6540, false)
		T.eq(fired[1], 6540, "told")
		T.ok(ns.Items.IsMissing(6540))
		T.eq(ns.Items.Get(6540), nil, "Get: gone")
		T.eq(ns.Items.Peek(6540), nil, "Peek: gone")
		ev("GET_ITEM_INFO_RECEIVED", 6540, false)
		T.eq(#fired, 1, "told once")
		ev("GET_ITEM_INFO_RECEIVED", 11288, false)
		T.eq(fired[2], 11288, "the other event too")
		ev("GET_ITEM_INFO_RECEIVED", 1, false)
		T.eq(#fired, 2, "an item we don't ship: not kept")
		T.eq(PoleSimGearDB.missing.ids[1], nil)
		T.eq(ns.Items.Peek(1219).id, 1219, "others untouched")
		-- the next session of the same version still knows
		local db = PoleSimGearDB
		ns = loaded(db)
		T.eq(ns.Items.Get(6540), nil, "remembered")
		T.eq(ns.Items.MissingCount(), 2)
		-- a new version (new data): forgotten
		db.missing.v = "0.0.1/old"
		ns = loaded(db)
		T.eq(ns.Items.Get(6540).name, "Willow Pants", "cleared by an update")
		T.eq(ns.Items.MissingCount(), 0)
		_G.PoleSimGearDB, _G.PoleSimGearCharDB = nil, nil
	end,
	-- /psg missing lists them; /psg missing clear forgets them (then /reload or reopen the window)
	missing_slash = function()
		local ns, ev = loaded({})
		local out = {}
		ns.Print = function(...) out[#out + 1] = table.concat({ ... }, " ") end
		SlashCmdList.POLESIMGEAR("missing")
		T.ok(out[1]:find("no items", 1, true), out[1])
		ev("ITEM_DATA_LOAD_RESULT", 6540, false)
		out = {}
		SlashCmdList.POLESIMGEAR("missing")
		T.ok(table.concat(out, "\n"):find("Willow Pants (6540)", 1, true), table.concat(out, "\n"))
		SlashCmdList.POLESIMGEAR("missing clear")
		T.eq(ns.Items.MissingCount(), 0)
		T.eq(ns.Items.Get(6540).name, "Willow Pants")
		_G.PoleSimGearDB, _G.PoleSimGearCharDB = nil, nil
	end,
	get = function()
		local ns = T.addon(FILES)
		local it = ns.Items.Get(6540)
		T.eq(it.name, "Willow Pants")
		T.eq(it.inv, 7)
		T.eq(it.c, 4)
		T.eq(it.sc, 1)
		T.ok(it.ar > 0)
		T.ok(#it.sfx > 5)
		T.eq(type(it.sfx[1]), "number")
		T.ok(it.b > 0)
		T.eq(ns.Items.Get(6540), it, "cached")
		T.eq(ns.Items.Get(1), nil)
		T.eq(ns.Items.Get(14152).name, "Robe of the Archmage", "mage-only items are shipped (mage support)")
		T.eq(ns.Items.Get(1219).sc, 7, "one-hand swords are shipped (mage weapon)")
	end,
	-- Gates other than the level: a reputation (faction, standing 0..7) is shipped (the vendor's note);
	-- PvP-rank items are not shipped at all (never upgrades, as on the website).
	gates = function()
		local ns = T.addon(FILES)
		T.eq(ns.Items.Get(16315), nil, "Sergeant Major's Cape: a PvP rank")
		T.eq(ns.Items.Get(6540).rep, nil)
		local id, f, s = ns.DATA.items:match("\n(%d+)\t([^\n]*\t)(%d+:%d+)\n")
		T.ok(id, "a shipped item with a reputation gate")
		local it = ns.Items.Get(tonumber(id))
		T.eq(it.rep[1] .. ":" .. it.rep[2], s)
	end,
	wand = function()
		local ns = T.addon(FILES)
		local w = ns.Items.Get(11288)
		T.eq(w.s.sp, 2)
		T.ok(w.dps > 0)
	end,
	by_inv = function()
		local ns = T.addon(FILES)
		local by = ns.Items.ByInv()
		local found = false
		for _, id in ipairs(by[7]) do if id == 6540 then found = true end end
		T.ok(found)
		T.ok(#by[26] > 0, "wands")
	end,
	-- The browser's index decodes nothing (the whole table decoded and kept was ~8 MB): it keeps ids per
	-- inventory type and each item's required level; Peek decodes one item without keeping it.
	by_inv_keeps_no_records = function()
		local ns = T.addon(FILES)
		local by = ns.Items.ByInv()
		T.eq(ns.Items._cached(), 0, "nothing decoded and kept")
		T.eq(ns.Items.Rl(6540), ns.Items.Peek(6540).rl)
		T.eq(ns.Items.Rl(1), nil)
		T.ok(ns.Items.Peek(6540) ~= ns.Items.Peek(6540), "Peek keeps nothing")
		T.eq(ns.Items._cached(), 0)
		local it = ns.Items.Get(6540)
		T.eq(ns.Items.Peek(6540), it, "an item kept by Get is shared")
		T.eq(ns.Items.Peek(1), nil)
		T.eq(ns.Items.ByInv(), by, "built once")
		ns.Items.ReleaseIndex()
		T.ok(ns.Items.ByInv() ~= by, "built again after a release")
		T.eq(ns.Items.Rl(6540), it.rl)
	end,
	-- With the index built, Peek reads the line at its recorded offset: no search of the blob for the
	-- id; the same record as Get's for every indexed item.
	peek_reads_at_the_offset = function()
		local find, searches = string.find, 0
		string.find = function(s, p, ...)
			if type(p) == "string" and p:match("^\n%d+	$") then searches = searches + 1 end
			return find(s, p, ...)
		end
		local ok, err = pcall(function()
			local ns = T.addon(FILES)
			local by = ns.Items.ByInv()
			searches = 0
			local n = 0
			for _, list in pairs(by) do
				for _, id in ipairs(list) do
					local p = ns.Items.Peek(id)
					T.eq(p.id, id); T.eq(p.rl, ns.Items.Rl(id))
					n = n + 1
				end
			end
			T.eq(searches, 0, "no search for the id")
			T.ok(n > 1000, "items " .. n)
			local fresh = T.addon(FILES)
			for _, id in ipairs({ 6540, 11288, by[26][#by[26]], by[1][1] }) do
				local a, b = ns.Items.Peek(id), fresh.Items.Get(id)
				for k, v in pairs(b) do
					if type(v) ~= "table" then T.eq(a[k], v, id .. "." .. k) end
				end
				T.eq(table.concat(a.sfx, ","), table.concat(b.sfx, ","))
			end
			T.eq(ns.Items.Peek(1), nil)
		end)
		string.find = find
		assert(ok, err)
	end,
	-- An offset that no longer points at its id (the table changed under the index) is not trusted:
	-- the line is searched for instead of decoding a neighbour.
	peek_checks_the_offset = function()
		local ns = T.addon(FILES)
		ns.Items.ByInv()
		ns.DATA.items = "\n1\tShifted\t1\t1\t1\t7\t4\t1\t\t0\t0\t\t0\t\t0\t0\t0\t0" .. ns.DATA.items
		local p = ns.Items.Peek(6540)
		T.eq(p and p.id, 6540); T.eq(p and p.name, "Willow Pants")
		T.eq(ns.Items.Peek(11288).dps > 0, true)
	end,
}
