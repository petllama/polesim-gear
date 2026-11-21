-- Auction house upgrade scan (AH.lua): the browse queries, the scan over a stub C_AuctionHouse
-- (pages, the throttle, failure, cancel, close mid-scan), scoring browse results into upgrade rows,
-- sorting, selecting a result in the AH frame (never buying).
local T = require("t")
local FILES = { "Core.lua", "Options.lua", "Data/Weights.lua", "Data/Suffixes.lua", "Data/Items.lua", "Items.lua", "Score.lua",
	"Bands.lua", "Equip.lua", "Browser.lua", "Plan.lua", "Wishlist.lua", "AH.lua" }

local A = require("ahstub")
local stubAH, result = A.stub, A.result

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
		T.eq(ns.AH.Status(), "Done: 0 upgrades in 4 results, 4 not scored", "ids 5-8 are not in the shipped table")
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
	-- Scoring: each result's shipped item with its suffix (the item key's suffix when it is one of the
	-- item's bonus lists; else the name the client gives the key; else the row stands for every suffix:
	-- the best one's gain, flagged), compared with what is worn; upgrades only; unknown ids counted.
	build_scores_upgrades = function()
		local ns = addon(20, { [5] = 2585 }) -- wears Gray Woolen Robe
		local api = stubAH({})
		api.names = { [789] = "Stout Battlehammer of the Owl" }
		_G.C_AuctionHouse = api
		local found = {}
		local function add(id, price, suffix) local r = result(id, price, suffix) found[id .. ":" .. (suffix or 0) .. ":0"] = { itemKey = r.itemKey, minPrice = price, result = r } end
		add(2585, 5000) -- the worn robe: no gain
		add(2292, 20000) -- Necrology Robes (rl 20): an upgrade
		add(999999, 100) -- not in the shipped table
		add(789, 30000, 12718) -- of the Eagle, from the key
		add(15224, 10000) -- Battlesmasher: suffix not in the key, its name has none: every suffix
		local rows, counts = ns.AH.Build(found, ns.Context.Get(), 0)
		T.eq(counts.results, 5); T.eq(counts.notScored, 1)
		local by = {}
		for _, r in ipairs(rows) do by[r.c.id] = r end
		T.eq(by[2585], nil, "worn: not an upgrade")
		local robe = by[2292]
		T.ok(robe and robe.gain > 0, "upgrade"); T.eq(robe.slot.key, "chest"); T.eq(robe.price, 20000)
		T.near(robe.value, robe.gain / 2, 1e-9, "gain per gold")
		T.eq(robe.at, nil, "wearable now")
		local w = ns.Context.Get().w
		local base = ns.Score.Score(ns.Score.Instance(ns.Items.Get(2585)), w, "priest", "gear")
		T.near(robe.gain, ns.Score.Score(ns.Score.Instance(ns.Items.Get(2292)), w, "priest", "gear") - base, 1e-9)
		local eagle = by[789]
		T.eq(eagle.c.inst.bonus, 12718); T.eq(eagle.c.inst.name, "Stout Battlehammer of the Eagle")
		local any = by[15224]
		T.ok(any.anySuffix, "the browse row stands for every suffix")
		local best = select(2, ns.Score.BestSuffix(ns.Items.Get(15224), w, "priest", "mh"))
		T.near(any.c.score, best, 1e-9, "scored with its best suffix")
		T.ok(any.anySuffix.worst < any.gain, "the weakest suffix gains less")
		-- the key's suffix is not one of the item's bonus lists: the client's name says which
		found = {}
		add(789, 30000, 77)
		rows = ns.AH.Build(found, ns.Context.Get(), 0)
		T.eq(rows[1].c.inst.bonus, 12720, "of the Owl, from the name"); T.eq(rows[1].anySuffix, nil)
	end,
	-- Look ahead: an item up to level + ahead is kept, marked with its level and scored with that
	-- level's band (as the window's coming rows); past the look ahead: left out.
	build_look_ahead = function()
		local ns = addon(18)
		_G.C_AuctionHouse = stubAH({})
		local r = result(2292, 1000) -- Necrology Robes, required level 20 (band 20-29; level 18 is in 1-19)
		local found = { ["2292:0:0"] = { itemKey = r.itemKey, minPrice = 1000, result = r } }
		T.eq(#ns.AH.Build(found, ns.Context.Get(), 1), 0, "level 20 is past 18 + 1")
		local rows = ns.AH.Build(found, ns.Context.Get(), 2)
		T.eq(rows[1].at, 20)
		local w20 = ns.Context.At(20).w
		T.near(rows[1].c.score, ns.Score.Score(ns.Score.Instance(ns.Items.Get(2292)), w20, "priest", "gear"), 1e-9, "level 20's band")
	end,
	-- Weapons are one set: under a worn staff an AH one-hander pairs with the best AH off hand (and the
	-- reverse); the set must beat the staff; its value counts both prices. Rings: against the weaker.
	build_weapon_set_and_rings = function()
		local ns = addon(21, { [16] = 1405, [11] = 1156 }) -- Foamspittle Staff; one ring worn, the other empty
		_G.C_AuctionHouse = stubAH({})
		local found = {}
		local function add(id, price) local r = result(id, price) found[id .. ":0:0"] = { itemKey = r.itemKey, minPrice = price, result = r } end
		add(789, 4000) -- Stout Battlehammer (main hand), every suffix
		add(4838, 1000) -- Orb of Power (held in off hand)
		add(1077, 500) -- Defias Mage Ring
		local ctx = ns.Context.Get()
		local rows = ns.AH.Build(found, ctx, 0)
		local by = {}
		for _, r in ipairs(rows) do by[r.c.id] = r end
		local staff = ctx.worn[16].score
		local mace, orb = by[789], by[4838]
		T.ok(mace and orb, "both listed as a set")
		T.near(mace.gain, mace.c.score + orb.c.score - staff, 1e-9, "mace + orb over the staff")
		T.near(orb.gain, mace.gain, 1e-9, "the same set")
		T.eq(mace.partner, orb); T.eq(orb.partner, mace)
		T.eq(mace.setPrice, 5000); T.near(mace.value, mace.gain / 0.5, 1e-9)
		T.ok(mace.note:find("Orb of Power", 1, true), mace.note)
		local ring = by[1077]
		T.ok(ring and ring.gain > 0); T.eq(ring.base, 0, "against the empty ring slot")
		-- a set that does not beat the staff is no upgrade
		ns.Context.Get = function() local c = ns.Context.At(21) c.worn[16].score = 1000 return c end
		T.eq(#ns.AH.Build({ ["4838:0:0"] = found["4838:0:0"] }, ns.Context.Get(), 0), 0)
	end,
	-- Sort: Gain (default, biggest first), Value (gain per gold), Price (cheapest first).
	sort_orders = function()
		local ns = addon(20)
		local function row(id, gain, price) return { c = { id = id }, key = id .. ":0", gain = gain, price = price, value = gain / (price / 10000) } end
		local rows = { row(1, 5, 50000), row(2, 3, 1000), row(3, 8, 900000), row(4, 3, 500) }
		local function ids(by)
			local out = {}
			for i, r in ipairs(ns.AH.Sort(rows, by)) do out[i] = r.c.id end
			return table.concat(out, ",")
		end
		T.eq(ids("gain"), "3,1,4,2", "ties: cheaper first")
		T.eq(ids("value"), "4,2,1,3")
		T.eq(ids("price"), "4,2,1,3")
		T.eq(ids(nil), "3,1,4,2", "default gain")
		T.eq(rows[1].c.id, 1, "a new list")
	end,
	-- A row's click selects its browse result in the AH frame the Blizzard way (SelectBrowseResult: the
	-- item's listings, cheapest buyout first); from the item buy view the listing is asked again
	-- (RefreshSearchResults). Nothing is bought; no item data yet: nothing happens, saying why.
	select_opens_listing_never_buys = function()
		local ns = addon(20)
		local api, log = stubAH({})
		_G.C_AuctionHouse = api
		local calls = {}
		_G.AuctionHouseFrameDisplayMode = { Buy = { "BrowseResultsFrame" }, ItemBuy = { "ItemBuyFrame" } }
		_G.AuctionHouseSearchContext = { BuyItems = 9 }
		local mode = AuctionHouseFrameDisplayMode.Buy
		_G.AuctionHouseFrame = {
			IsShown = function() return true end,
			GetDisplayMode = function() return mode end,
			SelectBrowseResult = function(_, r) calls[#calls + 1] = { "select", r } mode = AuctionHouseFrameDisplayMode.ItemBuy end,
			RefreshSearchResults = function(_, ctx, key) calls[#calls + 1] = { "refresh", ctx, key } end,
		}
		local r1, r2 = result(2292, 100), result(2585, 50)
		T.ok(ns.AH.Select({ result = r1, itemKey = r1.itemKey }))
		T.eq(#calls, 1); T.eq(calls[1][1], "select"); T.eq(calls[1][2], r1)
		T.ok(ns.AH.Select({ result = r2, itemKey = r2.itemKey }))
		T.eq(calls[2][2], r2); T.eq(calls[3][1], "refresh"); T.eq(calls[3][2], 9); T.eq(calls[3][3], r2.itemKey)
		api.GetItemKeyInfo = function() return nil end
		local ok, why = ns.AH.Select({ result = r1, itemKey = r1.itemKey })
		T.eq(ok, false); T.ok(why:find("not loaded"), why); T.eq(#calls, 3)
		T.eq(log.bought, 0)
		_G.AuctionHouseFrame, _G.AuctionHouseFrameDisplayMode, _G.AuctionHouseSearchContext = nil, nil, nil
	end,
	-- A change of scores (equipping a bought item, a level) scores the results again: the item worn
	-- now leaves the list.
	rescore_on_scores_changed = function()
		local ns = addon(20)
		local api, log = stubAH({ result(2292, 100) }, 5)
		_G.C_AuctionHouse = api
		ns.AH.Scan()
		for _ = 1, 10 do answer(ns, log) end
		T.eq(#ns.AH.Rows(), 1)
		local worn = ns.Context.Get
		ns.Context.Get = function()
			local c = worn()
			local inst = ns.Score.Instance(ns.Items.Get(2292))
			c.worn[5] = { inst = inst, score = ns.Score.Score(inst, c.w, "priest", "gear") }
			return c
		end
		ns.Fire("SCORES_CHANGED")
		T.eq(#ns.AH.Rows(), 0, "worn now")
	end,
}
