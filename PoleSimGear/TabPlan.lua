-- The Gear Plan tab: one row per slot with a plan item (the player's pick, else the best upgrade),
-- biggest planned gain first; "All gear" adds the slots without one, "Wishlist" lists starred items.
local ADDON, ns = ...
local Tab = {}
ns.TabPlan = Tab
local S = ns.Style
local C = S.C
local format = string.format
-- the columns for the list's width (Tab.Layout); rows take them when made, drawn or resized
local COL = S.PlanCols(S.CONTENT.w - 10)

local function text(parent, size, colour, justify)
	local t = S.Text(parent, size, colour)
	if justify then t:SetJustifyH(justify) end
	return t
end

-- a row's cells at the current columns
local function place(row)
	if row.cols == COL then return end
	row.cols = COL
	S.Place(row.star, "LEFT", COL.star, 0)
	S.Place(row.badge, "LEFT", COL.prio, 0)
	S.Place(row.slotText, "LEFT", COL.slot, 0, COL.slotW)
	S.Place(row.cur, "LEFT", COL.curIcon, 0)
	row.cur:SetNameWidth(COL.curNameW)
	S.Place(row.curScore, "LEFT", COL.curScore, 0, COL.curScoreW)
	S.Place(row.plan, "LEFT", COL.planIcon, 0)
	row.plan:SetNameWidth(COL.planNameW)
	S.Place(row.delta, "LEFT", COL.delta, 0, COL.deltaW)
	S.Place(row.pct, "LEFT", COL.pct, 0, COL.pctW)
	S.Place(row.srcIcon, "LEFT", COL.srcIcon, 0)
	S.Place(row.kind, "LEFT", COL.kind, 0, COL.kindW)
	S.Place(row.choose, "LEFT", COL.action, 0)
end

local function make(row)
	row.made = true
	row:SetHeight(S.ROW_H)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.star = S.Star(row, function() Tab.Star(row) end)
	row.star:SetPoint("LEFT", COL.star, 0)
	row.badge = S.Badge(row)
	row.badge:SetPoint("LEFT", COL.prio, 0)
	row.slotText = text(row, 12, C.text)
	row.cur = S.ItemCell(row, 22, COL.curNameW)
	-- the worn item's own tooltip and the slot's plan; a click is the row's
	row.cur:EnableMouse(true)
	row.cur:SetScript("OnEnter", function(self) S.Hover(row, true) Tab.CurrentTooltip(row, self) end)
	row.cur:SetScript("OnLeave", function() S.Hover(row, false) GameTooltip_Hide() end)
	row.cur:SetScript("OnMouseUp", function(_, button) Tab.Click(row, button) end)
	row.curScore = text(row, 11, C.dim, "RIGHT")
	row.plan = S.ItemCell(row, 22, COL.planNameW)
	row.delta = text(row, 12, C.green, "RIGHT")
	row.pct = text(row, 12, C.green, "RIGHT")
	row.srcIcon = row:CreateTexture(nil, "ARTWORK")
	row.srcIcon:SetSize(16, 16)
	row.route = S.Dot(row, 8, C.blue) -- on the source icon's corner: an item on the Polestar route
	row.route:SetPoint("CENTER", row.srcIcon, "TOPRIGHT", -1, -1)
	row.kind = text(row, 12, C.white)
	row.choose = S.Button(row, "Choose", COL.actionW, 18, function()
		local e = row.e
		if not e then return end
		if e.row then return ns.Window.PlanAction({ c = e.row.c, slot = e.def }) end -- a wishlist row: set as plan
		ns.Window.OpenSlot(e.def.key)
	end, S.ACTION)
	row.choose.tip = "Pick another upgrade for this slot"
	row:SetScript("OnEnter", function(self) S.Hover(self, true) Tab.Tooltip(self) end)
	row:SetScript("OnLeave", function(self) S.Hover(self, false) GameTooltip_Hide() end)
	row:SetScript("OnClick", function(self, button) Tab.Click(self, button) end)
end

-- the row's plan row (pick or suggestion) | nil
local function planRow(e) return e.row or (e.entry and e.entry.plan) end
Tab.PlanRow = planRow

local function primaryKind(r)
	local s = r.c.sources[1]
	return s and s.kind
end

-- one entry (View.PlanEntries) -> the row's widgets
local function fill(row, e)
	S.RowBg(row, e.index)
	local def = e.def
	row.badge:Set(e.priority)
	row.slotText:SetText(def and (def.short or def.label) or "")
	local w = e.worn
	row.cur:Set(w and w.inst, nil)
	row.curScore:SetText(w and format("%.1f", w.score) or "")
	local r = planRow(e)
	local entry = e.entry or {}
	if r then
		local sub
		if entry.isPick then
			sub = S.Colour(C.pick) .. "Your pick|r"
			if entry.betterBy then
				-- the name would be cut here: the row tooltip says which item ("Better: ...")
				sub = sub .. "  best " .. S.Colour(C.green) .. S.Signed(entry.suggestion.gain) .. "|r"
			end
		elseif r.at then
			sub = "level " .. r.at
		end
		row.plan:Set(r.c.inst, sub)
		row.delta:SetText(S.Signed(r.gain))
		row.pct:SetText(S.Pct(r.gain, r.base)) -- over everything it replaces (main + off hand for a staff)
		local k = primaryKind(r)
		row.srcIcon:SetTexture(k and S.KIND_ICON[k])
		row.srcIcon:SetShown(k ~= nil)
		local route = false
		for _, s in ipairs(r.c.sources) do route = route or s.route ~= nil end
		row.kind:SetText(k and S.KIND_SHORT[k] or "")
		row.route:SetShown(route)
		row.star:Show()
		row.star:Set(ns.Wishlist.Has(r.c.inst))
	elseif e.missing or entry.missing then
		local m = e.missing or entry.missing
		row.plan:Set(ns.View.Inst(m.id, m.bonus), S.Colour(C.orange) .. (e.why or "") .. "|r")
		row.plan:SetDim(true)
		row.delta:SetText(""); row.pct:SetText(""); row.srcIcon:Hide(); row.route:Hide(); row.kind:SetText("")
		row.star:Show()
		row.star:Set(ns.Wishlist.Has(ns.View.Inst(m.id, m.bonus)))
	else
		row.plan:Set(nil, S.Colour(C.label) .. "nothing better now|r")
		row.delta:SetText(""); row.pct:SetText(""); row.srcIcon:Hide(); row.route:Hide(); row.kind:SetText("")
		row.star:Hide()
	end
	row.choose:SetShown(def ~= nil and (e.entry ~= nil or e.row ~= nil))
	if e.row and def then
		-- wishlist rows: "Plan" sets the item as the slot's plan ("Picked" once it is)
		local ctx = ns.Context.Get()
		local mine = ctx and ns.Plan.Get(ctx.spec, def.key) == ns.Browser.KeyOf(e.row.c.inst)
		row.choose.label:SetText(mine and (S.Colour(C.pick) .. "Picked|r") or "Plan")
		row.choose.tip = mine and "Your pick for this slot (click: back to the suggestion)" or "Set as plan for this slot"
	else
		row.choose.label:SetText("Choose")
		row.choose.tip = "Pick another upgrade for this slot"
	end
end

local function emptyRow(row, msg)
	S.RowBg(row, 1)
	row.badge:Set(nil); row.slotText:SetText(""); row.cur:Set(nil); row.curScore:SetText("")
	row.plan:Set(nil, ""); row.plan.name:SetText(S.Colour(C.label) .. msg .. "|r")
	row.delta:SetText(""); row.pct:SetText(""); row.srcIcon:Hide(); row.route:Hide(); row.kind:SetText("")
	row.star:Hide(); row.choose:Hide()
end

local function init(row, e)
	if not row.made then make(row) end
	place(row)
	row.e = e
	if e.empty then return emptyRow(row, e.empty) end
	fill(row, e)
end

function Tab.Create(parent)
	local p = CreateFrame("Frame", nil, parent)
	p.header = CreateFrame("Frame", nil, p)
	p.header:SetPoint("TOPLEFT")
	p.header:SetPoint("TOPRIGHT")
	p.header:SetHeight(20)
	S.Fill(p.header, C.head)
	p.heads = {}
	for _, h in ipairs({ { "prio", "#", "CENTER" }, { "slot", "Slot" }, { "cur", "Current item" }, { "plan", "Plan" },
		{ "delta", "Gain", "RIGHT" }, { "pct", "Gain %", "RIGHT" }, { "src", "Source" } }) do
		local t = S.Text(p.header, 11, C.headText)
		if h[3] then t:SetJustifyH(h[3]) end
		t:SetText(h[2])
		p.heads[h[1]] = t
	end
	p.list = S.List(p, 0, -20, S.CONTENT.w, S.CONTENT.h - 20, S.ROW_H, init)
	Tab.Layout(p, S.CONTENT.w, S.CONTENT.h)
	return p
end

-- the tab at the content's size (w x h): the list stretches, the columns reflow (rows in view too)
function Tab.Layout(p, w, h)
	S.PlaceList(p.list, 0, -20, w, h - 20)
	COL = S.PlanCols(w - 10)
	local hd = p.heads
	S.Place(hd.prio, "LEFT", COL.prio, 0, COL.prioW)
	S.Place(hd.slot, "LEFT", COL.slot, 0, COL.slotW)
	-- "Current item" over the icon, name and score; "Current" when only the icon and score show
	hd.cur:SetText(COL.curNameW > 0 and "Current item" or "Current")
	S.Place(hd.cur, "LEFT", COL.curIcon, 0, COL.curScore + COL.curScoreW - COL.curIcon)
	S.Place(hd.plan, "LEFT", COL.planIcon, 0, COL.planNameW + 26)
	S.Place(hd.delta, "LEFT", COL.delta, 0, COL.deltaW)
	S.Place(hd.pct, "LEFT", COL.pct, 0, COL.pctW)
	S.Place(hd.src, "LEFT", COL.srcIcon, 0, COL.kind + COL.kindW - COL.srcIcon)
	S.EachRow(p.list, function(row) if row.made then place(row) end end)
end

function Tab.Entries()
	local st = ns.Window.state
	local ctx = ns.Context.Get()
	if not st.model then
		return { { empty = st.building and "Scoring items..." or (st.why or "Nothing to show") } }
	end
	if not ctx then return { { empty = "No weights for this character." } } end
	local es = ns.Window.PlanEntries(ns.Options.View().show)
	if #es == 0 then
		local show = ns.Options.View().show
		return { { empty = show == "wishlist" and "Your wishlist is empty: star an item in any list."
			or "No upgrades from the ticked sources." } }
	end
	local wish = ns.Options.View().show == "wishlist"
	for i, e in ipairs(es) do
		e.index = i
		if wish then e.worn = e.def and ns.Browser.WornFor(e.def, ctx.worn) end
	end
	return es
end

function Tab.Refresh(p) S.SetList(p.list, Tab.Entries()) end
function Tab.Release(p) S.SetList(p.list, {}) end

function Tab.Star(row)
	local e = row.e
	local r = e and planRow(e)
	local m = e and (e.missing or (e.entry and e.entry.missing))
	local inst = r and r.c.inst or (m and { id = m.id, bonus = m.bonus })
	if inst then ns.Wishlist.Toggle(inst) end -- WISHLIST_CHANGED redraws the window
end

function Tab.Tooltip(row)
	local e = row.e
	if not (e and not e.empty) then return end
	local r = planRow(e)
	if r then
		local entry = e.entry
		local better = entry and entry.isPick and entry.betterBy and entry.suggestion
			and format("Better: %s %s", entry.suggestion.c.inst.name or "?", S.Signed(entry.suggestion.gain)) or nil
		return ns.Window.RowTooltip(row, r, entry and "Click: this slot's upgrades. Right-click: back to suggestion, wishlist."
			or "Click: this slot's upgrades.", better)
	end
	local m = e.missing or (e.entry and e.entry.missing)
	if not m then return end
	local inst = ns.View.Inst(m.id, m.bonus)
	ns.Window.ItemTip(row, inst, function() GameTooltip:AddLine(e.why or "", 1, 0.6, 0.25, true) end)
end

-- The current item cell: the worn item's own tooltip (its inventory slot: for rings and trinkets the
-- one the row shows), then the slot's plan line.
function Tab.CurrentTooltip(row, cell)
	local e = row.e
	if not (e and e.def and e.worn) then return end
	local ctx = ns.Context.Get()
	local slot = e.def.slot
	if ctx and ctx.worn[slot] ~= e.worn and ctx.worn[slot + 1] == e.worn then slot = slot + 1 end
	GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
	GameTooltip:SetInventoryItem("player", slot)
	local line, r, g, b = ns.Window.SlotPlanLine(slot)
	if line then GameTooltip:AddLine(line, r, g, b, true) end
	GameTooltip:Show()
end

function Tab.Click(row, button)
	local e = row.e
	if not (e and e.def) then return end
	if button ~= "RightButton" then return ns.Window.OpenSlot(e.def.key) end
	local ctx = ns.Context.Get()
	if not ctx then return end
	if not (MenuUtil and MenuUtil.CreateContextMenu) then return ns.Window.OpenSlot(e.def.key) end -- an older client
	local r = planRow(e)
	local inst = r and r.c.inst or (e.entry and e.entry.missing and ns.View.Inst(e.entry.missing.id, e.entry.missing.bonus))
	MenuUtil.CreateContextMenu(row, function(_, root)
		root:CreateTitle(e.def.label)
		root:CreateButton("Choose another upgrade", function() ns.Window.OpenSlot(e.def.key) end)
		if e.entry and e.entry.isPick then
			root:CreateButton("Back to suggestion", function() ns.Plan.Clear(ctx.spec, e.def.key) end)
		end
		if inst then
			root:CreateButton(ns.Wishlist.Has(inst) and "Remove from wishlist" or "Add to wishlist", function() ns.Wishlist.Toggle(inst) end)
		end
	end)
end

ns.Window.RegisterTab("plan", { create = Tab.Create, refresh = Tab.Refresh, release = Tab.Release, layout = Tab.Layout })
