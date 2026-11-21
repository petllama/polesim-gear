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

-- the line under an item: where exactly it comes from in this place
local function srcLine(s)
	if not s then return "" end
	if s.kind == "dungeon" then
		return (s.npcName and (s.npcName .. (s.boss and " (boss)" or "")) or s.container or "?") .. (s.chance and format(", %g%%", s.chance) or "")
	elseif s.kind == "crafted" then
		return (s.profession or "Crafted") .. (s.skill and (" " .. s.skill) or "")
	elseif s.kind == "vendor" then
		return (s.npcName or "Vendor") .. (s.cost and (" · " .. S.Money(s.cost)) or "")
	end
	return s.text or ""
end
Tab.SrcLine = srcLine

-- The place a detail row's Waypoint leads to (a quest's giver, a dungeon's entrance, a vendor, a
-- world drop's mob) | nil: no button. Polestar's Nav API is read at call time (it may load later).
local function spotFor(d)
	if not ns.Waypoint.Available() then return nil end
	local codex = ns.Window.state.codex or {}
	if d.quest then return ns.Waypoint.SpotOf({ kind = "quest", questId = d.quest.questId, title = d.quest.title }, codex) end
	if d.dungeon then return ns.Waypoint.SpotOf({ kind = "dungeon", instanceKey = d.dungeon.key }, codex) end
	if d.c and d.src and (d.src.kind == "vendor" or d.src.kind == "world") then return ns.Waypoint.SpotOf(d.src, codex) end
	return nil
end

-- the hover's lines about this place: its other sources of the item, and a low chance
local function placeLines(d)
	local out = {}
	if d.rare then out[#out + 1] = format("Likeliest drop here is under %g%%: luck, not a plan.", ns.Groups.RARE_CHANCE) end
	for _, o in ipairs(d.others or {}) do out[#out + 1] = "Also here: " .. srcLine(o) end
	local more = (d.otherCount or 0) - #(d.others or {})
	if more > 0 then out[#out + 1] = format("and %d more here", more) end
	return out
end

local function makeDetail(row)
	row.made = true
	row.star = S.Star(row, function() if row.d and row.d.c then ns.Wishlist.Toggle(row.d.c.inst) end end)
	row.star:SetPoint("LEFT", 4, 0)
	row.item = S.ItemCell(row, 22, 160)
	row.item:SetPoint("LEFT", 22, 0)
	row.title = S.Text(row, 12, C.pick)
	row.title:SetPoint("LEFT", 8, 0)
	row.title:SetWidth(320)
	row.delta = S.Text(row, 12, C.green)
	row.delta:SetPoint("LEFT", 210, 0)
	row.delta:SetWidth(40)
	row.delta:SetJustifyH("RIGHT")
	row.action = S.Button(row, "", 70, 18, function() ns.Window.PlanAction(row.d) end, S.ACTION)
	row.action:SetPoint("LEFT", 254, 0)
	row.way = S.Button(row, "Waypoint", 64, 18, function(self)
		if not ns.Waypoint.Go(self.spot) then ns.Print("Polestar could not set the waypoint") end
	end, S.ACTION)
	row.way:SetPoint("LEFT", 328, 0)
	row.way.tip = "Polestar's arrow to this place"
	row:SetScript("OnEnter", function(self)
		S.Hover(self, true)
		if self.d and self.d.c then ns.Window.RowTooltip(self, self.d, "Set as plan: make it this slot's plan item.", placeLines(self.d)) end
	end)
	row:SetScript("OnLeave", function(self) S.Hover(self, false) GameTooltip_Hide() end)
end

local function initDetail(row, d)
	if not row.made then makeDetail(row) end
	row.d = d
	S.RowBg(row, d.index)
	local item = d.c ~= nil
	row.star:SetShown(item)
	row.item:SetShown(item)
	row.delta:SetShown(item)
	row.action:SetShown(item)
	row.title:SetShown(not item)
	local spot = spotFor(d)
	row.way.spot = spot
	row.way:SetShown(spot ~= nil)
	if d.quest then
		local q = d.quest
		local tags = {}
		if q.elite then tags[#tags + 1] = S.Colour(C.orange) .. "elite|r" end
		if q.route then tags[#tags + 1] = S.Colour(C.blue) .. "on your route|r" end
		if q.needs then tags[#tags + 1] = S.Colour(C.orange) .. "needs: " .. q.needs .. " first|r" end
		row.title:SetText(format("[%d] %s", q.level or 0, q.title or "?") .. (#tags > 0 and ("  " .. table.concat(tags, "  ")) or ""))
		return
	end
	if d.dungeon then
		row.title:SetText(d.dungeon.name .. (d.dungeon.levels and (" (levels " .. d.dungeon.levels .. ")") or ""))
		return
	end
	if not item then
		row.title:SetText(S.Colour(C.label) .. (d.empty or "") .. "|r")
		return
	end
	local sub = srcLine(d.src)
	if d.src and d.src.kind == "world" and d.src.zoneId and not d.src.where then
		local codex = ns.Window.state.codex
		local ok, z = pcall(function() return codex.Zone(d.src.zoneId) end)
		if ok and type(z) == "table" and z.name then sub = sub .. ", " .. z.name end
	end
	if d.at then sub = sub .. "  (level " .. d.at .. ")" end
	row.item:Set(d.c.inst, sub)
	if d.rare then row.item:SetDim(true) end
	row.delta:SetText(S.Signed(d.gain))
	row.star:Set(ns.Wishlist.Has(d.c.inst))
	ns.Window.PlanLabel(row.action, d, false)
end

-- a Groups row -> the detail list's data (world rows have no `rare`: their chance decides)
local function item(r, i)
	local rare = r.rare
	if rare == nil then rare = r.src ~= nil and ns.Groups.Rare(r.src) end
	return { c = r.c, gain = r.gain, at = r.at, slot = r.slot, note = r.note, src = r.src, others = r.others,
		otherCount = r.otherCount, rare = rare, index = i }
end
-- rows (by gain) -> the likely ones first, then the rare ones (each still by gain)
local function addRows(out, rows)
	for pass = 1, 2 do
		for _, r in ipairs(rows) do
			local d = item(r, 0)
			if (pass == 2) == (d.rare == true) then
				d.index = #out + 1
				out[#out + 1] = d
			end
		end
	end
end

function Tab.RefreshDetail(p, g)
	local out = {}
	if view.kind == "world" then
		addRows(out, g.world)
	else
		local grp
		for _, x in ipairs(g[view.kind] or {}) do
			if x.key == view.group then grp = x end
		end
		if grp and grp.quests then
			for _, q in ipairs(grp.quests) do
				out[#out + 1] = { quest = q, index = #out + 1 }
				addRows(out, q.rows)
			end
		elseif grp then
			if view.kind == "dungeon" then out[1] = { dungeon = grp, index = 1 } end
			addRows(out, grp.rows)
		end
	end
	if #out == 0 then out[1] = { empty = "Nothing here", index = 1 } end
	S.SetList(p.detail, out)
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
	p.detail = S.List(p, 218, -30, 408, S.CONTENT.h - 30, S.ROW_H, initDetail)
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
