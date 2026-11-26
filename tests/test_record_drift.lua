-- Item data drift in the recorder (Record.lua): at every sheet snapshot (login, level up) the worn and
-- bagged items are compared like /psg drift (Drift.Diff); only mismatches are kept, once per item +
-- suffix + stat per character (again only when the live value changes), items not loaded yet wait for
-- the next snapshot, at most Record.DRIFT_MAX rows are held for an export.
local T = require("t")
local RF = require("recfix")

-- Ambassador's Boots (2033) as the client reports them: spirit 6 (shipped 4)
local BOOTS = { ITEM_MOD_STAMINA_SHORT = 5, ITEM_MOD_AGILITY_SHORT = 3, ITEM_MOD_SPIRIT_SHORT = 6, RESISTANCE0_NAME = 62 }

-- items[link] = { loc, stats }; a link not listed is not loaded
local function client(items)
	return {
		Info = function(link)
			local e = items[link]
			if not e then return nil end
			return e.loc, 1, 4, 1, 2, 1, "x"
		end,
		Stats = function(link) local e = items[link] return e and e.stats end,
	}
end

local function setup(items, worn, bag)
	local R = RF.setup({ record = true })
	R.ns.Drift.client = client(items)
	for slot, link in pairs(worn or {}) do R.U.equipped[slot] = link end
	bag = bag or {}
	_G.C_Container = {
		GetContainerNumSlots = function(b) return b == 0 and #bag or 0 end,
		GetContainerItemInfo = function(b, s) return b == 0 and bag[s] and { hyperlink = bag[s] } or nil end,
	}
	return R
end
local function finish(R)
	R.ns.Drift.client = nil
	_G.C_Container = nil
	R.done()
end
local function levelUp(R)
	R.level = R.level + 1
	R.event("PLAYER_LEVEL_UP", R.level)
	R.wait(4)
	R.tick()
end

return {
	a_mismatch_is_recorded_at_the_login_snapshot = function()
		local R = setup({ ["item:2033"] = { loc = "INVTYPE_FEET", stats = BOOTS } }, { [8] = "item:2033" })
		R.login()
		R.play(20)
		local f = R.all("f")
		T.eq(#f, 1, "one drift row")
		T.eq(f[1].i, 2033); T.eq(f[1].sx, 0, "no suffix"); T.eq(f[1].k, "spi")
		T.eq(f[1].s, 4, "shipped"); T.eq(f[1].v, 6, "live")
		finish(R)
	end,

	the_same_mismatch_is_recorded_once_per_character = function()
		local items = { ["item:2033"] = { loc = "INVTYPE_FEET", stats = BOOTS } }
		local R = setup(items, { [8] = "item:2033" }, { "item:2033" })
		R.login()
		R.play(20)
		levelUp(R)
		T.eq(#R.all("c"), 2, "two snapshots")
		T.eq(#R.all("f"), 1, "worn + bagged copy and a second snapshot: still one row")
		-- the live value changes (another hotfix): recorded again
		local again = {}
		for k, v in pairs(BOOTS) do again[k] = v end
		again.ITEM_MOD_SPIRIT_SHORT = 7
		items["item:2033"].stats = again
		levelUp(R)
		local f = R.all("f")
		T.eq(#f, 2); T.eq(f[2].v, 7)
		-- an upload does not forget what was seen
		R.ns.Record.Data().blocks = {}
		levelUp(R)
		T.eq(#R.all("f"), 0, "seen before the upload: not again")
		finish(R)
	end,

	an_item_not_loaded_yet_waits_for_the_next_snapshot = function()
		local items = {}
		local R = setup(items, { [8] = "item:2033" })
		R.login()
		R.play(20)
		T.eq(#R.all("c"), 1)
		T.eq(#R.all("f"), 0, "not loaded: skipped")
		items["item:2033"] = { loc = "INVTYPE_FEET", stats = BOOTS }
		levelUp(R)
		T.eq(#R.all("f"), 1, "loaded by the next snapshot")
		finish(R)
	end,

	same_stats_record_nothing = function()
		local same = {}
		for k, v in pairs(BOOTS) do same[k] = v end
		same.ITEM_MOD_SPIRIT_SHORT = 4
		local R = setup({ ["item:2033"] = { loc = "INVTYPE_FEET", stats = same } }, { [8] = "item:2033" })
		R.login()
		R.play(20)
		T.eq(#R.all("f"), 0)
		finish(R)
	end,

	the_suffix_is_kept = function()
		-- Carving Knife (2140) of the Eagle (bonus 12718) reporting an extra point of Intellect
		local link = "item:2140" .. (":"):rep(12) .. "1:12718"
		local R = setup({ [link] = { loc = "INVTYPE_WEAPON", stats = { ITEM_MOD_INTELLECT_SHORT = 2,
			ITEM_MOD_STAMINA_SHORT = 1, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 5.94 } } }, {}, { link })
		R.login()
		R.play(20)
		local f = R.all("f")
		T.eq(#f, 1); T.eq(f[1].i, 2140); T.eq(f[1].sx, 12718); T.eq(f[1].k, "int"); T.eq(f[1].s, 1); T.eq(f[1].v, 2)
		finish(R)
	end,

	at_most_drift_max_rows_are_held = function()
		local items, bag = {}, {}
		-- every bag slot a boots copy with another (fake) bonus id: each is its own item + suffix
		for i = 1, 30 do
			local link = "item:2033:" .. i
			bag[i] = link
			items[link] = { loc = "INVTYPE_FEET", stats = { ITEM_MOD_STAMINA_SHORT = 9, ITEM_MOD_AGILITY_SHORT = 9,
				ITEM_MOD_SPIRIT_SHORT = 9, RESISTANCE0_NAME = 62 } }
		end
		local R = setup(items, {}, bag)
		R.ns.Record.DRIFT_MAX = 50
		R.login()
		R.play(20)
		-- 30 links differ only in the enchant field: one item + suffix, so 3 rows (sta, agi, spi)
		T.eq(#R.all("f"), 3, "duplicates of one item + suffix + stat count once")
		finish(R)
		-- a cap below what is found: the rest is not marked seen and comes later
		R = setup({ ["item:2033"] = { loc = "INVTYPE_FEET", stats = { ITEM_MOD_STAMINA_SHORT = 9,
			ITEM_MOD_AGILITY_SHORT = 9, ITEM_MOD_SPIRIT_SHORT = 9, RESISTANCE0_NAME = 62 } } }, { [8] = "item:2033" })
		R.ns.Record.DRIFT_MAX = 2
		R.login()
		R.play(20)
		T.eq(#R.all("f"), 2, "capped")
		R.ns.Record.Data().blocks = {}
		levelUp(R)
		T.eq(#R.all("f"), 1, "the third after an upload made room")
		R.ns.Record.DRIFT_MAX = 50
		finish(R)
	end,

	nothing_while_recording_is_off = function()
		local R = setup({ ["item:2033"] = { loc = "INVTYPE_FEET", stats = BOOTS } }, { [8] = "item:2033" })
		R.ns.Options.Set("record", false)
		R.login()
		R.play(20)
		T.eq(#R.all("f"), 0)
		finish(R)
	end,

	the_export_carries_drift_rows = function()
		local R = setup({ ["item:2033"] = { loc = "INVTYPE_FEET", stats = BOOTS } }, { [8] = "item:2033" })
		R.login()
		R.play(20)
		local doc = R.ns.RecordExport.Summary()
		T.eq(table.concat(doc.drift.cols, ","), "sess,at,item,suffix,stat,shipped,live")
		T.eq(#doc.drift.rows, 1)
		local row = doc.drift.rows[1]
		T.eq(row[3], 2033); T.eq(row[4], 0); T.eq(row[5], "spi"); T.eq(row[6], 4); T.eq(row[7], 6)
		local back = R.ns.RecordExport.Decode(table.concat(R.ns.RecordExport.Build(doc), "\n"))
		T.eq(back.drift.rows[1][5], "spi", "round trip")
		finish(R)
	end,

	-- blocks saved by 0.7.10 and older have no f list: the export still works
	old_blocks_without_drift_export = function()
		local R = setup({}, {})
		R.ns.char.rec = { v = 1, next = 2, since = 0, askAt = 7200, sessions = 1,
			blocks = { { id = 1, s = 1, t0 = 0, a = 60, p = {}, c = {}, m = {}, d = {}, x = {}, k = {} } } }
		local doc = R.ns.RecordExport.Summary()
		T.eq(#doc.drift.rows, 0)
		finish(R)
	end,
}
