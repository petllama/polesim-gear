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

-- Item classes (Enum.ItemClass Armor 4, Weapon 2) and inventory types (Enum.InventoryType: neck 2,
-- finger 11, trinket 12, holdable 23), as Blizzard_AuctionData's categories filter them.
local ARMOR, WEAPON = 4, 2
local ARMOR_NAMES = { [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate", [6] = "Shields" }
local WEAPON_NAMES = { [0] = "One-handed axes", [1] = "Two-handed axes", [2] = "Bows", [3] = "Guns", [4] = "Maces",
	[5] = "Two-handed maces", [6] = "Polearms", [7] = "Swords", [8] = "Two-handed swords", [10] = "Staves",
	[13] = "Fist weapons", [15] = "Daggers", [16] = "Thrown", [18] = "Crossbows", [19] = "Wands" }
local JEWELRY = { 2, 11, 12, 23 }

local function sortedKeys(t)
	local out = {}
	for k in pairs(t) do out[#out + 1] = k end
	table.sort(out)
	return out
end

-- The scan's browse queries for a class at level + ahead: one per armor type it can wear by then (cloth
-- includes cloaks), one for neck, rings, trinkets and held-in-off-hand items, one per weapon subclass.
-- -> { { label, query = AuctionHouseBrowseQuery }, ... }
function AH.Queries(cls, level, ahead)
	local p = ns.DATA.proficiency[cls]
	if not p then return {} end
	local top = math.min(60, level + (ahead or 0))
	local filters = { enum("AuctionHouseFilter", "UsableOnly", 2) }
	for _, q in ipairs(QUALITIES) do filters[#filters + 1] = enum("AuctionHouseFilter", q[1], q[2]) end
	local function query(label, classFilters)
		return { label = label, query = { searchString = "", minLevel = 1, maxLevel = top, filters = filters,
			sorts = { { sortOrder = enum("AuctionHouseSortOrder", "Price", 0), reverseSort = false } },
			itemClassFilters = classFilters } }
	end
	local out = {}
	for _, sc in ipairs(sortedKeys(p.armor)) do
		if sc ~= 0 and top >= p.armor[sc] and ARMOR_NAMES[sc] then
			out[#out + 1] = query(ARMOR_NAMES[sc], { { classID = ARMOR, subClassID = sc } })
		end
	end
	local j = {}
	for _, inv in ipairs(JEWELRY) do j[#j + 1] = { classID = ARMOR, subClassID = 0, inventoryType = inv } end
	out[#out + 1] = query("Neck rings trinkets off hands", j)
	for _, sc in ipairs(sortedKeys(p.weapons)) do
		if p.weapons[sc] then out[#out + 1] = query(WEAPON_NAMES[sc] or ("Weapons " .. sc), { { classID = WEAPON, subClassID = sc } }) end
	end
	return out
end

-- The scan ---------------------------------------------------------------------------------------------
-- One query at a time: send it when the throttled message system is ready (else wait for
-- AUCTION_HOUSE_THROTTLED_SYSTEM_READY), read the results on each BROWSE_RESULTS_UPDATED/ADDED, ask for
-- more (RequestMoreBrowseResults, throttled too) until HasFullBrowseResults, then the next query. A
-- query with no answer for AH.STALL seconds (one timer per send; a stale one does nothing) or a
-- BROWSE_FAILURE counts as failed and the scan goes on. MAX_PAGES bounds the pages of one query.
AH.STALL = 20
AH.MAX_PAGES = 25

-- scan = { queries, i, pages, waiting ("ready" | "results"), token, failed, done, stopped (why) }
-- found: "itemID:suffix:itemLevel" -> { itemKey, minPrice, totalQuantity, result }; rows: the upgrades
local scan, found, rows, counts = nil, {}, {}, nil
local sending = false -- our own SendBrowseQuery (the hook below tells it from another search)
local hookedApi = nil

local function changed() ns.Fire("AH_CHANGED") end

function AH.Found() return found end
function AH.Rows() return rows end
function AH.Scanning() return scan ~= nil and not scan.done end

function AH.Status()
	if not scan then return nil end
	local n = #scan.queries
	if scan.stopped then return scan.stopped end
	if scan.cancelled then return string.format("Cancelled (%d/%d searched)", scan.searched, n) end
	if not scan.done then return string.format("Scanning %d/%d...", math.min(scan.i, n), n) end
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

local advance
local function finish()
	scan.done = true
	scan.waiting = nil
	if AH.Build then rows, counts = AH.Build(found) end
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

local function stop(why)
	if not AH.Scanning() then return end
	scan.done = true
	scan.waiting = nil
	if why then scan.stopped = why else scan.cancelled = true end
	if AH.Build then rows, counts = AH.Build(found) end
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
	found, rows, counts = {}, {}, nil
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
	scan, found, rows, counts = nil, {}, {}, nil
	changed()
end
ns.RegisterEvent("AUCTION_HOUSE_CLOSED", AH.Clear)
