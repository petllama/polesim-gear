-- Sources: where to go for upgrades. Pills choose the kind; the left list its places (a dungeon, a
-- zone's quests, a profession, a zone's vendors; world drops have no places); the right list the
-- chosen place's upgrades. Source filters do not apply here (this tab is about the places).
local ADDON, ns = ...
local Tab = {}
ns.TabSources = Tab
local S = ns.Style
local C = S.C
local format = string.format

Tab.KINDS = { { "dungeon", "Dungeons" }, { "quest", "Quests" }, { "crafted", "Crafting" }, { "vendor", "Vendors" }, { "world", "BoE / World" } }
local view = { kind = "dungeon", group = nil } -- the tab's own selection (not saved)
Tab.view = view

-- The grouping of the shown model (made on the tab's first show; Window drops it with the model,
-- on a look ahead change and on close).
function Tab.Groups()
	local st = ns.Window.state
	if not st.model then return nil end
	if not st.groups then
		st.groups = ns.Groups.Build(st.model, ns.Options.View().ahead, st.codex or {})
	end
	return st.groups
end

-- a pill's number: upgrades (dungeons, crafting, vendors, world) or quests (quest zones)
local function count(g, kind)
	local list = g[kind] or {}
	if kind == "world" then return #list end
	local n = 0
	for _, x in ipairs(list) do n = n + x.count end
	return n
end

local function plural(n, word) return format("%d %s%s", n, word, n == 1 and "" or "s") end
local function groupSub(kind, g)
	if kind == "dungeon" then return (g.levels and ("levels " .. g.levels .. " · ") or "") .. plural(g.count, "upgrade") end
	if kind == "quest" then return plural(g.count, "quest") end
	if kind == "crafted" then return plural(g.count, "craft") end
	return plural(g.count, "upgrade")
end

local function initGroup(row, d)
	if not row.made then
		row.made = true
		row.name = S.Text(row, 13, C.white)
		row.name:SetPoint("TOPLEFT", 8, -4)
		row.name:SetWidth(190)
		row.sub = S.Text(row, 10, C.label)
		row.sub:SetPoint("TOPLEFT", 8, -19)
		row.sub:SetWidth(190)
		row:SetScript("OnClick", function(self)
			if self.d and self.d.g then
				view.group = self.d.g.key
				ns.Window.Refresh()
			end
		end)
		row:SetScript("OnEnter", function(self) S.Hover(self, true) end)
		row:SetScript("OnLeave", function(self) S.Hover(self, self.d and self.d.selected) end)
	end
	row.d = d
	S.RowBg(row, d.index)
	if d.selected then S.Hover(row, true) end
	row.name:SetText(d.g and d.g.name or (d.text or ""))
	row.sub:SetText(d.g and groupSub(view.kind, d.g) or "")
end

function Tab.Create(parent)
	local p = CreateFrame("Frame", nil, parent)
	p.pills = {}
	for i, k in ipairs(Tab.KINDS) do
		local b = S.Button(p, k[2], 118, 22, function()
			view.kind, view.group = k[1], nil
			ns.Window.Refresh()
		end, S.TAB)
		b:SetPoint("TOPLEFT", 4 + (i - 1) * 124, -4)
		b.kind, b.base = k[1], k[2]
		p.pills[i] = b
	end
	p.groups = S.List(p, 0, -30, 210, S.CONTENT.h - 30, 34, initGroup)
	local split = p:CreateTexture(nil, "BORDER")
	split:SetColorTexture(C.cardBorder[1], C.cardBorder[2], C.cardBorder[3], 1)
	split:SetPoint("TOPLEFT", 212, -30)
	split:SetSize(1, S.CONTENT.h - 30)
	return p
end

function Tab.RefreshLists(p, g)
	if not g then
		local st = ns.Window.state
		S.SetList(p.groups, { { text = st.building and "Scoring items..." or (st.why or "Nothing to show"), index = 1 } })
		if p.detail then S.SetList(p.detail, {}) end
		return
	end
	local list = {}
	if view.kind == "world" then
		list[1] = { text = "World drops: luck, no place", index = 1 }
	else
		local found = false
		for i, x in ipairs(g[view.kind] or {}) do
			list[i] = { g = x, index = i }
			found = found or x.key == view.group
		end
		-- the first place unless the chosen one is still there (a regroup may drop it)
		if not found then view.group = list[1] and list[1].g.key or nil end
		for _, d in ipairs(list) do d.selected = d.g.key == view.group end
		if #list == 0 then list[1] = { text = "No upgrades here", index = 1 } end
	end
	S.SetList(p.groups, list)
	if Tab.RefreshDetail then Tab.RefreshDetail(p, g) end
end
function Tab.ReleaseLists(p)
	S.SetList(p.groups, {})
	if p.detail then S.SetList(p.detail, {}) end
end

function Tab.Refresh(p)
	local g = Tab.Groups()
	for _, b in ipairs(p.pills) do
		b.label:SetText(g and format("%s %d", b.base, count(g, b.kind)) or b.base)
		S.SetColours(b, b.kind == view.kind and S.TAB_ON or S.TAB)
	end
	if Tab.RefreshLists then Tab.RefreshLists(p, g) end
end
function Tab.Release(p)
	view.group = nil
	if Tab.ReleaseLists then Tab.ReleaseLists(p) end
end

ns.Window.RegisterTab("sources", { create = Tab.Create, refresh = Tab.Refresh, release = Tab.Release })
