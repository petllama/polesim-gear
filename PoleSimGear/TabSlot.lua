-- Slot Upgrades: every upgrade of one slot (look ahead and source filters applied), where it comes
-- from, "Set as plan" and the wishlist star; "Show all (N)" scores the slot again untrimmed.
local ADDON, ns = ...
local Tab = {}
ns.TabSlot = Tab
local S = ns.Style
local C = S.C
local format = string.format

function Tab.Rows()
	local st = ns.Window.state
	local m = st.model
	if not m then return nil end
	local key, v = st.slot, ns.Options.View()
	if st.all and st.all.key == key then
		return ns.Browser.SlotRows({ level = m.level, now = { [key] = st.all.rows }, coming = m.coming }, key, v.ahead, v.filters)
	end
	return ns.Browser.SlotRows(m, key, v.ahead, v.filters)
end

function Tab.CountText(rows)
	local n = {}
	for _, r in ipairs(rows) do
		for k in pairs(r.c.kinds) do n[k] = (n[k] or 0) + 1 end
	end
	local parts = {}
	for _, k in ipairs(ns.Browser.KINDS) do
		if n[k] then parts[#parts + 1] = format("%s %d", ns.Plan.KIND_LABEL[k], n[k]) end
	end
	return format("%d upgrade%s", #rows, #rows == 1 and "" or "s") .. (#parts > 0 and (": " .. table.concat(parts, ", ")) or "")
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
	return p
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

-- 5.2 / 5.3
function Tab.List(rows) return rows end
function Tab.Init(row, d) end

ns.Window.RegisterTab("slot", { create = Tab.Create, refresh = Tab.Refresh, release = Tab.Release })
