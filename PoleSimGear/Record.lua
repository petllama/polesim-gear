-- The leveling recorder (opt-in, off until the player says yes): what PoleSim's model needs to check
-- itself against real play, kept per character in PoleSimGearCharDB.rec, nothing named.
--
--   c  character sheet at login and at every level up (stats, pools, armor, power, crit/hit, avoidance,
--      the client's mana regen out of combat and while casting, weapons, worn item ids, talents)
--   p  a pull: start/end (seconds into the session), its level, the mobs engaged (npc id from the GUID,
--      level, creature type, caster = has mana), kills with the XP each paid, the player's casts per
--      spell id, the gap since the previous pull's end, flags (a after a meal, d died, s some reads secret)
--   m  a meal: Food/Drink aura start, seconds, the aura's duration, kind, interrupted by a pull
--   d  a death: level, mobs and their levels, the fight so far, dead -> alive, death -> next pull
--   x  XP and rested at the session's start, every level up and the session's end
--   k  a pause over 2 minutes (AFK flag, or no combat, movement, casting or other input)
-- Records sit in blocks of at most an hour of ACTIVE play (pauses left out); about 20 h are kept per
-- character (oldest blocks dropped first). Export (RecordExport.lua) summarises them; a confirmed
-- upload deletes the blocks it carried.
--
-- Never read or stored: names (player, realm, guild, party, units), chat text (the kill XP line is
-- parsed for its number only), gold, map position, health and mana values (secret in Forever anyway).
--
-- APIs, checked in Forever's Blizzard_APIDocumentationGenerated: PLAYER_REGEN_DISABLED/ENABLED,
-- UNIT_DIED and PARTY_KILL (GUIDs; COMBAT_LOG_EVENT_UNFILTERED is a restricted callback event on this
-- client), CHAT_MSG_COMBAT_XP_GAIN, UNIT_SPELLCAST_SUCCEEDED (spellID secret when cast-restricted),
-- PLAYER_LEVEL_UP, UNIT_AURA + C_UnitAuras.GetAuraDataByIndex, PLAYER_DEAD/ALIVE/UNGHOST,
-- PLAYER_FLAGS_CHANGED + UnitIsAFK, NAME_PLATE_UNIT_ADDED/REMOVED, UnitThreatSituation, UnitCanAttack,
-- UnitGUID/UnitLevel/UnitCreatureType/UnitPowerType (identity secret when restricted), UnitXP,
-- UnitXPMax, GetXPExhaustion, IsPlayerMoving, UnitCastingInfo/UnitChannelInfo, and the sheet
-- (UnitStat, UnitHealthMax, UnitPowerMax, UnitArmor, UnitAttackPower, UnitRangedAttackPower,
-- GetSpellBonusDamage/Healing, Get*CritChance, GetHitModifier, GetSpellHitModifier, GetDodge/Parry/
-- BlockChance, GetManaRegen, UnitDamage, UnitAttackSpeed, UnitRangedDamage: secret while unit stats
-- are restricted, so the sheet is read out of combat only). Every value goes through `ok()`: a secret
-- or failed read is unknown, never an error.
local ADDON, ns = ...
local Record = {}
ns.Record = Record

local floor, format, type, pairs, ipairs, pcall, tonumber = math.floor, string.format, type, pairs, ipairs, pcall, tonumber

Record.BLOCK_SECONDS = 3600       -- active seconds per block
Record.CAP_SECONDS = 20 * 3600    -- active seconds kept per character
Record.IDLE_SECONDS = 120         -- no activity this long = a pause (left out of active play)
Record.CLOSE_SECONDS = 2          -- kills and XP lines this long after combat ends still belong to the pull
Record.OPENER_SECONDS = 3         -- casts this long before combat starts count for the pull
Record.LOGIN_DELAY = 5            -- the sheet at login waits this long (talents load late)
Record.LEVEL_DELAY = 3            -- and after a level up
Record.KEEP_SESSION = 600         -- a /reload within this long continues the session
local XP_WINDOW = 2               -- an XP line within this long of a death is that kill's
local SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }

-- A readable value (not a secret), else nil.
local function ok(v)
	if v == nil then return nil end
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end
local function num(v) v = ok(v) return type(v) == "number" and v or nil end
local function str(v) v = ok(v) return type(v) == "string" and v ~= "" and v or nil end
-- fn(...) -> its returns, each readable or nil; a missing function or an error -> nothing
local function call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local r = { pcall(fn, ...) }
	if not r[1] then return nil end
	for i = 2, 10 do r[i] = ok(r[i]) end
	return r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9], r[10]
end
local function round(v, d)
	if type(v) ~= "number" then return nil end
	local m = 10 ^ (d or 0)
	return floor(v * m + 0.5) / m
end
Record.Round = round
local function now() return GetTime() end

-- State ---------------------------------------------------------------------------------------------
local sess          -- { start = GetTime at the session's start, n = session number }
local lastAct       -- GetTime of the last activity
local afkAt         -- GetTime the AFK flag went on, nil when off
local pull          -- the pull in progress
local closing       -- the pull that just ended (still takes kills/XP for CLOSE_SECONDS)
local lastPullEnd   -- session time of the last pull's end
local meal          -- { t, k, a, at } while a Food/Drink aura is up
local ateSince = false -- a meal since the last pull
local death         -- the last death record (waits for alive and the next pull)
local deadAt        -- GetTime of the death
local casts = {}    -- recent casts out of combat: { id, at }, newest last (for the opener)
local plates = {}   -- nameplate tokens shown, in order
local candidate     -- a death no pull claimed yet: { npc, lvl, at } (an XP line may confirm it)
local xpLine        -- { xp, at } an XP line no kill took yet
local charDue       -- GetTime a sheet snapshot is due, nil when none
local loginAt       -- GetTime of the login (the opt-in question waits a little)

function Record.On() return ns.Options.Get("record") == true end

local function data()
	local c = ns.char
	if not c then return nil end
	if type(c.rec) ~= "table" then c.rec = {} end
	local r = c.rec
	r.v = 1
	if type(r.blocks) ~= "table" then r.blocks = {} end
	if type(r.next) ~= "number" then r.next = 1 end
	if type(r.since) ~= "number" then r.since = 0 end
	if type(r.askAt) ~= "number" then r.askAt = Record.ASK_SECONDS end
	-- 0.6-0.7.5 asked every 4 h: a saved wait at that old default moves to the current one
	if r.askAt == Record.OLD_ASK_SECONDS then r.askAt = Record.ASK_SECONDS end
	if type(r.sessions) ~= "number" then r.sessions = 0 end
	return r
end
Record.Data = data
Record.ASK_SECONDS = 2 * 3600
Record.OLD_ASK_SECONDS = 4 * 3600

-- seconds into the session (tenths)
local function rel(t) return round((t or now()) - (sess and sess.start or 0), 1) end
Record.Rel = rel

local function totalActive(r)
	local t = 0
	for _, b in ipairs(r.blocks) do t = t + (b.a or 0) end
	return t
end

-- Drop the oldest blocks while more than CAP_SECONDS of active play is kept (never the newest).
local function cap(r)
	local total = totalActive(r)
	while total > Record.CAP_SECONDS and #r.blocks > 1 do
		total = total - (r.blocks[1].a or 0)
		table.remove(r.blocks, 1)
	end
end

-- The block records go into now: the newest when it is this session's, not full and not cut by an
-- export; else a new one.
local function block()
	local r = data()
	if not (r and sess) then return nil end
	local b = r.blocks[#r.blocks]
	if b and b.s == sess.n and not r.cut and (b.a or 0) < Record.BLOCK_SECONDS then return b end
	r.cut = nil
	b = { id = r.next, s = sess.n, t0 = rel(), a = 0, p = {}, c = {}, m = {}, d = {}, x = {}, k = {} }
	r.next = r.next + 1
	r.blocks[#r.blocks + 1] = b
	cap(r)
	return b
end
Record.Block = block

local function add(kind, rec)
	if not Record.On() then return nil end
	local b = block()
	if not b then return nil end
	b[kind][#b[kind] + 1] = rec
	return rec
end

function Record.ActiveSeconds()
	local r = data()
	return r and totalActive(r) or 0
end

-- Active play ----------------------------------------------------------------------------------------
local function credit(d)
	if d <= 0 or not Record.On() then return end
	local b = block()
	if not b then return end
	b.a = round(b.a + d, 1)
	local r = data()
	r.since = round(r.since + d, 1)
	if b.a >= Record.BLOCK_SECONDS then r.cut = true end
end

local function pause(from, to)
	if to - from > Record.IDLE_SECONDS then add("k", { s = rel(from), e = rel(to) }) end
end

-- Something the player did (moving, casting, combat, looting...): the time since the last activity
-- counts as active play unless it was a pause.
local function activity()
	if not sess or afkAt then return end
	local t = now()
	if lastAct then
		local d = t - lastAct
		if d <= Record.IDLE_SECONDS then credit(d) else pause(lastAct, t) end
	end
	lastAct = t
end
Record.Activity = activity

local function onFlags(unit)
	if unit ~= "player" or not sess then return end
	local afk = call(UnitIsAFK, "player")
	if afk == nil then return end
	if afk and not afkAt then
		activity()
		afkAt = now()
	elseif not afk and afkAt then
		local from = afkAt
		afkAt = nil
		if Record.On() then add("k", { s = rel(from), e = rel(), afk = 1 }) end
		lastAct = now()
	end
end

-- Sessions -------------------------------------------------------------------------------------------
local function xpMark(why)
	local lvl = num(call(UnitLevel, "player"))
	add("x", { t = rel(), l = lvl, x = num(call(UnitXP, "player")), mx = num(call(UnitXPMax, "player")),
		r = num(call(GetXPExhaustion)) or 0, w = why })
end

local function startSession()
	local r = data()
	if not r then return end
	local t = now()
	local live = type(r.live) == "table" and r.live or nil
	if live and type(live.start) == "number" and type(live.seen) == "number" and t >= live.start
		and t - live.seen < Record.KEEP_SESSION and type(live.n) == "number" then
		sess = { start = live.start, n = live.n } -- a /reload: the same session
	else
		r.sessions = r.sessions + 1
		sess = { start = t, n = r.sessions }
		r.live = { start = t, n = sess.n, seen = t }
		if Record.On() then xpMark("s") end
	end
	lastAct = t
	charDue = t + Record.LOGIN_DELAY
end

-- The character sheet --------------------------------------------------------------------------------
local function schools(fn, d)
	local out = {}
	for s = 2, 7 do out[s] = round(num(call(fn, s)), d) end
	return out
end
local function power(fn)
	local base, pos, neg = call(fn, "player")
	if type(base) ~= "number" then return nil end
	return round(base + (num(pos) or 0) + (num(neg) or 0))
end
-- "slot:id:enchant:suffix" of a link (suffix: the bonus ids, else a classic suffix id)
function Record.ItemField(slot, link)
	local body = type(link) == "string" and link:match("item:([%-%d:]+)")
	if not body then return nil end
	local f = {}
	for v in (body .. ":"):gmatch("([^:]*):") do f[#f + 1] = tonumber(v) or 0 end
	local id = f[1]
	if not id or id <= 0 then return nil end
	local suffix = ""
	local nb = f[13] or 0
	if nb > 0 then
		local list = {}
		for i = 14, 13 + nb do if f[i] and f[i] ~= 0 then list[#list + 1] = format("%.0f", f[i]) end end
		suffix = table.concat(list, ",")
	elseif (f[7] or 0) ~= 0 then
		suffix = format("%.0f", f[7])
	end
	return format("%d:%.0f:%.0f:%s", slot, id, f[2] or 0, suffix)
end
local function items()
	local out = {}
	for _, slot in ipairs(SLOTS) do
		local v = Record.ItemField(slot, str(call(GetInventoryItemLink, "player", slot)))
		if v then out[#out + 1] = v end
	end
	return out
end
local function talents()
	local out = {}
	local CT, Tr = C_ClassTalents, C_Traits
	if not (CT and CT.GetActiveConfigID and Tr and Tr.GetConfigInfo and Tr.GetTreeNodes and Tr.GetNodeInfo) then return out end
	local cfg = num(call(CT.GetActiveConfigID))
	local info = cfg and call(Tr.GetConfigInfo, cfg)
	local tree = type(info) == "table" and type(info.treeIDs) == "table" and num(info.treeIDs[1])
	local ids = tree and call(Tr.GetTreeNodes, tree)
	for _, id in ipairs(type(ids) == "table" and ids or {}) do
		local n = call(Tr.GetNodeInfo, cfg, id)
		local rank = type(n) == "table" and (num(n.ranksPurchased) or 0) or 0
		if rank > 0 and num(n.ID) then out[#out + 1] = format("%.0f:%d", n.ID, rank) end
		if #out >= 100 then break end
	end
	return out
end
local function specKey()
	local C = ns.Context
	if not (C and C.Get) then return nil end
	local okc, ctx = pcall(C.Get)
	return okc and type(ctx) == "table" and type(ctx.spec) == "string" and ctx.spec or nil
end

function Record.Snapshot()
	local _, cls = call(UnitClass, "player")
	local _, race = call(UnitRace, "player")
	local c = { t = rel(), l = num(call(UnitLevel, "player")), cls = str(cls), race = str(race), spec = specKey() }
	c.st = {}
	for i = 1, 5 do
		local base, eff = call(UnitStat, "player", i)
		c.st[i] = { round(num(base)) or 0, round(num(eff)) or 0 }
	end
	c.hp = round(num(call(UnitHealthMax, "player")))
	c.mp = round(num(call(UnitPowerMax, "player", 0)))
	local base, eff = call(UnitArmor, "player")
	c.ar = round(num(eff) or num(base))
	c.ap, c.rap = power(UnitAttackPower), power(UnitRangedAttackPower)
	c.sp = schools(GetSpellBonusDamage, 0)
	c.heal = round(num(call(GetSpellBonusHealing)))
	c.cr, c.rcr = round(num(call(GetCritChance)), 2), round(num(call(GetRangedCritChance)), 2)
	c.scr = schools(GetSpellCritChance, 2)
	c.hit, c.shit = round(num(call(GetHitModifier)), 2), round(num(call(GetSpellHitModifier)), 2)
	c.dg, c.pr, c.bl = round(num(call(GetDodgeChance)), 2), round(num(call(GetParryChance)), 2), round(num(call(GetBlockChance)), 2)
	local mr, mrc = call(GetManaRegen)
	c.mr = { round(num(mr), 2) or 0, round(num(mrc), 2) or 0 }
	local mn, mx, on, ox = call(UnitDamage, "player")
	local ms, os = call(UnitAttackSpeed, "player")
	local rs, rn, rx = call(UnitRangedDamage, "player")
	local hasOff = (num(os) or 0) > 0
	local hasRanged = (num(rs) or 0) > 0
	c.wp = { round(num(mn), 1) or 0, round(num(mx), 1) or 0, round(num(ms), 2) or 0,
		hasOff and round(num(on), 1) or 0, hasOff and round(num(ox), 1) or 0, hasOff and round(num(os), 2) or 0,
		hasRanged and round(num(rn), 1) or 0, hasRanged and round(num(rx), 1) or 0, hasRanged and round(num(rs), 2) or 0 }
	c.it = items()
	c.ta = talents()
	return c
end

local function inCombat()
	local v = call(UnitAffectingCombat, "player")
	return v == true or (InCombatLockdown and InCombatLockdown()) or pull ~= nil
end
Record.InCombat = inCombat

-- Mobs -----------------------------------------------------------------------------------------------
-- npc id of a creature GUID ("Creature-0-1465-0-2105-448-000043F59F" -> 448)
function Record.NpcId(guid)
	guid = str(guid)
	if not guid then return nil end
	local kind, id = guid:match("^(%a+)%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)")
	if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
	return tonumber(id)
end
local function mobInfo(token)
	local guid = str(call(UnitGUID, token))
	local npc = Record.NpcId(guid)
	if not npc then return nil, guid end
	local pt = num(call(UnitPowerType, token))
	return { npc, num(call(UnitLevel, token)) or 0, str(call(UnitCreatureType, token)) or "", pt == nil and -1 or (pt == 0 and 1 or 0) }, guid
end
-- A hostile unit fighting the player (on its threat list; else in combat at all).
local function engaged(token)
	if not call(UnitExists, token) then return false end
	if call(UnitCanAttack, "player", token) ~= true then return false end
	local threat = call(UnitThreatSituation, "player", token)
	if threat ~= nil then return true end
	return call(UnitAffectingCombat, token) == true
end
-- The pull in progress / closing: { rec = the stored record, guids = { guid -> info | true }, dead = { guid },
-- live = most engaged at once, secret = a read was secret, at = GetTime of the start (of the end once closing) }.
-- GUIDs stay in this state only, never in the record.
local function scan()
	local p = pull
	if not p then return end
	local live = 0
	local function look(token)
		if not engaged(token) then return end
		live = live + 1
		local info, guid = mobInfo(token)
		if guid and not p.guids[guid] then
			p.guids[guid] = info or true
			if info then p.rec.m[#p.rec.m + 1] = info else p.secret = true end
		elseif not guid then
			p.secret = true
		end
	end
	look("target")
	for _, token in ipairs(plates) do look(token) end
	if live > p.live then p.live = live end
	local n = 0
	for _ in pairs(p.guids) do n = n + 1 end
	p.rec.n = math.max(n, p.live)
end
Record.Scan = scan

-- Pulls ----------------------------------------------------------------------------------------------
local function finishClosing() closing = nil end

local function startPull()
	if not (Record.On() and sess) then return end
	finishClosing()
	local t = now()
	if meal then
		meal.rec.i = 1
		meal.rec.d = round(t - meal.at, 1)
		meal = nil
	end
	local lvl = num(call(UnitLevel, "player"))
	local rec = { s = rel(t), l = lvl, n = 0, m = {}, k = {}, c = {}, g = lastPullEnd and round(rel(t) - lastPullEnd, 1) or nil,
		f = ateSince and "a" or "" }
	ateSince = false
	for _, c in ipairs(casts) do
		if t - c.at <= Record.OPENER_SECONDS then rec.c[c.id] = (rec.c[c.id] or 0) + 1 end
	end
	casts = {}
	if death and death.nx == nil then death.nx = round(t - deadAt, 1) end
	pull = { rec = rec, guids = {}, dead = {}, live = 0, at = t }
	scan()
end

local function endPull()
	local p = pull
	if not p then return end
	scan()
	pull = nil
	local t = now()
	p.rec.e = rel(t)
	if p.secret then p.rec.f = p.rec.f .. "s" end
	lastPullEnd = p.rec.e
	add("p", p.rec)
	closing = p
	p.at = t
end

local function holder()
	if pull then return pull end
	if closing and now() - closing.at <= Record.CLOSE_SECONDS then return closing end
	return nil
end

local function onDied(guid, byPlayer)
	local p = holder()
	if not p then return end
	local kills = p.rec.k
	local g = str(guid)
	if not g then
		if byPlayer then kills[#kills + 1] = { 0, 0 } end
		return
	end
	local info = p.guids[g]
	if info or byPlayer then
		if p.dead[g] then return end
		p.dead[g] = true
		local k = { type(info) == "table" and info[1] or Record.NpcId(g) or 0, type(info) == "table" and info[2] or 0 }
		kills[#kills + 1] = k
		local x = xpLine
		if x and now() - x.at <= XP_WINDOW then
			k[3] = x.xp
			xpLine = nil
		end
	else
		local npc = Record.NpcId(g)
		if npc then candidate = { npc, 0, at = now() } end
	end
end

-- The kill XP line: its number only (the line names the mob: never kept).
local xpPatterns
function Record.ParseXP(text)
	text = str(text)
	if not text then return nil end
	if not xpPatterns then
		xpPatterns = {}
		for _, name in ipairs({ "COMBATLOG_XPGAIN_EXHAUSTION1", "COMBATLOG_XPGAIN_EXHAUSTION2", "COMBATLOG_XPGAIN_EXHAUSTION1_GROUP",
			"COMBATLOG_XPGAIN_EXHAUSTION2_GROUP", "COMBATLOG_XPGAIN_FIRSTPERSON_GROUP", "COMBATLOG_XPGAIN_FIRSTPERSON" }) do
			local f = _G[name]
			if type(f) == "string" then
				local pat = f:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
				-- the first number argument after the first string is the XP
				pat = pat:gsub("%%%%%d%$s", "(.-)"):gsub("%%%%%d%$d", "(%%d+)"):gsub("%%%%s", "(.-)"):gsub("%%%%d", "(%%d+)")
				xpPatterns[#xpPatterns + 1] = "^" .. pat .. "$"
			end
		end
		xpPatterns[#xpPatterns + 1] = "dies, you gain (%d+) experience"
	end
	for _, pat in ipairs(xpPatterns) do
		local caps = { text:match(pat) }
		if caps[1] then
			for _, v in ipairs(caps) do
				local n = tonumber(v)
				if n then return n end
			end
		end
	end
	return nil
end

local function onXP(text)
	local xp = Record.ParseXP(text)
	if not xp then return end
	local p = holder()
	if not p then return end
	local t = now()
	local kills = p.rec.k
	for i = #kills, 1, -1 do
		if kills[i][3] == nil then
			kills[i][3] = xp
			return
		end
	end
	local c = candidate
	if c and t - c.at <= XP_WINDOW then
		candidate = nil
		kills[#kills + 1] = { c[1], c[2], xp }
		return
	end
	xpLine = { xp = xp, at = t }
end

local function onCast(unit, _, spell)
	if unit ~= "player" then return end
	activity()
	if not Record.On() then return end
	spell = num(spell)
	if not spell then return end
	if pull then
		pull.rec.c[spell] = (pull.rec.c[spell] or 0) + 1
	else
		casts[#casts + 1] = { id = spell, at = now() }
		if #casts > 8 then table.remove(casts, 1) end
	end
end

-- Meals ----------------------------------------------------------------------------------------------
local foodName, drinkName
local function mealKind(name)
	if not name then return nil end
	if foodName == nil then
		foodName = str(call(C_Spell and C_Spell.GetSpellName, 433)) or false
		drinkName = str(call(C_Spell and C_Spell.GetSpellName, 430)) or false
	end
	local f = foodName and name:find(foodName, 1, true)
	local d = drinkName and name:find(drinkName, 1, true)
	if f and d then return "b" end
	if name == foodName then return "f" end
	if name == drinkName then return "d" end
	return nil
end
local function onAura(unit)
	if unit ~= "player" or not Record.On() or not sess or pull then return end
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
	local kind, dur
	for i = 1, 40 do
		local a = call(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
		if type(a) ~= "table" then break end
		local k = mealKind(str(a.name))
		if k then
			kind = (kind and kind ~= k) and "b" or k
			dur = math.max(dur or 0, num(a.duration) or 0)
		end
	end
	if kind and not meal then
		local t = now()
		meal = { at = t, rec = add("m", { t = rel(t), k = kind, a = round(dur, 1), d = 0 }) }
		ateSince = true
		if not meal.rec then meal = nil end
	elseif kind and meal then
		if meal.rec.k ~= kind then meal.rec.k = "b" end
	elseif not kind and meal then
		meal.rec.d = round(now() - meal.at, 1)
		meal = nil
	end
end

-- Deaths ---------------------------------------------------------------------------------------------
local function onDead()
	if not (Record.On() and sess) then return end
	local t = now()
	local p = pull
	local d = { t = rel(t), l = num(call(UnitLevel, "player")), n = 0, ml = {}, f = 0 }
	if p then
		scan()
		d.n = p.rec.n
		for _, m in ipairs(p.rec.m) do d.ml[#d.ml + 1] = m[2] end
		d.f = round(t - p.at, 1)
		if not p.rec.f:find("d", 1, true) then p.rec.f = p.rec.f .. "d" end
	end
	death, deadAt = add("d", d), t
end
local function onAlive()
	if death and deadAt then death.r = round(now() - deadAt, 1) end
end

-- Snapshots and the clock ----------------------------------------------------------------------------
local function writeSheet()
	charDue = nil
	if Record.On() then add("c", Record.Snapshot()) end
end

-- Every few seconds (OnUpdate) and from tests: activity while moving, casting or fighting; the sheet
-- when due and out of combat; the mobs of the pull in progress; the cap; the UI's questions.
function Record.Tick()
	if not sess then return end
	local t = now()
	if pull then scan() end
	if pull or call(IsPlayerMoving) == true or call(UnitCastingInfo, "player") or call(UnitChannelInfo, "player") then
		activity()
	end
	if closing and t - closing.at > Record.CLOSE_SECONDS then finishClosing() end
	if charDue and t >= charDue and not inCombat() then writeSheet() end
	local r = data()
	if r then
		r.live = r.live or {}
		r.live.seen, r.live.start, r.live.n = t, sess.start, sess.n
		if Record.On() then cap(r) end
	end
	if ns.RecordUI and ns.RecordUI.Check then ns.RecordUI.Check() end
end

function Record.LoginAt() return loginAt end
function Record.SessionOn() return sess ~= nil end

-- Events ---------------------------------------------------------------------------------------------
ns.RegisterEvent("PLAYER_LOGIN", function() loginAt = now() end)
ns.RegisterEvent("PLAYER_ENTERING_WORLD", function(isLogin, isReload)
	if sess and not (isLogin or isReload) then return end
	loginAt = loginAt or now()
	startSession()
end)
ns.RegisterEvent("PLAYER_LOGOUT", function()
	if not sess then return end
	if pull then endPull() end
	finishClosing()
	if meal then
		meal.rec.d = round(now() - meal.at, 1)
		meal = nil
	end
	if lastAct and not afkAt then pause(lastAct, now()) end
	if Record.On() then xpMark("e") end
	local r = data()
	if r then r.live = nil end
end)
ns.RegisterEvent("PLAYER_REGEN_DISABLED", function() activity() startPull() end)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
	activity()
	endPull()
	if charDue and Record.On() and charDue <= now() then charDue = now() + 1 end
end)
ns.RegisterEvent("UNIT_DIED", function(guid) onDied(guid, false) end)
ns.RegisterEvent("PARTY_KILL", function(attacker, target)
	local a = str(attacker)
	local me, pet = str(call(UnitGUID, "player")), str(call(UnitGUID, "pet"))
	onDied(target, a ~= nil and (a == me or a == pet))
end)
ns.RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN", function(text) activity() onXP(text) end)
ns.RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", onCast)
ns.RegisterEvent("PLAYER_LEVEL_UP", function()
	if not sess then return end
	if Record.On() then xpMark("l") end
	charDue = now() + Record.LEVEL_DELAY
end)
ns.RegisterEvent("UNIT_AURA", onAura)
ns.RegisterEvent("PLAYER_DEAD", onDead)
ns.RegisterEvent("PLAYER_ALIVE", onAlive)
ns.RegisterEvent("PLAYER_UNGHOST", onAlive)
ns.RegisterEvent("PLAYER_FLAGS_CHANGED", onFlags)
ns.RegisterEvent("NAME_PLATE_UNIT_ADDED", function(token)
	token = str(token)
	if not token then return end
	for _, t in ipairs(plates) do if t == token then return end end
	plates[#plates + 1] = token
end)
ns.RegisterEvent("NAME_PLATE_UNIT_REMOVED", function(token)
	for i, t in ipairs(plates) do if t == token then table.remove(plates, i) return end end
end)
for _, e in ipairs({ "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING", "PLAYER_TARGET_CHANGED", "LOOT_OPENED", "QUEST_ACCEPTED",
	"QUEST_TURNED_IN", "MERCHANT_SHOW", "GOSSIP_SHOW", "BAG_UPDATE_DELAYED", "QUEST_DETAIL" }) do
	ns.RegisterEvent(e, activity)
end

-- The clock: every 5 s, every 0.5 s in a pull (the mobs engaged).
do
	local f = CreateFrame("Frame")
	local acc = 0
	f:SetScript("OnUpdate", function(_, elapsed)
		acc = acc + (elapsed or 0)
		if acc < (pull and 0.5 or 5) then return end
		acc = 0
		local okt, err = pcall(Record.Tick)
		if not okt then ns.ReportOnce("record:tick", err) end
	end)
end

-- For the settings tab and /psg record
function Record.Status()
	local r = data()
	local h = r and totalActive(r) / 3600 or 0
	return format("%.1f h of active play recorded", h), h
end
