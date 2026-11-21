local T = require("t")
local FILES = { "Core.lua", "Rewards.lua" }
local ALL = { "Core.lua", "Data/Weights.lua", "Data/Suffixes.lua", "Data/Items.lua", "Items.lua", "Score.lua", "Equip.lua",
	"Tooltip.lua", "Rewards.lua" }
local ctx = { cls = "priest", level = 20, w = { int = 1 }, worn = { [1] = { inst = { id = 9, inv = 1 }, score = 5 } } }
local function head(int, sc, rl) return { id = 1, inv = 1, c = 4, sc = sc or 1, cm = 0, rl = rl or 10, stats = { int = int }, armor = 0, dps = 0 } end

-- A widget for the marks: textures, font strings, frames (shown state and text kept).
local function widget()
	local w = { shown = true }
	for _, m in ipairs({ "SetAllPoints", "SetFrameLevel", "SetPoint", "SetAtlas", "SetSize", "SetJustifyH" }) do w[m] = function() end end
	function w:Show() self.shown = true end
	function w:Hide() self.shown = false end
	function w:SetShown(v) self.shown = v and true or false end
	function w:IsShown() return self.shown end
	function w:SetText(t) self.text = t end
	function w:CreateTexture() return widget() end
	function w:CreateFontString() return widget() end
	return w
end

-- The quest giver's reward panel with these choices: { link | "currency" | false (no link yet) } ->
-- ns, buttons, set(i, v) (change a choice), event(name, ...)
local function panel(choices, items)
	local W = require("wow")
	local ns = T.addon(ALL)
	_G.CreateFrame = function() return widget() end
	ns.Context = { Get = function() return ctx end }
	ns.Live = { Instance = function(link)
		local v = items[link]
		if v == "pending" then return nil, "pending" end
		return v
	end }
	_G.GetNumQuestChoices = function() return #choices end
	_G.GetQuestItemInfoLootType = function(_, i) return choices[i] == "currency" and 1 or 0 end
	_G.GetQuestItemLink = function(_, i) local c = choices[i] if c ~= "currency" and c then return c end end
	local buttons = {}
	for i = 1, #choices do
		local b = widget()
		b.type, b.objectType = "choice", choices[i] == "currency" and "currency" or "item"
		b.Icon = widget()
		function b:GetID() return i end
		function b:GetFrameLevel() return 1 end
		buttons[i] = b
	end
	local reward = widget() reward.type = "reward" function reward:GetID() return 1 end
	buttons[#buttons + 1] = reward
	_G.QuestInfoRewardsFrame = { RewardButtons = buttons }
	_G.QuestInfoFrame = { rewardsFrame = QuestInfoRewardsFrame }
	_G.QuestFrameRewardPanel = widget()
	local function event(name, ...) ns._frame.scripts.OnEvent(ns._frame, name, ...) end
	local function set(i, v) choices[i] = v end
	W.flush()
	return ns, buttons, set, event
end
local function unpanel()
	_G.QuestInfoRewardsFrame, _G.QuestInfoFrame, _G.QuestFrameRewardPanel = nil, nil, nil
	_G.GetNumQuestChoices, _G.GetQuestItemInfoLootType, _G.GetQuestItemLink = nil, nil, nil
end
-- -> the mark on a button: nil (none), or { arrow = shown, text = gain text }
local function markOf(ns, b)
	local m = ns.Rewards.MarkOf(b)
	if not (m and m.shown) then return nil end
	return { arrow = m.arrow.shown, text = m.text.text, note = m.note and m.note.shown and m.note.text or nil }
end
return {
	pick = function()
		local R = T.addon(FILES).Rewards
		local best, up = R.Pick({ { index = 1, usable = true, gain = -1, score = 3 }, { index = 2, usable = true, gain = 2, score = 5 },
			{ index = 3, usable = false } })
		T.eq(best, 2); T.ok(up)
		best, up = R.Pick({ { index = 1, usable = true, gain = -3, score = 1 }, { index = 2, usable = true, gain = -1, score = 4 } })
		T.eq(best, 2); T.ok(not up)
		best = R.Pick({ { index = 1, usable = true, gain = 1, score = 3 }, { index = 2, usable = true, gain = 1, score = 4 } })
		T.eq(best, 2, "tie: higher score")
		best = R.Pick({ { index = 1, usable = true, gain = 1, score = 4 }, { index = 2, usable = true, gain = 1, score = 4 } })
		T.eq(best, 1, "full tie: the earlier choice")
		T.eq(R.Pick({ { index = 1, usable = false } }), nil)
		T.eq(R.Pick({ { index = 1, pending = true, usable = true, gain = 9 } }), nil, "wait for item data")
	end,
	-- The best usable choice gets our arrow and its gain (as the tooltip shows it); a currency choice
	-- with the same button ID and a choice the character cannot wear are never marked.
	mark_best = function()
		local ns, B = panel({ "currency", "down", "up", "mail" },
			{ down = head(4), up = head(7), mail = head(30, 3) })
		ns.Rewards.Mark()
		T.eq(markOf(ns, B[1]), nil, "currency")
		T.eq(markOf(ns, B[2]), nil)
		local m = markOf(ns, B[3])
		T.ok(m and m.arrow, "arrow on the best")
		T.ok(m.text:find("+2.0", 1, true), m.text)
		T.eq(markOf(ns, B[4]), nil, "mail: a priest cannot wear it")
		T.eq(markOf(ns, B[5]), nil, "not a choice")
		unpanel()
	end,
	-- No choice is an upgrade: the least loss is marked in grey, without the arrow.
	mark_no_upgrade = function()
		local ns, B = panel({ "a", "b" }, { a = head(2), b = head(4) })
		ns.Rewards.Mark()
		local m = markOf(ns, B[2])
		T.ok(m and not m.arrow, "no arrow")
		T.ok(m.text:find("-1.0", 1, true) and m.text:find("cccccc", 1, true), m.text)
		T.eq(markOf(ns, B[1]), nil)
		unpanel()
	end,
	-- One choice or none usable: nothing to pick, no mark.
	mark_needs_two_choices = function()
		local ns, B = panel({ "up" }, { up = head(7) })
		ns.Rewards.Mark()
		T.eq(markOf(ns, B[1]), nil)
		unpanel()
	end,
	-- Item data still coming: no mark yet; the item's data arriving marks the panel.
	mark_waits_for_item_data = function()
		local W = require("wow")
		local items = { a = head(2), up = "pending" }
		local ns, B, _, event = panel({ "a", "up" }, items)
		ns.Rewards.Mark()
		T.eq(markOf(ns, B[1]), nil); T.eq(markOf(ns, B[2]), nil)
		items.up = head(7)
		event("GET_ITEM_INFO_RECEIVED", 1, true)
		W.flush()
		T.ok(markOf(ns, B[2]), "marked once the data came")
		unpanel()
	end,
	-- The best choice needs a level above the character's (the tooltip allows up to 5): still picked
	-- (the reward is kept until usable), but the mark does not claim an upgrade now: no arrow, the gain
	-- in gold, and a "lvl N" note.
	mark_above_level = function()
		local ns, B = panel({ "a", "later" }, { a = head(6), later = head(9, 1, 23) })
		ns.Rewards.Mark()
		local m = markOf(ns, B[2])
		T.ok(m, "still picked")
		T.ok(not m.arrow, "no 'upgrade now' arrow")
		T.ok(m.note and m.note:find("lvl 23", 1, true), tostring(m.note))
		T.ok(m.text:find("+4.0", 1, true) and m.text:find("ffd100", 1, true), m.text)
		T.eq(markOf(ns, B[1]), nil)
		unpanel()
		-- Above level and no upgrade either (both choices below what is worn): grey, not gold.
		ns, B = panel({ "a", "later" }, { a = head(2), later = head(4, 1, 23) })
		ns.Rewards.Mark()
		m = markOf(ns, B[2])
		T.ok(m and not m.arrow, "picked, no arrow")
		T.ok(m.text:find("-1.0", 1, true) and m.text:find("cccccc", 1, true) and not m.text:find("ffd100", 1, true), m.text)
		unpanel()
		ns, B = panel({ "a", "b" }, { a = head(6), b = head(4) })
		ns.Rewards.Mark()
		m = markOf(ns, B[1])
		T.ok(m and m.arrow and m.note == nil, "no note at the character's level")
		unpanel()
	end,
	-- A choice whose item data never comes (still pending after the retries) counts as unusable, so the
	-- others are marked.
	mark_gives_up_on_pending = function()
		local W = require("wow")
		local ns, B = panel({ "a", "never", "b" }, { a = head(6), b = head(4), never = "pending" })
		ns.Rewards.Mark()
		T.eq(markOf(ns, B[1]), nil, "waits first")
		for _ = 1, 5 do W.flush() end
		T.ok(markOf(ns, B[1]), "marked after the retries")
		T.eq(markOf(ns, B[2]), nil)
		T.eq(#W.timers, 0, "no more retries")
		unpanel()
	end,
	-- The client laying out the panel again (another quest, or the same panel refreshed) clears our
	-- marks at once, so no stale mark shows for a frame before the redraw.
	display_clears_marks_at_once = function()
		local W = require("wow")
		_G.QuestInfo_Display = function() end
		local ns, B, set = panel({ "a", "up" }, { a = head(2), up = head(7), low = head(1) })
		QuestInfo_Display()
		W.flush()
		T.ok(markOf(ns, B[2]))
		set(2, "low") -- now the first choice is the best
		QuestInfo_Display()
		T.eq(markOf(ns, B[2]), nil, "the old mark is gone before the next frame")
		W.flush()
		T.ok(markOf(ns, B[1]), "the new best marked")
		_G.QuestInfo_Display = nil
		unpanel()
	end,
	-- Only the quest giver's reward panel: not the detail panel or the quest log; hidden when it closes.
	mark_only_reward_panel = function()
		local ns, B, _, event = panel({ "a", "up" }, { a = head(2), up = head(7) })
		QuestFrameRewardPanel:Hide()
		ns.Rewards.Mark()
		T.eq(markOf(ns, B[2]), nil, "panel hidden")
		QuestFrameRewardPanel:Show()
		QuestInfoFrame.questLog = true
		ns.Rewards.Mark()
		T.eq(markOf(ns, B[2]), nil, "quest log")
		QuestInfoFrame.questLog = nil
		ns.Rewards.Mark()
		T.ok(markOf(ns, B[2]))
		event("QUEST_FINISHED")
		T.eq(markOf(ns, B[2]), nil, "hidden on close")
		unpanel()
	end,
	-- QuestInfo_Display (the client laying out the panel) and new scores redraw the marks.
	mark_on_display_and_scores = function()
		local W = require("wow")
		_G.QuestInfo_Display = function() end
		local ns, B = panel({ "a", "up" }, { a = head(2), up = head(7) })
		QuestInfo_Display()
		W.flush()
		T.ok(markOf(ns, B[2]), "marked after the panel's layout")
		ctx.worn[1].score = 9 -- now nothing is an upgrade
		ns.Fire("SCORES_CHANGED")
		W.flush()
		local m = markOf(ns, B[2])
		T.ok(m and not m.arrow, "redrawn with the new scores")
		ctx.worn[1].score = 5
		_G.QuestInfo_Display = nil
		unpanel()
	end,
}
