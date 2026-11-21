local T = require("t")
local F = require("winfix")
return {
	switches = function()
		local fx = F.load()
		local ns, U = fx.ns, fx.U
		fx.open()
		ns.Window.SetTab("settings")
		local p = ns.Window.Panel("settings")
		local tip = U.button(p, "Score line in item tooltips")
		T.eq(tip.on, true)
		tip:Click()
		T.eq(ns.Options.Get("tooltip"), false); T.eq(U.button(p, "Score line in item tooltips").on, false)
		for _, l in ipairs({ "Minimap button", "Upgrade arrows on bags, merchants, mail and the auction house", "Mark the best quest reward" }) do
			T.eq(U.button(p, l).on, true, l)
		end
		U.button(p, "Minimap button"):Click()
		T.eq(PoleSimGearDB.minimap.hide, true); T.eq(U.button(p, "Minimap button").on, false)
		U.button(p, "Mark the best quest reward"):Click()
		T.eq(ns.Options.Get("rewardMark"), false)
		local items = U.menu(p.ahead)
		items[3].select()
		T.eq(ns.Options.Get("ahead"), 2)
		T.ok(U.texts(p):find("Polestar's gear scores are off", 1, true), U.texts(p))
		ns.Coexist.PolestarGearOn = function() return true end
		PoleSimGearDB.askedPolestarGear = "no"
		ns.Window.Refresh()
		T.ok(U.texts(p):find("You answered: No", 1, true), U.texts(p))
		U.button(p, "Ask again"):Click()
		T.eq(PoleSimGearDB.askedPolestarGear, nil)
		T.ok(U.texts(p):find("Not asked yet", 1, true), "redrawn")
		fx.done()
	end,
}
