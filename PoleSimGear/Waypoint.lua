-- "Waypoint" on a source: Polestar's documented Nav API (Polestar.Nav.API, version 1: Navigate(owner,
-- uiMapID, x, y, title), x and y 0-1). Without it, or another version (its calls may differ), no button.
local ADDON, ns = ...
local Waypoint = {}
ns.Waypoint = Waypoint

local function api()
	local P = _G.Polestar
	local N = type(P) == "table" and P.Nav
	local A = type(N) == "table" and N.API
	if type(A) == "table" and A.version == 1 and type(A.Navigate) == "function" then return A end
	return nil
end

function Waypoint.Available() return api() ~= nil end

-- Codex reads are Polestar internals: guarded (an error or a non-table is no answer).
local function call(codex, name, arg)
	local fn = codex[name]
	if type(fn) ~= "function" or arg == nil then return nil end
	local ok, v = pcall(fn, arg)
	return ok and type(v) == "table" and v or nil
end

-- Codex places are percent (0-100); the Nav API takes 0-1.
local function spot(p, title)
	if not (p and p.map and p.x and p.y) then return nil end
	return { map = p.map, x = p.x / 100, y = p.y / 100, title = title }
end

-- A source view (Sources.View) -> { map, x, y (0-1), title } | nil
function Waypoint.SpotOf(src, codex)
	if src.kind == "dungeon" then
		local inst = call(codex, "Instance", src.instanceKey)
		return inst and spot(inst.entrance, inst.name)
	elseif src.kind == "quest" then
		local q = call(codex, "Quest", src.questId)
		local npcId = q and type(q.start) == "table" and type(q.start.npc) == "table" and q.start.npc[1]
		local npc = npcId and call(codex, "Npc", npcId)
		local sp = npc and type(npc.spawns) == "table" and npc.spawns[1]
		return spot(sp, (src.title or "Quest") .. (npc and npc.name and (" (" .. npc.name .. ")") or ""))
	elseif src.kind == "vendor" or src.kind == "world" then
		return spot(src.spot, src.npcName)
	end
	return nil
end

function Waypoint.Go(s)
	local A = api()
	if not (A and s) then return false end
	local ok, res = pcall(A.Navigate, ADDON, s.map, s.x, s.y, s.title)
	return ok and res == true
end

-- Quest details in Polestar's Lookup (the Codex pages: sources, chain, "Guide me"). Shift-click on a
-- quest-sourced row (window rows never link to chat, so Shift is free) or the right-click menu.
-- Polestar.Lookup.Show(query, kind, id) is not in its documented API: read at call time, guarded; a
-- Polestar without it gets one chat line. With Lookup turned off Polestar prints its own message.
local Lookup = {}
ns.Lookup = Lookup
Lookup.HINT = "Shift-click: quest details in Polestar"
Lookup.MISSING = "Update Polestar to open quests in its Lookup"

local function show()
	local P = _G.Polestar
	local L = type(P) == "table" and P.Lookup
	local fn = type(L) == "table" and L.Show
	return type(fn) == "function" and fn or nil
end
function Lookup.Available() return show() ~= nil end

-- the modifier that opens the quest (Shift)
function Lookup.Modifier() return IsShiftKeyDown and IsShiftKeyDown() and true or false end

-- An item's quest source to open, in the row's own order (sources as listed): the one on the Polestar
-- route (the row's "in N steps" tag, a near quest's), else the first available one, else the first.
-- sources: Sources.View list | nil -> source | nil
function Lookup.QuestSource(sources)
	local route, ok, first
	for _, s in ipairs(sources or {}) do
		if type(s) == "table" and s.kind == "quest" and s.questId then
			first = first or s
			if s.ok ~= false then ok = ok or s end
			if s.route then route = route or s end
		end
	end
	return route or ok or first
end

-- questId -> true when Polestar was asked to show it; else one chat line and false
function Lookup.OpenQuest(questId)
	if not questId then return false end
	local fn = show()
	if not fn then
		ns.Print(Lookup.MISSING)
		return false
	end
	if pcall(fn, nil, "quest", questId) then return true end
	ns.Print("Polestar could not open quest " .. tostring(questId) .. " in its Lookup")
	return false
end

-- A row click: with the modifier and a quest -> opened (true: the click is used); else false
function Lookup.Click(questId, button)
	if not questId or (button and button ~= "LeftButton") or not Lookup.Modifier() then return false end
	Lookup.OpenQuest(questId)
	return true
end

-- the right-click menu entry for a quest source | nil
function Lookup.MenuItem(src)
	if not (src and src.questId) then return nil end
	return { text = "Open quest in Polestar: " .. (src.title or ("quest " .. src.questId)),
		onClick = function() Lookup.OpenQuest(src.questId) end }
end
