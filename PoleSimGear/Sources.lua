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
