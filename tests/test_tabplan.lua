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
		if list[1].gain - second.gain > 1e-6 then
			-- the row: "best +N" only (a name would be cut); the tooltip names the better item
			local sub = picked.plan.sub.text
			T.ok(sub:find("best " .. ns.Style.Colour(ns.Style.C.green) .. "+", 1, true), sub)
			T.ok(not sub:find(list[1].c.inst.name, 1, true), "no name on the row: " .. sub)
			picked.scripts.OnEnter(picked)
			local tip = table.concat(U.tip.lines, "\n")
			T.ok(tip:find("Better: " .. list[1].c.inst.name .. " " .. ns.Style.Signed(list[1].gain), 1, true), tip)
		end
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
	all_and_wishlist_modes = function()
		local fx = F.load({ char = { wish = { ["424242:0"] = true } } })
		local ns, U = fx.ns, fx.U
		local f = fx.open()
		ns.Options.View().filters.vendor = false
		ns.Options.View().filters.crafted = false
		ns.Options.View().filters.dungeon = false
		ns.Options.View().filters.quest = false
		U.button(f, "All gear"):Click()
		local rows = rowsOf(fx)
		T.eq(#rows, #ns.Browser.SLOTS, "every slot")
		T.ok(rows[1].plan.sub.text:find("nothing better now", 1, true), "no source ticked: no upgrades")
		T.ok(rows[1].cur.name.text:find("Old Hat", 1, true), "the current item is shown")
		local first = ns.Window.state.model.now.head[1]
		ns.Wishlist.Toggle(first.c.inst)
		U.button(f, "Wishlist"):Click()
		rows = rowsOf(fx)
		T.eq(#rows, 2)
		T.eq(rows[1].e.row.c.id, first.c.id, "found, whatever the filters"); T.ok(rows[1].delta.text:match("^%+"))
		T.ok(rows[2].plan.sub.text:find("not an upgrade now", 1, true))
		T.eq(fx.U.ownText(rows[1].choose), "Plan")
		rows[1].choose:Click()
		T.eq(ns.Plan.Get("shadow", "head"), ns.Browser.KeyOf(first.c.inst), "Set as plan from the wishlist")
		T.ok(fx.U.ownText(rowsOf(fx)[1].choose):find("Picked", 1, true))
		fx.done()
	end,
	hover = function()
		local fx = F.load({ char = { plan = { shadow = { neck = "424242:0" } } } })
		local ns, U = fx.ns, fx.U
		fx.open()
		local rows = rowsOf(fx)
		rows[1].scripts.OnEnter(rows[1])
		local text = table.concat(U.tip.lines, "\n")
		T.ok(text:find("Gain over what you wear", 1, true), text); T.ok(text:find("Right-click", 1, true))
		local last = rows[#rows]
		last.scripts.OnEnter(last)
		text = table.concat(U.tip.lines, "\n")
		T.ok(text:find("not available now", 1, true), text)
		fx.done()
	end,
	close_releases_row_references = function()
		local fx = F.load()
		local ns = fx.ns
		local f = fx.open()
		local rows = rowsOf(fx)
		T.ok(rows[1].e, "a row holds its entry while shown")
		f:Hide()
		for _, r in ipairs(rows) do T.eq(r.e, nil, "released on close") end
		fx.done()
	end,
	row_reused_across_modes = function()
		local fx = F.load({ char = { plan = { shadow = { neck = "424242:0" } }, wish = { ["424242:0"] = true } } })
		local ns, U = fx.ns, fx.U
		local f = fx.open()
		local box = ns.Window.Panel("plan").list
		local row = U.new("Button", box) -- one pooled row given every kind of entry in turn
		local function last() local es = box.provided return es[#es] end
		box.view.init(row, last()) -- the greyed missing pick (Upgrades only)
		T.eq(row.plan.name.alpha, 0.5); T.eq(row.plan.icon.desaturated, true); T.eq(row.plan.iconFrame.alpha, 0.5)
		box.view.init(row, box.provided[1]) -- an upgrade
		T.eq(row.plan.name.alpha, 1); T.eq(row.plan.icon.desaturated, false); T.eq(row.badge.shown, true)
		U.button(f, "Wishlist"):Click()
		box.view.init(row, box.provided[1]) -- the missing wish
		T.eq(row.plan.icon.alpha, 0.5)
		ns.Wishlist.Toggle({ id = 424242, bonus = 0 })
		box.view.init(row, box.provided[1]) -- the empty wishlist message
		T.ok(row.e.empty); T.eq(row.plan.name.alpha, 1); T.eq(row.plan.icon.shown, false); T.eq(row.plan.iconFrame.shown, false)
		T.eq(row.cur.icon.shown, false); T.eq(row.star.shown, false); T.eq(row.choose.shown, false)
		for _, k in ipairs(ns.Browser.KINDS) do ns.Options.View().filters[k] = false end
		U.button(f, "All gear"):Click()
		local plain
		for _, e in ipairs(box.provided) do if not e.entry.plan and not e.entry.missing then plain = e end end
		T.ok(box.provided[1].entry.missing, "the missing pick first: no upgrades at all")
		box.view.init(row, box.provided[1]) -- the missing pick again
		T.eq(row.plan.icon.alpha, 0.5)
		box.view.init(row, plain) -- a slot with nothing better
		T.eq(row.plan.name.alpha, 1); T.eq(row.plan.icon.shown, false); T.ok(row.plan.sub.text:find("nothing better", 1, true))
		fx.done()
	end,
	kind_column = function()
		local fx = F.load()
		local ns, U = fx.ns, fx.U
		fx.open()
		local box = ns.Window.Panel("plan").list
		local e = box.provided[1]
		local s1 = e.entry.plan.c.sources[1]
		local row = U.new("Button", box)
		box.view.init(row, e)
		T.eq(row.kind.text, ns.Style.KIND_SHORT[s1.kind], "a short word: the column is narrow")
		T.eq(row.route.shown, false)
		s1.route = 3
		box.view.init(row, e)
		T.eq(row.kind.text, ns.Style.KIND_SHORT[s1.kind], "no \"(route)\" text"); T.eq(row.route.shown, true, "a route marker on the icon")
		T.eq(ns.Style.KIND_SHORT.world, "World"); T.eq(ns.Style.KIND_SHORT.dungeon, "Dungeon")
		fx.done()
	end,
}
