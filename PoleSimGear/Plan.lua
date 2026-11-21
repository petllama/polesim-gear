-- The gear plan the player sets: per character and spec, a slot's chosen upgrade ("id:bonus", the
-- item and its random suffix). No pick = the suggestion (the slot's best upgrade). A pick stays until
-- the player clears it ("Back to suggestion") or wears it (ClearWorn).
local ADDON, ns = ...
local Plan = {}
ns.Plan = Plan

local function bySpec(spec, create)
	local char = ns.char
	if not char then return nil end
	if type(char.plan) ~= "table" then char.plan = {} end
	local t = char.plan[spec]
	if type(t) ~= "table" then
		if not create then return nil end
		t = {}
		char.plan[spec] = t
	end
	return t
end

function Plan.Get(spec, key)
	local t = bySpec(spec)
	local v = t and t[key]
	return type(v) == "string" and v or nil
end

-- inst: { id, bonus } (a row's c.inst)
function Plan.Set(spec, key, inst)
	local t = bySpec(spec, true)
	if not t then return end
	t[key] = ns.Browser.KeyOf(inst)
	ns.Fire("PLAN_CHANGED", spec, key)
end

-- Fires PLAN_CHANGED only when there was a pick to clear.
function Plan.Clear(spec, key)
	local t = bySpec(spec)
	if not (t and t[key] ~= nil) then return end
	t[key] = nil
	ns.Fire("PLAN_CHANGED", spec, key)
end

-- "id:bonus" -> id, bonus (nil for 0) | nil
function Plan.Parse(k)
	local id, bonus = tostring(k or ""):match("^(%d+):(%d+)$")
	if not id then return nil end
	bonus = tonumber(bonus)
	return tonumber(id), bonus ~= 0 and bonus or nil
end

-- rows: the slot's upgrade rows as shown (Browser.SlotRows: filters + look ahead), best first;
-- pick: Plan.Get's "id:bonus" | nil. -> { suggestion = row|nil, plan = row|nil, isPick,
-- betterBy = suggestion gain - pick gain (when > 0), missing = { id, bonus } (a pick not in rows) }
function Plan.Resolve(rows, pick)
	local e = { suggestion = rows[1], isPick = pick ~= nil }
	if not pick then
		e.plan = rows[1]
		return e
	end
	for _, r in ipairs(rows) do
		if ns.Browser.KeyOf(r.c.inst) == pick then
			e.plan = r
			if rows[1] and rows[1].gain - r.gain > 1e-6 then e.betterBy = rows[1].gain - r.gain end
			return e
		end
	end
	local id, bonus = Plan.Parse(pick)
	e.missing = { id = id, bonus = bonus }
	return e
end

Plan.KIND_LABEL = { quest = "Quests", dungeon = "Dungeons", crafted = "Crafting", vendor = "Vendors", world = "BoE / World" }

-- Why a pick (not among the slot's shown rows) is unavailable: looked up in the whole model.
function Plan.Why(model, key, pick, ahead, filters)
	local function find(list)
		for _, r in ipairs(list or {}) do
			if ns.Browser.KeyOf(r.c.inst) == pick then return r end
		end
	end
	local r = find(model.now[key]) or find((model.coming or {})[key])
	if not r then return "not available now (quest done, retired, or no longer an upgrade)" end
	if r.at and r.at > model.level + (ahead or 0) then
		return string.format("needs level %d (look ahead +%d)", r.at, r.at - model.level)
	end
	local off = {}
	for _, k in ipairs(ns.Browser.KINDS) do
		if r.c.kinds[k] and not (filters and filters[k]) then off[#off + 1] = Plan.KIND_LABEL[k] end
	end
	return "its sources are off: " .. table.concat(off, ", ")
end

local WORN_SLOTS = {} -- slotKey -> inventory slots it covers
for _, def in ipairs(ns.Browser.SLOTS) do
	WORN_SLOTS[def.key] = (def.key == "finger" or def.key == "trinket") and { def.slot, def.slot + 1 } or { def.slot }
end

-- worn: Context's slot -> { inst }. Clears every spec's pick that is worn in its slot -> how many.
function Plan.ClearWorn(worn)
	local char = ns.char
	if not (char and type(char.plan) == "table") then return 0 end
	local n = 0
	for _, picks in pairs(char.plan) do
		if type(picks) == "table" then
			for key, pick in pairs(picks) do
				for _, slot in ipairs(WORN_SLOTS[key] or {}) do
					local e = worn[slot]
					if e and e.inst and ns.Browser.KeyOf(e.inst) == pick then
						picks[key] = nil -- clearing an existing field during pairs() is allowed
						n = n + 1
						break
					end
				end
			end
		end
	end
	if n > 0 then ns.Fire("PLAN_CHANGED") end
	return n
end

-- Equipping a picked item (any score change: Context fires SCORES_CHANGED after STATE) clears its pick.
ns.On("SCORES_CHANGED", function()
	local ctx = ns.Context and ns.Context.Get()
	if ctx and ctx.worn then Plan.ClearWorn(ctx.worn) end
end)
