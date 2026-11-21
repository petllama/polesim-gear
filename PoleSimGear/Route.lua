-- "On your route": the quest rewards the player's Polestar guides turn in AHEAD of where they are, and
-- how many steps ahead. Everything read here is a Polestar internal (not docs/API.md) and guarded
-- (type checks + pcall); its messages are the public bus (Polestar.On):
--   Engine.GetGuide()          the active tab's guide (Core/Engine.lua)
--   Engine.GetLiveStep()       the active tab's live step (first open step; nil: guide complete),
--                              else Engine.GetStepIndex() (the step shown) on an older Polestar
--   Engine.TabLiveSteps()      { { guide, live } } every open tab, in tab order (no tab is loaded)
--   Engine.NextGuide(id)       the guide Polestar hands off to after id (nil: none, or a choice to make)
--   Engine.StepNumberOf(g, i)  step i as the player counts it (steps not theirs left out); StepTotalOf(g)
--   RoutePlan.GetTurnIn(q)     Polestar's own hand-in plan over the open tabs' guide chains (class/race
--                              steps, skips, route choices): { status = now|future|later|other|missed|
--                              skipped|unplanned|choice|unloaded|noGuide, guide, title, step, via }
--   Guides.Get(id), CharState().skipped[guideId][step], Compat.IsQuestCompleted(q), Codex (tooltip)
-- Without RoutePlan (or when it errors) the steps are scanned here: the active tab from its live
-- step, then the other tabs from theirs, then the guides the active one hands off to.
-- A guide's `steps` may be deferred (Guides.Steps decodes them on the first read): read on demand.
local ADDON, ns = ...
local Route = {}
ns.Route = Route

local format = string.format
local MAX_HOPS = 20 -- guides walked along a chain

local function PS()
	local P = _G.Polestar
	return type(P) == "table" and P or nil
end
local function engine()
	local P = PS()
	return P and type(P.Engine) == "table" and P.Engine or nil
end
-- obj[name](...) guarded: ok, value
local function call(obj, name, ...)
	local fn = type(obj) == "table" and obj[name]
	if type(fn) ~= "function" then return false end
	local ok, v = pcall(fn, ...)
	if not ok then return false end
	return true, v
end

-- guide -> { [questId] = { step indexes that turn it in, ascending } }
function Route.Build(guide)
	local map = {}
	local steps = type(guide) == "table" and guide.steps
	for i, st in ipairs(type(steps) == "table" and steps or {}) do
		local goals = type(st) == "table" and st.goals
		for _, g in ipairs(type(goals) == "table" and goals or {}) do
			if type(g) == "table" and g.t == "turnin" and g.quest then
				local list = map[g.quest]
				if not list then list = {}; map[g.quest] = list end
				if list[#list] ~= i then list[#list + 1] = i end
			end
		end
	end
	return map
end

local cache, items, built = {}, {}, setmetatable({}, { __mode = "k" })
local signature
function Route.Reset() cache, items, built = {}, {}, setmetatable({}, { __mode = "k" }) end

local function getGuide(id)
	local P = PS()
	local ok, g = call(P and P.Guides, "Get", id)
	return ok and type(g) == "table" and g or nil
end
local function num(g, i)
	local ok, n = call(engine(), "StepNumberOf", g, i)
	return ok and type(n) == "number" and n or i
end
local function total(g)
	local ok, n = call(engine(), "StepTotalOf", g)
	if ok and type(n) == "number" then return n end
	return type(g.steps) == "table" and #g.steps or 0
end

-- The active tab's live step: nil when its guide is complete; 1 when Polestar cannot say.
local function activeLive(E)
	if type(E.GetLiveStep) == "function" then
		local ok, v = pcall(E.GetLiveStep)
		if ok then return type(v) == "number" and v or nil end
	end
	local ok, v = call(E, "GetStepIndex")
	return ok and type(v) == "number" and v or 1
end

-- The open tabs: { { guide, live, active, tab } }, the active one first.
local function tabs()
	local E = engine()
	if not E then return {} end
	local ok, active = call(E, "GetGuide")
	active = ok and type(active) == "table" and active or nil
	local out = {}
	local okT, list = call(E, "TabLiveSteps")
	if okT and type(list) == "table" then
		for i, t in ipairs(list) do
			if type(t) == "table" and type(t.guide) == "table" then
				local isActive = t.guide == active
				local live = isActive and activeLive(E) or (type(t.live) == "number" and t.live or nil)
				local row = { guide = t.guide, live = live, active = isActive, tab = i }
				if isActive then table.insert(out, 1, row) else out[#out + 1] = row end
			end
		end
	end
	if active and not (out[1] and out[1].active) then table.insert(out, 1, { guide = active, live = activeLive(E), active = true }) end
	return out
end

local function sig()
	local parts = {}
	for _, t in ipairs(tabs()) do parts[#parts + 1] = tostring(t.guide.id or t.guide) .. ":" .. tostring(t.live) .. (t.active and "*" or "") end
	return table.concat(parts, ",")
end

local function completed(q)
	local P = PS()
	local ok, done = call(P and P.Compat, "IsQuestCompleted", q)
	if ok then return done == true end
	local ok2, d2 = call(_G.C_QuestLog, "IsQuestFlaggedCompleted", q)
	return ok2 and d2 == true
end

local function skippedIn(g)
	local ok, s = call(PS(), "CharState")
	local sk = ok and type(s) == "table" and type(s.skipped) == "table" and s.skipped[g.id]
	return type(sk) == "table" and sk or nil
end

-- Steps from guide g's live step to step toIdx of guide toId, along g's chain (NextGuide); nil: not reached.
local function chainAhead(g, live, toId, toIdx)
	if g.id == toId then return num(g, toIdx) - num(g, live) end
	local E, id, acc = engine(), g.id, total(g) - num(g, live)
	for _ = 1, MAX_HOPS do
		local ok, nextId = call(E, "NextGuide", id)
		if not (ok and nextId) then return nil end
		id = nextId
		local h = getGuide(id)
		if id == toId then return acc + (h and num(h, toIdx) or toIdx) end
		if not h then return nil end
		acc = acc + total(h)
	end
	return nil
end

local function result(g, idx, ahead, tab, how)
	return { guide = g.title or tostring(g.id), guideId = g.id, step = num(g, idx), index = idx, ahead = ahead,
		tab = tab.tab, active = how == "active", next = how == "next" }
end

-- Our own scan: the first turn-in of q at or after `from` in g, not a skipped step.
local function firstAt(g, q, from)
	local map = built[g]
	if not map then
		local ok, m = pcall(Route.Build, g) -- reading steps may decode a deferred guide
		map = ok and m or {}
		built[g] = map
	end
	local sk = skippedIn(g)
	for _, i in ipairs(map[q] or {}) do
		if i >= from and not (sk and sk[i]) then return i end
	end
	return nil
end

local function scan(q, list)
	for _, t in ipairs(list) do
		if t.live then
			local i = firstAt(t.guide, q, t.live)
			if i then return result(t.guide, i, num(t.guide, i) - num(t.guide, t.live), t, t.active and "active" or "tab") end
		end
	end
	local a = list[1]
	if not (a and a.active and a.live) then return nil end
	local E, id = engine(), a.guide.id
	for _ = 1, MAX_HOPS do
		local ok, nextId = call(E, "NextGuide", id)
		if not (ok and nextId) then return nil end
		id = nextId
		local h = getGuide(id)
		if not h then return nil end
		local i = firstAt(h, q, 1)
		if i then return result(h, i, chainAhead(a.guide, a.live, id, i), a, "next") end
	end
	return nil
end

local AHEAD = { now = true, future = true, later = true }
-- Polestar's plan: r (a result or nil: not upcoming), answered (false: ask our own scan)
local function fromPlan(q, list)
	local P = PS()
	local ok, r = call(P and P.RoutePlan, "GetTurnIn", q)
	if not (ok and type(r) == "table" and type(r.status) == "string") then return nil, false end
	local other = r.status == "other"
	local st = other and r.via or r.status
	if not (AHEAD[st] or (other and r.dungeon)) then return nil, true end
	local how = (st == "later") and "next" or (other and "tab" or "active")
	local g = r.guide and getGuide(r.guide)
	local title = r.title or (g and g.title) or (r.guide and tostring(r.guide)) or "?"
	if type(r.step) ~= "number" then -- a later guide beyond the plan, or a dungeon open in a tab: no step
		return { guide = title, guideId = r.guide, active = false, next = how == "next" }, true
	end
	for _, t in ipairs(list) do
		if t.active ~= other and t.live then
			local ahead = chainAhead(t.guide, t.live, r.guide, r.step)
			if ahead and ahead >= 0 then
				local out = result(g or t.guide, r.step, ahead, t, how)
				out.guide = title
				return out, true
			end
		end
	end
	return { guide = title, guideId = r.guide, step = g and num(g, r.step) or r.step, index = r.step,
		active = how == "active", next = how == "next" }, true
end

-- questId -> { guide (title), guideId, tab, step (as the player counts it), index (raw), ahead (steps from
-- that tab's live step; 0 = this step; nil = unknown), active, next } | nil (not ahead on any route)
function Route.Upcoming(questId)
	if questId == nil then return nil end
	local hit = cache[questId]
	if hit ~= nil then return hit or nil end
	local r
	if not completed(questId) then
		local list = tabs()
		if signature == nil then signature = sig() end
		local answered
		r, answered = fromPlan(questId, list)
		if not answered then r = scan(questId, list) end
	end
	cache[questId] = r or false
	return r
end
Route.StepOf = Route.Upcoming -- the browser's env.routeStep (s.route)

local function plural(n) return format("%d step%s", n, n == 1 and "" or "s") end

-- The short blue tag of a row: "in 12 steps", "(this step)", "The Barrens, in 30 steps", "next guide: X".
function Route.Tag(r)
	if type(r) ~= "table" then return "on your route" end
	if r.active then
		if r.ahead == 0 then return "(this step)" end
		return r.ahead and ("in " .. plural(r.ahead)) or "on your route"
	end
	if r.next then return "next guide: " .. r.guide end
	if r.ahead == 0 then return r.guide .. ", this step" end
	if r.ahead then return r.guide .. ", in " .. plural(r.ahead) end
	return r.guide
end

-- The row tooltip's line: "On your Polestar route: <guide>, step 87 (12 steps ahead)".
function Route.Line(r)
	if type(r) ~= "table" then return "On your Polestar route" end
	local s = "On your Polestar route: " .. tostring(r.guide)
	if r.step then
		s = s .. ", step " .. r.step
		if r.ahead == 0 then s = s .. " (this step)"
		elseif r.ahead then s = s .. " (" .. plural(r.ahead) .. " ahead)" end
	end
	return s
end

local function better(a, b)
	if not b then return true end
	if a.active ~= b.active then return a.active end
	return (a.ahead or math.huge) < (b.ahead or math.huge)
end

-- The game tooltip's line for item id: "Polestar: in 12 steps (Assault on Fenris Isle)" | nil. Reads the
-- Codex only while it is loaded (never loads it for a tooltip); kept per item until the route changes.
function Route.ItemLine(id)
	local hit = items[id]
	if hit ~= nil then return hit or nil end
	local P = PS()
	local C = P and type(P.Codex) == "table" and P.Codex
	local okL, loaded = call(C, "IsLoaded")
	if not (okL and loaded) then return nil end
	local ok, rec = call(C, "Item", id)
	local best, bestQ
	for _, src in ipairs(ok and type(rec) == "table" and type(rec.sources) == "table" and rec.sources or {}) do
		if type(src) == "table" and src.type == "quest" and src.quest then
			local r = Route.Upcoming(src.quest)
			if r and better(r, best) then best, bestQ = r, src.quest end
		end
	end
	local line = false
	if best then
		local okQ, q = call(C, "Quest", bestQ)
		local title = okQ and type(q) == "table" and q.title or nil
		local tag = (best.active and best.ahead == 0) and "this step" or Route.Tag(best)
		line = "Polestar: " .. tag .. (title and (" (" .. title .. ")") or "")
	end
	items[id] = line
	return line or nil
end

-- Polestar moved: forget the answers and tell the window (ROUTE_CHANGED), but only when a tab's guide
-- or live step changed (TABS_CHANGED follows every goal ticked), or `force` (guide changed, quest done).
function Route.Changed(force)
	local now = sig()
	if not force and now == signature then return end
	signature = now
	Route.Reset()
	ns.Fire("ROUTE_CHANGED")
end

local P = PS()
if P and type(P.On) == "function" then
	pcall(P.On, "GUIDE_CHANGED", function() Route.Changed(true) end)
	pcall(P.On, "STEP_CHANGED", function() Route.Changed(false) end)
	pcall(P.On, "TABS_CHANGED", function() Route.Changed(false) end)
end
-- A quest turned in is no longer ahead; the window rebuilds for it itself (Window.lua, QUEST_TURNED_IN).
ns.RegisterEvent("QUEST_TURNED_IN", function() Route.Reset() end)
