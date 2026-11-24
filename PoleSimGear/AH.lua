-- Auction house upgrades: a few browse queries over what the character can wear (usable only, up to
-- the window's look ahead), paged and throttled the client's way; each result scored like the window's
-- rows (Equip.Compare against what is worn, the weapon set rule) and kept when it is an upgrade, with
-- its cheapest price. Session only: cleared when the auction house closes. Buying stays the player's:
-- nothing here bids, buys or posts (a click only opens the item's listings in the AH frame).
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
		local b = AH.Suffix(rec, f.itemKey)
		if b then
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

-- found (the scan's), ctx (Context.Get), ahead, yield (optional: called every YIELD_EVERY results, for
-- Browser.Start's frame slices) -> rows (upgrades: { key, c = { id, inst, score,
-- sources, kinds }, gain, base, slot, note, at, price, setPrice, value, partner, anySuffix, result,
-- itemKey }), counts { results, notScored, scored }.
-- Weapons follow the weapon set rule: under a worn two-hander a one-hander pairs with the best AH off
-- hand (and the reverse), and the pair must beat the two-hander (its value counts both prices).
AH.YIELD_EVERY = 50
function AH.Build(found, ctx, ahead, yield)
	local counts = { results = 0, notScored = 0, scored = 0 }
	local out = {}
	-- the cheapest price of every scored item, upgrade or not: exact ("id:bonus") and any-suffix (id)
	local prices = { exact = {}, any = {} }
	if not ctx then return out, counts, prices end
	local top = math.min(60, ctx.level + (ahead or 0))
	local bands = {}
	local function bandAt(L)
		if L == ctx.level then return ctx end
		if bands[L] == nil then bands[L] = ns.Context.At(L) or false end
		return bands[L] or nil
	end
	local cands = {}
	for _, f in pairs(found) do
		counts.results = counts.results + 1
		if yield and counts.results % AH.YIELD_EVERY == 0 then yield() end
		local ok, c, why = pcall(candidate, f, ctx, top, bandAt)
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
-- (cheapest first); ties: cheaper, then the item key.
function AH.Sort(list, by)
	local out = {}
	for i, r in ipairs(list) do out[i] = r end
	local function tie(a, b)
		if (a.price or 0) ~= (b.price or 0) then return (a.price or 0) < (b.price or 0) end
		return tostring(a.key) < tostring(b.key)
	end
	local cmp
	if by == "value" then
		cmp = function(a, b) if a.value ~= b.value then return a.value > b.value end return tie(a, b) end
	elseif by == "price" then
		cmp = function(a, b)
			if (a.price or 0) ~= (b.price or 0) then return (a.price or 0) < (b.price or 0) end
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

function AH.Status()
	if not scan then return nil end
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
local function score(s)
	if s.scoring and s.scoring ~= true then s.scoring:Cancel() end
	s.scoreToken = (s.scoreToken or 0) + 1
	local tok, ctx, f = s.scoreToken, ns.Context.Get(), found
	local function current() return scan == s and s.scoreToken == tok end
	s.scoring = true
	local h = ns.Browser.Start(nil, function(res)
		if not current() then return end
		s.scoring = nil
		rows, counts, prices = res[1], res[2], res[3]
		changed()
	end, function(_, y) return { AH.Build(f, ctx, s.ahead, y) } end, function()
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
	local queries = AH.Queries(ctx.cls, ctx.level, ahead)
	if #queries == 0 then return false, "nothing to search for" end
	hook(api)
	found, rows, counts, prices = {}, {}, nil, nil
	scan = { queries = queries, i = 0, pages = 0, failed = 0, searched = 0, level = ctx.level, ahead = ahead }
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

-- Session only: the auction house closing stops a scan and lets go of every result.
function AH.Clear()
	if scan and scan.scoring and scan.scoring ~= true then scan.scoring:Cancel() end
	scan, found, rows, counts, prices = nil, {}, {}, nil, nil
	changed()
end
ns.RegisterEvent("AUCTION_HOUSE_CLOSED", AH.Clear)

-- Scores changed (an item bought and equipped, a level, talents) or items turned out not to exist on
-- the server (Items.MarkMissing: candidate() no longer gets them): the results are scored again.
local function rescore()
	if not (scan and scan.done and next(found)) then return end
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
