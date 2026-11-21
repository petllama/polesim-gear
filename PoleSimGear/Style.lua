-- The window's look (the "Upgrade Command" template, see the v2 plan's "visual template"): colours,
-- sizes, column positions, and the small widget factories every tab uses. No game logic here.
local ADDON, ns = ...
local Style = {}
ns.Style = Style
local format = string.format

local function hex(h) return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255 } end
Style.hex = hex
local C = {
	body = hex("070a0b"), border = hex("2a3a40"), inner = hex("0f1a1d"),
	titleBg = hex("0b1214"), titleLine = hex("1c2a2f"), title = hex("eef2f3"), gold = hex("c99a3a"),
	tab = hex("112025"), tabBorder = hex("23363c"), tabText = hex("c8d2d4"), tabHover = hex("16303a"),
	tabOn = hex("05555e"), tabOnBorder = hex("2a8c95"), tabOnText = hex("e6f4f2"),
	close = hex("aa1414"), closeBorder = hex("5a0a0a"), closeHover = hex("c82020"), white = hex("ffffff"),
	card = hex("0a1316"), cardBorder = hex("1f2f35"), label = hex("9aa6aa"), text = hex("d6dde0"), sub = hex("c0c6c8"),
	dim = hex("aab4b8"), green = hex("5fd35f"), red = hex("e05050"), orange = hex("ff9a40"), blue = hex("4cc3ff"), pick = hex("ffd100"),
	barTrack = hex("1a2629"), barFill = hex("22a02a"),
	dd = hex("0e2127"), ddBorder = hex("2b4b55"),
	check = hex("0b1316"), checkBorder = hex("3a4a50"), checkOn = hex("2e9e3a"), checkOnBorder = hex("48c05a"), radioRow = hex("14262b"),
	table = hex("0f191b"), head = hex("182327"), headText = hex("b8bec0"), rowA = hex("10191c"), rowB = hex("121b1e"),
	sep = hex("1a262a"), rowHover = hex("1a2a30"),
	badgeGold = hex("95651d"), badgeGoldBorder = hex("c99a3a"), badgeGoldText = hex("ffe9a8"),
	badgeGrey = hex("242e31"), badgeGreyBorder = hex("3a464a"), badgeGreyText = hex("cfd5d7"),
}
Style.C = C
Style.W, Style.H, Style.ROW_H = 780, 500, 30
Style.FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
-- Where things sit (TOPLEFT offsets in the window); the table/content area is shared by every tab.
Style.CONTENT = { x = 142, y = -122, w = 626, h = 270 }
-- Gear Plan columns (x from the table's left edge). Column words: "Gain"/"Gain %" (the mockup's "Δ"
-- is not in every client font).
Style.COLS = { star = 4, prio = 22, slot = 48, curIcon = 106, curName = 130, curNameW = 100, curScore = 232,
	planIcon = 268, planName = 292, planNameW = 104, delta = 400, pct = 450, srcIcon = 500, kind = 518, action = 574 }
Style.KIND_ICON = {
	quest = "Interface\\GossipFrame\\AvailableQuestIcon", dungeon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
	crafted = "Interface\\Icons\\Trade_BlackSmithing", vendor = "Interface\\Icons\\INV_Misc_Coin_01",
	world = "Interface\\Icons\\INV_Misc_Bag_10",
}
Style.KIND_LABEL = { quest = "Quest", dungeon = "Dungeon", crafted = "Crafting", vendor = "Vendor", world = "BoE / World" }
-- the narrow Source columns (Gear Plan, Slot Upgrades): a word that fits 54 px at 12 px
Style.KIND_SHORT = { quest = "Quest", dungeon = "Dungeon", crafted = "Craft", vendor = "Vendor", world = "World" }
Style.TAB = { C.tab, C.tabBorder, C.tabText, C.tabHover }
Style.TAB_ON = { C.tabOn, C.tabOnBorder, C.tabOnText, C.tabOn }
Style.CLOSE = { C.close, C.closeBorder, C.white, C.closeHover }
Style.ACTION = { C.dd, C.ddBorder, C.text, C.tabHover }

-- numbers -------------------------------------------------------------------------------------------
function Style.Signed(x, suffix) return format("%+.1f", x) .. (suffix or "") end
function Style.Pct(gain, base)
	if not base or base <= 0.01 then return "" end
	return format("%+.1f%%", 100 * gain / base)
end
function Style.Thousands(x)
	local s = format("%.1f", x)
	local sign, int, dec = s:match("^(-?)(%d+)(%.%d)$")
	int = int:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if int:sub(1, 1) == "," then int = int:sub(2) end
	return sign .. int .. dec
end
function Style.Money(c)
	if type(GetMoneyString) == "function" then return GetMoneyString(c) end
	c = c or 0
	return format("%dg %ds %dc", math.floor(c / 10000), math.floor(c / 100) % 100, c % 100)
end
function Style.Colour(c) return format("|cff%02x%02x%02x", c[1] * 255 + 0.5, c[2] * 255 + 0.5, c[3] * 255 + 0.5) end
function Style.ItemText(inst)
	local q = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[inst.quality or 1]
	return (q and q.hex or "|cffffffff") .. (inst.name or "?") .. "|r"
end
function Style.Title(s) return ((s or ""):gsub("^%l", string.upper)) end

-- widgets -------------------------------------------------------------------------------------------
function Style.Fill(f, c, a, layer)
	local t = f:CreateTexture(nil, layer or "BACKGROUND")
	t:SetAllPoints()
	t:SetColorTexture(c[1], c[2], c[3], a or 1)
	return t
end
function Style.Border(f, c)
	local lines = {}
	local function line(p1, p2, horiz)
		local t = f:CreateTexture(nil, "BORDER")
		t:SetColorTexture(c[1], c[2], c[3], 1)
		t:SetPoint(p1)
		t:SetPoint(p2)
		if horiz then t:SetHeight(1) else t:SetWidth(1) end
		lines[#lines + 1] = t
	end
	line("TOPLEFT", "TOPRIGHT", true)
	line("BOTTOMLEFT", "BOTTOMRIGHT", true)
	line("TOPLEFT", "BOTTOMLEFT", false)
	line("TOPRIGHT", "BOTTOMRIGHT", false)
	return lines
end
function Style.SetBorder(lines, c) for _, t in ipairs(lines) do t:SetColorTexture(c[1], c[2], c[3], 1) end end
function Style.Text(parent, size, c, layer)
	local t = parent:CreateFontString(nil, layer or "OVERLAY")
	t:SetFont(Style.FONT, size or 12, "")
	c = c or C.text
	t:SetTextColor(c[1], c[2], c[3])
	t:SetJustifyH("LEFT")
	t:SetWordWrap(false)
	return t
end
-- A 1 px frame (colour c) just outside a texture: -> the frame (fr.border = its lines)
function Style.Frame(parent, tex, c)
	local fr = CreateFrame("Frame", nil, parent)
	fr:SetPoint("TOPLEFT", tex, "TOPLEFT", -1, 1)
	fr:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", 1, -1)
	fr.border = Style.Border(fr, c)
	return fr
end
-- A round dot (size px, a circle mask over a plain texture): dot:SetVertexColor colours it.
Style.DOT_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
function Style.Dot(parent, size, c)
	local t = parent:CreateTexture(nil, "OVERLAY")
	t:SetTexture("Interface\\Buttons\\WHITE8X8")
	t:SetSize(size, size)
	local m = parent:CreateMaskTexture()
	m:SetTexture(Style.DOT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	m:SetAllPoints(t)
	t:AddMaskTexture(m)
	if c then t:SetVertexColor(c[1], c[2], c[3], 1) end
	return t
end
function Style.Panel(parent, x, y, w, h, bg, border)
	local f = CreateFrame("Frame", nil, parent)
	f:SetPoint("TOPLEFT", x, y)
	f:SetSize(w, h)
	f.bg = Style.Fill(f, bg or C.card)
	f.border = Style.Border(f, border or C.cardBorder)
	return f
end
-- A flat button. colours = { fill, border, text, hover } (default: an inactive tab). b.tip: hover text.
function Style.Button(parent, text, w, h, onClick, colours)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w, h)
	b.bg = Style.Fill(b, C.tab)
	b.border = Style.Border(b, C.tabBorder)
	b.label = Style.Text(b, 12)
	b.label:SetPoint("CENTER")
	b.label:SetJustifyH("CENTER")
	b.label:SetText(text)
	Style.SetColours(b, colours or Style.TAB)
	b:SetScript("OnEnter", function(self)
		local hv = self.colours[4]
		if self:IsEnabled() then self.bg:SetColorTexture(hv[1], hv[2], hv[3], 1) end
		if self.tip then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(self.tip, 1, 1, 1, true)
			GameTooltip:Show()
		end
	end)
	b:SetScript("OnLeave", function(self)
		local f = self.colours[1]
		self.bg:SetColorTexture(f[1], f[2], f[3], 1)
		GameTooltip_Hide()
	end)
	b:SetScript("OnClick", onClick)
	return b
end
function Style.SetColours(b, colours)
	b.colours = colours
	b.bg:SetColorTexture(colours[1][1], colours[1][2], colours[1][3], 1)
	Style.SetBorder(b.border, colours[2])
	local t = b:IsEnabled() and colours[3] or C.label
	b.label:SetTextColor(t[1], t[2], t[3])
end
-- A Style.Button on or off, with the look: off is faded with a grey label and no hover colour.
function Style.SetEnabled(b, on)
	b:SetEnabled(on)
	b:SetAlpha(on and 1 or 0.4)
	Style.SetColours(b, b.colours)
end
-- Checkbox row (box, tick, label): b:Set(on); a click calls onToggle(not on).
function Style.Check(parent, label, onToggle)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(110, 20)
	b.box = CreateFrame("Frame", nil, b)
	b.box:SetSize(14, 14)
	b.box:SetPoint("LEFT", 0, 0)
	b.box.bg = Style.Fill(b.box, C.check)
	b.box.border = Style.Border(b.box, C.checkBorder)
	b.tick = b.box:CreateTexture(nil, "OVERLAY")
	b.tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	b.tick:SetAllPoints()
	b.label = Style.Text(b, 12)
	b.label:SetPoint("LEFT", 20, 0)
	b.label:SetText(label)
	function b:Set(on)
		self.on = on and true or false
		local f = self.on and C.checkOn or C.check
		self.box.bg:SetColorTexture(f[1], f[2], f[3], 1)
		Style.SetBorder(self.box.border, self.on and C.checkOnBorder or C.checkBorder)
		self.tick:SetShown(self.on)
	end
	b:SetScript("OnClick", function(self) onToggle(not self.on) end)
	b:Set(false)
	return b
end
-- Radio row: highlight bar + circle; b:Set(on); a click calls onSelect().
function Style.Radio(parent, label, onSelect)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(110, 20)
	b.hl = Style.Fill(b, C.radioRow)
	b.dot = b:CreateTexture(nil, "ARTWORK")
	b.dot:SetTexture("Interface\\Buttons\\UI-RadioButton")
	b.dot:SetSize(12, 12)
	b.dot:SetPoint("LEFT", 4, 0)
	b.label = Style.Text(b, 12)
	b.label:SetPoint("LEFT", 22, 0)
	b.label:SetText(label)
	function b:Set(on)
		self.on = on and true or false
		self.hl:SetShown(self.on)
		self.dot:SetTexCoord(self.on and 0.25 or 0, self.on and 0.5 or 0.25, 0, 1)
	end
	b:SetScript("OnClick", function() onSelect() end)
	b:Set(false)
	return b
end
-- Priority badge: b:Set(n) (1-3 gold, others grey; nil hides).
function Style.Badge(parent)
	local b = CreateFrame("Frame", nil, parent)
	b:SetSize(22, 18)
	b.bg = Style.Fill(b, C.badgeGrey)
	b.border = Style.Border(b, C.badgeGreyBorder)
	b.text = Style.Text(b, 11)
	b.text:SetPoint("CENTER")
	b.text:SetJustifyH("CENTER")
	function b:Set(n)
		if not n then self:Hide() return end
		self:Show()
		local gold = n <= 3
		local f, br, t = gold and C.badgeGold or C.badgeGrey, gold and C.badgeGoldBorder or C.badgeGreyBorder, gold and C.badgeGoldText or C.badgeGreyText
		self.bg:SetColorTexture(f[1], f[2], f[3], 1)
		Style.SetBorder(self.border, br)
		self.text:SetTextColor(t[1], t[2], t[3])
		self.text:SetText(tostring(n))
	end
	return b
end
-- Wishlist star: b:Set(on); click -> onClick().
function Style.Star(parent, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(14, 14)
	b.tex = b:CreateTexture(nil, "ARTWORK")
	b.tex:SetAllPoints()
	function b:Set(on)
		self.on = on and true or false
		self.tex:SetAtlas(self.on and "auctionhouse-icon-favorite" or "auctionhouse-icon-favorite-off")
	end
	b:SetScript("OnClick", function() onClick() end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(self.on and "Remove from your wishlist" or "Add to your wishlist", 1, 1, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	b:Set(false)
	return b
end
-- Item cell: icon (quality border), name (quality colour), a small second line. cell:Set(inst|nil, sub, subColour)
function Style.ItemCell(parent, iconSize, nameW)
	local c = CreateFrame("Frame", nil, parent)
	c:SetSize(iconSize + 4 + nameW, iconSize)
	c.icon = c:CreateTexture(nil, "ARTWORK")
	c.icon:SetSize(iconSize, iconSize)
	c.icon:SetPoint("LEFT", 0, 0)
	-- a 1 px quality-coloured frame around the icon
	c.iconFrame = CreateFrame("Frame", nil, c)
	c.iconFrame:SetPoint("TOPLEFT", c.icon, "TOPLEFT", -1, 1)
	c.iconFrame:SetPoint("BOTTOMRIGHT", c.icon, "BOTTOMRIGHT", 1, -1)
	c.frame = Style.Border(c.iconFrame, C.cardBorder)
	c.name = Style.Text(c, 12)
	c.name:SetPoint("TOPLEFT", iconSize + 4, -1)
	c.name:SetWidth(nameW)
	c.sub = Style.Text(c, 10, C.label)
	c.sub:SetPoint("TOPLEFT", iconSize + 4, -14)
	c.sub:SetWidth(nameW)
	-- faded and grey (a pick not available now); every Set undims
	function c:SetDim(on)
		local a = on and 0.5 or 1
		self.name:SetAlpha(a)
		self.icon:SetAlpha(a)
		self.iconFrame:SetAlpha(a)
		self.icon:SetDesaturated(on and true or false)
	end
	function c:Set(inst, sub, subColour)
		self:SetDim(false)
		if not inst then
			self.icon:Hide()
			self.iconFrame:Hide()
			self.name:SetText("")
			self.sub:SetText(sub or "")
			return
		end
		self.icon:Show()
		self.iconFrame:Show()
		self.icon:SetTexture(inst.icon and ("Interface\\Icons\\" .. inst.icon) or "Interface\\Icons\\INV_Misc_QuestionMark")
		local q = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[inst.quality or 1]
		Style.SetBorder(self.frame, q and q.r and { q.r, q.g, q.b } or C.cardBorder)
		self.name:SetText(Style.ItemText(inst))
		local s = subColour or C.label
		self.sub:SetTextColor(s[1], s[2], s[3])
		self.sub:SetText(sub or "")
	end
	return c
end
-- A dropdown: Blizzard's WowStyle1DropdownTemplate with radio items, else (template missing) a flat
-- button cycling through the list. list() -> { { text, value } }; dd:Update() redraws its text.
function Style.Dropdown(parent, w, h, list, isSelected, select)
	local ok, dd = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	if ok and dd and type(dd.SetupMenu) == "function" then
		dd:SetSize(w, h)
		dd:SetupMenu(function(_, root)
			for _, o in ipairs(list()) do
				root:CreateRadio(o.text, function() return isSelected(o.value) end, function() select(o.value) end, o.value)
			end
		end)
		function dd:Update() if self.GenerateMenu then self:GenerateMenu() end end
		return dd
	end
	local b = Style.Button(parent, "", w, h, nil, Style.ACTION)
	b:SetScript("OnClick", function()
		local l, at = list(), 1
		for i, o in ipairs(l) do if isSelected(o.value) then at = i end end
		if #l > 0 then select(l[at % #l + 1].value) end
	end)
	function b:Update()
		for _, o in ipairs(list()) do if isSelected(o.value) then self.label:SetText(o.text) end end
	end
	b:Update()
	return b
end
-- A scrolling list in parent at (x, y), w x h, rows `extent` px high, init(row, data).
function Style.List(parent, x, y, w, h, extent, init)
	local box = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
	box:SetPoint("TOPLEFT", x, y)
	box:SetSize(w - 10, h)
	local bar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
	bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 2, 0)
	bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 2, 0)
	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(extent)
	view:SetElementInitializer("Button", init)
	-- a released row lets go of its data (ScrollBoxListViewMixin:Release calls this): a pooled row
	-- would otherwise keep the closed window's model alive
	view:SetElementResetter(function(row) row.e, row.d = nil, nil end)
	ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
	box.bar = bar
	return box
end
function Style.SetList(box, list)
	box:SetDataProvider(CreateDataProvider(list), ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition)
end
-- Row background: alternating fill and the hover colour.
function Style.RowBg(row, index)
	if not row.bg then
		row.bg = Style.Fill(row, C.rowA)
		row.sep = row:CreateTexture(nil, "BORDER")
		row.sep:SetColorTexture(C.sep[1], C.sep[2], C.sep[3], 1)
		row.sep:SetPoint("BOTTOMLEFT")
		row.sep:SetPoint("BOTTOMRIGHT")
		row.sep:SetHeight(1)
	end
	local f = (index or 1) % 2 == 1 and C.rowA or C.rowB
	row.bg:SetColorTexture(f[1], f[2], f[3], 1)
	row.baseFill = f
end
function Style.Hover(row, on)
	local f = on and C.rowHover or row.baseFill or C.rowA
	if row.bg then row.bg:SetColorTexture(f[1], f[2], f[3], 1) end
end
