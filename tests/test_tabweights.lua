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
	-- Only specs with weights get a radio: a paladin sees Holy, Protection (0.7.1) and Retribution; a spec
	-- whose bands lack the weapon model (Protection before 0.7.1) gets none.
	spec_switch_supported_only = function()
		local fx = F.load({ cls = "paladin" })
		local ns, U = fx.ns, fx.U
		fx.open()
		local p = fx.tab("weights")
		T.ok(U.button(p, "Holy")); T.ok(U.button(p, "Retribution")); T.ok(U.button(p, "Protection"))
		T.eq(#p.radios, 4)
		fx.done()
		fx = F.load({ cls = "paladin" })
		fx.ns.DATA.specs.paladin.protection.weaponModel = nil
		fx.open()
		p = fx.tab("weights")
		T.eq(fx.U.find(p, function(w) return w.text == "Protection" end), nil, "no Protection radio")
		T.eq(#p.radios, 3)
		fx.done()
	end,
	-- Tanks: the less-certain note; Prot Paladin also its block/speed note; both wrap under the spec
	-- column without running past the panel at the window sizes the layout test uses. Others: no note.
	tank_notes = function()
		for _, case in ipairs({ { "paladin", true }, { "warrior", false } }) do
			local fx = F.load({ cls = case[1], spec = "protection", level = 45 })
			local f = fx.open()
			local p = fx.tab("weights")
			T.ok(p.note.text:find("Tank weights are less certain", 1, true), p.note.text)
			T.eq(p.note.text:find("level-60 weapon speed set to neutral", 1, true) ~= nil, case[2], p.note.text)
			if case[2] then T.ok(p.note.text:find("Block is a damage stat from 42 (Holy Shield, Reckoning)", 1, true)) end
			for _, size in ipairs({ { 980, 600 }, { 780, 500 }, { 1300, 760 } }) do
				f:SetSize(size[1], size[2])
				if f.scripts.OnSizeChanged then f.scripts.OnSizeChanged(f, size[1], size[2]) end
				p = fx.tab("weights")
				local cut = fx.U.overflows(p)
				T.eq(#cut, 0, case[1] .. " " .. size[1] .. ": " .. table.concat(cut, ", "))
			end
			fx.done()
		end
		local fx = F.load()
		fx.open()
		T.eq(fx.tab("weights").note.text, "", "a priest has no note")
		fx.done()
	end,
}
