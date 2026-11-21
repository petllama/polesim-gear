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
		T.eq(S.Pct(3, 12), "+25.0%"); T.eq(S.Pct(3, 0), "")
		T.eq(S.Thousands(1654.84), "1,654.8"); T.eq(S.Thousands(12.0), "12.0"); T.eq(S.Thousands(1234567.04), "1,234,567.0")
		T.eq(S.Money(12345), "12345c", "the client's GetMoneyString")
		_G.GetMoneyString = nil
		T.eq(S.Money(12345), "1g 23s 45c")
	end,
	colours_from_hex = function()
		local S = load().Style
		T.near(S.C.green[1], 0x5f / 255); T.near(S.C.tabOn[3], 0x5e / 255)
		T.eq(S.W, 780); T.eq(S.H, 500); T.eq(S.ROW_H, 30)
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
		cell:Set(nil); T.eq(cell.name.text, ""); T.eq(cell.icon.shown, false); T.eq(cell.iconFrame.shown, false, "no quality border")
		-- dimmed (a pick not available): name, icon and border faded, icon grey; the next Set undims
		cell:Set({ name = "Robe", quality = 3 }, "x"); T.eq(cell.iconFrame.shown, true)
		cell:SetDim(true)
		T.eq(cell.name.alpha, 0.5); T.eq(cell.icon.alpha, 0.5); T.eq(cell.iconFrame.alpha, 0.5); T.eq(cell.icon.desaturated, true)
		cell:Set({ name = "Robe", quality = 3 }, "x")
		T.eq(cell.name.alpha, 1); T.eq(cell.icon.alpha, 1); T.eq(cell.iconFrame.alpha, 1); T.eq(cell.icon.desaturated, false)
		local picked
		local dd = S.Dropdown(parent, 146, 24, function() return { { text = "Now", value = 0 }, { text = "+1", value = 1 } } end,
			function(v) return v == 0 end, function(v) picked = v end)
		local items = U.menu(dd)
		T.eq(#items, 2); T.ok(items[1].isSelected()); items[2].select(); T.eq(picked, 1)
	end,
}
