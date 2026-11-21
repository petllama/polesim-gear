-- Sources as destinations (the Sources tab): the shown upgrade rows (every kind, now + coming within
-- look ahead) grouped by where the player goes for them. Built when the tab is shown, dropped on close.
local ADDON, ns = ...
local Groups = {}
ns.Groups = Groups

-- Codex reads are Polestar internals: guarded (a failed read gives no name, never an error).
local function zoneName(codex, id)
	if not id or type(codex.Zone) ~= "function" then return nil end
	local ok, z = pcall(codex.Zone, id)
	return ok and type(z) == "table" and z.name or nil
end

local function bucket(list, index, key, name)
	local g = index[key]
	if not g then
		g = { key = key, name = name, rows = {}, seen = {}, count = 0, best = -math.huge }
		index[key] = g
		list[#list + 1] = g
	end
	return g
end

-- A group's row of an item (one per item: an item can come from many bosses, quests or vendors of a
-- place, and be listed in two slots). The best gain is kept; every distinct source is collected and
-- ranked in finish().
local KEY_FIELDS = { "text", "where", "questId", "npcId", "npcName", "container", "chance", "profession", "skill", "cost" }
local function srcKey(s)
	local t = {}
	for i, f in ipairs(KEY_FIELDS) do t[i] = tostring(s[f]) end
	return table.concat(t, "|")
end
local function rowOf(rows, items, r, src)
	local e = items[r.c.id]
	if not e then
		e = { c = r.c, gain = r.gain, at = r.at, note = r.note, slot = r.slot, srcs = {}, sseen = {} }
		items[r.c.id] = e
		rows[#rows + 1] = e
	elseif r.gain > e.gain then
		e.c, e.gain, e.at, e.note, e.slot = r.c, r.gain, r.at, r.note, r.slot
	end
	local k = srcKey(src)
	if not e.sseen[k] then
		e.sseen[k] = true
		e.srcs[#e.srcs + 1] = src
	end
	return e
end

local function add(g, r, src, countKey)
	g.items = g.items or {}
	rowOf(g.rows, g.items, r, src)
	if not g.seen[countKey] then
		g.seen[countKey] = true
		g.count = g.count + 1
	end
	if r.gain > g.best then g.best = r.gain end
end

Groups.OTHERS = 3 -- other sources listed in a row's detail (the likeliest)
Groups.RARE_CHANCE = 1 -- a row whose likeliest source drops under this % is low-likelihood
-- A low-likelihood source: a known chance under RARE_CHANCE %. Bosses too: the Codex's boss loot lists
-- carry world drops at 0.01-0.9% (every Deadmines boss), so its boss flag does not tell boss loot apart.
function Groups.Rare(s) return type(s.chance) == "number" and s.chance < Groups.RARE_CHANCE end

-- A row's sources, likeliest first (unknown chance last, then source order) -> src, others, otherCount, rare
local function finish(e)
	local list = {}
	for i, s in ipairs(e.srcs) do list[i] = { s = s, i = i } end
	table.sort(list, function(a, b)
		local ca, cb = a.s.chance or -1, b.s.chance or -1
		if ca ~= cb then return ca > cb end
		return a.i < b.i
	end)
	e.src = list[1].s
	e.others = {}
	for k = 2, math.min(#list, Groups.OTHERS + 1) do e.others[#e.others + 1] = list[k].s end
	e.otherCount = #list - 1
	e.rare = Groups.Rare(e.src)
	e.srcs, e.sseen = nil, nil
end

local function byGain(a, b)
	if a.gain ~= b.gain then return a.gain > b.gain end
	return a.c.id < b.c.id
end
local function byCount(a, b)
	if a.count ~= b.count then return a.count > b.count end
	if a.best ~= b.best then return a.best > b.best end
	return (a.name or "") < (b.name or "")
end

-- -> { dungeon = groups, quest = zones (each with quests), crafted = groups, vendor = zones, world = rows }
-- Groups: by count desc, then best gain desc, then name; quests in a zone by best gain; rows by gain.
-- One row per item per group (and per quest): { c, gain, at, note, slot, src = the likeliest source,
-- others = the next OTHERS sources, otherCount = how many other sources, rare = Groups.Rare(src) }.
function Groups.Build(model, ahead, codex)
	local out = { dungeon = {}, quest = {}, crafted = {}, vendor = {}, world = {} }
	local idx = { dungeon = {}, quest = {}, crafted = {}, vendor = {} }
	for _, def in ipairs(ns.Browser.SLOTS) do
		for _, r in ipairs(ns.Browser.SlotRows(model, def.key, ahead, nil)) do
			local worldDone = false
			for _, s in ipairs(r.c.sources) do
				if s.kind == "dungeon" and s.instanceKey then
					local g = idx.dungeon[s.instanceKey]
					if not g then
						local inst = type(codex.Instance) == "function" and select(2, pcall(codex.Instance, s.instanceKey)) or nil
						g = bucket(out.dungeon, idx.dungeon, s.instanceKey, type(inst) == "table" and inst.name or s.where or s.instanceKey)
						local lv = type(inst) == "table" and inst.levels
						if lv and lv[2] then g.levels = lv[2] .. "-" .. (lv[3] or lv[2]) end
					end
					add(g, r, s, r.c.id)
				elseif s.kind == "quest" then
					local zkey = s.zoneId or 0
					local z = bucket(out.quest, idx.quest, zkey, s.where or zoneName(codex, s.zoneId) or "Unknown zone")
					z.quests = z.quests or {}
					z.qidx = z.qidx or {}
					local q = z.qidx[s.questId]
					if not q then
						q = { questId = s.questId, title = s.title, level = s.level, elite = s.elite, route = s.route,
							needs = s.needs, rows = {}, best = -math.huge }
						z.qidx[s.questId] = q
						z.quests[#z.quests + 1] = q
					end
					q.items = q.items or {}
					rowOf(q.rows, q.items, r, s)
					if r.gain > q.best then q.best = r.gain end
					add(z, r, s, s.questId)
				elseif s.kind == "crafted" then
					add(bucket(out.crafted, idx.crafted, s.profession or "?", s.profession or "A profession"), r, s, r.c.id)
				elseif s.kind == "vendor" then
					local zkey = s.zoneId or 0
					add(bucket(out.vendor, idx.vendor, zkey, s.where or zoneName(codex, s.zoneId) or "Unknown zone"), r, s, r.c.id)
				elseif s.kind == "world" and not worldDone then
					worldDone = true
					out.world[#out.world + 1] = { c = r.c, gain = r.gain, at = r.at, note = r.note, slot = r.slot, src = s }
				end
			end
		end
	end
	for _, kind in ipairs({ "dungeon", "quest", "crafted", "vendor" }) do
		for _, g in ipairs(out[kind]) do
			for _, e in ipairs(g.rows) do finish(e) end
			table.sort(g.rows, byGain)
			g.seen, g.items = nil, nil
			if g.quests then
				table.sort(g.quests, function(a, b)
					if a.best ~= b.best then return a.best > b.best end
					return a.questId < b.questId
				end)
				for _, q in ipairs(g.quests) do
					for _, e in ipairs(q.rows) do finish(e) end
					table.sort(q.rows, byGain)
					q.items = nil
				end
				g.qidx = nil
			end
		end
		table.sort(out[kind], byCount)
	end
	table.sort(out.world, byGain)
	return out
end
