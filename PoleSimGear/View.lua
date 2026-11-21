-- What the window's tables show, from the model (pure): Gear Plan entries in three show modes, the
-- header's progress, the Weights tab's rows. Nothing here scores items or keeps state.
local ADDON, ns = ...
local View = {}
ns.View = View

local B = ns.Browser

-- The display data of an item that is not in the model (a missing pick or wish): name, icon, quality.
function View.Inst(id, bonus)
	local it = ns.Items.Peek(id)
	if not it then return { id = id, bonus = bonus, name = "item " .. id } end
	return ns.Score.Instance(it, bonus)
end

-- model, worn (Context), st = { spec, filters, ahead, show } -> entries:
--  upgrades/all: { def, worn, rows, entry (Plan.Resolve), why (missing pick), priority (1..) }
--  wishlist:     { def|nil, row|nil, missing|nil, why|nil, key }
function View.PlanEntries(model, worn, st)
	if st.show == "wishlist" then return View.WishEntries(model, st) end
	local withPlan, rest = {}, {}
	for _, def in ipairs(B.SLOTS) do
		local rows = B.SlotRows(model, def.key, st.ahead, st.filters)
		local pick = ns.Plan.Get(st.spec, def.key)
		local entry = ns.Plan.Resolve(rows, pick)
		local e = { def = def, worn = B.WornFor(def, worn), rows = rows, entry = entry }
		if entry.missing then e.why = ns.Plan.Why(model, def.key, pick, st.ahead, st.filters) end
		if entry.plan or entry.missing then withPlan[#withPlan + 1] = e else rest[#rest + 1] = e end
	end
	table.sort(withPlan, function(a, b)
		local ga = a.entry.plan and a.entry.plan.gain or -math.huge
		local gb = b.entry.plan and b.entry.plan.gain or -math.huge
		if ga ~= gb then return ga > gb end
		return a.def.slot < b.def.slot
	end)
	local n = 0
	for _, e in ipairs(withPlan) do
		if e.entry.plan then
			n = n + 1
			e.priority = n
		end
	end
	if st.show ~= "all" then return withPlan end
	for _, e in ipairs(rest) do withPlan[#withPlan + 1] = e end
	return withPlan
end

-- Starred items: found in any slot's rows (now + coming up to the model's last level, every kind:
-- the wishlist ignores the source filters), else missing.
function View.WishEntries(model, st)
	local out = {}
	for _, k in ipairs(ns.Wishlist.Keys()) do
		local found
		for _, def in ipairs(B.SLOTS) do
			for _, r in ipairs(B.SlotRows(model, def.key, ns.Options and ns.Options.AHEAD_MAX or 5, nil)) do
				if B.KeyOf(r.c.inst) == k then found = { def = def, row = r, key = k } break end
			end
			if found then break end
		end
		if not found then
			local id, bonus = ns.Plan.Parse(k)
			found = { key = k, missing = { id = id, bonus = bonus }, why = "not an upgrade now" }
		end
		out[#out + 1] = found
	end
	return out
end

-- Header progress: slots done / slots. Done = the plan item is worn (its pick was cleared, Plan.ClearWorn)
-- or no upgrade is available NOW under the source filters (look ahead not counted).
function View.Progress(model, worn, st)
	local done = 0
	for _, def in ipairs(B.SLOTS) do
		local rows = B.SlotRows(model, def.key, 0, st.filters)
		local pick = ns.Plan.Get(st.spec, def.key)
		local wornPick = false
		if pick then
			local w = B.WornFor(def, worn)
			wornPick = w and w.inst and B.KeyOf(w.inst) == pick or false
		end
		if wornPick or #rows == 0 then done = done + 1 end
	end
	return done, #B.SLOTS
end
