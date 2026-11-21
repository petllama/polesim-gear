-- The minimap button: a plain Button on the Minimap's rim (no library, no secure template). Left-click
-- toggles the upgrade browser (as /psg); drag moves it around the rim. Saved account-wide in
-- PoleSimGearDB.minimap = { angle = degrees, hide = bool }; `/psg minimap` hides/shows it.
local ADDON, ns = ...
local M = {}
ns.Minimap = M

M.DEFAULT_ANGLE = 225 -- bottom-left, clear of the zoom buttons and the calendar
M.RADIUS_PAD = 5 -- past the minimap's edge, so the 31 px button sits on the rim
M.ICON = "Interface\\Icons\\INV_Chest_Cloth_17" -- a cloth chest (the client's own Wardrobe portrait)

-- GetMinimapShape() (defined by minimap addons, not the client) -> which quadrants are round:
-- 1 top-right, 2 top-left, 3 bottom-right, 4 bottom-left (index = 1, +1 when x < 0, +2 when y < 0).
local SHAPES = {
	["ROUND"] = { true, true, true, true },
	["SQUARE"] = { false, false, false, false },
	["CORNER-TOPLEFT"] = { false, true, false, false },
	["CORNER-TOPRIGHT"] = { true, false, false, false },
	["CORNER-BOTTOMLEFT"] = { false, false, false, true },
	["CORNER-BOTTOMRIGHT"] = { false, false, true, false },
	["SIDE-LEFT"] = { false, true, false, true },
	["SIDE-RIGHT"] = { true, false, true, false },
	["SIDE-TOP"] = { true, true, false, false },
	["SIDE-BOTTOM"] = { false, false, true, true },
	-- TRICORNER-X: the corner opposite X is the square one (as minimap addons use the names)
	["TRICORNER-TOPLEFT"] = { true, true, false, true },
	["TRICORNER-TOPRIGHT"] = { true, true, true, false },
	["TRICORNER-BOTTOMLEFT"] = { false, true, true, true },
	["TRICORNER-BOTTOMRIGHT"] = { true, false, true, true },
}

-- The button's centre offset from the minimap's centre for an angle (degrees, 0 = right, 90 = up) on a
-- minimap of width w, height h and shape (nil/unknown = round). A square quadrant follows its corner.
function M.Offset(angle, w, h, shape)
	local a = math.rad(angle)
	local x, y = math.cos(a), math.sin(a)
	local q = 1
	if x < 0 then q = q + 1 end
	if y < 0 then q = q + 2 end
	local rw, rh = w / 2 + M.RADIUS_PAD, h / 2 + M.RADIUS_PAD
	local round = (SHAPES[shape or "ROUND"] or SHAPES.ROUND)[q]
	if round then return x * rw, y * rh end
	local s = math.sqrt(2)
	return math.max(-rw, math.min(x * rw * s, rw)), math.max(-rh, math.min(y * rh * s, rh))
end

-- The angle (degrees, 0..360) of point px,py seen from cx,cy.
function M.AngleFrom(cx, cy, px, py)
	return math.deg(math.atan2(py - cy, px - cx)) % 360
end

local function settings()
	local db = ns.db or PoleSimGearDB
	db.minimap = type(db.minimap) == "table" and db.minimap or {}
	local s = db.minimap
	if type(s.angle) ~= "number" then s.angle = M.DEFAULT_ANGLE end
	s.hide = s.hide == true
	return s
end

function M.Place()
	local b = M.button
	if not b then return end
	local shape = type(GetMinimapShape) == "function" and GetMinimapShape() or nil
	local x, y = M.Offset(settings().angle, Minimap:GetWidth(), Minimap:GetHeight(), shape)
	b:ClearAllPoints()
	b:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function follow(self)
	local mx, my = Minimap:GetCenter()
	local px, py = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	settings().angle = M.AngleFrom(mx, my, px / scale, py / scale)
	M.Place()
end

local function create()
	local b = CreateFrame("Button", "PoleSimGearMinimapButton", Minimap)
	M.button = b
	b:SetSize(31, 31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local border = b:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetPoint("TOPLEFT")
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetSize(20, 20)
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetPoint("TOPLEFT", 7, -5)
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetSize(17, 17)
	icon:SetTexture(M.ICON)
	icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
	icon:SetPoint("TOPLEFT", 7, -6)
	b.icon = icon

	b:SetScript("OnClick", function(_, button)
		if button == "LeftButton" then ns.Window.Toggle() end
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("PoleSim Gear")
		GameTooltip:AddLine("Left-click: upgrade browser", 1, 1, 1)
		GameTooltip:AddLine("Drag: move", 1, 1, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b:SetScript("OnDragStart", function(self)
		GameTooltip:Hide()
		self:LockHighlight()
		self:SetScript("OnUpdate", follow)
	end)
	b:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
		self:UnlockHighlight()
	end)
	M.Place()
	b:SetShown(not settings().hide)
end

ns.On("DB_READY", function()
	settings()
	if Minimap and not M.button then create() end
end)

ns.Slash("minimap", function()
	local s = settings()
	s.hide = not s.hide
	if M.button then M.button:SetShown(not s.hide) end
	ns.Print(s.hide and "minimap button hidden (/psg minimap shows it)" or "minimap button shown")
end)
