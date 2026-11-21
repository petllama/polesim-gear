-- The AH upgrades panel (AHPanel.lua) on a stub auction house frame, with the whole addon (winfix):
-- made when Blizzard_AuctionHouseUI loads, toggled and remembered, Scan/Cancel, rows (name, slot,
-- gain, price, gain per gold, look-ahead level), sorts, the item tooltip, a click selects the result,
-- and closing the auction house lets go of rows and results.
local T = require("t")
local F = require("winfix")
local A = require("ahstub")

local function fire(ns, e, ...) ns._frame.scripts.OnEvent(ns._frame, e, ...) end
local function answerAll(ns, log)
	for _ = 1, 50 do
		local p = log.pending
		if not p then break end
		log.pending = nil
		fire(ns, p == "updated" and "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or "AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
	end
end

-- the addon, a stub AH frame and API (results: browse results returned for every query)
local function setup(results, opts)
	local fx = F.load(opts)
	local U = fx.U
	local api, log = A.stub(results or {}, 10)
	_G.C_AuctionHouse = api
	_G.AuctionHouseFrameDisplayMode = { Buy = { "BrowseResultsFrame" }, ItemBuy = { "ItemBuyFrame" } }
	_G.AuctionHouseSearchContext = { BuyItems = 9 }
	local ahf = U.new("Frame", _G.UIParent, "AuctionHouseFrame")
	ahf:SetSize(800, 540)
	ahf.BrowseResultsFrame, ahf.ItemBuyFrame = false, false -- (Arrows hooks their lists: none here)
	ahf.mode = AuctionHouseFrameDisplayMode.Buy
	function ahf:GetDisplayMode() return self.mode end
	function ahf:SelectBrowseResult(r) self.selected = r self.mode = AuctionHouseFrameDisplayMode.ItemBuy end
	function ahf:RefreshSearchResults(ctx, key) self.refreshed = key end
	fx.api, fx.log, fx.ahf = api, log, ahf
	function fx.loadAH() fire(fx.ns, "ADDON_LOADED", "Blizzard_AuctionHouseUI") end
	function fx.cleanup()
		_G.C_AuctionHouse, _G.AuctionHouseFrame, _G.AuctionHouseFrameDisplayMode, _G.AuctionHouseSearchContext = nil, nil, nil, nil
		fx.done()
	end
	return fx
end

local function scanned(fx)
	fx.loadAH()
	local P = fx.ns.AHPanel
	fx.U.button(P.frame, "Scan for upgrades"):Click()
	answerAll(fx.ns, fx.log)
	return P
end

local RESULTS = { A.result(2292, 20000), A.result(2585, 900), A.result(789, 30000, 12718), A.result(999999, 5) }

return {
	-- Nothing before the AH UI loads; then a "PoleSim upgrades" button on the AH frame and the panel
	-- docked to its right (shown by default); the button hides and shows it, and the choice is kept.
	attach_and_toggle = function()
		local fx = setup()
		local ns = fx.ns
		T.eq(ns.AHPanel.frame, nil, "not before the AH UI loads")
		fx.loadAH()
		local P = ns.AHPanel
		T.ok(P.button and P.button.parent == fx.ahf, "on the AH frame")
		T.eq(fx.U.ownText(P.button), "PoleSim upgrades")
		T.ok(P.frame and P.frame:IsShown(), "shown by default")
		T.eq(P.frame.parent, fx.ahf, "hides with the AH frame")
		local p = P.frame:GetPoint(1)
		T.eq(p, "TOPLEFT"); T.eq(select(2, P.frame:GetPoint(1)), fx.ahf); T.eq(select(3, P.frame:GetPoint(1)), "TOPRIGHT")
		P.button:Click()
		T.eq(P.frame:IsShown(), false); T.eq(ns.Options.Get("ahPanel"), false, "remembered")
		P.button:Click()
		T.eq(P.frame:IsShown(), true); T.eq(ns.Options.Get("ahPanel"), true)
		fx.loadAH() -- a second load event makes nothing twice
		T.eq(#P.frame.children > 0, true)
		fx.cleanup()
	end,
	-- Scan: the button turns into Cancel with "Scanning n/6..."; at the end the upgrades are listed
	-- (biggest gain first) with slot, gain, price and gain per gold; unknown items are counted.
	scan_and_rows = function()
		local fx = setup(RESULTS)
		fx.loadAH()
		local P, U = fx.ns.AHPanel, fx.U
		fx.api.ready = false
		U.button(P.frame, "Scan for upgrades"):Click()
		T.ok(U.button(P.frame, "Cancel"), "Cancel while scanning")
		T.ok(U.texts(P.frame):find("Scanning 1/6...", 1, true))
		fx.api.ready = true
		fire(fx.ns, "AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
		answerAll(fx.ns, fx.log)
		T.ok(U.button(P.frame, "Scan for upgrades"), "Scan again")
		local text = U.texts(P.frame)
		T.ok(text:find("1 not scored", 1, true), text)
		local rows = U.rows(P.list)
		T.eq(#rows, 3, "Necrology Robes, Gray Woolen Robe, Stout Battlehammer of the Eagle")
		local first = rows[1].d
		for _, r in ipairs(rows) do T.ok(r.d.gain <= first.gain, "biggest gain first") end
		local robe
		for _, r in ipairs(rows) do if r.d.c.id == 2292 then robe = r end end
		T.ok(U.ownText(robe.item.name):find("Necrology Robes", 1, true))
		T.ok(robe.item.sub.text:find("Chest", 1, true))
		T.eq(robe.gain.text, fx.ns.Style.Signed(robe.d.gain))
		T.eq(robe.price.text, "20000c", "GetMoneyString of the cheapest")
		T.eq(robe.value.text, string.format("%+.1f", robe.d.gain / 2))
		T.eq(#U.overflows(P.frame), 0, table.concat(U.overflows(P.frame), "; "))
		T.eq(fx.log.bought, 0)
		fx.cleanup()
	end,
	-- Sort toggles: Value (gain per gold) and Price (cheapest first); Gain again.
	sort_toggles = function()
		local fx = setup(RESULTS)
		local P, U = scanned(fx), fx.U
		local function ids()
			local out = {}
			for i, r in ipairs(U.rows(P.list)) do out[i] = r.d.c.id end
			return table.concat(out, ",")
		end
		local byGain = ids()
		U.button(P.frame, "Price"):Click()
		local rows = U.rows(P.list)
		for i = 2, #rows do T.ok(rows[i - 1].d.price <= rows[i].d.price, "cheapest first") end
		U.button(P.frame, "Value"):Click()
		rows = U.rows(P.list)
		for i = 2, #rows do T.ok(rows[i - 1].d.value >= rows[i].d.value, "best value first") end
		U.button(P.frame, "Gain"):Click()
		T.eq(ids(), byGain)
		fx.cleanup()
	end,
	-- A row's click selects its result in the AH (its listings); the hover shows the game's item
	-- tooltip with the row's suffix, PoleSim's lines and the AH lines; nothing is bought.
	click_and_tooltip = function()
		local fx = setup(RESULTS)
		local P, U = scanned(fx), fx.U
		local eagle
		for _, r in ipairs(U.rows(P.list)) do if r.d.c.id == 789 then eagle = r end end
		eagle:Click("LeftButton")
		T.eq(fx.ahf.selected, eagle.d.result, "the row's browse result")
		eagle.scripts.OnEnter(eagle)
		T.eq(U.tip.link, "item:789" .. string.rep(":", 12) .. "1:12718", "the item with its suffix")
		local lines = table.concat(U.tip.lines, "\n")
		T.ok(lines:find("Gain over what you wear", 1, true), lines)
		T.ok(lines:find("Auction house: 30000c", 1, true), lines)
		T.ok(lines:find("Click: its listings", 1, true), lines)
		T.ok(not lines:find("best suffix", 1, true), "the suffix is the auction's own")
		T.eq(fx.log.bought, 0)
		fx.cleanup()
	end,
	-- An item above your level within the look ahead: "lvl N" in gold on its row.
	look_ahead_tag = function()
		local fx = setup({ A.result(2800, 1000) }, { level = 19 }) -- Black Velvet Robes, level 21
		fx.ns.Options.View().ahead = 2
		local P, U = scanned(fx), fx.U
		local rows = U.rows(P.list)
		T.eq(#rows, 1); T.eq(rows[1].d.at, 21)
		T.ok(rows[1].item.sub.text:find("lvl 21", 1, true), rows[1].item.sub.text)
		fx.cleanup()
	end,
	-- Closing the auction house stops a scan and lets go of results and rows (the rows' data too).
	close_releases = function()
		local fx = setup(RESULTS)
		local P, U = scanned(fx), fx.U
		local rows = U.rows(P.list)
		T.ok(#rows > 0)
		fire(fx.ns, "AUCTION_HOUSE_CLOSED")
		T.eq(#fx.ns.AH.Rows(), 0); T.eq(next(fx.ns.AH.Found()), nil)
		T.eq(#P.list.provided, 0, "the list is empty")
		for _, r in ipairs(rows) do T.eq(r.d, nil, "a released row keeps no data") end
		fx.cleanup()
	end,
}
