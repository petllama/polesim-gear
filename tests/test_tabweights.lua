local T = require("t")
local F = require("winfix")
return {
	bands = function()
		local fx = F.load()
		local ns, U = fx.ns, fx.U
		fx.open()
		ns.Window.SetTab("weights")
		local p = ns.Window.Panel("weights")
		local bands = ns.View.Bands("priest", "shadow")
		local i = ns.View.BandIndex(bands, 20)
		T.ok(U.texts(p):find(string.format("Levels %d%%-%d %%(your band%%)", bands[i].lo, bands[i].upTo)), U.texts(p))
		T.ok(U.texts(p):find("An item's score = its stats x these weights", 1, true))
		local rows = U.rows(p.list)
		T.eq(#rows, #ns.View.WeightRows(bands[i].w))
		T.ok(rows[1].value.text:match("^%d"), rows[1].value.text)
		T.eq(rows[1].bar.w, p.list.w + 10 - 290, "the largest weight fills the bar (as wide as the list allows)")
		T.ok(bands[i + 1], "the fixture's band has a next one")
		U.button(p, ">"):Click()
		T.ok(U.texts(p):find(string.format("Levels %d%%-%d", bands[i + 1].lo, bands[i + 1].upTo)))
		T.ok(not U.texts(p):find("your band", 1, true))
		U.button(p, "<"):Click()
		T.ok(U.texts(p):find("your band", 1, true))
		-- either end: that stepper looks disabled (faded), the other does not
		for _ = 1, #bands do ns.TabWeights.Step(-1) end
		T.eq(p.prev.enabled, false); T.eq(p.prev.alpha, 0.4); T.eq(p.next.alpha, 1)
		for _ = 1, #bands do ns.TabWeights.Step(1) end
		T.eq(p.next.enabled, false); T.eq(p.next.alpha, 0.4); T.eq(p.prev.enabled, true); T.eq(p.prev.alpha, 1)
		ns.TabWeights.view.band = nil; ns.Window.Refresh()
		SlashCmdList.POLESIMGEAR(""); fx.open()
		T.ok(U.texts(ns.Window.Panel("weights")):find("your band", 1, true), "back on your band after closing")
		fx.done()
	end,
	spec_switch = function()
		local fx = F.load()
		local ns, U = fx.ns, fx.U
		fx.open()
		ns.Window.SetTab("weights")
		local p = ns.Window.Panel("weights")
		local fired
		ns.On("STATE", function(e) fired = e end)
		T.eq(U.button(p, "Automatic (talents)").on, true)
		T.ok(U.texts(p):find("Now: Shadow, from your talents", 1, true), U.texts(p))
		U.button(p, "Holy"):Click()
		T.eq(ns.char.spec, "holy"); T.eq(fired, "SPEC")
		T.eq(U.button(p, "Holy").on, true); T.eq(U.button(p, "Automatic (talents)").on, false)
		fx.done()
	end,
	-- Only specs with weights get a radio: a druid sees Balance and Restoration, never Feral.
	spec_switch_supported_only = function()
		local fx = F.load({ cls = "druid" })
		local ns, U = fx.ns, fx.U
		fx.open()
		local p = fx.tab("weights")
		T.ok(U.button(p, "Balance")); T.ok(U.button(p, "Restoration"))
		T.eq(U.find(p, function(w) return w.text == "Feral" end), nil, "no Feral radio")
		T.eq(#p.radios, 3)
		fx.done()
	end,
}
