-- Auction house upgrade scan (AH.lua): the browse queries, the scan over a stub C_AuctionHouse
-- (pages, the throttle, failure, cancel, close mid-scan), scoring browse results into upgrade rows,
-- sorting, selecting a result in the AH frame (never buying).
local T = require("t")
local FILES = { "Core.lua", "Options.lua", "Data/Weights.lua", "Data/Suffixes.lua", "Data/Items.lua", "Items.lua", "Score.lua",
	"Bands.lua", "Equip.lua", "Browser.lua", "Plan.lua", "Wishlist.lua", "AH.lua" }

-- A stub C_AuctionHouse: the browse system with pages and a throttle. -> api, log
-- server: list of browse results returned for every query (pages of `page` results), or a function
-- (query) -> list. ready(): IsThrottledMessageSystemReady. Purchase functions error when called.
local function stubAH(server, page)
	page = page or 2
	local log = { sent = {}, more = 0, bought = 0 }
	local api = { ready = true }
	local all, shown = {}, 0
	local function list() local out = {} for i = 1, shown do out[i] = all[i] end return out end
	function api.IsThrottledMessageSystemReady() return api.ready end
	function api.SendBrowseQuery(q)
		assert(api.ready, "sent while throttled")
		log.sent[#log.sent + 1] = q
		all = type(server) == "function" and server(q) or server
		shown = math.min(page, #all)
		log.pending = "updated"
	end
	function api.RequestMoreBrowseResults()
		assert(api.ready, "asked for more while throttled")
		log.more = log.more + 1
		shown = math.min(shown + page, #all)
		log.pending = "added"
	end
	function api.GetBrowseResults() return list() end
	function api.HasFullBrowseResults() return shown >= #all end
	function api.GetItemKeyInfo(key) return { itemID = key.itemID, itemName = api.names and api.names[key.itemID] or "x", quality = 2, isCommodity = false } end
	for _, f in ipairs({ "PlaceBid", "StartCommoditiesPurchase", "ConfirmCommoditiesPurchase" }) do
		api[f] = function() log.bought = log.bought + 1 error("bought") end
	end
	return api, log
end

local function result(id, price, suffix) return { itemKey = { itemID = id, itemLevel = 0, itemSuffix = suffix or 0, battlePetSpeciesID = 0 }, minPrice = price, totalQuantity = 1, containsOwnerItem = false } end

-- The addon with a level L priest (shadow), worn items { [slot] = item id } scored at their bands.
local function addon(L, wornIds, cls)
	local ns = T.addon(FILES)
	require("wow").level = L
	cls = cls or "priest"
	local spec = ns.DATA.defaultSpec[cls]
	local function at(level)
		local band, lo = ns.Bands.For(cls, spec, level)
		local worn = {}
		for slot, id in pairs(wornIds or {}) do
			local inst = ns.Score.Instance(ns.Items.Get(id))
			worn[slot] = { inst = inst, score = ns.Score.Score(inst, band.w, cls, ns.Equip.ROLE_OF_SLOT[slot] or "gear") }
		end
		return { cls = cls, spec = spec, level = level, band = band, lo = lo, w = band.w, worn = worn }
	end
	ns.Context = { Get = function() return at(L) end, At = at, ClassKey = function() return cls end }
	return ns
end

-- Events to the addon's frame (as the client fires them)
local function fire(ns, e, ...) ns._frame.scripts.OnEvent(ns._frame, e, ...) end
-- Deliver what the stub server has pending (the client's answer to the last send)
local function answer(ns, log)
	local p = log.pending
	log.pending = nil
	if p == "updated" then fire(ns, "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
	elseif p == "added" then fire(ns, "AUCTION_HOUSE_BROWSE_RESULTS_ADDED", {}) end
	return p
end
local function drain(ns, log) local n = 0 while answer(ns, log) do n = n + 1 end return n end

return {
	-- Priest: cloth, then neck/rings/trinkets/held in off hand (+ cloaks), then one query per weapon
	-- subclass (maces, staves, daggers, wands); usable only, common..epic, levels 1..level + ahead,
	-- cheapest first.
	queries_priest = function()
		local ns = addon(20)
		local qs = ns.AH.Queries("priest", 20, 3)
		local labels = {}
		for i, q in ipairs(qs) do labels[i] = q.label end
		T.eq(table.concat(labels, ","), "Cloth,Neck rings trinkets off hands,Maces,Staves,Daggers,Wands")
		local q = qs[1]
		T.eq(q.query.minLevel, 1); T.eq(q.query.maxLevel, 23); T.eq(q.query.searchString, "")
		T.eq(q.query.sorts[1].sortOrder, 0, "price"); T.eq(q.query.sorts[1].reverseSort, false)
		local f = {}
		for _, v in ipairs(q.query.filters) do f[v] = true end
		T.ok(f[2], "usable only"); T.ok(f[7] and f[8] and f[9] and f[10], "common..epic"); T.ok(not f[6], "no poor")
		T.eq(q.query.itemClassFilters[1].classID, 4); T.eq(q.query.itemClassFilters[1].subClassID, 1)
		local j = qs[2].query.itemClassFilters
		local invs = {}
		for _, c in ipairs(j) do invs[#invs + 1] = c.classID .. "/" .. c.subClassID .. "/" .. c.inventoryType end
		T.eq(table.concat(invs, ","), "4/0/2,4/0/11,4/0/12,4/0/23")
		T.eq(qs[4].query.itemClassFilters[1].classID, 2); T.eq(qs[4].query.itemClassFilters[1].subClassID, 10)
		T.eq(#ns.AH.Queries("mage", 20, 0), 6, "mage: cloth, jewelry, swords, staves, daggers, wands")
		T.eq(ns.AH.Queries("mage", 60, 5)[1].query.maxLevel, 60, "not past 60")
	end,
	-- The scan sends one query at a time, only when the throttled system is ready (else it waits for
	-- AUCTION_HOUSE_THROTTLED_SYSTEM_READY), asks for more pages until HasFullBrowseResults, then the
	-- next query; progress "Scanning n/6..."; at the end every distinct result is kept (cheapest price).
	scan_pages_throttle_progress = function()
		local ns = addon(20)
		local api, log = stubAH({ result(5, 900), result(6, 100), result(5, 700), result(7, 50), result(8, 10) }, 2)
		_G.C_AuctionHouse = api
		api.ready = false
		T.ok(ns.AH.Scan())
		T.eq(#log.sent, 0, "waits for the throttle")
		T.eq(ns.AH.Status(), "Scanning 1/6...")
		local function ready() api.ready = true fire(ns, "AUCTION_HOUSE_THROTTLED_SYSTEM_READY") end
		ready()
		T.eq(#log.sent, 1)
		-- each send makes the system busy until its answer and the ready event
		local real = api.SendBrowseQuery
		api.SendBrowseQuery = function(q) real(q) api.ready = false end
		local realMore = api.RequestMoreBrowseResults
		api.RequestMoreBrowseResults = function() realMore() api.ready = false end
		api.ready = false
		answer(ns, log) -- 2 of 5: wants more, not ready yet
		T.eq(log.more, 0, "no request while throttled")
		ready()
		T.eq(log.more, 1)
		answer(ns, log); ready(); answer(ns, log)
		T.eq(log.more, 2); T.eq(#log.sent, 1, "first query full after 3 pages")
		ready()
		T.eq(#log.sent, 2, "next query once ready")
		T.eq(ns.AH.Status(), "Scanning 2/6...")
		for _ = 1, 30 do answer(ns, log); ready() end
		T.eq(#log.sent, 6); T.eq(ns.AH.Scanning(), false)
		local found = ns.AH.Found()
		T.eq(found["5:0:0"].minPrice, 700, "cheapest of the two")
		local n = 0
		for _ in pairs(found) do n = n + 1 end
		T.eq(n, 4)
		T.eq(log.bought, 0)
	end,
	-- Cancel stops the scan: later events send nothing; the results so far stay.
	scan_cancel = function()
		local ns = addon(20)
		local api, log = stubAH({ result(5, 900) }, 5)
		_G.C_AuctionHouse = api
		ns.AH.Scan()
		T.eq(#log.sent, 1)
		ns.AH.Cancel()
		answer(ns, log)
		fire(ns, "AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
		T.eq(#log.sent, 1, "nothing after cancel"); T.eq(ns.AH.Scanning(), false)
		T.eq(ns.AH.Status(), "Cancelled (0/6 searched)")
	end,
	-- Closing the auction house mid-scan stops it and lets go of everything found.
	scan_close_mid_scan = function()
		local ns = addon(20)
		local api, log = stubAH({ result(5, 900) }, 5)
		_G.C_AuctionHouse = api
		ns.AH.Scan()
		answer(ns, log)
		T.eq(#log.sent, 2)
		fire(ns, "AUCTION_HOUSE_CLOSED")
		answer(ns, log)
		fire(ns, "AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
		T.eq(#log.sent, 2); T.eq(ns.AH.Scanning(), false)
		T.eq(next(ns.AH.Found()), nil, "released"); T.eq(#ns.AH.Rows(), 0)
		T.eq(ns.AH.Status(), nil)
	end,
	-- A failed query is counted and the scan goes on; a query that never answers is given up after
	-- AH.STALL seconds (one timer per send, nothing once the scan is over).
	scan_failure_and_stall = function()
		local ns = addon(20)
		local W = require("wow")
		local api, log = stubAH({ result(5, 900) }, 5)
		_G.C_AuctionHouse = api
		ns.AH.Scan()
		fire(ns, "AUCTION_HOUSE_BROWSE_FAILURE")
		T.eq(#log.sent, 2, "next query after a failure")
		log.pending = nil -- query 2 never answers
		T.eq(#W.timers, 2, "one stall timer per send")
		W.flush() -- query 1's timer is stale (it was answered), query 2's gives up
		T.eq(#log.sent, 3, "given up after the stall, once")
		for _ = 1, 20 do if ns.AH.Scanning() then answer(ns, log) end end
		T.eq(ns.AH.Scanning(), false)
		T.eq(ns.AH.Status():match("2 failed") ~= nil, true, ns.AH.Status())
	end,
	-- Another search (the player's own, another addon's) mid-scan: the scan stops, saying why.
	scan_stops_on_another_search = function()
		local ns = addon(20)
		local api, log = stubAH({ result(5, 900) }, 5)
		_G.C_AuctionHouse = api
		ns.AH.Scan()
		T.eq(#log.sent, 1)
		C_AuctionHouse.SendBrowseQuery({ searchString = "Robe" })
		T.eq(ns.AH.Scanning(), false)
		answer(ns, log)
		T.eq(#log.sent, 2, "only the player's own")
		T.eq(ns.AH.Status(), "Stopped: another search started")
	end,
}
