local T = require("t")
local F = require("winfix")
return {
	pills = function()
		local fx = F.load()
		local ns, U = fx.ns, fx.U
		fx.open()
		local calls = 0
		local build = ns.Groups.Build
		ns.Groups.Build = function(...) calls = calls + 1 return build(...) end
		ns.Window.SetTab("sources")
		local p = ns.Window.Panel("sources")
		local text = U.texts(p)
		for _, l in ipairs({ "Dungeons", "Quests", "Crafting", "Vendors", "BoE / World" }) do T.ok(text:find(l .. " %d+"), l .. " in " .. text) end
		T.eq(calls, 1)
		ns.Window.Refresh()
		T.eq(calls, 1, "cached")
		ns.Window.SetAhead(2)
		T.eq(calls, 2, "regrouped for the new look ahead")
		SlashCmdList.POLESIMGEAR("")
		T.eq(ns.Window.state.groups, nil, "dropped on close")
		fx.done()
	end,
	groups_list = function()
		local fx = F.load()
		local ns, U = fx.ns, fx.U
		fx.open()
		ns.Window.SetTab("sources")
		local p = ns.Window.Panel("sources")
		local rows = U.rows(p.groups)
		T.eq(#rows, 1, "the fixture has one dungeon"); T.ok(U.texts(rows[1]):find("The Deadmines", 1, true))
		T.ok(U.texts(rows[1]):find("levels 16%-21"), U.texts(rows[1]))
		T.ok(rows[1].d.selected, "the first place is chosen")
		ns.TabSources.view.kind = "quest"; ns.TabSources.view.group = nil; ns.Window.Refresh()
		rows = U.rows(p.groups)
		T.ok(U.texts(rows[1]):find("Westfall", 1, true)); T.ok(U.texts(rows[1]):find("%d+ quests?"))
		U.button(p, "BoE / World " .. #ns.Window.state.groups.world):Click()
		rows = U.rows(p.groups)
		T.eq(#rows, 1); T.ok(U.texts(rows[1]):find("no place", 1, true))
		fx.done()
	end,
}
