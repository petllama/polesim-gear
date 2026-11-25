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

-- A level 21 priest wearing Foamspittle Staff; the AH has Stout Battlehammer (main hand), Orb of Power
-- (off hand) and Necrology Robes: -> fx, panel, U, mace row, orb row, robe row
local function setScanned()
	local fx = setup({ A.result(789, 4000), A.result(4838, 1000), A.result(2292, 20000) }, { level = 21 })
	local ns = fx.ns
	local inst = ns.Score.Instance(ns.Items.Get(1405))
	fx.worn[16] = { inst = inst, score = ns.Score.Score(inst, ns.Context.Get().w, "priest", ns.Equip.ROLE_OF_SLOT[16]) }
	local P = scanned(fx)
	local by = {}
	for _, r in ipairs(fx.U.rows(P.list)) do by[r.d.c.id] = r end
	T.ok(by[789] and by[4838] and by[2292], "mace, orb and robe listed")
	T.eq(by[789].d.partner, by[4838].d)
	return fx, P, fx.U, by[789], by[4838], by[2292]
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
	-- A weapon-set row (under a worn staff: mace + orb): right-click opens the PARTNER's listings, both
	-- ways; the tooltip says so; a row without a partner does nothing on right-click.
	set_right_click_opens_partner = function()
		local fx, P, U, mace, orb, robe = setScanned()
		mace:Click("RightButton")
		T.eq(fx.ahf.selected, orb.d.result, "the orb's browse result")
		T.eq(orb.d.itemKey.itemID, 4838)
		fx.ahf.mode = AuctionHouseFrameDisplayMode.ItemBuy
		orb:Click("RightButton")
		T.eq(fx.ahf.selected, mace.d.result, "and the reverse")
		T.eq(fx.ahf.refreshed, mace.d.itemKey, "already in the item buy view: its listings asked for")
		mace.scripts.OnEnter(mace)
		local lines = table.concat(U.tip.lines, "\n")
		T.ok(lines:find("Right-click: Orb of Power's listings", 1, true), lines)
		T.ok(lines:find("Click: its listings", 1, true), lines)
		fx.ahf.selected = nil
		robe:Click("RightButton")
		T.eq(fx.ahf.selected, nil, "no partner: nothing")
		robe.scripts.OnEnter(robe)
		T.ok(not table.concat(U.tip.lines, "\n"):find("Right-click", 1, true))
		T.eq(fx.log.bought, 0)
		fx.cleanup()
	end,
	-- After a set row's listings open (left-click), a "Next: <partner>" button opens the partner's and
	-- hides; not after a row without a partner; a new scan or the AH closing hides it too.
	set_next_button = function()
		local fx, P, U, mace, orb, robe = setScanned()
		T.eq(U.button(P.frame, "Next: Orb of Power"), nil, "not before a click")
		mace:Click("LeftButton")
		T.eq(fx.ahf.selected, mace.d.result)
		local nb = U.button(P.frame, "Next: Orb of Power")
		T.ok(nb, "Next after the set row's listings")
		T.eq(#U.overflows(P.frame), 0, table.concat(U.overflows(P.frame), "; "))
		nb:Click()
		T.eq(fx.ahf.selected, orb.d.result, "the partner's listings")
		T.eq(nb:IsShown(), false, "hidden after use")
		orb:Click("LeftButton")
		T.ok(nb:IsShown() and U.ownText(nb):find("Next: Stout Battle", 1, true), "from the off hand: the one-hander (cut to fit)")
		robe:Click("LeftButton")
		T.eq(nb:IsShown(), false, "a row without a partner hides it")
		mace:Click("LeftButton")
		T.ok(nb:IsShown())
		U.button(P.frame, "Scan for upgrades"):Click()
		T.eq(nb:IsShown(), false, "a new scan hides it")
		answerAll(fx.ns, fx.log)
		mace = nil
		for _, r in ipairs(U.rows(P.list)) do if r.d.c.id == 789 then mace = r end end
		mace:Click("LeftButton")
		T.ok(nb:IsShown())
		fire(fx.ns, "AUCTION_HOUSE_CLOSED")
		T.eq(nb:IsShown(), false, "the AH closing hides it")
		T.eq(fx.log.bought, 0)
		fx.cleanup()
	end,
	-- The partner's listing is gone (no browse result/item key): a browse search by its name instead,
	-- with a chat note.
	partner_gone_searches_by_name = function()
		local fx, P, U, mace = setScanned()
		local q
		function fx.ahf:SendBrowseQuery(s, lo, hi, filters) q = { s = s, lo = lo, hi = hi, filters = filters } end
		mace.d.partner.result, mace.d.partner.itemKey = nil, nil
		local printed = {}
		fx.ns.Print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end
		mace:Click("RightButton")
		T.ok(q, "a browse search")
		T.eq(q.s, "Orb of Power"); T.eq(q.lo, 0)
		T.ok(table.concat(printed, "\n"):find("Orb of Power", 1, true), table.concat(printed, "\n"))
		T.eq(fx.log.bought, 0)
		fx.cleanup()
	end,
	-- Weapon-set rows read as a pair at a glance: the partner's small icon on the row's icon, the slot
	-- line "Main hand + <partner>" (in the set colour), the Price cell = both items' price with "set of 2"
	-- under it (so Price and Gain/g agree); rows without a partner are unchanged.
	set_rows_marked_as_pairs = function()
		local fx, P, U, mace, orb, robe = setScanned()
		local S = fx.ns.Style
		local robeD = robe.d
		T.eq(mace.d.setPrice, 5000)
		T.eq(mace.price.text, S.Money(5000), "the pair's price")
		T.eq(orb.price.text, S.Money(5000))
		T.ok(mace.priceSub:IsShown() and mace.priceSub.text:find("set of 2", 1, true), "set marker")
		T.eq(mace.value.text, string.format("%+.1f", mace.d.gain / 0.5), "Gain/g agrees with the price shown")
		T.ok(mace.partnerIcon:IsShown(), "partner icon")
		T.eq(mace.partnerIcon.icon.texture, S.IconPath(orb.d.c.inst.icon))
		T.eq(orb.partnerIcon.icon.texture, S.IconPath(mace.d.c.inst.icon))
		local sub = mace.item.sub.text
		T.ok(sub:find("^Main hand") and sub:find("+ Orb of Power", 1, true), sub)
		T.ok(orb.item.sub.text:find("^Off hand") and orb.item.sub.text:find("+ Stout Battlehammer", 1, true), orb.item.sub.text)
		T.ok(sub:find("any suffix", 1, true), "other tags stay")
		-- unpaired row unchanged
		T.eq(robe.price.text, S.Money(20000)); T.eq(robe.priceSub:IsShown(), false)
		T.eq(robe.partnerIcon:IsShown(), false); T.eq(robe.item.sub.text, "Chest")
		T.eq(#U.overflows(P.frame), 0, table.concat(U.overflows(P.frame), "; "))
		-- tooltip: own price, the set line, the gain note
		mace.scripts.OnEnter(mace)
		local lines = table.concat(U.tip.lines, "\n")
		T.ok(lines:find("Auction house: 4000c (cheapest)", 1, true), lines)
		T.ok(lines:find("Weapon set with Orb of Power (1000c): 5000c together", 1, true), lines)
		T.ok(lines:find("with Orb of Power (AH) over your two-hander", 1, true), lines)
		-- Price sort: by the pair's price (5000) before the robe (20000)
		U.button(P.frame, "Price"):Click()
		local rows = U.rows(P.list)
		T.eq(rows[#rows].d.c.id, 2292, "robe last")
		-- a pooled row reused for an unpaired row drops the marks (rows are pooled: the sort moved data)
		fx.ns.AHPanel._fill(mace, robeD)
		T.eq(mace.partnerIcon:IsShown(), false); T.eq(mace.priceSub:IsShown(), false); T.eq(mace.item.sub.text, "Chest")
		fx.cleanup()
	end,
	-- A long partner name is cut with "..." so the slot line fits the name column.
	set_long_partner_name_fits = function()
		local fx, P, U, mace, orb = setScanned()
		orb.d.c.inst.name = "Orb of the Exceedingly Long Mistmantle Name"
		fx.ns.AHPanel._fill(mace, mace.d)
		local sub = mace.item.sub.text
		T.ok(sub:find("+ Orb of the", 1, true) and sub:find("...", 1, true), sub)
		T.eq(#U.overflows(P.frame), 0, table.concat(U.overflows(P.frame), "; "))
		fx.cleanup()
	end,
	-- The Slot dropdown (our own Style.Dropdown, beside the sort buttons): "All slots" (default), then only
	-- the slots in the results, in paper-doll order, each with its count.
	slot_filter_entries = function()
		local fx = setup(RESULTS)
		fx.loadAH()
		local P, U = fx.ns.AHPanel, fx.U
		local dd = P.frame.slot
		T.ok(dd and dd:IsShown(), "the Slot dropdown")
		T.eq(dd.label.text, "All slots", "default")
		local items = U.menu(dd)
		T.eq(#items, 1, "no results: only All"); T.eq(items[1].text, "All slots")
		U.button(P.frame, "Scan for upgrades"):Click()
		answerAll(fx.ns, fx.log)
		items = U.menu(dd)
		local texts = {}
		for i, it in ipairs(items) do texts[i] = it.text end
		T.eq(table.concat(texts, "|"), "All slots|Chest (2)|Main hand (1)")
		T.ok(items[1].isSelected(), "All selected")
		fx.ns.Style.ClosePopup()
		fx.cleanup()
		-- paper-doll order, not gain order
		local fx2, P2, U2 = setScanned()
		texts = {}
		for i, it in ipairs(U2.menu(P2.frame.slot)) do texts[i] = it.text end
		T.eq(table.concat(texts, "|"), "All slots|Chest (1)|Main hand (1)|Off hand (1)")
		fx2.ns.Style.ClosePopup()
		fx2.cleanup()
	end,
	-- Choosing a slot lists only its rows (the sort still applies, indexes from 1, back to the top);
	-- All again lists everything; everything fits.
	slot_filter_filters_and_sorts = function()
		local fx = setup(RESULTS)
		local P, U = scanned(fx), fx.U
		local dd = P.frame.slot
		U.menu(dd)[2].select()
		T.eq(dd.label.text, "Chest (2)")
		local rows = U.rows(P.list)
		T.eq(#rows, 2)
		for i, r in ipairs(rows) do T.eq(r.d.slot.key, "chest"); T.eq(r.d.index, i) end
		T.ok(rows[1].d.gain >= rows[2].d.gain, "biggest gain first")
		T.eq(P.list.retained, nil, "a new filter starts at the top")
		U.button(P.frame, "Price"):Click()
		rows = U.rows(P.list)
		T.eq(#rows, 2); T.ok(rows[1].d.price <= rows[2].d.price, "cheapest first within the slot")
		T.ok(P.list.retained, "re-sorting keeps the scroll position")
		T.eq(#U.overflows(P.frame), 0, table.concat(U.overflows(P.frame), "; "))
		T.ok(U.textWidth("Main hand (999)", 12) <= dd.label.w, "a 3-digit count fits the dropdown")
		U.menu(dd)[1].select()
		T.eq(dd.label.text, "All slots"); T.eq(#U.rows(P.list), 3)
		fx.cleanup()
	end,
	-- The choice stays while the AH is open (a re-scan keeps it), falls back to All when a re-scan finds
	-- nothing for that slot, and resets to All when the AH closes.
	slot_filter_keep_fallback_reset = function()
		local res = { A.result(2292, 20000), A.result(2585, 900), A.result(789, 30000, 12718) }
		local fx = setup(res)
		local P, U = scanned(fx), fx.U
		local dd = P.frame.slot
		U.menu(dd)[3].select()
		T.eq(dd.label.text, "Main hand (1)")
		U.button(P.frame, "Scan for upgrades"):Click()
		T.eq(dd.label.text, "Main hand (0)", "kept while scanning")
		answerAll(fx.ns, fx.log)
		T.eq(dd.label.text, "Main hand (1)", "kept after a re-scan")
		T.eq(#U.rows(P.list), 1); T.eq(U.rows(P.list)[1].d.c.id, 789)
		table.remove(res, 3) -- the mace sold
		U.button(P.frame, "Scan for upgrades"):Click()
		answerAll(fx.ns, fx.log)
		T.eq(dd.label.text, "All slots", "nothing left for that slot: All")
		T.eq(#U.rows(P.list), 2)
		U.menu(dd)[2].select()
		T.eq(#U.rows(P.list), 2)
		fire(fx.ns, "AUCTION_HOUSE_CLOSED")
		T.eq(dd.label.text, "All slots", "the AH closing resets it")
		res[3] = A.result(789, 30000, 12718)
		U.button(P.frame, "Scan for upgrades"):Click()
		answerAll(fx.ns, fx.log)
		T.eq(#U.rows(P.list), 3, "next visit: every slot")
		fx.cleanup()
	end,
	-- Filtered to Main hand, the off-hand partner is not listed, yet "Next: <partner>" still opens it
	-- (the row's partner listing, not a visible row); the Next button and dropdown fit beside the sorts.
	slot_filter_next_with_partner_hidden = function()
		local fx, P, U, mace, orb = setScanned()
		local orbResult = orb.d.result
		orb.d.c.inst.name = "Orb of the Exceedingly Long Mistmantle Name"
		local items = U.menu(P.frame.slot)
		items[3].select()
		local rows = U.rows(P.list)
		T.eq(#rows, 1); T.eq(rows[1].d.c.id, 789)
		rows[1]:Click("LeftButton")
		local nb = P.frame.next
		T.ok(nb:IsShown() and U.ownText(nb):find("Next: Orb of the", 1, true), U.ownText(nb))
		T.eq(#U.overflows(P.frame), 0, table.concat(U.overflows(P.frame), "; "))
		T.ok(nb.tip:find("Exceedingly Long Mistmantle Name", 1, true), "the full name in the tooltip")
		T.ok(U.textWidth(nb.label.text, 12) <= P.NEXT_W - 12, "the cut name fits the button")
		local sx, nx = P.frame.slot.points[1][2], nb.points[1][2]
		T.eq(type(sx), "number", "x of the dropdown")
		T.ok(sx + P.SLOT_W <= nx and nx + P.NEXT_W <= P.W - 8, "dropdown, Next inside the panel")
		nb:Click()
		T.eq(fx.ahf.selected, orbResult, "the partner's listings")
		T.eq(fx.log.bought, 0)
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
