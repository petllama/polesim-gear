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
