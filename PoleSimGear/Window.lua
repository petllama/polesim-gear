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
-- keep: the items the model was built to keep (Win.Keep at build time, plus kept rows found in it)
-- pending: picks/stars made while the first model was building (its keep lacks them): checked when it ends
local state = { model = nil, building = nil, stale = true, why = nil, groups = nil, slot = "head", all = nil,
	allBuilding = nil, allWhy = nil, codex = nil, keep = nil, pending = nil }
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

-- the tab's buttons and panel (made on its first show), no redraw
local function showTab(key)
	if not Win.TABS_BY[key] then return false end
	ns.Options.View().tab = key
	if not frame then return false end
	for k, b in pairs(frame.tabs) do S.SetColours(b, k == key and S.TAB_ON or S.TAB) end
	if not panels[key] then
		-- a tab whose file is not there yet (a later phase) gets an empty panel
		panels[key] = tabDefs[key] and tabDefs[key].create(frame.content) or CreateFrame("Frame", nil, frame.content)
		panels[key]:SetAllPoints(frame.content)
		local def = tabDefs[key]
		if def and def.layout then def.layout(panels[key], frame.content:GetWidth(), frame.content:GetHeight()) end
	end
	for k, p in pairs(panels) do p:SetShown(k == key) end
	return true
end
function Win.SetTab(key)
	if showTab(key) then Win.Refresh() end
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
	state.building, state.model, state.stale, state.groups, state.codex, state.keep, state.pending = nil, nil, true, nil, nil, nil, nil
	Win.badges = nil -- the strip's plan entries (they hold the model)
	Win.ReleaseItemTip() -- a row tooltip's redraw (it holds the row's data)
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

-- The largest size: the screen (UIParent), when the client says it.
function Win.MaxSize()
	local w, h = UIParent:GetWidth(), UIParent:GetHeight()
	if not (type(w) == "number" and w > 0 and type(h) == "number" and h > 0) then return nil, nil end
	return math.max(S.MIN_W, math.floor(w)), math.max(S.MIN_H, math.floor(h))
end
-- a size within the bounds (the saved one may come from a larger screen or an older save)
function Win.ClampSize(w, h)
	local mw, mh = Win.MaxSize()
	w = math.max(S.MIN_W, tonumber(w) or S.W)
	h = math.max(S.MIN_H, tonumber(h) or S.H)
	if mw then w, h = math.min(w, mw), math.min(h, mh) end
	return math.floor(w + 0.5), math.floor(h + 0.5)
end
-- Save the window's place and size per account: { point, relPoint, x, y, w, h }.
function Win.SavePlace()
	if not (ns.db and frame) then return end
	local p, _, rel, x, y = frame:GetPoint(1)
	local old = type(ns.db.window) == "table" and ns.db.window or {}
	local w, h = frame:GetWidth(), frame:GetHeight()
	ns.db.window = { point = p or old.point, relPoint = rel or p or old.relPoint, x = p and x or old.x, y = p and y or old.y,
		w = (w and w > 0) and math.floor(w + 0.5) or old.w, h = (h and h > 0) and math.floor(h + 0.5) or old.h }
end

local function create()
	frame = CreateFrame("Frame", "PoleSimGearFrame", UIParent)
	-- saved { point, relPoint, x, y, w, h } (an older save has no relPoint: relative to the same point;
	-- no size: the default)
	local pos = ns.db and type(ns.db.window) == "table" and ns.db.window
	frame:SetSize(Win.ClampSize(pos and pos.w or S.W, pos and pos.h or S.H))
	if pos and type(pos.point) == "string" then
		if type(pos.relPoint) ~= "string" then pos.relPoint = pos.point end
		frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x or 0, pos.y or 0)
	else
		frame:SetPoint("CENTER")
	end
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:SetResizable(true)
	frame:SetResizeBounds(S.MIN_W, S.MIN_H, Win.MaxSize())
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
		Win.SavePlace()
	end)
	local icon = bar:CreateTexture(nil, "ARTWORK")
	icon:SetSize(36, 36)
	icon:SetPoint("TOPLEFT", 12, -5)
	icon:SetTexture(ns.Minimap and ns.Minimap.ICON or "Interface\\Icons\\INV_Chest_Cloth_17")
	frame.iconFrame = S.Frame(bar, icon, C.gold)
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
	-- the resize grip (the chat frame's size grabber), bottom right
	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -2, 2)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetScript("OnMouseDown", function(_, button)
		if button == "LeftButton" then frame:StartSizing("BOTTOMRIGHT") end
	end)
	grip:SetScript("OnMouseUp", function()
		frame:StopMovingOrSizing()
		Win.SavePlace()
	end)
	frame.grip = grip
	frame:SetScript("OnSizeChanged", function(_, w, h) Win.Layout(w, h) end)
	Win.Layout(frame:GetWidth(), frame:GetHeight())
	frame:Hide() -- a new frame is shown: hidden first, so the first toggle shows it (and OnShow runs)
	frame:SetScript("OnShow", function()
		showTab(ns.Options.View().tab) -- one redraw: Build's (or Refresh's)
		if state.stale then Win.Build() else Win.Refresh() end
	end)
	frame:SetScript("OnHide", release)
	Win.frame = frame
end

-- This redraw's View.PlanEntries by show mode (the strip and the Gear Plan tab share one pass).
local pass
function Win.PlanEntries(show)
	local ctx = ns.Context.Get()
	if not (ctx and state.model) then return nil end
	if pass and pass[show] then return pass[show] end
	local st = Win.St()
	st.show = show
	local es = ns.View.PlanEntries(state.model, ctx.worn, st)
	if pass then pass[show] = es end
	return es
end

-- shown and visible (Alt+Z hides UIParent: no work then; OnShow builds again)
local function visible() return frame ~= nil and frame:IsVisible() end

local function redrawAll()
	local ctx = ns.Context.Get()
	if Win.UpdateHeader then Win.UpdateHeader(frame, ctx) end
	if Win.UpdateLeft then Win.UpdateLeft(frame) end
	if Win.UpdateBottom then Win.UpdateBottom(frame, ctx) end
	local key = ns.Options.View().tab
	local p, def = panels[key], tabDefs[key]
	if p and def and def.refresh then def.refresh(p) end
end
-- One redraw; the plan pass lives only during it (dropped even when a part errors; the error goes on).
function Win.Refresh()
	if not visible() then return end
	pass = {}
	local ok, err = pcall(redrawAll)
	pass = nil
	if not ok then error(err, 0) end
end

-- Build/ShowAll: the 0.1.0 browser window's Build and ShowAll (Build also drops the Sources grouping).
-- ShowAll(key) is used by Slot Upgrades.
-- soft: the scores did not change (a pick or star the model lacks): the old model, its grouping and
-- Show all stay shown until the new model is there.
function Win.Build(soft)
	if state.building then state.building:Cancel() end
	if not soft then
		Win.DropAll()
		state.model, state.groups = nil, nil
	end
	state.building, state.pending = nil, nil -- (this build's keep has every pick and star made so far)
	ns.Sources.lastError = nil
	local env, why = Win.Env()
	state.why = why
	if not env then
		state.model, state.groups = nil, nil
		return Win.Refresh()
	end
	local handle, ended -- ended: done or failed (perhaps at once, inside Start)
	handle = ns.Browser.Start(env, function(model)
		ended = true
		if state.building ~= handle then return end
		state.model, state.building, state.stale, state.groups, state.keep = model, nil, false, nil, env.keep
		if Win.KeepPending() then return end
		Win.Refresh()
	end, nil, function()
		ended = true
		if state.building ~= handle then return end
		state.building = nil -- stale stays true: reopening tries again
		state.why = "The upgrade list could not be built (the error was reported); close and reopen to try again."
		Win.Refresh()
	end)
	if ended then return end -- done or failed at once: already redrawn
	state.building = handle
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

-- Everything at the window's size W x H (on create and OnSizeChanged): the title bar, the header
-- cards (the progress card takes the width), the content area and its tabs, the bottom strip (the
-- equipped icons grow with it, the weights card keeps the right edge).
function Win.Layout(W, H)
	local f = frame
	if not (f and W and H and W > 0 and H > 0) then return end
	f.bar:SetWidth(W)
	local h = f.header
	if h then
		local w3 = W - 544
		h.c3:SetWidth(w3)
		h.trackW = w3 - 112
		h.track:SetWidth(h.trackW)
		S.Place(h.progress, "TOPLEFT", 10 + h.trackW + 8, -31, w3 - (10 + h.trackW + 8) - 6)
		S.Place(h.c4, "TOPLEFT", W - 176, -52)
		if h.fill:IsShown() and h.done then h.fill:SetWidth(math.max(1, h.trackW * h.done)) end
	end
	local A = S.Content(W, H)
	S.Place(f.content, "TOPLEFT", A.x, A.y)
	f.content:SetSize(A.w, A.h)
	for key, p in pairs(panels) do
		local def = tabDefs[key]
		if def and def.layout then def.layout(p, A.w, A.h) end
	end
	if f.eq then
		local y = -(H - 100)
		local eqW = W - 24 - 8 - Win.WEIGHTS_W
		S.Place(f.eq, "TOPLEFT", 12, y)
		f.eq:SetSize(eqW, 88)
		S.Place(f.wc, "TOPLEFT", W - 12 - Win.WEIGHTS_W, y)
		f.wc:SetSize(Win.WEIGHTS_W, 88)
		local step = math.floor((eqW - 16) / #f.slots)
		local size = math.min(32, step - 2)
		for i, b in ipairs(f.slots) do
			S.Place(b, "TOPLEFT", 8 + (i - 1) * step, -26)
			b:SetSize(size, size)
		end
	end
end

function Win.CreateHeader(f)
	local h = {}
	f.header = h
	local c1 = S.Panel(f, 12, -52, 220, 62)
	h.classIcon = c1:CreateTexture(nil, "ARTWORK")
	h.classIcon:SetSize(44, 44)
	h.classIcon:SetPoint("TOPLEFT", 8, -9)
	h.classIcon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
	h.classFrame = S.Frame(c1, h.classIcon, C.gold)
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
	h.c3 = c3
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
	h.progress = S.Text(c3, 11, C.white)
	h.trackW = 150
	c3:EnableMouse(true)
	c3:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine("Gear plan progress", 1, 1, 1)
		GameTooltip:AddLine("A slot is done when you wear its plan item or nothing from the ticked sources is better now.", 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	c3:SetScript("OnLeave", GameTooltip_Hide)
	local c4 = S.Panel(f, 604, -52, 164, 62)
	h.c4 = c4
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
		h.done = done / total
		h.fill:SetWidth(math.max(1, h.trackW * h.done))
		h.progress:SetText(format("%d / %d (%d%%)", done, total, math.floor(100 * done / total + 0.5)))
	else
		h.fill:Hide()
		h.progress:SetText(state.building and "scoring..." or "")
	end
	h.ahead:Update()
end

Win.KIND_ROWS = { { "quest", "Quests" }, { "dungeon", "Dungeons" }, { "crafted", "Crafting" }, { "vendor", "Vendor" }, { "world", "BoE / World" } }
Win.SHOW_ROWS = { { "all", "All gear" }, { "upgrades", "Upgrades only" }, { "wishlist", "Wishlist" } }
function Win.CreateLeft(f)
	local box = S.Panel(f, 12, -122, 122, 160)
	local t = S.Text(box, 13, C.white)
	t:SetPoint("TOPLEFT", 8, -8)
	t:SetText("Sources")
	f.checks = {}
	for i, k in ipairs(Win.KIND_ROWS) do
		local b = S.Check(box, k[2], function(on)
			ns.Options.View().filters[k[1]] = on
			Win.Refresh()
		end)
		b:SetPoint("TOPLEFT", 8, -30 - (i - 1) * 24)
		b.kind = k[1]
		f.checks[i] = b
	end
	local box2 = S.Panel(f, 12, -290, 122, 100)
	local t2 = S.Text(box2, 13, C.white)
	t2:SetPoint("TOPLEFT", 8, -8)
	t2:SetText("Show")
	f.radios = {}
	for i, k in ipairs(Win.SHOW_ROWS) do
		local b = S.Radio(box2, k[2], function()
			ns.Options.View().show = k[1]
			Win.Refresh()
		end)
		b:SetPoint("TOPLEFT", 4, -28 - (i - 1) * 22)
		b.show = k[1]
		f.radios[i] = b
	end
end
function Win.UpdateLeft(f)
	local v = ns.Options.View()
	for _, b in ipairs(f.checks) do b:Set(v.filters[b.kind]) end
	for _, b in ipairs(f.radios) do b:Set(v.show == b.show) end
end

Win.EQUIP_SLOTS = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }
Win.WEIGHTS_W = 320 -- the weights card (two values a line); the equipped strip takes the rest
-- An empty slot's own art (C_PaperDollInfo.GetInventorySlotInfoForInvSlot's slotTexture, a fileID),
-- else the backpack's empty slot.
function Win.EmptySlotArt(slot)
	local P = C_PaperDollInfo
	if P and P.GetInventorySlotInfoForInvSlot then
		local ok, _, tex = pcall(P.GetInventorySlotInfoForInvSlot, slot)
		if ok and tex then return tex end
	end
	return "Interface\\PaperDoll\\UI-Backpack-EmptySlot"
end
-- The equipped-slot tooltip's plan line: -> text, r, g, b | nil (no model yet)
function Win.SlotPlanLine(slot)
	local info = Win.badges and Win.badges[slot]
	if not Win.badges then return nil end
	if not info then return "No upgrade from the ticked sources", 0.6, 0.6, 0.6 end
	local entry = info.entry
	local r = entry.plan
	local what = r and (r.c.inst.name or "?") .. " " .. S.Signed(r.gain)
		or ((entry.missing and ns.View.Inst(entry.missing.id, entry.missing.bonus).name or "?") .. " (not available now)")
	if entry.isPick then return "Your pick: " .. what, C.pick[1], C.pick[2], C.pick[3] end
	return "Suggested upgrade: " .. what, C.green[1], C.green[2], C.green[3]
end
function Win.CreateBottom(f)
	local eq = S.Panel(f, 12, -400, 470, 88)
	f.eq = eq
	f.eqTitle = S.Text(eq, 12, C.white)
	f.eqTitle:SetPoint("TOPLEFT", 8, -6)
	-- the legend of the dots on the icons (textures: the client font may not have a round dot)
	f.legend = {}
	local x = 8
	for _, l in ipairs({ { C.green, "suggested upgrade" }, { C.pick, "your pick" } }) do
		local dot = S.Dot(eq, 8, l[1])
		dot:SetPoint("TOPLEFT", x, -70)
		local t = S.Text(eq, 10, C.label)
		t:SetPoint("TOPLEFT", x + 11, -68)
		t:SetText(l[2])
		f.legend[#f.legend + 1] = t
		x = x + 11 + (l[2] == "your pick" and 60 or 104) + 10
	end
	f.slots = {}
	for i, slot in ipairs(Win.EQUIP_SLOTS) do
		local b = CreateFrame("Button", nil, eq)
		b:SetSize(24, 24)
		b:SetPoint("TOPLEFT", 8 + (i - 1) * 26, -26)
		b.slot = slot
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetAllPoints()
		b.border = S.Border(b, C.cardBorder)
		b.badge = S.Dot(b, 10)
		b.badge:SetPoint("TOPRIGHT", 3, 3)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetInventoryItem("player", self.slot)
			local line, r, g, bl = Win.SlotPlanLine(self.slot)
			if line then GameTooltip:AddLine(line, r, g, bl, true) end
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", GameTooltip_Hide)
		f.slots[i] = b
	end
	local wc = S.Panel(f, 490, -400, Win.WEIGHTS_W, 88)
	f.wc = wc
	f.wTitle = S.Text(wc, 12, C.white)
	f.wTitle:SetPoint("TOPLEFT", 8, -6)
	-- the top four weights, two a line: name (short) and value
	f.wCells = {}
	local cw = (Win.WEIGHTS_W - 24) / 2
	for i = 1, 4 do
		local col, line = (i - 1) % 2, math.floor((i - 1) / 2)
		local cx, cy = 8 + col * (cw + 8), -28 - line * 17
		local name = S.Text(wc, 11, C.white)
		name:SetPoint("TOPLEFT", cx, cy)
		name:SetWidth(cw - 40)
		local value = S.Text(wc, 11, C.green)
		value:SetPoint("TOPLEFT", cx + cw - 38, cy)
		value:SetWidth(38)
		value:SetJustifyH("RIGHT")
		f.wCells[i] = { name = name, value = value }
	end
	f.wSub = S.Text(wc, 10, C.label)
	f.wSub:SetPoint("TOPLEFT", 8, -66)
	f.wSub:SetWidth(Win.WEIGHTS_W - 16)
	f.pencil = S.Button(wc, "", 20, 20, function() Win.SetTab("weights") end, S.ACTION)
	f.pencil:SetPoint("TOPRIGHT", -6, -6)
	f.pencil.tip = "Weights and spec"
	local pen = f.pencil:CreateTexture(nil, "OVERLAY")
	pen:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
	pen:SetSize(14, 14)
	pen:SetPoint("CENTER")
end

function Win.UpdateBottom(f, ctx)
	local n = 0
	local badges = {}
	Win.badges = nil
	if ctx and state.model then
		-- the Gear Plan's own pass (All gear adds only slots without a plan); Wishlist lists stars
		local show = ns.Options.View().show
		local entries
		badges, entries = ns.View.BadgeSlots(Win.PlanEntries(show == "all" and "all" or "upgrades"), ctx.worn)
		Win.badges = entries
	end
	for _, b in ipairs(f.slots) do
		local link = GetInventoryItemLink("player", b.slot)
		if link then n = n + 1 end
		b.icon:SetTexture(link and GetInventoryItemTexture("player", b.slot) or Win.EmptySlotArt(b.slot))
		local q = link and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[GetInventoryItemQuality("player", b.slot) or 1]
		S.SetBorder(b.border, q and q.r and { q.r, q.g, q.b } or C.cardBorder)
		local kind = badges[b.slot]
		local c = kind == "pick" and C.pick or C.green
		b.badge:SetVertexColor(c[1], c[2], c[3], 1)
		b.badge:SetShown(kind ~= nil)
	end
	f.eqTitle:SetText(format("Equipped gear (%d)", n))
	for _, cell in ipairs(f.wCells) do cell.name:SetText(""); cell.value:SetText("") end
	if not ctx then
		f.wTitle:SetText("Stat weights"); f.wSub:SetText("")
		return
	end
	f.wTitle:SetText("Stat weights (" .. S.Title(ctx.spec) .. ")")
	for i, w in ipairs(ns.View.WeightRows(ctx.w, 4)) do
		f.wCells[i].name:SetText(S.STAT_SHORT[w.key] or w.label)
		f.wCells[i].value:SetText(format("%.2f", w.value))
	end
	f.wSub:SetText(format("levels %d-%d, points of %s", ctx.lo, ctx.band.upTo, ns.DATA.statLabels[ctx.ref] or ctx.ref))
end

-- The link the game's tooltip shows for an item row's instance: a worn item's own link, else the item
-- with its random suffix. Forever's suffixes are item bonus lists (ItemBonusListID, armory data), so the
-- suffix goes in the link's bonus-ID list: count (field 13 after "item:") 1, then the id (Live.Bonus).
function Win.ItemLink(inst)
	if type(inst.link) == "string" and inst.link ~= "" then return inst.link end
	if inst.bonus then return "item:" .. inst.id .. string.rep(":", 12) .. "1:" .. inst.bonus end
	return "item:" .. inst.id
end

-- Shift (COMPAREITEMS) held: the client's comparison tooltips, as on its own item tooltips.
local function comparing() return IsModifiedClick and IsModifiedClick("COMPAREITEMS") and true or false end

-- An item tooltip owned by a window row: the game's tooltip for the item, then draw() adds the
-- window's lines. How to draw it again is kept while it shows (tip; let go when the tooltip hides or
-- the window closes, as it holds the row's model data): when the item's data arrives
-- (GET_ITEM_INFO_RECEIVED) and when Shift changes (the client calls owner:UpdateTooltip while shown;
-- having one also keeps the client from rebuilding the tooltip without our lines). owner.psgItemTip
-- tells the item post-call hook (Tooltip.lua) not to add its own score lines.
local tip, hookedTip = nil, nil
function Win.ReleaseItemTip() tip = nil end
local function drawTip(t)
	t.compare = comparing()
	GameTooltip:SetOwner(t.owner, "ANCHOR_RIGHT")
	tip = t -- after SetOwner (it may hide the tooltip)
	GameTooltip:SetHyperlink(t.link)
	GameTooltip:AddLine(" ")
	t.draw()
	GameTooltip:Show()
	if t.compare and GameTooltip_ShowCompareItem then GameTooltip_ShowCompareItem(GameTooltip) end
end
function Win.ItemTip(owner, inst, draw)
	if hookedTip ~= GameTooltip and GameTooltip.HookScript then
		hookedTip = GameTooltip
		GameTooltip:HookScript("OnHide", Win.ReleaseItemTip)
	end
	owner.psgItemTip = true
	owner.UpdateTooltip = Win.UpdateItemTip
	drawTip({ owner = owner, id = inst.id, link = Win.ItemLink(inst), draw = draw })
end
-- the kept tooltip when the owner still shows it
local function shown(owner)
	if tip and owner ~= nil and tip.owner == owner and GameTooltip.GetOwner and GameTooltip:GetOwner() == owner then return tip end
end
function Win.UpdateItemTip(owner)
	local t = shown(owner)
	if t and t.compare ~= comparing() then drawTip(t) end
end
ns.RegisterEvent("GET_ITEM_INFO_RECEIVED", function(id)
	local t = shown(GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner())
	if t and t.id == id then drawTip(t) end
end)

-- extra (optional): a line or a list of lines in gold above the hint (Gear Plan: "Better: <item> +N"
-- on a pick; Sources: the place's other sources)
function Win.RowTooltip(owner, r, hint, extra)
	if not (r and r.c) then return end
	local ctx = ns.Context.Get()
	if not ctx then return end
	-- a coming level's band; none (no weights there): no "how?" rather than another band's weights
	local band
	if r.at then band = ns.Context.At(r.at) else band = ctx end
	local inst = r.c.inst
	Win.ItemTip(owner, inst, function() Win.RowLines(r, ctx, band, hint, extra) end)
end

-- The window's lines of an item row's tooltip (below the game's item tooltip).
function Win.RowLines(r, ctx, band, hint, extra)
	local inst = r.c.inst
	if inst.suffix then GameTooltip:AddLine("scored with its best suffix for this spec: " .. inst.suffix, 0.6, 0.6, 0.6) end
	GameTooltip:AddDoubleLine("Score", format("%.2f", r.c.score), 1, 0.82, 0, 1, 1, 1)
	local role = inst.inv == 17 and "mh" or (ns.Equip.ROLE_OF_SLOT[r.slot.slot] or "gear")
	for _, p in ipairs(band and ns.Score.Parts(inst, band.w, ctx.cls, role) or {}) do
		local name = (ns.DATA.statLabels[p[1]] or p[1]) .. (p[1] ~= p[3] and (" as " .. (ns.DATA.statLabels[p[3]] or p[3])) or "")
		GameTooltip:AddDoubleLine(format("  %s %g x %g", name, p[2], p[4]), format("%.2f", p[5]), 0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
	end
	GameTooltip:AddDoubleLine("Gain over what you wear", format("%+.2f", r.gain) .. (r.base and r.base > 0.01
		and format(" (%s)", ns.Style.Pct(r.gain, r.base)) or ""), 1, 1, 1, 0.3, 1, 0.3)
	if r.at and band then GameTooltip:AddLine(format("level %d item: scored with the weights of levels %d-%d", r.at, band.lo, band.band.upTo), 0.6, 0.6, 0.6, true) end
	if r.note then GameTooltip:AddLine(r.note, 0.6, 0.6, 0.6, true) end
	local pick = ns.Plan.Get(ctx.spec, r.slot.key)
	if pick and pick == ns.Browser.KeyOf(r.c.inst) then GameTooltip:AddLine("Your pick for " .. r.slot.label, 1, 0.82, 0) end
	if ns.Wishlist.Has(r.c.inst) then GameTooltip:AddLine("|A:auctionhouse-icon-favorite:12:12|a On your wishlist", 1, 0.82, 0) end
	GameTooltip:AddLine(" ")
	for _, s in ipairs(r.c.sources) do
		local where = s.where
		if not where and s.zoneId and state.codex and type(state.codex.Zone) == "function" then
			local ok, z = pcall(state.codex.Zone, s.zoneId)
			where = ok and type(z) == "table" and z.name or nil
		end
		GameTooltip:AddLine(s.text .. (where and (", " .. where) or ""), 1, 1, 1, true)
		if s.cost then GameTooltip:AddLine("  " .. ns.Style.Money(s.cost), 0.8, 0.8, 0.8) end
		if s.needs then GameTooltip:AddLine("  needs: " .. s.needs .. " first", 1, 0.5, 0.3, true) end
		if s.route then GameTooltip:AddLine(format("  on your route (Polestar guide step %d)", s.route), 0.3, 0.8, 1, true) end
	end
	if type(extra) == "string" then extra = { extra } end
	for _, line in ipairs(extra or {}) do GameTooltip:AddLine(line, 1, 0.82, 0, true) end
	if hint then GameTooltip:AddLine(hint, 0.6, 0.6, 0.6, true) end
end

-- The "Set as plan" button of an upgrade row d ({ c, slot }) in Slot Upgrades and Sources: its label
-- (the pick's own row says "Your pick", the suggestion "Suggested" when first) and its click.
function Win.PlanLabel(btn, d, first)
	local ctx = ns.Context.Get()
	local pick = ctx and ns.Plan.Get(ctx.spec, d.slot.key)
	if pick and pick == ns.Browser.KeyOf(d.c.inst) then
		btn.label:SetText(S.Colour(C.pick) .. "Your pick|r")
		btn.tip = "Click: back to the suggestion"
	elseif not pick and first then
		btn.label:SetText("Suggested")
		btn.tip = "The best upgrade: the plan unless you pick another"
	else
		btn.label:SetText("Set as plan")
		btn.tip = nil
	end
end
-- Set an upgrade row d ({ c, slot }) as the slot's plan, or back to the suggestion when it already is
-- (Gear Plan's wishlist rows, Slot Upgrades, Sources).
function Win.PlanAction(d)
	local ctx = ns.Context.Get()
	if not (d and d.c and ctx) then return end
	if ns.Plan.Get(ctx.spec, d.slot.key) == ns.Browser.KeyOf(d.c.inst) then
		ns.Plan.Clear(ctx.spec, d.slot.key)
	else
		ns.Plan.Set(ctx.spec, d.slot.key, d.c.inst)
	end
end

function Win.Toggle()
	if not ns.Context.ClassKey() then return ns.Print("no weights for this class yet (Priest only for now)") end
	if not frame then create() end
	frame:SetShown(not frame:IsShown())
end

local function rebuild()
	state.stale = true
	if visible() then Win.Build() end
end
ns.On("SCORES_CHANGED", rebuild)
ns.On("ROUTE_CHANGED", rebuild)
local function redraw() Win.Refresh() end

-- Whether the model holds item key k (any slot, now or coming).
local function modelHas(k)
	local m = state.model
	for _, def in ipairs(ns.Browser.SLOTS) do
		for _, list in ipairs({ m.now[def.key] or {}, (m.coming or {})[def.key] or {} }) do
			for _, r in ipairs(list) do
				if ns.Browser.KeyOf(r.c.inst) == k then return true end
			end
		end
	end
	return false
end
-- A pick or star the model was not built to keep: in it anyway (redraw), else build again keeping it
-- (a Show all row the trim left out would show as "not available").
local function kept(k)
	if k and state.building and not state.model then
		-- the first build started without it: checked when that build ends (Win.KeepPending)
		state.pending = state.pending or {}
		state.pending[k] = true
		return redraw()
	end
	if not (k and state.model and state.keep) or state.keep[k] then return redraw() end
	if modelHas(k) then
		state.keep[k] = true
		return redraw()
	end
	state.stale = true
	if visible() then Win.Build(true) end
end
-- After a build: a pick or star made during it that is still wanted and not in the model marks the
-- model stale and builds again (the new model stays shown meanwhile) -> true when building again.
function Win.KeepPending()
	local pending = state.pending
	state.pending = nil
	if not (pending and state.model) then return false end
	local ctx = ns.Context.Get()
	local want = ctx and Win.Keep(ctx.spec) or {}
	for k in pairs(pending) do
		if want[k] and not state.keep[k] then
			if not modelHas(k) then
				state.stale = true
				Win.Build(true)
				return true
			end
			state.keep[k] = true
		end
	end
	return false
end
ns.On("PLAN_CHANGED", function(spec, key)
	local ctx = ns.Context.Get()
	if spec and key and ctx and spec == ctx.spec then return kept(ns.Plan.Get(spec, key)) end
	redraw()
end)
ns.On("WISHLIST_CHANGED", function(k)
	local id, bonus = ns.Plan.Parse(k)
	if id and ns.Wishlist.Has({ id = id, bonus = bonus }) then return kept(k) end
	redraw()
end)
ns.On("OPTIONS", redraw)
-- A quest turned in (QUEST_TURNED_IN, QuestLogDocumentation in the Forever 1.60.1 UI source) takes its
-- rewards off the list: one rebuild a moment later for a burst of turn-ins (the completion flag is set
-- by then), only while the window is shown (closed, it builds again when opened).
Win.TURNIN_DELAY = 1
local turninQueued = false
ns.RegisterEvent("QUEST_TURNED_IN", function()
	if turninQueued or not visible() then return end
	turninQueued = true
	C_Timer.After(Win.TURNIN_DELAY, function()
		turninQueued = false
		if visible() then Win.Build() else state.stale = true end
	end)
end)
ns.Slash("", Win.Toggle)
function PoleSimGear_OnAddonCompartmentClick() Win.Toggle() end
