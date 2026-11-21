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
		fx.done()
	end,
}
