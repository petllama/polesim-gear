-- Where an upgrade comes from, read at runtime from Polestar's Codex (never copied into this addon:
-- it holds QuestieDB-derived facts). Five kinds: quest rewards, dungeon drops, crafted items (with the
-- website's gates), vendors (faction-gated) and BoE / World (world drops by level, open-world mob drops).
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
-- generic: the item is a generic world drop (Sources.GenericWorld): its in-instance drops and containers
-- are BoE / World views (with `where`), never dungeon ones.
function Sources.View(src, codex, player, lim, generic)
	if src.type == "quest" then
		local q = codex.Quest(src.quest)
		if not q then return nil end
		local ok, why = Sources.QuestOk(q, player, lim)
		local zone = call(codex, "Zone", q.zone)
		return {
			kind = "quest", ok = ok, why = why, questId = q.id, where = zone and zone.name or nil,
			title = q.title, level = q.level, zoneId = q.zone, elite = Sources.Elite(q, player.faction),
			text = "Quest: " .. (q.title or "?") .. ns.LevelText(q.level, " (", ")") .. (src.choice and ", a choice" or ""),
			needs = ok and Sources.Needs(q, codex, player.completed) or nil,
		}
	elseif src.type == "drop" then
		local npc = call(codex, "Npc", src.npc)
		local key = src.instance or (npc and npc.instance)
		if not key then
			-- An open-world drop: the BoE / World kind. The zone's name is read only where it is shown
			-- (Groups, the tooltip): a world item can have dozens of these. An unknown mob: nothing to
			-- show (and a Codex without Npc, changed upstream, gives no source: test `views_guarded`).
			if not npc then return nil end
			local ok, why = true, nil
			if npc.level and npc.level > lim + 5 then ok, why = false, "mob level " .. npc.level end
			local sp = type(npc.spawns) == "table" and npc.spawns[1] or nil
			return {
				kind = "world", ok = ok, why = why, npcId = src.npc, npcName = npc.name, npcLevel = npc.level,
				chance = src.chance, zoneId = sp and sp.map or nil,
				spot = sp and { map = sp.map, x = sp.x, y = sp.y } or nil,
				text = "Drop: " .. (npc.name or "?") .. (npc.level and (" (" .. npc.level .. ")") or "")
					.. (src.chance and string.format(", %g%%", src.chance) or ""),
			}
		end
		local inst = call(codex, "Instance", key)
		if generic then
			-- A generic world drop seen in an instance: BoE / World, saying where it was seen.
			local ok, why = true, nil
			if npc and npc.level and npc.level > lim + 5 then ok, why = false, "mob level " .. npc.level end
			return {
				kind = "world", ok = ok, why = why, npcId = src.npc, npcName = npc and npc.name, npcLevel = npc and npc.level,
				chance = src.chance, where = inst and inst.name or key,
				text = "Drop: " .. (npc and npc.name or "?") .. (src.chance and string.format(", %g%%", src.chance) or ""),
			}
		end
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
		if generic then
			return {
				kind = "world", ok = true, where = inst and inst.name or key, chance = src.chance,
				text = "Container: " .. (obj.name or "?") .. (src.chance and string.format(", %g%%", src.chance) or ""),
			}
		end
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
	elseif src.type == "world" then
		-- Drops anywhere from mobs of these levels (the Codex's world-drop table): luck, not a place.
		return {
			kind = "world", ok = true, minLevel = src.minLevel, maxLevel = src.maxLevel,
			text = "World drop" .. (src.minLevel and string.format(", levels %d-%d", src.minLevel, src.maxLevel or src.minLevel) or ""),
		}
	elseif src.type == "vendor" then
		-- A vendor of the other side only is not one the character can buy from; "AH" and unknown are (and
		-- every vendor when the character's side is unknown: Context gives nil for Neutral).
		local npc = call(codex, "Npc", src.npc)
		local fac = npc and npc.faction
		if player.faction and type(fac) == "string" and fac ~= "" and not fac:find(player.faction, 1, true) then return nil end
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

Sources.WORLD_KEEP = 3 -- open-world drops kept per item (usable ones first, then the best chances): the rest is noise
-- views (in source order) -> the same, with only WORLD_KEEP open-world drops: the usable ones (mob level
-- within the limit) first, then by chance (stable), so a likelier too-high mob never hides usable drops.
local function keepBestDrops(views)
	local drops = {}
	for i, v in ipairs(views) do
		if v.kind == "world" and v.npcId then drops[#drops + 1] = { v = v, i = i } end
	end
	table.sort(drops, function(a, b)
		if a.v.ok ~= b.v.ok then return a.v.ok end
		if (a.v.chance or 0) ~= (b.v.chance or 0) then return (a.v.chance or 0) > (b.v.chance or 0) end
		return a.i < b.i
	end)
	local out = {}
	for _, v in ipairs(views) do
		if not (v.kind == "world" and v.npcId) then out[#out + 1] = v end
	end
	for k = 1, math.min(#drops, Sources.WORLD_KEEP) do out[#out + 1] = drops[k].v end
	return out
end

Sources.STANDINGS = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }

-- " (needs <Faction>: <Standing>)" for an item with a reputation gate (the shipped `rep`: faction id,
-- standing 0 Hated .. 7 Exalted; armory._rep_note), else "". The faction's name from the Codex.
function Sources.RepNote(it, codex)
	local r = it and it.rep
	if not r then return "" end
	local ok, f = pcall(call, codex, "Faction", r[1])
	local name = ok and type(f) == "table" and f.name or ("faction " .. r[1])
	return " (needs " .. name .. ": " .. (Sources.STANDINGS[r[2] + 1] or ("standing " .. r[2])) .. ")"
end

-- Sources with no level of their own (a vendor, a container in a dungeon): an item with no required
-- level from one follows the item-level rule (ns.LevelLessGate, shared with the AH scan).
local LEVEL_LESS = { vendor = true, object = true }

-- Whether an item is a generic world drop: green or lower (the shipped quality, else the Codex's) with a
-- world (level-range) source. Every mob of those levels can drop it, so a drop inside a dungeon is luck,
-- not that dungeon's loot: BoE / World only. Boss loot (no world source) and blue+ items found in a
-- dungeon stay dungeon items. The website's armory.generic_world_drop (parity fixture `W` rows).
function Sources.GenericWorld(rec, it)
	local q = it and it.q or rec and rec.quality
	if type(q) ~= "number" or q > 2 or type(rec) ~= "table" or type(rec.sources) ~= "table" then return false end
	for _, src in ipairs(rec.sources) do
		if type(src) == "table" and src.type == "world" then return true end
	end
	return false
end

-- Primary professions (Classic skill lines, as Polestar's Compat.SKILL_LINES); secondary ones (Cooking,
-- First Aid, Fishing) never count. English names for clients that give names only.
Sources.PRIMARY = { [171] = "alchemy", [164] = "blacksmithing", [333] = "enchanting", [202] = "engineering",
	[182] = "herbalism", [165] = "leatherworking", [186] = "mining", [393] = "skinning", [197] = "tailoring" }
local LINE_OF = {}
for line, name in pairs(Sources.PRIMARY) do LINE_OF[name] = line end
Sources.MAX_PRIMARY = 2

-- The character's primary professions -> { lines = { [skillLine] = true }, n } | nil (the client can't
-- say). Read from GetProfessions, else C_SkillInfo by id or by index, else the Classic skill list.
function Sources.Professions()
	local lines, n = {}, 0
	local function add(line)
		if Sources.PRIMARY[line] and not lines[line] then lines[line], n = true, n + 1 end
	end
	if type(GetProfessions) == "function" and type(GetProfessionInfo) == "function" then
		local ok, p1, p2 = pcall(GetProfessions)
		if ok then
			for _, idx in ipairs({ p1 or false, p2 or false }) do
				if idx then
					local okInfo, _, _, _, _, _, _, line = pcall(GetProfessionInfo, idx)
					if okInfo then add(line) end
				end
			end
			return { lines = lines, n = n }
		end
	end
	local S = C_SkillInfo
	if type(S) == "table" and type(S.GetSkillLineInfoByID) == "function" then
		local answered = false
		for line in pairs(Sources.PRIMARY) do
			local ok, info = pcall(S.GetSkillLineInfoByID, line)
			if ok then answered = true end
			if ok and type(info) == "table" and not info.isHeader
				and ((tonumber(info.rank) or 0) > 0 or (tonumber(info.maxRank) or 0) > 0) then add(line) end
		end
		if answered then return { lines = lines, n = n } end
	end
	if type(S) == "table" and type(S.GetNumSkillLines) == "function" and type(S.GetSkillLineInfo) == "function" then
		local ok, count = pcall(S.GetNumSkillLines)
		if ok and type(count) == "number" then
			for i = 1, count do
				local okInfo, info = pcall(S.GetSkillLineInfo, i)
				if okInfo and type(info) == "table" and not info.isHeader then
					add(info.skillID or LINE_OF[type(info.name) == "string" and info.name:lower() or ""])
				end
			end
			return { lines = lines, n = n }
		end
	end
	if type(GetNumSkillLines) == "function" and type(GetSkillLineInfo) == "function" then
		local ok, count = pcall(GetNumSkillLines)
		if ok and type(count) == "number" then
			for i = 1, count do
				local okInfo, name, header = pcall(GetSkillLineInfo, i)
				if okInfo and not header and type(name) == "string" then add(LINE_OF[name:lower()]) end
			end
			return { lines = lines, n = n }
		end
	end
	return nil
end

-- Bind on pickup: the shipped item's binding (`bd` 1), else the client's (GetItemInfo bindType 1)
-- -> true | false | nil (unknown)
function Sources.IsBoP(it, id)
	if type(it) == "table" and type(it.bd) == "number" then return it.bd == 1 end
	local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	if not (id and type(get) == "function") then return nil end
	local ok, name, _, _, _, _, _, _, _, _, _, _, _, _, bind = pcall(get, id)
	if not (ok and name and type(bind) == "number") then return nil end
	return bind == 1
end

-- A crafted view the character can never use: the item binds on pickup, its profession is not one of
-- theirs and they already have MAX_PRIMARY primary professions. Unknown professions, binding or
-- profession: kept (never guessed).
function Sources.CraftBlocked(v, it, id, profs)
	if not (v and v.kind == "crafted" and type(profs) == "table" and (profs.n or 0) >= Sources.MAX_PRIMARY) then return false end
	local line = tonumber(v.skillLine) or LINE_OF[type(v.profession) == "string" and v.profession:lower() or ""]
	if not (line and Sources.PRIMARY[line]) or profs.lines[line] then return false end
	return Sources.IsBoP(it, id) == true
end

-- An item's browser sources; nil when Polestar marks it retired (hidden). it (optional): the shipped
-- item (rl, il, rep) for the item-level rule and the reputation note. Codex reads are Polestar
-- internals: one that errors (Polestar changed) drops that source, or all of the item's, and is kept in
-- Sources.lastError for the window; it never stops the browser. player.profs (Sources.Professions)
-- drops crafted sources the character can't use (Sources.CraftBlocked).
function Sources.For(id, codex, player, lim, it)
	local okRec, rec = pcall(codex.Item, id)
	if not okRec then
		Sources.lastError = rec
		return {}
	end
	if type(rec) ~= "table" then return {} end
	if rec.status == "retired" then return nil end
	local out = {}
	local srcs = type(rec.sources) == "table" and rec.sources or {}
	local generic = Sources.GenericWorld(rec, it)
	if generic then -- the world source first (the tooltip's first line)
		local first, rest = {}, {}
		for _, src in ipairs(srcs) do
			local t = type(src) == "table" and src.type == "world" and first or rest
			t[#t + 1] = src
		end
		for _, src in ipairs(rest) do first[#first + 1] = src end
		srcs = first
	end
	for _, src in ipairs(srcs) do
		local ok, v = pcall(Sources.View, src, codex, player, lim, generic)
		if not ok then
			Sources.lastError = v
		elseif v and Sources.CraftBlocked(v, it, id, player.profs) then
			-- a BoP craft of a profession the character can't take up any more: not a source
		elseif v then
			local gate = v.ok and LEVEL_LESS[src.type] and ns.LevelLessGate(it, lim)
			if gate then v.ok, v.why = false, gate end
			if it and it.rep and v.kind == "vendor" then v.text = v.text .. Sources.RepNote(it, codex) end
			out[#out + 1] = v
		end
	end
	return keepBestDrops(out)
end
