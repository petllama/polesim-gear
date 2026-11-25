-- /psg export gear: the character's gear string (GearString.lua) in one line, focused and highlighted
-- for Ctrl+C, to paste in the Armory at polesim.petllama.com ("Paste from PoleSim Gear"). Our own frame
-- in the recorder export's style (RecordUI.Dialog, Style), never StaticPopup or Blizzard's Menu (taint).
local ADDON, ns = ...
local GE = {}
ns.GearExport = GE

GE.URL = "polesim.petllama.com"
local win

function GE.Frame() return win end

local function build()
	local S, C = ns.Style, ns.Style.C
	local f = ns.RecordUI.Dialog(520, 150)
	local title = S.Text(f, 14, C.gold)
	title:SetPoint("TOPLEFT", 16, -14)
	title:SetText("Your gear for PoleSim")
	f.close = S.Button(f, "X", 18, 18, function() f:Hide() end, S.CLOSE)
	f.close:SetPoint("TOPRIGHT", -8, -8)
	f.help = S.Text(f, 12, C.text)
	f.help:SetPoint("TOPLEFT", 16, -40)
	f.help:SetText("Ctrl+C, then paste it in the Armory at " .. GE.URL)
	local box = CreateFrame("EditBox", nil, f)
	box:SetSize(488, 24)
	box:SetPoint("TOPLEFT", 16, -62)
	box:SetAutoFocus(false)
	box:SetFontObject(ChatFontNormal or "ChatFontNormal")
	box:SetMaxLetters(0)
	box.bg = S.Fill(box, C.card, 1)
	box.border = S.Border(box, C.cardBorder)
	box:SetScript("OnEscapePressed", function() f:Hide() end)
	box:SetScript("OnEnterPressed", function() f:Hide() end)
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
	f.note = S.Text(f, 11, C.label)
	f.note:SetPoint("TOPLEFT", 16, -96)
	f.note:SetWidth(488)
	f.note:SetWordWrap(true)
	f.note:SetText("Class, spec, level, race, faction and the item (and random suffix) of each worn slot. No names.")
	f:SetScript("OnHide", function() box:ClearFocus() end)
	f:Hide()
	win = f
	return f
end

function GE.Open()
	local text, why = ns.GearString.Text()
	if not text then
		ns.Print("Can't export the gear: " .. tostring(why) .. ".")
		return
	end
	if not win then build() end
	win.box.want = text
	win.box:SetText(text)
	win:Show()
	win.box:SetFocus()
	win.box:HighlightText()
end
