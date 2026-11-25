-- The upload prompt, the export string and the confirmation code (RecordExport.lua, RecordUI.lua).
local T = require("t")
local RF = require("recfix")

local session = RF.session

local function card(R) return R.ns.RecordUI.UploadShown() end

return {
	asks_to_upload_after_two_hours_of_active_play = function()
		local R = RF.setup({ record = true })
		R.login()
		R.play(3600 + 3000)
		T.ok(not card(R), "not before 2 h")
		R.play(700)
		T.ok(card(R), "after 2 h")
		T.ok(R.U.texts(R.ns.RecordUI.UploadFrame()):find("2 h of leveling recorded. Upload it?", 1, true), "card text")
		R.done()
	end,

	-- a character saved by 0.6-0.7.5 still waits for the old 4 h default: it moves to 2 h
	old_four_hour_wait_moves_to_two = function()
		local R = RF.setup({ record = true })
		R.ns.char.rec = { v = 1, blocks = {}, next = 1, since = 0, askAt = 4 * 3600, sessions = 0 }
		R.login()
		R.play(2 * 3600 + 20)
		T.ok(card(R), "asks at 2 h")
		R.done()
	end,

	afk_time_does_not_count_toward_the_two_hours = function()
		local R = RF.setup({ record = true })
		R.login()
		R.play(3600)
		R.afk = true
		R.event("PLAYER_FLAGS_CHANGED", "player")
		R.wait(2 * 3600)
		R.tick()
		R.afk = false
		R.event("PLAYER_FLAGS_CHANGED", "player")
		R.play(60)
		T.ok(not card(R), "1 h of play + 2 h AFK is not 2 h")
		R.done()
	end,

	waits_for_a_calm_moment = function()
		local R = RF.setup({ record = true })
		R.login()
		R.play(2 * 3600 - 30)
		for _, case in ipairs({ "combat", "instance", "casting", "MailFrame", "AuctionHouseFrame", "MerchantFrame", "ClassTrainerFrame" }) do
			if R[case] ~= nil then R[case] = true else R.frames[case] = true end
			R.play(60)
			T.ok(not card(R), "no card while " .. case)
			if R[case] ~= nil then R[case] = false else R.frames[case] = false end
		end
		-- another PoleSim prompt open: the equip card
		local f = R.ns.Prompt.Frame and R.ns.Prompt.Frame()
		T.eq(f, nil, "(no equip card made yet)")
		R.play(10)
		T.ok(card(R), "calm now")
		R.done()
	end,

	not_while_the_equip_prompt_shows = function()
		local R = RF.setup({ record = true })
		R.login()
		R.play(2 * 3600 - 30)
		R.ns.RecordUI.OtherPopup = function() return true end
		R.play(60)
		T.ok(not card(R), "the equip card is up")
		R.ns.RecordUI.OtherPopup = nil
		R.play(10)
		T.ok(card(R))
		R.done()
	end,

	later_asks_again_after_an_hour_of_play = function()
		local R = RF.setup({ record = true })
		R.login()
		R.play(2 * 3600 + 20)
		T.ok(card(R))
		R.U.button(R.ns.RecordUI.UploadFrame(), "Later"):Click()
		T.ok(not card(R))
		R.play(3000)
		T.ok(not card(R), "not within the hour")
		R.play(700)
		T.ok(card(R), "an hour later")
		R.done()
	end,

	stop_asking_keeps_recording_and_settings_turn_it_back_on = function()
		local R = RF.setup({ record = true })
		R.login()
		R.play(2 * 3600 + 20)
		R.U.button(R.ns.RecordUI.UploadFrame(), "Stop asking"):Click()
		T.eq(R.ns.Options.Get("recPrompt"), false)
		T.eq(R.ns.Options.Get("record"), true, "still recording")
		R.play(3 * 3600)
		T.ok(not card(R), "never asks")
		local n = #R.all("p")
		R.fight(10, { { 448, 12, "Beast", false, 50 } })
		T.eq(#R.all("p"), n + 1, "still recording")
		R.ns.Options.Set("recPrompt", true)
		R.play(20)
		T.ok(card(R), "asks again once the setting is back on")
		R.done()
	end,

	copy_export_opens_one_highlighted_line = function()
		local R = RF.setup({ record = true })
		R.login()
		session(R, 600)
		R.play(2 * 3600)
		R.U.button(R.ns.RecordUI.UploadFrame(), "Copy export"):Click()
		local w = R.ns.RecordUI.ExportFrame()
		T.ok(w and w:IsShown(), "export window")
		local box = w.box
		T.ok(box.text:match("^PSG1:"), "the export string")
		T.ok(not box.text:find("\n"), "one line")
		T.ok(box.focused, "focused")
		T.ok(box.highlighted, "highlighted")
		T.ok(R.U.texts(w):find("Ctrl+C, then paste at polesim.petllama.com/upload", 1, true), "instructions")
		T.ok(R.U.button(w, "I uploaded it"), "confirm button")
		R.done()
	end,

	slash_export_and_the_string_round_trips = function()
		local R = RF.setup({ record = true })
		R.login()
		session(R, 900)
		SlashCmdList.POLESIMGEAR("export")
		R.fx.settle()
		local E = R.ns.RecordExport
		local text = R.ns.RecordUI.ExportFrame().box.text
		local doc, err = E.Decode(text)
		T.ok(doc, err)
		T.eq(doc.v, 1, "format version")
		T.eq(doc.cls, "PRIEST")
		T.eq(#doc.pulls.rows, #R.all("p"), "every pull")
		T.ok(doc.h > 0.2, "hours of active play")
		T.ok(type(doc.chars[1]) == "table", "the sheet")
		local s = E.Json(doc)
		T.ok(not s:find("Pelleas") and not s:find("Kobold"), "no names")
		R.done()
	end,

	a_truncated_paste_is_rejected = function()
		local R = RF.setup({ record = true })
		R.login()
		session(R, 600)
		local E = R.ns.RecordExport
		local parts = E.Build()
		local text = parts[1]
		T.ok(E.Decode(text), "whole")
		local doc, err = E.Decode(text:sub(1, #text - 7))
		T.eq(doc, nil, "truncated")
		T.ok(err:find("incomplete") or err:find("checksum"), err)
		R.done()
	end,

	big_exports_split_into_numbered_parts = function()
		local R = RF.setup({ record = true })
		R.login()
		session(R, 900)
		local E = R.ns.RecordExport
		E.PART_CHARS = 1000
		local parts = E.Build()
		T.ok(#parts > 1, "several parts")
		T.ok(parts[1]:match("^PSG1:[^:]+:%x+:%d+:1/" .. #parts .. ":"), parts[1]:sub(1, 40))
		local doc = E.Decode(table.concat(parts, "\n"))
		T.ok(doc, "the parts together decode")
		R.ns.RecordUI.OpenExport()
		local w = R.ns.RecordUI.ExportFrame()
		T.ok(R.U.texts(w):find("Part 1/" .. #parts, 1, true), "part label")
		R.U.button(w, "Next"):Click()
		T.ok(R.U.texts(w):find("Part 2/" .. #parts, 1, true), "next part")
		T.eq(w.box.text, parts[2])
		T.ok(w.box.focused and w.box.highlighted)
		R.done()
	end,

	the_confirmation_code_clears_what_was_exported = function()
		local R = RF.setup({ record = true })
		R.login()
		session(R, 2 * 3600 + 100)
		R.play(30)
		local E, UI = R.ns.RecordExport, R.ns.RecordUI
		UI.OpenExport()
		local code = E.CodeFor(E.Last().crc)
		T.eq(#code, 6)
		local n = #R.all("p")
		T.ok(n > 0)
		-- recording goes on after the export
		R.fight(10, { { 448, 12, "Beast", false, 50 } })
		local w = UI.ExportFrame()
		R.U.button(w, "I uploaded it"):Click()
		local ok, msg = E.Confirm("ZZZZZZ")
		T.eq(ok, false, "a wrong code")
		T.eq(#R.all("p"), n + 1, "nothing deleted on a wrong code")
		w.code:SetText(code:lower())
		R.U.button(w, "Confirm"):Click()
		T.eq(#R.all("p"), 1, "the exported records are gone, the newer pull stays")
		T.eq(R.rec().since, 0, "the 4 h clock starts again")
		T.ok(not card(R))
		T.ok(msg, "a message for the wrong code")
		R.done()
	end,

	four_hours_export_size = function()
		local R = RF.setup({ record = true })
		R.login()
		session(R, 4 * 3600)
		local E = R.ns.RecordExport
		local parts = E.Build()
		local json = E.Json(E.Summary())
		local bytes = 0
		for _, p in ipairs(parts) do bytes = bytes + #p end
		print(("    4 h synthetic: %d pulls, JSON %d B, export %d B in %d part(s)"):format(#R.all("p"), #json, bytes, #parts))
		T.ok(bytes < 40000, "a few KB per 4 h: " .. bytes)
		R.done()
	end,
}
