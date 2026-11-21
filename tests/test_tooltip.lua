local T = require("t")
local FILES = { "Core.lua", "Options.lua", "Data/Weights.lua", "Data/Suffixes.lua", "Data/Items.lua", "Items.lua", "Score.lua", "Equip.lua",
	"Sources.lua", "Browser.lua", "Wishlist.lua", "Tooltip.lua" }
local ctx = { cls = "priest", spec = "shadow", ref = "spShadow", lo = 30, band = { upTo = 39 }, level = 34,
	w = { int = 0.5, spShadow = 1 } }
local inst = { id = 1, inv = 1, stats = { int = 10, spShadow = 3 }, armor = 0, dps = 0, weapon = false, rl = 30 }
local function text(L)
	local out = {}
	for _, l in ipairs(L) do out[#out + 1] = l[1] .. "|" .. (l[2] or "") end
	return table.concat(out, "\n")
end
-- A client with GameTooltip and ItemRefTooltip modelled (shown item tooltips, Shift redraw), the
-- addon loaded, Context/Live stubbed: -> ns, GT, REF, show(tooltip, link) (runs the item post-call), key(name) (fires
-- MODIFIER_STATE_CHANGED)
local USABLE = { id = 1, inv = 1, c = 4, sc = 1, cm = 0, stats = { int = 10 }, armor = 0, dps = 0, rl = 30 }
local function client()
	local post
	local function tip()
		local t = { shown = true, kind = 0, refreshed = 0, lines = {}, hooks = {} }
		function t:IsShown() return self.shown end
		function t:RefreshData() self.refreshed = self.refreshed + 1 end
		function t:IsTooltipType(k) return self.kind == k end
		function t:HookScript(s, fn) self.hooks[s] = fn end
		function t:AddLine(s) self.lines[#self.lines + 1] = s end
		function t:AddDoubleLine(a, b) self.lines[#self.lines + 1] = a .. "|" .. b end
		return t
	end
	local GT, REF = tip(), tip()
	require("wow").install()
	_G.Enum = { TooltipDataType = { Item = 0, Unit = 2 } }
	_G.TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) if kind == 0 then post = fn _G.TooltipDataProcessor.post = fn end end }
	_G.TooltipUtil = { GetDisplayedItem = function(t) if t.kind == 0 then return "x", t.link end end }
	_G.GameTooltip, _G.ItemRefTooltip = GT, REF
	_G.IsShiftKeyDown = function() return false end
	_G.InCombatLockdown = function() return false end
	local ns = {}
	for _, f in ipairs(FILES) do assert(loadfile("PoleSimGear/" .. f))("PoleSimGear", ns) end
	ns.Context = { Get = function() return { cls = "priest", spec = "shadow", ref = "spShadow", lo = 30,
		band = { upTo = 39 }, level = 34, w = { int = 0.5, spShadow = 1 }, worn = {} } end }
	ns.Live = { Instance = function(link) if link == "cloth" or link == "item:1:cloth" then return USABLE end end }
	local function key(k) ns._frame.scripts.OnEvent(ns._frame, "MODIFIER_STATE_CHANGED", k, 1) end
	local function show(t, link) t.link, t.kind, t.shown, t.lines = link, 0, true, {} post(t) end
	return ns, GT, REF, show, key
end
local function unclient()
	_G.TooltipDataProcessor, _G.TooltipUtil, _G.Enum, _G.GameTooltip, _G.ItemRefTooltip = nil, nil, nil, nil, nil
	_G.InCombatLockdown = nil
end

return {
	-- Shift redraws only a shown item tooltip that carries our lines for the item it still shows.
	shift_redraws_our_item_tooltip = function()
		local _, GT, _, show, key = client()
		show(GT, "cloth")
		T.ok(#GT.lines > 0, "drawn")
		key("LSHIFT"); key("RSHIFT")
		T.eq(GT.refreshed, 2)
		unclient()
	end,
	shift_skips_non_item_or_other_tooltips = function()
		local _, GT, _, show, key = client()
		key("LSHIFT")
		T.eq(GT.refreshed, 0, "shown but never drawn by us")
		show(GT, "cloth")
		GT.kind = 2 -- now a unit tooltip
		key("LSHIFT")
		T.eq(GT.refreshed, 0, "unit tooltip")
		show(GT, "plate") -- an item we add nothing to
		key("LSHIFT")
		T.eq(GT.refreshed, 0, "another item, not ours")
		show(GT, "cloth"); GT.shown = false
		key("LSHIFT")
		T.eq(GT.refreshed, 0, "hidden")
		unclient()
	end,
	shift_cleared_on_hide = function()
		local _, GT, _, show, key = client()
		show(GT, "cloth")
		T.ok(GT.hooks.OnHide, "OnHide hooked")
		GT.hooks.OnHide(GT)
		key("LSHIFT")
		T.eq(GT.refreshed, 0)
		unclient()
	end,
	other_keys_ignored = function()
		local _, GT, _, show, key = client()
		show(GT, "cloth")
		key("LCTRL"); key("LALT")
		T.eq(GT.refreshed, 0)
		unclient()
	end,
	shift_skipped_in_combat = function()
		local _, GT, _, show, key = client()
		show(GT, "cloth")
		_G.InCombatLockdown = function() return true end
		key("LSHIFT")
		T.eq(GT.refreshed, 0)
		unclient()
	end,
	shift_redraws_item_ref_tooltip = function()
		local _, GT, REF, show, key = client()
		show(REF, "cloth")
		key("LSHIFT")
		T.eq(REF.refreshed, 1); T.eq(GT.refreshed, 0)
		unclient()
	end,
	-- The hover path: an item's instance and comparison are kept until scores change.
	hover_cached_until_scores_change = function()
		local ns, GT, _, show = client()
		local calls, live = 0, ns.Live.Instance
		ns.Live.Instance = function(link) calls = calls + 1 return live(link) end
		show(GT, "cloth"); show(GT, "cloth")
		T.eq(calls, 1)
		T.ok(#GT.lines > 0, "drawn from the cache")
		show(GT, "plate"); show(GT, "plate")
		T.eq(calls, 2, "an item we add nothing to is kept too")
		ns.Fire("SCORES_CHANGED")
		show(GT, "cloth")
		T.eq(calls, 3)
		unclient()
	end,
	-- Built from the shipped table while the client has no stats yet: drawn, not kept (the next hover
	-- reads the client again).
	hover_from_table_not_cached = function()
		local ns, GT, _, show = client()
		local calls = 0
		local fromTable = { id = 1, inv = 1, c = 4, sc = 1, cm = 0, stats = { int = 10 }, armor = 0, dps = 0, rl = 30, fromTable = true }
		ns.Live.Instance = function() calls = calls + 1 return fromTable end
		show(GT, "cloth")
		T.ok(#GT.lines > 0, "drawn")
		show(GT, "cloth")
		T.eq(calls, 2)
		unclient()
	end,
	hover_pending_not_cached = function()
		local ns, GT, _, show = client()
		local calls = 0
		ns.Live.Instance = function() calls = calls + 1 return nil, "pending" end
		show(GT, "cloth"); show(GT, "cloth")
		T.eq(calls, 2)
		unclient()
	end,
	-- A Lua error while drawing an item is reported once per link per session, not on every redraw.
	error_reported_once_per_link = function()
		local ns, GT, _, show = client()
		local reported = 0
		_G.geterrorhandler = function() return function() reported = reported + 1 end end
		ns.Live.Instance = function() error("boom") end
		show(GT, "cloth"); show(GT, "cloth")
		T.eq(reported, 1)
		show(GT, "other")
		T.eq(reported, 2)
		unclient()
	end,
	-- The post-call's own tooltip data gives the link (hyperlink, or the GUID of a bag/worn item);
	-- the displayed item only when the data has neither.
	link_from_tooltip_data = function()
		local ns, GT = client()
		local seen = {}
		ns.Tooltip.Add = function(_, link) seen[#seen + 1] = link end
		_G.C_Item = { GetItemLinkByGUID = function(g) return g == "G1" and "fromguid" or nil end }
		local post = _G.TooltipDataProcessor.post
		GT.link = "displayed"
		post(GT, { hyperlink = "fromdata" })
		post(GT, { guid = "G1" })
		post(GT, { hyperlink = "" })
		post(GT, nil)
		T.eq(table.concat(seen, ","), "fromdata,fromguid,displayed,displayed")
		_G.C_Item = nil
		unclient()
	end,
	short = function()
		local L = T.addon(FILES).Tooltip.Lines({ score = 8, gain = 2, base = 6 }, inst, ctx, false, false)
		T.eq(L[1][1], "Score 8.0"); T.eq(L[1][2], "+2.0 (+33%)")
		T.eq(L[2][1], "Shadow, levels 30-39: points of Shadow spell damage")
		T.eq(L[#L][1], "Shift: how?")
	end,
	label_and_equipped = function()
		local L = T.addon(FILES).Tooltip.Lines({ score = 8, gain = 0, base = 8, equipped = true }, inst, ctx, false, true)
		T.eq(L[1][1], "PoleSim score 8.0"); T.eq(L[1][2], "equipped")
	end,
	how = function()
		local L = T.addon(FILES).Tooltip.Lines({ score = 8, gain = 2, base = 6, note = "against your weaker one" }, inst, ctx, true, false)
		local s = text(L)
		T.ok(s:find("Intellect 10 x 0.5", 1, true), s)
		T.ok(s:find("Shadow spell damage 3 x 1|3.00", 1, true), s)
		T.ok(s:find("minus worn|6.00", 1, true), s)
		T.ok(s:find("against your weaker one", 1, true), s)
	end,
	future_level = function()
		local far = { id = 2, inv = 1, stats = {}, armor = 0, dps = 0, rl = 37 }
		local L = T.addon(FILES).Tooltip.Lines({ score = 1, gain = 1, base = 0 }, far, ctx, false, false)
		T.eq(L[1][2], "+1.0")
		T.ok(L[3][1]:find("requires level 37", 1, true))
	end,
	-- An equip bonus the client did not report (filled from the item table) says so in the how? sum.
	filled_labelled = function()
		local filled = { id = 3, inv = 1, stats = { int = 10, spShadow = 3 }, armor = 0, dps = 0, rl = 30, filled = { spShadow = true } }
		local s = text(T.addon(FILES).Tooltip.Lines({ score = 8, gain = 2, base = 6 }, filled, ctx, true, false))
		T.ok(s:find("Shadow spell damage 3 x 1 (item table)|3.00", 1, true), s)
		T.ok(s:find("Intellect 10 x 0.5|", 1, true), s)
		T.ok(not s:find("Intellect 10 x 0.5 (item table)", 1, true), s)
	end,
	-- Tooltip.Add: lines for an item the character can use (up to 5 levels above), none otherwise.
	add = function()
		local ns = T.addon(FILES)
		local c = { cls = "priest", spec = "shadow", ref = "spShadow", lo = 30, band = { upTo = 39 }, level = 34,
			w = { int = 0.5, spShadow = 1 }, worn = {} }
		ns.Context = { Get = function() return c end }
		local items = {
			cloth = { id = 1, inv = 1, c = 4, sc = 1, cm = 0, stats = { int = 10 }, armor = 0, dps = 0, rl = 30 },
			plate = { id = 2, inv = 1, c = 4, sc = 4, cm = 0, stats = { int = 10 }, armor = 0, dps = 0, rl = 30 },
			far = { id = 3, inv = 1, c = 4, sc = 1, cm = 0, stats = { int = 10 }, armor = 0, dps = 0, rl = 40 },
			near = { id = 4, inv = 1, c = 4, sc = 1, cm = 0, stats = { int = 10 }, armor = 0, dps = 0, rl = 39 },
		}
		ns.Live = { Instance = function(link) return items[link] end }
		_G.IsShiftKeyDown = function() return false end
		local function tip()
			local t = { lines = {} }
			function t:AddLine(s) self.lines[#self.lines + 1] = s end
			function t:AddDoubleLine(a, b) self.lines[#self.lines + 1] = a .. "|" .. b end
			return t
		end
		local t = tip()
		ns.Tooltip.Add(t, "cloth")
		T.eq(t.lines[1], "Score 5.0|+5.0"); T.eq(t.lines[#t.lines], "Shift: how?")
		t = tip(); ns.Tooltip.Add(t, "plate"); T.eq(#t.lines, 0, "priest wears no plate")
		t = tip(); ns.Tooltip.Add(t, "far"); T.eq(#t.lines, 0, "more than 5 levels above")
		t = tip(); ns.Tooltip.Add(t, "near"); T.ok(#t.lines > 0, "5 levels above")
		t = tip(); ns.Tooltip.Add(t, nil); T.eq(#t.lines, 0)
		ns.Context = { Get = function() return nil end }
		t = tip(); ns.Tooltip.Add(t, "cloth"); T.eq(#t.lines, 0, "no weights for this class")
	end,
	-- An upcoming quest reward on the Polestar route: one blue line (Route.ItemLine), score or not.
	route_line = function()
		local ns = T.addon(FILES)
		ns.Context = { Get = function() return nil end }
		ns.Route = { ItemLine = function(id) return id == 77 and "Polestar: in 12 steps (Assault on Fenris Isle)" or nil end }
		local t = { lines = {} }
		function t:AddLine(s, r, g, b) self.lines[#self.lines + 1] = s; self.blue = b end
		ns.Tooltip.Add(t, "|cff1eff00|Hitem:77::::|h[Robe]|h|r")
		T.eq(t.lines[1], "Polestar: in 12 steps (Assault on Fenris Isle)"); T.eq(t.blue, 1)
		t.lines = {}
		ns.Tooltip.Add(t, "|cff1eff00|Hitem:78::::|h[Robe]|h|r")
		T.eq(#t.lines, 0)
	end,
	-- The client hook: GameTooltip and ItemRefTooltip only, forbidden tooltips skipped.
	hook = function()
		local post
		local GT, REF, CMP = {}, {}, {}
		local function setup()
			_G.Enum = { TooltipDataType = { Item = 0 } }
			_G.TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) if kind == 0 then post = fn _G.TooltipDataProcessor.post = fn end end }
			_G.TooltipUtil = { GetDisplayedItem = function(t) return "x", t.link end }
			_G.GameTooltip, _G.ItemRefTooltip = GT, REF
		end
		require("wow").install()
		setup()
		local ns = {}
		for _, f in ipairs(FILES) do assert(loadfile("PoleSimGear/" .. f))("PoleSimGear", ns) end
		T.ok(post, "registered")
		local seen = {}
		ns.Tooltip.Add = function(t, link) seen[#seen + 1] = link end
		GT.link, REF.link, CMP.link = "a", "b", "c"
		post(GT); post(REF); post(CMP)
		T.eq(table.concat(seen, ","), "a,b", "not the comparison tooltips")
		GT.IsForbidden = function() return true end
		post(GT)
		T.eq(#seen, 2, "forbidden")
		_G.TooltipDataProcessor, _G.TooltipUtil, _G.Enum, _G.GameTooltip, _G.ItemRefTooltip = nil, nil, nil, nil, nil
	end,
	switch_off_no_line = function()
		local ns, GT = client()
		ns.Options.Set("tooltip", false)
		GT.lines = {}
		ns.Tooltip.Add(GT, "cloth")
		T.eq(#GT.lines, 0, "tooltip line off")
		ns.Options.Set("tooltip", true)
		ns.Tooltip.Add(GT, "cloth")
		T.ok(#GT.lines > 0)
		unclient()
	end,
	wishlist_star = function()
		local ns, GT = client()
		_G.PoleSimGearDB, _G.PoleSimGearCharDB = {}, { wish = { ["1:0"] = true } }
		ns._frame.scripts.OnEvent(ns._frame, "ADDON_LOADED", "PoleSimGear")
		GT.lines = {}
		ns.Tooltip.Add(GT, "item:1:cloth") -- USABLE has id 1
		local text = table.concat(GT.lines, "\n")
		T.ok(text:find("On your PoleSim wishlist", 1, true), text)
		unclient()
	end,
	-- The star line is the player's own mark: shown for any starred item, scored or not, switch on or off.
	wishlist_star_always = function()
		local ns, GT = client()
		_G.PoleSimGearDB, _G.PoleSimGearCharDB = {}, { wish = { ["1:0"] = true, ["7:0"] = true } }
		ns._frame.scripts.OnEvent(ns._frame, "ADDON_LOADED", "PoleSimGear")
		GT.lines = {}
		ns.Tooltip.Add(GT, "item:7:plate") -- not a scored hit (Live gives nothing)
		T.eq(#GT.lines, 1, "only the star line"); T.ok(GT.lines[1]:find("On your PoleSim wishlist", 1, true))
		ns.Options.Set("tooltip", false)
		GT.lines = {}
		ns.Tooltip.Add(GT, "item:1:cloth")
		T.eq(#GT.lines, 1, "score lines off, the star line stays"); T.ok(GT.lines[1]:find("On your PoleSim wishlist", 1, true))
		GT.lines = {}
		ns.Tooltip.Add(GT, "item:8:plate")
		T.eq(#GT.lines, 0, "not starred")
		ns.Options.Set("tooltip", true)
		unclient()
	end,
}
