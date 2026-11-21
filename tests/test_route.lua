local T = require("t")
return {
	build = function()
		local R = T.addon({ "Core.lua", "Route.lua" }).Route
		local map = R.Build({ steps = {
			{ goals = { { t = "accept", quest = 1 } } },
			{ goals = { { t = "turnin", quest = 1 }, { t = "turnin", quest = 2 } } },
			{ goals = { { t = "turnin", quest = 1 } } },
		} })
		T.eq(map[1], 2); T.eq(map[2], 2); T.eq(map[3], nil)
		T.eq(next(R.Build(nil)), nil)
	end,
	step_of_reads_polestar = function()
		_G.Polestar = { Engine = { GetGuide = function() return { steps = { { goals = { { t = "turnin", quest = 9 } } } } } end } }
		local R = T.addon({ "Core.lua", "Route.lua" }).Route
		R.Reset()
		T.eq(R.StepOf(9), 1)
		_G.Polestar = nil
	end,
	-- Polestar internals that changed (GetGuide errors, steps not a list, a goal not a table): no route
	-- tag, no error.
	step_of_guarded = function()
		_G.Polestar = { Engine = { GetGuide = function() error("changed upstream") end } }
		local R = T.addon({ "Core.lua", "Route.lua" }).Route
		T.eq(R.StepOf(9), nil)
		_G.Polestar.Engine.GetGuide = function() return { steps = { "odd", { goals = { 5, { t = "turnin", quest = 9 } } } } } end
		R.Reset()
		T.eq(R.StepOf(9), 2)
		_G.Polestar = { Engine = "gone" }
		R.Reset()
		T.eq(R.StepOf(9), nil)
		_G.Polestar = nil
	end,
	-- Polestar's public GUIDE_CHANGED forgets the map and tells the window (ROUTE_CHANGED).
	guide_changed = function()
		local handlers = {}
		local steps = { { goals = { { t = "turnin", quest = 9 } } } }
		_G.Polestar = { On = function(msg, fn) handlers[msg] = fn end, Engine = { GetGuide = function() return { steps = steps } end } }
		local ns = T.addon({ "Core.lua", "Route.lua" })
		local fired = 0
		ns.On("ROUTE_CHANGED", function() fired = fired + 1 end)
		T.eq(ns.Route.StepOf(9), 1)
		steps = { { goals = {} }, { goals = { { t = "turnin", quest = 9 } } } }
		T.eq(ns.Route.StepOf(9), 1, "kept until the guide changes")
		handlers.GUIDE_CHANGED("next")
		T.eq(fired, 1)
		T.eq(ns.Route.StepOf(9), 2)
		_G.Polestar = nil
	end,
}
