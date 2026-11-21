-- Weights: the spec's weights for a band (the character's band first, "<" ">" step through the
-- others) and the spec switch (the same as /psg spec). No weight editing.
local ADDON, ns = ...
local Tab = {}
ns.TabWeights = Tab
local S = ns.Style
local C = S.C
local format = string.format

local view = { band = nil } -- shown band index; nil = the character's
Tab.view = view

local function bandsNow()
	local ctx = ns.Context.Get()
	if not ctx then return nil end
	local bands = ns.View.Bands(ctx.cls, ctx.spec)
	return ctx, bands, ns.View.BandIndex(bands, ctx.level)
end

local function initRow(row, d)
	if not row.made then
		row.made = true
		row.stat = S.Text(row, 12, C.text)
		row.stat:SetPoint("LEFT", 8, 0)
		row.stat:SetWidth(180)
		row.value = S.Text(row, 12, C.green)
		row.value:SetPoint("LEFT", 190, 0)
		row.value:SetWidth(60)
		row.value:SetJustifyH("RIGHT")
		row.bar = row:CreateTexture(nil, "ARTWORK")
		row.bar:SetPoint("LEFT", 262, 0)
		row.bar:SetHeight(10)
		row.bar:SetColorTexture(C.barFill[1], C.barFill[2], C.barFill[3], 1)
	end
	S.RowBg(row, d.index)
	row.stat:SetText(d.label)
	row.value:SetText(format("%.3f", d.value))
	row.bar:SetWidth(math.max(1, 120 * math.max(0, d.value) / d.max))
end

function Tab.Create(parent)
	local p = CreateFrame("Frame", nil, parent)
	local bar = CreateFrame("Frame", nil, p)
	bar:SetPoint("TOPLEFT")
	bar:SetSize(400, 30)
	S.Fill(bar, C.head)
	p.prev = S.Button(bar, "<", 24, 22, function() Tab.Step(-1) end, S.ACTION)
	p.prev:SetPoint("LEFT", 6, 0)
	p.band = S.Text(bar, 14, C.white)
	p.band:SetPoint("LEFT", 38, 0)
	p.band:SetWidth(320)
	p.next = S.Button(bar, ">", 24, 22, function() Tab.Step(1) end, S.ACTION)
	p.next:SetPoint("LEFT", 370, 0)
	p.how = S.Text(p, 11, C.label)
	p.how:SetPoint("TOPLEFT", 8, -36)
	p.how:SetWidth(390)
	p.list = S.List(p, 0, -56, 410, S.CONTENT.h - 56, 22, initRow)
	local t = S.Text(p, 13, C.white)
	t:SetPoint("TOPLEFT", 420, -8)
	t:SetText("Spec")
	p.radios = {}
	p.specSub = S.Text(p, 10, C.label)
	p.specSub:SetWidth(196)
	return p
end

-- the radios are made on the first refresh (the class's specs are known then)
local function radios(p, ctx)
	if #p.radios > 0 then return end
	local keys = { { "auto", "Automatic (talents)" } }
	for _, k in ipairs(ns.Spec.Keys(ctx.cls)) do keys[#keys + 1] = { k, S.Title(k) } end
	for i, k in ipairs(keys) do
		local b = S.Radio(p, k[2], function()
			if not ns.char then return end
			ns.char.spec = k[1]
			view.band = nil
			ns.Fire("STATE", "SPEC") -- as /psg spec: read the spec again, rescore, rebuild
			ns.Window.Refresh()
		end)
		b:SetSize(190, 20)
		b:SetPoint("TOPLEFT", 416, -30 - (i - 1) * 22)
		b.spec = k[1]
		p.radios[i] = b
	end
	p.specSub:SetPoint("TOPLEFT", 420, -34 - #keys * 22)
end

function Tab.Step(d)
	local _, bands, mine = bandsNow()
	if not bands then return end
	view.band = math.max(1, math.min(#bands, (view.band or mine) + d))
	ns.Window.Refresh()
end

function Tab.Refresh(p)
	local ctx, bands, mine = bandsNow()
	if not (ctx and bands and #bands > 0) then
		p.band:SetText("")
		p.how:SetText("")
		return S.SetList(p.list, {})
	end
	radios(p, ctx)
	local chosen = ns.char and ns.char.spec or "auto"
	for _, b in ipairs(p.radios) do b:Set(b.spec == chosen) end
	p.specSub:SetText(format("Now: %s, %s", S.Title(ctx.spec),
		ctx.specSource == "chosen" and "your choice" or (ctx.specSource == "talents" and "from your talents" or "the default (talents not read yet)")))
	local i = math.min(view.band or mine, #bands)
	local b = bands[i]
	p.band:SetText(format("Levels %d-%d", b.lo, b.upTo) .. (i == mine and " (your band)" or ""))
	p.prev:SetEnabled(i > 1)
	p.next:SetEnabled(i < #bands)
	p.how:SetText(format("An item's score = its stats x these weights, in points of %s.", ns.DATA.statLabels[ctx.ref] or ctx.ref))
	local rows = ns.View.WeightRows(b.w)
	local max = rows[1] and rows[1].value or 1
	for k, r in ipairs(rows) do
		r.index, r.max = k, max
	end
	S.SetList(p.list, rows)
end

function Tab.Release(p)
	view.band = nil
	S.SetList(p.list, {})
end

ns.Window.RegisterTab("weights", { create = Tab.Create, refresh = Tab.Refresh, release = Tab.Release })
