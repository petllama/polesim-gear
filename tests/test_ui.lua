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
	-- U.rows reuses a list's frames as a ScrollBox does: no new frame for the same or a shorter list,
	-- frames past the data are released (resetter, hidden) and acquired again later
	rows_reuse_frames = function()
		require("wow").install()
		local U = require("ui")
		U.install()
		local f = CreateFrame("Frame", nil, UIParent)
		local view = CreateScrollBoxListLinearView()
		local inits, resets = 0, 0
		view:SetElementInitializer("Button", function(row, d) inits = inits + 1 row.d = d end)
		view:SetElementResetter(function() resets = resets + 1 end)
		local box = CreateFrame("Frame", nil, f)
		ScrollUtil.InitScrollBoxListWithScrollBar(box, nil, view)
		box:SetDataProvider({ 1, 2, 3 })
		local a = U.rows(box)
		T.eq(#a, 3); T.eq(#box.children, 3)
		local b = U.rows(box)
		T.eq(b[1], a[1], "the same frames"); T.eq(#box.children, 3, "no new frame"); T.eq(inits, 6)
		box:SetDataProvider({ 9 })
		T.eq(resets, 2); T.eq(a[2].shown, false, "released frames hidden")
		local c = U.rows(box)
		T.eq(#c, 1); T.eq(c[1].d, 9)
		box:SetDataProvider({ 1, 2, 3, 4 })
		local d = U.rows(box)
		T.eq(#d, 4); T.eq(#box.children, 4, "released frames acquired again, one new")
		T.eq(d[2].shown, true)
		local e = U.rows(box, 2)
		T.eq(#e, 2, "only the first 2"); T.eq(d[3].shown, false, "the rest released")
	end,
	-- U.scroll runs the initializer on every element through a window of n frames (as scrolling a
	-- ScrollBox does): a long list makes only n frames
	scroll_reuses_a_window = function()
		require("wow").install()
		local U = require("ui")
		U.install()
		local view = CreateScrollBoxListLinearView()
		local seen = {}
		view:SetElementInitializer("Button", function(row, d) seen[#seen + 1] = d row.d = d end)
		view:SetElementResetter(function(row) row.d = nil end)
		local box = CreateFrame("Frame", nil, UIParent)
		ScrollUtil.InitScrollBoxListWithScrollBar(box, nil, view)
		local data = {}
		for i = 1, 25 do data[i] = i end
		box:SetDataProvider(data)
		T.eq(U.scroll(box, 10), 25)
		T.eq(#seen, 25); T.eq(seen[25], 25)
		T.eq(#box.children, 10, "one window of frames")
		box:SetDataProvider({})
		for _, f in ipairs(box.children) do T.eq(f.d, nil, "released") end
	end,
}
