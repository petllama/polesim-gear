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
	details = function()
		local fx = F.load()
		local ns, U = fx.ns, fx.U
		fx.open()
		ns.Window.SetTab("sources")
		local p = ns.Window.Panel("sources")
		ns.TabSources.view.kind, ns.TabSources.view.group = "quest", nil
		ns.Window.Refresh()
		local rows = U.rows(p.detail)
		T.ok(rows[1].d.quest, "a quest header first"); T.ok(U.texts(rows[1]):find("%[18%] Quest 10%d"), U.texts(rows[1]))
		T.ok(rows[2].d.c, "then its rewards")
		rows[2].action:Click()
		T.eq(ns.Plan.Get("shadow", rows[2].d.slot.key), ns.Browser.KeyOf(rows[2].d.c.inst), "Set as plan from Sources")
		rows[2].star:Click(); T.ok(ns.Wishlist.Has(rows[2].d.c.inst))
		ns.TabSources.view.kind, ns.TabSources.view.group = "vendor", nil
		ns.Window.Refresh()
		rows = U.rows(p.detail)
		T.ok(U.texts(rows[1]):find("Trader", 1, true)); T.ok(U.texts(rows[1]):find("1000c", 1, true), "price")
		ns.TabSources.view.kind = "world"
		ns.Window.Refresh()
		rows = U.rows(p.detail)
		T.ok(#rows > 0); T.ok(U.texts(rows[1]):find("Drop: Ogre", 1, true))
		rows[1].scripts.OnEnter(rows[1])
		T.ok(table.concat(U.tip.lines, "\n"):find("Duskwood", 1, true), "zone in the hover")
		fx.done()
	end,
	-- Groups gives one row per item per place: the likeliest source on the row, the place's other
	-- sources in the hover; a row whose likeliest chance is under 1% is dimmed and listed last.
	rare_last_others_in_hover = function()
		local fx = F.load()
		local ns, U = fx.ns, fx.U
		local codex = _G.Polestar.Codex
		local item, npc = codex.Item, codex.Npc
		codex.Item = function(id)
			if id % 10 == 1 then return { sources = { { type = "drop", npc = 7, chance = 10, instance = "DM" }, { type = "drop", npc = 11, chance = 5, instance = "DM" } } } end
			if id % 10 == 6 then return { sources = { { type = "drop", npc = 7, chance = 0.5, instance = "DM" }, { type = "drop", npc = 11, chance = 0.3, instance = "DM" } } } end
			return item(id)
		end
		codex.Npc = function(id)
			if id == 11 then return { name = "Second Boss", level = 19, boss = true, instance = "DM" } end
			return npc(id)
		end
		fx.open()
		ns.Window.SetTab("sources")
		local p = ns.Window.Panel("sources")
		local rows = U.rows(p.detail)
		T.ok(rows[1].d.dungeon, "the dungeon's header")
		local seenRare, likely, rare = false, nil, nil
		for i = 2, #rows do
			local d = rows[i].d
			if d.rare then seenRare = true rare = rare or rows[i] else
				T.ok(not seenRare, "rare rows last"); likely = likely or rows[i]
			end
		end
		T.ok(likely and rare, "both kinds of row")
		T.eq(likely.item.name.alpha, 1); T.eq(rare.item.name.alpha, 0.5, "dimmed"); T.eq(rare.item.icon.desaturated, true)
		T.ok(likely.item.sub.text:find("Boss (boss), 10%", 1, true), likely.item.sub.text)
		likely.scripts.OnEnter(likely)
		local tip = table.concat(U.tip.lines, "\n")
		T.ok(tip:find("Also here: Second Boss (boss), 5%", 1, true), tip)
		rare.scripts.OnEnter(rare)
		tip = table.concat(U.tip.lines, "\n")
		T.ok(tip:find("under 1%", 1, true), tip); T.ok(tip:find("Also here: Second Boss (boss), 0.3%", 1, true), tip)
		fx.done()
	end,
	waypoint = function()
		local fx = F.load()
		local ns, U = fx.ns, fx.U
		fx.open()
		ns.Window.SetTab("sources")
		local p = ns.Window.Panel("sources")
		ns.TabSources.view.kind, ns.TabSources.view.group = "quest", nil
		ns.Window.Refresh()
		local rows = U.rows(p.detail)
		T.eq(rows[1].way.shown, false, "no Nav API: no button")
		local got
		_G.Polestar.Nav = { API = { version = 1, Navigate = function(_, map, x, y, title) got = { map, x, y, title } return true end } }
		rows = U.rows(p.detail)
		T.eq(rows[1].way.shown, true)
		T.eq(rows[2].way.shown, false, "a quest's reward rows: the header has it")
		rows[1].way:Click()
		T.eq(got[1], 1436); T.near(got[2], 0.56); T.ok(got[4]:find("Giver", 1, true))
		ns.TabSources.view.kind, ns.TabSources.view.group = "dungeon", nil
		ns.Window.Refresh()
		rows = U.rows(p.detail)
		T.ok(rows[1].d.dungeon); T.eq(rows[1].way.shown, true, "the dungeon's entrance")
		rows[1].way:Click()
		T.near(got[2], 0.419); T.eq(got[4], "The Deadmines")
		local said
		ns.Print = function(m) said = m end
		_G.Polestar.Nav.API.Navigate = function() return false end
		rows[1].way:Click()
		T.eq(said, "Polestar could not set the waypoint")
		fx.done()
	end,
}
