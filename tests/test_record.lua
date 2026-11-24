-- The leveling recorder (Record.lua): opt-in, what it records from the client's events, what it never
-- records, the storage cap and the active-play clock.
local T = require("t")
local RF = require("recfix")

local function count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end

return {
	opt_in_is_asked_once_and_nothing_is_recorded_before_yes = function()
		local R = RF.setup()
		R.login()
		R.wait(10)
		R.tick()
		local ui = R.ns.RecordUI
		T.ok(ui.OptInShown(), "the opt-in dialog shows on the first load")
		T.ok(R.U.texts(ui.OptInFrame()):find("Help improve PoleSim's gear weights?", 1, true), "title")
		R.fight(20, { { 448, 12, "Beast", false, 50 } }, { 116 })
		T.eq(#R.all("p"), 0, "no pull recorded before the answer")
		R.U.button(ui.OptInFrame(), "Yes, record"):Click()
		T.ok(not ui.OptInShown(), "closed after the answer")
		T.eq(R.ns.Options.Get("record"), true, "recording on")
		T.eq(R.ns.Options.Get("recAsked"), true, "asked")
		R.fight(20, { { 448, 12, "Beast", false, 50 } }, { 116 })
		T.eq(#R.all("p"), 1, "recorded after yes")
		R.done()
		-- next login (same account): no question
		local R2 = RF.setup({ db = R.db })
		R2.login()
		R2.wait(10)
		R2.tick()
		T.ok(not R2.ns.RecordUI.OptInShown(), "asked only once")
		R2.done()
	end,

	no_thanks_keeps_recording_off_and_never_asks_again = function()
		local R = RF.setup()
		R.login()
		R.wait(10)
		R.tick()
		R.U.button(R.ns.RecordUI.OptInFrame(), "No thanks"):Click()
		T.eq(R.ns.Options.Get("record"), false)
		T.eq(R.ns.Options.Get("recAsked"), true)
		R.fight(20, { { 448, 12, "Beast", false, 50 } })
		T.eq(#R.all("p"), 0, "nothing recorded")
		R.done()
	end,

	opt_in_waits_for_a_calm_moment = function()
		local R = RF.setup()
		R.login()
		R.combat = true
		R.wait(10)
		R.tick()
		T.ok(not R.ns.RecordUI.OptInShown(), "not in combat")
		R.combat = false
		R.wait(5)
		R.tick()
		T.ok(R.ns.RecordUI.OptInShown(), "after combat")
		R.done()
	end,

	a_pull_records_mobs_kills_xp_and_casts = function()
		local R = RF.setup({ record = true })
		R.login()
		R.play(30)
		R.fight(24, { { 448, 13, "Beast", false, 60 }, { 257, 12, "Humanoid", true, 45 } }, { 116, 116, 168 })
		local p = R.all("p")
		T.eq(#p, 1, "one pull")
		p = p[1]
		T.near(p.e - p.s, 24, 1.5, "fight length")
		T.eq(p.n, 2, "two mobs engaged")
		T.eq(#p.m, 2, "each mob described")
		T.eq(p.m[1][1], 448, "npc id from the GUID")
		T.eq(p.m[1][2], 13, "mob level")
		T.eq(p.m[1][3], "Beast", "creature type")
		T.eq(p.m[1][4], 0, "not a caster")
		T.eq(p.m[2][4], 1, "a caster (mana)")
		T.eq(#p.k, 2, "two kills")
		T.eq(p.k[1][3], 60, "XP of the first kill from the XP line")
		T.eq(p.k[2][3], 45, "XP of the second")
		T.eq(p.c[116], 2, "casts per spell id")
		T.eq(p.c[168], 1)
		T.eq(p.l, 12, "player level")
		R.done()
	end,

	the_gap_between_pulls_is_end_to_next_start = function()
		local R = RF.setup({ record = true })
		R.login()
		R.fight(10, { { 448, 12, "Beast", false, 50 } })
		R.play(17) -- R.fight waits 3 s after the end
		R.fight(10, { { 448, 12, "Beast", false, 50 } })
		local p = R.all("p")
		T.eq(#p, 2)
		T.near(p[2].g, 20, 1.5, "gap")
		T.near(p[2].s - p[1].e, 20, 1.5)
		R.done()
	end,

	the_opener_cast_just_before_combat_counts_for_the_pull = function()
		local R = RF.setup({ record = true })
		R.login()
		R.play(20)
		R.cast(116)
		R.wait(1)
		R.fight(10, { { 448, 12, "Beast", false, 50 } }, { 116 })
		T.eq(R.all("p")[1].c[116], 2, "opener + the cast in the fight")
		R.done()
	end,

	a_character_snapshot_at_login_and_every_level_up = function()
		local R = RF.setup({ record = true })
		R.U.equipped[1] = "|cff1eff00|Hitem:1234:15:0:0:0:0:0:0:12:0:0:0:1:2045|h[Cap of the Owl]|h|r"
		R.login()
		R.play(20)
		local c = R.all("c")
		T.eq(#c, 1, "one snapshot after login")
		c = c[1]
		T.eq(c.l, 12)
		T.eq(c.cls, "PRIEST")
		T.eq(c.race, "Scourge")
		T.eq(c.st[1][1], 11, "base Strength")
		T.eq(c.st[5][2], 25, "effective Spirit")
		T.eq(c.hp, 500, "max health")
		T.eq(c.mp, 800, "max mana")
		T.eq(c.ar, 320, "armor (effective)")
		T.eq(c.ap, 45, "attack power base + buffs")
		T.eq(c.sp[6], 25, "shadow spell power")
		T.eq(c.heal, 12)
		T.near(c.cr, 5.25, 1e-9, "melee crit")
		T.near(c.scr[6], 3.75, 1e-9, "spell crit per school")
		T.near(c.mr[1], 8.5, 1e-9, "mana regen out of combat")
		T.near(c.mr[2], 1.25, 1e-9, "mana regen while casting")
		T.near(c.wp[3], 2.6, 1e-9, "main hand speed")
		T.near(c.wp[9], 2.0, 1e-9, "ranged speed")
		T.eq(c.it[1], "1:1234:15:2045", "slot:item:enchant:suffix bonus")
		R.event("PLAYER_LEVEL_UP", 13)
		R.level = 13
		R.wait(4)
		R.tick()
		c = R.all("c")
		T.eq(#c, 2, "a snapshot after the level up")
		T.eq(c[2].l, 13)
		local x = R.all("x")
		T.eq(x[#x].w, "l", "xp mark at the level up")
		R.done()
	end,

	snapshots_wait_for_the_end_of_combat = function()
		local R = RF.setup({ record = true })
		R.login()
		R.combat = true
		R.event("PLAYER_REGEN_DISABLED")
		R.wait(20)
		R.tick()
		T.eq(#R.all("c"), 0, "none in combat")
		R.combat = false
		R.event("PLAYER_REGEN_ENABLED")
		R.wait(5)
		R.tick()
		T.eq(#R.all("c"), 1, "after combat")
		R.done()
	end,

	a_meal_records_its_length_and_aura_duration = function()
		local R = RF.setup({ record = true })
		R.login()
		R.play(20)
		R.auras[1] = { name = "Drink", duration = 30, expirationTime = R.now + 30, spellId = 1133 }
		R.event("UNIT_AURA", "player")
		R.wait(18)
		R.auras[1] = nil
		R.event("UNIT_AURA", "player")
		local m = R.all("m")
		T.eq(#m, 1)
		T.eq(m[1].k, "d", "drink")
		T.near(m[1].d, 18, 0.2, "seconds")
		T.eq(m[1].a, 30, "the aura's duration")
		T.eq(m[1].i, nil, "not interrupted")
		R.done()
	end,

	a_pull_interrupting_a_meal_is_flagged = function()
		local R = RF.setup({ record = true })
		R.login()
		R.play(20)
		R.auras[1] = { name = "Food", duration = 24, expirationTime = R.now + 24, spellId = 1131 }
		R.event("UNIT_AURA", "player")
		R.wait(6)
		R.fight(10, { { 448, 12, "Beast", false, 50 } })
		local m = R.all("m")
		T.eq(#m, 1)
		T.eq(m[1].k, "f")
		T.eq(m[1].i, 1, "interrupted by the pull")
		T.ok(R.all("p")[1].f:find("a"), "the pull follows a meal")
		R.done()
	end,

	a_death_records_its_context_and_the_time_to_the_next_pull = function()
		local R = RF.setup({ record = true })
		R.login()
		R.play(20)
		local a = R.mob("target", 448, 14, "Beast", false)
		local b = R.mob("nameplate2", 449, 13, "Beast", false)
		R.pullStart()
		R.tick()
		R.wait(15)
		R.event("PLAYER_DEAD")
		R.combat = false
		R.event("PLAYER_REGEN_ENABLED")
		R.units = {}
		R.wait(60)
		R.event("PLAYER_ALIVE")
		R.wait(30)
		R.event("PLAYER_UNGHOST")
		R.play(20)
		R.fight(10, { { 448, 12, "Beast", false, 50 } })
		local d = R.all("d")
		T.eq(#d, 1)
		d = d[1]
		T.eq(d.l, 12, "level")
		T.eq(d.n, 2, "mobs")
		T.eq(table.concat(d.ml, ","), "14,13", "mob levels")
		T.near(d.f, 15, 1.5, "fight so far")
		T.near(d.r, 90, 1.5, "dead to alive")
		T.near(d.nx, 110, 2, "death to the next pull")
		T.ok(R.all("p")[1].f:find("d"), "the pull is flagged died")
		T.eq(a.guid ~= nil and b.guid ~= nil, true)
		R.done()
	end,

	afk_and_long_pauses_are_not_active_play = function()
		local R = RF.setup({ record = true })
		R.login()
		R.play(600)
		local before = R.ns.Record.ActiveSeconds()
		T.near(before, 600, 15, "ten minutes of play")
		R.afk = true
		R.event("PLAYER_FLAGS_CHANGED", "player")
		R.wait(900)
		R.tick()
		R.afk = false
		R.event("PLAYER_FLAGS_CHANGED", "player")
		R.play(60)
		T.near(R.ns.Record.ActiveSeconds() - before, 60, 15, "AFK left out")
		-- an idle pause without the flag (no input, combat or movement for 5 minutes)
		local mid = R.ns.Record.ActiveSeconds()
		R.wait(300)
		R.tick()
		R.play(60)
		T.near(R.ns.Record.ActiveSeconds() - mid, 60, 15, "the idle pause left out")
		local k = R.all("k")
		T.eq(#k, 2, "two pauses over 2 minutes recorded")
		R.done()
	end,

	xp_marks_at_login_and_session_end = function()
		local R = RF.setup({ record = true })
		R.rested = 300
		R.login()
		R.play(20)
		R.xp = 400
		R.event("PLAYER_LOGOUT")
		local x = R.all("x")
		T.eq(x[1].w, "s")
		T.eq(x[1].r, 300, "rested")
		T.eq(x[#x].w, "e")
		T.eq(x[#x].x, 400)
		R.done()
	end,

	storage_keeps_about_twenty_hours_of_active_play = function()
		local R = RF.setup({ record = true })
		R.login()
		for _ = 1, 23 do
			R.play(3600)
			R.fight(10, { { 448, 12, "Beast", false, 50 } })
		end
		local total = 0
		for _, b in ipairs(R.blocks()) do total = total + b.a end
		T.ok(total <= 20 * 3600 + 60, "at most ~20 h kept: " .. total)
		T.ok(total >= 19 * 3600, "the newest ~20 h kept: " .. total)
		T.ok(#R.all("p") <= 21, "the oldest pulls dropped")
		R.done()
	end,

	cheap_per_event = function()
		local R = RF.setup({ record = true })
		R.login()
		R.play(20)
		R.mob("target", 448, 12, "Beast", false)
		R.pullStart()
		local t0 = os.clock()
		for i = 1, 1000 do
			R.ns._frame.scripts.OnEvent(R.ns._frame, "UNIT_SPELLCAST_SUCCEEDED", "player", "c", 116)
			R.ns._frame.scripts.OnEvent(R.ns._frame, "UNIT_DIED", "Creature-0-1-0-1-999-" .. i)
		end
		local per = (os.clock() - t0) / 2000
		T.ok(per < 0.0002, ("%.1f us per event"):format(per * 1e6))
		R.done()
	end,

	settings_switches_turn_recording_and_asking_on_and_off = function()
		local R = RF.setup({ record = false })
		R.login()
		local fx = R.fx
		fx.open()
		local p = fx.tab("settings")
		local rec = R.U.find(p, function(w) return w.get and R.U.ownText(w) == "Record leveling data for PoleSim" end)
		local ask = R.U.find(p, function(w) return w.get and R.U.ownText(w) == "Ask me to upload every 4 h of play" end)
		T.ok(rec and ask, "both switches")
		rec:Click()
		T.eq(R.ns.Options.Get("record"), true, "recording on from Settings")
		ask:Click()
		T.eq(R.ns.Options.Get("recPrompt"), false, "asking off")
		T.ok(R.U.texts(p):find("h of active play recorded", 1, true), "status line")
		T.ok(R.U.button(p, "Export now"), "export button")
		R.done()
	end,

	no_names_anywhere_in_saved_variables = function()
		local R = RF.setup({ record = true })
		R.login()
		R.play(30)
		R.fight(10, { { 448, 12, "Beast", false, 50 } }, { 116 })
		R.event("PLAYER_LEVEL_UP", 13)
		R.level = 13
		R.wait(5)
		R.tick()
		for _, s in ipairs(RF.strings({ _G.PoleSimGearDB, _G.PoleSimGearCharDB })) do
			for _, name in ipairs(RF.NAMES) do
				T.ok(not s:find(name, 1, true), "a name in SavedVariables: " .. s)
			end
			T.ok(not s:find("Player%-"), "a player GUID in SavedVariables: " .. s)
			T.ok(not s:find("Creature%-"), "a creature GUID in SavedVariables: " .. s)
		end
		R.done()
	end,
}
