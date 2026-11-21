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
		for _, h in ipairs({ "#", "Slot", "Current item", "Plan", "Gain", "Gain %", "Source" }) do T.ok(head:find(h, 1, true), h) end
		local rows = rowsOf(fx)
		T.ok(#rows >= 10, "most slots have an upgrade at 20 with only a hat worn: " .. #rows)
		local r1 = rows[1]
		T.eq(r1.badge.text.text, "1"); T.near(r1.badge.bg.color[1], ns.Style.C.badgeGold[1])
		T.eq(rows[4].badge.text.text, "4"); T.near(rows[4].badge.bg.color[1], ns.Style.C.badgeGrey[1])
		T.ok(r1.delta.text:match("^%+%d"), r1.delta.text)
		local gains = {}
		for i, r in ipairs(rows) do gains[i] = r.e.entry.plan.setGain or r.e.entry.plan.gain end
		for i = 2, #gains do T.ok(gains[i - 1] >= gains[i], "sorted by gain (weapons by their set's)") end
		local headRow
		for _, r in ipairs(rows) do if r.e.def.key == "head" then headRow = r end end
		T.ok(headRow.cur.name.text:find("Old Hat", 1, true)); T.eq(headRow.curScore.text, "1.0")
		T.ok(headRow.pct.text:find("%%"), "a % against the worn score")
		T.ok(headRow.kind.text ~= "", "source kind")
		fx.done()
	end,
	-- Gain % = gain / the score of everything the plan item replaces: a staff against main + off hand
	-- (the Gear Plan showed +3233% against the main hand alone while the gain was over both).
	pct_two_hander = function()
		local worn = {}
		local fx = F.load({ worn = worn, level = 18 })
		local ns = fx.ns
		local w = ns.Bands.For("priest", "shadow", 18).w
		local function wear(slot, id, role)
			local inst = ns.Score.Instance(ns.Items.Get(id))
			worn[slot] = { inst = inst, score = ns.Score.Score(inst, w, "priest", role) }
		end
		wear(16, 277247, "mh"); wear(17, 15945, "oh") -- Mug of Muddled Memories, Runic Stave
		fx.open()
		local row
		for _, r in ipairs(rowsOf(fx)) do if r.e.def.key == "mainhand" then row = r end end
		local plan = row.e.entry.plan
		local pair = worn[16].score + worn[17].score
		-- the weapon set decides (here a one-hander + off hand beat every staff): a one-hander's % is over
		-- the main hand it replaces, a staff's over main + off hand
		T.near(plan.base, plan.c.inst.inv == 17 and pair or worn[16].score, 1e-9)
		T.eq(row.pct.text, ns.Style.Pct(plan.gain, plan.base))
		-- Slot Upgrades: the same base on every row; a staff's is the pair
		ns.Window.OpenSlot("mainhand")
		local staff
		for _, r in ipairs(fx.U.rows(ns.Window.Panel("slot").list)) do
			if r.d and r.d.c then
				T.eq(r.pct.text, ns.Style.Pct(r.d.gain, r.d.base), r.d.c.inst.name)
				if r.d.c.inst.inv == 17 then
					staff = true
					T.near(r.d.base, pair, 1e-9)
					T.ok(r.pct.text ~= ns.Style.Pct(r.d.gain, worn[16].score), "not over the main hand alone")
				end
			end
		end
		T.ok(staff, "a staff in the list")
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
			-- the row: "BiS +N" only (a name would be cut); the tooltip names the better item
			local sub = picked.plan.sub.text
			T.ok(sub:find("BiS " .. ns.Style.Colour(ns.Style.C.green) .. "+", 1, true), sub)
			T.ok(not sub:find(list[1].c.inst.name, 1, true), "no name on the row: " .. sub)
			picked.scripts.OnEnter(picked)
			local tip = table.concat(U.tip.lines, "\n")
			T.ok(tip:find("Best overall: " .. list[1].c.inst.name .. " " .. ns.Style.Signed(list[1].gain), 1, true), tip)
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
	-- An upgrade from an upcoming guide quest within 2 levels is the suggestion over the BiS: the row says
	-- "near quest" and "BiS +N", the tooltip "Best overall: <item> +N (<source>)", the strip's tooltip
	-- and Slot Upgrades name it; the setting off brings the BiS back.
	near_quest_suggestion = function()
		local fx = F.load()
		local ns, U = fx.ns, fx.U
		local f = fx.open()
		T.eq(ns.Options.Get("preferQuest"), true)
		local key, list, q
		for _, def in ipairs(ns.Browser.SLOTS) do
			local rows = ns.Browser.SlotRows(ns.Window.state.model, def.key, 0, ns.Options.View().filters)
			for i = 2, #rows do
				local s = rows[i].c.sources[1]
				if s.kind == "quest" and rows[1].gain - rows[i].gain > 0.1 and not rows[1].c.kinds.quest then key, list, q = def.key, rows, rows[i] break end
			end
			if key then break end
		end
		T.ok(key, "a slot whose BiS is not a quest and that has a quest upgrade")
		local function row()
			for _, x in ipairs(rowsOf(fx)) do if x.e.def.key == key then return x end end
		end
		-- not on the route: BiS stays
		ns.Window.Refresh()
		T.eq(row().e.entry.plan, list[1], "a quest not on the guide never replaces BiS")
		q.c.sources[1].route = { guide = "Westfall", step = 40, ahead = 6, active = true }
		ns.Window.Refresh()
		local x = row()
		T.eq(x.e.entry.plan, q); T.eq(x.e.entry.near, true)
		local sub = x.plan.sub.text
		T.ok(sub:find("near quest", 1, true), sub)
		T.ok(sub:find("BiS " .. ns.Style.Colour(ns.Style.C.green) .. ns.Style.Signed(list[1].gain), 1, true), sub)
		T.eq(x.delta.text, ns.Style.Signed(q.gain), "the row is the quest's")
		x.scripts.OnEnter(x)
		local tip = table.concat(U.tip.lines, "\n")
		T.ok(tip:find("Best overall: " .. list[1].c.inst.name .. " " .. ns.Style.Signed(list[1].gain) .. " (" .. list[1].c.sources[1].text, 1, true), tip)
		-- the strip's tooltip names the suggestion
		local slot = x.e.def.slot
		if key == "finger" or key == "trinket" then
			for s, e in pairs(ns.Window.badges or {}) do if e == x.e then slot = s end end
		end
		local line = ns.Window.SlotPlanLine(slot)
		T.ok(line and line:find("Suggested upgrade: " .. q.c.inst.name, 1, true), tostring(line))
		-- Slot Upgrades: the quest says "Suggested", the BiS row stays listed
		ns.Window.OpenSlot(key)
		local srows = U.rows(ns.Window.Panel("slot").list)
		local labels = {}
		for _, r in ipairs(srows) do
			if r.d and r.d.c then labels[r.d.c.id] = U.ownText(r.action) end
		end
		T.eq(labels[q.c.id], "Suggested"); T.eq(labels[list[1].c.id], "Set as plan")
		-- the setting off: BiS as before
		ns.Options.Set("preferQuest", false)
		ns.Window.SetTab("plan")
		T.eq(row().e.entry.plan, list[1])
		T.ok(not row().plan.sub.text:find("near quest", 1, true))
		fx.done()
	end,
	-- A worn item from the client (Live.Instance) shows its link name and icon in "Current item".
	worn_from_client_named = function()
		local worn = {}
		local fx = F.load({ worn = worn })
		local ns = fx.ns
		local inst = ns.Live.Instance("|cff1eff00|Hitem:999999::::::::20::::::::|h[Odd Robe of the Eagle]|h|r",
			{ Info = function() return "INVTYPE_ROBE", 10, 4, 1, 2, 132656 end, Stats = function() return { ITEM_MOD_STAMINA_SHORT = 1 } end })
		worn[5] = { inst = inst, score = 0.5 }
		fx.open()
		local row
		for _, r in ipairs(rowsOf(fx)) do if r.e.def.key == "chest" then row = r end end
		T.ok(row.cur.name.text:find("Odd Robe of the Eagle", 1, true), row.cur.name.text)
		T.eq(row.cur.icon.texture, 132656)
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
	-- The weapon set in the window (a Shadow priest at 21 wearing Wind Rider Staff): the main and off
	-- hand rows name each other "(also planned)" and the tooltip gives the set's gain; with a two-hander
	-- as the plan the Off hand row "uses the two-hander" (greyed, no gain, no number), and the equipped
	-- strip's off-hand slot says so.
	weapon_set_rows = function()
		local worn = {}
		local fx = F.load({ worn = worn, level = 21 })
		local ns, U = fx.ns, fx.U
		local w = ns.Bands.For("priest", "shadow", 21).w
		local inst = ns.Score.Instance(ns.Items.Get(5306))
		worn[16] = { inst = inst, score = ns.Score.Score(inst, w, "priest", "mh") }
		fx.open()
		local function rows()
			local by = {}
			for _, r in ipairs(rowsOf(fx)) do if r.e.def then by[r.e.def.key] = r end end
			return by
		end
		local by = rows()
		local mh, oh = by.mainhand.e.entry.plan, by.offhand.e.entry.plan
		T.ok(mh and mh.c.inst.inv ~= 17 and oh, "this fixture's best set: a one-hander + an off hand")
		T.eq(oh.note, "with " .. mh.c.inst.name .. " (also planned)")
		T.near(mh.gain + oh.gain, mh.setGain, 1e-9, "the rows add up to the set")
		T.near(mh.gain, mh.c.score - worn[16].score, 1e-9)
		T.eq(by.mainhand.delta.text, ns.Style.Signed(mh.gain))
		by.offhand.scripts.OnEnter(by.offhand)
		local tip = table.concat(U.tip.lines, "\n")
		T.ok(tip:find("Weapon set: " .. ns.Style.Signed(mh.setGain) .. " over Wind Rider Staff", 1, true), tip)
		T.ok(tip:find("(also planned)", 1, true), tip)
		-- a two-hander picked as the plan
		local staff
		for _, r in ipairs(by.mainhand.e.entry.rows) do if r.c.inst.inv == 17 then staff = r break end end
		ns.Plan.Set("shadow", "mainhand", staff.c.inst)
		ns.Window.Refresh()
		by = rows()
		T.eq(by.offhand, nil, "Upgrades only: no off-hand row")
		ns.Options.View().show = "all"
		ns.Window.Refresh()
		by = rows()
		T.eq(by.mainhand.e.entry.plan.c.id, staff.c.id)
		local off = by.offhand
		T.ok(off.e.entry.twoHander)
		T.ok(off.plan.name.text:find("Uses the two-hander", 1, true), off.plan.name.text)
		T.eq(off.delta.text, ""); T.eq(off.pct.text, ""); T.ok(not off.badge:IsShown(), "no priority")
		local line = ns.Window.SlotPlanLine(17)
		T.ok(line and line:find("two-hander", 1, true), tostring(line))
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
	-- The current item: the worn item's own tooltip (SetInventoryItem) and the slot's plan; a click on
	-- it still opens the slot. A missing pick shows the game's item tooltip and why.
	current_item_and_missing_tooltips = function()
		local fx = F.load({ char = { plan = { shadow = { neck = "424242:0" } } } })
		local ns, U = fx.ns, fx.U
		fx.open()
		local rows = rowsOf(fx)
		local headRow
		for _, r in ipairs(rows) do if r.e.def.key == "head" then headRow = r end end
		headRow.cur.scripts.OnEnter(headRow.cur)
		T.eq(U.tip.inventory, 1, "the worn item's own tooltip"); T.eq(U.tip.owner, headRow.cur)
		local tip = table.concat(U.tip.lines, "\n")
		T.ok(tip:find("Suggested upgrade: " .. headRow.e.entry.plan.c.inst.name, 1, true), tip)
		T.eq(U.tip.shown, true)
		headRow.cur.scripts.OnMouseUp(headRow.cur, "LeftButton")
		T.eq(ns.Options.View().tab, "slot", "the click opens the slot"); T.eq(ns.Window.state.slot, "head")
		ns.Window.SetTab("plan")
		rows = rowsOf(fx)
		local last = rows[#rows]
		T.eq(last.e.def.key, "neck")
		last.scripts.OnEnter(last)
		T.eq(U.tip.link, "item:424242", "the game's tooltip for the missing pick")
		tip = table.concat(U.tip.lines, "\n")
		T.ok(tip:find("not available now", 1, true), tip)
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
		s1.route = { guide = "Silverpine Forest", step = 87, ahead = 3, active = true }
		box.view.init(row, e)
		T.eq(row.kind.text, ns.Style.KIND_SHORT[s1.kind], "no \"(route)\" text"); T.eq(row.route.shown, true, "a route marker on the icon")
		T.ok(row.plan.sub.text:find("in 3 steps", 1, true), "the steps ahead under the name: " .. row.plan.sub.text)
		T.eq(ns.Style.KIND_SHORT.world, "World"); T.eq(ns.Style.KIND_SHORT.dungeon, "Dungeon")
		fx.done()
	end,
}
