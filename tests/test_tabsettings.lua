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
		local pq = U.button(p, "Prefer upgrades from upcoming guide quests (within 2 levels)")
		T.eq(pq.on, true); pq:Click(); T.eq(ns.Options.Get("preferQuest"), false)
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
	-- The spec choice (as /psg spec and the Weights tab): Automatic plus only the specs with weights
	-- (a druid: Balance, Restoration; no Feral).
	spec_dropdown = function()
		local fx = F.load({ cls = "druid" })
		local ns, U = fx.ns, fx.U
		fx.open()
		local p = fx.tab("settings")
		T.ok(U.texts(p):find("Spec", 1, true))
		local items = U.menu(p.spec)
		local texts = {}
		for i, it in ipairs(items) do texts[i] = it.text end
		T.eq(table.concat(texts, ","), "Automatic (talents),Balance,Feral,Restoration")
		T.eq(items[1].isSelected(), true)
		local fired
		ns.On("STATE", function(event) fired = event end)
		items[4].select()
		T.eq(ns.char.spec, "restoration"); T.eq(fired, "SPEC")
		fx.done()
		local fp = F.load({ cls = "paladin" })
		fp.open()
		local pp = fp.tab("settings")
		local list = {}
		for i, it in ipairs(fp.U.menu(pp.spec)) do list[i] = it.text end
		T.eq(table.concat(list, ","), "Automatic (talents),Holy,Retribution")  -- no Protection (tank weights pending)
		fp.done()
	end,
	-- Auto-detect on a spec with no weights (Protection): the window says so where the lists would be and
	-- in the header, Settings still offers the supported specs; picking one scores with its weights.
	unsupported_spec_window = function()
		local fx = F.load({ cls = "paladin", unsupportedSpec = "protection" })
		local ns, U = fx.ns, fx.U
		local f = fx.open()
		T.ok(f and f:IsShown(), "the window opens")
		local msg = "Paladin Protection isn't supported yet. Pick a supported spec in Settings to use its weights."
		T.eq(fx.tab("plan").list.provided[1].empty, msg)
		T.eq(f.header.spec.text, "Protection (not supported)"); T.eq(f.header.who.text, "Level 20 Paladin")
		local p = fx.tab("settings")
		local items = U.menu(p.spec)
		T.eq(#items, 3)
		items[2].select()
		T.eq(ns.char.spec, "holy")
		fx.settle()
		T.eq(ns.Context.Get().spec, "holy")
		T.ok(fx.tab("plan").list.provided[1].empty ~= msg, "scored now")
		fx.done()
	end,
}
