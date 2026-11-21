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

local function add(g, r, src, countKey)
	g.rows[#g.rows + 1] = { c = r.c, gain = r.gain, at = r.at, note = r.note, slot = r.slot, src = src }
	if not g.seen[countKey] then
		g.seen[countKey] = true
		g.count = g.count + 1
	end
	if r.gain > g.best then g.best = r.gain end
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
					q.rows[#q.rows + 1] = { c = r.c, gain = r.gain, at = r.at, note = r.note, slot = r.slot, src = s }
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
			table.sort(g.rows, byGain)
			g.seen = nil
			if g.quests then
				table.sort(g.quests, function(a, b)
					if a.best ~= b.best then return a.best > b.best end
					return a.questId < b.questId
				end)
				for _, q in ipairs(g.quests) do table.sort(q.rows, byGain) end
				g.qidx = nil
			end
		end
		table.sort(out[kind], byCount)
	end
	table.sort(out.world, byGain)
	return out
end
