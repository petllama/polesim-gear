-- The minimap button: placement math, dragging, the saved angle and hide flag, the click and /psg minimap.
local T = require("t")

-- Permissive widgets (every Uppercase method a no-op unless set here), recording points and scripts.
local function widget()
	local w = { scripts = {}, shown = true }
	return setmetatable(w, { __index = function(_, k)
		if type(k) == "string" and k:match("^%u") then return function() end end
	end })
end
local function frame(kind, name, parent)
	local f = widget()
	f.parent = parent
	f.SetScript = function(self, k, fn) self.scripts[k] = fn end
	f.GetScript = function(self, k) return self.scripts[k] end
	f.Show = function(self) self.shown = true end
	f.Hide = function(self) self.shown = false end
	f.SetShown = function(self, on) self.shown = on and true or false end
	f.IsShown = function(self) return self.shown end
	f.SetPoint = function(self, p, rel, rp, x, y) self.point = { p, rel, rp, x, y } end
	f.CreateTexture = function() return widget() end
	if name then _G[name] = f end
	return f
end

-- Core + Minimap loaded, the client's Minimap (198 px, centre at 500,400, scale 1) and saved variables.
local function load(db)
	local ns = T.addon({ "Core.lua" })
	ns.Print = function() end
	_G.CreateFrame = frame
	_G.Minimap = frame("Minimap")
	_G.Minimap.GetWidth = function() return 198 end
	_G.Minimap.GetHeight = function() return 198 end
	_G.Minimap.GetCenter = function() return 500, 400 end
	_G.Minimap.GetEffectiveScale = function() return 1 end
	_G.GameTooltip = widget()
	_G.GetMinimapShape = nil
	assert(loadfile("PoleSimGear/Minimap.lua"))("PoleSimGear", ns)
	_G.PoleSimGearDB, _G.PoleSimGearCharDB = db, nil
	ns._frame.scripts.OnEvent(ns._frame, "ADDON_LOADED", "PoleSimGear")
	return ns
end

return {
	-- Round: the angle around the centre at half the width + 5 (on the minimap's rim).
	offset_round = function()
		local ns = load({})
		local M = ns.Minimap
		local x, y = M.Offset(0, 198, 198)
		T.near(x, 104); T.near(y, 0)
		x, y = M.Offset(90, 198, 198)
		T.near(x, 0); T.near(y, 104)
		x, y = M.Offset(225, 198, 198)
		T.near(x, -104 / math.sqrt(2)); T.near(y, -104 / math.sqrt(2))
	end,
	-- Square: a square corner is followed to the corner (clamped to the edges), a round one stays round.
	offset_square = function()
		local M = load({}).Minimap
		local x, y = M.Offset(45, 198, 198, "SQUARE")
		T.near(x, 104, 1e-6, "square corner x"); T.near(y, 104, 1e-6, "square corner y")
		x, y = M.Offset(0, 198, 198, "SQUARE")
		T.near(x, 104); T.near(y, 0)
		-- CORNER-TOPLEFT: only the top-left quadrant is round
		x, y = M.Offset(135, 198, 198, "CORNER-TOPLEFT")
		T.near(x, -104 / math.sqrt(2)); T.near(y, 104 / math.sqrt(2))
		x, y = M.Offset(-45, 198, 198, "CORNER-TOPLEFT")
		T.near(x, 104); T.near(y, -104)
		-- an unknown shape counts as round
		x, y = M.Offset(45, 198, 198, "WEIRD")
		T.near(x, 104 / math.sqrt(2))
	end,
	angle_from_cursor = function()
		local M = load({}).Minimap
		T.near(M.AngleFrom(500, 400, 600, 400), 0)
		T.near(M.AngleFrom(500, 400, 500, 500), 90)
		T.near(M.AngleFrom(500, 400, 400, 400), 180)
		T.near(M.AngleFrom(500, 400, 500, 300), 270, 1e-6, "never negative")
	end,
	-- Created on load, shown by default, the saved table filled in; placed by the saved angle.
	default_shown = function()
		local db = {}
		local ns = load(db)
		local b = ns.Minimap.button
		T.ok(b, "button made")
		T.eq(b.parent, _G.Minimap, "parented to Minimap")
		T.eq(b:IsShown(), true)
		T.eq(db.minimap.hide, false)
		T.eq(db.minimap.angle, 225)
		T.eq(b.point[2], _G.Minimap)
		T.near(b.point[4], -104 / math.sqrt(2))
	end,
	saved_angle_and_hide = function()
		local ns = load({ minimap = { angle = 90, hide = true } })
		local b = ns.Minimap.button
		T.eq(b:IsShown(), false, "stays hidden")
		T.near(b.point[4], 0); T.near(b.point[5], 104)
	end,
	-- A minimap addon's GetMinimapShape() is honoured when placing.
	square_minimap_placement = function()
		local ns = load({ minimap = { angle = 45 } })
		_G.GetMinimapShape = function() return "SQUARE" end
		ns.Minimap.Place()
		local b = ns.Minimap.button
		T.near(b.point[4], 104); T.near(b.point[5], 104)
		_G.GetMinimapShape = nil
	end,
	-- Dragging follows the cursor (scaled by the minimap's effective scale) and saves the angle.
	drag_saves_angle = function()
		local db = {}
		local ns = load(db)
		local b = ns.Minimap.button
		_G.Minimap.GetEffectiveScale = function() return 2 end
		_G.GetCursorPosition = function() return 1000, 1000 end -- 500,500 in minimap units: straight up
		b.scripts.OnDragStart(b)
		T.ok(b.scripts.OnUpdate, "follows while dragged")
		b.scripts.OnUpdate(b, 0.01)
		T.near(db.minimap.angle, 90)
		T.near(b.point[4], 0); T.near(b.point[5], 104)
		b.scripts.OnDragStop(b)
		T.eq(b.scripts.OnUpdate, nil, "stops following")
	end,
	click_toggles_browser = function()
		local ns = load({})
		local n = 0
		ns.Window = { Toggle = function() n = n + 1 end }
		local b = ns.Minimap.button
		b.scripts.OnClick(b, "LeftButton")
		T.eq(n, 1)
		b.scripts.OnClick(b, "RightButton")
		T.eq(n, 1, "right-click does not open it")
	end,
	tooltip = function()
		local ns = load({})
		local lines = {}
		_G.GameTooltip.AddLine = function(_, s) lines[#lines + 1] = s end
		_G.GameTooltip.SetText = function(_, s) lines[#lines + 1] = s end
		local b = ns.Minimap.button
		b.scripts.OnEnter(b)
		T.eq(table.concat(lines, "|"), "PoleSim Gear|Left-click: upgrade browser|Drag: move")
	end,
	-- /psg minimap hides and shows it, saved.
	slash_toggles = function()
		local db = {}
		local ns = load(db)
		local b = ns.Minimap.button
		_G.SlashCmdList.POLESIMGEAR("minimap")
		T.eq(b:IsShown(), false); T.eq(db.minimap.hide, true)
		_G.SlashCmdList.POLESIMGEAR("minimap")
		T.eq(b:IsShown(), true); T.eq(db.minimap.hide, false)
	end,
	-- No Minimap frame (a replaced minimap UI): no error, no button; /psg minimap still answers.
	no_minimap = function()
		local ns = T.addon({ "Core.lua" })
		ns.Print = function() end
		_G.CreateFrame = frame
		_G.Minimap = nil
		assert(loadfile("PoleSimGear/Minimap.lua"))("PoleSimGear", ns)
		_G.PoleSimGearDB = {}
		ns._frame.scripts.OnEvent(ns._frame, "ADDON_LOADED", "PoleSimGear")
		T.eq(ns.Minimap.button, nil)
		_G.SlashCmdList.POLESIMGEAR("minimap")
		T.eq(_G.PoleSimGearDB.minimap.hide, true)
	end,
	in_toc_before_the_end = function()
		local f = assert(io.open("PoleSimGear/PoleSimGear.toc"))
		local toc = f:read("*a")
		f:close()
		T.ok(toc:find("Window.lua\r?\nMinimap.lua"), "Minimap.lua right after the window files")
	end,
}
