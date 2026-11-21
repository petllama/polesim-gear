local T = require("t")
return {
	stub_basics = function()
		require("wow").install()
		local U = require("ui")
		U.install()
		local f = CreateFrame("Frame", "PSGTestFrame", UIParent)
		T.eq(_G.PSGTestFrame, f)
		local shown = 0
		f:SetScript("OnShow", function() shown = shown + 1 end)
		f:Hide(); f:Show()
		T.eq(shown, 1)
		local b = CreateFrame("Button", nil, f)
		local t = b:CreateFontString(); t:SetText("Go")
		local clicked
		b:SetScript("OnClick", function() clicked = true end)
		T.eq(U.button(f, "Go"), b); U.button(f, "Go"):Click(); T.ok(clicked)
		f:Hide()
		T.eq(b:IsVisible(), false, "parent hidden"); T.eq(U.button(f, "Go"), nil, "only visible buttons")
		T.ok(U.texts(UIParent) == "", "hidden text not collected")
		local dd = CreateFrame("DropdownButton", nil, f, "WowStyle1DropdownTemplate")
		dd:SetupMenu(function(_, root) root:CreateRadio("Now", function() return true end, function() end, 0) end)
		T.eq(U.menu(dd)[1].text, "Now")
		_G.PSGTestFrame = nil
	end,
}
