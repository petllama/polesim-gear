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

-- q: a Codex quest; player: { faction "A"|"H", classBit, raceBit, completed(questId) }; lim: the highest
-- level the list is for. -> ok, why
function Sources.QuestOk(q, player, lim)
	if q.faction and q.faction ~= player.faction then return false, "other faction" end
	if (q.classes or 0) ~= 0 and bit.band(q.classes, player.classBit) == 0 then return false, "other classes" end
	if (q.races or 0) ~= 0 and bit.band(q.races, 0xFF) ~= 0xFF and bit.band(q.races, player.raceBit) == 0 then
		return false, "other races"
	end
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

local function call(codex, name, arg)
	local fn = codex[name]
	if type(fn) ~= "function" or arg == nil then return nil end
	return fn(arg)
end

-- One Codex source -> { kind = "quest"|"dungeon"|"crafted", ok, why, text, where, questId, needs } | nil
function Sources.View(src, codex, player, lim)
	if src.type == "quest" then
		local q = codex.Quest(src.quest)
		if not q then return nil end
		local ok, why = Sources.QuestOk(q, player, lim)
		local zone = call(codex, "Zone", q.zone)
		return {
			kind = "quest", ok = ok, why = why, questId = q.id, where = zone and zone.name or nil,
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
			text = "Drop: " .. (npc and npc.name or "?") .. ((npc and npc.boss) and " (boss)" or "")
				.. (src.chance and string.format(", %g%%", src.chance) or ""),
		}
	elseif src.type == "craft" then
		-- Skill caps follow the level (armory: about level = skill / 5 when a leveling crafter gets there).
		local need = math.floor((src.skill or 0) / 5)
		return {
			kind = "crafted", ok = need <= lim, why = need > lim and ("skill " .. src.skill .. " (about level " .. need .. ")") or nil,
			text = "Crafted: " .. (src.profession or "a profession") .. (src.skill and (" " .. src.skill) or ""),
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
