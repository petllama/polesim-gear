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
