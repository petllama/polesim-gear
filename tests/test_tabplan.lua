local T = require("t")
local F = require("winfix")
local function rowsOf(fx) return fx.U.rows(fx.ns.Window.Panel("plan").list) end
return {
	upgrades_rows = function()
		local fx = F.load()
		local ns, U = fx.ns, fx.U
		local f = fx.open()
		local p = ns.Window.Panel("plan")
		T.ok(p:IsShown(), "the default tab")
		local head = U.texts(p.header)
		for _, h in ipairs({ "Priority", "Slot", "Current item", "Plan", "Gain", "Gain %", "Source" }) do T.ok(head:find(h, 1, true), h) end
		local rows = rowsOf(fx)
		T.ok(#rows >= 10, "most slots have an upgrade at 20 with only a hat worn: " .. #rows)
		local r1 = rows[1]
		T.eq(r1.badge.text.text, "1"); T.near(r1.badge.bg.color[1], ns.Style.C.badgeGold[1])
		T.eq(rows[4].badge.text.text, "4"); T.near(rows[4].badge.bg.color[1], ns.Style.C.badgeGrey[1])
		T.ok(r1.delta.text:match("^%+%d"), r1.delta.text)
		local gains = {}
		for i, r in ipairs(rows) do gains[i] = r.e.entry.plan.gain end
		for i = 2, #gains do T.ok(gains[i - 1] >= gains[i], "sorted by gain") end
		local headRow
		for _, r in ipairs(rows) do if r.e.def.key == "head" then headRow = r end end
		T.ok(headRow.cur.name.text:find("Old Hat", 1, true)); T.eq(headRow.curScore.text, "1.0")
		T.ok(headRow.pct.text:find("%%"), "a % against the worn score")
		T.ok(headRow.kind.text ~= "", "source kind")
		fx.done()
	end,
	empty_states = function()
		local fx = F.load()
		local ns = fx.ns
		SlashCmdList.POLESIMGEAR("")
		local p = ns.Window.Panel("plan")
		T.eq(p.list.provided[1].empty, "Scoring items...")
		fx.settle()
		for _, k in ipairs({ "quest", "dungeon", "crafted", "vendor", "world" }) do ns.Options.View().filters[k] = false end
		ns.Window.Refresh()
		T.eq(p.list.provided[1].empty, "No upgrades from the ticked sources.")
		fx.done()
	end,
	picks = function()
		local fx = F.load()
		local ns, U = fx.ns, fx.U
		fx.open()
		local rows = rowsOf(fx)
		local r = rows[1]
		local key = r.e.def.key
		-- choose the slot's last listed upgrade, as Slot Upgrades' "Set as plan" does
		local list = ns.Browser.SlotRows(ns.Window.state.model, key, 0, ns.Options.View().filters)
		T.ok(#list >= 2, "the top slot has several upgrades")
		local second = list[#list]
		ns.Plan.Set("shadow", key, second.c.inst)
		rows = rowsOf(fx)
		local picked
		for _, x in ipairs(rows) do if x.e.def.key == key then picked = x end end
		T.eq(picked.e.entry.plan.c.id, second.c.id)
		T.ok(picked.plan.sub.text:find("Your pick", 1, true), picked.plan.sub.text)
		if list[1].gain - second.gain > 1e-6 then T.ok(picked.plan.sub.text:find("best: ", 1, true), "the suggestion is better") end
		picked.scripts.OnClick(picked, "RightButton")
		local labels = {}
		for _, it in ipairs(U.contextMenu) do labels[#labels + 1] = it.text end
		local all = table.concat(labels, "|")
		T.ok(all:find("Back to suggestion", 1, true), all); T.ok(all:find("Choose another upgrade", 1, true))
		for _, it in ipairs(U.contextMenu) do if it.text == "Back to suggestion" then it.fn() end end
		T.eq(ns.Plan.Get("shadow", key), nil)
		-- left click and Choose open Slot Upgrades on that slot
		rows = rowsOf(fx)
		rows[1].scripts.OnClick(rows[1], "LeftButton")
		T.eq(ns.Options.View().tab, "slot"); T.eq(ns.Window.state.slot, rows[1].e.def.key)
		fx.done()
	end,
	missing_pick_greyed_last = function()
		local fx = F.load({ char = { plan = { shadow = { neck = "424242:0" } } } })
		local ns = fx.ns
		fx.open()
		local rows = rowsOf(fx)
		local last = rows[#rows]
		T.eq(last.e.def.key, "neck"); T.eq(last.badge.shown, false, "no priority number")
		T.ok(last.plan.sub.text:find("not available now", 1, true), last.plan.sub.text)
		T.eq(last.delta.text, "")
		fx.done()
	end,
	star = function()
		local fx = F.load()
		local ns = fx.ns
		fx.open()
		local r = rowsOf(fx)[1]
		r.star:Click()
		T.ok(ns.Wishlist.Has(r.e.entry.plan.c.inst), "starred")
		T.eq(rowsOf(fx)[1].star.on, true, "redrawn starred")
		rowsOf(fx)[1].star:Click()
		T.eq(ns.Wishlist.Has(r.e.entry.plan.c.inst), false)
		fx.done()
	end,
}
