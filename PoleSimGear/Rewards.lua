-- Quest reward pick: at turn-in, mark the choice that is best for the character (our arrow and the
-- gain on the icon). Choices it cannot use are never picked.
local ADDON, ns = ...
local Rewards = {}
ns.Rewards = Rewards

-- choices = { { index, usable, gain, score, pending }, ... } -> best index | nil, is an upgrade
-- Best: the largest gain; ties: the higher score, then the earlier choice. Nothing while any choice's
-- item data is still pending.
function Rewards.Pick(choices)
	local best
	for _, c in ipairs(choices) do
		if c.pending then return nil end
		if c.usable then
			if not best or c.gain > best.gain + 1e-9 or (math.abs(c.gain - best.gain) <= 1e-9 and c.score > best.score + 1e-9) then
				best = c
			end
		end
	end
	if not best then return nil end
	return best.index, best.gain > 1e-6
end

-- The mark: the client's green bag arrow at the left edge of the icon and the gain at its bottom
-- (green for an upgrade, grey otherwise), on a frame of our own over the button. Polestar's reward
-- marks use the icon's corners (its arrow top-left, its coin top-right) and a ring around the icon;
-- ours keeps clear of all three.
local marks = {}
local function mark(button, gain, upgrade)
	local m = marks[button]
	if not m then
		local icon = button.Icon or button
		m = CreateFrame("Frame", nil, button)
		m:SetAllPoints(icon)
		m:SetFrameLevel(button:GetFrameLevel() + 5)
		m.arrow = m:CreateTexture(nil, "OVERLAY")
		m.arrow:SetAtlas("bags-greenarrow", true)
		m.arrow:SetPoint("RIGHT", m, "LEFT", 6, 0)
		m.text = m:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
		m.text:SetPoint("BOTTOM", m, "BOTTOM", 0, 1)
		marks[button] = m
	end
	m.arrow:SetShown(upgrade)
	m.text:SetText((upgrade and "|cff4cff4c" or "|cffcccccc") .. string.format("%+.1f", gain) .. "|r")
	m:Show()
end
function Rewards.MarkOf(button) return marks[button] end

local function hideMarks()
	for _, m in pairs(marks) do m:Hide() end
end

-- The quest giver's reward panel at turn-in (QuestFrameRewardPanel; QuestInfo_Display sets
-- QuestInfoFrame.rewardsFrame to QuestInfoRewardsFrame there, the map's own frame in map view, and
-- QuestInfoFrame.questLog for the quest log).
local function rewardPanel()
	if not (QuestFrameRewardPanel and QuestFrameRewardPanel:IsShown() and QuestInfoFrame) then return nil end
	if QuestInfoFrame.questLog then return nil end
	local frame = QuestInfoFrame.rewardsFrame
	if not (frame and frame == QuestInfoRewardsFrame and type(frame.RewardButtons) == "table") then return nil end
	return frame
end

-- The choices as Pick reads them, scored by the tooltip's per-link result (Tooltip.Lookup), so the gain
-- on the icon is the tooltip's. A currency choice (GetQuestItemInfoLootType 1) is not an item.
function Rewards.Choices(ctx)
	local choices = {}
	for i = 1, GetNumQuestChoices() or 0 do
		local c = { index = i }
		local currency = GetQuestItemInfoLootType and GetQuestItemInfoLootType("choice", i) == 1
		if not currency then
			local link = GetQuestItemLink("choice", i)
			local hit, wait = nil, not link
			if link then hit, wait = ns.Tooltip.Lookup(link, ctx) end
			c.pending = wait and not hit or nil
			if hit then
				local cmp = hit[2]
				c.usable, c.gain, c.score = true, cmp.equipped and 0 or cmp.gain, cmp.score
			end
		end
		choices[i] = c
	end
	return choices
end

local RETRIES, RETRY_DELAY = 3, 0.3
local tries = 0
function Rewards.Mark()
	hideMarks()
	local frame = rewardPanel()
	local ctx = frame and ns.Context.Get()
	if not ctx then return end
	local choices = Rewards.Choices(ctx)
	if #choices < 2 then return end
	local best, upgrade = Rewards.Pick(choices)
	if not best then
		for _, c in ipairs(choices) do
			if c.pending and tries < RETRIES then -- item data on its way (GET_ITEM_INFO_RECEIVED redraws too)
				tries = tries + 1
				C_Timer.After(RETRY_DELAY, Rewards.Mark)
				break
			end
		end
		return
	end
	tries = 0
	for _, b in pairs(frame.RewardButtons) do
		if b.type == "choice" and b.objectType == "item" and b:IsShown() and b:GetID() == best then
			mark(b, choices[best].gain, upgrade)
		end
	end
end

-- One redraw on the next frame after the panel's layout or new data.
local queued = false
local function schedule()
	if queued then return end
	queued = true
	C_Timer.After(0, function()
		queued = false
		Rewards.Mark()
	end)
end

if QuestInfo_Display then hooksecurefunc("QuestInfo_Display", schedule) end
ns.RegisterEvent("QUEST_COMPLETE", function() tries = 0 end)
ns.RegisterEvent("QUEST_FINISHED", hideMarks)
ns.RegisterEvent("GET_ITEM_INFO_RECEIVED", function() if rewardPanel() then schedule() end end)
ns.On("SCORES_CHANGED", function() if rewardPanel() then schedule() end end)
