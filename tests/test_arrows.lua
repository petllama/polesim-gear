local T = require("t")
local FILES = { "Core.lua", "Data/Weights.lua", "Data/Suffixes.lua", "Data/Items.lua", "Items.lua", "Score.lua", "Equip.lua", "Arrows.lua" }
local WITH_TOOLTIP = { "Core.lua", "Data/Weights.lua", "Data/Suffixes.lua", "Data/Items.lua", "Items.lua", "Score.lua", "Equip.lua",
	"Tooltip.lua", "Arrows.lua" }
local ctx = { cls = "priest", level = 20, w = { int = 1 }, worn = { [1] = { inst = { id = 9, inv = 1 }, score = 5 } } }
local function head(int, rl) return { id = 1, inv = 1, c = 4, sc = 1, cm = 0, rl = rl or 10, stats = { int = int }, armor = 0, dps = 0 } end

-- The addon with Tooltip and Arrows, Context and Live stubbed: -> ns, calls (Live.Instance count by link)
local function live(items)
	local ns = T.addon(WITH_TOOLTIP)
	local calls = {}
	ns.Context = { Get = function() return ctx end }
	ns.Live = { Instance = function(link)
		calls[link] = (calls[link] or 0) + 1
		local v = items[link]
		if v == "pending" then return nil, "pending" end
		return v
	end }
	return ns, calls
end

return {
	is_upgrade = function()
		local A = T.addon(FILES).Arrows
		T.ok(A.IsUpgrade(head(6), ctx))
		T.ok(not A.IsUpgrade(head(5), ctx), "equal")
		T.ok(not A.IsUpgrade(head(9, 21), ctx), "level 21")
		local mail = head(9); mail.sc = 3
		T.ok(not A.IsUpgrade(mail, ctx), "mail")
	end,
	-- The arrow's verdict comes from the tooltip's per-link result: one Live read and one comparison
	-- per link, shared by hover and arrows, until scores change.
	verdict_shares_the_tooltip_cache = function()
		local ns, calls = live({ up = head(6), down = head(4), later = head(9, 23) })
		T.eq(ns.Arrows.Verdict("up"), true)
		T.eq(ns.Arrows.Verdict("up"), true)
		T.eq(ns.Arrows.Verdict("down"), false)
		T.eq(ns.Arrows.Verdict("later"), false, "needs level 23: a tooltip line, no arrow")
		T.eq(calls.up, 1, "one read per link")
		local hit = ns.Tooltip.Lookup("up", ctx)
		T.ok(hit and hit[2].gain > 0, "the hover path reads the same entry")
		T.eq(calls.up, 1, "the hover path did not read again")
		ns.Fire("SCORES_CHANGED")
		ns.Arrows.Verdict("up")
		T.eq(calls.up, 2, "read again after scores changed")
		T.eq(ns.Arrows.Verdict(nil), false)
	end,
	verdict_pending_read_again = function()
		local ns, calls = live({ wait = "pending" })
		T.eq(ns.Arrows.Verdict("wait"), false)
		T.eq(ns.Arrows.Verdict("wait"), false)
		T.eq(calls.wait, 2)
	end,
	-- Auction browse rows: by item id; a random-suffix item gets none (the row is every suffix).
	verdict_by_id = function()
		local ns = live({})
		local seen
		ns.Arrows.Verdict = function(link) seen = link return true end
		T.eq(ns.Arrows.VerdictByID(6540), false, "Willow Pants: random suffix")
		T.eq(seen, nil)
		T.eq(ns.Arrows.VerdictByID(11288), true)
		T.eq(seen, "item:11288")
	end,
	-- The arrow is our own texture on the button, made once, shown and hidden.
	mark = function()
		local A = T.addon(FILES).Arrows
		local made = 0
		local tex = { shown = false }
		function tex:SetAtlas() end
		function tex:SetPoint() end
		function tex:SetShown(v) self.shown = v end
		local button = { CreateTexture = function() made = made + 1 return tex end }
		A.Mark(button, false)
		T.eq(made, 0, "nothing made for no arrow")
		A.Mark(button, true); A.Mark(button, true)
		T.eq(made, 1); T.eq(tex.shown, true)
		A.Mark(button, false)
		T.eq(tex.shown, false)
	end,
	-- New scores redraw the shown buttons once (not per event); item data redraws only when an arrow
	-- waited for that item.
	redraw_debounced = function()
		local W = require("wow")
		local ns = live({ ["item:7"] = "pending" })
		local n = 0
		ns.Arrows.OnRedraw(function() n = n + 1 end)
		ns.Fire("SCORES_CHANGED"); ns.Fire("SCORES_CHANGED")
		W.flush()
		T.eq(n, 1, "one redraw")
		local function info(id) ns._frame.scripts.OnEvent(ns._frame, "GET_ITEM_INFO_RECEIVED", id, true) end
		info(5)
		W.flush()
		T.eq(n, 1, "no arrow waited for item 5")
		ns.Arrows.Verdict("item:7")
		info(7); info(7)
		W.flush()
		T.eq(n, 2, "item 7 was pending: one redraw")
	end,
}
