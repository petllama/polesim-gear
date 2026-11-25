-- Scoring, a port of forever/web/armory.py (score, score_parts, suffix_stats, instance, best_suffix):
-- score = sum of an item's stats x the band's weights, in points of the spec's reference stat.
-- The website and the addon must give the same number for the same item, spec and level
-- (tests/test_parity.lua checks it against armory.py's own output).
local ADDON, ns = ...
local Score = {}
ns.Score = Score

Score.TWO_HAND, Score.ONE_HAND, Score.MAIN_HAND_ONLY, Score.OFF_HAND_ONLY = 17, 13, 21, 22
Score.SHIELD, Score.HELD, Score.RELIC = 14, 23, 28
local ONE_HAND, OFF_HAND_ONLY = 13, 22

-- Item stat keys that feed several weight keys (armory.EXPAND): Forever's hit/crit count for melee
-- and spells, its attack power for melee and ranged.
local EXPAND = { hit = { "hit", "spellHit" }, crit = { "crit", "spellCrit" }, mhit = { "hit" }, mcrit = { "crit" },
	spDmg = { "sp" }, ap = { "ap", "rap" } }
Score.EXPAND = EXPAND

-- armory.expand: the weight keys an item stat counts with. Spell damage alone (spDmg) takes the band's
-- spDmg weight when it has one (paladins: Holy spell damage; their healing power has its own `heal`
-- weight = sp - spHoly, both set by armory.split_spell_power), else the generic spell power weight.
local SPDMG = { "spDmg" }
function Score.Expand(k, w)
	if k == "spDmg" and w.spDmg ~= nil then return SPDMG end
	return EXPAND[k] or { k }
end
local expand = Score.Expand

local function sortedKeys(t)
	local out = {}
	for k in pairs(t) do out[#out + 1] = k end
	table.sort(out)
	return out
end
Score.SortedKeys = sortedKeys

local function round(x, n)
	local m = 10 ^ n
	return math.floor(x * m + 0.5) / m
end
Score.Round = round

function Score.StatScore(stats, w, cls)
	local total = 0
	for _, k in ipairs(sortedKeys(stats)) do
		local v = stats[k]
		if k == "apFeral" then
			if cls == "druid" then total = total + v * (w.ap or 0) end
		else
			for _, wk in ipairs(expand(k, w)) do total = total + v * (w[wk] or 0) end
		end
	end
	return total
end

-- Weapon terms (armory._weapon_terms; PoleSim design 2026-11-22-melee-weapon-weights): per role the DPS
-- weight, the speed weight and its anchor, the band's reference weapon speed (shipped in the weights as
-- _mhSpeed/_ohSpeed/_rSpeed). A weapon's speed term is (its speed - the anchor) x the weight, so a
-- reference-speed weapon scores its DPS alone; an off hand without ohDps scores half the DPS weight.
local TERMS = { mh = { "dps", "speed", "_mhSpeed" }, oh = { "ohDps", "ohSpeed", "_ohSpeed" }, ranged = { "rdps", "rspeed", "_rSpeed" } }
Score.TERMS = TERMS
-- armory.SPEED_RANGE: the speed weights hold within +-0.6 s of the reference weapon (PoleSim's linearity
-- check), so a weapon's speed difference counts at most that far either way.
local SPEED_RANGE = 0.6
Score.SPEED_RANGE = SPEED_RANGE
-- -> { { item key, amount, weight key, weight }, ... } of a weapon in a role
function Score.WeaponTerms(inst, w, role)
	local t = TERMS[role]
	if not t or (role == "oh" and inst.inv ~= ONE_HAND and inst.inv ~= OFF_HAND_ONLY) then return {} end
	if role == "oh" and w.ohDps == nil then return { { "dps", inst.dps, "dps", 0.5 * (w.dps or 0) } } end
	local out = { { t[1], inst.dps, t[1], w[t[1]] or 0 } }
	local sw, anchor, speed = w[t[2]], w[t[3]], inst.speed
	if sw and sw ~= 0 and anchor and speed and speed ~= 0 then
		out[2] = { t[2], math.max(-SPEED_RANGE, math.min(SPEED_RANGE, speed - anchor)), t[2], sw }
	end
	return out
end

-- role: "mh" (main hand or two-hander), "oh" (off-hand weapon: ohDps/ohSpeed, else half its DPS),
-- "ranged" (wands, bows: rdps, rspeed), else "gear".
function Score.Score(inst, w, cls, role)
	if not inst then return 0 end
	local s = Score.StatScore(inst.stats, w, cls) + (inst.armor or 0) * (w.armor or 0)
	if (inst.dps or 0) ~= 0 and inst.weapon then
		for _, x in ipairs(Score.WeaponTerms(inst, w, role)) do s = s + x[2] * x[4] end
	end
	return s
end

-- Score() term by term: { item stat key, amount, weight key, weight, points } (rounded like
-- armory.score_parts: amount 3, weight 4, points 3 decimals). One item stat can count with two weights.
function Score.Parts(inst, w, cls, role)
	local out = {}
	local function add(k, amount, wk, mult)
		local wt = (w[wk] or 0) * (mult or 1)
		if amount ~= 0 and wt ~= 0 then out[#out + 1] = { k, round(amount, 3), wk, round(wt, 4), round(amount * wt, 3) } end
	end
	local stats = inst.stats or {}
	for _, k in ipairs(sortedKeys(stats)) do
		if k == "apFeral" then
			if cls == "druid" then add(k, stats[k], "ap") end
		else
			for _, wk in ipairs(expand(k, w)) do add(k, stats[k], wk) end
		end
	end
	add("armor", inst.armor or 0, "armor")
	if (inst.dps or 0) ~= 0 and inst.weapon then
		for _, x in ipairs(Score.WeaponTerms(inst, w, role)) do
			if x[2] ~= 0 and x[4] ~= 0 then out[#out + 1] = { x[1], round(x[2], 3), x[3], round(x[4], 4), round(x[2] * x[4], 3) } end
		end
	end
	return out
end

-- (suffix name, stats it adds) for an item's random suffix bonus list (its budget, rounded like the
-- client), or (nil, {}) when the item has no such suffix.
function Score.SuffixStats(it, bonus)
	local sfx = ns.DATA.suffixes[bonus]
	if not sfx then return nil, {} end
	local has = false
	for _, b in ipairs(it.sfx) do
		if b == bonus then has = true break end
	end
	if not has then return nil, {} end
	local out, rating = {}, ns.DATA.rating
	for k, alloc in pairs(sfx.a) do
		local v = math.floor(alloc * (it.b or 0) / 10000 + 0.5)
		if rating[k] then v = round(v / rating[k], 2) end
		if v ~= 0 then out[k] = v end
	end
	return sfx.n, out
end

-- A shipped item as worn (with the suffix's stats): the shape Score/Parts/Equip read.
function Score.Instance(it, bonus)
	if not it then return nil end
	local stats = {}
	for k, v in pairs(it.s) do stats[k] = v end
	local sname
	if bonus then
		local extra
		sname, extra = Score.SuffixStats(it, bonus)
		for k, v in pairs(extra) do stats[k] = (stats[k] or 0) + v end
	end
	return {
		id = it.id, bonus = sname and bonus or nil, suffix = sname, name = it.name .. (sname and (" " .. sname) or ""),
		quality = it.q, icon = it.icon, rl = it.rl, inv = it.inv, c = it.c, sc = it.sc, cm = it.cm, rm = it.rm,
		unique = it.u, stats = stats, armor = it.ar, dps = it.dps, weapon = it.dps > 0, speed = it.speed,
	}
end

-- (instance, score) of an item with its best random suffix for these weights, kept per weights table
-- (a band), class, role and item until ClearCache (Context clears it whenever scores change). The
-- instance is shared: read it, do not change it. keep == false (the browser, which scores each item
-- once per build) uses a kept answer but keeps nothing new.
local bestCache = setmetatable({}, { __mode = "k" })
function Score.ClearCache()
	bestCache = setmetatable({}, { __mode = "k" })
end

function Score.BestSuffix(it, w, cls, role, keep)
	if not it then return nil end
	local byW = bestCache[w]
	local key = (cls or "") .. ":" .. (role or "") .. ":" .. it.id
	local hit = byW and byW[key]
	if hit then return hit[1], hit[2] end
	local best, bestScore
	local list = #it.sfx > 0 and it.sfx or { false }
	for _, bl in ipairs(list) do
		local inst = Score.Instance(it, bl or nil)
		local s = Score.Score(inst, w, cls, role)
		if not best or s > bestScore + 1e-9 then best, bestScore = inst, s end
	end
	if keep ~= false then
		if not byW then
			byW = {}
			bestCache[w] = byW
		end
		byW[key] = { best, bestScore }
	end
	return best, bestScore
end
