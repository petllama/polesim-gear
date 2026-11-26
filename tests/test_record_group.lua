-- Dungeon group fights in the recorder (Record.lua "Group fights in dungeons", kind g): only with
-- recording on, in a party, inside a dungeon; roles, mobs, the player's heals per target role and the
-- party's damage taken from the client's damage meter (read after the fight), deaths, mana, drinking,
-- caps, the export's `groups` table, and no names or GUIDs anywhere.
local T = require("t")
local RF = require("recfix")

local TAKEN, HEAL, ABS, DEATHS = 7, 2, 4, 9
local MAGE_GUID, ME = "Player-1-00002EEE", "Player-1-0000ABCD"
local fakeMeter, fight, meterFor = RF.fakeMeter, RF.groupFight, RF.meterFor

-- a level 23 priest in Blackfathom Deeps with a warrior tank and a mage
local function setup(o)
	o = o or {}
	local R = RF.setup({ record = o.record ~= false, level = 23 })
	R.instance = o.instance ~= false
	R.login()
	R.play(10)
	if o.party ~= false then
		R.member("party1", "WARRIOR", 24, { role = o.roles ~= false and "TANK" or nil, name = RF.NAMES[6] })
		R.member("party2", "MAGE", 22, { role = o.roles ~= false and "DAMAGER" or nil, name = RF.NAMES[7] })
	end
	R.tick()
	return R
end

local function finish(R)
	_G.C_DamageMeter = nil
	R.done()
end

return {
	nothing_outside_a_dungeon_party = function()
		-- open world, in a party
		local R = setup({ instance = false })
		local meter = fakeMeter(R)
		fight(R, { { "target", 4789, 23, "elite" } }, 10)
		T.eq(#R.all("g"), 0, "no group fight in the open world")
		T.eq(next(R.ns.Record.GroupRegistered()), nil, "no fight events registered")
		T.eq(R.ns.Record.GroupOn(), false)
		finish(R)
		-- a dungeon, solo
		R = setup({ party = false })
		fakeMeter(R)
		fight(R, { { "target", 4789, 23, "elite" } }, 10)
		T.eq(#R.all("g"), 0, "no group fight solo")
		T.eq(next(R.ns.Record.GroupRegistered()), nil)
		T.eq(#R.all("p"), 1, "the leveling pull is still recorded")
		finish(R)
		-- a dungeon party with recording off
		R = setup({ record = false })
		fakeMeter(R)
		fight(R, { { "target", 4789, 23, "elite" } }, 10)
		T.eq(#R.all("g"), 0, "nothing with recording off")
		T.eq(next(R.ns.Record.GroupRegistered()), nil)
		finish(R)
		T.eq(meter.list[1], nil)
	end,

	the_gate_registers_and_drops_the_fight_events = function()
		local R = setup()
		local reg = R.ns.Record.GroupRegistered()
		T.ok(reg.UNIT_COMBAT and reg.ENCOUNTER_START and reg.ENCOUNTER_END, "registered in a dungeon party")
		T.eq(R.ns.Record.GroupOn(), true)
		-- a fight in progress, then the player leaves the dungeon (hearth, port out)
		for token in pairs(R.party) do R.units[token].combat = true end
		R.pullStart()
		R.wait(3)
		R.tick()
		R.instance = false
		R.event("ZONE_CHANGED_NEW_AREA")
		T.eq(next(R.ns.Record.GroupRegistered()), nil, "dropped outside")
		local g = R.all("g")
		T.eq(#g, 1, "the fight so far is kept")
		T.ok(g[1].f:find("x", 1, true), "flag x: ended by leaving")
		R.pullEnd()
		-- the recording option off closes the gate too
		R.instance = true
		R.event("ZONE_CHANGED_NEW_AREA")
		T.eq(R.ns.Record.GroupOn(), true)
		R.ns.Options.Set("record", false)
		T.eq(R.ns.Record.GroupOn(), false, "recording off")
		T.eq(next(R.ns.Record.GroupRegistered()), nil)
		finish(R)
	end,

	a_dungeon_fight_records_roles_mobs_heals_damage_deaths_and_mana = function()
		local R = setup()
		local meter = fakeMeter(R)
		meter.add(3, 12, {}) -- a session from before: never this fight's
		R.event("ZONE_CHANGED_NEW_AREA")
		R.ns.Record.GroupCheck()
		R.mana = 900
		local mobs = { { "target", 4789, 24, "elite", RF.NAMES[9] }, { "nameplate2", 4798, 23, "elite" },
			{ "boss1", 4887, 25, "worldboss", RF.NAMES[9] } }
		fight(R, mobs, 30, function(R2, s)
			R2.mana = 900 - s * 10
			if s == 1 then R2.gevent("ENCOUNTER_START", 1667, RF.NAMES[9], 1, 5) end
			if s == 2 then R2.cast(2061) end
			if s == 5 then R2.cast(139) end
			if s == 6 then
				R2.gevent("UNIT_COMBAT", "party1", "WOUND", "", 150, 1)
				R2.gevent("UNIT_COMBAT", "party1", "WOUND", "CRITICAL", 230, 1)
				R2.gevent("UNIT_COMBAT", "party2", "WOUND", "", 90, 8)
				R2.gevent("UNIT_COMBAT", "party1", "HEAL", "", 500, 2) -- heals received: not damage
			end
			if s == 28 then R2.event("UNIT_DIED", MAGE_GUID) end
		end, function(R2)
			R2.gevent("ENCOUNTER_END", 1667, RF.NAMES[9], 1, 5, 1)
			meterFor(meter, 5)
		end)
		local g = R.all("g")
		T.eq(#g, 1, "one group fight")
		g = g[1]
		T.near(g.d, 30, 1.5, "fight length")
		T.eq(g.i, 48, "instance id"); T.eq(g.df, 1, "difficulty"); T.eq(g.n, 1, "pull 1")
		T.eq(g.e, 1667, "encounter"); T.eq(g.es, 1, "won"); T.eq(g.b, 1, "a boss")
		T.eq(#g.m, 3, "three mobs")
		T.eq(g.m[1][1], 4789); T.eq(g.m[1][2], 24); T.eq(g.m[1][3], "e", "elite")
		local boss
		for _, m in ipairs(g.m) do if m[1] == 4887 then boss = m end end
		T.eq(boss[3], "b", "boss classification")
		T.eq(table.concat(g.p, ";"), "s:PRIEST:23;t:WARRIOR:24;o:MAGE:22", "party by role, class, level")
		T.eq(g.rs, "a", "tank from the assigned role")
		-- heals: Flash Heal 600 to the tank + 200 to self, Renew 300 to the mage (a single detail table)
		T.eq(g.ht, 1100, "healing total")
		T.eq(#g.h, 2)
		T.eq(table.concat(g.h[1], ","), "2061,800,120,200,600,0,0")
		T.eq(table.concat(g.h[2], ","), "139,300,-1,0,0,300,0", "overheal unknown = -1")
		T.eq(table.concat(g.ab[1], ","), "592,240", "absorbs")
		-- damage taken per role: total, melee, spell, biggest hit, hits seen
		T.eq(table.concat(g.dt.t, ","), "1200,1000,200,230,2", "tank")
		T.eq(table.concat(g.dt.o, ","), "300,0,300,90,1", "others")
		T.eq(table.concat(g.dt.s, ","), "100,100,0,-1,0", "self")
		T.eq(table.concat(g.ds[1], ","), "t,4887,1,1000", "biggest source: the boss's melee on the tank")
		T.eq(#g.ds, 4)
		T.eq(g.x.o, 1, "the mage died (UNIT_DIED and the meter: once)")
		T.eq(g.x.t, 0); T.eq(g.x.s, 0)
		-- mana every second, start and end
		T.eq(g.mp.a, 900, "start"); T.eq(g.mp.z, 600, "end"); T.eq(g.mp.mx, 800, "max")
		T.ok(#g.mp.c >= 30 and #g.mp.c <= 32, "a sample a second: " .. #g.mp.c)
		T.eq(table.concat(g.st, ","), "12,25,24,8.5,1.25,800", "sheet: +healing, spirit, int, regen, casting, max mana")
		T.eq(g.c[2061], 1); T.eq(g.c[139], 1)
		T.eq(g.ct[1][2], 2061); T.near(g.ct[1][1], 2, 1.1, "cast time into the fight")
		T.eq(g.ms, 31.5, "the meter's session length")
		T.eq(g.f, "", "nothing secret: " .. g.f)
		finish(R)
	end,

	without_roles_the_tank_is_who_took_the_most_melee = function()
		local R = setup({ roles = false })
		local meter = fakeMeter(R)
		fight(R, { { "target", 4789, 24, "elite" } }, 8, nil, function() meterFor(meter, 1) end)
		local g = R.all("g")[1]
		T.eq(g.rs, "d", "from damage")
		T.eq(table.concat(g.p, ";"), "s:PRIEST:23;t:WARRIOR:24;o:MAGE:22")
		-- next fight: nothing readable -> the tank of the earlier fight
		_G.C_DamageMeter = nil
		fight(R, { { "target", 4789, 24, "elite" } }, 8)
		local g2 = R.all("g")[2]
		T.eq(g2.rs, "c", "carried over")
		T.eq(g2.n, 2, "pull 2")
		T.ok(g2.g > 0, "gap since the last fight")
		T.eq(table.concat(g2.p, ";"), "s:PRIEST:23;t:WARRIOR:24;o:MAGE:22")
		finish(R)
	end,

	secret_reads_become_flags_not_errors = function()
		local R = setup()
		local errors = {}
		R.ns.ReportOnce = function(k, e) errors[#errors + 1] = k .. ": " .. tostring(e) end
		local meter = fakeMeter(R)
		local S = { secret = true }
		fight(R, { { "target", 4789, 24, "elite" } }, 6, function(R2, s)
			if s == 2 then R2.gevent("UNIT_COMBAT", "party1", "WOUND", "", S, 1) end
		end, function()
			meter.add(1, 6, { [HEAL] = { sources = { { sourceGUID = ME, totalAmount = S, isLocalPlayer = true } } },
				[TAKEN] = { sources = { { sourceGUID = S, name = S, classFilename = "WARRIOR", totalAmount = S } } } })
		end)
		local g = R.all("g")[1]
		T.ok(g.f:find("p", 1, true), "mana secret: " .. g.f)
		T.ok(g.f:find("u", 1, true), "hit sizes secret")
		T.ok(g.f:find("S", 1, true), "meter values secret")
		T.eq(#g.mp.c, 0, "no mana samples")
		T.eq(g.mp.a, -1)
		T.eq(g.ht, 0)
		T.eq(table.concat(g.dt.t, ","), "0,0,0,-1,1", "a hit seen, its size unknown")
		-- no damage meter at all
		_G.C_DamageMeter = nil
		fight(R, { { "target", 4789, 24, "elite" } }, 6)
		T.ok(R.all("g")[2].f:find("M", 1, true), "flag M")
		T.eq(#errors, 0, table.concat(errors, "; "))
		finish(R)
	end,

	drinking_between_pulls_is_counted = function()
		local R = setup()
		fakeMeter(R)
		fight(R, { { "target", 4789, 24, "elite" } }, 5)
		R.auras[1] = { name = "Drink", duration = 18, expirationTime = R.now + 18, spellId = 1133 }
		R.event("UNIT_AURA", "player")
		R.wait(12)
		R.tick()
		R.auras[1] = nil
		R.event("UNIT_AURA", "player")
		R.wait(5)
		-- the next pull interrupts a second drink after 4 s
		R.auras[1] = { name = "Drink", duration = 18, expirationTime = R.now + 18, spellId = 1133 }
		R.event("UNIT_AURA", "player")
		R.wait(4)
		fight(R, { { "target", 4789, 24, "elite" } }, 5)
		local g = R.all("g")
		T.eq(g[1].dk, 0, "no drink before the first")
		T.near(g[2].dk, 16, 0.6, "12 s + 4 s of drinking")
		finish(R)
	end,

	a_new_dungeon_visit_counts_pulls_from_one = function()
		local R = setup()
		fakeMeter(R)
		fight(R, { { "target", 4789, 24, "elite" } }, 5)
		fight(R, { { "target", 4789, 24, "elite" } }, 5)
		R.instance = false
		R.event("ZONE_CHANGED_NEW_AREA")
		R.instance, R.instanceId = true, 36
		R.event("ZONE_CHANGED_NEW_AREA")
		fight(R, { { "target", 1732, 18, "elite" } }, 5)
		local g = R.all("g")
		T.eq(g[2].n, 2); T.eq(g[3].n, 1, "a new visit"); T.eq(g[3].i, 36); T.eq(g[3].g, -1, "no gap across visits")
		finish(R)
	end,

	caps_on_fights_mobs_casts_and_samples = function()
		local R = setup()
		fakeMeter(R)
		local printed = {}
		R.ns.Print = function(s) printed[#printed + 1] = s end
		local Rec = R.ns.Record
		Rec.GROUP_MAX, Rec.GROUP_MOBS, Rec.GROUP_CASTS, Rec.GROUP_SAMPLES = 3, 2, 4, 5
		R.mana = 500
		for _ = 1, 5 do
			fight(R, { { "target", 1, 24, "elite" }, { "nameplate2", 2, 24 }, { "nameplate3", 3, 24 } }, 8, function(R2)
				R2.cast(2061)
			end)
		end
		local g = R.all("g")
		T.eq(#g, 3, "at most GROUP_MAX held")
		T.eq(#printed, 1, "one chat line when full: " .. table.concat(printed, " | "))
		T.ok(printed[1]:find("/psg export", 1, true))
		T.eq(#g[1].m, 2, "mobs capped"); T.eq(#g[1].ct, 4, "cast times capped"); T.eq(g[1].c[2061], 8, "counts stay whole")
		T.eq(#g[1].mp.c, 5, "samples capped")
		T.eq(#R.ns.RecordExport.Summary().groups.fights, 3)
		finish(R)
	end,

	-- a full store (GROUP_MAX fights of 45 s, mana readable, the meter answering) stays well under the
	-- website's 400 KB limit and a small SavedVariables
	a_full_store_exports_small = function()
		local R = setup()
		local meter = fakeMeter(R)
		R.mana = 900
		local id = 0
		for i = 1, R.ns.Record.GROUP_MAX do
			fight(R, { { "target", 4789, 24, "elite" }, { "nameplate2", 4798 + i % 3, 23, "elite" } }, 45, function(R2, s)
				R2.mana = 900 - s * 7
				if s % 3 == 0 then R2.cast(s % 2 == 0 and 2061 or 139) end
			end, function() id = id + 1 meterFor(meter, id) end)
		end
		local E = R.ns.RecordExport
		local doc = E.Summary()
		T.eq(#doc.groups.fights, R.ns.Record.GROUP_MAX)
		local json = E.Json(doc)
		local parts = E.Build(doc)
		local chars = #table.concat(parts)
		print(("    %d group fights: JSON %d B, export %d B in %d part(s)"):format(#doc.groups.fights, #json, chars, #parts))
		T.ok(chars < 150000, "export " .. chars)
		finish(R)
	end,

	no_names_or_guids_are_stored_or_exported = function()
		local R = setup()
		local meter = fakeMeter(R)
		R.mana = 700
		fight(R, { { "target", 4789, 24, "elite", RF.NAMES[9] }, { "boss1", 4887, 25, "worldboss", RF.NAMES[9] } }, 10,
			function(R2, s) if s == 3 then R2.gevent("ENCOUNTER_START", 1667, RF.NAMES[9], 1, 5) end end,
			function(R2) R2.gevent("ENCOUNTER_END", 1667, RF.NAMES[9], 1, 5, 1) meterFor(meter, 1) end)
		local strings = RF.strings(_G.PoleSimGearCharDB)
		for _, s in ipairs(RF.strings(_G.PoleSimGearDB)) do strings[#strings + 1] = s end
		local E = R.ns.RecordExport
		local json = E.Json(E.Summary())
		strings[#strings + 1] = json
		for _, s in ipairs(strings) do
			for _, name in ipairs(RF.NAMES) do T.ok(not s:find(name, 1, true), "no name: " .. name .. " in " .. s:sub(1, 80)) end
			T.ok(not s:find("Player%-"), "no player GUID")
			T.ok(not s:find("Creature%-"), "no mob GUID")
		end
		finish(R)
	end,

	the_export_carries_groups_and_round_trips = function()
		local R = setup()
		local meter = fakeMeter(R)
		R.mana = 700
		fight(R, { { "target", 4789, 24, "elite", RF.NAMES[9] } }, 10, nil, function() meterFor(meter, 1) end)
		local E = R.ns.RecordExport
		local doc = E.Summary()
		T.eq(doc.v, 1, "the export format is unchanged")
		T.eq(doc.groups.v, 1, "groups has its own version")
		local f = doc.groups.fights[1]
		T.eq(f.inst, 48); T.eq(f.pull, 1); T.eq(f.mobs, "4789:24:e"); T.eq(f.party, "s:PRIEST:23;t:WARRIOR:24;o:MAGE:22")
		T.eq(f.healTotal, 1100); T.eq(#f.heal, 2); T.eq(f.heal[1][1], 2061)
		T.eq(f.taken[1][1], "s"); T.eq(f.taken[2][1], "t"); T.eq(f.taken[2][2], 1200)
		T.eq(f.takenBy[1][1], "t")
		T.eq(table.concat(f.deaths, ","), "0,0,1")
		T.eq(f.mana[1], 700); T.eq(#f.stats, 6); T.eq(f.encOk, -1)
		local parts = E.Build(doc)
		local back = E.Decode(table.concat(parts, "\n"))
		T.eq(E.Json(back), E.Json(doc), "decodes to the same document")
		finish(R)
		-- a character with only old blocks (no g): an empty groups table
		local R2 = setup({ party = false, instance = false })
		R2.fight(10, { { 448, 12, "Beast", false, 50 } })
		local d2 = R2.ns.RecordExport.Summary()
		for _, b in ipairs(R2.blocks()) do b.g = nil end
		d2 = R2.ns.RecordExport.Summary()
		T.eq(#d2.groups.fights, 0)
		T.eq(#d2.pulls.rows, 1)
		finish(R2)
	end,

	psg_group_reports_the_gate_and_the_last_fight = function()
		local R = setup()
		local meter = fakeMeter(R)
		fight(R, { { "target", 4789, 24, "elite" } }, 6, nil, function() meterFor(meter, 1) end)
		local text = table.concat(R.ns.RecordUI.GroupText(), "\n")
		T.ok(text:find("ON here", 1, true), text)
		T.ok(text:find("1 of 200 fights", 1, true), text)
		T.ok(text:find("healing 1100", 1, true), text)
		T.ok(text:find("mana secret", 1, true), "mana unreadable is said: " .. text)
		R.instance = false
		R.event("ZONE_CHANGED_NEW_AREA")
		T.ok(R.ns.RecordUI.GroupText()[1]:find("not in a dungeon", 1, true))
		finish(R)
	end,
}
