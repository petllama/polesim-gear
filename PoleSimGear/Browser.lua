-- The upgrade browser's model (pure: the window in Window.lua and the Tab*.lua files draws it). Layout "B": best
-- per slot right now, every upgrade of a slot, and "coming up" (the next levels, each scored with the
-- weights of the band it would be worn in).
local ADDON, ns = ...
local Browser = {}
ns.Browser = Browser

Browser.SLOTS = {
	{ key = "head", label = "Head", slot = 1, invs = { 1 } }, { key = "neck", label = "Neck", slot = 2, invs = { 2 } },
	{ key = "shoulder", label = "Shoulder", slot = 3, invs = { 3 } }, { key = "back", label = "Back", slot = 15, invs = { 16 } },
	{ key = "chest", label = "Chest", slot = 5, invs = { 5, 20 } }, { key = "wrist", label = "Wrist", slot = 9, invs = { 9 } },
	{ key = "hands", label = "Hands", slot = 10, invs = { 10 } }, { key = "waist", label = "Waist", slot = 6, invs = { 6 } },
	{ key = "legs", label = "Legs", slot = 7, invs = { 7 } }, { key = "feet", label = "Feet", slot = 8, invs = { 8 } },
	{ key = "finger", label = "Rings", slot = 11, invs = { 11 } }, { key = "trinket", label = "Trinkets", slot = 13, invs = { 12 } },
	{ key = "mainhand", label = "Main hand", slot = 16 }, { key = "offhand", label = "Off hand", slot = 17 },
	{ key = "ranged", label = "Ranged / wand", slot = 18, invs = { 15, 25, 26, 28 } },
}

-- The weapons PoleSim gives the spec at that band (armory: mh_invs / oh_invs by weapon style; casters
-- "any"). Dual wield is left out: no Priest can (later classes add it with their data).
local MH = { ["2h"] = { 17 }, dw = { 13, 21 }, shield = { 13, 21 }, ["1h"] = { 13, 21 }, any = { 13, 17, 21 } }
local OH = { ["2h"] = {}, shield = { 14 }, ["1h"] = { 14, 23 }, any = { 14, 23 } }
function Browser.Invs(def, style)
	if def.key == "mainhand" then return MH[style] or MH.any end
	if def.key == "offhand" then return OH[style] or OH.any end
	return def.invs
end

-- One item -> { id, inst (best suffix), score, sources (ok ones), kinds, rl } | nil (unusable, retired,
-- no source the character can use).
function Browser.Candidate(id, env, lim, w, role)
	local it = env.items.Get(id)
	if not it or it.rl > lim then return nil end
	if not ns.Equip.CanUse(it, env.cls, math.max(env.level, it.rl)) then return nil end
	if not ns.Sources.RaceOk(it.rm, env.player.raceBit) then return nil end
	local srcs = ns.Sources.For(id, env.codex, env.player, lim)
	if not srcs then return nil end
	local ok, kinds = {}, {}
	for _, s in ipairs(srcs) do
		if s.ok then
			if s.questId then s.route = env.routeStep(s.questId) end
			ok[#ok + 1] = s
			kinds[s.kind] = true
		end
	end
	if #ok == 0 then return nil end
	local inst, score = ns.Score.BestSuffix(it, w, env.cls, role, false) -- once per build: not kept
	return { id = id, inst = inst, score = score, sources = ok, kinds = kinds, rl = it.rl }
end

-- One indexed id: its candidate if its required level is in the window. -> in (window), candidate
local function consider(id, env, rlFrom, rlTo, lim, w, role)
	-- the index's required level when it has one (nothing decoded outside the window)
	local rl = env.items.Rl and env.items.Rl(id)
	if rl == nil then
		local it = env.items.Get(id)
		rl = it and it.rl
	end
	if not (rl and rl >= rlFrom and rl <= rlTo) then return false end
	return true, Browser.Candidate(id, env, lim, w, role)
end

-- Candidates per slot for items with rlFrom <= required level <= rlTo, scored with the band of `at`.
-- yield (optional) is called after the index, every YIELD_EVERY items in the window and after each
-- slot's sort, so the window can spread the work over frames (no step over ~8 ms under lua5.1 with the
-- real data); only (optional) = { [slotKey] = true } limits it to those slots. An item that throws is skipped and
-- reported once per session (ns.ReportOnce): one bad record does not end the build.
Browser.YIELD_EVERY = 15
function Browser.Collect(env, at, rlFrom, rlTo, lim, yield, only)
	local band = env.at(at)
	local byInv = env.items.ByInv()
	if yield then yield() end
	local cands, n = {}, 0
	for _, def in ipairs(Browser.SLOTS) do
		cands[def.key] = {}
		if not only or only[def.key] then
			local role = ns.Equip.ROLE_OF_SLOT[def.slot] or "gear"
			local list = {}
			for _, inv in ipairs(Browser.Invs(def, band.style)) do
				local r = inv == 17 and "mh" or role
				for _, id in ipairs(byInv[inv] or {}) do
					local ok, inWindow, c = pcall(consider, id, env, rlFrom, rlTo, lim, band.w, r)
					if not ok then
						ns.ReportOnce("browser:" .. id, inWindow)
						inWindow = true
					end
					if inWindow then
						if c then list[#list + 1] = c end
						n = n + 1
						if yield and n % Browser.YIELD_EVERY == 0 then yield() end
					end
				end
			end
			table.sort(list, function(a, b)
				if a.score ~= b.score then return a.score > b.score end
				return a.id < b.id
			end)
			cands[def.key] = list
			if yield then yield() end
		end
	end
	return cands, band
end

local function byGain(a, b)
	if a.gain ~= b.gain then return a.gain > b.gain end
	return a.c.id < b.c.id
end
Browser.ByGain = byGain

-- worn: the same item with the same suffix (armory._same)
local function same(a, b) return a and b and a.id == b.id and (a.bonus or 0) == (b.bonus or 0) end

-- cands (Collect), band ({ worn }) -> { [slotKey] = { { c, gain, note, slot }, ... } } with gain > 0, best first.
-- pair (optional, Collect's shape): where the one-hander / off hand to pair with under a worn two-hander
-- comes from (default cands); the website picks them from every candidate up to the level.
function Browser.Gains(cands, band, pair)
	pair = pair or cands
	local worn = band.worn
	local function at(slot)
		local e = worn[slot]
		return e and e.score or 0, e and e.inst
	end
	local mhS, mh = at(16)
	local ohS, oh = at(17)
	local mh2h = mh and mh.inv == 17
	local best1h
	for _, c in ipairs(pair.mainhand or {}) do
		if c.inst.inv ~= 17 then best1h = c break end
	end
	local bestOh = (pair.offhand or {})[1]
	local out = {}
	for _, def in ipairs(Browser.SLOTS) do
		local rows = {}
		for _, c in ipairs(cands[def.key] or {}) do
			local gain, note
			if def.key == "finger" or def.key == "trinket" then
				local sa, ia = at(def.slot)
				local sb, ib = at(def.slot + 1)
				if not (same(ia, c.inst) or same(ib, c.inst)) then
					-- unique-equipped and worn with another suffix: it can only replace that one
					if c.inst.unique and ia and ia.id == c.id then
						gain, note = c.score - sa, "unique: replaces the one you wear"
					elseif c.inst.unique and ib and ib.id == c.id then
						gain, note = c.score - sb, "unique: replaces the one you wear"
					else
						gain = c.score - math.min(sa, sb)
					end
				end
			elseif def.key == "mainhand" then
				if not same(mh, c.inst) then
					if c.inst.inv == 17 then
						gain = c.score - mhS - (mh2h and 0 or ohS)
						note = (oh and not mh2h) and "replaces your main and off hand" or nil
					elseif mh2h then
						gain = c.score + (bestOh and bestOh.score or 0) - mhS
						note = bestOh and ("with " .. bestOh.inst.name .. " in the off hand") or "leaves the off hand empty"
					else
						gain = c.score - mhS
					end
				end
			elseif def.key == "offhand" then
				if not same(oh, c.inst) then
					if mh2h then
						gain = c.score + (best1h and best1h.score or 0) - mhS
						note = best1h and ("with " .. best1h.inst.name .. " in the main hand") or "needs a one-hander"
					else
						gain = c.score - ohS
					end
				end
			else
				local s, i = at(def.slot)
				if not same(i, c.inst) then gain = c.score - s end
			end
			if gain and gain > 1e-6 then rows[#rows + 1] = { c = c, gain = gain, note = note, slot = def } end
		end
		table.sort(rows, byGain)
		out[def.key] = rows
	end
	return out
end

Browser.AHEAD = 5 -- "coming up": the next levels (the website's look-ahead default)
Browser.KEEP = 25 -- rows kept per slot and source kind (and for "coming up")

Browser.KINDS = { "quest", "dungeon", "crafted", "vendor", "world" }
local KINDS = Browser.KINDS

-- An item as worn/kept: id and random suffix (armory._same's key).
function Browser.KeyOf(inst) return inst.id .. ":" .. (inst.bonus or 0) end

-- rows (best first) -> the rows among the best `n` of at least one source kind, in the same order:
-- each filter still lists its own best n. keep (optional): { [KeyOf] = true } rows always kept (the
-- player's picks and wishlist).
function Browser.Trim(rows, n, keep)
	local seen, out = {}, {}
	for _, r in ipairs(rows) do
		local keepIt = false
		for _, k in ipairs(KINDS) do
			if r.c.kinds[k] then
				seen[k] = (seen[k] or 0) + 1
				if seen[k] <= n then keepIt = true end
			end
		end
		if keep and keep[Browser.KeyOf(r.c.inst)] then keepIt = true end
		if keepIt then out[#out + 1] = r end
	end
	return out
end

-- rows -> { all = n, quest = n, dungeon = n, crafted = n, vendor = n, world = n }
local function counts(rows)
	local out = { all = #rows }
	for _, k in ipairs(KINDS) do out[k] = 0 end
	for _, r in ipairs(rows) do
		for _, k in ipairs(KINDS) do
			if r.c.kinds[k] then out[k] = out[k] + 1 end
		end
	end
	return out
end

-- -> { now = { [slotKey] = rows (trimmed) }, counts = { [slotKey] = counts before the trim },
-- coming = { [slotKey] = rows with `at` (trimmed) }, level }. env.keep (optional): { [KeyOf] = true }
-- items kept through both trims (picks, wishlist).
function Browser.Build(env, yield)
	local keep = env.keep
	local now = Browser.Gains(Browser.Collect(env, env.level, 0, env.level, env.level, yield))
	local n = {}
	for key, rows in pairs(now) do
		n[key] = counts(rows)
		now[key] = Browser.Trim(rows, Browser.KEEP, keep)
	end
	local coming = {}
	for _, def in ipairs(Browser.SLOTS) do coming[def.key] = {} end
	local lim = env.level + (env.ahead or Browser.AHEAD)
	local last = math.min(60, lim)
	-- Under a worn two-hander a level L one-hander pairs with the best off hand available by L (and the
	-- reverse), from any level up to L (the website's rule). The weapons are collected once per band, up
	-- to its last coming level, and filtered by required level for each L.
	local pools = {}
	local function pairAt(L, band)
		local pool = pools[band.w]
		if not pool then
			local top = L
			for L2 = L + 1, last do
				if env.at(L2).w == band.w then top = L2 end
			end
			pool = Browser.Collect(env, L, 0, top, lim, yield, { mainhand = true, offhand = true })
			pools[band.w] = pool
		end
		local out = {}
		for _, key in ipairs({ "mainhand", "offhand" }) do
			local list = {}
			for _, c in ipairs(pool[key]) do
				if c.rl <= L then list[#list + 1] = c end
			end
			out[key] = list
		end
		return out
	end
	for L = env.level + 1, last do
		local cands, band = Browser.Collect(env, L, L, L, lim, yield)
		local mh, pair = band.worn[16], nil
		if mh and mh.inst and mh.inst.inv == 17 then pair = pairAt(L, band) end
		for key, rows in pairs(Browser.Gains(cands, band, pair)) do
			local list = coming[key]
			for _, r in ipairs(rows) do
				r.at = L
				list[#list + 1] = r
			end
		end
	end
	for key, list in pairs(coming) do
		table.sort(list, byGain)
		coming[key] = Browser.Trim(list, Browser.KEEP, keep)
	end
	return { now = now, counts = n, coming = coming, level = env.level }
end

-- { [slotKey] = rows } -> one list, biggest gain first (the old flat "coming up").
function Browser.Flat(bySlot)
	local out = {}
	for _, def in ipairs(Browser.SLOTS) do
		for _, r in ipairs(bySlot[def.key] or {}) do out[#out + 1] = r end
	end
	table.sort(out, byGain)
	return out
end

-- Whether a row passes a kinds filter ({ [kind] = true }; nil = every kind): any of its kinds on.
function Browser.Pass(r, filters)
	if not filters then return true end
	for k in pairs(r.c.kinds) do
		if filters[k] then return true end
	end
	return false
end

-- A slot's upgrade rows for the window: now, plus coming rows up to level + ahead (each scored with
-- its own band, Build's rule), passing the filter; biggest gain first. A new list (the model's lists
-- are not changed).
function Browser.SlotRows(model, key, ahead, filters)
	local out = {}
	for _, r in ipairs(model.now[key] or {}) do
		if Browser.Pass(r, filters) then out[#out + 1] = r end
	end
	local top = (model.level or 0) + (ahead or 0)
	for _, r in ipairs((model.coming or {})[key] or {}) do
		if r.at <= top and Browser.Pass(r, filters) then out[#out + 1] = r end
	end
	table.sort(out, byGain)
	return out
end

-- The worn entry ({ inst, score } | nil) an upgrade of this slot replaces: rings and trinkets the
-- weaker of the two (an empty one first: it is "replaced" by nothing), else the slot's own.
function Browser.WornFor(def, worn)
	if def.key == "finger" or def.key == "trinket" then
		local a, b = worn[def.slot], worn[def.slot + 1]
		if not a or not b then return nil end
		return (b.score < a.score) and b or a
	end
	return worn[def.slot]
end

-- Gear score: the sum of the worn items' scores (points of the spec's reference stat).
function Browser.GearScore(worn)
	local s = 0
	for _, e in pairs(worn) do s = s + (e.score or 0) end
	return s
end

-- How many upgrades a slot has under a source filter (before the model's trim).
function Browser.Count(model, key, filter)
	local c = model.counts and model.counts[key]
	return c and c[filter] or 0
end

-- Every upgrade of one slot now (the drill-down's "Show all"): that slot scored again, untrimmed (the
-- weapons together: a two-hander is weighed against the pair).
function Browser.SlotAll(env, key, yield)
	local only = { [key] = true }
	if key == "mainhand" or key == "offhand" then only.mainhand, only.offhand = true, true end
	local cands, band = Browser.Collect(env, env.level, 0, env.level, env.level, yield, only)
	return Browser.Gains(cands, band)[key] or {}
end

-- rows passing a source filter ("all", "quest", "dungeon", "crafted")
function Browser.Rows(rows, filter)
	local out = {}
	for _, r in ipairs(rows) do
		if filter == "all" or r.c.kinds[filter] then out[#out + 1] = r end
	end
	return out
end

-- Best per slot right now: the top upgrade of every slot, biggest gain first.
function Browser.Best(now, filter)
	local out = {}
	for _, def in ipairs(Browser.SLOTS) do
		local r = Browser.Rows(now[def.key] or {}, filter)[1]
		if r then out[#out + 1] = r end
	end
	table.sort(out, byGain)
	return out
end

-- Build over several frames (no stutter opening the window); done(model) at the end. Each frame
-- resumes the build until FRAME_MS milliseconds are spent (debugprofilestop), then waits for the next
-- frame (one step per frame without the clock). -> a handle; handle:Cancel() stops the build.
-- work(env, yield) (optional) replaces Build (SlotAll for "Show all"). An error ending the build is
-- reported to the client's handler and passed to onError(err) (optional); done is not called.
Browser.FRAME_MS = 8
function Browser.Start(env, done, work, onError)
	local co = coroutine.create(function() return (work or Browser.Build)(env, coroutine.yield) end)
	local clock = type(debugprofilestop) == "function" and debugprofilestop or nil
	local handle = { Cancel = function(self) self.cancelled = true end }
	local function step()
		if handle.cancelled then return end
		local t0 = clock and clock()
		while true do
			local ok, res = coroutine.resume(co)
			if not ok then
				if onError then onError(res) end -- first: the window's state does not hang on the handler
				return geterrorhandler()(res)
			end
			if coroutine.status(co) == "dead" then return done(res) end
			if not clock or clock() - t0 >= Browser.FRAME_MS then break end
		end
		C_Timer.After(0, step)
	end
	step()
	return handle
end
