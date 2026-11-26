-- Auction house upgrades: a few browse queries over what the character can wear (usable only, up to
-- the window's look ahead), paged and throttled the client's way; each result scored like the window's
-- rows (Equip.Compare against what is worn, the weapon set rule) and kept when it is an upgrade, with
-- its cheapest price. The last complete scan's prices are kept per realm and faction (PoleSimGearDB.ah:
-- the auction house is shared by every character there) and listed again, re-scored for the character
-- at the AH, when it opens ("Last scan 3 h ago") until a new scan replaces them; they are only a hint (a
-- click opens the live listings). Price history: per realm-faction and item ("id:suffix"), one price a
-- day (that day's cheapest), from every scored item, upgrade or not; a row whose price is at most 60%
-- of the median of 3+ earlier days is a deal. Scans search 2 levels past the character (or the look
-- ahead, if more) so the history covers gear worn soon; rows stay within the look ahead.
-- Buying stays the player's: nothing here bids, buys or posts (a click only opens the item's listings).
-- Client API (Forever 1.60.1 UI source, Blizzard_APIDocumentationGenerated/AuctionHouseDocumentation.lua):
-- C_AuctionHouse.SendBrowseQuery(AuctionHouseBrowseQuery), GetBrowseResults, HasFullBrowseResults,
-- RequestMoreBrowseResults, IsThrottledMessageSystemReady, GetItemKeyInfo; events
-- AUCTION_HOUSE_BROWSE_RESULTS_UPDATED / _ADDED / _FAILURE, AUCTION_HOUSE_THROTTLED_SYSTEM_READY,
-- AUCTION_HOUSE_CLOSED. (There is no C_AuctionHouse.GetNumBrowseResults: count GetBrowseResults().)
local ADDON, ns = ...
local AH = {}
ns.AH = AH

-- Enum.AuctionHouseFilter / Enum.AuctionHouseSortOrder values (AuctionHouseEnumsDocumentation.lua),
-- read from the client's Enum when it has them.
local function enum(group, name, value)
	local E = _G.Enum and _G.Enum[group]
	return E and E[name] or value
end
local QUALITIES = { { "CommonQuality", 7 }, { "UncommonQuality", 8 }, { "RareQuality", 9 }, { "EpicQuality", 10 } }

-- Item classes (Enum.ItemClass Armor 4, Weapon 2), armor subclass Generic 0 (neck, rings, trinkets,
-- held in off hand, some heads and robes) and the cloak slot (Enum.InventoryType 16, cloth or not), as
-- Blizzard_AuctionData's categories filter them ({ classID, subClassID, inventoryType }, each optional
-- but the class).
local ARMOR, WEAPON = 4, 2
local ARMOR_NAMES = { [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate", [6] = "Shields" }
local WEAPON_NAMES = { [0] = "One-handed axes", [1] = "Two-handed axes", [2] = "Bows", [3] = "Guns", [4] = "Maces",
	[5] = "Two-handed maces", [6] = "Polearms", [7] = "Swords", [8] = "Two-handed swords", [10] = "Staves",
	[13] = "Fist weapons", [15] = "Daggers", [16] = "Thrown", [18] = "Crossbows", [19] = "Wands" }
local CLOAK = 16

local function sortedKeys(t)
	local out = {}
	for k in pairs(t) do out[#out + 1] = k end
	table.sort(out)
	return out
end

-- The scan's browse queries for a class at level + ahead: one per armor type it can wear by then, one
-- for the miscellaneous armor (neck, rings, trinkets, held in off hand) and every cloak, one per weapon
-- subclass. Required level 0 (no lower bound, the AH's own default) to level + ahead.
-- -> { { label, query = AuctionHouseBrowseQuery }, ... }
function AH.Queries(cls, level, ahead)
	local p = ns.DATA.proficiency[cls]
	if not p then return {} end
	local top = math.min(60, level + (ahead or 0))
	local filters = { enum("AuctionHouseFilter", "UsableOnly", 2) }
	for _, q in ipairs(QUALITIES) do filters[#filters + 1] = enum("AuctionHouseFilter", q[1], q[2]) end
	local function query(label, classFilters)
		return { label = label, query = { searchString = "", minLevel = 0, maxLevel = top, filters = filters,
			sorts = { { sortOrder = enum("AuctionHouseSortOrder", "Price", 0), reverseSort = false } },
			itemClassFilters = classFilters } }
	end
	local out = {}
	for _, sc in ipairs(sortedKeys(p.armor)) do
		if sc ~= 0 and top >= p.armor[sc] and ARMOR_NAMES[sc] then
			out[#out + 1] = query(ARMOR_NAMES[sc], { { classID = ARMOR, subClassID = sc } })
		end
	end
	out[#out + 1] = query("Neck rings trinkets off hands", { { classID = ARMOR, subClassID = 0 }, { classID = ARMOR, inventoryType = CLOAK } })
	for _, sc in ipairs(sortedKeys(p.weapons)) do
		if p.weapons[sc] then out[#out + 1] = query(WEAPON_NAMES[sc] or ("Weapons " .. sc), { { classID = WEAPON, subClassID = sc } }) end
	end
	return out
end

-- Scoring --------------------------------------------------------------------------------------------
-- An inventory type -> its Browser.SLOTS entry (the weapons by hand).
local MAIN_INV = { [13] = true, [17] = true, [21] = true }
local OFF_INV = { [14] = true, [22] = true, [23] = true }
local function slotDef(inv)
	for _, def in ipairs(ns.Browser.SLOTS) do
		if (def.key == "mainhand" and MAIN_INV[inv]) or (def.key == "offhand" and OFF_INV[inv]) then return def end
		for _, i in ipairs(def.invs or {}) do
			if i == inv then return def end
		end
	end
end

local function itemKeyName(itemKey)
	local api = _G.C_AuctionHouse
	if not (api and api.GetItemKeyInfo) then return nil end
	local ok, info = pcall(api.GetItemKeyInfo, itemKey)
	return ok and type(info) == "table" and info.itemName or nil
end

-- The suffix (bonus list id) of a browse result's item: the key's itemSuffix when it is one of the
-- item's bonus lists, else the suffix whose name ends the client's name for the key (Forever's item
-- key may carry another suffix id), else nil (the browse row stands for every suffix).
function AH.Suffix(rec, itemKey)
	if #rec.sfx == 0 then return nil end
	local s = itemKey.itemSuffix
	for _, b in ipairs(rec.sfx) do
		if b == s and ns.DATA.suffixes[b] then return b end
	end
	local name = itemKeyName(itemKey)
	if type(name) ~= "string" then return nil end
	for _, b in ipairs(rec.sfx) do
		local sfx = ns.DATA.suffixes[b]
		if sfx and name:sub(-#sfx.n - 1) == " " .. sfx.n then return b end
	end
	return nil
end

local function roleOf(inv)
	if MAIN_INV[inv] then return "mh" end
	if OFF_INV[inv] then return "oh" end
	if inv == 15 or inv == 25 or inv == 26 or inv == 28 then return "ranged" end
	return "gear"
end

-- A weapon of this inventory type in a hand the spec's weapon style uses at that band (Browser.Invs,
-- the Gear Plan's and the website's rule: tanks one-hander + shield, Arms/Ret/Enh two-handers, casters
-- any); non-weapons always fit.
function AH.WeaponFits(inv, style, canDw)
	if not (MAIN_INV[inv] or OFF_INV[inv]) then return true end
	for _, def in ipairs(ns.Browser.SLOTS) do
		if def.key == "mainhand" or def.key == "offhand" then
			for _, i in ipairs(ns.Browser.Invs(def, style or "any", canDw)) do
				if i == inv then return true end
			end
		end
	end
	return false
end

-- One found entry -> a candidate { key, c, cmp, def, at, price, anySuffix, band } | nil, why
local function candidate(f, ctx, top, bandAt)
	local id = f.itemKey.itemID
	local rec = ns.Items.Peek(id)
	if not rec then return nil, "unknown" end
	if not (rec.c == 2 or rec.c == 4) then return nil, "not gear" end
	if rec.rl > top or not ns.Equip.CanUse(rec, ctx.cls, math.max(ctx.level, rec.rl)) then return nil, "unusable" end
	if ns.LevelLessGate(rec, top) then return nil, "item level" end -- no required level: as the sources
	local def = slotDef(rec.inv)
	if not def then return nil, "not gear" end
	local L = math.max(ctx.level, rec.rl)
	local band = bandAt(L)
	if not band then return nil, "no weights" end
	if not AH.WeaponFits(rec.inv, band.band and band.band.style, band.canDw) then return nil, "weapon style" end
	local role = roleOf(rec.inv)
	local inst, anySuffix
	if #rec.sfx > 0 then
		local b = f.bonus or AH.Suffix(rec, f.itemKey)
		if b then
			f.bonus = b -- kept with a saved scan (the item's name may not be loaded on a later visit)
			inst = ns.Score.Instance(rec, b)
		else
			-- every suffix: the best one scores the row, the weakest is said in the tooltip
			local worst, worstScore, bestScore
			for _, bl in ipairs(rec.sfx) do
				local i = ns.Score.Instance(rec, bl)
				local s = ns.Score.Score(i, band.w, ctx.cls, role)
				if not inst or s > bestScore + 1e-9 then inst, bestScore = i, s end
				if not worst or s < worstScore - 1e-9 then worst, worstScore = i, s end
			end
			anySuffix = { best = inst.suffix, worstName = worst.suffix, worstScore = worstScore }
		end
	else
		inst = ns.Score.Instance(rec)
	end
	local cmp = ns.Equip.Compare(inst, band.w, ctx.cls, band.worn, band.canDw, ctx.rules)
	if not cmp or cmp.equipped then return nil, "worn" end
	return { key = ns.Browser.KeyOf(inst), c = { id = id, inst = inst, score = cmp.score, sources = {}, kinds = {} },
		cmp = cmp, def = def, at = L > ctx.level and L or nil, price = f.minPrice or 0, quantity = f.totalQuantity,
		result = f.result, itemKey = f.itemKey, anySuffix = anySuffix, band = band }
end

local function perGold(gain, price) return gain / (math.max(price or 0, 1) / 10000) end

-- Price history -----------------------------------------------------------------------------------
AH.HISTORY_DAYS = 14 -- days kept per item
AH.HISTORY_FORGET = 30 -- an item not seen for this many days is dropped
AH.HISTORY_MAX = 3000 -- items kept per realm-faction (the longest unseen go first)
AH.DEAL_SHARE = 0.6 -- a deal: price <= 60% of the usual (median of earlier days)
AH.DEAL_MIN_DAYS = 3 -- earlier days needed before anything is called a deal
AH.PRICE_AHEAD = 2 -- scans search this many levels ahead at least (history only past the look ahead)

function AH.Now() return type(time) == "function" and time() or 0 end
-- a calendar day number (local days when the client's date/time are there)
function AH.Day(t)
	t = t or AH.Now()
	if type(date) == "function" and type(time) == "function" then
		local ok, d = pcall(date, "*t", t)
		if ok and type(d) == "table" then
			local ok2, noon = pcall(time, { year = d.year, month = d.month, day = d.day, hour = 12 })
			if ok2 and noon then return math.floor(noon / 86400) end
		end
	end
	return math.floor(t / 86400)
end
-- the history key of a browse result: item id and the item key's suffix (any item level)
function AH.HistKey(itemKey) return (itemKey.itemID or 0) .. ":" .. (itemKey.itemSuffix or 0) end

-- hist ({ [key] = { s = last day seen, d = { day, price, day, price, ... } } }), prices ({ [key] = copper }),
-- day: each price becomes that day's entry (the lowest of the day), at most HISTORY_DAYS days an item;
-- then items unseen for HISTORY_FORGET days go, and the longest unseen past HISTORY_MAX.
function AH.Record(hist, prices, day)
	for k, p in pairs(prices) do
		if type(p) == "number" and p > 0 then
			local e = hist[k]
			if type(e) ~= "table" or type(e.d) ~= "table" then e = { d = {} } hist[k] = e end
			local d = e.d
			local n = #d
			if n >= 2 and d[n - 1] == day then
				if p < d[n] then d[n] = p end
			elseif n < 2 or d[n - 1] < day then
				d[n + 1], d[n + 2] = day, p
			end -- (an earlier day than the last: the clock went back; ignored)
			while #d > 2 * AH.HISTORY_DAYS do
				table.remove(d, 1)
				table.remove(d, 1)
			end
			if not e.s or day > e.s then e.s = day end
		end
	end
	AH.Prune(hist, day)
end
function AH.Prune(hist, day)
	local keys = {}
	for k, e in pairs(hist) do
		if type(e) ~= "table" or not e.s or day - e.s > AH.HISTORY_FORGET then hist[k] = nil
		else keys[#keys + 1] = k end
	end
	if #keys <= AH.HISTORY_MAX then return end
	table.sort(keys, function(a, b)
		if hist[a].s ~= hist[b].s then return hist[a].s < hist[b].s end
		return a < b
	end)
	for i = 1, #keys - AH.HISTORY_MAX do hist[keys[i]] = nil end
end

function AH.Median(list)
	local t = {}
	for i, v in ipairs(list) do t[i] = v end
	table.sort(t)
	local n = #t
	if n == 0 then return nil end
	if n % 2 == 1 then return t[(n + 1) / 2] end
	return (t[n / 2] + t[n / 2 + 1]) / 2
end

-- What the history says about a price on a day: nil (fewer than DEAL_MIN_DAYS earlier days: no guess),
-- else { deal (price <= DEAL_SHARE x median), pct (below the median, 0..1; negative = above), median,
-- days (earlier days), lowest (below every earlier day) }. The day itself never counts.
function AH.Deal(hist, key, price, day)
	local e = hist and key and hist[key]
	if not (type(e) == "table" and type(e.d) == "table" and price and price > 0) then return nil end
	local prev, low = {}, nil
	for i = 1, #e.d - 1, 2 do
		if e.d[i] < day then
			local p = e.d[i + 1]
			prev[#prev + 1] = p
			if not low or p < low then low = p end
		end
	end
	if #prev < AH.DEAL_MIN_DAYS then return nil end
	local med = AH.Median(prev)
	if not med or med <= 0 then return nil end
	return { deal = price <= AH.DEAL_SHARE * med, pct = 1 - price / med, median = med, days = #prev,
		lowest = price < low }
end

-- found (the scan's), ctx (Context.Get), ahead, yield (optional: called every YIELD_EVERY results, for
-- Browser.Start's frame slices) -> rows (upgrades: { key, c = { id, inst, score,
-- sources, kinds }, gain, base, slot, note, at, price, setPrice, value, partner, anySuffix, result,
-- itemKey }), counts { results, notScored, scored }.
-- Weapons follow the weapon set rule: under a worn two-hander a one-hander pairs with the best AH off
-- hand (and the reverse), and the pair must beat the two-hander (its value counts both prices).
-- opts (optional): histAhead (levels searched for the price history only; default ahead), hist (the
-- realm's price history: rows get `history`, and `deal` when it is one), day (today, or the saved
-- scan's day). prices.hist = { [AH.HistKey] = cheapest } of every item scored up to histAhead.
AH.YIELD_EVERY = 50
function AH.Build(found, ctx, ahead, yield, opts)
	opts = opts or {}
	local counts = { results = 0, notScored = 0, scored = 0 }
	local out = {}
	-- the cheapest price of every scored item, upgrade or not: exact ("id:bonus") and any-suffix (id);
	-- hist: by history key, up to the history's levels
	local prices = { exact = {}, any = {}, hist = {} }
	if not ctx then return out, counts, prices end
	local top = math.min(60, ctx.level + (ahead or 0))
	local histTop = math.max(top, math.min(60, ctx.level + (opts.histAhead or ahead or 0)))
	local bands = {}
	local function bandAt(L)
		if L == ctx.level then return ctx end
		if bands[L] == nil then bands[L] = ns.Context.At(L) or false end
		return bands[L] or nil
	end
	local cands = {}
	local seen = 0
	for _, f in pairs(found) do
		seen = seen + 1
		if yield and seen % AH.YIELD_EVERY == 0 then yield() end
		-- the price history: every usable gear item up to histTop, upgrade or not; past the look ahead
		-- the item is history only (no row, not counted)
		local rec = f.itemKey and ns.Items.Peek(f.itemKey.itemID)
		local histOnly = false
		if rec and (rec.c == 2 or rec.c == 4) and rec.rl <= histTop and not ns.LevelLessGate(rec, histTop)
			and ns.Equip.CanUse(rec, ctx.cls, math.max(ctx.level, rec.rl)) then
			local hk, p = AH.HistKey(f.itemKey), f.minPrice
			if p and p > 0 and (not prices.hist[hk] or p < prices.hist[hk]) then prices.hist[hk] = p end
			histOnly = rec.rl > top or ns.LevelLessGate(rec, top)
		end
		local ok, c, why = true, nil, "history"
		if not histOnly then
			counts.results = counts.results + 1
			ok, c, why = pcall(candidate, f, ctx, top, bandAt)
		end
		if not ok then
			ns.ReportOnce("ah:" .. tostring(f.itemKey and f.itemKey.itemID), c)
		elseif c then
			counts.scored = counts.scored + 1
			cands[#cands + 1] = c
			local t, k = prices.exact, c.key
			if c.anySuffix then t, k = prices.any, c.c.id end
			if not t[k] or c.price < t[k] then t[k] = c.price end
		elseif why == "unknown" then
			counts.notScored = counts.notScored + 1
		end
	end
	-- the best one-hander and off hand by their own score (the partners under a worn two-hander)
	local best = {}
	for _, c in ipairs(cands) do
		local hand = (c.c.inst.inv == 13 or c.c.inst.inv == 21) and "mh" or (OFF_INV[c.c.inst.inv] and "oh") or nil
		if hand and (not best[hand] or c.c.score > best[hand].c.score) then best[hand] = c end
	end
	local rowOf = {}
	for _, c in ipairs(cands) do
		local worn16 = c.band.worn[16]
		local under2h = worn16 and worn16.inst and worn16.inst.inv == 17
		local inv = c.c.inst.inv
		local gain, base, note, partner = c.cmp.gain, c.cmp.base, c.cmp.note, nil
		-- under a two-hander an off hand only counts as the best one-hander's partner: every other one
		-- would ride on that one-hander's score (and flood the list with frills)
		local skip = under2h and OFF_INV[inv] and c ~= best.oh
		if skip then
			gain = 0
		elseif under2h and (inv == 13 or inv == 21 or OFF_INV[inv]) then
			partner = (inv == 13 or inv == 21) and best.oh or best.mh
			base = worn16.score
			gain = c.c.score + (partner and partner.c.score or 0) - base
			note = partner and ("with " .. (partner.c.inst.name or "?") .. " (AH) over your two-hander")
				or (OFF_INV[inv] and "needs a one-hander" or "leaves the off hand empty")
		end
		if gain > 1e-6 then
			local r = { key = c.key, c = c.c, gain = gain, base = base, slot = c.def, note = note, at = c.at,
				price = c.price, quantity = c.quantity, result = c.result, itemKey = c.itemKey, anySuffix = c.anySuffix,
				suffixKnown = c.c.inst.suffix ~= nil and not c.anySuffix }
			if c.anySuffix then c.anySuffix.worst = gain - (c.c.score - c.anySuffix.worstScore) end
			r.setPrice = partner and (c.price + partner.price) or nil
			r.value = perGold(gain, r.setPrice or c.price)
			r.partnerCand = partner
			r.hkey = AH.HistKey(c.itemKey)
			if opts.hist and opts.day then
				r.history = AH.Deal(opts.hist, r.hkey, c.price, opts.day)
				r.deal = r.history and r.history.deal and r.history or nil
			end
			rowOf[c] = r
			out[#out + 1] = r
		end
	end
	for _, r in ipairs(out) do
		r.partner = r.partnerCand and rowOf[r.partnerCand] or nil
		r.partnerCand = nil
	end
	return AH.Sort(out, "gain"), counts, prices
end

-- rows -> a new list in the order: "gain" (default: biggest first), "value" (gain per gold), "price"
-- (cheapest first), "deal" (deals first, the biggest discount first, then by gain); ties: cheaper, then
-- the item key. A weapon-set row's price is the pair's (setPrice),
-- the one its Price cell and gain per gold show.
function AH.RowPrice(r) return r.setPrice or r.price or 0 end
function AH.Sort(list, by)
	local out = {}
	for i, r in ipairs(list) do out[i] = r end
	local price = AH.RowPrice
	local function tie(a, b)
		if price(a) ~= price(b) then return price(a) < price(b) end
		return tostring(a.key) < tostring(b.key)
	end
	local cmp
	if by == "value" then
		cmp = function(a, b) if a.value ~= b.value then return a.value > b.value end return tie(a, b) end
	elseif by == "deal" then
		cmp = function(a, b)
			local da, db = a.deal and a.deal.pct or nil, b.deal and b.deal.pct or nil
			if (da ~= nil) ~= (db ~= nil) then return da ~= nil end
			if da and da ~= db then return da > db end
			if a.gain ~= b.gain then return a.gain > b.gain end
			return tie(a, b)
		end
	elseif by == "price" then
		cmp = function(a, b)
			if price(a) ~= price(b) then return price(a) < price(b) end
			if a.gain ~= b.gain then return a.gain > b.gain end
			return tostring(a.key) < tostring(b.key)
		end
	else
		cmp = function(a, b) if a.gain ~= b.gain then return a.gain > b.gain end return tie(a, b) end
	end
	table.sort(out, cmp)
	return out
end

-- The scan ---------------------------------------------------------------------------------------------
-- One query at a time: send it when the throttled message system is ready (else wait for
-- AUCTION_HOUSE_THROTTLED_SYSTEM_READY), read the results on each BROWSE_RESULTS_UPDATED/ADDED, ask for
-- more (RequestMoreBrowseResults, throttled too) until HasFullBrowseResults, then the next query. A
-- query with no answer for AH.STALL seconds (one timer per send; a stale one does nothing) or a
-- BROWSE_FAILURE counts as failed and the scan goes on. MAX_PAGES bounds the pages of one query.
AH.STALL = 20
AH.MAX_PAGES = 40

-- scan = { queries, i, pages, waiting ("ready" | "results"), token, failed, done, stopped (why) }
-- found: "itemID:suffix:itemLevel" -> { itemKey, minPrice, totalQuantity, result }; rows: the upgrades
local scan, found, rows, counts, prices = nil, {}, {}, nil, nil
local sending = false -- our own SendBrowseQuery (the hook below tells it from another search)
local hookedApi = nil

local function changed() ns.Fire("AH_CHANGED") end

function AH.Found() return found end

-- The cheapest price of an item (an instance: id, bonus) in the last scan: price, anySuffix (the browse
-- row stands for every suffix of it) | nil (not scanned, not for sale, the AH closed).
function AH.PriceOf(inst)
	if not (prices and inst and inst.id) then return nil end
	local p = prices.exact[inst.id .. ":" .. (inst.bonus or 0)]
	if p then return p, false end
	p = prices.any[inst.id]
	if p then return p, true end
	return nil
end

-- The scan's biggest upgrade for a slot (Browser.SLOTS key) | nil
function AH.BestFor(slotKey)
	local best
	for _, r in ipairs(rows) do
		if r.slot and r.slot.key == slotKey and (not best or r.gain > best.gain) then best = r end
	end
	return best
end
function AH.Rows() return rows end
function AH.Scanning() return scan ~= nil and (not scan.done or scan.scoring ~= nil) end

-- "12 min" / "3 h" / "2 days" since a time
function AH.Age(at)
	local s = math.max(0, AH.Now() - (at or 0))
	if s < 3600 then return string.format("%d min", math.max(1, math.floor(s / 60))) end
	if s < 48 * 3600 then return string.format("%d h", math.floor(s / 3600)) end
	return string.format("%d days", math.floor(s / 86400))
end
-- The saved scan on show: its time | nil (a live scan, or none)
function AH.Restored() return scan and scan.restored and scan.at or nil end

function AH.Status()
	if not scan then return nil end
	if scan.restored then
		if scan.scoring then return "Last scan " .. AH.Age(scan.at) .. " ago: scoring..." end
		return string.format("Last scan %s ago: %d upgrade%s (old prices)", AH.Age(scan.at), #rows,
			#rows == 1 and "" or "s")
	end
	local n = #scan.queries
	if scan.stopped then return scan.stopped end
	if scan.cancelled then return string.format("Cancelled (%d/%d searched)", scan.searched, n) end
	if not scan.done then return string.format("Scanning %d/%d...", math.min(scan.i, n), n) end
	if scan.scoring then
		local k = 0
		for _ in pairs(found) do k = k + 1 end
		return string.format("Scoring %d results...", k)
	end
	local c = counts or {}
	local s = string.format("Done: %d upgrade%s in %d results", #rows, #rows == 1 and "" or "s", c.results or 0)
	if (c.notScored or 0) > 0 then s = s .. string.format(", %d not scored", c.notScored) end
	if scan.failed > 0 then s = s .. string.format(", %d failed", scan.failed) end
	return s
end

local function keyOf(k) return (k.itemID or 0) .. ":" .. (k.itemSuffix or 0) .. ":" .. (k.itemLevel or 0) end

-- the current results of the query in flight, merged into found (the cheapest price per item key)
local function collect()
	local list = C_AuctionHouse.GetBrowseResults() or {}
	for _, r in ipairs(list) do
		local k = r.itemKey and keyOf(r.itemKey)
		if k then
			local f = found[k]
			if not f then
				found[k] = { itemKey = r.itemKey, minPrice = r.minPrice, totalQuantity = r.totalQuantity, result = r }
			elseif (r.minPrice or math.huge) < (f.minPrice or math.huge) then
				f.minPrice, f.totalQuantity, f.result = r.minPrice, r.totalQuantity, r
			end
		end
	end
end

-- Score what the scan found, over frames (Browser.Start: FRAME_MS per frame): a few thousand results
-- cost ~60-170 ms under lua5.1, too long for one frame. A later scoring (scores changed) replaces it.
-- Saved data --------------------------------------------------------------------------------------------
-- PoleSimGearDB.ah = { realms = { ["<realm>-<faction>"] = { scan = { at, day, cls, level, f = { [found key] =
-- { itemID, itemSuffix, itemLevel, minPrice, totalQuantity, bonus (0 = not known) } } }, hist = { ... } } } }
function AH.RealmKey()
	local realm = type(GetRealmName) == "function" and GetRealmName() or nil
	local faction = type(UnitFactionGroup) == "function" and UnitFactionGroup("player") or nil
	return (realm or "?") .. "-" .. (faction or "?")
end
-- this realm-faction's saved table | nil (before the saved variables load)
function AH.Store()
	local db = ns.db
	if type(db) ~= "table" then return nil end
	if type(db.ah) ~= "table" then db.ah = {} end
	if type(db.ah.realms) ~= "table" then db.ah.realms = {} end
	local k = AH.RealmKey()
	local r = db.ah.realms[k]
	if type(r) ~= "table" then r = {} db.ah.realms[k] = r end
	if type(r.hist) ~= "table" then r.hist = {} end
	return r
end

local function saveScan(s, ctx)
	local st = AH.Store()
	if not st then return end
	local f = {}
	for k, e in pairs(found) do
		local key = e.itemKey
		if key and key.itemID then
			f[k] = { key.itemID, key.itemSuffix or 0, key.itemLevel or 0, e.minPrice or 0, e.totalQuantity or 1, e.bonus or 0 }
		end
	end
	st.scan = { at = s.at, day = s.day, cls = ctx and ctx.cls, level = ctx and ctx.level, f = f }
end

-- the saved scan -> found (browse results rebuilt from it: the row's click needs the item key) | nil
local function loadScan(saved)
	if not (type(saved) == "table" and type(saved.f) == "table") then return nil end
	local out, n = {}, 0
	for k, e in pairs(saved.f) do
		if type(e) == "table" and type(e[1]) == "number" then
			local key = { itemID = e[1], itemSuffix = e[2] or 0, itemLevel = e[3] or 0, battlePetSpeciesID = 0 }
			local res = { itemKey = key, minPrice = e[4], totalQuantity = e[5] or 1 }
			out[k] = { itemKey = key, minPrice = e[4], totalQuantity = e[5] or 1, result = res,
				bonus = (e[6] or 0) > 0 and e[6] or nil }
			n = n + 1
		end
	end
	return n > 0 and out or nil
end

local function score(s)
	if s.scoring and s.scoring ~= true then s.scoring:Cancel() end
	s.scoreToken = (s.scoreToken or 0) + 1
	local tok, ctx, f = s.scoreToken, ns.Context.Get(), found
	local function current() return scan == s and s.scoreToken == tok end
	local st = AH.Store()
	local opts = { histAhead = s.histAhead, hist = st and st.hist, day = s.day }
	s.scoring = true
	local h = ns.Browser.Start(nil, function(res)
		if not current() then return end
		s.scoring = nil
		rows, counts, prices = res[1], res[2], res[3]
		-- a live scan's prices go into the history once (after the rows' deals: today never counts);
		-- a complete one becomes the saved scan
		if not s.restored and not s.recorded and st then
			s.recorded = true
			AH.Record(st.hist, prices.hist, s.day)
			if not (s.cancelled or s.stopped) and next(found) then saveScan(s, ctx) end
		end
		changed()
	end, function(_, y) return { AH.Build(f, ctx, s.ahead, y, opts) } end, function()
		if current() then s.scoring = nil changed() end
	end)
	if current() and s.scoring == true then s.scoring = h end
end

local advance
local function finish()
	scan.done = true
	scan.waiting = nil
	score(scan)
	changed()
end

-- send what the scan waits to send, when the system is ready
local function trySend()
	if not scan or scan.done then return end
	local api = C_AuctionHouse
	if not api.IsThrottledMessageSystemReady() then
		scan.waiting = scan.wantMore and "more" or "send"
		return
	end
	scan.token = (scan.token or 0) + 1
	local token = scan.token
	if scan.wantMore then
		scan.wantMore = false
		scan.pages = scan.pages + 1
		scan.waiting = "results"
		api.RequestMoreBrowseResults()
	else
		scan.pages = 1
		scan.waiting = "results"
		sending = true
		local ok, err = pcall(api.SendBrowseQuery, scan.queries[scan.i].query)
		sending = false
		if not ok then geterrorhandler()(err) end
	end
	C_Timer.After(AH.STALL, function()
		if scan and not scan.done and scan.token == token and scan.waiting == "results" then
			scan.failed = scan.failed + 1
			advance()
		end
	end)
end

-- the next query (or the end)
advance = function()
	scan.i = scan.i + 1
	scan.wantMore = false
	if scan.i > #scan.queries then return finish() end
	changed()
	trySend()
end

-- Stop: while searching, what was found so far is scored; while scoring, nothing more is.
local function stop(why)
	if not AH.Scanning() then return end
	local wasScoring = scan.done
	if scan.scoring and scan.scoring ~= true then scan.scoring:Cancel() end
	scan.scoring = nil
	scan.done = true
	scan.waiting = nil
	if why then scan.stopped = why else scan.cancelled = true end
	if not wasScoring then score(scan) end
	changed()
end

-- Another browse search while scanning (the player's, another addon's) replaces the client's browse
-- results: the scan stops.
local function hook(api)
	if hookedApi == api or type(hooksecurefunc) ~= "function" then return end
	hookedApi = api
	hooksecurefunc(api, "SendBrowseQuery", function()
		if not sending and AH.Scanning() then stop("Stopped: another search started") end
	end)
end

-- -> true | false, why
function AH.Scan()
	local api = _G.C_AuctionHouse
	if not (api and api.SendBrowseQuery and api.GetBrowseResults) then return false, "no auction house API" end
	if AH.Scanning() then return false, "already scanning" end
	local ctx = ns.Context.Get()
	if not ctx then return false, "no weights for this character" end
	local ahead = ns.Options and ns.Options.View().ahead or 0
	-- the searches reach PRICE_AHEAD levels at least (the price history); rows stay within `ahead`
	local histAhead = math.max(ahead, AH.PRICE_AHEAD)
	local queries = AH.Queries(ctx.cls, ctx.level, histAhead)
	if #queries == 0 then return false, "nothing to search for" end
	hook(api)
	if scan and scan.scoring and scan.scoring ~= true then scan.scoring:Cancel() end
	found, rows, counts, prices = {}, {}, nil, nil
	local now = AH.Now()
	scan = { queries = queries, i = 0, pages = 0, failed = 0, searched = 0, level = ctx.level, ahead = ahead,
		histAhead = histAhead, at = now, day = AH.Day(now) }
	advance()
	return true
end

function AH.Cancel() stop(nil) end

-- Results of the query in flight: kept, then more pages or the next query.
local function onResults()
	if not (scan and not scan.done and scan.waiting == "results") then return end
	collect()
	if C_AuctionHouse.HasFullBrowseResults() or scan.pages >= AH.MAX_PAGES then
		scan.searched = scan.searched + 1
		return advance()
	end
	scan.wantMore = true
	trySend()
end
ns.RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", onResults)
ns.RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", onResults)
ns.RegisterEvent("AUCTION_HOUSE_BROWSE_FAILURE", function()
	if not (scan and not scan.done and scan.waiting == "results") then return end
	scan.failed = scan.failed + 1
	advance()
end)
ns.RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", function()
	if scan and not scan.done and (scan.waiting == "send" or scan.waiting == "more") then trySend() end
end)

-- The auction house closing stops a scan and lets go of every result (a complete scan is saved).
local ahOpen, restorePending = false, false
function AH.Clear()
	if scan and scan.scoring and scan.scoring ~= true then scan.scoring:Cancel() end
	scan, found, rows, counts, prices = nil, {}, {}, nil, nil
	ahOpen, restorePending = false, false
	changed()
end
ns.RegisterEvent("AUCTION_HOUSE_CLOSED", AH.Clear)

-- The auction house opening: the saved scan of this realm-faction, re-scored for this character (its
-- level, spec and worn gear now). No weights yet (the character's data still loading): again when
-- scores change. -> true (restoring) | false
function AH.Restore()
	restorePending = false
	if scan then return false end
	local st = AH.Store()
	local f = st and loadScan(st.scan)
	if not f then return false end
	if not ns.Context.Get() then restorePending = true return false end
	local ahead = ns.Options and ns.Options.View().ahead or 0
	found, rows, counts, prices = f, {}, nil, nil
	scan = { restored = true, done = true, queries = {}, i = 0, pages = 0, failed = 0, searched = 0, ahead = ahead,
		histAhead = ahead, at = st.scan.at or 0, day = st.scan.day or AH.Day(st.scan.at) }
	score(scan)
	changed()
	return true
end
ns.RegisterEvent("AUCTION_HOUSE_SHOW", function()
	ahOpen = true
	AH.Restore()
end)

-- Scores changed (an item bought and equipped, a level, talents) or items turned out not to exist on
-- the server (Items.MarkMissing: candidate() no longer gets them): the results are scored again.
local function rescore()
	if restorePending and ahOpen and not scan then AH.Restore() return end
	if not (scan and scan.done and next(found)) then return end
	if scan.restored then scan.ahead = ns.Options and ns.Options.View().ahead or 0 scan.histAhead = scan.ahead end
	score(scan)
	changed()
end
ns.On("SCORES_CHANGED", rescore)
ns.On("ITEMS_MISSING", rescore)

-- Show a row's item in the auction house: AuctionHouseFrame:SelectBrowseResult (Shared
-- Blizzard_AuctionHouseFrame.lua: the item buy view, whose list asks for the item's listings on show,
-- sorted by buyout, cheapest first). Already in the item buy view, the list is not shown again, so its
-- listings are asked for with RefreshSearchResults(BuyItems, itemKey), as its refresh button does.
-- Buying stays the player's: no bid, buyout or purchase call here. -> true | false, why
function AH.Select(r)
	local f = _G.AuctionHouseFrame
	if not (r and r.result and r.itemKey) then return false, "no auction for this row" end
	if not (f and f.SelectBrowseResult and f:IsShown()) then return false, "the auction house is not open" end
	local api = _G.C_AuctionHouse
	-- SelectBrowseResult reads GetItemKeyInfo(itemKey).isCommodity: nil until the client has the item
	if not (api and api.GetItemKeyInfo and api.GetItemKeyInfo(r.itemKey)) then
		return false, "the item's data is not loaded yet: click again in a moment"
	end
	local modes = _G.AuctionHouseFrameDisplayMode
	local inItemBuy = modes and f.GetDisplayMode and f:GetDisplayMode() == modes.ItemBuy
	f:SelectBrowseResult(r.result)
	local ctxs = _G.AuctionHouseSearchContext
	if inItemBuy and f.RefreshSearchResults and ctxs and ctxs.BuyItems then
		f:RefreshSearchResults(ctxs.BuyItems, r.itemKey)
	end
	return true
end

-- A browse search by an item's name, as the AH's own search bar sends it (AuctionHouseFrame:SendBrowseQuery:
-- browse view, its results list). -> true | false, why
function AH.SearchName(name)
	local f = _G.AuctionHouseFrame
	if not name or name == "" then return false, "no item name to search for" end
	if not (f and f.SendBrowseQuery and f:IsShown()) then return false, "the auction house is not open" end
	f:SendBrowseQuery(name, 0, 0, {})
	return true
end

-- A weapon-set row's partner (the other hand): its listings (AH.Select); when its listing is gone (no
-- browse result or item key left), a search by its name. -> true, note (chat) | false, why | false (no partner)
function AH.SelectPartner(r)
	local p = r and r.partner
	if not p then return false end
	if p.result and p.itemKey then return AH.Select(p) end
	local inst = p.c and p.c.inst or {}
	local name = inst.name
	if name and inst.suffix and name:sub(-#inst.suffix - 1) == " " .. inst.suffix then
		name = name:sub(1, #name - #inst.suffix - 1)
	end
	local ok, why = AH.SearchName(name)
	if not ok then return false, why end
	return true, (name or "?") .. "'s listing is gone: searching the auction house for it by name"
end
