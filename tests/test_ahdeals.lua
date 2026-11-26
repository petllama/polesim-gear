-- Kept auction house results and deals (AH.lua, AHPanel.lua): the price history (one price a day, the
-- day's cheapest, pruning and caps), the median/deal rule (60%, 3+ earlier days, today excluded), the
-- saved scan per realm-faction restored and re-scored when the AH opens (another character too), the
-- Deals sort, the deal tag and tooltip, history-only levels past the look ahead, and old saved
-- variables without the new tables.
local T = require("t")
local F = require("winfix")
local A = require("ahstub")

local DAY = 86400
local D0 = 20000 -- a day number (AH.Day falls back to floor(t / 86400) without the client's date())

local function fire(ns, e, ...) ns._frame.scripts.OnEvent(ns._frame, e, ...) end
local function answerAll(ns, log)
	for _ = 1, 50 do
		local p = log.pending
		if not p then break end
		log.pending = nil
		fire(ns, p == "updated" and "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or "AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
	end
end

-- the whole addon with a stub AH (as test_ahpanel); opts.now = the clock (seconds)
local function setup(results, opts)
	opts = opts or {}
	local fx = F.load(opts)
	local api, log = A.stub(results or {}, 10)
	_G.C_AuctionHouse = api
	_G.GetRealmName = function() return opts.realm or "Forever" end
	_G.AuctionHouseFrameDisplayMode = { Buy = { "BrowseResultsFrame" }, ItemBuy = { "ItemBuyFrame" } }
	_G.AuctionHouseSearchContext = { BuyItems = 9 }
	local ahf = fx.U.new("Frame", _G.UIParent, "AuctionHouseFrame")
	ahf:SetSize(800, 540)
	ahf.BrowseResultsFrame, ahf.ItemBuyFrame = false, false
	ahf.mode = AuctionHouseFrameDisplayMode.Buy
	function ahf:GetDisplayMode() return self.mode end
	function ahf:SelectBrowseResult(r) self.selected = r self.mode = AuctionHouseFrameDisplayMode.ItemBuy end
	function ahf:RefreshSearchResults(ctx, key) self.refreshed = key end
	fx.api, fx.log, fx.ahf = api, log, ahf
	fx.now = opts.now or (D0 * DAY + 3600)
	fx.ns.AH.Now = function() return fx.now end
	function fx.open()
		fire(fx.ns, "ADDON_LOADED", "Blizzard_AuctionHouseUI")
		fire(fx.ns, "AUCTION_HOUSE_SHOW")
		fx.settle()
	end
	function fx.scan()
		fx.U.button(fx.ns.AHPanel.frame, "Scan for upgrades"):Click()
		answerAll(fx.ns, fx.log)
		fx.settle()
	end
	function fx.close() fire(fx.ns, "AUCTION_HOUSE_CLOSED") end
	function fx.ids()
		local out = {}
		for i, r in ipairs(fx.U.rows(fx.ns.AHPanel.list)) do out[i] = r.d.c.id end
		return table.concat(out, ",")
	end
	function fx.row(id)
		for _, r in ipairs(fx.U.rows(fx.ns.AHPanel.list)) do if r.d.c.id == id then return r end end
	end
	function fx.cleanup()
		_G.C_AuctionHouse, _G.AuctionHouseFrame, _G.AuctionHouseFrameDisplayMode, _G.AuctionHouseSearchContext = nil, nil, nil, nil
		_G.GetRealmName = nil
		fx.done()
	end
	return fx
end

-- a history entry with prices on days (D0 - n ... )
local function hist(prices)
	local d, last = {}, nil
	for _, dp in ipairs(prices) do d[#d + 1] = dp[1] d[#d + 1] = dp[2] last = dp[1] end
	return { s = last, d = d }
end

-- pure functions: an addon with AH.lua only
local FILES = { "Core.lua", "Options.lua", "Data/Weights.lua", "Data/Suffixes.lua", "Data/Items.lua", "Items.lua", "Score.lua",
	"Bands.lua", "Equip.lua", "Browser.lua", "Plan.lua", "Wishlist.lua", "AH.lua" }

return {
	-- One entry a day per item: the day's lowest price; a later, dearer scan the same day changes nothing;
	-- the next day appends; at most HISTORY_DAYS days (the oldest go).
	history_one_per_day_min = function()
		local AH = T.addon(FILES).AH
		local h = {}
		AH.Record(h, { ["2292:0"] = 5000 }, D0)
		AH.Record(h, { ["2292:0"] = 7000 }, D0)
		AH.Record(h, { ["2292:0"] = 4000 }, D0)
		T.eq(table.concat(h["2292:0"].d, ","), D0 .. ",4000", "one entry, the day's lowest")
		AH.Record(h, { ["2292:0"] = 9000 }, D0 + 1)
		T.eq(table.concat(h["2292:0"].d, ","), D0 .. ",4000," .. (D0 + 1) .. ",9000")
		T.eq(h["2292:0"].s, D0 + 1, "last seen")
		AH.Record(h, { ["2292:0"] = 1 }, D0 - 5) -- the clock went back: ignored
		T.eq(#h["2292:0"].d, 4)
		AH.Record(h, { ["2292:0"] = 0, ["5:0"] = 0 }, D0 + 1) -- no price: nothing
		T.eq(h["5:0"], nil)
		for i = 2, 20 do AH.Record(h, { ["2292:0"] = 100 * i }, D0 + i) end
		local d = h["2292:0"].d
		T.eq(#d, 2 * AH.HISTORY_DAYS, "14 days kept")
		T.eq(d[1], D0 + 20 - 13, "the oldest dropped"); T.eq(d[#d], 2000)
	end,
	-- Items not seen for 30 days are dropped; past HISTORY_MAX items the longest unseen go.
	history_prune_and_cap = function()
		local AH = T.addon(FILES).AH
		local h = { old = hist({ { D0 - 31, 10 } }), kept = hist({ { D0 - 30, 10 } }) }
		AH.Record(h, { new = 5 }, D0)
		T.eq(h.old, nil, "31 days unseen: gone"); T.ok(h.kept, "30 days: kept"); T.ok(h.new)
		local cap = AH.HISTORY_MAX
		AH.HISTORY_MAX = 3
		local h2 = { a = hist({ { D0 - 3, 1 } }), b = hist({ { D0 - 1, 1 } }), c = hist({ { D0 - 2, 1 } }) }
		AH.Record(h2, { d = 7 }, D0)
		T.eq(h2.a, nil, "the longest unseen dropped"); T.ok(h2.b and h2.c and h2.d)
		AH.HISTORY_MAX = cap
		T.eq(cap, 3000)
	end,
	-- Median (odd, even); a deal needs 3+ EARLIER days (today never counts) and a price at most 60% of
	-- their median; the discount, days and "lowest seen".
	median_and_deal_rule = function()
		local AH = T.addon(FILES).AH
		T.eq(AH.Median({ 3, 1, 2 }), 2); T.eq(AH.Median({ 4, 1, 3, 2 }), 2.5); T.eq(AH.Median({}), nil)
		local h = { k = hist({ { D0 - 2, 10000 }, { D0 - 1, 12000 } }) }
		T.eq(AH.Deal(h, "k", 1000, D0), nil, "2 earlier days: no guess")
		h.k = hist({ { D0 - 2, 10000 }, { D0 - 1, 12000 }, { D0, 1 } })
		T.eq(AH.Deal(h, "k", 1000, D0), nil, "today's entry does not count")
		h.k = hist({ { D0 - 3, 10000 }, { D0 - 2, 14000 }, { D0 - 1, 12000 }, { D0, 500 } })
		local d = AH.Deal(h, "k", 7200, D0)
		T.eq(d.deal, true, "60% of 12000 exactly"); T.eq(d.median, 12000); T.eq(d.days, 3)
		T.ok(math.abs(d.pct - 0.4) < 1e-9); T.eq(d.lowest, true)
		d = AH.Deal(h, "k", 7201, D0)
		T.eq(d.deal, false, "just above 60%: not a deal"); T.eq(d.lowest, true)
		d = AH.Deal(h, "k", 11000, D0)
		T.eq(d.deal, false); T.eq(d.lowest, false, "10000 was lower")
		T.eq(AH.Deal(h, "nope", 100, D0), nil); T.eq(AH.Deal(nil, "k", 100, D0), nil)
	end,
	-- The Deals sort: deals first (biggest discount first), then by gain.
	deals_sort = function()
		local AH = T.addon(FILES).AH
		local rows = {
			{ key = "a", gain = 9, price = 100, value = 1 },
			{ key = "b", gain = 1, price = 100, value = 1, deal = { pct = 0.5 } },
			{ key = "c", gain = 2, price = 100, value = 1, deal = { pct = 0.7 } },
			{ key = "d", gain = 5, price = 100, value = 1 },
			{ key = "e", gain = 3, price = 100, value = 1, deal = { pct = 0.5 } },
		}
		local out = {}
		for i, r in ipairs(AH.Sort(rows, "deal")) do out[i] = r.key end
		T.eq(table.concat(out, ","), "c,e,b,a,d")
	end,
	-- A scan records every scored item's price (upgrade or not) under PoleSimGearDB.ah per realm-faction,
	-- saves the scan; the next day's cheaper listing after 3 days of history is a deal: orange "deal"
	-- tag, tooltip line, Deals sort button; nothing bought.
	scan_records_and_flags_deals = function()
		local res = { A.result(2292, 20000), A.result(2585, 900) }
		local fx = setup(res)
		local ns = fx.ns
		fx.open()
		fx.scan()
		local st = ns.db.ah.realms["Forever-Horde"]
		T.ok(st and st.hist, "per realm and faction")
		T.eq(table.concat(st.hist["2292:0"].d, ","), D0 .. ",20000")
		T.ok(st.hist["2585:0"], "an upgrade or not, recorded")
		T.ok(st.scan and st.scan.f["2292:0:0"], "the scan saved")
		T.eq(st.scan.at, fx.now)
		-- three more days at 20000, then 11000 (55% of usual)
		for i = 1, 3 do
			fx.close()
			fx.now = fx.now + DAY
			fx.open()
			fx.scan()
		end
		T.eq(#st.hist["2292:0"].d, 8)
		res[1] = A.result(2292, 11000)
		fx.close()
		fx.now = fx.now + DAY
		fx.open()
		fx.scan()
		local robe = fx.row(2292)
		T.ok(robe.d.deal, "a deal")
		T.ok(robe.item.sub.text:find("deal", 1, true), robe.item.sub.text)
		T.ok(not fx.row(2585).d.deal and not fx.row(2585).item.sub.text:find("deal", 1, true), "not the other")
		T.eq(#fx.U.overflows(ns.AHPanel.frame), 0, table.concat(fx.U.overflows(ns.AHPanel.frame), "; "))
		robe.scripts.OnEnter(robe)
		local lines = table.concat(fx.U.tip.lines, "\n")
		T.ok(lines:find("Deal: 45% below usual (median 20000c over 4 days)", 1, true), lines)
		T.ok(lines:find("Lowest price seen in 4 days of scans", 1, true), lines)
		T.ok(not lines:find("Last scan", 1, true) and not lines:find("listings may have changed", 1, true), "live prices")
		local db = fx.U.button(ns.AHPanel.frame, "Deals")
		T.ok(db, "Deals sort")
		T.ok(fx.U.textWidth("Value", 12) <= ns.AHPanel.SORT_W - 4, "sort labels fit")
		db:Click()
		T.eq(fx.U.rows(ns.AHPanel.list)[1].d.c.id, 2292, "deals first")
		T.eq(fx.log.bought, 0)
		fx.cleanup()
	end,
	-- History only past the look ahead: the scan searches 2 levels ahead (look ahead 0), records the
	-- level-21 robe's price, but lists, counts and offers in the Slot dropdown only what the look ahead
	-- allows.
	extra_levels_history_only = function()
		local fx = setup({ A.result(2800, 1000), A.result(2585, 900) }, { level = 19 })
		local ns = fx.ns
		ns.Options.View().ahead = 0
		fx.open()
		fx.scan()
		T.eq(fx.log.sent[1].maxLevel, 21, "searched to level + 2")
		T.eq(#fx.log.sent, #ns.AH.Queries("priest", 19, 0), "no extra queries")
		local st = ns.db.ah.realms["Forever-Horde"]
		T.ok(st.hist["2800:0"], "Black Velvet Robes (level 21) recorded")
		T.eq(fx.ids(), "2585", "not listed")
		T.ok(ns.AH.Status():find("in 1 results", 1, true), ns.AH.Status())
		local texts = {}
		for i, it in ipairs(fx.U.menu(ns.AHPanel.frame.slot)) do texts[i] = it.text end
		T.eq(table.concat(texts, "|"), "All slots|Chest (1)")
		ns.Style.ClosePopup()
		-- look ahead 3: searched to 22, the robe listed
		ns.Options.View().ahead = 3
		fx.scan()
		T.eq(fx.log.sent[#fx.log.sent].maxLevel, 22)
		T.ok(fx.row(2800), "listed within the look ahead")
		fx.cleanup()
	end,
	-- The AH opening lists the saved scan (re-scored) with "Last scan 3 h ago" until a new scan; a click
	-- still opens the item's live listings; the tooltip says the price is from that scan.
	restore_on_open = function()
		local fx = setup({ A.result(2292, 20000), A.result(2585, 900) })
		local ns = fx.ns
		fx.open()
		fx.scan()
		local live = fx.ids()
		fx.close()
		T.eq(#ns.AH.Rows(), 0)
		fx.now = fx.now + 3 * 3600
		fx.api.SendBrowseQuery = function() error("no search on open") end
		fx.open()
		T.eq(fx.ids(), live, "the same rows")
		T.ok(ns.AH.Status():find("Last scan 3 h ago", 1, true), ns.AH.Status())
		T.ok(fx.U.texts(ns.AHPanel.frame):find("Last scan 3 h ago", 1, true))
		T.eq(#fx.U.overflows(ns.AHPanel.frame), 0, table.concat(fx.U.overflows(ns.AHPanel.frame), "; "))
		T.ok(fx.U.textWidth("Last scan 29 days ago: 999 upgrades (old prices)", 11) <= ns.AHPanel.W - 168, "the longest status fits")
		local robe = fx.row(2292)
		robe:Click("LeftButton")
		T.eq(fx.ahf.selected.itemKey.itemID, 2292, "its listings")
		robe.scripts.OnEnter(robe)
		local lines = table.concat(fx.U.tip.lines, "\n")
		T.ok(lines:find("Price from the last scan, 3 h ago", 1, true), lines)
		T.eq(ns.AHPanel.frame.slot.enabled, true, "slot filter usable")
		T.eq(fx.log.bought, 0)
		fx.cleanup()
	end,
	-- The saved scan belongs to the realm-faction: another character there gets it re-scored for its own
	-- class/level (here a mage, who has another weapon style and weights); another realm gets nothing.
	restore_for_another_character = function()
		local db = {}
		local fx = setup({ A.result(2292, 20000), A.result(2585, 900), A.result(789, 30000, 12718) }, { db = db })
		fx.open()
		fx.scan()
		local priestRows = {}
		for _, r in ipairs(fx.ns.AH.Rows()) do priestRows[r.c.id] = r.gain end
		T.ok(priestRows[789], "the priest lists the mace")
		fx.cleanup()
		local fx2 = setup({}, { db = db, cls = "mage", level = 22 })
		fx2.api.SendBrowseQuery = function() error("no search on open") end
		fx2.open()
		local ns = fx2.ns
		T.ok(ns.AH.Restored(), "restored")
		local by = {}
		for _, r in ipairs(ns.AH.Rows()) do by[r.c.id] = r end
		T.eq(by[789], nil, "a mage can't use a mace")
		T.ok(by[2292] and by[2585], "the robes, scored for the mage")
		T.ok(math.abs(by[2292].gain - priestRows[2292]) > 1e-6, "re-scored with the mage's weights")
		fx2.cleanup()
		local fx3 = setup({}, { db = db, realm = "Elsewhere" })
		fx3.open()
		T.eq(fx3.ns.AH.Restored(), nil); T.eq(#fx3.ns.AH.Rows(), 0)
		fx3.cleanup()
	end,
	-- No weights yet when the AH opens: the saved scan waits and is restored when scores change.
	restore_waits_for_weights = function()
		local fx = setup({ A.result(2292, 20000) })
		fx.open()
		fx.scan()
		fx.close()
		local get = fx.ns.Context.Get
		fx.ns.Context.Get = function() return nil end
		fx.open()
		T.eq(fx.ns.AH.Restored(), nil, "not yet")
		fx.ns.Context.Get = get
		fx.ns.Fire("SCORES_CHANGED")
		fx.settle()
		T.ok(fx.ns.AH.Restored(), "restored once there are weights")
		T.eq(fx.ids(), "2292")
		fx.cleanup()
	end,
	-- Old saved variables (no `ah`, or junk in it) load and scan; a cancelled scan keeps the saved one.
	old_saved_variables = function()
		local fx = setup({ A.result(2292, 20000) }, { db = { options = {}, ah = { realms = { ["Forever-Horde"] = { scan = "junk", hist = 5 } } } } })
		fx.open()
		T.eq(fx.ns.AH.Restored(), nil, "junk: nothing restored")
		fx.scan()
		local st = fx.ns.db.ah.realms["Forever-Horde"]
		T.ok(type(st.hist) == "table" and st.hist["2292:0"], "history started")
		T.ok(type(st.scan) == "table")
		fx.cleanup()
		local fx2 = setup({ A.result(2292, 20000) }, { db = { options = {} } })
		fx2.open()
		T.eq(fx2.ns.AH.Restored(), nil)
		fx2.scan()
		T.ok(fx2.ns.db.ah.realms["Forever-Horde"].hist["2292:0"])
		local saved = fx2.ns.db.ah.realms["Forever-Horde"].scan
		fx2.api.ready = false
		fx2.U.button(fx2.ns.AHPanel.frame, "Scan for upgrades"):Click()
		fx2.U.button(fx2.ns.AHPanel.frame, "Cancel"):Click()
		fx2.settle()
		T.eq(fx2.ns.db.ah.realms["Forever-Horde"].scan, saved, "a cancelled scan does not replace it")
		fx2.cleanup()
	end,
}
