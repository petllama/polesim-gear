local T = require("t")
local F = require("winfix")
return {
	-- Under a worn two-hander (Wind Rider Staff at 21) the off hands are listed as part of the best
	-- set with each: paired with the best one-hander passing the ticked sources, or the player's
	-- main-hand pick; pairs that lose to the staff only under All gear, with their negative gain; the
	-- "Suggested" mark follows the Gear Plan's weapon set.
	weapon_set_lists = function()
		local worn = {}
		local fx = F.load({ worn = worn, level = 21 })
		local ns, U = fx.ns, fx.U
		local w = ns.Bands.For("priest", "shadow", 21).w
		local inst = ns.Score.Instance(ns.Items.Get(5306))
		worn[16] = { inst = inst, score = ns.Score.Score(inst, w, "priest", "mh") }
		fx.open()
		ns.Window.OpenSlot("offhand")
		local p = ns.Window.Panel("slot")
		local rows = U.rows(p.list, 50)
		T.ok(#rows >= 2)
		for _, r in ipairs(rows) do
			if r.d and r.d.c then
				T.ok(r.d.gain > 0, "Upgrades only: pairs that beat the staff")
				T.ok(r.d.note:find("in the main hand", 1, true), r.d.note)
			end
		end
		local _, oh = ns.View.Weapons(ns.Window.state.model, worn, ns.Window.St(), ns.Window.St().ahead)
		T.eq(U.ownText(rows[1].action), oh.plan and ns.Browser.KeyOf(oh.plan.c.inst) == ns.Browser.KeyOf(rows[1].d.c.inst)
			and "Suggested" or "Set as plan")
		-- a weak one-hander picked for the main hand: the off hands pair with it
		local weak
		for _, r in ipairs(ns.Window.state.model.now.mainhand) do if r.c.inst.inv ~= 17 then weak = r end end
		T.ok(weak, "a one-hander")
		ns.Plan.Set("shadow", "mainhand", weak.c.inst)
		ns.Window.Refresh()
		rows = U.rows(p.list, 50)
		for _, r in ipairs(rows) do
			if r.d and r.d.c then T.ok(r.d.note:find("with " .. weak.c.inst.name, 1, true), r.d.note) end
		end
		-- a stronger two-hander worn (Soul Harvester): All gear lists the losing pairs too, negative;
		-- the count line counts upgrades only
		ns.Plan.Clear("shadow", "mainhand")
		inst = ns.Score.Instance(ns.Items.Get(20536))
		worn[16] = { inst = inst, score = ns.Score.Score(inst, w, "priest", "mh") }
		ns.Window.Build()
		fx.settle()
		ns.Options.View().show = "all"
		ns.Window.OpenSlot("offhand")
		rows = U.rows(p.list, 400)
		local neg, pos = 0, 0
		for _, r in ipairs(rows) do
			if r.d and r.d.c then if r.d.gain > 0 then pos = pos + 1 else neg = neg + 1 end end
		end
		T.ok(neg > 0 and pos > 0, "losing pairs listed under All gear: " .. neg .. " / " .. pos)
		T.ok(p.count.text:match("^" .. pos .. " upgrade"), p.count.text .. " / " .. pos)
		ns.Options.View().show = "upgrades"
		ns.Window.Refresh()
		T.eq(#U.rows(p.list, 400), pos + (p.list.provided[pos + 1] and 1 or 0), "Upgrades only: the winning pairs")
		-- a two-hander picked: no off hand is "Suggested"
		local staff
		for _, r in ipairs(ns.Window.state.model.now.mainhand) do if r.c.inst.inv == 17 then staff = r break end end
		if staff then
			ns.Plan.Set("shadow", "mainhand", staff.c.inst)
			ns.Window.Refresh()
			T.eq(U.ownText(U.rows(p.list, 1)[1].action), "Set as plan")
		end
		fx.done()
	end,
	picker_and_count = function()
		local fx = F.load()
		local ns, U = fx.ns, fx.U
		fx.open()
		ns.Window.OpenSlot("chest")
		local p = ns.Window.Panel("slot")
		T.ok(p:IsShown())
		local items = U.menu(p.picker)
		T.eq(#items, #ns.Browser.SLOTS); T.ok(items[5].isSelected(), "Chest")
		items[1].select()
		T.eq(ns.Window.state.slot, "head")
		T.ok(p.count.text:match("^%d+ upgrades?"), p.count.text)
		T.ok(p.count.text:find("Quests", 1, true), p.count.text)
		T.eq(ns.Plan.KIND_LABEL.vendor, "Vendors", "the count line says \"Vendors 3\"")
		fx.done()
	end,
	set_as_plan = function()
		local fx = F.load()
		local ns, U = fx.ns, fx.U
		fx.open()
		ns.Window.OpenSlot("head")
		local p = ns.Window.Panel("slot")
		local rows = U.rows(p.list)
		T.ok(#rows >= 2)
		T.eq(U.ownText(rows[1].action), "Suggested"); T.eq(U.ownText(rows[2].action), "Set as plan")
		T.ok(rows[1].item.sub.text ~= "", "first source shown")
		rows[1].d.c.sources[1].route = { guide = "Silverpine Forest", step = 87, ahead = 12, active = true }
		rows = U.rows(p.list)
		T.ok(rows[1].item.sub.text:find("in 12 steps", 1, true), rows[1].item.sub.text)
		T.ok(not rows[1].item.sub.text:find("(route)", 1, true), rows[1].item.sub.text)
		rows[1].d.c.sources[1].route = nil
		T.ok(rows[1].level.text:match("^lvl %d+"), rows[1].level.text)
		T.eq(rows[1].kind.text, ns.Style.KIND_SHORT[rows[1].d.c.sources[1].kind])
		T.ok(rows[1].pct.text:find("%%"), "Gain % shown: " .. tostring(rows[1].pct.text))
		T.eq(rows[1].pct.text, ns.Style.Pct(rows[1].d.gain, rows[1].d.base))
		rows[2].action:Click()
		T.eq(ns.Plan.Get("shadow", "head"), ns.Browser.KeyOf(rows[2].d.c.inst))
		rows = U.rows(p.list)
		T.ok(U.ownText(rows[2].action):find("Your pick", 1, true))
		T.eq(U.ownText(rows[1].action), "Set as plan", "the suggestion is not the plan now")
		rows[2].action:Click()
		T.eq(ns.Plan.Get("shadow", "head"), nil, "back to suggestion")
		rows[1].star:Click()
		T.ok(ns.Wishlist.Has(rows[1].d.c.inst))
		T.eq(U.rows(p.list)[1].star.on, true, "redrawn starred")
		rows[1].scripts.OnEnter(rows[1])
		T.ok(table.concat(U.tip.lines, "\n"):find("Gain over what you wear", 1, true), "the shared row tooltip")
		fx.done()
	end,
	show_all = function()
		local fx = F.load()
		local ns, U = fx.ns, fx.U
		ns.Browser.KEEP = 1
		fx.open()
		ns.Window.OpenSlot("chest")
		local p = ns.Window.Panel("slot")
		local rows = U.rows(p.list)
		local last = rows[#rows]
		T.ok(last.d.showAll, "offers the rest")
		local total = ns.Browser.CountPassing(ns.Window.state.model, "chest", ns.Options.View().filters)
		T.ok(last.item.name.text:find(string.format("Show all (%d)", total), 1, true), last.item.name.text)
		last.scripts.OnClick(last)
		T.ok(U.rows(p.list)[#U.rows(p.list)].d.header == "Scoring every upgrade...")
		fx.settle()
		rows = U.rows(p.list)
		T.eq(#rows, total, "every upgrade listed (look ahead 0)"); T.ok(not rows[#rows].d.showAll)
		_G.Polestar.Codex.Load = function() return false end
		ns.Window.OpenSlot("legs")
		rows = U.rows(p.list)
		last = rows[#rows]
		if last.d.showAll then
			last.scripts.OnClick(last)
			T.ok(U.rows(p.list)[#U.rows(p.list)].d.header:find("could not be loaded", 1, true))
		end
		fx.done()
	end,
}
