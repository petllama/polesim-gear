-- Shift-click on a quest-sourced row opens the quest in Polestar's Lookup (Polestar.Lookup.Show(nil,
-- "quest", id)); the right-click menu offers it; hints only on quest rows; missing API: one chat line.
local T = require("t")
local F = require("winfix")

-- capture print and the Lookup calls; shift: whether Shift is held
local function harness(ns)
	local h = { calls = {}, printed = {}, shift = false }
	h.oldShift = _G.IsShiftKeyDown
	ns.Print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
		h.printed[#h.printed + 1] = table.concat(parts, " ")
	end
	_G.IsShiftKeyDown = function() return h.shift end
	function h.stub()
		_G.Polestar.Lookup = { Show = function(...) h.calls[#h.calls + 1] = { n = select("#", ...), ... } end }
	end
	function h.restore() _G.IsShiftKeyDown = h.oldShift end
	return h
end

local function tipText(U) return table.concat(U.tip.lines, "\n") end
local function menuTexts(U)
	local out = {}
	for _, it in ipairs(U.popup() or {}) do out[#out + 1] = it.text end
	return table.concat(out, "|")
end

return {
	-- the source chosen: the one on the route, else the first available, else the first; never non-quests
	quest_source_order = function()
		local ns = T.addon({ "Core.lua", "Waypoint.lua" })
		local L = ns.Lookup
		local drop = { kind = "dungeon" }
		local a = { kind = "quest", questId = 1, ok = false }
		local b = { kind = "quest", questId = 2 }
		local c = { kind = "quest", questId = 3, route = { ahead = 4 } }
		T.eq(L.QuestSource(nil), nil)
		T.eq(L.QuestSource({ drop, { kind = "vendor" } }), nil, "no quest: nothing")
		T.eq(L.QuestSource({ drop, a }), a, "the only quest, even unavailable")
		T.eq(L.QuestSource({ a, b }), b, "an available quest over an unavailable one")
		T.eq(L.QuestSource({ drop, b, c }), c, "the quest on the Polestar route (the row's tag)")
		T.eq(L.QuestSource({ { kind = "quest" } }), nil, "a quest without an id")
	end,
	-- the API: called with (nil, "quest", id); missing/old Polestar: a chat line; an error: a chat line
	open_quest = function()
		local ns = T.addon({ "Core.lua", "Waypoint.lua" })
		local L = ns.Lookup
		local h = harness(ns)
		_G.Polestar = nil
		T.eq(L.Available(), false)
		T.eq(L.OpenQuest(42), false)
		T.ok(h.printed[1] and h.printed[1]:find(L.MISSING, 1, true), tostring(h.printed[1]))
		_G.Polestar = { Lookup = {} }
		T.eq(L.OpenQuest(42), false, "an older Polestar without Lookup.Show")
		T.eq(#h.printed, 2)
		_G.Polestar = { Lookup = { Show = "not a function" } }
		T.eq(L.Available(), false)
		_G.Polestar = { Codex = {} }
		h.stub()
		T.eq(L.Available(), true)
		T.eq(L.OpenQuest(42), true)
		T.eq(#h.calls, 1); T.eq(h.calls[1].n, 3)
		T.eq(h.calls[1][1], nil); T.eq(h.calls[1][2], "quest"); T.eq(h.calls[1][3], 42)
		T.eq(L.OpenQuest(nil), false, "no quest: no call"); T.eq(#h.calls, 1)
		_G.Polestar.Lookup.Show = function() error("changed") end
		T.eq(L.OpenQuest(7), false, "an error is caught")
		T.ok(h.printed[#h.printed]:find("could not open quest 7", 1, true), h.printed[#h.printed])
		h.restore()
		_G.Polestar = nil
	end,
	-- Shift + left button only; right-click and plain clicks are not the quest's
	modifier = function()
		local ns = T.addon({ "Core.lua", "Waypoint.lua" })
		local L = ns.Lookup
		local h = harness(ns)
		_G.Polestar = {}
		h.stub()
		T.eq(L.Click(5, "LeftButton"), false, "no Shift")
		h.shift = true
		T.eq(L.Click(5, "RightButton"), false, "Shift + right-click: still the menu")
		T.eq(L.Click(nil, "LeftButton"), false, "no quest")
		T.eq(#h.calls, 0)
		T.eq(L.Click(5, "LeftButton"), true)
		T.eq(L.Click(6, nil), true, "a click without a button name (Button:Click()) is a left click")
		T.eq(#h.calls, 2); T.eq(h.calls[1][3], 5); T.eq(h.calls[2][3], 6)
		h.restore()
		_G.Polestar = nil
	end,
	-- Gear Plan: Shift-click on a quest row opens Lookup (stays on the plan); on other rows a plain click;
	-- hint and menu entry only on quest rows
	gear_plan = function()
		local fx = F.load()
		local ns, U = fx.ns, fx.U
		local h = harness(ns)
		h.stub()
		fx.open()
		local quest, other
		for _, r in ipairs(U.rows(ns.Window.Panel("plan").list)) do
			local q = r.e and ns.TabPlan.QuestOf(r.e)
			if q then quest = quest or r elseif r.e and ns.TabPlan.PlanRow(r.e) then other = other or r end
		end
		assert(quest, "a quest-sourced plan row in the fixture")
		assert(other, "a plan row from another source")
		local q = ns.TabPlan.QuestOf(quest.e)
		T.eq(q.kind, "quest")
		-- hint
		quest.scripts.OnEnter(quest)
		T.ok(tipText(U):find(ns.Lookup.HINT, 1, true), tipText(U))
		other.scripts.OnEnter(other)
		T.ok(not tipText(U):find(ns.Lookup.HINT, 1, true), "no hint on a non-quest row")
		T.ok(tipText(U):find("Click: this slot's upgrades.", 1, true), "the old hint stays")
		-- Shift-click
		h.shift = true
		quest.scripts.OnClick(quest, "LeftButton")
		T.eq(#h.calls, 1); T.eq(h.calls[1][1], nil); T.eq(h.calls[1][2], "quest"); T.eq(h.calls[1][3], q.questId)
		T.eq(ns.Options.View().tab, "plan", "the quest, not Slot Upgrades")
		other.scripts.OnClick(other, "LeftButton")
		T.eq(#h.calls, 1, "a non-quest row: no Lookup")
		T.eq(ns.Options.View().tab, "slot", "a non-quest row keeps its click")
		ns.Window.SetTab("plan")
		-- a plain click on the quest row still opens the slot
		h.shift = false
		for _, r in ipairs(U.rows(ns.Window.Panel("plan").list)) do if r.e and ns.TabPlan.QuestOf(r.e) then quest = r break end end
		quest.scripts.OnClick(quest, "LeftButton")
		T.eq(ns.Options.View().tab, "slot"); T.eq(#h.calls, 1)
		ns.Window.SetTab("plan")
		-- right-click menu
		for _, r in ipairs(U.rows(ns.Window.Panel("plan").list)) do
			if r.e and ns.TabPlan.QuestOf(r.e) then quest = r elseif r.e and ns.TabPlan.PlanRow(r.e) then other = r end
		end
		h.shift = true -- Shift + right-click: still the menu
		q = ns.TabPlan.QuestOf(quest.e)
		quest.scripts.OnClick(quest, "RightButton")
		local label = "Open quest in Polestar: " .. q.title
		T.ok(menuTexts(U):find(label, 1, true), menuTexts(U))
		for _, it in ipairs(U.popup()) do if it.text == label then it.click() end end
		T.eq(#h.calls, 2); T.eq(h.calls[2][3], q.questId)
		other.scripts.OnClick(other, "RightButton")
		T.ok(not menuTexts(U):find("Open quest in Polestar", 1, true), menuTexts(U))
		T.ok(menuTexts(U):find("Choose another upgrade", 1, true))
		h.restore()
		fx.done()
	end,
	-- Gear Plan without the API: Shift-click says to update Polestar and keeps the plan tab
	gear_plan_missing_api = function()
		local fx = F.load()
		local ns, U = fx.ns, fx.U
		local h = harness(ns)
		fx.open()
		local quest
		for _, r in ipairs(U.rows(ns.Window.Panel("plan").list)) do if r.e and ns.TabPlan.QuestOf(r.e) then quest = r break end end
		assert(quest)
		h.shift = true
		quest.scripts.OnClick(quest, "LeftButton")
		T.ok(table.concat(h.printed, "\n"):find(ns.Lookup.MISSING, 1, true), table.concat(h.printed, "\n"))
		T.eq(ns.Options.View().tab, "plan")
		h.restore()
		fx.done()
	end,
	-- Slot Upgrades and the Sources tab
	slot_and_sources = function()
		local fx = F.load()
		local ns, U = fx.ns, fx.U
		local h = harness(ns)
		h.stub()
		fx.open()
		local found = 0
		for _, d in ipairs(ns.Browser.SLOTS) do
			ns.Window.OpenSlot(d.key)
			for _, r in ipairs(U.rows(ns.Window.Panel("slot").list)) do
				if r.d and r.d.c then
					local q = ns.TabSlot.QuestOf(r.d)
					r.scripts.OnEnter(r)
					T.eq(tipText(U):find(ns.Lookup.HINT, 1, true) ~= nil, q ~= nil, "hint only on quest rows")
					local before = #h.calls
					h.shift = true
					r.scripts.OnClick(r, "LeftButton")
					h.shift = false
					if q then
						found = found + 1
						T.eq(#h.calls, before + 1); T.eq(h.calls[#h.calls][2], "quest"); T.eq(h.calls[#h.calls][3], q.questId)
					else
						T.eq(#h.calls, before, "a non-quest upgrade: nothing")
					end
					r.scripts.OnClick(r, "LeftButton")
					T.eq(#h.calls, before + (q and 1 or 0), "no Shift: nothing")
				end
			end
		end
		T.ok(found > 0, "quest rows in Slot Upgrades")
		-- Sources: quest headers and their rewards
		local p = fx.tab("sources")
		ns.TabSources.view.kind = "quest"
		ns.Window.Refresh()
		local header, reward
		for _, r in ipairs(U.rows(p.detail)) do
			if r.d and r.d.quest then header = header or r end
			if r.d and r.d.c and r.d.src and r.d.src.kind == "quest" then reward = reward or r end
		end
		assert(header and reward, "a quest and a reward in the Sources tab")
		header.scripts.OnEnter(header)
		T.ok(tipText(U):find(ns.Lookup.HINT, 1, true), tipText(U))
		local n = #h.calls
		h.shift = true
		header.scripts.OnClick(header, "LeftButton")
		T.eq(#h.calls, n + 1); T.eq(h.calls[#h.calls][3], header.d.quest.questId)
		reward.scripts.OnClick(reward, "LeftButton")
		T.eq(#h.calls, n + 2); T.eq(h.calls[#h.calls][3], reward.d.src.questId)
		-- a dungeon's rows: no quest
		ns.TabSources.view.kind, ns.TabSources.view.group = "dungeon", nil
		ns.Window.Refresh()
		for _, r in ipairs(U.rows(p.detail)) do
			if r.d and (r.d.c or r.d.dungeon) then
				r.scripts.OnClick(r, "LeftButton")
				T.eq(ns.TabSources.QuestOf(r.d), nil)
			end
		end
		T.eq(#h.calls, n + 2, "dungeon rows open nothing")
		h.restore()
		fx.done()
	end,
}
