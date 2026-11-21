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
	return p
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
