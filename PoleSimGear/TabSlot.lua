-- Slot Upgrades: every upgrade of one slot (look ahead and source filters applied), where it comes
-- from, "Set as plan" and the wishlist star; "Show all (N)" scores the slot again untrimmed.
local ADDON, ns = ...
local Tab = {}
ns.TabSlot = Tab
local S = ns.Style
local C = S.C
local format = string.format
local COL = S.SlotCols(S.CONTENT.w - 10) -- Tab.Layout's

function Tab.Rows()
	local st = ns.Window.state
	local m = st.model
	if not m then return nil end
	local key, v = st.slot, ns.Options.View()
	-- weapons pair with the other hand's pick when there is one; All gear also lists the pairs that do
	-- not beat a worn two-hander (negative)
	local ctx = ns.Context.Get()
	local other = key == "mainhand" and "offhand" or key == "offhand" and "mainhand" or nil
	local opts = { partner = other and ctx and ns.Plan.Get(ctx.spec, other) or nil, all = v.show == "all" }
	if st.all and st.all.key == key then
		local now = { [key] = st.all.rows }
		if other then now[other] = m.now[other] end
		return ns.Browser.SlotRows({ level = m.level, now = now, coming = m.coming, under2h = m.under2h }, key, v.ahead, v.filters, opts)
	end
	return ns.Browser.SlotRows(m, key, v.ahead, v.filters, opts)
end

function Tab.CountText(rows)
	local n, ups = {}, 0
	for _, r in ipairs(rows) do
		if r.gain > 1e-6 then -- (All gear lists weapon pairs that lose to a worn two-hander too)
			ups = ups + 1
			for k in pairs(r.c.kinds) do n[k] = (n[k] or 0) + 1 end
		end
	end
	local parts = {}
	for _, k in ipairs(ns.Browser.KINDS) do
		if n[k] then parts[#parts + 1] = format("%s %d", ns.Plan.KIND_LABEL[k], n[k]) end
	end
	return format("%d upgrade%s", ups, ups == 1 and "" or "s") .. (#parts > 0 and (": " .. table.concat(parts, ", ")) or "")
end

function Tab.Create(parent)
	local p = CreateFrame("Frame", nil, parent)
	local bar = CreateFrame("Frame", nil, p)
	bar:SetPoint("TOPLEFT")
	bar:SetPoint("TOPRIGHT")
	bar:SetHeight(30)
	S.Fill(bar, C.head)
	p.picker = S.Dropdown(bar, 160, 24, function()
		local out = {}
		for _, d in ipairs(ns.Browser.SLOTS) do out[#out + 1] = { text = d.label, value = d.key } end
		return out
	end, function(k) return ns.Window.state.slot == k end, function(k) ns.Window.OpenSlot(k) end)
	p.picker:SetPoint("LEFT", 6, 0)
	p.count = S.Text(bar, 12, C.text)
	p.count:SetPoint("LEFT", 176, 0)
	p.count:SetWidth(440)
	p.list = S.List(p, 0, -30, S.CONTENT.w, S.CONTENT.h - 30, S.ROW_H, function(row, d) Tab.Init(row, d) end)
	Tab.Layout(p, S.CONTENT.w, S.CONTENT.h)
	return p
end

local function place(row)
	if row.cols == COL then return end
	row.cols = COL
	S.Place(row.star, "LEFT", COL.star, 0)
	S.Place(row.item, "LEFT", COL.item, 0)
	row.item:SetNameWidth(COL.nameW)
	S.Place(row.level, "LEFT", COL.level, 0, COL.levelW)
	S.Place(row.delta, "LEFT", COL.delta, 0, COL.deltaW)
	S.Place(row.pct, "LEFT", COL.pct, 0, COL.pctW)
	S.Place(row.srcIcon, "LEFT", COL.srcIcon, 0)
	S.Place(row.kind, "LEFT", COL.kind, 0, COL.kindW)
	S.Place(row.action, "LEFT", COL.action, 0)
end

function Tab.Layout(p, w, h)
	S.PlaceList(p.list, 0, -30, w, h - 30)
	p.count:SetWidth(w - 176 - 8)
	COL = S.SlotCols(w - 10)
	S.EachRow(p.list, function(row) if row.made then place(row) end end)
end

function Tab.Refresh(p)
	p.picker:Update()
	local rows = Tab.Rows()
	if not rows then
		local st = ns.Window.state
		p.count:SetText("")
		return S.SetList(p.list, { { empty = st.building and "Scoring items..." or (st.why or "Nothing to show") } })
	end
	p.count:SetText(Tab.CountText(rows))
	S.SetList(p.list, Tab.List(rows))
end
function Tab.Release(p) S.SetList(p.list, {}) end

local function make(row)
	row.made = true
	row.star = S.Star(row, function()
		if row.d and row.d.c then ns.Wishlist.Toggle(row.d.c.inst) end
	end)
	row.item = S.ItemCell(row, 22, COL.nameW)
	row.level = S.Text(row, 11, C.dim)
	row.delta = S.Text(row, 12, C.green)
	row.delta:SetJustifyH("RIGHT")
	row.pct = S.Text(row, 12, C.green)
	row.pct:SetJustifyH("RIGHT")
	row.srcIcon = row:CreateTexture(nil, "ARTWORK")
	row.srcIcon:SetSize(16, 16)
	row.kind = S.Text(row, 12, C.white)
	row.action = S.Button(row, "", COL.actionW, 18, function() ns.Window.PlanAction(row.d) end, S.ACTION)
	row:SetScript("OnEnter", function(self)
		S.Hover(self, true)
		if self.d and self.d.c then ns.Window.RowTooltip(self, self.d, "Set as plan: make it this slot's plan item.") end
	end)
	row:SetScript("OnLeave", function(self) S.Hover(self, false) GameTooltip_Hide() end)
	row:SetScript("OnClick", function(self) if self.d and self.d.showAll then ns.Window.ShowAll(ns.Window.state.slot) end end)
end

function Tab.Init(row, d)
	if not row.made then make(row) end
	place(row)
	row.d = d
	S.RowBg(row, d.index)
	local header = d.empty or d.header
	row.star:SetShown(not header)
	row.action:SetShown(not header)
	row.srcIcon:SetShown(not header)
	if header then
		row.item:Set(nil, "")
		row.item.name:SetText(S.Colour(d.showAll and C.blue or C.label) .. header .. "|r")
		row.level:SetText(""); row.delta:SetText(""); row.pct:SetText(""); row.kind:SetText("")
		return
	end
	local s = d.c.sources[1]
	local sub = s and s.text or ""
	if s and s.route then sub = sub .. " " .. S.Colour(C.blue) .. ns.Route.Tag(s.route) .. "|r" end -- "in 12 steps"
	if s and s.needs then sub = sub .. " " .. S.Colour(C.orange) .. "needs: " .. s.needs .. " first|r" end
	row.item:Set(d.c.inst, sub)
	row.level:SetText(ns.LevelText(d.at or d.c.rl, "lvl "))
	row.delta:SetText(S.Signed(d.gain))
	row.pct:SetText(S.Pct(d.gain, d.base)) -- over everything it replaces (main + off hand for a staff)
	row.srcIcon:SetTexture(s and S.KIND_ICON[s.kind])
	row.kind:SetText(s and S.KIND_SHORT[s.kind] or "")
	row.star:Set(ns.Wishlist.Has(d.c.inst))
	ns.Window.PlanLabel(row.action, d, true)
end

-- The rows' list data; the model keeps the best KEEP per kind, so when more upgrades now pass the
-- ticked sources the last row offers "Show all (N)" (scored again over frames, Window.ShowAll).
function Tab.List(rows)
	local st = ns.Window.state
	local key, v = st.slot, ns.Options.View()
	local out, now = {}, 0
	for i, r in ipairs(rows) do
		out[i] = { c = r.c, gain = r.gain, base = r.base, at = r.at, note = r.note, slot = r.slot, index = i }
		if not r.at then now = now + 1 end
	end
	if #out == 0 then out[1] = { empty = "No upgrade for this slot from the ticked sources.", index = 1 } end
	if not (st.all and st.all.key == key) then
		local total = ns.Browser.CountPassing(st.model, key, v.filters)
		if st.allBuilding then
			out[#out + 1] = { header = "Scoring every upgrade...", index = #out + 1 }
		elseif total > now then
			out[#out + 1] = { header = format("Show all (%d)", total) .. (st.allWhy and (": " .. st.allWhy) or ""), showAll = true, index = #out + 1 }
		end
	end
	return out
end

ns.Window.RegisterTab("slot", { create = Tab.Create, refresh = Tab.Refresh, release = Tab.Release, layout = Tab.Layout })
