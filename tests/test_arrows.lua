local T = require("t")
local FILES = { "Core.lua", "Data/Weights.lua", "Data/Suffixes.lua", "Data/Items.lua", "Items.lua", "Score.lua", "Equip.lua", "Arrows.lua" }
local WITH_TOOLTIP = { "Core.lua", "Data/Weights.lua", "Data/Suffixes.lua", "Data/Items.lua", "Items.lua", "Score.lua", "Equip.lua",
	"Tooltip.lua", "Arrows.lua" }
local ctx = { cls = "priest", level = 20, w = { int = 1 }, worn = { [1] = { inst = { id = 9, inv = 1 }, score = 5 } } }
local function head(int, rl) return { id = 1, inv = 1, c = 4, sc = 1, cm = 0, rl = rl or 10, stats = { int = int }, armor = 0, dps = 0 } end

-- The addon with Tooltip and Arrows, Context and Live stubbed: -> ns, calls (Live.Instance count by link)
local function live(items)
	local ns = T.addon(WITH_TOOLTIP)
	local calls = {}
	ns.Context = { Get = function() return ctx end }
	ns.Live = { Instance = function(link)
		calls[link] = (calls[link] or 0) + 1
		local v = items[link]
		if v == "pending" then return nil, "pending" end
		return v
	end }
	return ns, calls
end

-- An item button the arrows can mark: -> button (button.arrow: our texture once made)
local function button(fields)
	local b = fields or {}
	b.CreateTexture = function(self)
		local t = { shown = false }
		function t:SetAtlas() end
		function t:SetPoint() end
		function t:SetShown(v) self.shown = v end
		self.arrow = t
		return t
	end
	b.IsShown = b.IsShown or function() return true end
	return b
end
local function arrow(b) return b.arrow ~= nil and b.arrow.shown end
local function login(ns) ns._frame.scripts.OnEvent(ns._frame, "PLAYER_LOGIN") end

return {
	is_upgrade = function()
		local A = T.addon(FILES).Arrows
		T.ok(A.IsUpgrade(head(6), ctx))
		T.ok(not A.IsUpgrade(head(5), ctx), "equal")
		T.ok(not A.IsUpgrade(head(9, 21), ctx), "level 21")
		local mail = head(9); mail.sc = 3
		T.ok(not A.IsUpgrade(mail, ctx), "mail")
	end,
	-- The arrow's verdict comes from the tooltip's per-link result: one Live read and one comparison
	-- per link, shared by hover and arrows, until scores change.
	verdict_shares_the_tooltip_cache = function()
		local ns, calls = live({ up = head(6), down = head(4), later = head(9, 23) })
		T.eq(ns.Arrows.Verdict("up"), true)
		T.eq(ns.Arrows.Verdict("up"), true)
		T.eq(ns.Arrows.Verdict("down"), false)
		T.eq(ns.Arrows.Verdict("later"), false, "needs level 23: a tooltip line, no arrow")
		T.eq(calls.up, 1, "one read per link")
		local hit = ns.Tooltip.Lookup("up", ctx)
		T.ok(hit and hit[2].gain > 0, "the hover path reads the same entry")
		T.eq(calls.up, 1, "the hover path did not read again")
		ns.Fire("SCORES_CHANGED")
		ns.Arrows.Verdict("up")
		T.eq(calls.up, 2, "read again after scores changed")
		T.eq(ns.Arrows.Verdict(nil), false)
	end,
	-- Stats from the shipped table (the client had none yet): the verdict is given, and the item is
	-- waited for, so its data arriving redraws the arrows with the client's stats.
	verdict_from_table_waits = function()
		local W = require("wow")
		local t = head(6); t.fromTable = true
		local ns, calls = live({ ["item:7:0"] = t })
		local n = 0
		ns.Arrows.OnRedraw(function() n = n + 1 end)
		T.eq(ns.Arrows.Verdict("item:7:0"), true)
		ns._frame.scripts.OnEvent(ns._frame, "GET_ITEM_INFO_RECEIVED", 7, true)
		W.flush()
		T.eq(n, 1, "waited for item 7: one redraw")
		ns.Arrows.Verdict("item:7:0")
		T.eq(calls["item:7:0"], 2, "not kept: read again")
	end,
	verdict_pending_read_again = function()
		local ns, calls = live({ wait = "pending" })
		T.eq(ns.Arrows.Verdict("wait"), false)
		T.eq(ns.Arrows.Verdict("wait"), false)
		T.eq(calls.wait, 2)
	end,
	-- Auction browse rows: by item id; a random-suffix item gets none (the row is every suffix).
	verdict_by_id = function()
		local ns = live({})
		local seen
		ns.Arrows.Verdict = function(link) seen = link return true end
		T.eq(ns.Arrows.VerdictByID(6540), false, "Willow Pants: random suffix")
		T.eq(seen, nil)
		T.eq(ns.Arrows.VerdictByID(11288), true)
		T.eq(seen, "item:11288")
	end,
	-- The arrow is our own texture on the button, made once, shown and hidden.
	mark = function()
		local A = T.addon(FILES).Arrows
		local made = 0
		local tex = { shown = false }
		function tex:SetAtlas() end
		function tex:SetPoint() end
		function tex:SetShown(v) self.shown = v end
		local button = { CreateTexture = function() made = made + 1 return tex end }
		A.Mark(button, false)
		T.eq(made, 0, "nothing made for no arrow")
		A.Mark(button, true); A.Mark(button, true)
		T.eq(made, 1); T.eq(tex.shown, true)
		A.Mark(button, false)
		T.eq(tex.shown, false)
	end,
	-- New scores redraw the shown buttons once (not per event); item data redraws only when an arrow
	-- waited for that item.
	redraw_debounced = function()
		local W = require("wow")
		local ns = live({ ["item:7"] = "pending" })
		local n = 0
		ns.Arrows.OnRedraw(function() n = n + 1 end)
		ns.Fire("SCORES_CHANGED"); ns.Fire("SCORES_CHANGED")
		W.flush()
		T.eq(n, 1, "one redraw")
		local function info(id) ns._frame.scripts.OnEvent(ns._frame, "GET_ITEM_INFO_RECEIVED", id, true) end
		info(5)
		W.flush()
		T.eq(n, 1, "no arrow waited for item 5")
		ns.Arrows.Verdict("item:7")
		info(7); info(7)
		W.flush()
		T.eq(n, 2, "item 7 was pending: one redraw")
	end,
	-- The client's bags: every container frame's UpdateItems paints its buttons (no scan of our own).
	client_bags = function()
		local links = { [0] = { [1] = "up", [2] = "down" }, [1] = { [1] = "up" } }
		_G.C_Container = { GetContainerItemLink = function(bag, slot) return links[bag] and links[bag][slot] end }
		local function container(bag, n)
			local f = { items = {}, shown = true }
			for i = 1, n do
				f.items[i] = button({ GetBagID = function() return bag end, GetID = function() return i end })
			end
			function f:EnumerateValidItems() return ipairs(self.items) end
			function f:UpdateItems() end
			function f:IsShown() return self.shown end
			return f
		end
		local bag0, bag1, combined = container(0, 3), container(1, 1), container(0, 2)
		_G.ContainerFrameContainer = { ContainerFrames = { bag0, bag1 } }
		_G.ContainerFrameCombinedBags = combined
		local ns = live({ up = head(6), down = head(4) })
		login(ns)
		bag0:UpdateItems(); combined:UpdateItems()
		T.eq(arrow(bag0.items[1]), true); T.eq(arrow(bag0.items[2]), false); T.eq(arrow(bag0.items[3]), false)
		T.eq(arrow(combined.items[1]), true)
		T.eq(bag1.items[1].arrow, nil, "not painted before its update")
		links[0][1] = "down" -- the item moved: the next update clears the arrow
		bag0:UpdateItems()
		T.eq(arrow(bag0.items[1]), false)
		bag1.shown = false
		links[0][1] = "up"
		ns.Arrows.Redraw()
		T.eq(arrow(bag0.items[1]), true, "a redraw paints the shown bags")
		T.eq(bag1.items[1].arrow, nil, "and not the hidden ones")
		_G.ContainerFrameContainer, _G.ContainerFrameCombinedBags, _G.C_Container = nil, nil, nil
	end,
	-- One link that throws: the other buttons still paint, and its error is reported once per session
	-- (not on every bag update).
	paint_error_isolated_per_button = function()
		local links = { [0] = { "up", "boom", "up" } }
		_G.C_Container = { GetContainerItemLink = function(bag, slot) return links[bag][slot] end }
		local f = { items = {} }
		for i = 1, 3 do f.items[i] = button({ GetBagID = function() return 0 end, GetID = function() return i end }) end
		function f:EnumerateValidItems() return ipairs(self.items) end
		function f:UpdateItems() end
		function f:IsShown() return true end
		_G.ContainerFrameContainer = { ContainerFrames = { f } }
		local ns = live({ up = head(6) })
		local inst = ns.Live.Instance
		ns.Live.Instance = function(link) if link == "boom" then error("bad item") end return inst(link) end
		local errors = {}
		_G.geterrorhandler = function() return function(e) errors[#errors + 1] = e end end
		login(ns)
		f:UpdateItems()
		T.eq(arrow(f.items[1]), true); T.eq(arrow(f.items[3]), true, "painted after the throwing button")
		T.eq(arrow(f.items[2]), false)
		T.eq(#errors, 1)
		T.ok(tostring(errors[1]):find("bad item", 1, true), tostring(errors[1]))
		f:UpdateItems(); ns.Arrows.Redraw()
		T.eq(#errors, 1, "reported once per session")
		_G.ContainerFrameContainer, _G.C_Container = nil, nil
	end,
	-- A button that had an arrow loses it when its verdict later throws (no stale arrow left behind).
	paint_error_clears_existing_arrow = function()
		local ns = live({ up = head(6) })
		local errors = {}
		_G.geterrorhandler = function() return function(e) errors[#errors + 1] = e end end
		local b = button()
		ns.Arrows.Paint(b, "up")
		T.eq(arrow(b), true)
		ns.Arrows.Paint(b, "up", function() error("verdict boom") end)
		T.eq(arrow(b), false, "cleared")
		T.eq(#errors, 1)
	end,
	-- A redraw that throws goes to the error handler (not swallowed); the other redraws still run.
	redraw_errors_reported = function()
		local ns = live({})
		local errors, ran = {}, false
		_G.geterrorhandler = function() return function(e) errors[#errors + 1] = e end end
		ns.Arrows.OnRedraw(function() error("redraw boom") end)
		ns.Arrows.OnRedraw(function() ran = true end)
		ns.Arrows.Redraw()
		T.ok(ran); T.eq(#errors, 1)
		T.ok(tostring(errors[1]):find("redraw boom", 1, true))
		ns.Arrows.Redraw()
		T.eq(#errors, 1, "the same redraw error is reported once per session")
	end,
	-- Bagnon (BagBrother): Item:Update(info) sets self.info; our hook paints after it.
	bagnon = function()
		local updates = 0
		local Item = {}
		function Item:Update(info) self.info = info end
		_G.BagBrother = { Item = Item, Frames = { Update = function() updates = updates + 1 end } }
		local ns = live({ up = head(6), down = head(4) })
		ns._frame.scripts.OnEvent(ns._frame, "ADDON_LOADED", "BagBrother")
		local b = button()
		Item.Update(b, { hyperlink = "up" })
		T.eq(arrow(b), true)
		Item.Update(b, { hyperlink = "down" })
		T.eq(arrow(b), false)
		Item.Update(b, {})
		T.eq(arrow(b), false, "empty slot")
		login(ns) -- hooked once only
		Item.Update(b, { hyperlink = "up" })
		ns.Arrows.Redraw()
		T.eq(updates, 1, "a redraw asks Bagnon to update its frames")
		_G.BagBrother = nil
	end,
	-- Bagnon showing another character's bags (BagBrother: the frame's owner, Item:GetOwner(), is
	-- offline): its items are not this character's, so no arrows there (and none left from the player's
	-- view). The player's own bank or vault viewed away from the banker is cached too (Item:IsCached()),
	-- but its owner is the player: those keep their arrows.
	bagnon_skips_other_characters = function()
		local Item = {}
		function Item:Update(info) self.info = info end
		_G.BagBrother = { Item = Item, Frames = { Update = function() end } }
		local ns = live({ up = head(6) })
		ns._frame.scripts.OnEvent(ns._frame, "ADDON_LOADED", "BagBrother")
		local owner = { offline = false }
		local b = button({ GetOwner = function() return owner end, IsCached = function() return true end })
		Item.Update(b, { hyperlink = "up" })
		T.eq(arrow(b), true, "the player's own bank, viewed away from the banker")
		owner = { offline = true }
		Item.Update(b, { hyperlink = "up" })
		T.eq(arrow(b), false, "an alt's bags: no arrow")
		b.GetOwner = function() error("no frame") end
		Item.Update(b, { hyperlink = "up" })
		T.eq(arrow(b), true, "an owner that cannot be read counts as the player's")
		_G.BagBrother = nil
	end,
	-- Loot rolls: each GroupLootFrame<i> shows one rollID; its icon gets the arrow when shown.
	loot_roll = function()
		local links = { [11] = "up", [12] = "down" }
		_G.GetLootRollItemLink = function(id) return links[id] end
		local frames = {}
		for i = 1, 4 do
			local f = { IconFrame = button(), shown = false }
			function f:HookScript(k, fn) self[k] = fn end
			function f:IsShown() return self.shown end
			frames[i] = f
			_G["GroupLootFrame" .. i] = f
		end
		local ns = live({ up = head(6), down = head(4) })
		login(ns)
		frames[1].rollID, frames[1].shown = 11, true
		frames[1]:OnShow()
		T.eq(arrow(frames[1].IconFrame), true)
		frames[2].rollID, frames[2].shown = 12, true
		frames[2]:OnShow()
		T.eq(arrow(frames[2].IconFrame), false)
		frames[1].rollID = 12 -- reused for another roll
		frames[1]:OnShow()
		T.eq(arrow(frames[1].IconFrame), false)
		frames[1].rollID = 11
		ns.Arrows.Redraw()
		T.eq(arrow(frames[1].IconFrame), true, "a redraw paints the shown roll frames")
		for i = 1, 4 do _G["GroupLootFrame" .. i] = nil end
		_G.GetLootRollItemLink = nil
	end,
	-- The merchant: the shown page's buttons; none on the buyback tab.
	merchant = function()
		_G.MERCHANT_ITEMS_PER_PAGE = 10
		local links = { [1] = "down", [12] = "up" }
		_G.GetMerchantItemLink = function(i) return links[i] end
		_G.MerchantFrame = { page = 2, selectedTab = 1, IsShown = function() return true end }
		for i = 1, 12 do _G["MerchantItem" .. i .. "ItemButton"] = button() end
		_G.MerchantFrame_UpdateMerchantInfo = function() end
		_G.MerchantFrame_UpdateBuybackInfo = function() end
		local ns = live({ up = head(6), down = head(4) })
		local b2 = _G.MerchantItem2ItemButton
		MerchantFrame_UpdateMerchantInfo()
		T.eq(arrow(b2), true, "page 2, second item = index 12")
		MerchantFrame.page = 1
		MerchantFrame_UpdateMerchantInfo()
		T.eq(arrow(b2), false)
		MerchantFrame.page = 2
		ns.Arrows.Redraw()
		T.eq(arrow(b2), true)
		MerchantFrame.selectedTab = 2
		MerchantFrame_UpdateBuybackInfo()
		T.eq(arrow(b2), false, "buyback tab")
		for i = 1, 12 do _G["MerchantItem" .. i .. "ItemButton"] = nil end
		_G.MerchantFrame, _G.MerchantFrame_UpdateMerchantInfo, _G.MerchantFrame_UpdateBuybackInfo = nil, nil, nil
		_G.GetMerchantItemLink, _G.MERCHANT_ITEMS_PER_PAGE = nil, nil
	end,
	-- Mail: the inbox rows' first item (GetInboxHeaderInfo's 15th value) and the open letter's attachments.
	mail = function()
		_G.INBOXITEMS_TO_DISPLAY, _G.ATTACHMENTS_MAX_RECEIVE = 7, 16
		local first = { [8] = "up", [9] = "down" }
		_G.GetInboxHeaderInfo = function(i) return nil, nil, nil, nil, 0, 0, 1, 1, false, nil, nil, nil, nil, 1, first[i] end
		_G.GetInboxItemLink = function(mail, i) return mail == 8 and ({ "down", "up" })[i] or nil end
		for i = 1, 7 do _G["MailItem" .. i .. "Button"] = button() end
		for i = 1, 16 do _G["OpenMailAttachmentButton" .. i] = button({ IsShown = function() return i <= 2 end }) end
		_G.InboxFrame = { pageNum = 2, openMailID = 8, IsShown = function() return true end, Update = function() end }
		_G.OpenMailFrame = { IsShown = function() return true end, Update = function() end }
		local ns = live({ up = head(6), down = head(4) })
		ns._frame.scripts.OnEvent(ns._frame, "ADDON_LOADED", "Blizzard_MailFrame")
		InboxFrame:Update()
		T.eq(arrow(MailItem1Button), true, "page 2, first row = mail 8")
		T.eq(arrow(MailItem2Button), false)
		OpenMailFrame:Update()
		T.eq(arrow(OpenMailAttachmentButton1), false)
		T.eq(arrow(OpenMailAttachmentButton2), true)
		T.eq(OpenMailAttachmentButton3.arrow, nil)
		login(ns) -- hooked once only
		InboxFrame.pageNum = 1
		InboxFrame:Update()
		T.eq(arrow(MailItem1Button), false)
		for i = 1, 7 do _G["MailItem" .. i .. "Button"] = nil end
		for i = 1, 16 do _G["OpenMailAttachmentButton" .. i] = nil end
		_G.InboxFrame, _G.OpenMailFrame, _G.GetInboxHeaderInfo, _G.GetInboxItemLink = nil, nil, nil, nil
	end,
	-- Auction house: list rows are ScrollBox frames whose element data is an index into the list's
	-- getEntry (row.rowData may still be the previous entry when our callback runs).
	auction_house = function()
		local function list(entries)
			local box = { frames = {} }
			function box:GetView() return true end
			function box:ForEachFrame(fn) for _, f in ipairs(self.frames) do fn(f, f.index) end end
			return { ScrollBox = box, getEntry = function(i) return entries[i] end }
		end
		local browse = list({ { itemKey = { itemID = 11288 } }, { itemKey = { itemID = 6540 } } })
		local buy = list({ { itemLink = "down" }, { itemLink = "up" } })
		_G.AuctionHouseFrame = { BrowseResultsFrame = { ItemList = browse }, ItemBuyFrame = { ItemList = buy },
			IsShown = function() return true end }
		_G.ScrollUtil = { AddInitializedFrameCallback = function(box, fn, owner, existing)
			T.ok(not existing, "no iterateExisting: the view may not exist yet")
			box.init = function(row, data) row.index = data box.frames[#box.frames + 1] = row fn(owner, row, data) end
		end }
		local ns = live({ up = head(6), down = head(4), ["item:11288"] = head(6), ["item:6540"] = head(9) })
		ns._frame.scripts.OnEvent(ns._frame, "ADDON_LOADED", "Blizzard_AuctionHouseUI")
		local r1, r2 = button({ rowData = { itemKey = { itemID = 6540 } } }), button()
		browse.ScrollBox.init(r1, 1); browse.ScrollBox.init(r2, 2)
		T.eq(arrow(r1), true, "Greater Magic Wand row (stale rowData ignored)")
		T.eq(r2.arrow, nil, "random-suffix item: no arrow on the browse row")
		local b1, b2 = button(), button()
		buy.ScrollBox.init(b1, 1); buy.ScrollBox.init(b2, 2)
		T.eq(b1.arrow, nil); T.eq(arrow(b2), true)
		r1.arrow.shown = false
		ns.Arrows.Redraw()
		T.eq(arrow(r1), true, "a redraw repaints the shown rows")
		buy.ScrollBox.init(b2, 1) -- the row scrolled to another auction, not an upgrade
		T.eq(arrow(b2), false, "a reused row loses its arrow")
		browse.ScrollBox.init(r1, 2)
		T.eq(arrow(r1), false, "a reused browse row on a random-suffix item loses its arrow")
		_G.AuctionHouseFrame, _G.ScrollUtil = nil, nil
	end,
}
