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

-- model, worn (Context), st = { spec, filters, ahead, show, preferQuest } -> entries (preferQuest: a
-- slot's suggestion is its best upgrade from an upcoming guide quest within 2 levels of model.level):
--  upgrades/all: { def, worn, rows, entry (Plan.Resolve), why (missing pick), priority (1..) }
--  wishlist:     { def|nil, row|nil, missing|nil, why|nil, key }
-- Main and off hand come from View.Weapons (one weapon set); an off hand that "uses the two-hander"
-- (entry.twoHander) is listed only under All gear, with no priority.
function View.PlanEntries(model, worn, st)
	if st.show == "wishlist" then return View.WishEntries(model, st) end
	local withPlan, rest = {}, {}
	local wmh, woh = View.Weapons(model, worn, st, st.ahead)
	for _, def in ipairs(B.SLOTS) do
		local rows, entry
		if def.key == "mainhand" or def.key == "offhand" then
			entry = def.key == "mainhand" and wmh or woh
			rows = entry.rows
		else
			rows = B.SlotRows(model, def.key, st.ahead, st.filters)
			entry = ns.Plan.Resolve(rows, ns.Plan.Get(st.spec, def.key), st.preferQuest and model.level or nil)
		end
		local e = { def = def, worn = B.WornFor(def, worn), rows = rows, entry = entry }
		if entry.missing then e.why = ns.Plan.Why(model, def.key, ns.Plan.Get(st.spec, def.key), st.ahead, st.filters) end
		if entry.plan or entry.missing then withPlan[#withPlan + 1] = e else rest[#rest + 1] = e end
	end
	-- the weapon rows rank by their set's gain (they are one decision; a one-hander replacing a staff
	-- may gain less than the staff alone)
	local function rank(e) return e.entry.plan and (e.entry.plan.setGain or e.entry.plan.gain) or -math.huge end
	table.sort(withPlan, function(a, b)
		local ga, gb = rank(a), rank(b)
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
-- or no upgrade is available NOW under the source filters (look ahead not counted). Main and off hand
-- count once: the weapon set is done when View.Weapons plans neither hand.
function View.Progress(model, worn, st)
	local done, total = 0, 1
	for _, def in ipairs(B.SLOTS) do
		if def.key ~= "mainhand" and def.key ~= "offhand" then
			total = total + 1
			local rows = B.SlotRows(model, def.key, 0, st.filters)
			local pick = ns.Plan.Get(st.spec, def.key)
			local wornPick = false
			if pick then
				local w = B.WornFor(def, worn)
				wornPick = w and w.inst and B.KeyOf(w.inst) == pick or false
			end
			if wornPick or #rows == 0 then done = done + 1 end
		end
	end
	local mh, oh = View.Weapons(model, worn, { spec = st.spec, filters = st.filters }, 0)
	if not (mh.plan or oh.plan) then done = done + 1 end
	return done, total
end

local function copy(r, t)
	local o = { c = r.c, gain = r.gain, base = r.base, at = r.at, note = r.note, slot = r.slot, vs2h = r.vs2h, pairWith = r.pairWith }
	for k, v in pairs(t) do o[k] = v end
	return o
end
local function isTwo(inst) return inst ~= nil and inst.inv == 17 end
local function rowsWith(all, pick)
	local out = {}
	for _, r in ipairs(all) do
		if r.gain > 1e-6 or (pick and B.KeyOf(r.c.inst) == pick) then out[#out + 1] = r end
	end
	return out
end

-- The weapons as ONE decision, the weapon set: a two-hander alone, or a one-hander + an off hand (a
-- one-hander alone when no off hand passes). The set with the biggest gain over what is worn wins,
-- after the player's picks (an off-hand pick fixes the set to one-hander + it; a two-hander pick leaves
-- the off hand to it) and the near-quest rule per item (st.preferQuest). An off hand is planned only
-- with the main hand of the set; when the set is a two-hander the off hand "uses the two-hander".
-- Row gains split so they add up to the set's gain: a one-hander replacing a worn two-hander gains its
-- score minus the staff's, its off hand its own score; setGain/setText carry the whole set.
-- -> main-hand entry, off-hand entry (Plan.Resolve's shape + rows; the off hand's twoHander = true)
function View.Weapons(model, worn, st, ahead)
	local level = st.preferQuest and model.level or nil
	local wm, wo = worn[16], worn[17]
	local W2 = wm and isTwo(wm.inst) or false
	local pickMH, pickOH = ns.Plan.Get(st.spec, "mainhand"), ns.Plan.Get(st.spec, "offhand")
	local mhAll = B.SlotRows(model, "mainhand", ahead, st.filters, { partner = pickOH, all = true })
	local ohAll = B.SlotRows(model, "offhand", ahead, st.filters, { partner = pickMH, all = true })
	-- the off hand: the pick, else the near quest or the best (what a one-hander pairs with)
	local ohRows = rowsWith(ohAll, pickOH)
	local oh = ns.Plan.Resolve(ohRows, pickOH, level)
	oh.rows = ohRows
	local partner = oh.plan
	local ohFixed = oh.isPick and partner ~= nil
	-- what an off hand adds to the set: all of its score in an empty off hand (under a two-hander)
	local function ohOwn(r) return W2 and r.c.score or (r.c.score - (r.base or 0)) end
	local set = {}
	for _, r in ipairs(mhAll) do
		local k = B.KeyOf(r.c.inst)
		local g, own
		if isTwo(r.c.inst) then
			if not ohFixed or k == pickMH then g = r.gain end -- against main + off hand
		else
			own = r.c.score - (r.base or 0)
			g = own + (partner and ohOwn(partner) or 0)
		end
		-- only sets that beat what is worn; the pick; under an off-hand pick every one-hander (it needs one)
		if g and (g > 1e-6 or k == pickMH or (ohFixed and W2 and own)) then set[#set + 1] = copy(r, { gain = g, own = own }) end
	end
	table.sort(set, B.ByGain)
	local mh = ns.Plan.Resolve(set, pickMH, level)
	mh.rows = set
	local mp = mh.plan
	if (mp and isTwo(mp.c.inst)) or (not mp and W2 and not ohFixed) then
		-- the set is a two-hander (planned, or the one worn): nothing to plan for the off hand
		oh = { twoHander = true, rows = ohRows }
	end
	if mp and not isTwo(mp.c.inst) then
		local p = oh.plan
		local d
		if p then
			local names = W2 and (wm.inst.name or "?")
				or (wm and wo and ((wm.inst.name or "?") .. " + " .. (wo.inst.name or "?")))
				or (wm and wm.inst.name) or (wo and wo.inst.name) or "empty hands"
			local text = string.format("Weapon set: %s over %s", ns.Style and ns.Style.Signed(mp.gain) or string.format("%+.1f", mp.gain), names)
			d = copy(mp, { gain = mp.own, setGain = mp.gain, setText = text, note = "with " .. (p.c.inst.name or "?") .. " (also planned)" })
			local od = copy(p, { gain = ohOwn(p), base = W2 and 0 or p.base, setGain = mp.gain, setText = text,
				note = "with " .. (mp.c.inst.name or "?") .. " (also planned)" })
			if oh.best == p then oh.best = od end
			if oh.suggestion == p then oh.suggestion = od end
			oh.plan = od
		else
			d = copy(mp, { gain = mp.own, note = W2 and "leaves the off hand empty" or mp.note })
		end
		if mh.best == mp then mh.best = d end
		if mh.suggestion == mp then mh.suggestion = d end
		mh.plan = d
	end
	return mh, oh
end

-- A band's weights, biggest first (ties by key), zero weights left out; n (optional) = top n.
function View.WeightRows(w, n)
	local out = {}
	for k, v in pairs(w) do
		if type(v) == "number" and v ~= 0 then out[#out + 1] = { key = k, value = v, label = ns.DATA.statLabels[k] or k } end
	end
	table.sort(out, function(a, b)
		if a.value ~= b.value then return a.value > b.value end
		return a.key < b.key
	end)
	if n then for i = #out, n + 1, -1 do out[i] = nil end end
	return out
end

-- The spec's bands: { { lo, upTo, w, band }, ... } in level order.
function View.Bands(cls, spec)
	local sd = ns.DATA.specs[cls] and ns.DATA.specs[cls][spec]
	local out, lo = {}, 1
	for _, b in ipairs(sd and sd.bands or {}) do
		out[#out + 1] = { lo = lo, upTo = b.upTo, w = b.w, band = b }
		lo = b.upTo + 1
	end
	return out
end

-- The index of the band a level falls in (the last band past its end).
function View.BandIndex(bands, level)
	for i, b in ipairs(bands) do
		if level <= b.upTo then return i end
	end
	return #bands
end

-- Inventory slots that get a plan badge: { [invSlot] = "pick" | "suggestion" }. Rings and trinkets
-- badge the slot the plan replaces (the weaker or the empty one, Browser.WornFor's choice).
-- -> slot -> "pick" | "suggestion", and slot -> the entry ({ def, entry, ... }) the dot is for
function View.BadgeSlots(entries, worn)
	local out, of = {}, {}
	for _, e in ipairs(entries) do
		if e.entry and (e.entry.plan or e.entry.missing) then
			local def, slot = e.def, e.def.slot
			if def.key == "finger" or def.key == "trinket" then
				local a, b = worn[def.slot], worn[def.slot + 1]
				if a and (not b or b.score < a.score) then slot = def.slot + 1 end
			end
			out[slot] = e.entry.isPick and "pick" or "suggestion"
			of[slot] = e
		end
	end
	return out, of
end
