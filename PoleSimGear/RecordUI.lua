-- The recorder's dialogs, all our own frames (Style), never StaticPopup or Blizzard's Menu (taint):
--   * the opt-in question, once per account on the first load of a version with the recorder;
--   * the upload card every 4 h of ACTIVE recorded play since the last confirmed upload, at a calm
--     moment (out of combat, not in an instance, not casting, no other PoleSim popup, not at the
--     auction house, mail, a vendor or a trainer): [Copy export] [Later] (again after 1 h of play)
--     [Stop asking] (recording goes on; /psg export still works; Settings asks again);
--   * the export window: one line of text, focused and highlighted for Ctrl+C, "Part i/n" with Next
--     for big exports, [I uploaded it] -> the website's 6-character code -> the exported records go.
local ADDON, ns = ...
local UI = {}
ns.RecordUI = UI

local format = string.format
UI.OPTIN_DELAY = 8 -- seconds after login before the opt-in question
UI.LATER_SECONDS = 3600
UI.URL = "polesim.petllama.com/upload"
UI.BUSY_FRAMES = { "AuctionHouseFrame", "MailFrame", "MerchantFrame", "ClassTrainerFrame", "TradeFrame", "BankFrame",
	"GossipFrame", "QuestFrame" }

local optIn, card, win

local function shown(f) return f ~= nil and f:IsShown() end
function UI.OptInFrame() return optIn end
function UI.OptInShown() return shown(optIn) end
function UI.UploadFrame() return card end
function UI.UploadShown() return shown(card) end
function UI.ExportFrame() return win end

-- Another PoleSim popup open: the equip card, our dropdown/context popup.
function UI.OtherPopup()
	if ns.Prompt and ns.Prompt.Frame and shown(ns.Prompt.Frame()) then return true end
	local p = ns.Style and ns.Style.PopupFrame and ns.Style.PopupFrame()
	return shown(p)
end

local function value(fn, ...)
	if type(fn) ~= "function" then return nil end
	local okc, v = pcall(fn, ...)
	if not okc or (issecretvalue and issecretvalue(v)) then return nil end
	return v
end

-- -> calm, why not
function UI.Calm()
	if ns.Record.InCombat() then return false, "combat" end
	if value(IsInInstance) then return false, "instance" end
	if value(UnitCastingInfo, "player") or value(UnitChannelInfo, "player") then return false, "casting" end
	for _, name in ipairs(UI.BUSY_FRAMES) do
		local f = _G[name]
		if type(f) == "table" and type(f.IsShown) == "function" and f:IsShown() then return false, name end
	end
	if UI.OtherPopup and UI.OtherPopup() then return false, "popup" end
	if shown(optIn) or shown(card) or shown(win) then return false, "ours" end
	return true
end

-- Dialog frame ----------------------------------------------------------------------------------------
local function dialog(w, h)
	local S, C = ns.Style, ns.Style.C
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetSize(w, h)
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	if f.RegisterForDrag then f:RegisterForDrag("LeftButton") end
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
	f.bg = S.Fill(f, C.inner, 0.97)
	f.border = S.Border(f, C.ddBorder)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
	return f
end
local function line(f, y, text, size, colour, w)
	local S = ns.Style
	local t = S.Text(f, size or 12, colour)
	t:SetPoint("TOPLEFT", 16, y)
	t:SetWidth(w or (f:GetWidth() - 32))
	t:SetWordWrap(true)
	t:SetText(text)
	return t
end

-- The opt-in question --------------------------------------------------------------------------------
UI.OPTIN_TITLE = "Help improve PoleSim's gear weights?"
UI.OPTIN_TEXT = {
	"PoleSim Gear can record how this character levels, so PoleSim's model (fight lengths, kills per hour, "
		.. "rest, regen) can be checked against real play. It stays in your SavedVariables; every 4 hours of play it "
		.. "offers a copy-paste export for " .. UI.URL .. ".",
	"Recorded: level, class, race, character stats, regen, worn item ids, talents; each fight's length, the mobs' "
		.. "type and level, kills and XP, your spell casts; meals, deaths, XP and rested, pauses.",
	"Never recorded: names (yours, realm, guild, party or mobs), chat, gold, map position, health or mana.",
	"You can turn it off any time in Settings.",
}
local function answer(yes)
	ns.Options.Set("record", yes)
	ns.Options.Set("recAsked", true)
	if optIn then optIn:Hide() end
	ns.Print(yes and "Recording leveling data for PoleSim (Settings to turn it off; /psg export)." or "Not recording (Settings to change it).")
end
function UI.ShowOptIn()
	if not optIn then
		local S, C = ns.Style, ns.Style.C
		local f = dialog(460, 262)
		local title = S.Text(f, 14, C.gold)
		title:SetPoint("TOP", 0, -14)
		title:SetText(UI.OPTIN_TITLE)
		local y = -42
		for i, text in ipairs(UI.OPTIN_TEXT) do
			local t = line(f, y, text, 12, i == 1 and C.text or C.label)
			-- the wrapped height (an estimate before the client has laid it out)
			local h = t.GetStringHeight and t:GetStringHeight()
			if type(h) ~= "number" or h <= 0 then h = math.ceil(#text * 12 * 0.62 / 428) * 15 end
			y = y - h - 10
		end
		f:SetHeight(-y + 52)
		f.yes = S.Button(f, "Yes, record", 120, 24, function() answer(true) end, S.TAB_ON)
		f.yes:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -6, 14)
		f.no = S.Button(f, "No thanks", 120, 24, function() answer(false) end, S.ACTION)
		f.no:SetPoint("BOTTOMLEFT", f, "BOTTOM", 6, 14)
		optIn = f
	end
	optIn:Show()
end

-- The upload card ------------------------------------------------------------------------------------
function UI.CardText()
	local r = ns.Record.Data()
	local h = r and math.floor(r.since / 3600) or 0
	return format("%d h of leveling recorded. Upload it?", math.max(1, h))
end
local function later()
	local r = ns.Record.Data()
	if r then r.askAt = r.since + UI.LATER_SECONDS end
	card:Hide()
end
local function stop()
	ns.Options.Set("recPrompt", false)
	card:Hide()
	ns.Print("Recording goes on; it won't ask again. /psg export any time, or Settings to be asked again.")
end
function UI.ShowCard()
	if not card then
		local S, C = ns.Style, ns.Style.C
		local f = CreateFrame("Frame", nil, UIParent)
		f:SetSize(340, 86)
		f:SetFrameStrata("HIGH")
		f:SetClampedToScreen(true)
		f:EnableMouse(true)
		f.bg = S.Fill(f, C.inner, 0.97)
		f.border = S.Border(f, C.ddBorder)
		f:SetPoint("TOP", UIParent, "TOP", 0, -140)
		f.title = S.Text(f, 12, C.gold)
		f.title:SetPoint("TOPLEFT", 12, -10)
		f.title:SetText("PoleSim Gear")
		f.text = S.Text(f, 12, C.text)
		f.text:SetPoint("TOPLEFT", 12, -30)
		f.copy = S.Button(f, "Copy export", 104, 22, function() card:Hide() UI.OpenExport() end, S.TAB_ON)
		f.copy:SetPoint("BOTTOMLEFT", 12, 10)
		f.later = S.Button(f, "Later", 90, 22, later, S.ACTION)
		f.later:SetPoint("LEFT", f.copy, "RIGHT", 8, 0)
		f.stop = S.Button(f, "Stop asking", 104, 22, stop, S.ACTION)
		f.stop:SetPoint("LEFT", f.later, "RIGHT", 8, 0)
		f.stop.tip = "Keep recording without asking; /psg export still works and Settings can turn asking back on."
		card = f
	end
	card.text:SetText(UI.CardText())
	card:Show()
end

-- The export window ----------------------------------------------------------------------------------
local parts, part = nil, 1
local function showPart()
	local f = win
	f.box:SetText(parts[part] or "")
	f.box.want = parts[part] or ""
	f.box:SetFocus()
	f.box:HighlightText()
	f.part:SetText(#parts > 1 and format("Part %d/%d", part, #parts) or "")
	f.next:SetShown(#parts > 1)
	f.next.label:SetText(part < #parts and "Next" or "First")
end
local function confirmMode(on)
	local f = win
	f.codeLabel:SetShown(on)
	f.code:SetShown(on)
	f.confirm:SetShown(on)
	f.uploaded:SetShown(not on)
	f.msg:SetText("")
	if on then f.code:SetText("") f.code:SetFocus() end
end
local function doConfirm()
	local okc, msg = ns.RecordExport.Confirm(win.code:GetText() or "")
	win.msg:SetText(msg)
	if okc then
		ns.Print(msg)
		win:Hide()
		if card then card:Hide() end
	end
end
local function build()
	local S, C = ns.Style, ns.Style.C
	local f = dialog(520, 196)
	local title = S.Text(f, 14, C.gold)
	title:SetPoint("TOPLEFT", 16, -14)
	title:SetText("Export for PoleSim")
	f.part = S.Text(f, 12, C.label)
	f.part:SetPoint("TOPRIGHT", -40, -16)
	f.close = S.Button(f, "X", 18, 18, function() f:Hide() end, S.CLOSE)
	f.close:SetPoint("TOPRIGHT", -8, -8)
	f.help = S.Text(f, 12, C.text)
	f.help:SetPoint("TOPLEFT", 16, -40)
	f.help:SetText("Ctrl+C, then paste at " .. UI.URL)
	local box = CreateFrame("EditBox", nil, f)
	box:SetSize(488, 24)
	box:SetPoint("TOPLEFT", 16, -62)
	box:SetAutoFocus(false)
	box:SetFontObject(ChatFontNormal or "ChatFontNormal")
	box:SetMaxLetters(0)
	box.bg = S.Fill(box, C.card, 1)
	box.border = S.Border(box, C.cardBorder)
	box:SetScript("OnEscapePressed", function() f:Hide() end)
	-- the text is for copying: an edit puts it back
	box:SetScript("OnTextChanged", function(self, user)
		if user and self.want and self:GetText() ~= self.want then
			self:SetText(self.want)
			self:HighlightText()
		end
	end)
	box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	box:SetScript("OnMouseUp", function(self) self:HighlightText() end)
	f.box = box
	f.next = S.Button(f, "Next", 70, 22, function()
		part = part < #parts and part + 1 or 1
		showPart()
	end, S.ACTION)
	f.next:SetPoint("TOPRIGHT", -16, -94)
	f.uploaded = S.Button(f, "I uploaded it", 120, 22, function() confirmMode(true) end, S.TAB_ON)
	f.uploaded:SetPoint("TOPLEFT", 16, -96)
	f.uploaded.tip = "Enter the confirmation code the website shows: the exported records are then removed here."
	f.codeLabel = S.Text(f, 12, C.text)
	f.codeLabel:SetPoint("TOPLEFT", 16, -100)
	f.codeLabel:SetText("Code from the website:")
	local code = CreateFrame("EditBox", nil, f)
	code:SetSize(90, 22)
	code:SetPoint("TOPLEFT", 170, -96)
	code:SetAutoFocus(false)
	code:SetFontObject(ChatFontNormal or "ChatFontNormal")
	code:SetMaxLetters(8)
	code.bg = S.Fill(code, C.card, 1)
	code.border = S.Border(code, C.cardBorder)
	code:SetScript("OnEnterPressed", doConfirm)
	code:SetScript("OnEscapePressed", function() f:Hide() end)
	f.code = code
	f.confirm = S.Button(f, "Confirm", 80, 22, doConfirm, S.TAB_ON)
	f.confirm:SetPoint("LEFT", code, "RIGHT", 8, 0)
	f.msg = S.Text(f, 11, C.label)
	f.msg:SetPoint("TOPLEFT", 16, -128)
	f.msg:SetWidth(488)
	f.msg:SetWordWrap(true)
	f.note = S.Text(f, 11, C.label)
	f.note:SetPoint("BOTTOMLEFT", 16, 12)
	f.note:SetWidth(488)
	f.note:SetWordWrap(true)
	f.note:SetText("Nothing is deleted until you enter the code. Recording goes on meanwhile.")
	f:SetScript("OnHide", function()
		parts = nil
		box:ClearFocus()
		code:ClearFocus()
	end)
	f:Hide()
	win = f
	return f
end
function UI.OpenExport()
	local p = ns.RecordExport.Export()
	if not p then
		ns.Print("Nothing recorded yet." .. (ns.Record.On() and "" or " Recording is off (Settings)."))
		return
	end
	if not win then build() end
	parts, part = p, 1
	win:Show()
	confirmMode(false)
	showPart()
end
ns.Slash("export", UI.OpenExport)
ns.Slash("record", function()
	local r = ns.Record.Data()
	local status = ns.Record.Status()
	ns.Print(format("Recording %s; %s; %.1f h since the last upload.", ns.Record.On() and "on" or "off", status,
		r and r.since / 3600 or 0))
end)

-- When to ask ----------------------------------------------------------------------------------------
-- From Record.Tick (every few seconds): the opt-in question once, then the upload card when due.
function UI.Check()
	if not ns.db then return end
	local O = ns.Options
	if not O.Get("recAsked") then
		local at = ns.Record.LoginAt()
		if at and GetTime() - at >= UI.OPTIN_DELAY and not shown(optIn) and UI.Calm() then UI.ShowOptIn() end
		return
	end
	if not (ns.Record.On() and O.Get("recPrompt")) or shown(card) then return end
	local r = ns.Record.Data()
	if r and r.since >= r.askAt and UI.Calm() then UI.ShowCard() end
end

ns.RegisterEvent("PLAYER_REGEN_DISABLED", function() if card and card:IsShown() then card:Hide() end end)
ns.On("OPTIONS", function(k, v)
	if (k == "recPrompt" or k == "record") and v == false and card then card:Hide() end
	if k == "recPrompt" and v == true then
		local r = ns.Record.Data()
		if r and r.askAt > r.since + UI.LATER_SECONDS then r.askAt = r.since end
	end
end)
