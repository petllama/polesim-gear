local T = require("t")
local FILES = { "Core.lua", "Data/Weights.lua", "Data/Suffixes.lua", "Data/Items.lua", "Items.lua", "Score.lua", "Bands.lua",
	"Equip.lua", "Sources.lua", "Route.lua", "Browser.lua", "BrowserUI.lua" }
local function ctx()
	return { cls = "priest", spec = "shadow", level = 20, faction = "H", classBit = 16, raceBit = 16 }
end
-- The window offline with permissive widgets (every Uppercase method a no-op unless set here); every
-- list it draws goes to onProvide. A Polestar Codex whose every item is a reward of quest 100.
local function window(onProvide)
	local W = require("wow")
	local function widget()
		local w = { scripts = {}, shown = false }
		return setmetatable(w, { __index = function(t, k)
			if type(k) == "string" and k:match("^%u") then return function() end end
		end })
	end
	local ns
	local function frame(kind, name)
		local f = widget()
		f.Show = function(self) self.shown = true if self.scripts.OnShow then self.scripts.OnShow(self) end end
		f.Hide = function(self) self.shown = false if self.scripts.OnHide then self.scripts.OnHide(self) end end
		f.SetShown = function(self, on) if on then self:Show() else self:Hide() end end
		f.IsShown = function(self) return self.shown end
		f.SetScript = function(self, k, fn) self.scripts[k] = fn end
		f.CreateFontString = function() local t = widget() t.SetText = function(s, v) s.text = v end return t end
		f.CreateTexture = function() return widget() end
		f.TitleText = widget()
		f.SetDataProvider = function(_, dp) onProvide(dp) end
		return f
	end
	_G.Polestar = { Codex = {
		Item = function(id) return { sources = { { type = "quest", quest = 100 } } } end,
		Quest = function(id) return { id = id, title = "Wanted", level = 10 } end,
		Load = function() return true end,
	} }
	ns = T.addon(FILES)
	_G.CreateFrame = frame
	_G.UIParent, _G.UISpecialFrames, _G.tinsert = frame(), {}, table.insert
	local view = widget()
	view.SetElementInitializer = function(_, _, init) view.init = init end
	_G.CreateScrollBoxListLinearView = function() return view end
	_G.ScrollUtil = { InitScrollBoxListWithScrollBar = function() end }
	_G.CreateDataProvider = function(t) return t end
	_G.GameTooltip_Hide = function() end
	ns.char = { spec = "auto" }
	ns.Spec = { ORDER = { priest = { "discipline", "holy", "shadow" } } }
	local band, lo, sd = ns.Bands.For("priest", "shadow", 20)
	ns.Context = {
		ClassKey = function() return "priest" end,
		Get = function() return { cls = "priest", spec = "shadow", level = 20, lo = lo, band = band, ref = sd.ref, w = band.w, worn = {},
			faction = "H", classBit = 16, raceBit = 16 } end,
		At = function(L) local b, l = ns.Bands.For("priest", "shadow", L) return { band = b, lo = l, w = b.w, worn = {} } end,
	}
	return { ns = ns, W = W, view = view, frame = frame }
end

return {
	-- The browser's data: nil (the window says why) without Polestar's Codex or when its pack can't load.
	env_needs_the_codex = function()
		_G.Polestar = nil
		local ns = T.addon(FILES)
		ns.Context = { Get = ctx, At = function() return nil end }
		T.eq(ns.BrowserUI.Env(), nil, "no Polestar")
		_G.Polestar = { Codex = { Item = function() end, Quest = function() end, Load = function() return false, "disabled" end } }
		T.eq(ns.BrowserUI.Env(), nil, "pack not loadable")
		_G.Polestar.Codex.Load = function() error("changed upstream") end
		T.eq(ns.BrowserUI.Env(), nil, "Load errors")
		_G.Polestar = nil
	end,
	env = function()
		local done = { [7] = true }
		_G.Polestar = { Codex = { Item = function() end, Quest = function() end, Load = function() return true end },
			Compat = { IsQuestCompleted = function(q) return done[q] == true end } }
		local ns = T.addon(FILES)
		ns.Context = { Get = ctx, At = function(L) return L == 21 and { w = { int = 1 }, worn = {}, band = { style = "any" } } or nil end }
		local e = ns.BrowserUI.Env()
		T.eq(e.level, 20); T.eq(e.player.faction, "H"); T.eq(e.player.raceBit, 16)
		T.ok(e.player.completed(7)); T.ok(not e.player.completed(8))
		T.eq(e.items.Get, ns.Items.Peek, "decoded on demand"); T.eq(e.items.Rl, ns.Items.Rl)
		T.eq(e.at(21).style, "any")
		T.eq(next(e.at(22).w), nil, "no band: nothing scores")
		_G.Polestar.Compat.IsQuestCompleted = function() error("changed upstream") end
		_G.C_QuestLog = { IsQuestFlaggedCompleted = function(q) return q == 9 end }
		T.ok(e.player.completed(9), "the client's answer when Polestar's errors"); T.ok(not e.player.completed(7))
		_G.Polestar, _G.C_QuestLog = nil, nil
	end,
	-- The window opens,
	-- builds over frames, lists rows, drills into a slot, closes and lets go of the model and the index.
	window_smoke = function()
		local provided
		local win = window(function(dp) provided = dp end)
		local ns, W, view, frame = win.ns, win.W, win.view, win.frame
		ns.Browser.KEEP = 1 -- a short list per kind: the drill-down offers "Show all (N)"
		SlashCmdList.POLESIMGEAR("")
		T.eq(provided[1].header, "Scoring items...")
		local n = 0
		while #W.timers > 0 and n < 10000 do W.flush() n = n + 1 end
		T.eq(provided[1].header, "Best per slot right now")
		T.ok(#provided > 5, "rows: " .. #provided)
		local row = frame()
		for _, d in ipairs(provided) do view.init(row, d) end
		local first = provided[2]
		T.ok(first.c and first.gain > 0)
		view.init(row, first)
		row.scripts.OnClick(row)
		T.eq(provided[1].header, first.slot.label .. ": every upgrade")
		for _, d in ipairs(provided) do view.init(row, d) end
		local more = provided[#provided]
		local total = 0
		local all = ns.Browser.SlotAll(ns.BrowserUI.Env(), first.slot.key)
		total = #all
		T.ok(total > #provided - 2, "more upgrades than kept: " .. total)
		T.ok(more.showAll, "the last row offers the rest"); T.eq(more.header, string.format("Show all (%d)", total))
		view.init(row, more)
		row.scripts.OnClick(row)
		n = 0
		while #W.timers > 0 and n < 10000 do W.flush() n = n + 1 end
		T.eq(#provided, total + 1, "every upgrade listed"); T.ok(not provided[#provided].showAll)
		T.eq(provided[2].c.id, all[1].c.id)
		for _, d in ipairs(provided) do view.init(row, d) end
		-- hover: the score sum, the gain, every source with "needs ... first"
		local lines = {}
		_G.GameTooltip = setmetatable({
			AddLine = function(_, t) lines[#lines + 1] = t end,
			AddDoubleLine = function(_, a, b) lines[#lines + 1] = a .. " = " .. b end,
		}, { __index = function(_, k) if k:match("^%u") then return function() end end end })
		view.init(row, provided[2])
		row.scripts.OnEnter(row)
		local text = table.concat(lines, "\n")
		T.ok(text:find("Score = ", 1, true), text)
		T.ok(text:find("Gain over what you wear = +", 1, true), text)
		T.ok(text:find("Quest: Wanted (10)", 1, true), text)
		local released = 0
		local rel = ns.Items.ReleaseIndex
		ns.Items.ReleaseIndex = function() released = released + 1 rel() end
		_G.PoleSimGear_OnAddonCompartmentClick()
		T.eq(released, 1, "closing releases the index")
		T.eq(ns.Items._cached(), 0, "nothing decoded kept")
		SlashCmdList.POLESIMGEAR("")
		T.eq(provided[1].header, "Scoring items...", "reopening builds again")
		_G.Polestar = nil
	end,
	-- A quest turned in while the window is open: its reward leaves the list (one rebuild, a moment
	-- later, for a burst of turn-ins); with the window closed nothing is built.
	turned_in_quest_rebuilds = function()
		local provided
		local win = window(function(dp) provided = dp end)
		local ns, W = win.ns, win.W
		local done = {}
		_G.Polestar.Compat = { IsQuestCompleted = function(q) return done[q] == true end }
		local function settle() local n = 0 while #W.timers > 0 and n < 10000 do W.flush() n = n + 1 end end
		local function event(...) ns._frame.scripts.OnEvent(ns._frame, "QUEST_TURNED_IN", ...) end
		SlashCmdList.POLESIMGEAR("")
		settle()
		T.ok(provided[2].c, "quest 100's rewards are listed")
		done[100] = true
		event(100, 50, 0)
		event(101, 50, 0)
		T.eq(#W.timers, 1, "one rebuild for the burst")
		settle()
		T.eq(provided[2].header, "nothing better than what you wear", "the turned-in quest's rewards are gone")
		SlashCmdList.POLESIMGEAR("") -- close
		local before = provided
		event(102, 50, 0)
		T.eq(#W.timers, 0, "closed: nothing queued"); T.eq(provided, before)
		_G.Polestar = nil
	end,
}
