-- The upgrade browser window (layout B). Draws Browser's model; never scores anything itself.
local ADDON, ns = ...
local UI = {}
ns.BrowserUI = UI

local FILTERS = { { "all", "All" }, { "quest", "Quests" }, { "dungeon", "Dungeons" }, { "crafted", "Crafted" } }
local KIND_TAG = { quest = "Quest", dungeon = "Dungeon", crafted = "Crafted" }
-- all: { key, rows } every upgrade of the drilled-into slot ("Show all"), allBuilding its build
local state = { filter = "all", slot = nil, model = nil, building = nil, stale = true, why = nil, all = nil, allBuilding = nil }
local frame
local format = string.format

local function title(s) return (s:gsub("^%l", string.upper)) end
local function itemText(inst)
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[inst.quality or 1]
	return (c and c.hex or "|cffffffff") .. inst.name .. "|r"
end
local function tagOf(c)
	for _, k in ipairs({ "quest", "dungeon", "crafted" }) do
		if c.kinds[k] then return KIND_TAG[k] end
	end
	return ""
end
local function onRoute(c)
	for _, s in ipairs(c.sources) do
		if s.route then return true end
	end
	return false
end

-- Polestar's Codex, its pack loaded (Codex.Load: the load-on-demand Polestar_Codex). -> codex | nil, why
local function codex()
	local C = ns.Sources.Codex()
	if not C then return nil, "Polestar's Codex is not available: is Polestar enabled?" end
	if type(C.Load) == "function" then
		local ok, loaded = pcall(C.Load)
		if not (ok and loaded) then return nil, "Polestar's Codex could not be loaded: is Polestar_Codex enabled?" end
	end
	return C
end

-- The character's data for Browser (Context + Polestar's Codex and quest state). -> env | nil, why
function UI.Env()
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
	return {
		cls = ctx.cls, level = ctx.level, ahead = ns.Browser.AHEAD, codex = C,
		-- decoded on demand, nothing kept (Items.Peek; the index is released when the window closes)
		items = { Get = Items.Peek, ByInv = Items.ByInv, Rl = Items.Rl },
		player = { faction = ctx.faction, classBit = ctx.classBit, raceBit = ctx.raceBit, completed = completed },
		routeStep = ns.Route.StepOf,
		at = function(L)
			local a = ns.Context.At(L)
			if not a then return { w = {}, worn = {}, style = "any" } end
			return { w = a.w, worn = a.worn, style = a.band.style }
		end,
	}
end

local function listData()
	local m = state.model
	if not m then
		return { { header = state.building and "Scoring items..." or (state.why or "Nothing to show") } }
	end
	local out = {}
	if state.slot then
		local key = state.slot.key
		local all = state.all and state.all.key == key and state.all.rows
		out[1] = { header = state.slot.label .. ": every upgrade" }
		local rows = ns.Browser.Rows(all or m.now[key] or {}, state.filter)
		for _, r in ipairs(rows) do
			out[#out + 1] = { c = r.c, gain = r.gain, note = r.note, slot = r.slot, detail = true }
		end
		if #out == 1 then out[2] = { header = "no upgrade from these sources" } end
		-- the model keeps the best KEEP of each kind: the rest on demand
		local total = ns.Browser.Count(m, key, state.filter)
		if not all and total > #rows then
			out[#out + 1] = state.allBuilding and { header = "Scoring every upgrade..." }
				or { header = format("Show all (%d)", total), showAll = true }
		end
		return out
	end
	out[1] = { header = "Best per slot right now" }
	for _, r in ipairs(ns.Browser.Best(m.now, state.filter)) do out[#out + 1] = r end
	if #out == 1 then out[2] = { header = "nothing better than what you wear" } end
	local ctx = ns.Context.Get()
	if ctx and ctx.level < 60 then
		out[#out + 1] = { header = format("Coming up (levels %d-%d)", ctx.level + 1, math.min(60, ctx.level + ns.Browser.AHEAD)) }
		local coming = ns.Browser.Rows(m.coming, state.filter)
		for i = 1, math.min(10, #coming) do out[#out + 1] = coming[i] end
	end
	if ns.Sources.lastError then
		out[#out + 1] = { header = "|cffff8040some sources could not be read from Polestar's Codex|r" }
	end
	return out
end

local function showRowTooltip(row)
	local r = row.data
	if not (r and r.c) then return end
	local ctx = ns.Context.Get()
	if not ctx then return end
	local band = r.at and ns.Context.At(r.at) or ctx
	local inst = r.c.inst
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:AddLine(itemText(inst))
	if inst.suffix then GameTooltip:AddLine("scored with its best suffix for this spec: " .. inst.suffix, 0.6, 0.6, 0.6) end
	GameTooltip:AddDoubleLine("Score", format("%.2f", r.c.score), 1, 0.82, 0, 1, 1, 1)
	local role = inst.inv == 17 and "mh" or (ns.Equip.ROLE_OF_SLOT[r.slot.slot] or "gear")
	for _, p in ipairs(ns.Score.Parts(inst, band.w, ctx.cls, role)) do
		local name = (ns.DATA.statLabels[p[1]] or p[1]) .. (p[1] ~= p[3] and (" as " .. (ns.DATA.statLabels[p[3]] or p[3])) or "")
		GameTooltip:AddDoubleLine(format("  %s %g x %g", name, p[2], p[4]), format("%.2f", p[5]), 0.7, 0.7, 0.7, 0.7, 0.7, 0.7)
	end
	GameTooltip:AddDoubleLine("Gain over what you wear", format("%+.2f", r.gain), 1, 1, 1, 0.3, 1, 0.3)
	if r.at then GameTooltip:AddLine(format("level %d item: scored with the weights of levels %d-%d", r.at, band.lo, band.band.upTo), 0.6, 0.6, 0.6, true) end
	if r.note then GameTooltip:AddLine(r.note, 0.6, 0.6, 0.6, true) end
	GameTooltip:AddLine(" ")
	for _, s in ipairs(r.c.sources) do
		GameTooltip:AddLine(s.text .. (s.where and (", " .. s.where) or ""), 1, 1, 1, true)
		if s.needs then GameTooltip:AddLine("  needs: " .. s.needs .. " first", 1, 0.5, 0.3, true) end
		if s.route then GameTooltip:AddLine(format("  on your route (Polestar guide step %d)", s.route), 0.3, 0.8, 1, true) end
	end
	GameTooltip:Show()
end

local function initRow(row, data)
	row.data = data
	if not row.icon then
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(20, 20)
		row.icon:SetPoint("LEFT", 4, 0)
		local function text(font, x, width)
			local t = row:CreateFontString(nil, "OVERLAY", font)
			t:SetPoint("LEFT", x, 0)
			t:SetWidth(width)
			t:SetJustifyH("LEFT")
			t:SetWordWrap(false)
			return t
		end
		row.slotText = text("GameFontNormalSmall", 28, 78)
		row.name = text("GameFontHighlightSmall", 110, 230)
		row.tag = text("GameFontDisableSmall", 344, 150)
		row.gain = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.gain:SetPoint("RIGHT", -6, 0)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row:SetScript("OnEnter", function(self) showRowTooltip(self) end)
		row:SetScript("OnLeave", GameTooltip_Hide)
		row:SetScript("OnClick", function(self)
			local d = self.data
			if d and d.showAll and state.slot then
				UI.ShowAll(state.slot.key)
			elseif d and d.c and not d.at and not state.slot then
				state.slot = d.slot
				UI.Refresh()
			end
		end)
	end
	if data.header then
		row.icon:Hide()
		row.slotText:SetText("")
		row.name:SetText("|cffffd100" .. data.header .. "|r")
		row.tag:SetText("")
		row.gain:SetText("")
		return
	end
	local c = data.c
	row.icon:Show()
	row.icon:SetTexture(c.inst.icon and ("Interface\\Icons\\" .. c.inst.icon) or "Interface\\Icons\\INV_Misc_QuestionMark")
	row.slotText:SetText(data.at and ("level " .. data.at) or (data.detail and ("level " .. c.rl) or data.slot.label))
	row.name:SetText(itemText(c.inst))
	row.tag:SetText((data.detail and c.sources[1].text or tagOf(c)) .. (onRoute(c) and " |cff4cc3ff(route)|r" or ""))
	row.gain:SetText(format("|cff4cff4c%+.1f|r", data.gain))
end

local function dropAll()
	if state.allBuilding then state.allBuilding:Cancel() end
	state.all, state.allBuilding = nil, nil
end

-- Closing the window lets go of what the build used: the model, the item index, the route map;
-- reopening builds again.
local function release()
	if state.building then state.building:Cancel() end
	dropAll()
	state.building, state.model, state.stale = nil, nil, true
	ns.Items.ReleaseIndex()
	ns.Route.Reset()
end

local function create()
	frame = CreateFrame("Frame", "PoleSimGearFrame", UIParent, "BasicFrameTemplateWithInset")
	frame:SetSize(580, 500)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("HIGH")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	tinsert(UISpecialFrames, "PoleSimGearFrame")
	frame.TitleText:SetText("PoleSim Gear")
	frame.info = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.info:SetPoint("TOPLEFT", 14, -32)
	frame.info:SetPoint("RIGHT", -140, 0)
	frame.info:SetJustifyH("LEFT")
	frame.spec = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.spec:SetSize(124, 20)
	frame.spec:SetPoint("TOPRIGHT", -12, -28)
	frame.spec:SetScript("OnClick", function()
		local cls = ns.Context.ClassKey()
		local cycle = { "auto" }
		for _, k in ipairs(ns.Spec.ORDER[cls] or {}) do cycle[#cycle + 1] = k end
		local i = 1
		for j, k in ipairs(cycle) do if k == ns.char.spec then i = j end end
		ns.char.spec = cycle[i % #cycle + 1]
		ns.Fire("STATE", "SPEC")
	end)
	frame.chips = {}
	for i, f in ipairs(FILTERS) do
		local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		b:SetSize(84, 20)
		b:SetPoint("TOPLEFT", 12 + (i - 1) * 88, -54)
		b:SetText(f[2])
		b:SetScript("OnClick", function()
			state.filter = f[1]
			UI.Refresh()
		end)
		frame.chips[i] = b
	end
	frame.back = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.back:SetSize(84, 20)
	frame.back:SetPoint("TOPRIGHT", -12, -54)
	frame.back:SetText("Back")
	frame.back:SetScript("OnClick", function()
		state.slot = nil
		dropAll()
		UI.Refresh()
	end)
	frame.box = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
	frame.box:SetPoint("TOPLEFT", 10, -80)
	frame.box:SetPoint("BOTTOMRIGHT", -26, 10)
	frame.bar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
	frame.bar:SetPoint("TOPLEFT", frame.box, "TOPRIGHT", 6, 0)
	frame.bar:SetPoint("BOTTOMLEFT", frame.box, "BOTTOMRIGHT", 6, 0)
	local view = CreateScrollBoxListLinearView()
	view:SetElementExtent(24)
	view:SetElementInitializer("Button", initRow)
	ScrollUtil.InitScrollBoxListWithScrollBar(frame.box, frame.bar, view)
	frame:SetScript("OnShow", function()
		if state.stale then UI.Build() else UI.Refresh() end
	end)
	frame:SetScript("OnHide", release)
end

function UI.Refresh()
	if not (frame and frame:IsShown()) then return end
	local ctx = ns.Context.Get()
	if ctx then
		frame.info:SetText(format("%s, level %d (weights of levels %d-%d). Gains in points of %s.", title(ctx.spec), ctx.level,
			ctx.lo, ctx.band.upTo, ns.DATA.statLabels[ctx.ref] or ctx.ref))
		frame.spec:SetText("Spec: " .. (ns.char.spec == "auto" and ("auto (" .. ctx.spec .. ")") or ns.char.spec))
	end
	for i, b in ipairs(frame.chips) do
		if FILTERS[i][1] == state.filter then b:LockHighlight() else b:UnlockHighlight() end
	end
	frame.back:SetShown(state.slot ~= nil)
	frame.box:SetDataProvider(CreateDataProvider(listData()), ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition)
end

-- Every upgrade of one slot (the drill-down's "Show all"), scored over frames like the model.
function UI.ShowAll(key)
	dropAll()
	local env = UI.Env()
	if not env then return end
	local handle, ended -- ended: done or failed (perhaps at once, inside Start)
	handle = ns.Browser.Start(env, function(rows)
		ended = true
		if state.allBuilding ~= handle then return end
		state.all, state.allBuilding = { key = key, rows = rows }, nil
		UI.Refresh()
	end, function(e, yield) return ns.Browser.SlotAll(e, key, yield) end, function()
		ended = true
		if state.allBuilding ~= handle then return end
		state.allBuilding = nil -- "Show all (N)" again: the error went to the client's handler
		UI.Refresh()
	end)
	if not ended then state.allBuilding = handle end
	UI.Refresh()
end

-- (Re)build the model over frames; a build already running is dropped (its scores are stale).
function UI.Build()
	if state.building then state.building:Cancel() end
	dropAll()
	state.building, state.model = nil, nil
	ns.Sources.lastError = nil
	local env, why = UI.Env()
	state.why = why
	if not env then return UI.Refresh() end
	local handle, ended -- ended: done or failed (perhaps at once, inside Start)
	handle = ns.Browser.Start(env, function(model)
		ended = true
		if state.building ~= handle then return end
		state.model, state.building, state.stale = model, nil, false
		UI.Refresh()
	end, nil, function()
		ended = true
		if state.building ~= handle then return end
		state.building = nil -- stale stays true: reopening tries again
		state.why = "The upgrade list could not be built (the error was reported); close and reopen to try again."
		UI.Refresh()
	end)
	if not ended then state.building = handle end
	UI.Refresh()
end

function UI.Toggle()
	if not ns.Context.ClassKey() then return ns.Print("no weights for this class yet (Priest only for now)") end
	if not frame then create() end
	frame:SetShown(not frame:IsShown())
end

local function rebuild()
	state.stale = true
	if frame and frame:IsShown() then UI.Build() end
end
ns.On("SCORES_CHANGED", rebuild)
ns.On("ROUTE_CHANGED", rebuild)
-- A quest turned in (QUEST_TURNED_IN, QuestLogDocumentation in the Forever 1.60.1 UI source) takes its
-- rewards off the list: one rebuild a moment later for a burst of turn-ins (the completion flag is set
-- by then), only while the window is shown (closed, it builds again when opened).
UI.TURNIN_DELAY = 1
local turninQueued = false
ns.RegisterEvent("QUEST_TURNED_IN", function()
	if turninQueued or not (frame and frame:IsShown()) then return end
	turninQueued = true
	C_Timer.After(UI.TURNIN_DELAY, function()
		turninQueued = false
		if frame and frame:IsShown() then UI.Build() end
	end)
end)
ns.Slash("", UI.Toggle)
function PoleSimGear_OnAddonCompartmentClick() UI.Toggle() end
