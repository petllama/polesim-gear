-- The tooltip line: score for the current spec and band, gain over what is worn (points of the spec's
-- reference stat, and %), and with Shift the "how?" sum (stat x weight = points, minus the worn item).
-- A term whose stat the client did not report (an equip bonus filled from the item table, Live) is
-- marked "(item table)".
local ADDON, ns = ...
local Tooltip = {}
ns.Tooltip = Tooltip

local format = string.format
local GREEN, RED, GREY, GOLD = { 0.3, 1, 0.3 }, { 1, 0.4, 0.4 }, { 0.6, 0.6, 0.6 }, { 1, 0.82, 0 }

local function label(k) return ns.DATA.statLabels[k] or k end
local function title(s) return (s:gsub("^%l", string.upper)) end
local function g(x) return format("%g", x) end

-- cmp (Equip.Compare), inst, ctx (Context), shift held, label ours "PoleSim" -> { { left, right, color, rightColor }, ... }
function Tooltip.Lines(cmp, inst, ctx, shift, labelled)
	local lines = {}
	local right, color
	if cmp.equipped then
		right, color = "equipped", GREY
	elseif cmp.blocked then
		right, color = "not for " .. title(ctx.spec), RED
	else
		right = format("%+.1f", cmp.gain) .. (cmp.base > 0.01 and format(" (%+.0f%%)", 100 * cmp.gain / cmp.base) or "")
		color = cmp.gain > 1e-6 and GREEN or (cmp.gain < -1e-6 and RED or GREY)
	end
	lines[1] = { (labelled and "PoleSim score " or "Score ") .. format("%.1f", cmp.score), right, GOLD, color }
	lines[2] = { format("%s, levels %d-%d: points of %s", title(ctx.spec), ctx.lo, ctx.band.upTo, label(ctx.ref)), nil, GREY }
	if (inst.rl or 0) > ctx.level then lines[#lines + 1] = { format("requires level %d", inst.rl), nil, GREY } end
	if cmp.note then lines[#lines + 1] = { cmp.note, nil, GREY } end
	if cmp.blocked then lines[#lines + 1] = { cmp.blocked, nil, RED } end
	if not shift then
		lines[#lines + 1] = { "Shift: how?", nil, GREY }
		return lines
	end
	local role = ns.Equip.ROLE_OF_SLOT[cmp.slot] or "gear"
	if inst.inv == 17 then role = "mh" end
	local filled = inst.filled or {}
	for _, p in ipairs(ns.Score.Parts(inst, ctx.w, ctx.cls, role)) do
		local name = label(p[1]) .. (p[1] ~= p[3] and (" as " .. label(p[3])) or "")
		lines[#lines + 1] = { format("  %s %s x %s%s", name, g(p[2]), g(p[4]), filled[p[1]] and " (item table)" or ""),
			format("%.2f", p[5]), GREY, GREY }
	end
	if not cmp.equipped and not cmp.blocked then
		lines[#lines + 1] = { "  minus worn", format("%.2f", cmp.base), GREY, GREY }
		lines[#lines + 1] = { "  gain", format("%+.2f", cmp.gain), GREY, color }
	end
	return lines
end

-- The live hook: every item tooltip (GameTooltip, ItemRefTooltip) gets the lines for items the character
-- can use, up to AHEAD levels above; Shift redraws it with the breakdown.
local AHEAD = 5 -- items up to this many levels above the character still get a line
local secret = issecretvalue or function() return false end
local drawn = setmetatable({}, { __mode = "k" }) -- tooltip -> the item link our lines were drawn for

-- The hover path's results per link ({ inst, cmp }, or false: nothing to show), kept until scores
-- change; a pending item, or one built from the shipped table while the client had no stats yet
-- (inst.fromTable), is not kept. Bounded: emptied when it reaches CACHE_MAX links.
local CACHE_MAX = 500
local cache, cached = {}, 0
ns.On("SCORES_CHANGED", function() cache, cached = {}, 0 end)

-- link, ctx -> { inst, cmp } | false, waiting (true: the client has not got the item, or its stats, yet).
-- Shared with the upgrade arrows and the reward pick (one read and one comparison per link).
local function lookup(link, ctx)
	local hit = cache[link]
	if hit ~= nil then return hit end
	local inst, pending = ns.Live.Instance(link)
	if pending then return false, true end
	local cmp = inst and ns.Equip.CanUse(inst, ctx.cls, ctx.level) and (inst.rl or 0) <= ctx.level + AHEAD
		and ns.Equip.Compare(inst, ctx.w, ctx.cls, ctx.worn, ctx.canDw, ctx.rules)
	hit = cmp and { inst, cmp } or false
	if inst and inst.fromTable then return hit, true end -- the client's stats may come by the next read
	if cached >= CACHE_MAX then cache, cached = {}, 0 end
	cache[link], cached = hit, cached + 1
	return hit
end
Tooltip.Lookup = lookup

-- The score lines (switch "tooltip"), then the wishlist star line: the player's own mark, shown for any
-- starred item whether or not it is scored and whatever the switch says (one line).
local function scoreLines(tooltip, link)
	if ns.Options and ns.Options.Get("tooltip") == false then return end
	local ctx = ns.Context.Get()
	if not ctx then return end
	local hit = lookup(link, ctx)
	if not hit then return end
	local inst, cmp = hit[1], hit[2]
	local labelled = ns.Coexist and ns.Coexist.Label() or false
	for _, l in ipairs(Tooltip.Lines(cmp, inst, ctx, IsShiftKeyDown(), labelled)) do
		local a, b = l[3] or GREY, l[4] or GREY
		if l[2] then
			tooltip:AddDoubleLine(l[1], l[2], a[1], a[2], a[3], b[1], b[2], b[3])
		else
			tooltip:AddLine(l[1], a[1], a[2], a[3], true)
		end
	end
	drawn[tooltip] = link -- Shift redraws only a tooltip with the score lines (the star line never changes)
end

function Tooltip.Add(tooltip, link)
	if not link then return end
	scoreLines(tooltip, link)
	local id = tonumber(link:match("item:(%d+)"))
	-- an upcoming quest reward on the Polestar route: "Polestar: in 12 steps (Assault on Fenris Isle)"
	local route = id and ns.Route and ns.Route.ItemLine(id)
	if route then tooltip:AddLine(route, 0.3, 0.8, 1, true) end
	if ns.Wishlist and id and ns.Wishlist.HasId(id) then
		tooltip:AddLine("|A:auctionhouse-icon-favorite:12:12|a On your PoleSim wishlist", 1, 0.82, 0)
	end
end

local function forbidden(tooltip)
	if not tooltip.IsForbidden then return false end
	local ok, f = pcall(tooltip.IsForbidden, tooltip)
	return not ok or secret(f) or f
end

local function str(x) return type(x) == "string" and not secret(x) and x ~= "" and x or nil end

-- The item link from the post-call's tooltip data (the GUID of a bag/worn item, or its hyperlink, read
-- as TooltipUtil.GetDisplayedItem reads them), else the tooltip's displayed item.
local function linkOf(tooltip, data)
	if type(data) == "table" then
		local ok, link = pcall(function()
			local guid = str(data.guid) -- the GUID first, as GetDisplayedItem (Shift compares with it)
			if guid then return C_Item and C_Item.GetItemLinkByGUID and C_Item.GetItemLinkByGUID(guid) end
			return data.hyperlink
		end)
		if ok and str(link) then return link end
	end
	local ok, _, link = pcall(TooltipUtil.GetDisplayedItem, tooltip)
	return ok and str(link) or nil
end

-- A window row's item tooltip (Window.ItemTip) draws its own score lines: the hook adds none there.
local function windowRow(tooltip)
	if not tooltip.GetOwner then return false end
	local ok, owner = pcall(tooltip.GetOwner, tooltip)
	return ok and type(owner) == "table" and owner.psgItemTip == true
end

local function onItem(tooltip, data)
	if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end -- not the comparison tooltips
	if forbidden(tooltip) or windowRow(tooltip) then return end
	local link = linkOf(tooltip, data)
	if not link then return end
	local ok2, err = pcall(Tooltip.Add, tooltip, link)
	if not ok2 then ns.ReportOnce(link, err) end -- once per link per session, not on every redraw
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and TooltipUtil and TooltipUtil.GetDisplayedItem
	and Enum and Enum.TooltipDataType then
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onItem)
end

-- Shift redraws a tooltip only while it still shows the item we drew lines for (drawn[tooltip] =
-- link, set by Add, cleared on hide), never a unit/spell tooltip, and not in combat (the redraw runs
-- from an insecure event).
local function shownItem(tooltip)
	if forbidden(tooltip) or not (tooltip.IsShown and tooltip:IsShown() and tooltip.RefreshData) then return nil end
	if not tooltip.IsTooltipType then return nil end
	local ok, isItem = pcall(tooltip.IsTooltipType, tooltip, Enum.TooltipDataType.Item)
	if not ok or secret(isItem) or not isItem then return nil end
	local ok2, _, link = pcall(TooltipUtil.GetDisplayedItem, tooltip)
	if ok2 and type(link) == "string" and not secret(link) then return link end
	return nil
end

function Tooltip.OnModifier(key)
	if key ~= "LSHIFT" and key ~= "RSHIFT" then return end
	if InCombatLockdown and InCombatLockdown() then return end
	if not (Enum and Enum.TooltipDataType and TooltipUtil and TooltipUtil.GetDisplayedItem) then return end
	for _, tooltip in ipairs({ GameTooltip or false, ItemRefTooltip or false }) do
		local link = tooltip and drawn[tooltip]
		if link and shownItem(tooltip) == link then tooltip:RefreshData() end
	end
end
ns.RegisterEvent("MODIFIER_STATE_CHANGED", Tooltip.OnModifier)

for _, tooltip in ipairs({ GameTooltip or false, ItemRefTooltip or false }) do
	if tooltip and tooltip.HookScript then
		tooltip:HookScript("OnHide", function(self) drawn[self] = nil end)
	end
end
