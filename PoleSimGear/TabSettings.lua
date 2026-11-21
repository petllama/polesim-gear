-- Settings: the account-wide switches (minimap button, tooltip line, upgrade arrows, reward mark),
-- the look ahead a new character starts with, and Polestar's gear-score question.
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
}

function Tab.Create(parent)
	local p = CreateFrame("Frame", nil, parent)
	p.checks = {}
	for i, sw in ipairs(Tab.SWITCHES) do
		local b = S.Check(p, sw[1], function(on)
			sw[3](on)
			ns.Window.Refresh()
		end)
		b:SetSize(420, 20)
		b:SetPoint("TOPLEFT", 16, -16 - (i - 1) * 28)
		b.get = sw[2]
		p.checks[i] = b
	end
	local y = -16 - #Tab.SWITCHES * 28 - 8
	local l = S.Text(p, 12, C.text)
	l:SetPoint("TOPLEFT", 16, y)
	l:SetText("Look ahead for a new character")
	p.ahead = S.Dropdown(p, 146, 24, ns.Window.AheadList, function(a) return ns.Options.Get("ahead") == a end,
		function(a) ns.Options.Set("ahead", a) ns.Window.Refresh() end)
	p.ahead:SetPoint("TOPLEFT", 240, y + 5)
	y = y - 40
	local t = S.Text(p, 13, C.white)
	t:SetPoint("TOPLEFT", 16, y)
	t:SetText("Polestar's gear scores")
	p.answer = S.Text(p, 12, C.label)
	p.answer:SetPoint("TOPLEFT", 16, y - 20)
	p.answer:SetWidth(420)
	p.ask = S.Button(p, "Ask again", 90, 20, function()
		if ns.Coexist then ns.Coexist.AskAgain() end
		ns.Window.Refresh()
	end, S.ACTION)
	p.ask:SetPoint("TOPLEFT", 440, y - 16)
	return p
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
end

ns.Window.RegisterTab("settings", { create = Tab.Create, refresh = Tab.Refresh })
