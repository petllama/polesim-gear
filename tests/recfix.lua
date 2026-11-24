-- The recorder's test client: the whole addon (winfix) plus the client APIs the recorder reads, driven
-- by a clock (R.now), unit tables (R.units[token]) and events (R.event). Every name the client could
-- hand out (player, realm, guild, mobs) is a marker string the SavedVariables scan looks for.
local F = require("winfix")
local RF = {}

RF.NAMES = { "Pelleas", "Argent Dawn", "Llama Lords", "Kobold Vermin", "Pathfinder Pal" }

-- opts: { db, char, level, record = true|false|nil (the opt-in answer), prompt }
function RF.setup(opts)
	opts = opts or {}
	local db = opts.db or {}
	if opts.record ~= nil then
		db.options = db.options or {}
		db.options.record = opts.record
		db.options.recAsked = true
	end
	if opts.prompt ~= nil then
		db.options = db.options or {}
		db.options.recPrompt = opts.prompt
	end
	local fx = F.load({ db = db, char = opts.char, level = opts.level or 12 })
	local R = { now = 1000, combat = false, afk = false, moving = false, instance = false, casting = false,
		units = {}, auras = {}, xp = 100, xpMax = 1000, rested = 0, level = opts.level or 12, frames = {} }
	_G.GetTime = function() return R.now end
	_G.InCombatLockdown = function() return R.combat end
	_G.UnitAffectingCombat = function(u)
		if u == "player" then return R.combat end
		local e = R.units[u]
		return e and e.combat or false
	end
	_G.UnitIsAFK = function(u) return u == "player" and R.afk end
	_G.IsPlayerMoving = function() return R.moving end
	_G.IsInInstance = function() return R.instance, R.instance and "party" or "none" end
	_G.UnitCastingInfo = function(u) if u == "player" and R.casting then return "Frostbolt" end end
	_G.UnitChannelInfo = function() return nil end
	_G.UnitName = function(u)
		if u == "player" then return RF.NAMES[1], RF.NAMES[2] end
		local e = R.units[u]
		return e and RF.NAMES[4] or nil
	end
	_G.GetRealmName = function() return RF.NAMES[2] end
	_G.GetGuildInfo = function() return RF.NAMES[3] end
	_G.UnitExists = function(u) return u == "player" or R.units[u] ~= nil end
	_G.UnitGUID = function(u)
		if u == "player" then return "Player-1-0000ABCD" end
		if u == "pet" then return R.pet end
		local e = R.units[u]
		return e and e.guid
	end
	local W = require("wow")
	_G.UnitLevel = function(u)
		if u == "player" then return R.level end
		local e = R.units[u]
		return e and e.lvl or 0
	end
	_G.UnitCreatureType = function(u) local e = R.units[u] return e and e.ctype end
	_G.UnitPowerType = function(u)
		if u == "player" then return 0, "MANA" end
		local e = R.units[u]
		if not e then return nil end
		return e.mana and 0 or 1, e.mana and "MANA" or "RAGE"
	end
	_G.UnitCanAttack = function(_, u) local e = R.units[u] return e ~= nil and e.hostile ~= false end
	_G.UnitThreatSituation = function(_, u) local e = R.units[u] return e and e.threat or nil end
	_G.UnitXP = function() return R.xp end
	_G.UnitXPMax = function() return R.xpMax end
	_G.GetXPExhaustion = function() return R.rested > 0 and R.rested or nil end
	_G.GetBuildInfo = function() return "1.60.1", "70938", "Nov 1 2026", 16001 end
	-- the character sheet
	_G.UnitStat = function(_, i) return 10 + i, 20 + i end
	_G.UnitHealthMax = function() return 500 end
	_G.UnitPowerMax = function() return 800 end
	_G.UnitHealth = function() error("UnitHealth is secret in Forever: never read") end
	_G.UnitPower = function() error("UnitPower is secret in Forever: never read") end
	_G.UnitArmor = function() return 300, 320 end
	_G.UnitAttackPower = function() return 40, 5, 0 end
	_G.UnitRangedAttackPower = function() return 30, 0, 0 end
	_G.GetSpellBonusDamage = function(school) return school == 6 and 25 or 10 end
	_G.GetSpellBonusHealing = function() return 12 end
	_G.GetCritChance = function() return 5.25 end
	_G.GetRangedCritChance = function() return 4.5 end
	_G.GetSpellCritChance = function() return 3.75 end
	_G.GetHitModifier = function() return 1 end
	_G.GetSpellHitModifier = function() return 2 end
	_G.GetDodgeChance = function() return 4.1 end
	_G.GetParryChance = function() return 0 end
	_G.GetBlockChance = function() return 0 end
	_G.GetManaRegen = function() return 8.5, 1.25 end
	_G.UnitDamage = function() return 20, 30, 0, 0 end
	_G.UnitAttackSpeed = function() return 2.6, nil end
	_G.UnitRangedDamage = function() return 2.0, 15, 25 end
	_G.C_Spell = { GetSpellName = function(id) return ({ [433] = "Food", [430] = "Drink" })[id] end }
	_G.C_UnitAuras = { GetAuraDataByIndex = function(u, i, filter)
		if u ~= "player" or filter ~= "HELPFUL" then return nil end
		return R.auras[i]
	end }
	_G.COMBATLOG_XPGAIN_FIRSTPERSON = "%s dies, you gain %d experience."
	_G.COMBATLOG_XPGAIN_EXHAUSTION1 = "%s dies, you gain %d experience. (%s exp %s bonus)"
	_G.issecretvalue = function(v) return type(v) == "table" and v.secret == true end
	-- the frames the calm check looks at
	for _, name in ipairs({ "AuctionHouseFrame", "MailFrame", "MerchantFrame", "ClassTrainerFrame" }) do
		_G[name] = { IsShown = function() return R.frames[name] == true end }
	end
	W.level = R.level
	local ns = fx.ns
	R.fx, R.ns, R.db, R.U = fx, ns, _G.PoleSimGearDB, fx.U
	function R.event(name, ...)
		ns._frame.scripts.OnEvent(ns._frame, name, ...)
		fx.settle()
	end
	function R.at(t) R.now = t end
	function R.wait(s) R.now = R.now + s end
	function R.tick() ns.Record.Tick() fx.settle() end
	-- n seconds of play: activity every 10 s (moving), the clock ticking
	function R.play(seconds)
		local was = R.moving
		R.moving = true
		local left = seconds
		while left > 0 do
			local s = math.min(10, left)
			R.wait(s)
			R.tick()
			left = left - s
		end
		R.moving = was
	end
	function R.login()
		_G.IsLoggedIn = function() return true end
		R.event("PLAYER_LOGIN")
		R.event("PLAYER_ENTERING_WORLD", true, false)
	end
	-- a hostile mob as a unit token: { guid, npc, lvl, ctype, mana, threat }
	function R.mob(token, npc, lvl, ctype, mana, spawn)
		local e = { guid = "Creature-0-1-0-1-" .. npc .. "-" .. (spawn or "0000AAAA"), lvl = lvl, ctype = ctype, mana = mana,
			threat = 1, combat = true }
		R.units[token] = e
		if token:match("^nameplate") then R.event("NAME_PLATE_UNIT_ADDED", token) end
		return e
	end
	function R.pullStart()
		R.combat = true
		R.event("PLAYER_REGEN_DISABLED")
	end
	function R.pullEnd()
		R.combat = false
		R.event("PLAYER_REGEN_ENABLED")
	end
	function R.cast(id) R.event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-0-0-0-" .. id .. "-0", id) end
	function R.kill(e, xp)
		R.event("UNIT_DIED", e.guid)
		if xp then R.event("CHAT_MSG_COMBAT_XP_GAIN", RF.NAMES[4] .. " dies, you gain " .. xp .. " experience.", "") end
	end
	-- one whole pull: mobs as { npc, lvl, ctype, mana, xp }, casts as spell ids
	function R.fight(seconds, mobs, casts)
		local units = {}
		for i, m in ipairs(mobs) do
			units[i] = R.mob(i == 1 and "target" or ("nameplate" .. i), m[1], m[2], m[3], m[4], tostring(i) .. tostring(R.now))
		end
		R.pullStart()
		R.tick()
		for _, id in ipairs(casts or {}) do R.cast(id) end
		R.wait(seconds)
		for i, m in ipairs(mobs) do R.kill(units[i], m[5]) end
		R.pullEnd()
		for token in pairs(R.units) do
			if token:match("^nameplate") then R.event("NAME_PLATE_UNIT_REMOVED", token) end
		end
		R.units = {}
		R.wait(3)
		R.tick()
	end
	function R.rec() return _G.PoleSimGearCharDB.rec end
	function R.blocks() return R.rec().blocks end
	-- every record of a kind over all blocks
	function R.all(kind)
		local out = {}
		for _, b in ipairs(R.blocks() or {}) do
			for _, r in ipairs(b[kind] or {}) do out[#out + 1] = r end
		end
		return out
	end
	function R.done()
		for _, k in ipairs({ "GetTime", "UnitAffectingCombat", "UnitIsAFK", "IsPlayerMoving", "IsInInstance", "UnitCastingInfo",
			"UnitChannelInfo", "UnitName", "GetRealmName", "GetGuildInfo", "UnitExists", "UnitGUID", "UnitCreatureType",
			"UnitPowerType", "UnitCanAttack", "UnitThreatSituation", "UnitXP", "UnitXPMax", "GetXPExhaustion", "GetBuildInfo",
			"UnitStat", "UnitHealthMax", "UnitPowerMax", "UnitHealth", "UnitPower", "UnitArmor", "UnitAttackPower",
			"UnitRangedAttackPower", "GetSpellBonusDamage", "GetSpellBonusHealing", "GetCritChance", "GetRangedCritChance",
			"GetSpellCritChance", "GetHitModifier", "GetSpellHitModifier", "GetDodgeChance", "GetParryChance", "GetBlockChance",
			"GetManaRegen", "UnitDamage", "UnitAttackSpeed", "UnitRangedDamage", "C_Spell", "C_UnitAuras", "issecretvalue",
			"AuctionHouseFrame", "MailFrame", "MerchantFrame", "ClassTrainerFrame" }) do
			_G[k] = nil
		end
		fx.done()
	end
	return R
end

-- Every string anywhere in a table (keys and values), for the name scan.
function RF.strings(t, out, seen)
	out, seen = out or {}, seen or {}
	if type(t) ~= "table" or seen[t] then return out end
	seen[t] = true
	for k, v in pairs(t) do
		if type(k) == "string" then out[#out + 1] = k end
		if type(v) == "string" then out[#out + 1] = v elseif type(v) == "table" then RF.strings(v, out, seen) end
	end
	return out
end

-- A level 12 priest's typical hour: pulls of 1-2 mobs every ~45 s, a drink now and then.
function RF.session(R, seconds)
	local spent, i = 0, 0
	while spent < seconds do
		i = i + 1
		local two = i % 4 == 0
		local mobs = { { 448 + i % 7, 12 + i % 2, i % 3 == 0 and "Humanoid" or "Beast", i % 3 == 0, 50 + i % 9 } }
		if two then mobs[2] = { 449, 12, "Beast", false, 48 } end
		R.fight(two and 26 or 18, mobs, { 585, 585, 589, i % 5 == 0 and 17 or 8092 })
		R.play(22)
		spent = spent + (two and 26 or 18) + 25
		if i % 6 == 0 then
			R.auras[1] = { name = "Drink", duration = 18, expirationTime = R.now + 18, spellId = 1133 }
			R.event("UNIT_AURA", "player")
			R.play(14)
			R.auras[1] = nil
			R.event("UNIT_AURA", "player")
			spent = spent + 14
		end
	end
end

return RF
