-- "On your route": quest rewards of the player's active Polestar guide. Polestar.Engine.GetGuide and
-- a guide's steps are Polestar internals (guarded); GUIDE_CHANGED and Polestar.On are its public API.
-- Engine.GetGuide() is the guide of Polestar's active tab (Core/Engine.lua); its `steps` may be
-- deferred (Guides.Steps decodes them on the first read), so they are read here only on demand.
local ADDON, ns = ...
local Route = {}
ns.Route = Route

-- guide -> { [questId] = index of the first step that turns it in }
function Route.Build(guide)
	local map = {}
	local steps = type(guide) == "table" and guide.steps
	for i, st in ipairs(type(steps) == "table" and steps or {}) do
		local goals = type(st) == "table" and st.goals
		for _, g in ipairs(type(goals) == "table" and goals or {}) do
			if type(g) == "table" and g.t == "turnin" and g.quest and not map[g.quest] then map[g.quest] = i end
		end
	end
	return map
end

local map
function Route.Reset() map = nil end

function Route.StepOf(questId)
	if not map then
		local P = _G.Polestar
		local E = type(P) == "table" and P.Engine
		local guide
		if type(E) == "table" and type(E.GetGuide) == "function" then
			local ok, g = pcall(E.GetGuide)
			guide = ok and g or nil
		end
		local ok, m = pcall(Route.Build, guide) -- reading steps may decode a deferred guide
		map = ok and m or {}
	end
	return map[questId]
end

local P = _G.Polestar
if type(P) == "table" and type(P.On) == "function" then
	pcall(P.On, "GUIDE_CHANGED", function()
		Route.Reset()
		ns.Fire("ROUTE_CHANGED")
	end)
end
