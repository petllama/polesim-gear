local T = require("t")
local function load()
	local ns = T.addon({ "Core.lua", "Data/Weights.lua", "Data/Suffixes.lua", "Data/Items.lua", "Items.lua", "Score.lua",
		"Equip.lua", "Sources.lua", "Browser.lua", "Style.lua" })
	require("ui").install()
	return ns, require("ui")
end
return {
	numbers = function()
		local S = load().Style
		T.eq(S.Signed(31.06), "+31.1"); T.eq(S.Signed(-2), "-2.0")
		T.eq(S.Signed(1200), "+1200", "1000 and over: no decimal, so it fits the 48 px Gain column"); T.eq(S.Signed(999.94), "+999.9")
		T.eq(S.Pct(3, 12), "+25.0%"); T.eq(S.Pct(3, 0), "")
		T.eq(S.Pct(28.1, 2.388), "+1177%", "100% and over: no decimal, so it fits the 54 px column")
		T.eq(S.Pct(-1, 2), "-50.0%"); T.eq(S.Pct(99.94, 100), "+99.9%")
		T.eq(S.Thousands(1654.84), "1,654.8"); T.eq(S.Thousands(12.0), "12.0"); T.eq(S.Thousands(1234567.04), "1,234,567.0")
		T.eq(S.Money(12345), "12345c", "the client's GetMoneyString")
		_G.GetMoneyString = nil
		T.eq(S.Money(12345), "1g 23s 45c")
	end,
	colours_from_hex = function()
		local S = load().Style
		T.near(S.C.green[1], 0x5f / 255); T.near(S.C.tabOn[3], 0x5e / 255)
		T.eq(S.W, 980); T.eq(S.H, 600); T.eq(S.MIN_W, 780); T.eq(S.MIN_H, 500); T.eq(S.ROW_H, 30)
		T.eq(S.KIND_LABEL.world, "BoE / World")
		for _, k in ipairs({ "quest", "dungeon", "crafted", "vendor", "world" }) do T.ok(S.KIND_ICON[k], k) end
	end,
	widgets = function()
		local ns, U = load()
		local S = ns.Style
		local parent = CreateFrame("Frame", nil, UIParent)
		local on
		local c = S.Check(parent, "Quests", function(v) on = v end)
		c:Set(true); T.eq(c.tick.shown, true); c:Click(); T.eq(on, false, "click asks for the other state")
		local b = S.Badge(parent)
		b:Set(2); T.eq(b.text.text, "2"); T.near(b.bg.color[1], S.C.badgeGold[1])
		b:Set(4); T.near(b.bg.color[1], S.C.badgeGrey[1]); b:Set(nil); T.eq(b.shown, false)
		local st = S.Star(parent, function() end)
		st:Set(true); T.eq(st.tex.atlas, "auctionhouse-icon-favorite"); st:Set(false); T.eq(st.tex.atlas, "auctionhouse-icon-favorite-off")
		local cell = S.ItemCell(parent, 22, 100)
		cell:Set({ name = "Robe", quality = 3, icon = "inv_chest_cloth_01" }, "Your pick")
		T.eq(cell.name.text, "|cff0070ddRobe|r"); T.ok(cell.icon.texture:find("inv_chest_cloth_01", 1, true)); T.eq(cell.sub.text, "Your pick")
		cell:Set({ name = "Worn", quality = 2, icon = 132656 }); T.eq(cell.icon.texture, 132656, "a client fileID as is")
		cell:Set(nil); T.eq(cell.name.text, ""); T.eq(cell.icon.shown, false); T.eq(cell.iconFrame.shown, false, "no quality border")
		-- dimmed (a pick not available): name, icon and border faded, icon grey; the next Set undims
		cell:Set({ name = "Robe", quality = 3 }, "x"); T.eq(cell.iconFrame.shown, true)
		cell:SetDim(true)
		T.eq(cell.name.alpha, 0.5); T.eq(cell.icon.alpha, 0.5); T.eq(cell.iconFrame.alpha, 0.5); T.eq(cell.icon.desaturated, true)
		cell:Set({ name = "Robe", quality = 3 }, "x")
		T.eq(cell.name.alpha, 1); T.eq(cell.icon.alpha, 1); T.eq(cell.iconFrame.alpha, 1); T.eq(cell.icon.desaturated, false)
		-- a disabled button looks disabled (faded, grey label, no hover) and comes back as it was
		local btn = S.Button(parent, ">", 24, 22, function() end, S.ACTION)
		S.SetEnabled(btn, false)
		T.eq(btn.enabled, false); T.eq(btn.alpha, 0.4); T.near(btn.label.textColor[1], S.C.label[1])
		btn.scripts.OnEnter(btn); T.near(btn.bg.color[1], S.ACTION[1][1], 1e-6, "no hover colour")
		S.SetEnabled(btn, true)
		T.eq(btn.enabled, true); T.eq(btn.alpha, 1); T.near(btn.label.textColor[1], S.ACTION[3][1])
		btn.scripts.OnEnter(btn); T.near(btn.bg.color[1], S.ACTION[4][1], 1e-6, "hover again")
		local picked
		local dd = S.Dropdown(parent, 146, 24, function() return { { text = "Now", value = 0 }, { text = "+1", value = 1 } } end,
			function(v) return v == 0 end, function(v) picked = v end)
		local items = U.menu(dd)
		T.eq(#items, 2); T.ok(items[1].isSelected()); items[2].select(); T.eq(picked, 1)
	end,
	-- Style.Dropdown: our own flat button + popup (Blizzard's Menu system taints the unit popup: Target
	-- Marker Icon was blocked). Opens below the button with a radio mark on the selected choice; a click
	-- selects and closes; a second click on the button, a click outside, Escape or the owner hiding close.
	dropdown_popup = function()
		local ns, U = load()
		local S = ns.Style
		local parent = CreateFrame("Frame", nil, UIParent)
		local sel, picked = 0, {}
		local dd = S.Dropdown(parent, 146, 24, function() return { { text = "Now", value = 0 }, { text = "+1", value = 1 }, { text = "+2", value = 2 } } end,
			function(v) return v == sel end, function(v) sel = v picked[#picked + 1] = v end)
		T.eq(dd.label.text, "Now", "the button shows the selected choice")
		T.eq(U.popup(), nil)
		dd:Click()
		local p = U.popupFrame()
		T.ok(p, "a click opens the popup")
		T.eq(p.parent, UIParent); T.eq(p.name, nil, "unnamed: no new global")
		T.eq(p.strata, "DIALOG"); T.eq(p.clamped, true, "clamped to the screen")
		local pt = p.points[1]
		T.eq(pt[1], "TOPLEFT"); T.eq(pt[2], dd); T.eq(pt[3], "BOTTOMLEFT")
		T.ok((p.w or 0) >= 146, "at least the button's width")
		T.ok(p.catcher:IsShown(), "the click catcher covers the screen"); T.eq(p.catcher.strata, "DIALOG")
		T.eq(p.catcher.points[1][1], "TOPLEFT"); T.ok(p.catcher.mouse, "the catcher takes clicks")
		local rows = U.popup()
		T.eq(#rows, 3); T.eq(rows[1].text, "Now"); T.eq(rows[1].checked, true); T.eq(rows[2].checked, false)
		T.eq(rows[1].row.mark.shown, true); T.ok(rows[1].row.mark.alpha > rows[2].row.mark.alpha, "the selected mark stands out")
		-- hover colours the row
		rows[2].row.scripts.OnEnter(rows[2].row); T.eq(rows[2].row.hl.shown, true)
		rows[2].row.scripts.OnLeave(rows[2].row); T.eq(rows[2].row.hl.shown, false)
		rows[3].click()
		T.eq(sel, 2); T.eq(U.popup(), nil, "a choice closes the popup"); T.eq(p.catcher:IsShown(), false)
		T.eq(dd.label.text, "+2", "the button shows the new choice")
		-- the button again: open, then a second click closes (no select)
		dd:Click(); T.ok(U.popup()); T.eq(U.popup()[3].checked, true)
		dd:Click(); T.eq(U.popup(), nil, "the button toggles")
		-- a click outside (the catcher) closes, nothing selected
		dd:Click(); p.catcher.scripts.OnMouseDown(p.catcher, "LeftButton")
		T.eq(U.popup(), nil); T.eq(#picked, 1)
		-- Escape closes the popup and is not passed on (the window stays); other keys pass on
		dd:Click()
		T.eq(p.keys:IsVisible(), true, "the key catcher listens while open (out of combat)")
		T.eq(p.keys.keyboard, true)
		p.keys.scripts.OnKeyDown(p.keys, "W"); T.eq(p.keys.propagate, true, "movement keys pass on"); T.ok(U.popup())
		p.keys.scripts.OnKeyDown(p.keys, "ESCAPE"); T.eq(p.keys.propagate, false, "Escape is ours"); T.eq(U.popup(), nil)
		-- the owner hiding (window closed, tab switched) closes the popup on the next frame
		dd:Click(); parent:Hide(); p.scripts.OnUpdate(p, 0.01); T.eq(U.popup(), nil)
		parent:Show()
		-- combat: no keyboard (SetPropagateKeyboardInput is restricted), and combat starting closes it
		_G.InCombatLockdown = function() return true end
		dd:Click(); T.ok(U.popup()); T.eq(p.keys:IsShown(), false, "no key catcher in combat")
		_G.InCombatLockdown = function() return false end
		dd:Click(); T.eq(U.popup(), nil)
		dd:Click(); T.ok(U.popup())
		ns._frame.scripts.OnEvent(ns._frame, "PLAYER_REGEN_DISABLED"); T.eq(U.popup(), nil, "combat closes it")
		-- a list that shrinks reuses rows and hides the rest; an empty list opens nothing
		local n = 3
		local dd2 = S.Dropdown(parent, 100, 24, function()
			local l = {}
			for i = 1, n do l[i] = { text = "c" .. i, value = i } end
			return l
		end, function() return false end, function() end)
		dd2:Click(); T.eq(#U.popup(), 3); U.popupFrame():Hide()
		n = 1; dd2:Click(); T.eq(#U.popup(), 1); U.popupFrame():Hide()
		n = 0; dd2:Click(); T.eq(U.popup(), nil)
	end,
	-- Style.ContextMenu (the Gear Plan's right-click): a title, buttons, at the cursor; a choice runs its
	-- onClick after the popup closes (so it may open another one).
	context_menu = function()
		local ns, U = load()
		local S = ns.Style
		local owner = CreateFrame("Button", nil, UIParent)
		local ran = {}
		S.ContextMenu(owner, {
			{ text = "Chest", isTitle = true },
			{ text = "Choose another upgrade", onClick = function() ran[#ran + 1] = "choose" end },
			{ text = "Add to wishlist", onClick = function() ran[#ran + 1] = "wish" T.eq(U.popup(), nil, "closed first") end },
		})
		local rows = U.popup()
		T.eq(#rows, 3); T.eq(rows[1].title, true); T.eq(rows[1].row.mark.shown, false); T.eq(rows[2].row.mark.shown, false)
		local pt = U.popupFrame().points[1]
		T.eq(pt[1], "TOPLEFT"); T.eq(pt[2], UIParent); T.eq(pt[3], "BOTTOMLEFT"); T.eq(pt[4], 500); T.eq(pt[5], 400)
		rows[1].click(); T.ok(U.popup(), "the title does nothing")
		rows[3].click(); T.eq(table.concat(ran, ","), "wish"); T.eq(U.popup(), nil)
		-- a new menu replaces an open one (one popup)
		S.ContextMenu(owner, { { text = "A", onClick = function() end } })
		S.ContextMenu(owner, { { text = "B", onClick = function() end } })
		T.eq(#U.popup(), 1); T.eq(U.popup()[1].text, "B")
	end,
	-- No Blizzard Menu system anywhere in the addon (taint: SetRaidTarget blocked from the target frame)
	no_blizzard_menus = function()
		local p = io.popen("ls PoleSimGear/*.lua")
		for f in p:lines() do
			local h = assert(io.open(f, "rb")); local src = h:read("*a"); h:close()
			src = src:gsub("%-%-[^\n]*", "") -- comments may name them
			for _, bad in ipairs({ "MenuUtil", "DropdownButton", "DropdownTemplate", "SetupMenu", "GenerateMenu",
				"UIDropDownMenu", "EasyMenu", "UnitPopup", "%f[%w_]Menu%.", "CreateContextMenu", "MenuTemplate" }) do
				T.eq(src:find(bad), nil, f .. ": " .. bad)
			end
		end
		p:close()
	end,
}
