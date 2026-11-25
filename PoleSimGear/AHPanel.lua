-- The "PoleSim upgrades" panel docked to the right of the auction house (Blizzard_AuctionHouseUI, load
-- on demand: made when it loads). A small button on the AH frame shows and hides it (kept: the
-- ahPanel setting). Scan for upgrades (AH.lua) and the upgrades it found: icon, name with suffix, slot,
-- "lvl N" (look ahead), gain, cheapest price, gain per gold; sorts Gain / Value / Price; hover: the
-- game's item tooltip with PoleSim's lines; click: the item's listings in the AH (buying is yours).
-- Weapon-set rows (one-hander + off hand under a worn two-hander): right-click opens the PARTNER's
-- listings, and after a set row's listings a "Next: <partner>" button does (then hides). They read as a
-- pair at a glance: the partner's small icon on the row's icon, "Main hand + <partner>" in the set
-- colour, and the Price cell shows both items' price ("set of 2"), the price Gain/g uses.
local ADDON, ns = ...
local P = {}
ns.AHPanel = P
local S = ns.Style
local C = S.C
local format = string.format

P.W = 500
P.ROW_H = 30
-- row columns (x from the row's left; the row is P.W - 20 wide)
local COL = { star = 4, item = 22, nameW = 210, gain = 262, gainW = 48, price = 314, priceW = 100, value = 418, valueW = 56 }
P.COL = COL
P.SORTS = { { "gain", "Gain", "Biggest gain first" }, { "value", "Value", "Most gain per gold first" },
	{ "price", "Price", "Cheapest first" } }
local sortBy = "gain"

local function ctxNow() return ns.Context.Get() end

-- the weapon-set row whose listings were opened last: the "Next: <partner>" button opens its partner's
P.nextFor = nil
local function partnerName(r) return r.partner and r.partner.c and r.partner.c.inst and r.partner.c.inst.name or "?" end

-- The Gear Plan's item for the row's slot (your pick, else the suggestion): "plan" on the row.
local function isPlan(r)
	local ctx = ctxNow()
	if not (ctx and r.slot) then return false end
	local pick = ns.Plan.Get(ctx.spec, r.slot.key)
	if pick then return pick == r.key end
	local ok, sk = pcall(ns.Window.SuggestedKey, r.slot.key)
	return ok and sk == r.key or false
end

-- the weapon-set colour (partner name, "set of 2", the partner icon's frame)
P.SET = S.hex("6fd6c4")

-- The slot line: slot, "+ <partner>" (set rows; the name cut with "..." to fit the column), tags.
local function slotLine(row, r)
	local slot = r.slot and (r.slot.short or r.slot.label) or ""
	local tags = ""
	if (r.at or 0) > 0 then tags = tags .. "  " .. S.Colour(C.gold) .. "lvl " .. r.at .. "|r" end
	if r.anySuffix then tags = tags .. "  " .. S.Colour(C.label) .. "any suffix|r" end
	if isPlan(r) then tags = tags .. "  " .. S.Colour(C.pick) .. "plan|r" end
	if not r.partner then return slot .. tags end
	local name = partnerName(r)
	local function line(n) return slot .. " " .. S.Colour(P.SET) .. "+ " .. n .. "|r" .. tags end
	local fs, text = row.item.sub, line(name)
	fs:SetText(text)
	local cut = #name
	while cut > 4 and (fs:GetStringWidth() or 0) > COL.nameW do
		cut = cut - 1
		text = line(name:sub(1, cut):gsub("%s+$", "") .. "...")
		fs:SetText(text)
	end
	return text
end

local function fill(row, r)
	S.RowBg(row, row.index)
	local sub = slotLine(row, r)
	row.item:Set(r.c.inst, sub)
	row.gain:SetText(S.Signed(r.gain))
	local p = r.partner
	row.price:SetText(S.Money(ns.AH.RowPrice(r)))
	S.Place(row.price, "LEFT", COL.price, p and 6 or 0, COL.priceW)
	row.priceSub:SetShown(p ~= nil)
	if p then
		row.partnerIcon.icon:SetTexture(S.IconPath(p.c and p.c.inst and p.c.inst.icon))
	end
	row.partnerIcon:SetShown(p ~= nil)
	row.value:SetText(format("%+.1f", r.value))
	row.star:Set(ns.Wishlist.Has(r.c.inst))
end
P._fill = fill

-- The row tooltip: the game's item tooltip (with the row's suffix), PoleSim's lines (Window.RowLines),
-- then the auction house's: price, gain per gold, the weapon set's partner, any-suffix rows.
function P.Tooltip(row)
	local r = row.d
	local ctx = ctxNow()
	if not (r and ctx) then return end
	local band = r.at and ns.Context.At(r.at) or ctx
	local extra = { "Auction house: " .. S.Money(r.price) .. (r.quantity and r.quantity > 1 and format(" (cheapest of %d)", r.quantity) or " (cheapest)") }
	if r.partner then
		extra[#extra + 1] = format("Weapon set with %s (%s): %s together", r.partner.c.inst.name or "?", S.Money(r.partner.price), S.Money(r.setPrice or r.price))
	end
	extra[#extra + 1] = format("Gain per gold: %+.2f", r.value)
	if r.anySuffix then
		extra[#extra + 1] = format("The browse list shows every suffix of this item as one row: scored with the best (%s); the weakest (%s) gains %s. Its listings show each one's suffix.",
			r.anySuffix.best or "?", r.anySuffix.worstName or "?", S.Signed(r.anySuffix.worst or 0))
	end
	local hint = "Click: its listings in the auction house, cheapest first (buying is yours)"
	if r.partner then hint = hint .. "\nRight-click: " .. partnerName(r) .. "'s listings" end
	ns.Window.ItemTip(row, r.c.inst, function()
		ns.Window.RowLines(r, ctx, band, hint, extra)
	end)
end

-- Left: the row's listings (a set row then offers "Next: <partner>"); right: a set row's partner's.
function P.Open(r)
	local ok, why = ns.AH.Select(r)
	if not ok and why then ns.Print(why) end
	P.SetNext(ok and r and r.partner and r or nil)
end
function P.OpenPartner(r)
	if not (r and r.partner) then return end
	local ok, why = ns.AH.SelectPartner(r)
	if why then ns.Print(why) end
	if ok then P.SetNext(nil) end
end
function P.SetNext(r)
	P.nextFor = r
	local b = P.frame and P.frame.next
	if not b then return end
	if r then
		b.label:SetText("Next: " .. partnerName(r))
		b.tip = "The other half of the weapon set: " .. partnerName(r) .. "'s listings"
	end
	b:SetShown(r ~= nil)
end

local function make(row)
	row.made = true
	row:SetHeight(P.ROW_H)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.gain = S.Text(row, 12, C.green)
	row.gain:SetJustifyH("RIGHT")
	S.Place(row.gain, "LEFT", COL.gain, 0, COL.gainW)
	row.star = S.Star(row, function() if row.d then ns.Wishlist.Toggle(row.d.c.inst) end end)
	row.star:SetPoint("LEFT", COL.star, 0)
	row.item = S.ItemCell(row, 22, COL.nameW)
	row.item:SetPoint("LEFT", COL.item, 0)
	-- a weapon set's partner: its small icon over the row icon's bottom-right corner, framed in the set colour
	local pi = CreateFrame("Frame", nil, row.item)
	pi:SetSize(14, 14)
	pi:SetPoint("CENTER", row.item.icon, "BOTTOMRIGHT", -3, 3)
	if pi.SetFrameLevel and row.item.GetFrameLevel then pi:SetFrameLevel((row.item:GetFrameLevel() or 0) + 2) end
	pi.bg = S.Fill(pi, C.body)
	pi.icon = pi:CreateTexture(nil, "ARTWORK")
	pi.icon:SetPoint("TOPLEFT", 1, -1)
	pi.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	pi.border = S.Border(pi, P.SET)
	pi:Hide()
	row.partnerIcon = pi
	row.price = S.Text(row, 11, C.text)
	row.price:SetJustifyH("RIGHT")
	S.Place(row.price, "LEFT", COL.price, 0, COL.priceW)
	row.priceSub = S.Text(row, 9, P.SET)
	row.priceSub:SetJustifyH("RIGHT")
	S.Place(row.priceSub, "LEFT", COL.price, -8, COL.priceW)
	row.priceSub:SetText("set of 2")
	row.priceSub:Hide()
	row.value = S.Text(row, 11, C.dim)
	row.value:SetJustifyH("RIGHT")
	S.Place(row.value, "LEFT", COL.value, 0, COL.valueW)
	row:SetScript("OnEnter", function(self) S.Hover(self, true) P.Tooltip(self) end)
	row:SetScript("OnLeave", function(self) S.Hover(self, false) GameTooltip_Hide() end)
	row:SetScript("OnClick", function(self, button)
		if button == "RightButton" then return P.OpenPartner(self.d) end
		P.Open(self.d)
	end)
end

local function init(row, d)
	if not row.made then make(row) end
	row.d = d
	row.index = d.index
	fill(row, d)
end

-- The panel's status line: the scan's, else what to do.
function P.StatusText()
	local s = ns.AH.Status()
	if s then return s end
	local ctx = ctxNow()
	if not ctx then return "No weights for this character." end
	local ahead = ns.Options.View().ahead
	return format("Gear you can wear up to level %d (look ahead %d)", math.min(60, ctx.level + ahead), ahead)
end

function P.Refresh()
	local f = P.frame
	if not (f and f:IsShown()) then return end
	local scanning = ns.AH.Scanning()
	f.scan.label:SetText(scanning and "Cancel" or "Scan for upgrades")
	f.scan.tip = scanning and "Stop the scan (what it found so far stays)"
		or "Search the auction house for gear you can wear (a few searches, one at a time); upgrades are listed here"
	f.status:SetText(P.StatusText())
	for _, b in ipairs(f.sorts) do S.SetColours(b, b.key == sortBy and S.TAB_ON or S.TAB) end
	local list = ns.AH.Sort(ns.AH.Rows(), sortBy)
	for i, r in ipairs(list) do r.index = i end
	S.SetList(P.list, list)
	f.empty:SetShown(#list == 0 and not scanning and ns.AH.Status() ~= nil)
end

function P.SetSort(by)
	sortBy = by
	P.Refresh()
end

local function create(ahf)
	local f = CreateFrame("Frame", "PoleSimGearAHPanel", ahf)
	P.frame = f
	f:SetPoint("TOPLEFT", ahf, "TOPRIGHT", 2, -24)
	f:SetPoint("BOTTOMLEFT", ahf, "BOTTOMRIGHT", 2, 0)
	f:SetWidth(P.W)
	f:EnableMouse(true)
	f.bg = S.Fill(f, C.body)
	f.border = S.Border(f, C.border)
	f.title = S.Text(f, 14, C.title)
	f.title:SetPoint("TOPLEFT", 10, -8)
	f.title:SetText("PoleSim upgrades")
	f.scan = S.Button(f, "Scan for upgrades", 140, 22, function()
		if ns.AH.Scanning() then return ns.AH.Cancel() end
		P.SetNext(nil)
		local ok, why = ns.AH.Scan()
		if not ok and why then ns.Print(why) end
		P.Refresh()
	end, S.ACTION)
	f.scan:SetPoint("TOPLEFT", 10, -30)
	f.status = S.Text(f, 11, C.label)
	f.status:SetPoint("TOPLEFT", 158, -35)
	f.status:SetWidth(P.W - 168)
	f.sorts = {}
	local sl = S.Text(f, 11, C.label)
	sl:SetPoint("TOPLEFT", 10, -64)
	sl:SetText("Sort")
	for i, s in ipairs(P.SORTS) do
		local b = S.Button(f, s[2], 60, 20, function() P.SetSort(s[1]) end)
		b.key, b.tip = s[1], s[3]
		b:SetPoint("TOPLEFT", 44 + (i - 1) * 64, -60)
		f.sorts[i] = b
	end
	f.next = S.Button(f, "", P.W - 254, 20, function() if P.nextFor then P.OpenPartner(P.nextFor) end end, S.ACTION)
	f.next:SetPoint("TOPLEFT", 244, -60)
	f.next:Hide()
	local head = CreateFrame("Frame", nil, f)
	head:SetPoint("TOPLEFT", 4, -88)
	head:SetSize(P.W - 18, 20)
	S.Fill(head, C.head)
	for _, h in ipairs({ { "Item", COL.item, 120 }, { "Gain", COL.gain, COL.gainW, "RIGHT" }, { "Price", COL.price, COL.priceW, "RIGHT" },
		{ "Gain/g", COL.value, COL.valueW, "RIGHT" } }) do
		local t = S.Text(head, 11, C.headText)
		if h[4] then t:SetJustifyH(h[4]) end
		S.Place(t, "LEFT", h[2], 0, h[3])
		t:SetText(h[1])
	end
	P.list = S.List(f, 4, -108, P.W - 8, 400, P.ROW_H, init)
	f.empty = S.Text(f, 12, C.label)
	f.empty:SetPoint("TOPLEFT", 12, -116)
	f.empty:SetWidth(P.W - 24)
	f.empty:SetText("No upgrades for sale right now.")
	f:SetScript("OnShow", P.Refresh)
	f:SetScript("OnHide", function() ns.Window.ReleaseItemTip() P.SetNext(nil) end)
	-- the list fills the panel's height (the AH frame's)
	f:SetScript("OnSizeChanged", function(self, w, h) S.PlaceList(P.list, 4, -108, P.W - 8, math.max(60, (h or 0) - 114)) end)
	local h = ahf.GetHeight and ahf:GetHeight() or 0
	if h and h > 0 then S.PlaceList(P.list, 4, -108, P.W - 8, math.max(60, h - 24 - 114)) end
	f:SetShown(ns.Options.Get("ahPanel") ~= false)
	return f
end

-- On the AH frame: the toggle button (above the panel's top-left corner, outside Blizzard's frame) and
-- the panel. Once per session (the AH UI loads once).
function P.Attach()
	local ahf = _G.AuctionHouseFrame
	if P.button or not (ahf and ns.Context.ClassKey()) then return end
	local b = S.Button(ahf, "PoleSim upgrades", 130, 22, function()
		local on = not P.frame:IsShown()
		ns.Options.Set("ahPanel", on)
		P.frame:SetShown(on)
	end, S.ACTION)
	b:SetPoint("TOPLEFT", ahf, "TOPRIGHT", 2, 0)
	b.tip = "PoleSim Gear: show or hide the upgrades panel"
	P.button = b
	create(ahf)
	P.Refresh()
end

ns.RegisterEvent("ADDON_LOADED", function(name) if name == "Blizzard_AuctionHouseUI" then P.Attach() end end)
ns.RegisterEvent("PLAYER_LOGIN", function() if _G.AuctionHouseFrame then P.Attach() end end)

-- Redraw on the scan's changes and what the rows show (stars, plan, scores); the AH closing empties the
-- list (AH.Clear fires AH_CHANGED): released rows let go of their data (Style.List's resetter).
local function redraw() if P.frame then P.Refresh() end end
ns.On("AH_CHANGED", function()
	if not P.frame then return end
	if not ns.AH.Status() then
		ns.Window.ReleaseItemTip()
		P.SetNext(nil)
		S.SetList(P.list, {})
	end
	P.Refresh()
end)
ns.On("WISHLIST_CHANGED", redraw)
ns.On("PLAN_CHANGED", redraw)
ns.On("OPTIONS", function(k) if k == "ahead" then redraw() end end)
