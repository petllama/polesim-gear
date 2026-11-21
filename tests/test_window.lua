local T = require("t")
local F = require("winfix")
local function ctx()
	return { cls = "priest", spec = "shadow", level = 20, faction = "H", classBit = 16, raceBit = 16 }
end
return {
	env_needs_the_codex = function()
		local fx = F.load()
		local ns = fx.ns
		_G.Polestar = nil
		T.eq(ns.Window.Env(), nil, "no Polestar")
		_G.Polestar = { Codex = { Item = function() end, Quest = function() end, Load = function() return false, "disabled" end } }
		T.eq(ns.Window.Env(), nil, "pack not loadable")
		_G.Polestar.Codex.Load = function() error("changed upstream") end
		T.eq(ns.Window.Env(), nil, "Load errors")
		fx.done()
	end,
	env_keeps_picks_and_stars = function()
		local fx = F.load({ char = { plan = { shadow = { head = "10:3" }, holy = { neck = "11:0" } }, wish = { ["12:0"] = true } } })
		local e = fx.ns.Window.Env()
		T.eq(e.level, 20); T.eq(e.player.faction, "H"); T.eq(e.items.Get, fx.ns.Items.Peek)
		T.ok(e.keep["10:3"]); T.ok(e.keep["12:0"]); T.eq(e.keep["11:0"], nil, "another spec's pick")
		fx.done()
	end,
	opens_builds_tabs_closes = function()
		local fx = F.load()
		local ns = fx.ns
		SlashCmdList.POLESIMGEAR("")
		local f = _G.PoleSimGearFrame
		T.ok(f and f:IsShown()); T.ok(ns.Window.state.building, "building over frames")
		T.ok(fx.U.texts(f):find("PoleSim Gear", 1, true))
		T.eq(UISpecialFrames[1], "PoleSimGearFrame", "Escape closes")
		fx.settle()
		T.ok(ns.Window.state.model, "built"); T.eq(ns.Window.state.building, nil)
		for _, t in ipairs(ns.Window.TABS) do T.ok(fx.U.button(f, t.label), "tab " .. t.label) end
		fx.U.button(f, "Weights"):Click()
		T.eq(ns.Options.View().tab, "weights", "saved per character")
		T.eq(ns.Window.Panel("weights"):IsShown(), true)
		T.eq(ns.Window.Panel("plan"):IsShown(), false)
		local released = 0
		local rel = ns.Items.ReleaseIndex
		ns.Items.ReleaseIndex = function() released = released + 1 rel() end
		fx.U.button(f, "X"):Click()
		T.eq(f:IsShown(), false); T.eq(released, 1); T.eq(ns.Window.state.model, nil, "model let go")
		_G.PoleSimGear_OnAddonCompartmentClick()
		T.ok(f:IsShown(), "the compartment opens it"); T.eq(ns.Window.Panel("weights"):IsShown(), true, "on the saved tab")
		fx.done()
	end,
	build_error_says_so = function()
		local fx = F.load()
		local ns = fx.ns
		local reported = {}
		_G.geterrorhandler = function() return function(e) reported[#reported + 1] = e end end
		ns.Browser.Build = function(_, yield) yield() error("fatal") end
		fx.open()
		T.eq(#reported, 1); T.eq(ns.Window.state.building, nil)
		T.ok(ns.Window.state.why:find("could not be built", 1, true), ns.Window.state.why)
		fx.done()
	end,
	close_resets_the_route = function()
		local fx = F.load()
		local reads = 0
		_G.Polestar.Engine = { GetGuide = function() reads = reads + 1 return { steps = {} } end }
		fx.open(); T.eq(reads, 1)
		SlashCmdList.POLESIMGEAR(""); fx.open()
		T.eq(reads, 2, "read again after closing")
		fx.done()
	end,
	turned_in_quest_rebuilds_once = function()
		local fx = F.load()
		local ns, W = fx.ns, fx.W
		fx.open()
		local builds = 0
		local build = ns.Browser.Build
		ns.Browser.Build = function(...) builds = builds + 1 return build(...) end
		local function event(...) ns._frame.scripts.OnEvent(ns._frame, "QUEST_TURNED_IN", ...) end
		event(100, 50, 0); event(101, 50, 0)
		T.eq(#W.timers, 1, "one rebuild for the burst")
		fx.settle(); T.eq(builds, 1)
		SlashCmdList.POLESIMGEAR("") -- close
		event(102, 50, 0)
		T.eq(#W.timers, 0, "closed: nothing queued")
		fx.done()
	end,
	view_changes_do_not_rebuild = function()
		local fx = F.load()
		local ns = fx.ns
		fx.open()
		local builds = 0
		ns.Browser.Build = function() builds = builds + 1 return { now = {}, coming = {}, counts = {}, level = 20 } end
		ns.Fire("PLAN_CHANGED"); ns.Fire("WISHLIST_CHANGED"); ns.Fire("OPTIONS", "arrows", false)
		ns.Window.SetAhead(3); fx.settle()
		T.eq(builds, 0, "picks, stars, options and look ahead redraw only")
		ns.Fire("SCORES_CHANGED"); fx.settle()
		T.eq(builds, 1, "scores changed: rebuilt")
		fx.done()
	end,
	position_saved = function()
		local fx = F.load()
		local f = fx.open()
		f.points = { { "TOPLEFT", UIParent, "TOPLEFT", 100, -50 } }
		f.bar.scripts.OnDragStop(f.bar)
		T.eq(PoleSimGearDB.window.point, "TOPLEFT"); T.eq(PoleSimGearDB.window.x, 100)
		-- StopMovingOrSizing may anchor to another point of UIParent: the relative point is kept too
		f.points = { { "TOPLEFT", UIParent, "BOTTOMLEFT", 120, 600 } }
		f.bar.scripts.OnDragStop(f.bar)
		local w = PoleSimGearDB.window
		T.eq(w.point, "TOPLEFT"); T.eq(w.relPoint, "BOTTOMLEFT"); T.eq(w.x, 120); T.eq(w.y, 600)
		fx.done()
	end,
	position_restored = function()
		local fx = F.load({ db = { window = { point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = 120, y = 600 } } })
		local f = fx.open()
		local p = f.points[1]
		T.eq(p[1], "TOPLEFT"); T.eq(p[2], UIParent); T.eq(p[3], "BOTTOMLEFT"); T.eq(p[4], 120); T.eq(p[5], 600)
		fx.done()
		-- the older form (point, x, y): relative to the same point
		fx = F.load({ db = { window = { point = "TOP", x = 5, y = -40 } } })
		f = fx.open()
		p = f.points[1]
		T.eq(p[1], "TOP"); T.eq(p[3], "TOP"); T.eq(p[4], 5); T.eq(p[5], -40)
		T.eq(PoleSimGearDB.window.relPoint, "TOP", "migrated")
		fx.done()
	end,
	header = function()
		local fx = F.load({ worn = { [1] = { inst = { id = 1, name = "Hat", quality = 1 }, score = 1200.5 }, [5] = { inst = { id = 2, name = "Robe", quality = 2 }, score = 454.3 } } })
		local ns, U = fx.ns, fx.U
		T.eq(ns.Window.AheadText(0, 20), "Now"); T.eq(ns.Window.AheadText(1, 20), "+1 level (21)")
		T.eq(ns.Window.AheadText(5, 58), "+5 levels (60)", "capped at 60")
		local f = fx.open()
		local text = U.texts(f)
		T.ok(text:find("Level 20 Priest", 1, true), text); T.ok(text:find("Shadow (auto)", 1, true))
		T.ok(text:find("1,654.8", 1, true), "gear score"); T.ok(text:find("Gear plan progress", 1, true))
		-- 1 px gold frames around the addon icon and the class icon
		local gold = ns.Style.C.gold
		T.ok(f.iconFrame, "addon icon framed"); T.ok(f.header.classFrame, "class icon framed")
		for _, fr in ipairs({ f.iconFrame, f.header.classFrame }) do
			T.near(fr.border[1].color[1], gold[1]); T.near(fr.border[1].color[3], gold[3])
		end
		T.ok(text:match("%d+ / 15 %(%d+%%%)"), "progress text")
		local items = U.menu(f.header.ahead)
		T.eq(#items, 6); T.eq(items[1].text, "Now"); T.ok(items[1].isSelected())
		items[4].select()
		T.eq(ns.Options.View().ahead, 3); T.ok(items[4].isSelected())
		fx.done()
	end,
	left_panel = function()
		local fx = F.load()
		local ns, U, W = fx.ns, fx.U, fx.W
		local f = fx.open()
		local text = U.texts(f)
		for _, l in ipairs({ "Sources", "Quests", "Dungeons", "Crafting", "Vendor", "BoE / World", "Show", "All gear", "Upgrades only", "Wishlist" }) do
			T.ok(text:find(l, 1, true), l)
		end
		local world = U.button(f, "BoE / World")
		T.eq(world.on, false, "off by default")
		world:Click()
		T.eq(ns.Options.View().filters.world, true); T.eq(world.on, true, "redrawn")
		T.eq(#W.timers, 0, "no rebuild")
		U.button(f, "All gear"):Click()
		T.eq(ns.Options.View().show, "all"); T.eq(U.button(f, "All gear").on, true); T.eq(U.button(f, "Upgrades only").on, false)
		fx.done()
	end,
	bottom_strip = function()
		local fx = F.load()
		local ns, U = fx.ns, fx.U
		U.equipped[1] = "item:999001"
		local f = fx.open()
		local text = U.texts(f)
		T.ok(text:find("Equipped gear (1)", 1, true), text)
		T.ok(text:find("Stat weights (Shadow)", 1, true))
		T.ok(text:find("levels %d+%-%d+, points of"), "band line")
		T.eq(#f.slots, 17)
		local head = f.slots[1]
		head.scripts.OnEnter(head)
		T.eq(U.tip.inventory, 1, "the item's own tooltip")
		T.eq(head.badge.shown, true, "the head has a plan (an upgrade exists at level 20)")
		T.eq(head.badge.w, 10); T.eq(head.badge.h, 10); T.ok(head.badge.mask, "a round dot")
		f.pencil:Click()
		T.eq(ns.Options.View().tab, "weights")
		fx.done()
	end,
	row_tooltip = function()
		local fx = F.load({ char = { wish = { ["9:0"] = true }, plan = { shadow = { chest = "9:0" } } } })
		local ns, U = fx.ns, fx.U
		fx.open()
		local inst = { id = 9, name = "Robe", inv = 5, stats = { int = 5 }, quality = 2 }
		local r = { c = { id = 9, inst = inst, score = 5, sources = {
			{ kind = "quest", text = "Quest: X", where = "Westfall", needs = "First", route = 3 },
			{ kind = "world", text = "Drop: Ogre (18), 2%", zoneId = 1431 } }, kinds = { quest = true, world = true }, rl = 21 },
			gain = 2, at = 21, slot = ns.Browser.SLOTS[5] }
		local owner = U.new("Button")
		ns.Window.RowTooltip(owner, r, "Click: this slot's upgrades")
		local text = table.concat(U.tip.lines, "\n")
		for _, want in ipairs({ "Score = 5.00", "Gain over what you wear = +2.00", "Quest: X, Westfall", "needs: First first",
			"on your route (Polestar guide step 3)", "Drop: Ogre (18), 2%, Duskwood", "Your pick", "On your wishlist",
			"Click: this slot's upgrades", "weights of levels" }) do
			T.ok(text:find(want, 1, true), want .. " in\n" .. text)
		end
		ns.Context.At = function() return nil end
		ns.Window.RowTooltip(owner, r)
		text = table.concat(U.tip.lines, "\n")
		T.ok(not text:find(" x ", 1, true), "no band: no how?"); T.ok(not text:find("weights of levels", 1, true))
		fx.done()
	end,
	one_plan_pass_per_refresh = function()
		local fx = F.load()
		local ns = fx.ns
		fx.open()
		local calls = 0
		local pe = ns.View.PlanEntries
		ns.View.PlanEntries = function(...) calls = calls + 1 return pe(...) end
		ns.Window.Refresh()
		T.eq(calls, 1, "the strip and the Gear Plan tab share one pass")
		fx.done()
	end,
	open_refreshes_once = function()
		local fx = F.load()
		local ns = fx.ns
		local refreshes = 0
		local tabRefresh = ns.TabPlan.Refresh
		ns.Window.RegisterTab("plan", { create = ns.TabPlan.Create, refresh = function(p) refreshes = refreshes + 1 tabRefresh(p) end,
			release = ns.TabPlan.Release })
		SlashCmdList.POLESIMGEAR("")
		T.eq(refreshes, 1, "opening draws once (\"Scoring items...\")")
		fx.settle()
		T.eq(refreshes, 2, "and once more when built")
		fx.done()
	end,
	no_build_while_the_ui_is_hidden = function()
		local fx = F.load()
		local ns, W = fx.ns, fx.W
		fx.open()
		local builds = 0
		local build = ns.Browser.Build
		ns.Browser.Build = function(...) builds = builds + 1 return build(...) end
		UIParent:Hide() -- Alt+Z: the window is shown but not visible
		ns.Fire("SCORES_CHANGED"); ns.Fire("ROUTE_CHANGED")
		ns._frame.scripts.OnEvent(ns._frame, "QUEST_TURNED_IN", 100, 50, 0)
		fx.settle()
		T.eq(builds, 0, "nothing built while hidden"); T.eq(ns.Window.state.stale, true, "built when shown again")
		T.eq(#W.timers, 0)
		UIParent:Show()
		fx.done()
	end,
	pick_outside_the_model_rebuilds = function()
		local fx = F.load()
		local ns = fx.ns
		fx.open()
		local builds, keep = 0, nil
		local build = ns.Browser.Build
		ns.Browser.Build = function(env, ...) builds = builds + 1 keep = env.keep return build(env, ...) end
		local inModel = ns.Window.state.model.now.head[#ns.Window.state.model.now.head]
		ns.Plan.Set("shadow", "head", inModel.c.inst)
		ns.Wishlist.Toggle(inModel.c.inst)
		fx.settle()
		T.eq(builds, 0, "picked or starred from the model: redraw only")
		ns.Plan.Set("shadow", "neck", { id = 424242, bonus = 0 }) -- e.g. a Show all row the trim left out
		T.ok(ns.Window.state.model, "the old model stays shown while scoring again")
		fx.settle()
		T.eq(builds, 1, "a pick the model may not hold: built again"); T.ok(keep["424242:0"], "kept")
		ns.Wishlist.Toggle({ id = 424243, bonus = 0 })
		fx.settle()
		T.eq(builds, 2, "a star the model may not hold")
		ns.Wishlist.Toggle({ id = 424243, bonus = 0 })
		ns.Plan.Clear("shadow", "neck")
		fx.settle()
		T.eq(builds, 2, "unstarring and clearing: redraw only")
		fx.done()
	end,
	-- the first build (no model yet) was started without the pick: built again when it ends
	pick_during_the_first_build_rebuilds_after = function()
		local fx = F.load()
		local ns = fx.ns
		local builds, keep = 0, nil
		local build = ns.Browser.Build
		ns.Browser.Build = function(env, ...) builds = builds + 1 keep = env.keep return build(env, ...) end
		SlashCmdList.POLESIMGEAR("")
		T.ok(ns.Window.state.building and not ns.Window.state.model, "building the first model")
		ns.Plan.Set("shadow", "neck", { id = 424242, bonus = 0 })
		ns.Wishlist.Toggle({ id = 424243, bonus = 0 })
		fx.settle()
		T.eq(builds, 2, "built once more after the first build"); T.ok(keep["424242:0"]); T.ok(keep["424243:0"])
		T.ok(ns.Window.state.model); T.eq(ns.Window.state.stale, false)
		fx.done()
	end,
	-- a tab whose refresh errors: the error still reaches the client, the redraw's plan pass is dropped
	pass_cleared_when_a_tab_errors = function()
		local fx = F.load()
		local ns = fx.ns
		fx.open()
		ns.Window.RegisterTab("settings", { create = function(parent) return CreateFrame("Frame", nil, parent) end,
			refresh = function() error("tab broke") end })
		local ok, err = pcall(ns.Window.SetTab, "settings")
		T.eq(ok, false); T.ok(tostring(err):find("tab broke", 1, true), tostring(err))
		local calls = 0
		local pe = ns.View.PlanEntries
		ns.View.PlanEntries = function(...) calls = calls + 1 return pe(...) end
		ns.Window.PlanEntries("upgrades"); ns.Window.PlanEntries("upgrades")
		T.eq(calls, 2, "no stale pass outside a redraw")
		ns.View.PlanEntries = pe
		fx.done()
	end,
	-- the fixture's options for tools/fullload.lua: a level, the caller's Polestar, the minimap button
	fixture_options = function()
		local mine = { Codex = F.codex(), Compat = { IsQuestCompleted = function() return false end } }
		_G.Polestar = mine
		local fx = F.load({ codex = false, level = 34, minimap = true })
		local ns, U = fx.ns, fx.U
		T.eq(_G.Polestar, mine, "kept"); T.eq(ns.Context.Get().level, 34); T.eq(UnitLevel("player"), 34)
		T.ok(ns.Minimap.button, "the minimap button")
		ns.Minimap.button:Click("LeftButton"); fx.settle()
		T.ok(_G.PoleSimGearFrame:IsShown(), "opened from the minimap button")
		T.ok(U.texts(_G.PoleSimGearFrame):find("Level 34 Priest", 1, true))
		fx.done(); _G.Minimap = nil; require("wow").level = 20
	end,
	frames_made_once = function()
		local fx = F.load()
		local ns, U = fx.ns, fx.U
		local made = 0
		local cf = CreateFrame
		_G.CreateFrame = function(...) made = made + 1 return cf(...) end
		local f = fx.open()
		for _, t in ipairs(ns.Window.TABS) do ns.Window.SetTab(t.key) end
		ns.Window.SetTab("plan")
		local first = made
		T.ok(first > 0)
		for _ = 1, 3 do
			f:Hide(); fx.open()
			for _, t in ipairs(ns.Window.TABS) do ns.Window.SetTab(t.key) end
		end
		T.eq(made, first, "reopening and revisiting tabs makes no frame")
		_G.CreateFrame = cf
		fx.done()
	end,
}
