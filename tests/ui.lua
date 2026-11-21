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
function M:SetDesaturated(v) self.desaturated = v and true or false end
function M:CreateMaskTexture(name) return new("MaskTexture", self, name) end
function M:AddMaskTexture(m) self.mask = m end
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
-- ScrollBoxListViewMixin:Release does) into the list's pool, hidden; U.rows acquires frames.
local function releaseFrom(box, n)
	local keep = {}
	box.pool = box.pool or {}
	for i, f in ipairs(box.frames or {}) do
		if i <= n then keep[#keep + 1] = f
		else
			if box.view and box.view.resetter then box.view.resetter(f, f.d or f.e) end
			f:Hide()
			box.pool[#box.pool + 1] = f
		end
	end
	box.frames = keep
end
function M:SetFont(file, size, flags) self.font, self.fontSize = file, size end
function M:SetResizable(v) self.resizable = v end
function M:SetResizeBounds(a, b, c, d) self.bounds = { a, b, c, d } end
function M:StartSizing(point) self.sizing = point or "BOTTOMRIGHT" end
function M:StopMovingOrSizing() self.sizing = nil end
function M:SetNormalTexture(v) self.normalTexture = v end
function M:SetHighlightTexture(v) self.highlightTexture = v end
function M:SetPushedTexture(v) self.pushedTexture = v end
-- ScrollBox: the frames in view with their data (the client's ScrollBoxListMixin:ForEachFrame)
function M:GetView() return self.view end
function M:ForEachFrame(fn) for _, f in ipairs(self.frames or {}) do fn(f, f.e or f.d) end end
function M:SetDataProvider(dp)
	releaseFrom(self, #(dp or {}))
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
	U.walk(root, function(w) if type(w.text) == "string" and w:IsVisible() then out[#out + 1] = w.text end end)
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
-- run a ScrollBox's element initializer over its data: -> its rows (one per element). Frames are
-- reused as the client's ScrollBox does (shown ones first, then released ones, new ones last), so
-- reused-row paths run and a long session makes no more frames than its longest list.
function U.rows(box, max)
	local out = {}
	local data = box.provided or {}
	local n = math.min(#data, max or #data) -- max: only the first max rows (the ones in view)
	releaseFrom(box, n)
	for i = 1, n do
		local d = data[i]
		local row = box.frames[i] or table.remove(box.pool) or new("Button", box)
		row:Show()
		box.view.init(row, d)
		out[i] = row
		box.frames[i] = row
	end
	return out
end
-- Scroll a list from top to bottom through a window of n frames (n visible rows): every element's
-- initializer runs, frames leaving the view are released (resetter) and reused -> elements shown
function U.scroll(box, n)
	local data = box.provided or {}
	releaseFrom(box, 0)
	local count = 0
	for first = 1, #data, n do
		releaseFrom(box, 0)
		for i = first, math.min(#data, first + n - 1) do
			local row = table.remove(box.pool) or new("Button", box)
			row:Show()
			box.view.init(row, data[i])
			box.frames[#box.frames + 1] = row
			count = count + 1
		end
	end
	return count
end

-- A FontString's drawn width, estimated for FRIZQT__ (the client's font), in em per character:
-- narrow 0.33, r 0.45, wide (m w M W %) 0.95, other capitals 0.75, the rest (lower case, digits: all
-- digits are one width) 0.66.
-- Calibrated on the 0.2.0 screenshot: every cut text there ("Range...", "Main h...", "130...",
-- "+30....", "Dunge...") is over its width by this estimate. Colour codes and atlases do not count.
function U.textWidth(text, size)
	local s = tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|A.-|a", "")
	local w = 0
	for ch in s:gmatch(".") do
		local e
		if ch:match("[ilIj%.,:;'!|t f%(%)/%[%]]") then e = 0.33
		elseif ch == "r" then e = 0.45
		elseif ch:match("[mwMW%%]") then e = 0.95
		elseif ch:match("%u") then e = 0.75
		else e = 0.66 end
		w = w + e
	end
	return w * (size or 12)
end
-- Every visible FontString under root with a set width whose text is wider than it:
-- -> { "text (needs N, has W)", ... }
function U.overflows(root)
	local out = {}
	U.walk(root, function(w)
		if w.kind == "FontString" and w:IsVisible() and type(w.text) == "string" and w.text ~= "" and (w.w or 0) > 0 then
			local need = U.textWidth(w.text, w.fontSize)
			if need > w.w then out[#out + 1] = string.format("%q (needs %.0f, has %d)", w.text, need, w.w) end
		end
	end)
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
	U.postCall = nil
	_G.IsModifiedClick = function() return false end
	_G.GameTooltip_ShowCompareItem = nil
	local tipM = {
		SetOwner = function(t, owner) t.owner, t.lines = owner, {} end,
		AddLine = function(t, s) t.lines[#t.lines + 1] = s end,
		AddDoubleLine = function(t, a, b) t.lines[#t.lines + 1] = a .. " = " .. b end,
		SetInventoryItem = function(t, _, slot) t.inventory = slot end,
		-- the client's item tooltip: its lines replace the tooltip's, then the item post-calls run
		-- (U.postCall: a test's capture of the addon's TooltipDataProcessor hook)
		SetHyperlink = function(t, link)
			t.link, t.lines = link, { "<item " .. link .. ">" }
			t.hyperlinks = (t.hyperlinks or 0) + 1
			if U.postCall then U.postCall(t, { hyperlink = link }) end
		end,
		GetOwner = function(t) return t.owner end,
		Show = function(t) t.shown = true end,
		Hide = function(t)
			t.shown = false
			for _, fn in ipairs(t.onHide or {}) do fn(t) end
		end,
		HookScript = function(t, k, fn)
			if k == "OnHide" then t.onHide = t.onHide or {} t.onHide[#t.onHide + 1] = fn end
		end,
	}
	_G.GameTooltip = setmetatable(U.tip, { __index = function(_, k) return tipM[k] or (k:match("^%u") and function() end) or nil end })
	_G.GameTooltip_Hide = function() U.tip:Hide() end
	_G.ITEM_QUALITY_COLORS = {}
	for q, hex in pairs({ [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000" }) do
		_G.ITEM_QUALITY_COLORS[q] = { hex = "|cff" .. hex, r = tonumber(hex:sub(1, 2), 16) / 255,
			g = tonumber(hex:sub(3, 4), 16) / 255, b = tonumber(hex:sub(5, 6), 16) / 255 }
	end
	_G.CLASS_ICON_TCOORDS = { PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 }, MAGE = { 0.25, 0.49609375, 0, 0.25 } }
	U.equipped = {}
	_G.GetInventoryItemLink = function(_, slot) return U.equipped[slot] end
	_G.GetInventoryItemTexture = function(_, slot) return U.equipped[slot] and 134400 or nil end
	_G.GetInventoryItemQuality = function(_, slot) return U.equipped[slot] and 2 or nil end
	_G.GetMoneyString = function(c) return c .. "c" end
	_G.MenuUtil = { CreateContextMenu = function(owner, gen) U.contextMenu = U.collectMenu(gen, owner) end }
	_G.IsShiftKeyDown = function() return false end
end

return U
