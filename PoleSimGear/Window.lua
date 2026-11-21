-- The PoleSim Gear window (the "Upgrade Command" design): frame, title bar, tabs, header cards, left
-- panel, bottom strip and the model's build lifecycle. Tabs (Tab*.lua) register a panel each and
-- draw from Window.state; nothing here scores items.
local ADDON, ns = ...
local Win = {}
ns.Window = Win
local S = ns.Style
local C = S.C
local format = string.format

Win.TABS = { { key = "plan", label = "Gear Plan" }, { key = "slot", label = "Slot Upgrades" }, { key = "sources", label = "Sources" },
	{ key = "weights", label = "Weights" }, { key = "settings", label = "Settings" } }
local tabDefs, panels = {}, {}
-- def = { create = fn(parent) -> panel, refresh = fn(panel), release = fn(panel) (optional) }
function Win.RegisterTab(key, def) tabDefs[key] = def end

-- model: Browser.Build's; groups: Groups.Build's (Sources tab, made on demand); slot: Slot Upgrades'
-- slot; all: { key, rows } every upgrade of that slot (Show all)
local state = { model = nil, building = nil, stale = true, why = nil, groups = nil, slot = "head", all = nil,
	allBuilding = nil, allWhy = nil, codex = nil }
Win.state = state
local frame

-- (codex() and the body of Env: the 0.1.0 browser window's, unchanged, plus keep)
local function codex()
	local C = ns.Sources.Codex()
	if not C then return nil, "Polestar's Codex is not available: is Polestar enabled?" end
	if type(C.Load) == "function" then
		local ok, loaded = pcall(C.Load)
		if not (ok and loaded) then return nil, "Polestar's Codex could not be loaded: is Polestar_Codex enabled?" end
	end
	return C
end


-- The items the build keeps whatever the trim: this spec's picks and the wishlist.
function Win.Keep(spec)
	local keep = {}
	local char = ns.char or {}
	local picks = type(char.plan) == "table" and char.plan[spec]
	for _, k in pairs(type(picks) == "table" and picks or {}) do keep[k] = true end
	for _, k in ipairs(ns.Wishlist.Keys()) do keep[k] = true end
	return keep
end

function Win.Env()
	local ctx = ns.Context.Get()
	if not ctx then return nil, "no weights for this character" end
	local C, why = codex()
	if not C then return nil, why end
	-- Polestar.Compat.IsQuestCompleted (docs/API.md), else the client's own answer.
	local function completed(q)
		local P = _G.Polestar
		local Compat = type(P) == "table" and P.Compat
		if type(Compat) == "table" and type(Compat.IsQuestCompleted) == "function" then
			local ok, done = pcall(Compat.IsQuestCompleted, q)
			if ok then return done == true end
		end
		return C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(q) and true or false
	end
	local Items = ns.Items
	state.codex = C
	return {
		cls = ctx.cls, level = ctx.level, ahead = ns.Browser.AHEAD, codex = C,
		-- decoded on demand, nothing kept (Items.Peek; the index is released when the window closes)
		items = { Get = Items.Peek, ByInv = Items.ByInv, Rl = Items.Rl },
		player = { faction = ctx.faction, classBit = ctx.classBit, raceBit = ctx.raceBit, completed = completed },
		routeStep = ns.Route.StepOf, keep = Win.Keep(ctx.spec),
		at = function(L)
			local a = ns.Context.At(L)
			if not a then return { w = {}, worn = {}, style = "any" } end
			return { w = a.w, worn = a.worn, style = a.band.style }
		end,
	}
end

-- The view state for View/Plan: { spec, filters, ahead, show }
function Win.St()
	local ctx = ns.Context.Get()
	local v = ns.Options.View()
	return { spec = ctx and ctx.spec, filters = v.filters, ahead = v.ahead, show = v.show }
end

function Win.Panel(key) return panels[key] end

function Win.SetTab(key)
	if not Win.TABS_BY[key] then return end
	ns.Options.View().tab = key
	if not frame then return end
	for k, b in pairs(frame.tabs) do S.SetColours(b, k == key and S.TAB_ON or S.TAB) end
	if not panels[key] then
		-- a tab whose file is not there yet (a later phase) gets an empty panel
		panels[key] = tabDefs[key] and tabDefs[key].create(frame.content) or CreateFrame("Frame", nil, frame.content)
		panels[key]:SetAllPoints(frame.content)
	end
	for k, p in pairs(panels) do p:SetShown(k == key) end
	Win.Refresh()
end
Win.TABS_BY = {}
for _, t in ipairs(Win.TABS) do Win.TABS_BY[t.key] = t end

-- Slot Upgrades on one slot (a Gear Plan row, a "Choose").
function Win.OpenSlot(key)
	if state.slot ~= key then Win.DropAll() end
	state.slot = key
	Win.SetTab("slot")
end

local function release()
	if state.building then state.building:Cancel() end
	Win.DropAll()
	state.building, state.model, state.stale, state.groups, state.codex = nil, nil, true, nil, nil
	for key, p in pairs(panels) do
		local def = tabDefs[key]
		if def and def.release then def.release(p) end
	end
	ns.Items.ReleaseIndex()
	ns.Route.Reset()
end

function Win.DropAll()
	if state.allBuilding then state.allBuilding:Cancel() end
	state.all, state.allBuilding, state.allWhy = nil, nil, nil
end

local function create()
	frame = CreateFrame("Frame", "PoleSimGearFrame", UIParent)
	frame:SetSize(S.W, S.H)
	local pos = ns.db and type(ns.db.window) == "table" and ns.db.window
	if pos and pos.point then frame:SetPoint(pos.point, UIParent, pos.point, pos.x or 0, pos.y or 0) else frame:SetPoint("CENTER") end
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	tinsert(UISpecialFrames, "PoleSimGearFrame")
	S.Fill(frame, C.body, 0.97)
	S.Border(frame, C.border)
	local bar = S.Panel(frame, 0, 0, S.W, 46, C.titleBg, C.titleLine)
	frame.bar = bar
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function() frame:StartMoving() end)
	bar:SetScript("OnDragStop", function()
		frame:StopMovingOrSizing()
		local p, _, _, x, y = frame:GetPoint(1)
		if ns.db and p then ns.db.window = { point = p, x = x, y = y } end
	end)
	local icon = bar:CreateTexture(nil, "ARTWORK")
	icon:SetSize(36, 36)
	icon:SetPoint("TOPLEFT", 12, -5)
	icon:SetTexture(ns.Minimap and ns.Minimap.ICON or "Interface\\Icons\\INV_Chest_Cloth_17")
	frame.title = S.Text(bar, 20, C.title)
	frame.title:SetPoint("TOPLEFT", 56, -14)
	frame.title:SetText("PoleSim Gear")
	frame.close = S.Button(bar, "X", 22, 22, function() frame:Hide() end, S.CLOSE)
	frame.close:SetPoint("TOPRIGHT", -10, -12)
	frame.tabs = {}
	local x = -40
	for i = #Win.TABS, 1, -1 do
		local t = Win.TABS[i]
		local b = S.Button(bar, t.label, 86, 26, function() Win.SetTab(t.key) end, S.TAB)
		b:SetPoint("TOPRIGHT", x, -10)
		x = x - 92
		frame.tabs[t.key] = b
	end
	local A = S.CONTENT
	frame.content = S.Panel(frame, A.x, A.y, A.w, A.h, C.table, C.cardBorder)
	if Win.CreateHeader then Win.CreateHeader(frame) end -- Task 3.4
	if Win.CreateLeft then Win.CreateLeft(frame) end -- Task 3.5
	if Win.CreateBottom then Win.CreateBottom(frame) end -- Task 3.6
	frame:Hide() -- a new frame is shown: hidden first, so the first toggle shows it (and OnShow runs)
	frame:SetScript("OnShow", function()
		Win.SetTab(ns.Options.View().tab)
		if state.stale then Win.Build() else Win.Refresh() end
	end)
	frame:SetScript("OnHide", release)
	Win.frame = frame
end

function Win.Refresh()
	if not (frame and frame:IsShown()) then return end
	local ctx = ns.Context.Get()
	if Win.UpdateHeader then Win.UpdateHeader(frame, ctx) end
	if Win.UpdateLeft then Win.UpdateLeft(frame) end
	if Win.UpdateBottom then Win.UpdateBottom(frame, ctx) end
	local key = ns.Options.View().tab
	local p, def = panels[key], tabDefs[key]
	if p and def and def.refresh then def.refresh(p) end
end

-- Build/ShowAll: the 0.1.0 browser window's Build and ShowAll (Build also drops the Sources grouping). ShowAll(key) is used by Slot Upgrades.
function Win.Build()
	if state.building then state.building:Cancel() end
	Win.DropAll()
	state.building, state.model, state.groups = nil, nil, nil
	ns.Sources.lastError = nil
	local env, why = Win.Env()
	state.why = why
	if not env then return Win.Refresh() end
	local handle, ended -- ended: done or failed (perhaps at once, inside Start)
	handle = ns.Browser.Start(env, function(model)
		ended = true
		if state.building ~= handle then return end
		state.model, state.building, state.stale = model, nil, false
		Win.Refresh()
	end, nil, function()
		ended = true
		if state.building ~= handle then return end
		state.building = nil -- stale stays true: reopening tries again
		state.why = "The upgrade list could not be built (the error was reported); close and reopen to try again."
		Win.Refresh()
	end)
	if not ended then state.building = handle end
	Win.Refresh()
end

function Win.ShowAll(key)
	Win.DropAll()
	local env, why = Win.Env()
	if not env then
		state.allWhy = why
		return Win.Refresh()
	end
	local handle, ended -- ended: done or failed (perhaps at once, inside Start)
	handle = ns.Browser.Start(env, function(rows)
		ended = true
		if state.allBuilding ~= handle then return end
		state.all, state.allBuilding = { key = key, rows = rows }, nil
		Win.Refresh()
	end, function(e, yield) return ns.Browser.SlotAll(e, key, yield) end, function()
		ended = true
		if state.allBuilding ~= handle then return end
		state.allBuilding = nil -- "Show all (N)" again: the error went to the client's handler
		state.allWhy = "could not be scored (error reported)"
		Win.Refresh()
	end)
	if not ended then state.allBuilding = handle end
	Win.Refresh()
end


function Win.SetAhead(a)
	ns.Options.View().ahead = a
	state.groups = nil -- the Sources tab regroups for the new look ahead
	Win.Refresh()
end

function Win.AheadText(a, level)
	if a == 0 then return "Now" end
	return format("+%d level%s (%d)", a, a == 1 and "" or "s", math.min(60, level + a))
end
function Win.AheadList()
	local ctx = ns.Context.Get()
	local out = {}
	for a = 0, ns.Options.AHEAD_MAX do out[#out + 1] = { value = a, text = Win.AheadText(a, ctx and ctx.level or 1) } end
	return out
end

function Win.CreateHeader(f)
	local h = {}
	f.header = h
	local c1 = S.Panel(f, 12, -52, 220, 62)
	h.classIcon = c1:CreateTexture(nil, "ARTWORK")
	h.classIcon:SetSize(44, 44)
	h.classIcon:SetPoint("TOPLEFT", 8, -9)
	h.classIcon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
	h.who = S.Text(c1, 15, C.white)
	h.who:SetPoint("TOPLEFT", 60, -14)
	h.spec = S.Text(c1, 13, C.sub)
	h.spec:SetPoint("TOPLEFT", 60, -34)
	local c2 = S.Panel(f, 240, -52, 112, 62)
	local l2 = S.Text(c2, 11, C.label)
	l2:SetPoint("TOP", 0, -6)
	l2:SetText("Gear score")
	h.score = S.Text(c2, 20, C.green)
	h.score:SetPoint("TOP", 0, -26)
	c2:EnableMouse(true)
	c2:SetScript("OnEnter", function(self)
		local ctx = ns.Context.Get()
		if not ctx then return end
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine("Gear score", 1, 1, 1)
		GameTooltip:AddLine(format("The sum of what you wear, in points of %s (weights of levels %d-%d).",
			ns.DATA.statLabels[ctx.ref] or ctx.ref, ctx.lo, ctx.band.upTo), 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	c2:SetScript("OnLeave", GameTooltip_Hide)
	local c3 = S.Panel(f, 360, -52, 236, 62)
	local l3 = S.Text(c3, 11, C.label)
	l3:SetPoint("TOPLEFT", 8, -6)
	l3:SetText("Gear plan progress")
	h.track = CreateFrame("Frame", nil, c3)
	h.track:SetPoint("TOPLEFT", 10, -30)
	h.track:SetSize(150, 14)
	S.Fill(h.track, C.barTrack)
	S.Border(h.track, C.inner)
	h.fill = h.track:CreateTexture(nil, "ARTWORK")
	h.fill:SetPoint("TOPLEFT")
	h.fill:SetHeight(14)
	h.fill:SetColorTexture(C.barFill[1], C.barFill[2], C.barFill[3], 1)
	h.progress = S.Text(c3, 12, C.white)
	h.progress:SetPoint("TOPLEFT", 168, -31)
	c3:EnableMouse(true)
	c3:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine("Gear plan progress", 1, 1, 1)
		GameTooltip:AddLine("A slot is done when you wear its plan item or nothing from the ticked sources is better now.", 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	c3:SetScript("OnLeave", GameTooltip_Hide)
	local c4 = S.Panel(f, 604, -52, 164, 62)
	local l4 = S.Text(c4, 11, C.label)
	l4:SetPoint("TOPLEFT", 8, -6)
	l4:SetText("Look ahead")
	h.ahead = S.Dropdown(c4, 146, 24, Win.AheadList, function(a) return ns.Options.View().ahead == a end, Win.SetAhead)
	h.ahead:SetPoint("TOPLEFT", 8, -28)
end

function Win.UpdateHeader(f, ctx)
	local h = f.header
	if not ctx then
		h.who:SetText(""); h.spec:SetText(""); h.score:SetText(""); h.progress:SetText(""); h.fill:Hide()
		return
	end
	local className, file = UnitClass("player")
	local tc = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[file or ""]
	if tc then h.classIcon:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) end
	h.who:SetText(format("Level %d %s", ctx.level, className or ""))
	h.spec:SetText(S.Title(ctx.spec) .. (ctx.specSource == "chosen" and "" or " (auto)"))
	h.score:SetText(S.Thousands(ns.Browser.GearScore(ctx.worn)))
	if state.model then
		local done, total = ns.View.Progress(state.model, ctx.worn, Win.St())
		h.fill:SetShown(done > 0)
		h.fill:SetWidth(math.max(1, 150 * done / total))
		h.progress:SetText(format("%d / %d (%d%%)", done, total, math.floor(100 * done / total + 0.5)))
	else
		h.fill:Hide()
		h.progress:SetText(state.building and "scoring..." or "")
	end
	h.ahead:Update()
end

function Win.Toggle()
	if not ns.Context.ClassKey() then return ns.Print("no weights for this class yet (Priest only for now)") end
	if not frame then create() end
	frame:SetShown(not frame:IsShown())
end

local function rebuild()
	state.stale = true
	if frame and frame:IsShown() then Win.Build() end
end
ns.On("SCORES_CHANGED", rebuild)
ns.On("ROUTE_CHANGED", rebuild)
local function redraw() Win.Refresh() end
ns.On("PLAN_CHANGED", redraw)
ns.On("WISHLIST_CHANGED", redraw)
ns.On("OPTIONS", redraw)
-- A quest turned in (QUEST_TURNED_IN, QuestLogDocumentation in the Forever 1.60.1 UI source) takes its
-- rewards off the list: one rebuild a moment later for a burst of turn-ins (the completion flag is set
-- by then), only while the window is shown (closed, it builds again when opened).
Win.TURNIN_DELAY = 1
local turninQueued = false
ns.RegisterEvent("QUEST_TURNED_IN", function()
	if turninQueued or not (frame and frame:IsShown()) then return end
	turninQueued = true
	C_Timer.After(Win.TURNIN_DELAY, function()
		turninQueued = false
		if frame and frame:IsShown() then Win.Build() end
	end)
end)
ns.Slash("", Win.Toggle)
function PoleSimGear_OnAddonCompartmentClick() Win.Toggle() end
