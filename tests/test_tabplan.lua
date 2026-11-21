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
}
