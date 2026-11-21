local T = require("t")
local F = require("winfix")
return {
	picker_and_count = function()
		local fx = F.load()
		local ns, U = fx.ns, fx.U
		fx.open()
		ns.Window.OpenSlot("chest")
		local p = ns.Window.Panel("slot")
		T.ok(p:IsShown())
		local items = U.menu(p.picker)
		T.eq(#items, #ns.Browser.SLOTS); T.ok(items[5].isSelected(), "Chest")
		items[1].select()
		T.eq(ns.Window.state.slot, "head")
		T.ok(p.count.text:match("^%d+ upgrades?"), p.count.text)
		T.ok(p.count.text:find("Quests", 1, true), p.count.text)
		fx.done()
	end,
}
