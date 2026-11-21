-- Upgrade arrows on item buttons: the client's bags and Bagnon, loot rolls, the merchant, mail and the
-- auction house. An arrow = the character can wear it now and it scores above what is worn. The verdict
-- is read from the tooltip's per-link result (Tooltip.Lookup: one Live read and one comparison per link
-- until scores change). Only our own texture is added to the buttons (nothing written into them, no
-- protected calls), from hooks that run after the client's own updates: no scanning per frame.
local ADDON, ns = ...
local Arrows = {}
ns.Arrows = Arrows

-- inst, ctx, cmp (Equip.Compare, optional) -> true when it is an upgrade the character can wear now
function Arrows.IsUpgrade(inst, ctx, cmp)
	if not ns.Equip.CanUse(inst, ctx.cls, ctx.level) or (inst.rl or 0) > ctx.level then return false end
	cmp = cmp or ns.Equip.Compare(inst, ctx.w, ctx.cls, ctx.worn, false)
	return cmp ~= nil and not cmp.equipped and cmp.gain > 1e-6
end

local waiting = {} -- item id -> true: a verdict waited for the client's item data
function Arrows.Verdict(link)
	local ctx = ns.Context.Get()
	if not (ctx and type(link) == "string") then return false end
	local hit, wait = ns.Tooltip.Lookup(link, ctx)
	if wait then
		local id = tonumber(link:match("item:(%d+)"))
		if id then waiting[id] = true end
	end
	if not hit then return false end
	return Arrows.IsUpgrade(hit[1], ctx, hit[2])
end

-- By item id (auction house browse rows: no link). Random-suffix items get no arrow there: the row
-- stands for every suffix; each auction's own row in the item list has its link.
function Arrows.VerdictByID(id)
	local rec = ns.Items.Get(id)
	if rec and #rec.sfx > 0 then return false end
	return Arrows.Verdict("item:" .. id)
end

local marks = setmetatable({}, { __mode = "k" })
-- Our arrow sits top-right (Polestar's own sits top-left, so both stay readable if the player keeps both).
function Arrows.Mark(button, show)
	local t = marks[button]
	if show and not t then
		t = button:CreateTexture(nil, "OVERLAY", nil, 4)
		t:SetAtlas("bags-greenarrow", true)
		t:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
		marks[button] = t
	end
	if t then t:SetShown(show and true or false) end
end

-- Paint one button for one link (verdict: Arrows.Verdict, or another function of the link). An error
-- is trapped per button, so the other buttons still paint; it is reported once per link per session
-- (shared with the tooltip's reporter), and the button keeps no arrow.
local function paint(button, link, verdict)
	Arrows.Mark(button, link and (verdict or Arrows.Verdict)(link))
end
function Arrows.Paint(button, link, verdict)
	local ok, err = pcall(paint, button, link, verdict)
	if ok then return end
	pcall(Arrows.Mark, button, false)
	ns.ReportOnce(link or "?", err)
end

local redraws = {}
function Arrows.OnRedraw(fn) redraws[#redraws + 1] = fn end
function Arrows.Redraw()
	for _, fn in ipairs(redraws) do
		local ok, err = pcall(fn)
		if not ok then geterrorhandler()(err) end
	end
end

-- One redraw shortly after a burst of changes.
local queued = false
local function schedule()
	if queued then return end
	queued = true
	C_Timer.After(0.2, function()
		queued = false
		Arrows.Redraw()
	end)
end

ns.On("SCORES_CHANGED", function()
	waiting = {}
	schedule()
end)
ns.RegisterEvent("GET_ITEM_INFO_RECEIVED", function(itemID)
	if itemID and waiting[itemID] then
		waiting[itemID] = nil
		schedule()
	end
end)

-- The client's bags (Blizzard_UIPanels_Game Mainline ContainerFrame.lua, which Forever loads): each
-- frame of ContainerFrameContainer.ContainerFrames and ContainerFrameCombinedBags carries
-- ContainerFrameMixin's functions (XML mixin), and Update -> AddItemsForRefresh calls self:UpdateItems()
-- on every bag change: hook UpdateItems on the frames.
local hooked = {}
local function paintContainer(frame)
	for _, button in frame:EnumerateValidItems() do
		Arrows.Paint(button, C_Container.GetContainerItemLink(button:GetBagID(), button:GetID()))
	end
end
local function containerFrames()
	local out = {}
	local list = ContainerFrameContainer and ContainerFrameContainer.ContainerFrames
	for _, f in ipairs(type(list) == "table" and list or {}) do out[#out + 1] = f end
	if ContainerFrameCombinedBags then out[#out + 1] = ContainerFrameCombinedBags end
	return out
end
local function hookBags()
	for _, f in ipairs(containerFrames()) do
		if not hooked[f] and type(f.UpdateItems) == "function" then
			hooksecurefunc(f, "UpdateItems", paintContainer)
			hooked[f] = true
		end
	end
end
Arrows.OnRedraw(function()
	for _, f in ipairs(containerFrames()) do
		if hooked[f] and f:IsShown() then paintContainer(f) end
	end
end)

-- Bagnon (BagBrother 12.1.12: Poncho classes, methods looked up at call time; ContainerItem:Update
-- calls Item:Update through Super, which sets self.info). A cached view (Item:IsCached(): the frame's
-- owner is offline, i.e. another character's bags; Frame:IsCached = GetOwner().offline) gets no arrows:
-- its items are not this character's.
local function cachedView(item)
	if type(item.IsCached) ~= "function" then return false end
	local ok, cached = pcall(item.IsCached, item)
	return ok and cached and true or false
end
local function hookBagnon()
	local B = _G.BagBrother
	local Item = type(B) == "table" and B.Item
	if hooked.bagnon or not (type(Item) == "table" and type(Item.Update) == "function") then return end
	hooksecurefunc(Item, "Update", function(self)
		local link = not cachedView(self) and type(self.info) == "table" and self.info.hyperlink
		Arrows.Paint(self, link or nil)
	end)
	hooked.bagnon = true
end
Arrows.OnRedraw(function()
	local B = _G.BagBrother
	if hooked.bagnon and type(B.Frames) == "table" and B.Frames.Update then B.Frames:Update() end
end)

ns.RegisterEvent("PLAYER_LOGIN", function()
	hookBags()
	hookBagnon()
end)
ns.RegisterEvent("ADDON_LOADED", function(name)
	if name == "BagBrother" or name == "Bagnon" then hookBagnon() end
end)

-- Group loot rolls (Mainline GroupLootFrame.lua/.xml, GroupLootFrame1..4): GroupLootContainer_OpenNewFrame
-- sets frame.rollID, then shows the frame; the item icon is the frame's IconFrame button.
local function paintRoll(frame)
	local link = frame.rollID and GetLootRollItemLink(frame.rollID)
	if frame.IconFrame then Arrows.Paint(frame.IconFrame, link or nil) end
end
ns.RegisterEvent("PLAYER_LOGIN", function()
	if hooked.rolls then return end
	for i = 1, 4 do
		local f = _G["GroupLootFrame" .. i]
		if f and f.HookScript then f:HookScript("OnShow", paintRoll) end
	end
	hooked.rolls = true
end)
Arrows.OnRedraw(function()
	if not hooked.rolls then return end
	for i = 1, 4 do
		local f = _G["GroupLootFrame" .. i]
		if f and f:IsShown() then paintRoll(f) end
	end
end)

-- The merchant (Mainline MerchantFrame.lua): MerchantItem<i>ItemButton for the shown page
-- (MERCHANT_ITEMS_PER_PAGE). The buyback tab (selectedTab 2, MerchantFrame_UpdateBuybackInfo) reuses
-- the same buttons: no arrows there.
local function paintMerchant()
	if not (MerchantFrame and MerchantFrame:IsShown()) then return end
	local per = MERCHANT_ITEMS_PER_PAGE or 10
	for i = 1, per do
		local b = _G["MerchantItem" .. i .. "ItemButton"]
		if b then
			local index = ((MerchantFrame.page or 1) - 1) * per + i
			Arrows.Paint(b, MerchantFrame.selectedTab == 1 and b:IsShown() and GetMerchantItemLink(index) or nil)
		end
	end
end
if MerchantFrame_UpdateMerchantInfo then hooksecurefunc("MerchantFrame_UpdateMerchantInfo", paintMerchant) end
if MerchantFrame_UpdateBuybackInfo then hooksecurefunc("MerchantFrame_UpdateBuybackInfo", paintMerchant) end
Arrows.OnRedraw(paintMerchant)

-- Mail (Blizzard_MailFrame, loaded at startup): the open letter's attachments
-- (OpenMailAttachmentButton<i>, GetInboxItemLink), and each inbox row's first item (MailItem<i>Button,
-- the 15th value of GetInboxHeaderInfo). OpenMailFrame:Update() and InboxFrame:Update() are
-- OpenMailMixin/InboxMixin methods on the frames.
local function paintOpenMail()
	if not (OpenMailFrame and InboxFrame) then return end
	local id = OpenMailFrame:IsShown() and InboxFrame.openMailID
	if id == 0 then id = nil end
	for i = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
		local b = _G["OpenMailAttachmentButton" .. i]
		if b then
			Arrows.Paint(b, id and b:IsShown() and GetInboxItemLink(id, i) or nil)
		end
	end
end
local function paintInbox()
	if not (InboxFrame and InboxFrame:IsShown()) then return end
	local per = INBOXITEMS_TO_DISPLAY or 7
	for i = 1, per do
		local b = _G["MailItem" .. i .. "Button"]
		if b then
			local index = ((InboxFrame.pageNum or 1) - 1) * per + i
			Arrows.Paint(b, b:IsShown() and select(15, GetInboxHeaderInfo(index)) or nil)
		end
	end
end
local function hookMail()
	if hooked.mail or not (OpenMailFrame and InboxFrame and OpenMailFrame.Update and InboxFrame.Update) then return end
	hooksecurefunc(OpenMailFrame, "Update", paintOpenMail)
	hooksecurefunc(InboxFrame, "Update", paintInbox)
	hooked.mail = true
end
Arrows.OnRedraw(function()
	if not hooked.mail then return end
	paintOpenMail()
	paintInbox()
end)

-- Auction house (Blizzard_AuctionHouseUI, load on demand): rows are ScrollBox frames whose element data
-- is an index into the list's getEntry (AuctionHouseItemListMixin: CreateIndexRangeDataProvider; the
-- table builder sets row.rowData from it in its own callback, which may run after ours). Browse rows
-- carry an itemKey, the item buy list one auction (with its link) per row.
-- Each list: its frame, and entry -> the item (id or link) and the verdict for it.
local AH_LISTS = {
	{ "BrowseResultsFrame", function(d)
		local key = type(d) == "table" and d.itemKey
		return key and key.itemID, Arrows.VerdictByID
	end },
	{ "ItemBuyFrame", function(d) return type(d) == "table" and d.itemLink, Arrows.Verdict end },
}
local function paintRow(list, item, row, data)
	local d = type(data) == "number" and type(list.getEntry) == "function" and list.getEntry(data) or row.rowData
	local key, verdict = item(d)
	Arrows.Paint(row, key or nil, verdict)
end
local function hookAuctionHouse()
	local AH = AuctionHouseFrame
	if hooked.ah or not (AH and AH.BrowseResultsFrame and AH.ItemBuyFrame and ScrollUtil) then return end
	for _, l in ipairs(AH_LISTS) do
		local list, item = AH[l[1]].ItemList, l[2]
		-- No iterateExisting: it calls ScrollBox:ForEachFrame, which needs the view the list makes on Init.
		ScrollUtil.AddInitializedFrameCallback(list.ScrollBox, function(_, row, data)
			paintRow(list, item, row, data)
		end, Arrows)
	end
	hooked.ah = true
end
Arrows.OnRedraw(function()
	local AH = AuctionHouseFrame
	if not (hooked.ah and AH:IsShown()) then return end
	for _, l in ipairs(AH_LISTS) do
		local list, item = AH[l[1]].ItemList, l[2]
		local box = list.ScrollBox
		if box:GetView() then
			box:ForEachFrame(function(row, data) paintRow(list, item, row, data) end)
		end
	end
end)

ns.RegisterEvent("PLAYER_LOGIN", function()
	hookMail()
	hookAuctionHouse()
end)
ns.RegisterEvent("ADDON_LOADED", function(name)
	if name == "Blizzard_MailFrame" then hookMail() end
	if name == "Blizzard_AuctionHouseUI" then hookAuctionHouse() end
end)
