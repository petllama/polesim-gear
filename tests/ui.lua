-- Permissive client widgets for window tests. Every frame, texture and font string remembers its
-- parent, children, text, shown state, scripts, textures, colours and points; other Uppercase methods
-- are no-ops (lowercase fields stay nil, as the addon's own fields must). U.install() sets the globals
-- the window reads. Helpers find widgets by text and run ScrollBox initializers.
local U = {}
local M = {}

local function new(kind, parent, name, template)
	local w = { kind = kind, parent = parent, name = name, template = template, children = {}, scripts = {},
		shown = true, points = {}, w = 0, h = 0, alpha = 1, enabled = true }
	setmetatable(w, { __index = function(_, k)
		local m = M[k]
		if m then return m end
		if type(k) == "string" and k:match("^%u") then return function() end end
	end })
	if parent and parent.children then parent.children[#parent.children + 1] = w end -- (a foreign parent: not tracked)
	if name then _G[name] = w end
	return w
end
U.new = new

function M:SetText(v) self.text = v end
function M:GetText() return self.text end
function M:IsShown() return self.shown end
function M:IsVisible()
	local w = self
	while w do
		if not w.shown then return false end
		w = w.parent
	end
	return true
end
function M:Show()
	local was = self:IsVisible()
	self.shown = true
	if not was and self:IsVisible() and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function M:Hide()
	local was = self:IsVisible()
	self.shown = false
	if was and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function M:SetShown(v) if v then self:Show() else self:Hide() end end
function M:SetScript(k, fn) self.scripts[k] = fn end
function M:GetScript(k) return self.scripts[k] end
function M:HookScript(k, fn)
	local old = self.scripts[k]
	self.scripts[k] = function(...) if old then old(...) end fn(...) end
end
function M:CreateFontString(name) return new("FontString", self, name) end
function M:CreateTexture(name) return new("Texture", self, name) end
function M:SetTexture(v) self.texture = v end
function M:SetAtlas(v) self.atlas = v end
function M:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
function M:SetVertexColor(r, g, b, a) self.vertex = { r, g, b, a } end
function M:SetTextColor(r, g, b) self.textColor = { r, g, b } end
function M:SetTexCoord(...) self.texCoord = { ... } end
function M:SetPoint(...) self.points[#self.points + 1] = { ... } end
function M:GetPoint(i) local p = self.points[i or 1] if p then return unpack(p) end end
function M:ClearAllPoints() self.points = {} end
function M:SetSize(w, h) self.w, self.h = w, h end
function M:SetWidth(w) self.w = w end
function M:SetHeight(h) self.h = h end
function M:GetWidth() return self.w end
function M:GetHeight() return self.h end
function M:SetAlpha(a) self.alpha = a end
function M:GetAlpha() return self.alpha end
function M:Enable() self.enabled = true end
function M:Disable() self.enabled = false end
function M:IsEnabled() return self.enabled end
function M:SetEnabled(v) self.enabled = v and true or false end
function M:Click(button) if self.scripts.OnClick then self.scripts.OnClick(self, button or "LeftButton") end end
function M:GetParent() return self.parent end
function M:GetName() return self.name end
-- WowScrollBoxList: frames past the new data's end are released (the view's resetter runs on them, as
-- ScrollBoxListViewMixin:Release does); U.rows acquires frames.
function M:SetDataProvider(dp)
	local keep = {}
	for i, f in ipairs(self.frames or {}) do
		if i <= #(dp or {}) then keep[#keep + 1] = f
		elseif self.view and self.view.resetter then self.view.resetter(f, f.d or f.e) end
	end
	self.frames = keep
	self.provided = dp
end
function M:SetupMenu(gen) self.menu = gen end -- WowStyle1DropdownTemplate

-- A menu generator run against a recording root: -> { { text, radio, isSelected, select, fn, data }, ... }
function U.collectMenu(gen, owner)
	local items = {}
	local root = {}
	function root:CreateRadio(text, isSel, setSel, data) items[#items + 1] = { text = text, radio = true, isSelected = isSel, select = setSel, data = data } return {} end
	function root:CreateButton(text, fn) items[#items + 1] = { text = text, fn = fn } return {} end
	function root:CreateCheckbox(text, isSel, setSel, data) items[#items + 1] = { text = text, isSelected = isSel, select = setSel, data = data } return {} end
	function root:CreateTitle(text) items[#items + 1] = { text = text, title = true } return {} end
	function root:CreateDivider() return {} end
	gen(owner, root)
	return items
end
function U.menu(dd) return U.collectMenu(dd.menu, dd) end

function U.walk(w, fn)
	fn(w)
	for _, c in ipairs(w.children) do U.walk(c, fn) end
end
-- every visible text under root, in creation order, one per line
function U.texts(root)
	local out = {}
	U.walk(root, function(w) if w.text and w:IsVisible() then out[#out + 1] = w.text end end)
	return table.concat(out, "\n")
end
function U.find(root, pred)
	local hit
	U.walk(root, function(w) if not hit and pred(w) then hit = w end end)
	return hit
end
local function ownText(w)
	if w.text then return w.text end
	for _, c in ipairs(w.children) do
		if c.kind == "FontString" and c.text then return c.text end
	end
end
U.ownText = ownText
-- the first visible clickable widget whose own text (or its first label) is `text`
function U.button(root, text)
	return U.find(root, function(w) return w.scripts.OnClick and w:IsVisible() and ownText(w) == text end)
end
-- run a ScrollBox's element initializer over its data: -> fresh rows (one per element)
function U.rows(box)
	local out = {}
	box.frames = {}
	for i, d in ipairs(box.provided or {}) do
		local row = new("Button", box)
		box.view.init(row, d)
		out[i] = row
		box.frames[i] = row
	end
	return out
end

function U.install()
	_G.CreateFrame = function(kind, name, parent, template) return new(kind, parent, name, template) end
	_G.UIParent = new("Frame", nil, "UIParent")
	_G.UISpecialFrames, _G.tinsert = {}, table.insert
	_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
	_G.CreateScrollBoxListLinearView = function()
		local v = new("View")
		function v:SetElementInitializer(_, init) self.init = init end
		function v:SetElementExtent(n) self.extent = n end
		function v:SetElementResetter(fn) self.resetter = fn end
		return v
	end
	_G.ScrollUtil = { InitScrollBoxListWithScrollBar = function(box, _, view) box.view = view end }
	_G.CreateDataProvider = function(t) return t or {} end
	_G.ScrollBoxConstants = { RetainScrollPosition = 1 }
	U.tip = { lines = {} }
	local tipM = {
		SetOwner = function(t, owner) t.owner, t.lines = owner, {} end,
		AddLine = function(t, s) t.lines[#t.lines + 1] = s end,
		AddDoubleLine = function(t, a, b) t.lines[#t.lines + 1] = a .. " = " .. b end,
		SetInventoryItem = function(t, _, slot) t.inventory = slot end,
		Show = function(t) t.shown = true end, Hide = function(t) t.shown = false end,
	}
	_G.GameTooltip = setmetatable(U.tip, { __index = function(_, k) return tipM[k] or (k:match("^%u") and function() end) or nil end })
	_G.GameTooltip_Hide = function() U.tip.shown = false end
	_G.ITEM_QUALITY_COLORS = {}
	for q, hex in pairs({ [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000" }) do
		_G.ITEM_QUALITY_COLORS[q] = { hex = "|cff" .. hex, r = tonumber(hex:sub(1, 2), 16) / 255,
			g = tonumber(hex:sub(3, 4), 16) / 255, b = tonumber(hex:sub(5, 6), 16) / 255 }
	end
	_G.CLASS_ICON_TCOORDS = { PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 } }
	U.equipped = {}
	_G.GetInventoryItemLink = function(_, slot) return U.equipped[slot] end
	_G.GetInventoryItemTexture = function(_, slot) return U.equipped[slot] and 134400 or nil end
	_G.GetInventoryItemQuality = function(_, slot) return U.equipped[slot] and 2 or nil end
	_G.GetMoneyString = function(c) return c .. "c" end
	_G.MenuUtil = { CreateContextMenu = function(owner, gen) U.contextMenu = U.collectMenu(gen, owner) end }
	_G.IsShiftKeyDown = function() return false end
end

return U
