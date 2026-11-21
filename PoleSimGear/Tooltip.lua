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
	else
		right = format("%+.1f", cmp.gain) .. (cmp.base > 0.01 and format(" (%+.0f%%)", 100 * cmp.gain / cmp.base) or "")
		color = cmp.gain > 1e-6 and GREEN or (cmp.gain < -1e-6 and RED or GREY)
	end
	lines[1] = { (labelled and "PoleSim score " or "Score ") .. format("%.1f", cmp.score), right, GOLD, color }
	lines[2] = { format("%s, levels %d-%d: points of %s", title(ctx.spec), ctx.lo, ctx.band.upTo, label(ctx.ref)), nil, GREY }
	if (inst.rl or 0) > ctx.level then lines[#lines + 1] = { format("requires level %d", inst.rl), nil, GREY } end
	if cmp.note then lines[#lines + 1] = { cmp.note, nil, GREY } end
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
	if not cmp.equipped then
		lines[#lines + 1] = { "  minus worn", format("%.2f", cmp.base), GREY, GREY }
		lines[#lines + 1] = { "  gain", format("%+.2f", cmp.gain), GREY, color }
	end
	return lines
end

-- The live hook: every item tooltip (GameTooltip, ItemRefTooltip) gets the lines for items the character
-- can use, up to AHEAD levels above; Shift redraws it with the breakdown.
local AHEAD = 5 -- items up to this many levels above the character still get a line
local secret = issecretvalue or function() return false end

function Tooltip.Add(tooltip, link)
	local ctx = ns.Context.Get()
	if not (ctx and link) then return end
	local inst = ns.Live.Instance(link)
	if not inst or not ns.Equip.CanUse(inst, ctx.cls, ctx.level) or (inst.rl or 0) > ctx.level + AHEAD then return end
	local cmp = ns.Equip.Compare(inst, ctx.w, ctx.cls, ctx.worn, false)
	if not cmp then return end
	local labelled = ns.Coexist and ns.Coexist.Label() or false
	for _, l in ipairs(Tooltip.Lines(cmp, inst, ctx, IsShiftKeyDown(), labelled)) do
		local a, b = l[3] or GREY, l[4] or GREY
		if l[2] then
			tooltip:AddDoubleLine(l[1], l[2], a[1], a[2], a[3], b[1], b[2], b[3])
		else
			tooltip:AddLine(l[1], a[1], a[2], a[3], true)
		end
	end
end

local function forbidden(tooltip)
	if not tooltip.IsForbidden then return false end
	local ok, f = pcall(tooltip.IsForbidden, tooltip)
	return not ok or secret(f) or f
end

local function onItem(tooltip)
	if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end -- not the comparison tooltips
	if forbidden(tooltip) then return end
	local ok, _, link = pcall(TooltipUtil.GetDisplayedItem, tooltip)
	if not ok or type(link) ~= "string" or secret(link) then return end
	local ok2, err = pcall(Tooltip.Add, tooltip, link)
	if not ok2 then geterrorhandler()(err) end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and TooltipUtil and TooltipUtil.GetDisplayedItem
	and Enum and Enum.TooltipDataType then
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, onItem)
end

ns.RegisterEvent("MODIFIER_STATE_CHANGED", function(key)
	if (key == "LSHIFT" or key == "RSHIFT") and GameTooltip and GameTooltip:IsShown() and GameTooltip.RefreshData then
		GameTooltip:RefreshData()
	end
end)
