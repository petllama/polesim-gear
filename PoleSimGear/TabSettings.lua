-- Settings: the account-wide switches (minimap button, tooltip line, upgrade arrows, reward mark, the
-- equip prompt), the look ahead a new character starts with, the equip prompt's minimum gain and never
-- list, Polestar's gear-score question, the character's spec (Automatic or a spec with weights: the
-- way out when the talents land on one without, e.g. Feral), recording for PoleSim and update notices
-- (the hidden channel switch; a newer release heard of). Recording: on/off, asking to upload on/off and
-- its interval (2/4/6 h of active play).
local ADDON, ns = ...
local Tab = {}
ns.TabSettings = Tab
local S = ns.Style
local C = S.C

local function minimapShown()
	local db = ns.db or {}
	return not (type(db.minimap) == "table" and db.minimap.hide)
end

-- { label, get, set(on) }
Tab.SWITCHES = {
	{ "Minimap button", minimapShown, function(on) if ns.Minimap then ns.Minimap.SetHidden(not on) end end },
	{ "Score line in item tooltips", function() return ns.Options.Get("tooltip") end, function(on) ns.Options.Set("tooltip", on) end },
	{ "Upgrade arrows on bags, merchants, mail and the auction house", function() return ns.Options.Get("arrows") end,
		function(on) ns.Options.Set("arrows", on) end },
	{ "Mark the best quest reward", function() return ns.Options.Get("rewardMark") end, function(on) ns.Options.Set("rewardMark", on) end },
	{ "Prefer upgrades from upcoming guide quests (within 2 levels)", function() return ns.Options.Get("preferQuest") end,
		function(on) ns.Options.Set("preferQuest", on) end },
	{ "Ask to equip upgrades I pick up", function() return ns.Options.Get("askEquip") end, function(on) ns.Options.Set("askEquip", on) end },
	-- Update.lua: off = leave the channel, send nothing
	{ "Update notices (joins a hidden PoleSimGear channel)", function() return ns.Options.Get("shareVersion") end,
		function(on) ns.Options.Set("shareVersion", on) end },
}
local ROW = 24

-- the minimum gain choices: { { value, text } }
function Tab.MinGainList()
	local out = {}
	for _, v in ipairs(ns.Prompt.MIN_CHOICES) do out[#out + 1] = { value = v, text = v == 0 and "Any gain" or ("+" .. v .. "% or more") } end
	return out
end

function Tab.Create(parent)
	local p = CreateFrame("Frame", nil, parent)
	p.checks = {}
	for i, sw in ipairs(Tab.SWITCHES) do
		local b = S.Check(p, sw[1], function(on)
			sw[3](on)
			ns.Window.Refresh()
		end)
		b:SetSize(420, 20)
		b:SetPoint("TOPLEFT", 16, -12 - (i - 1) * ROW)
		b.get = sw[2]
		p.checks[i] = b
	end
	local y = -12 - #Tab.SWITCHES * ROW - 4
	local l = S.Text(p, 12, C.text)
	l:SetPoint("TOPLEFT", 16, y)
	l:SetText("Look ahead for a new character")
	p.ahead = S.Dropdown(p, 146, 24, ns.Window.AheadList, function(a) return ns.Options.Get("ahead") == a end,
		function(a) ns.Options.Set("ahead", a) ns.Window.Refresh() end)
	p.ahead:SetPoint("TOPLEFT", 240, y + 5)
	-- the upgrade prompt: minimum gain, the never list, and Polestar's own prompt
	y = y - 30
	local g = S.Text(p, 12, C.text)
	g:SetPoint("TOPLEFT", 16, y)
	g:SetText("Minimum gain to ask to equip")
	p.minGain = S.Dropdown(p, 146, 24, Tab.MinGainList, function(v) return ns.Options.Get("askMinPct") == v end,
		function(v) ns.Options.Set("askMinPct", v) ns.Window.Refresh() end)
	p.minGain:SetPoint("TOPLEFT", 240, y + 5)
	p.never = S.Text(p, 11, C.label)
	p.never:SetPoint("TOPLEFT", 400, y)
	p.clearNever = S.Button(p, "Clear", 50, 20, function()
		ns.Prompt.ClearNever()
		ns.Window.Refresh()
	end, S.ACTION)
	p.clearNever:SetPoint("TOPLEFT", 520, y + 4)
	p.clearNever.tip = "Ask again about the items you right-clicked Never for"
	y = y - 22
	p.promptNote = S.Text(p, 11, C.label)
	p.promptNote:SetPoint("TOPLEFT", 16, y)
	y = y - 22
	local t = S.Text(p, 13, C.white)
	t:SetPoint("TOPLEFT", 16, y)
	t:SetText("Polestar's gear scores")
	p.answer = S.Text(p, 12, C.label)
	p.answer:SetPoint("TOPLEFT", 16, y - 18)
	p.answer:SetWidth(420)
	p.ask = S.Button(p, "Ask again", 90, 20, function()
		if ns.Coexist then ns.Coexist.AskAgain() end
		ns.Window.Refresh()
	end, S.ACTION)
	p.ask:SetPoint("TOPLEFT", 440, y - 14)
	-- the spec (as the Weights tab and /psg spec)
	y = y - 50
	local sl = S.Text(p, 12, C.text)
	sl:SetPoint("TOPLEFT", 16, y)
	sl:SetText("Spec")
	p.spec = S.Dropdown(p, 146, 24, Tab.SpecList, function(v) return ((ns.char and ns.char.spec) or "auto") == v end, Tab.SetSpec)
	p.spec:SetPoint("TOPLEFT", 240, y + 5)
	p.healer = S.Text(p, 11, C.label)
	p.healer:SetPoint("TOPLEFT", 16, y - 22)
	p.healer:SetWidth(560)
	p.healer:SetText(Tab.HEALER_NOTE)
	-- recording for PoleSim (Record.lua): the account-wide answer and asking to upload (right column)
	local X, CW = 590, 230
	local rt = S.Text(p, 13, C.white)
	rt:SetPoint("TOPLEFT", X, -12)
	rt:SetText("Recording for PoleSim")
	p.recChecks = {}
	for i, sw in ipairs(Tab.RECORD_SWITCHES) do
		local b = S.Check(p, sw[1], function(on)
			sw[3](on)
			ns.Window.Refresh()
		end)
		b:SetSize(CW, 20)
		b:SetPoint("TOPLEFT", X, -34 - (i - 1) * ROW)
		b.get = sw[2]
		p.recChecks[i] = b
	end
	-- "Ask me to upload every [2 h]" of active play: our own dropdown right of the switch's label
	local DW = 52
	p.recChecks[2]:SetSize(CW - DW - 4, 20) -- the switch's click area ends before the dropdown
	p.recEvery = S.Dropdown(p, DW, 22, Tab.RecEveryList, function(h) return ns.Options.Get("recEvery") == h end,
		function(h) ns.Options.Set("recEvery", h) ns.Window.Refresh() end)
	p.recEvery:SetPoint("TOPLEFT", X + CW - DW, -34 - ROW + 1)
	p.recEvery.tip = "Hours of active play between upload reminders, counted from your last upload"
	local ry = -34 - #Tab.RECORD_SWITCHES * ROW - 2
	p.recStatus = S.Text(p, 11, C.label)
	p.recStatus:SetPoint("TOPLEFT", X, ry)
	p.recStatus:SetWidth(CW)
	for i, text in ipairs(Tab.RECORD_NOTES) do
		local t = S.Text(p, 11, C.label)
		t:SetPoint("TOPLEFT", X, ry - 16 * i)
		t:SetWidth(CW)
		t:SetText(text)
	end
	p.recExport = S.Button(p, "Export now", 90, 20, function() ns.RecordUI.OpenExport() end, S.ACTION)
	p.recExport:SetPoint("TOPLEFT", X, ry - 16 * (#Tab.RECORD_NOTES + 1) - 4)
	p.recExport.tip = "The copy-paste export for polesim.petllama.com/upload (also /psg export)"
	-- update notices (Update.lua): sharing our version, and what is known (right column, under recording)
	local uy = ry - 16 * (#Tab.RECORD_NOTES + 1) - 36
	local ut = S.Text(p, 13, C.white)
	ut:SetPoint("TOPLEFT", X, uy)
	ut:SetText("Update notices")
	p.updateStatus = S.Text(p, 11, C.label)
	p.updateStatus:SetPoint("TOPLEFT", X, uy - 22)
	p.updateStatus:SetWidth(CW)
	for i, text in ipairs(Tab.SHARE_NOTES) do
		local t = S.Text(p, 11, C.label)
		t:SetPoint("TOPLEFT", X, uy - 22 - 16 * i)
		t:SetWidth(CW)
		t:SetText(text)
	end
	return p
end

Tab.RECORD_NOTES = { "for this character; about 20 h", "are kept. No names, chat, gold", "or map position." }
-- { label, get, set(on) }
Tab.RECORD_SWITCHES = {
	{ "Record leveling data for PoleSim", function() return ns.Options.Get("record") end, function(on)
		ns.Options.Set("record", on)
		ns.Options.Set("recAsked", true)
	end },
	{ "Ask me to upload every", function() return ns.Options.Get("recPrompt") end,
		function(on) ns.Options.Set("recPrompt", on) end },
}
-- the upload interval choices (Record.ASK_HOURS): { { value, text } }
function Tab.RecEveryList()
	local out = {}
	for _, h in ipairs(ns.Record.ASK_HOURS) do out[#out + 1] = { value = h, text = h .. " h" } end
	return out
end

-- Update notices (Options shareVersion, on by default; the switch is in Tab.SWITCHES): what is known.
Tab.SHARE_NOTES = { "Only the version number is sent,", "on a hidden channel. /psg version" }
function Tab.UpdateText()
	local line = ns.Update and ns.Update.Line()
	if line then return line end
	return "No newer version heard of"
end

-- The spec choices: Automatic (talents), then the class's specs with weights (Spec.Keys).
function Tab.SpecList()
	local out = { { value = "auto", text = "Automatic (talents)" } }
	local cls = ns.Context.ClassKey()
	for _, k in ipairs(cls and ns.Spec.Keys(cls) or {}) do out[#out + 1] = { value = k, text = S.Title(k) } end
	return out
end
function Tab.SetSpec(v)
	if not ns.char then return end
	ns.char.spec = v
	if ns.TabWeights and ns.TabWeights.view then ns.TabWeights.view.band = nil end
	ns.Fire("STATE", "SPEC") -- as /psg spec: read the spec again, rescore, rebuild
	ns.Window.Refresh()
end
-- (Restoration, Holy, Discipline: kill-sim weights, the website's)
Tab.HEALER_NOTE = "Healer specs' weights are for leveling (killing while questing), not dungeon healing."

-- The never list's count, and whose prompt asks (ours, or Polestar's while its Gear is on).
function Tab.NeverText(n)
	if n == 0 then return "No item never asked" end
	return n .. (n == 1 and " item never asked" or " items never asked")
end
function Tab.PromptNote()
	local Co = ns.Coexist
	if Co and Co.PolestarGearOn() then return "Polestar's Gear is on: its own \"Wear it\" asks, ours stays quiet." end
	return "Right-click the equip prompt: Never for this item. /psg ask: every upgrade in your bags."
end

function Tab.AnswerText()
	local Co = ns.Coexist
	if not (Co and Co.PolestarGearOn()) then return "Polestar's gear scores are off: only PoleSim's show." end
	local a = ns.db and ns.db.askedPolestarGear
	if a == "yes" then return "You answered: Yes" end
	if a == "no" then return "You answered: No (both show; ours says PoleSim)" end
	return "Not asked yet"
end

function Tab.Refresh(p)
	for _, b in ipairs(p.checks) do b:Set(b.get()) end
	p.ahead:Update()
	p.answer:SetText(Tab.AnswerText())
	local n = ns.Prompt.NeverCount()
	p.never:SetText(Tab.NeverText(n))
	p.clearNever:SetShown(n > 0)
	p.promptNote:SetText(Tab.PromptNote())
	p.minGain:Update()
	p.spec:Update()
	for _, b in ipairs(p.recChecks) do b:Set(b.get()) end
	p.recEvery:Update()
	p.recStatus:SetText(ns.Record.Status())
	p.updateStatus:SetText(Tab.UpdateText())
end

ns.Window.RegisterTab("settings", { create = Tab.Create, refresh = Tab.Refresh })
