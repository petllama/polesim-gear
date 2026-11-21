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

function Plan.Clear(spec, key)
	local t = bySpec(spec)
	if t and t[key] ~= nil then
		t[key] = nil
	end
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
