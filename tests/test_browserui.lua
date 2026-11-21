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
	-- A build that fails (not one item: the whole pass) is reported, and the window leaves "Scoring
	-- items..." for a message saying so; so does "Show all".
	build_error_leaves_scoring = function()
		local provided
		local win = window(function(dp) provided = dp end)
		local ns, W = win.ns, win.W
		ns.Browser.KEEP = 1 -- the drill-down offers "Show all"
		local reported = {}
		_G.geterrorhandler = function() return function(e) reported[#reported + 1] = e end end
		local build = ns.Browser.Build
		ns.Browser.Build = function(_, yield) yield() error("fatal") end
		SlashCmdList.POLESIMGEAR("")
		T.eq(provided[1].header, "Scoring items...")
		local n = 0
		while #W.timers > 0 and n < 100 do W.flush() n = n + 1 end
		T.eq(#reported, 1)
		T.ok(provided[1].header ~= "Scoring items...", "left Scoring")
		T.ok(provided[1].header:find("could not be built", 1, true), provided[1].header)
		-- failing in its first step (inside Start) too
		ns.Browser.Build = function() error("fatal at once") end
		SlashCmdList.POLESIMGEAR("") -- close
		SlashCmdList.POLESIMGEAR("")
		T.eq(#reported, 2)
		T.ok(provided[1].header:find("could not be built", 1, true), provided[1].header)
		-- Show all fails: its "Scoring every upgrade..." row goes too
		ns.Browser.Build = build
		SlashCmdList.POLESIMGEAR("") -- close
		SlashCmdList.POLESIMGEAR("")
		n = 0
		while #W.timers > 0 and n < 10000 do W.flush() n = n + 1 end
		local row = win.frame()
		local key = provided[2].slot.key
		win.view.init(row, provided[2])
		row.scripts.OnClick(row)
		ns.Browser.SlotAll = function(_, _, yield) yield() error("fatal all") end
		ns.BrowserUI.ShowAll(key)
		T.eq(provided[#provided].header, "Scoring every upgrade...")
		n = 0
		while #W.timers > 0 and n < 100 do W.flush() n = n + 1 end
		T.ok(provided[#provided].header ~= "Scoring every upgrade...", provided[#provided].header)
		local last = provided[#provided].header
		T.ok(last:find("could not be scored (error reported)", 1, true), last)
		_G.Polestar = nil
	end,
	-- Closing the window forgets the route map too (Route.Reset): reopening reads the active guide again.
	close_resets_the_route = function()
		local provided
		local win = window(function(dp) provided = dp end)
		local ns, W = win.ns, win.W
		local reads = 0
		_G.Polestar.Engine = { GetGuide = function() reads = reads + 1 return { steps = {} } end }
		local function settle() local n = 0 while #W.timers > 0 and n < 10000 do W.flush() n = n + 1 end end
		SlashCmdList.POLESIMGEAR("")
		settle()
		T.eq(reads, 1)
		SlashCmdList.POLESIMGEAR("") -- close
		SlashCmdList.POLESIMGEAR("")
		settle()
		T.eq(reads, 2, "read again after closing")
		_G.Polestar = nil
	end,
	-- A "coming up" row whose level has no band (Context.At nil): the tooltip shows no "how?" (no stat
	-- lines, no band line) rather than the current band's weights.
	tooltip_without_a_band = function()
		local win = window(function() end)
		local ns = win.ns
		SlashCmdList.POLESIMGEAR("")
		local lines = {}
		_G.GameTooltip = setmetatable({
			AddLine = function(_, t) lines[#lines + 1] = t end,
			AddDoubleLine = function(_, a, b) lines[#lines + 1] = a .. " = " .. b end,
		}, { __index = function(_, k) if k:match("^%u") then return function() end end end })
		local inst = { id = 9, name = "Robe", inv = 5, stats = { int = 5 }, quality = 2 }
		local data = { c = { id = 9, inst = inst, score = 5, sources = { { text = "Quest: X" } }, kinds = { quest = true }, rl = 21 },
			gain = 2, at = 21, slot = ns.Browser.SLOTS[5] }
		local row = win.frame()
		ns.Context.At = function() return nil end
		win.view.init(row, data)
		row.scripts.OnEnter(row)
		local text = table.concat(lines, "\n")
		T.ok(not text:find(" x ", 1, true), text)
		T.ok(not text:find("weights of levels", 1, true), text)
		T.ok(text:find("Gain over what you wear", 1, true), text)
		T.ok(text:find("Quest: X", 1, true), text)
		lines = {}
		ns.Context.At = function(L) local b, l = ns.Bands.For("priest", "shadow", L) return { band = b, lo = l, w = b.w, worn = {} } end
		row.scripts.OnEnter(row)
		text = table.concat(lines, "\n")
		T.ok(text:find(" x ", 1, true), "with a band: the how? " .. text)
		_G.Polestar = nil
	end,
	-- A pooled row reused for another entry resets its icon, texts, tag and gain; plain header rows get no
	-- hover highlight ("Show all", which can be clicked, and item rows do).
	reused_row_resets = function()
		local win = window(function() end)
		local ns = win.ns
		SlashCmdList.POLESIMGEAR("")
		local row = win.frame()
		local hl = { alpha = 1, SetAlpha = function(self, a) self.alpha = a end }
		row.SetHighlightTexture = function(self) self.hl = hl end
		row.GetHighlightTexture = function(self) return self.hl end
		local icon
		row.CreateTexture = function()
			icon = { shown = true, Show = function(s) s.shown = true end, Hide = function(s) s.shown = false end,
				SetTexture = function(s, t) s.tex = t end, SetSize = function() end, SetPoint = function() end }
			return icon
		end
		local inst = { id = 9, name = "Robe", inv = 5, stats = {}, quality = 2, icon = "INV_Chest_Cloth_01" }
		local item = { c = { id = 9, inst = inst, score = 5, sources = { { text = "Quest: X", route = 3 } }, kinds = { quest = true }, rl = 18 },
			gain = 2, slot = ns.Browser.SLOTS[5] }
		win.view.init(row, item)
		T.ok(icon.shown); T.ok(icon.tex:find("INV_Chest_Cloth_01", 1, true))
		T.eq(row.slotText.text, "Chest"); T.ok(row.tag.text:find("Quest", 1, true)); T.ok(row.gain.text:find("+2.0", 1, true))
		T.eq(hl.alpha, 1)
		win.view.init(row, { header = "Coming up" })
		T.ok(not icon.shown, "icon hidden"); T.eq(row.slotText.text, ""); T.eq(row.tag.text, ""); T.eq(row.gain.text, "")
		T.ok(row.name.text:find("Coming up", 1, true))
		T.eq(hl.alpha, 0, "no highlight on a header")
		win.view.init(row, { header = "Show all (9)", showAll = true })
		T.eq(hl.alpha, 1, "Show all can be clicked")
		inst.icon = nil
		item.c.sources[1].route = nil
		item.gain = 1
		win.view.init(row, item)
		T.ok(icon.shown); T.ok(icon.tex:find("QuestionMark", 1, true), "no icon: the question mark")
		T.ok(not row.tag.text:find("route", 1, true), "route tag gone"); T.ok(row.gain.text:find("+1.0", 1, true))
		T.eq(hl.alpha, 1)
		_G.Polestar = nil
	end,
	-- No context any more (Context.Get nil): the info line and the spec button are cleared, not left
	-- with the last character's text.
	no_context_clears_info = function()
		local win = window(function() end)
		local ns = win.ns
		local made = {}
		local create = _G.CreateFrame
		_G.CreateFrame = function(kind, name, ...)
			local f = create(kind, name, ...)
			f.SetText = function(self, v) self.text = v end
			made[#made + 1] = f
			if name then made[name] = f end
			return f
		end
		SlashCmdList.POLESIMGEAR("")
		local f = made.PoleSimGearFrame
		local spec = made[2]
		T.ok(f.info.text and f.info.text:find("level 20", 1, true), tostring(f.info.text))
		T.ok(spec.text and spec.text:find("Spec", 1, true), tostring(spec.text))
		ns.Context.Get = function() return nil end
		ns.BrowserUI.Refresh()
		T.eq(f.info.text, ""); T.eq(spec.text, "")
		_G.Polestar = nil
	end,
	-- "Show all" when the browser's data is not available (Env fails): the row says why.
	show_all_says_why = function()
		local provided
		local win = window(function(dp) provided = dp end)
		local ns, W = win.ns, win.W
		ns.Browser.KEEP = 1
		SlashCmdList.POLESIMGEAR("")
		local n = 0
		while #W.timers > 0 and n < 10000 do W.flush() n = n + 1 end
		local row = win.frame()
		local key = provided[2].slot.key
		win.view.init(row, provided[2])
		row.scripts.OnClick(row)
		_G.Polestar.Codex.Load = function() return false end
		ns.BrowserUI.ShowAll(key)
		local last = provided[#provided].header
		T.ok(last and last:find("could not be loaded", 1, true), tostring(last))
		_G.Polestar = nil
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
