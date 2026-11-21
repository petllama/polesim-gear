local T = require("t")

-- n steps; turnins = { [stepIndex] = questId or { questIds } }
local function guide(id, title, n, turnins)
	local st = {}
	for i = 1, n do
		local goals = {}
		local q = turnins[i]
		for _, id2 in ipairs(type(q) == "table" and q or { q }) do goals[#goals + 1] = { t = "turnin", quest = id2 } end
		st[i] = { goals = goals }
	end
	return { id = id, title = title, steps = st }
end

-- A fake Polestar: tabs = { { guide, live } } (the first is active unless active = n), next = { [id] = id },
-- done = { [questId] = true }, plan: a RoutePlan.GetTurnIn (nil: the older Polestar without it).
local function fake(o)
	local handlers = {}
	local byId = {}
	for _, t in ipairs(o.tabs) do byId[t.guide.id] = t.guide end
	for _, g in ipairs(o.extra or {}) do byId[g.id] = g end
	local P
	P = {
		On = function(m, fn) handlers[m] = fn end,
		Engine = {
			GetGuide = function() return P._tabs[P._active].guide end,
			GetLiveStep = function() return P._tabs[P._active].live end,
			GetStepIndex = function() return P._tabs[P._active].live end,
			TabLiveSteps = function()
				local out = {}
				for i, t in ipairs(P._tabs) do out[i] = { guide = t.guide, live = t.live } end
				return out
			end,
			NextGuide = function(id) return (o.next or {})[id] end,
		},
		Guides = { Get = function(id) return byId[id] end },
		Compat = { IsQuestCompleted = function(q) return (o.done or {})[q] == true end },
		CharState = function() return { skipped = o.skipped or {} } end,
		RoutePlan = o.plan and { GetTurnIn = o.plan } or nil,
		_tabs = o.tabs, _active = o.active or 1,
	}
	_G.Polestar = P
	local ns = T.addon({ "Core.lua", "Route.lua" })
	return ns, P, handlers
end

local silverpine = guide("h/silverpine", "Silverpine Forest", 100, { [80] = 7, [87] = 9, [60] = 5 })
local barrens = guide("h/barrens", "The Barrens", 60, { [40] = 11, [10] = 12 })
local stonetalon = guide("h/stonetalon", "Stonetalon", 30, { [5] = 13 })

return {
	build = function()
		local R = T.addon({ "Core.lua", "Route.lua" }).Route
		local map = R.Build({ steps = {
			{ goals = { { t = "accept", quest = 1 } } },
			{ goals = { { t = "turnin", quest = 1 }, { t = "turnin", quest = 2 } } },
			{ goals = { { t = "turnin", quest = 1 } } },
		} })
		T.eq(map[1][1], 2); T.eq(map[1][2], 3); T.eq(map[2][1], 2); T.eq(map[3], nil)
		T.eq(next(R.Build(nil)), nil)
	end,
	-- The active guide: the first turn-in at or after the live step, its steps ahead.
	active_guide_steps_ahead = function()
		local ns = fake({ tabs = { { guide = silverpine, live = 75 } } })
		local r = ns.Route.Upcoming(9)
		T.eq(r.step, 87); T.eq(r.ahead, 12); T.eq(r.active, true); T.eq(r.tab, 1); T.eq(r.guide, "Silverpine Forest")
		T.eq(ns.Route.Tag(r), "in 12 steps")
		T.eq(ns.Route.Line(r), "On your Polestar route: Silverpine Forest, step 87 (12 steps ahead)")
		T.eq(ns.Route.StepOf, ns.Route.Upcoming, "the browser's env.routeStep")
		_G.Polestar = nil
	end,
	this_step = function()
		local ns = fake({ tabs = { { guide = silverpine, live = 87 } } })
		local r = ns.Route.Upcoming(9)
		T.eq(r.ahead, 0); T.eq(ns.Route.Tag(r), "(this step)")
		T.ok(ns.Route.Line(r):find("step 87 (this step)", 1, true), ns.Route.Line(r))
		T.eq(ns.Route.Tag({ ahead = 1, active = true, guide = "X" }), "in 1 step")
		_G.Polestar = nil
	end,
	-- A turn-in already passed (step < live) or a quest already completed: not upcoming.
	passed_or_completed = function()
		local ns = fake({ tabs = { { guide = silverpine, live = 75 } }, done = { [7] = true } })
		T.eq(ns.Route.Upcoming(5), nil, "step 60 is behind step 75")
		T.eq(ns.Route.Upcoming(7), nil, "turned in already")
		T.eq(ns.Route.Upcoming(424242), nil, "not on any guide")
		_G.Polestar = nil
	end,
	-- Other open tabs, after the active guide: the tab's guide named, steps from that tab's live step.
	other_tab = function()
		local ns = fake({ tabs = { { guide = silverpine, live = 75 }, { guide = barrens, live = 10 } } })
		local r = ns.Route.Upcoming(11)
		T.eq(r.active, false); T.eq(r.tab, 2); T.eq(r.step, 40); T.eq(r.ahead, 30); T.eq(r.guide, "The Barrens")
		T.eq(ns.Route.Tag(r), "The Barrens, in 30 steps")
		T.eq(ns.Route.Upcoming(12).ahead, 0, "the Barrens tab's own live step")
		T.eq(ns.Route.Tag(ns.Route.Upcoming(12)), "The Barrens, this step")
		_G.Polestar = nil
	end,
	-- The guide the active one hands off to (Engine.NextGuide): counted over the rest of this guide.
	next_guide = function()
		local ns = fake({ tabs = { { guide = barrens, live = 50 } }, extra = { stonetalon },
			next = { ["h/barrens"] = "h/stonetalon" } })
		local r = ns.Route.Upcoming(13)
		T.eq(r.next, true); T.eq(r.active, false); T.eq(r.step, 5); T.eq(r.ahead, 15, "10 left here + 5")
		T.eq(ns.Route.Tag(r), "next guide: Stonetalon")
		_G.Polestar = nil
	end,
	-- A step the player skipped in Polestar (CharState().skipped) is not where it is turned in.
	skipped_step = function()
		local ns = fake({ tabs = { { guide = silverpine, live = 75 } }, skipped = { ["h/silverpine"] = { [87] = true } } })
		T.eq(ns.Route.Upcoming(9), nil)
		_G.Polestar = nil
	end,
	-- Polestar's own hand-in plan (Core/RoutePlan.lua GetTurnIn) when it has one: its answer, counted.
	route_plan = function()
		local answers = {
			[9] = { status = "future", guide = "h/silverpine", title = "Silverpine Forest", step = 87, chapter = 2 },
			[13] = { status = "later", guide = "h/stonetalon", title = "Stonetalon", step = 5, chapter = 3 },
			[11] = { status = "other", via = "future", guide = "h/barrens", title = "The Barrens", step = 40, chapter = 1 },
			[5] = { status = "missed", guide = "h/silverpine", step = 60 },
			[14] = { status = "later", guide = "h/far", title = "Far Away", carried = true },
			[15] = { status = "unplanned" },
		}
		local ns = fake({ tabs = { { guide = silverpine, live = 75 }, { guide = barrens, live = 10 } }, extra = { stonetalon },
			next = { ["h/silverpine"] = "h/stonetalon" }, plan = function(q) return answers[q] end })
		local r = ns.Route.Upcoming(9)
		T.eq(r.ahead, 12); T.eq(r.active, true); T.eq(r.tab, 1)
		r = ns.Route.Upcoming(13)
		T.eq(r.next, true); T.eq(r.ahead, 30, "25 left in Silverpine + 5")
		r = ns.Route.Upcoming(11)
		T.eq(r.tab, 2); T.eq(r.ahead, 30); T.eq(r.active, false)
		T.eq(ns.Route.Upcoming(5), nil, "missed: behind")
		T.eq(ns.Route.Upcoming(15), nil)
		r = ns.Route.Upcoming(14)
		T.eq(r.ahead, nil); T.eq(ns.Route.Tag(r), "next guide: Far Away"); T.eq(ns.Route.Line(r), "On your Polestar route: Far Away")
		_G.Polestar.RoutePlan.GetTurnIn = function() error("changed upstream") end
		ns.Route.Reset()
		T.eq(ns.Route.Upcoming(9).ahead, 12, "an erroring plan: our own scan")
		_G.Polestar = nil
	end,
	-- Polestar internals that changed (GetGuide errors, steps not a list, a goal not a table): no route
	-- tag, no error.
	guarded = function()
		_G.Polestar = { Engine = { GetGuide = function() error("changed upstream") end } }
		local R = T.addon({ "Core.lua", "Route.lua" }).Route
		T.eq(R.Upcoming(9), nil)
		_G.Polestar.Engine.GetGuide = function() return { steps = { "odd", { goals = { 5, { t = "turnin", quest = 9 } } } } } end
		R.Reset()
		T.eq(R.Upcoming(9).step, 2, "no live step known: from the first")
		_G.Polestar = { Engine = "gone" }
		R.Reset()
		T.eq(R.Upcoming(9), nil)
		_G.Polestar = { Engine = { GetGuide = function() return silverpine end, TabLiveSteps = function() error("x") end,
			GetStepIndex = function() return 75 end, StepNumberOf = function() error("y") end } }
		R.Reset()
		T.eq(R.Upcoming(9).ahead, 12)
		_G.Polestar = nil
	end,
	-- Polestar numbers steps as the player sees them (Engine.StepNumberOf: steps not theirs left out).
	step_numbers = function()
		local ns, P = fake({ tabs = { { guide = silverpine, live = 75 } } })
		P.Engine.StepNumberOf = function(g, i) return i - 2 end
		P.Engine.StepTotalOf = function(g) return #g.steps - 2 end
		local r = ns.Route.Upcoming(9)
		T.eq(r.step, 85); T.eq(r.index, 87); T.eq(r.ahead, 12)
		_G.Polestar = nil
	end,
	-- A step change (STEP_CHANGED), a tab's live step moving (TABS_CHANGED) and GUIDE_CHANGED forget
	-- the answers and tell the window (ROUTE_CHANGED); a TABS_CHANGED with no tab moved (a kill that
	-- counted) does not; QUEST_TURNED_IN forgets them (the window rebuilds for it already).
	step_change_event = function()
		local ns, P, h = fake({ tabs = { { guide = silverpine, live = 75 } } })
		local fired = 0
		ns.On("ROUTE_CHANGED", function() fired = fired + 1 end)
		T.eq(ns.Route.Upcoming(9).ahead, 12)
		P._tabs[1].live = 80
		T.eq(ns.Route.Upcoming(9).ahead, 12, "kept until Polestar says")
		h.STEP_CHANGED(80)
		T.eq(fired, 1); T.eq(ns.Route.Upcoming(9).ahead, 7)
		h.TABS_CHANGED({})
		T.eq(fired, 1, "same tabs, same live steps: nothing")
		P._tabs[1].live = 81
		h.TABS_CHANGED({})
		T.eq(fired, 2); T.eq(ns.Route.Upcoming(9).ahead, 6)
		h.GUIDE_CHANGED("x")
		T.eq(fired, 3)
		P._tabs[1].live = 82
		ns._frame.scripts.OnEvent(ns._frame, "QUEST_TURNED_IN", 9, 0, 0)
		T.eq(fired, 3, "the window rebuilds for a turn-in itself")
		T.eq(ns.Route.Upcoming(9).ahead, 5, "but the answers are forgotten")
		P._tabs[1].live = 88
		h.STEP_CHANGED(88)
		T.eq(ns.Route.Upcoming(9), nil, "walked past its turn-in")
		_G.Polestar = nil
	end,
	-- The game tooltip's line: an item that a quest on the route rewards (Codex, only while loaded).
	item_line = function()
		local ns, P, h = fake({ tabs = { { guide = silverpine, live = 75 } } })
		local reads = 0
		P.Codex = { IsLoaded = function() return true end,
			Item = function(id) reads = reads + 1 return id == 100 and { sources = { { type = "drop", npc = 1 }, { type = "quest", quest = 9 } } } or nil end,
			Quest = function(q) return q == 9 and { id = 9, title = "Assault on Fenris Isle" } or nil end }
		T.eq(ns.Route.ItemLine(100), "Polestar: in 12 steps (Assault on Fenris Isle)")
		T.eq(ns.Route.ItemLine(100), "Polestar: in 12 steps (Assault on Fenris Isle)")
		T.eq(reads, 1, "cached per item")
		T.eq(ns.Route.ItemLine(101), nil)
		P._tabs[1].live = 80
		h.STEP_CHANGED(80)
		T.eq(ns.Route.ItemLine(100), "Polestar: in 7 steps (Assault on Fenris Isle)", "a step change invalidates")
		P.Codex.IsLoaded = function() return false end
		ns.Route.Reset()
		T.eq(ns.Route.ItemLine(100), nil, "never loads the Codex for a tooltip")
		_G.Polestar = nil
	end,
}
