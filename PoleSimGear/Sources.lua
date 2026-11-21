-- Where an upgrade comes from, read at runtime from Polestar's Codex (never copied into this addon:
-- it holds QuestieDB-derived facts). The browser shows three kinds: quest rewards, dungeon drops and
-- crafted items, with the website's gates.
local ADDON, ns = ...
local Sources = {}
ns.Sources = Sources

-- Polestar.Codex is a Polestar internal (not in docs/API.md): guarded, nil when it is missing.
function Sources.Codex()
	local P = _G.Polestar
	local C = type(P) == "table" and P.Codex
	if type(C) == "table" and type(C.Item) == "function" and type(C.Quest) == "function" then return C end
	return nil
end

-- Whether a race mask lets a race in. Codex masks are doubles above 32 bits (Skyborne: 2^32 Alliance,
-- 2^33 Horde; whole-side masks 2^32 + 77, 2^33 + 178), past bit.band: tested with arithmetic, exact up
-- to 2^53. A mask with no bit above 2^32 is a Classic mask, not a Skyborne lock; nil/0/-1 = anyone;
-- raceBit nil (a race with no known bit) is never excluded.
local HIGH = 2 ^ 32
function Sources.RaceOk(mask, raceBit)
	if type(mask) ~= "number" or mask <= 0 or not raceBit then return true end
	if raceBit >= HIGH then
		if mask < HIGH then return true end
		return math.floor(mask / raceBit) % 2 == 1
	end
	return math.floor((mask % HIGH) / raceBit) % 2 == 1
end

-- q: a Codex quest; player: { faction "A"|"H", classBit, raceBit, completed(questId) }; lim: the highest
-- level the list is for. -> ok, why
function Sources.QuestOk(q, player, lim)
	if q.faction and q.faction ~= player.faction then return false, "other faction" end
	if (q.classes or 0) ~= 0 and bit.band(q.classes, player.classBit) == 0 then return false, "other classes" end
	if not Sources.RaceOk(q.races, player.raceBit) then return false, "other races" end
	if player.completed(q.id) then return false, "done" end
	local from = q.minLevel or ((q.level or 0) - 5)
	if from > lim then return false, "quest from level " .. from end
	if q.level and q.level > lim + 5 then return false, "level " .. q.level .. " quest" end
	return true
end

-- The first prerequisite not done yet (all of `pre`, one of `preAny`), as its title; nil when none.
function Sources.Needs(q, codex, completed)
	for _, id in ipairs(q.pre or {}) do
		if not completed(id) then
			local p = codex.Quest(id)
			return p and p.title or ("quest " .. id)
		end
	end
	local any = q.preAny or {}
	if #any == 0 then return nil end
	for _, id in ipairs(any) do
		if completed(id) then return nil end
	end
	local p = codex.Quest(any[1])
	return p and p.title or ("quest " .. any[1])
end

-- Whether a quest sends the character against hostile elites (an objective's Codex `elites` for the
-- character's side): the "elite" tag. The Codex has no group flag; this is the closest it gives.
function Sources.Elite(q, faction)
	for _, o in ipairs(type(q.objectives) == "table" and q.objectives or {}) do
		if type(o) == "table" and type(o.elites) == "table" and o.elites[faction] then return true end
	end
	return false
end

local function call(codex, name, arg)
	local fn = codex[name]
	if type(fn) ~= "function" or arg == nil then return nil end
	return fn(arg)
end

-- One Codex source -> { kind = "quest"|"dungeon"|"crafted"|"vendor"|"world", ok, why, text, where,
-- + the kind's grouping fields (quest: questId, title, level, zoneId, elite, needs; dungeon: instanceKey,
-- npcName, boss, container, chance, levels; crafted: profession, skill, skillLine; vendor: npcId,
-- npcName, cost, zoneId, spot) } | nil   (dungeon: a drop or a container in a dungeon)
function Sources.View(src, codex, player, lim)
	if src.type == "quest" then
		local q = codex.Quest(src.quest)
		if not q then return nil end
		local ok, why = Sources.QuestOk(q, player, lim)
		local zone = call(codex, "Zone", q.zone)
		return {
			kind = "quest", ok = ok, why = why, questId = q.id, where = zone and zone.name or nil,
			title = q.title, level = q.level, zoneId = q.zone, elite = Sources.Elite(q, player.faction),
			text = "Quest: " .. (q.title or "?") .. (q.level and (" (" .. q.level .. ")") or "") .. (src.choice and ", a choice" or ""),
			needs = ok and Sources.Needs(q, codex, player.completed) or nil,
		}
	elseif src.type == "drop" then
		local npc = call(codex, "Npc", src.npc)
		local key = src.instance or (npc and npc.instance)
		if not key then return nil end -- an open-world drop: not one of the browser's kinds
		local inst = call(codex, "Instance", key)
		if inst and inst.kind == "raid" then return nil end -- raids: a non-goal
		local ok, why = true, nil
		if npc and npc.level and npc.level > lim + 5 then ok, why = false, "boss level " .. npc.level end
		return {
			kind = "dungeon", ok = ok, why = why, where = inst and inst.name or key,
			instanceKey = key, npcName = npc and npc.name, boss = npc and npc.boss or false, chance = src.chance,
			levels = inst and inst.levels,
			text = "Drop: " .. (npc and npc.name or "?") .. ((npc and npc.boss) and " (boss)" or "")
				.. (src.chance and string.format(", %g%%", src.chance) or ""),
		}
	elseif src.type == "object" then
		-- A container inside a dungeon (chests, Rookery Eggs) is a dungeon source (the website's rule);
		-- open-world containers and raids are not the browser's kinds.
		local obj = call(codex, "Object", src.object)
		local key = obj and obj.instance
		if not key then return nil end
		local inst = call(codex, "Instance", key)
		if inst and inst.kind == "raid" then return nil end
		return {
			kind = "dungeon", ok = true, where = inst and inst.name or key,
			instanceKey = key, container = obj.name, chance = src.chance, levels = inst and inst.levels,
			text = "Container: " .. (obj.name or "?") .. (src.chance and string.format(", %g%%", src.chance) or ""),
		}
	elseif src.type == "craft" then
		-- Skill caps follow the level (armory: about level = skill / 5 when a leveling crafter gets there).
		local need = math.floor((src.skill or 0) / 5)
		return {
			kind = "crafted", ok = need <= lim, why = need > lim and ("skill " .. src.skill .. " (about level " .. need .. ")") or nil,
			profession = src.profession, skill = src.skill, skillLine = src.skillLine,
			text = "Crafted: " .. (src.profession or "a profession") .. (src.skill and (" " .. src.skill) or ""),
		}
	elseif src.type == "vendor" then
		-- A vendor of the other side only is not one the character can buy from; "AH" and unknown are.
		local npc = call(codex, "Npc", src.npc)
		local fac = npc and npc.faction
		if type(fac) == "string" and fac ~= "" and not fac:find(player.faction, 1, true) then return nil end
		local sp = npc and type(npc.spawns) == "table" and npc.spawns[1] or nil
		local zone = sp and call(codex, "Zone", sp.map)
		return {
			kind = "vendor", ok = true, npcId = src.npc, npcName = npc and npc.name or nil, cost = src.cost,
			zoneId = sp and sp.map or nil, where = zone and zone.name or nil,
			spot = sp and { map = sp.map, x = sp.x, y = sp.y } or nil,
			text = "Vendor: " .. (npc and npc.name or "?"),
		}
	end
	return nil
end

-- An item's browser sources; nil when Polestar marks it retired (hidden). Codex reads are Polestar
-- internals: one that errors (Polestar changed) drops that source, or all of the item's, and is kept in
-- Sources.lastError for the window; it never stops the browser.
function Sources.For(id, codex, player, lim)
	local okRec, rec = pcall(codex.Item, id)
	if not okRec then
		Sources.lastError = rec
		return {}
	end
	if type(rec) ~= "table" then return {} end
	if rec.status == "retired" then return nil end
	local out = {}
	for _, src in ipairs(type(rec.sources) == "table" and rec.sources or {}) do
		local ok, v = pcall(Sources.View, src, codex, player, lim)
		if not ok then
			Sources.lastError = v
		elseif v then
			out[#out + 1] = v
		end
	end
	return out
end
