-- The leveling recorder (opt-in, off until the player says yes): what PoleSim's model needs to check
-- itself against real play, kept per character in PoleSimGearCharDB.rec, nothing named.
--
--   c  character sheet at login and at every level up (stats, pools, armor, power, crit/hit, avoidance,
--      the client's mana regen out of combat and while casting, weapons, worn item ids, talents)
--   p  a pull: start/end (seconds into the session), its level, the mobs engaged (npc id from the GUID,
--      level, creature type, caster = has mana), kills with the XP each paid (a kill XP line with no
--      readable death is still a kill: npc 0 when Forever keeps the mob's identity secret), the player's casts per
--      spell id, the gap since the previous pull's end, flags (a after a meal, d died, s some reads secret)
--   m  a meal: Food/Drink aura start, seconds, the aura's duration, kind, interrupted by a pull
--   d  a death: level, mobs and their levels, the fight so far, dead -> alive, death -> next pull
--   x  XP and rested at the session's start, every level up (read a few seconds later: the client
--      still reports the old level while PLAYER_LEVEL_UP fires) and the session's end (the last
--      readable values: the client hands out 0 on logout)
--   k  a pause over 2 minutes (AFK flag, or no combat, movement, casting or other input)
--   f  item data drift, at each sheet: a worn or bagged item whose shipped stats differ from the
--      client's (item id, suffix id, stat key, shipped and live value), once per item + suffix + stat
--   g  a group fight in a dungeon (0.7.14; only in a party inside a dungeon instance): pull number,
--      instance + difficulty ids, mobs (npc id, level, elite/boss), the party's classes + levels by
--      role (self/tank/other), the player's healing per spell and target role (overheal when the
--      client gives it), damage taken per role (melee/spell, by mob npc id + spell id, biggest hit),
--      deaths per role, the player's mana every second (when readable), the healing sheet at the
--      start, drinking time since the last fight ("Group fights in dungeons" below)
-- Records sit in blocks of at most an hour of ACTIVE play (pauses left out); about 20 h are kept per
-- character (oldest blocks dropped first). Export (RecordExport.lua) summarises them; a confirmed
-- upload deletes the blocks it carried.
--
-- Never stored: names (player, realm, guild, party, units; party names and GUIDs are compared in
-- memory only to sort the party into roles), chat text (the kill XP line is parsed for its number
-- only), gold, map position, health values; mana only the player's own during dungeon group fights,
-- and only when the client lets addons read it (Forever keeps it secret so far).
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
-- are restricted, so the sheet is read out of combat only); for dungeon fights IsInInstance,
-- GetInstanceInfo, GetNumGroupMembers/IsInGroup, UnitGroupRolesAssigned, UnitClassification,
-- ENCOUNTER_START/END, UNIT_COMBAT (amount secret when restricted) and C_DamageMeter (secret in combat). Every value goes through `ok()`: a secret
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
local xpKill        -- { k = the kill record, at } a kill made from an XP line no death named yet
local xpDue         -- GetTime the level-up XP mark is due
local xpLast        -- the last readable { l, x, mx, r }
local charDue       -- GetTime a sheet snapshot is due, nil when none
local loginAt       -- GetTime of the login (the opt-in question waits a little)
-- the dungeon group fights ("Group fights in dungeons" below)
local groupCast, groupMealEnded, groupDied, groupPlayerDead, groupTick, groupCheck, startGroupFight

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
	-- the upload card's next ask, in active seconds since the last confirmed upload: the chosen interval
	-- (Settings, recEvery), or later after "Later"; askEvery = the interval it was set with, so a new
	-- choice applies at once (askAt = the last upload + the new interval), on every character
	local every = Record.AskSeconds()
	if type(r.askAt) ~= "number" then r.askAt, r.askEvery = every, every end
	if type(r.askEvery) ~= "number" then
		-- saved by 0.7.10 or older (2 h); 0.6-0.7.5 asked every 4 h: that old default moves too
		if r.askAt == Record.OLD_ASK_SECONDS then r.askAt = 2 * 3600 end
		r.askEvery = 2 * 3600
	end
	if r.askEvery ~= every then r.askAt, r.askEvery = every, every end
	if type(r.sessions) ~= "number" then r.sessions = 0 end
	return r
end
Record.Data = data
Record.ASK_HOURS = { 2, 4, 6 } -- Settings "Ask me to upload every" (Options recEvery, default 2)
Record.OLD_ASK_SECONDS = 4 * 3600
-- The chosen upload interval in active seconds.
function Record.AskSeconds()
	local h = ns.Options.Get("recEvery")
	for _, v in ipairs(Record.ASK_HOURS) do
		if h == v then return h * 3600 end
	end
	return Record.ASK_HOURS[1] * 3600
end

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
	b = { id = r.next, s = sess.n, t0 = rel(), a = 0, p = {}, c = {}, m = {}, d = {}, x = {}, k = {}, f = {}, g = {} }
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
	if type(b[kind]) ~= "table" then b[kind] = {} end -- a block saved before this kind existed
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
-- The XP state now, or the last readable one when the client hands out nothing (logout).
local function xpRead()
	local v = { l = num(call(UnitLevel, "player")), x = num(call(UnitXP, "player")), mx = num(call(UnitXPMax, "player")),
		r = num(call(GetXPExhaustion)) or 0 }
	if (v.mx or 0) > 0 and (v.l or 0) > 0 then
		xpLast = v
		return v
	end
	return xpLast or v
end
local function xpMark(why)
	local v = xpRead()
	add("x", { t = rel(), l = v.l, x = v.x, mx = v.mx, r = v.r, w = why })
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
	-- UnitStat: Forever's first return already holds gear AND buffs (= the second); the buff part
	-- (posBuff + negBuff) is kept apart so base + gear can be told from buffs
	c.st, c.bf = {}, {}
	for i = 1, 5 do
		local base, eff, pos, neg = call(UnitStat, "player", i)
		c.st[i] = { round(num(base)) or 0, round(num(eff)) or 0 }
		c.bf[i] = round((num(pos) or 0) + (num(neg) or 0)) or 0
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
	local hasTarget = call(UnitExists, "target") == true
	for _, token in ipairs(plates) do
		-- the target's own nameplate is the same mob
		if not (hasTarget and call(UnitIsUnit, token, "target") == true) then look(token) end
	end
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
		groupMealEnded(meal)
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
		local npc, lvl = type(info) == "table" and info[1] or Record.NpcId(g) or 0, type(info) == "table" and info[2] or 0
		local x = xpKill
		if x and now() - x.at <= XP_WINDOW and x.p == p then
			-- its XP line came first: name that kill
			xpKill = nil
			x.k[1], x.k[2] = npc, lvl
			return
		end
		kills[#kills + 1] = { npc, lvl }
	else
		local npc = Record.NpcId(g)
		local x = xpKill
		if npc and x and now() - x.at <= XP_WINDOW and x.p == p and x.k[1] == 0 then
			xpKill = nil
			x.k[1] = npc
		elseif npc then
			candidate = { npc, 0, at = now() }
		end
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
	-- no death to give it to (not yet, or its GUID was secret): a kill of this pull all the same
	local k = { 0, 0, xp }
	kills[#kills + 1] = k
	xpKill = { k = k, at = t, p = p }
end

local function onCast(unit, _, spell)
	if unit ~= "player" then return end
	activity()
	if not Record.On() then return end
	spell = num(spell)
	if not spell then return end
	groupCast(spell)
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
		groupMealEnded(meal)
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
	groupPlayerDead()
end
local function onAlive()
	if death and deadAt then death.r = round(now() - deadAt, 1) end
end

-- Item data drift ------------------------------------------------------------------------------------
-- The random suffix of a link for a drift row: the one the shipped table knows (Live.Bonus), else the
-- link's first bonus id, else its classic suffix field; 0 = none.
local function driftSuffix(link, rec)
	local b = ns.Live and ns.Live.Bonus and ns.Live.Bonus(link, rec)
	if b then return b end
	local body = link:match("item:([%-%d:]+)")
	if not body then return 0 end
	local f = {}
	for v in (body .. ":"):gmatch("([^:]*):") do f[#f + 1] = tonumber(v) or 0 end
	for i = 14, 13 + (f[13] or 0) do
		if (f[i] or 0) > 0 then return f[i] end
	end
	return (f[7] or 0) > 0 and f[7] or 0
end

-- At each sheet snapshot: the worn and bagged items compared like /psg drift (Drift.Diff: shipped
-- stats vs the client's); only mismatches are recorded (kind f: item id, suffix, stat key, shipped,
-- live), once per item + suffix + stat per character (rec.drift remembers the live value; a changed
-- value is recorded again). Items the client has not loaded are requested and wait for the next
-- snapshot. At most DRIFT_MAX rows are held; the rest stay unseen until an upload makes room.
function Record.DriftScan()
	local D = ns.Drift
	local r = data()
	if not (r and D and D.Diff and D.Links and Record.On()) then return end
	if type(r.drift) ~= "table" then r.drift = {} end
	local seen, held = r.drift, 0
	for _, b in ipairs(r.blocks) do held = held + (type(b.f) == "table" and #b.f or 0) end
	for _, link in ipairs(D.Links()) do
		local okd, d = pcall(D.Diff, link)
		local id = tonumber(link:match("item:(%d+)"))
		if okd and d == "pending" then
			if id and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
		elseif okd and type(d) == "table" and id then
			local sx = driftSuffix(link, ns.Items.Get(id))
			for _, e in ipairs(d) do
				local key = format("%.0f:%.0f:%s", id, sx, e[1])
				local live = round(e[3], 2)
				if seen[key] ~= live then
					if held >= Record.DRIFT_MAX then return end
					if add("f", { t = rel(), i = id, sx = sx, k = e[1], s = round(e[2], 2), v = live }) then
						seen[key], held = live, held + 1
					end
				end
			end
		end
	end
end
Record.DRIFT_MAX = 50

-- Group fights in dungeons (0.7.14) ------------------------------------------------------------------
-- Kind g, one record per fight of the GROUP, only while recording is on AND the player is in a party
-- inside a dungeon (IsInInstance "party", 2+ group members): for PoleSim's dungeon-healing model.
--   t start (session s), d seconds, i instance id, df difficulty id, n pull number in this dungeon visit,
--   e encounter id (ENCOUNTER_START, 0 none) + es success (1/0, -1 open), b a boss fought,
--   m mobs { npc, level, class code } (n normal, e elite, r rare, re rare elite, b boss, t trivial, x minus),
--   p party "role:CLASS:level" (role s self, t tank, o other), rs where the tank came from (a assigned
--     role, d most melee damage taken this fight, c carried over from an earlier fight, "" none),
--   h the player's heals per spell { spell, amount, overheal (-1 unknown), to self, to tank, to others,
--     to nobody known }, ht their total, ab absorbs { spell, amount },
--   dt damage taken per role { total, melee, spell, biggest hit (-1 unknown), hits seen },
--   ds damage taken by source { role, npc (0 unknown), spell, amount }, the biggest GROUP_SOURCES,
--   x deaths per role { s, t, o }, mp the player's mana { start, end, max, samples every second }
--   (empty when the client keeps mana secret: flag p), st the sheet at the start { +healing, spirit,
--   intellect, mana regen/s out of combat, while casting, max mana }, dk drinking seconds since the
--   last fight, g seconds since it, c casts { spell = count }, ct { seconds into the fight, spell },
--   ms the damage meter's own length of the session, f flags (M no meter data, S meter values secret,
--   p mana secret, u hit amounts secret, g mob identity secret, c a party member matched by class only,
--   x ended by leaving the dungeon).
-- Where the numbers come from: Forever's combat log is a restricted event (no addon reads it), so the
-- heal and damage totals come from the client's own damage meter (C_DamageMeter, read once the fight
-- is over: its values are secret in combat), the biggest hit from UNIT_COMBAT (when its amount is not
-- secret), deaths from UNIT_DIED / PLAYER_DEAD and the meter. Party members are told apart by GUID,
-- name or class IN MEMORY ONLY to sort them into roles; no name or GUID is ever stored.
-- Cost: outside a dungeon group nothing is registered but a few roster/zone events; UNIT_COMBAT and the
-- encounter events are registered only while the gate is open.
Record.GROUP_MAX = 200        -- fights held for one export (more wait for an upload)
Record.GROUP_MOBS = 30        -- mobs per fight
Record.GROUP_SPELLS = 24      -- heal / absorb spells per fight
Record.GROUP_SOURCES = 30     -- damage-taken rows per fight
Record.GROUP_CASTS = 300      -- cast times per fight
Record.GROUP_SAMPLES = 900    -- mana samples per fight (15 min)
Record.GROUP_QUIET = 2        -- nobody in combat this long ends the fight
Record.METER_DELAY = 1.5      -- the meter is read again this long after the fight
Record.MELEE_SPELLS = { [1] = true, [6603] = true } -- how the meter names an auto attack
local PARTY = { "party1", "party2", "party3", "party4" }
local CLASSIFY = { normal = "n", elite = "e", rare = "r", rareelite = "re", worldboss = "b", trivial = "t", minus = "x" }
local GROUP_EVENTS = { "UNIT_COMBAT", "ENCOUNTER_START", "ENCOUNTER_END" }

local grp = { on = false, n = 0, drink = 0, tank = nil, enc = nil, inst = nil, statsAt = nil, stats = nil,
	meterSeen = 0, full = false, registered = {} }
local gf      -- the group fight in progress: { rec, at, quiet, sampleAt, guids, names, uc, deaths, tokens }
local gclose  -- the fight that ended, waiting for the meter: { rec, ctx, readAt }
local gframe  -- UNIT_COMBAT / ENCOUNTER_* while the gate is open

local function groupHeld()
	local r = data()
	local n = 0
	for _, b in ipairs(r and r.blocks or {}) do n = n + (type(b.g) == "table" and #b.g or 0) end
	return n
end
Record.GroupHeld = groupHeld

-- Recording on, in a dungeon instance, in a group of 2+.
local function groupGate()
	if not (Record.On() and sess) then return false, "recording off" end
	local inside, kind = call(IsInInstance)
	if not inside or kind ~= "party" then return false, "not in a dungeon" end
	local n = num(call(GetNumGroupMembers)) or 0
	if n < 2 and call(IsInGroup) ~= true then return false, "not in a group" end
	return true
end
Record.GroupGate = groupGate

-- player + party1-4: { token, cls, lvl, role (assigned), key } with key = GUID, else name, else the token
-- (kept in memory for this fight only)
local function roster()
	local out = {}
	for _, token in ipairs({ "player", PARTY[1], PARTY[2], PARTY[3], PARTY[4] }) do
		if token == "player" or call(UnitExists, token) == true then
			local _, cls = call(UnitClass, token)
			local guid = str(call(UnitGUID, token))
			local name = str(call(UnitName, token))
			out[#out + 1] = { token = token, cls = str(cls) or "", lvl = num(call(UnitLevel, token)) or 0,
				role = str(call(UnitGroupRolesAssigned, token)), guid = guid, name = name, key = guid or name or token }
		end
	end
	return out
end

local function inCombatAny(members)
	if inCombat() then return true end
	for _, m in ipairs(members) do
		if m.token ~= "player" and call(UnitAffectingCombat, m.token) == true then return true end
	end
	return false
end

local function readStats()
	local _, spi = call(UnitStat, "player", 5)
	local _, int = call(UnitStat, "player", 4)
	local mr, mrc = call(GetManaRegen)
	return { round(num(call(GetSpellBonusHealing))) or 0, round(num(spi)) or 0, round(num(int)) or 0,
		round(num(mr), 2) or 0, round(num(mrc), 2) or 0, round(num(call(UnitPowerMax, "player", 0))) or 0 }
end

local function setRegistered(on)
	if not gframe then
		gframe = CreateFrame("Frame")
		gframe:SetScript("OnEvent", function(_, event, ...)
			local okh, err = pcall(Record.GroupEvent, event, ...)
			if not okh then ns.ReportOnce("record:group", err) end
		end)
		Record._gframe = gframe
	end
	for _, e in ipairs(GROUP_EVENTS) do
		if on and not grp.registered[e] then
			pcall(gframe.RegisterEvent, gframe, e)
			grp.registered[e] = true
		elseif not on and grp.registered[e] then
			pcall(gframe.UnregisterEvent, gframe, e)
			grp.registered[e] = nil
		end
	end
end
function Record.GroupRegistered() return grp.registered end

local endGroupFight, finishMeter

-- The gate opened or closed (zone, roster, the recording option): register or drop the fight events;
-- a new dungeon visit starts the pull count again.
groupCheck = function()
	local on = groupGate() == true
	if on and not grp.on then
		local _, _, diff, _, _, _, _, inst = call(GetInstanceInfo)
		inst, diff = num(inst) or 0, num(diff) or 0
		if grp.inst ~= inst then
			grp.n, grp.drink, grp.tank, grp.lastEnd, grp.enc = 0, 0, nil, nil, nil
		end
		grp.inst, grp.diff = inst, diff
		-- meter sessions from before the gate opened are never a fight of ours
		local DM = C_DamageMeter
		local list = DM and DM.GetAvailableCombatSessions and call(DM.GetAvailableCombatSessions)
		for _, s in ipairs(type(list) == "table" and list or {}) do
			local sid = type(s) == "table" and num(s.sessionID)
			if sid and sid > grp.meterSeen then grp.meterSeen = sid end
		end
	elseif not on and grp.on then
		if gf then endGroupFight("x") end
		if gclose then finishMeter() end
	end
	grp.on = on
	setRegistered(on)
	return on
end

-- Mobs fighting the group: the target, focus, boss frames, party targets and nameplates in combat.
local function groupScan()
	local f = gf
	if not f then return end
	local function look(token)
		if #f.rec.m >= Record.GROUP_MOBS then return end
		if call(UnitExists, token) ~= true or call(UnitCanAttack, "player", token) ~= true then return end
		if call(UnitAffectingCombat, token) ~= true and not token:match("^boss") then return end
		local guid = str(call(UnitGUID, token))
		local npc = Record.NpcId(guid)
		if not npc then
			f.rec.f = f.rec.f:find("g", 1, true) and f.rec.f or (f.rec.f .. "g")
			return
		end
		if f.guids[guid] then return end
		f.guids[guid] = true
		local lvl = num(call(UnitLevel, token)) or 0
		local cls = CLASSIFY[str(call(UnitClassification, token)) or ""] or ""
		if token:match("^boss") or lvl < 0 then cls = "b" end
		if cls == "b" then f.rec.b = 1 end
		f.rec.m[#f.rec.m + 1] = { npc, lvl, cls }
		local name = str(call(UnitName, token))
		if name then f.names[name] = npc end -- for the meter's damage sources; memory only
	end
	for _, token in ipairs({ "target", "focus", "boss1", "boss2", "boss3", "boss4", "boss5",
		"party1target", "party2target", "party3target", "party4target" }) do look(token) end
	for _, token in ipairs(plates) do look(token) end
end

local function sampleMana(f, t)
	f.sampleAt = t
	local v = num(call(UnitPower, "player", 0))
	if v then
		local c = f.rec.mp.c
		if #c < Record.GROUP_SAMPLES then c[#c + 1] = round(v) end
		if f.rec.mp.a == -1 then f.rec.mp.a = round(v) end
		f.rec.mp.z = round(v)
	elseif not f.rec.f:find("p", 1, true) then
		f.rec.f = f.rec.f .. "p"
	end
end

local function drinkKind(m) return m and m.rec and (m.rec.k == "d" or m.rec.k == "b") end

startGroupFight = function()
	if gf or not grp.on then return end
	if gclose then finishMeter() end
	local t = now()
	if grp.stats == nil or not inCombat() then grp.stats, grp.statsAt = readStats(), t end
	local dk = grp.drink
	if drinkKind(meal) then
		local part = t - meal.at - (meal.counted or 0)
		if part > 0 then dk, meal.counted = dk + part, (meal.counted or 0) + part end
	end
	grp.drink = 0
	grp.n = grp.n + 1
	local rec = { t = rel(t), d = 0, i = grp.inst or 0, df = grp.diff or 0, n = grp.n, e = grp.enc or 0, es = -1,
		b = 0, m = {}, p = {}, rs = "", h = {}, ht = 0, ab = {}, dt = {}, ds = {}, x = { s = 0, t = 0, o = 0 },
		mp = { a = -1, z = -1, mx = round(num(call(UnitPowerMax, "player", 0))) or 0, c = {} }, st = { unpack(grp.stats) },
		dk = round(dk, 1), g = grp.lastEnd and round(rel(t) - grp.lastEnd, 1) or -1, c = {}, ct = {}, ms = 0, f = "" }
	gf = { rec = rec, at = t, guids = {}, names = {}, uc = {}, deaths = {}, members = roster() }
	sampleMana(gf, t)
	groupScan()
end

-- The meter's view of the session that just ended (all values secret while the player is in combat).
local function meterTypes()
	local E = Enum and Enum.DamageMeterType or {}
	return E.HealingDone or 2, E.Absorbs or 4, E.DamageTaken or 7, E.Deaths or 9
end

-- A party member of the meter's source / detail entry: GUID, else name, else the only member of
-- that class (flag c); the local player by isLocalPlayer. -> member | nil
local function memberOf(ctx, guid, name, cls, isLocal)
	if isLocal == true then
		for _, m in ipairs(ctx.members) do if m.token == "player" then return m end end
	end
	guid, name, cls = str(guid), str(name), str(cls)
	local short = name and name:match("^([^%-]+)%-") -- "Name-Realm" (another realm): UnitName gives the name alone
	for _, m in ipairs(ctx.members) do
		if (guid and m.guid == guid) or (name and (m.name == name or m.name == short)) then return m end
	end
	if cls then
		local hit, count = nil, 0
		for _, m in ipairs(ctx.members) do if m.cls == cls then hit, count = m, count + 1 end end
		if count == 1 then
			ctx.byClass = true
			return hit
		end
	end
	return nil
end

local function details(d)
	if type(d) ~= "table" then return {} end
	if d.amount ~= nil or d.unitName ~= nil then return { d } end
	return d
end

local function roleOf(ctx, m)
	if not m then return nil end
	if m.token == "player" then return "s" end
	return m.key == ctx.tankKey and "t" or "o"
end

-- Decide the tank: an assigned TANK (not the player), else the member who took the most melee damage
-- (meter, else UNIT_COMBAT physical hits), else the tank of an earlier fight in this visit.
local function pickTank(ctx, taken)
	for _, m in ipairs(ctx.members) do
		if m.token ~= "player" and m.role == "TANK" then
			ctx.tankKey, ctx.rs = m.key, "a"
			grp.tank = m.key
			return
		end
	end
	local best, most = nil, 0
	for _, m in ipairs(ctx.members) do
		if m.token ~= "player" then
			local a = taken[m.key]
			local v = a and (a.melee > 0 and a.melee or a.total) or 0
			if v > most then best, most = m, v end
		end
	end
	if best then
		ctx.tankKey, ctx.rs = best.key, "d"
		grp.tank = best.key
		return
	end
	if grp.tank then
		for _, m in ipairs(ctx.members) do
			if m.key == grp.tank then
				ctx.tankKey, ctx.rs = m.key, "c"
				return
			end
		end
	end
	ctx.rs = ""
end

-- Fill the fight record from the meter (when readable) and the live counts; again after METER_DELAY.
local function fillRecord(rec, ctx)
	local DM = C_DamageMeter
	local HEAL, ABS, TAKEN, DEATHS = meterTypes()
	local id
	local secret = false
	if DM and DM.GetAvailableCombatSessions and DM.GetCombatSessionFromID and not inCombat() then
		local list = call(DM.GetAvailableCombatSessions)
		for _, s in ipairs(type(list) == "table" and list or {}) do
			local sid = type(s) == "table" and num(s.sessionID)
			if sid and sid > (ctx.meterBase or 0) and (not id or sid > id) then id, rec.ms = sid, round(num(s.durationSeconds), 1) or 0 end
		end
	end
	-- damage taken per member key: { total, melee, spell, rows = { [npc:spell] = amount } }
	local taken = {}
	local function acc(m)
		local a = taken[m.key]
		if not a then
			a = { total = 0, melee = 0, spell = 0, rows = {} }
			taken[m.key] = a
		end
		return a
	end
	local meterDeaths = {}
	local heal, absorb, healTotal = {}, {}, 0
	if id then
		local s = call(DM.GetCombatSessionFromID, id, TAKEN)
		for _, src in ipairs(type(s) == "table" and type(s.combatSources) == "table" and s.combatSources or {}) do
			local m = memberOf(ctx, src.sourceGUID, src.name, src.classFilename, ok(src.isLocalPlayer))
			local total = num(src.totalAmount)
			if src.totalAmount ~= nil and total == nil then secret = true end
			if m and total then
				local a = acc(m)
				a.total = a.total + total
				local guid = str(src.sourceGUID) or (m.token == "player" and str(call(UnitGUID, "player"))) or m.guid
				local detail = guid and call(DM.GetCombatSessionSourceFromID, id, TAKEN, guid)
				for _, sp in ipairs(type(detail) == "table" and type(detail.combatSpells) == "table" and detail.combatSpells or {}) do
					local spell, amount = num(sp.spellID) or 0, num(sp.totalAmount)
					if amount then
						if Record.MELEE_SPELLS[spell] then a.melee = a.melee + amount else a.spell = a.spell + amount end
						local npc = ctx.names[str(sp.creatureName) or ""] or 0
						local k = npc .. ":" .. spell
						a.rows[k] = (a.rows[k] or 0) + amount
					end
				end
			end
		end
		local d = call(DM.GetCombatSessionFromID, id, DEATHS)
		for _, src in ipairs(type(d) == "table" and type(d.combatSources) == "table" and d.combatSources or {}) do
			local m = memberOf(ctx, src.sourceGUID, src.name, src.classFilename, ok(src.isLocalPlayer))
			if m then meterDeaths[m.key] = (meterDeaths[m.key] or 0) + 1 end
		end
	end
	-- UNIT_COMBAT physical hits stand in for the melee split when the meter gave nothing
	local fromMeter = next(taken) ~= nil
	if not fromMeter then
		for _, m in ipairs(ctx.members) do
			local u = ctx.uc[m.token]
			if u and u.sum > 0 then
				local a = acc(m)
				a.total, a.melee, a.spell = u.sum, u.phys, u.sum - u.phys
			end
		end
	end
	pickTank(ctx, taken)
	-- heals: the player's source, per spell, split by target role
	if id then
		local s = call(DM.GetCombatSessionFromID, id, HEAL)
		local mine
		for _, src in ipairs(type(s) == "table" and type(s.combatSources) == "table" and s.combatSources or {}) do
			if ok(src.isLocalPlayer) == true then mine = src break end
		end
		if mine then
			healTotal = num(mine.totalAmount) or 0
			if mine.totalAmount ~= nil and num(mine.totalAmount) == nil then secret = true end
			local guid = str(mine.sourceGUID) or str(call(UnitGUID, "player"))
			local detail = guid and call(DM.GetCombatSessionSourceFromID, id, HEAL, guid)
			for _, sp in ipairs(type(detail) == "table" and type(detail.combatSpells) == "table" and detail.combatSpells or {}) do
				local spell, amount = num(sp.spellID), num(sp.totalAmount)
				if spell and amount and #heal < Record.GROUP_SPELLS then
					local row = { spell, round(amount), round(num(sp.overkillAmount)) or -1, 0, 0, 0, 0 }
					local placed = 0
					for _, dt in ipairs(details(sp.combatSpellDetails)) do
						local a = type(dt) == "table" and num(dt.amount)
						if a then
							local role = roleOf(ctx, memberOf(ctx, nil, dt.unitName, dt.unitClassFilename, nil))
							local col = role == "s" and 4 or role == "t" and 5 or role == "o" and 6 or 7
							row[col] = row[col] + round(a)
							placed = placed + a
						end
					end
					if placed < amount then row[7] = row[7] + round(amount - placed) end
					heal[#heal + 1] = row
				end
			end
		end
		local a = call(DM.GetCombatSessionFromID, id, ABS)
		for _, src in ipairs(type(a) == "table" and type(a.combatSources) == "table" and a.combatSources or {}) do
			if ok(src.isLocalPlayer) == true then
				local guid = str(src.sourceGUID) or str(call(UnitGUID, "player"))
				local detail = guid and call(DM.GetCombatSessionSourceFromID, id, ABS, guid)
				for _, sp in ipairs(type(detail) == "table" and type(detail.combatSpells) == "table" and detail.combatSpells or {}) do
					local spell, amount = num(sp.spellID), num(sp.totalAmount)
					if spell and amount and #absorb < Record.GROUP_SPELLS then absorb[#absorb + 1] = { spell, round(amount) } end
				end
			end
		end
	end
	-- per role
	local dt, rows, x = {}, {}, { s = 0, t = 0, o = 0 }
	for _, m in ipairs(ctx.members) do
		local role = roleOf(ctx, m)
		local a, u = taken[m.key], ctx.uc[m.token]
		if a or u then
			local r = dt[role] or { 0, 0, 0, -1, 0 }
			dt[role] = r
			if a then r[1], r[2], r[3] = r[1] + round(a.total), r[2] + round(a.melee), r[3] + round(a.spell) end
			if u then
				if u.max and u.max > r[4] then r[4] = round(u.max) end
				r[5] = r[5] + u.n
			end
			for k, v in pairs(a and a.rows or {}) do
				local npc, spell = k:match("^(%d+):(%d+)$")
				local rk = role .. ":" .. k
				rows[rk] = rows[rk] or { role, tonumber(npc), tonumber(spell), 0 }
				rows[rk][4] = rows[rk][4] + v
			end
		end
		local dead = math.max(ctx.deaths[m.token] or 0, meterDeaths[m.key] or 0)
		if dead > 0 then x[role] = x[role] + dead end
	end
	local ds = {}
	for _, r in pairs(rows) do r[4] = round(r[4]) ds[#ds + 1] = r end
	table.sort(ds, function(a, b) if a[4] ~= b[4] then return a[4] > b[4] end return a[1] .. a[2] .. ":" .. a[3] < b[1] .. b[2] .. ":" .. b[3] end)
	for i = #ds, Record.GROUP_SOURCES + 1, -1 do ds[i] = nil end
	-- the party with roles (class + level only)
	local p = {}
	for _, m in ipairs(ctx.members) do p[#p + 1] = roleOf(ctx, m) .. ":" .. (m.cls ~= "" and m.cls or "UNKNOWN") .. ":" .. m.lvl end
	rec.p, rec.rs, rec.dt, rec.ds, rec.x = p, ctx.rs or "", dt, ds, x
	if id then
		rec.h, rec.ht, rec.ab = heal, round(healTotal), absorb
		ctx.meterId = id
	end
	local flags = rec.f:gsub("[MSc]", "")
	if not id then flags = flags .. "M" elseif secret then flags = flags .. "S" end
	if ctx.byClass then flags = flags .. "c" end
	rec.f = flags
end

-- Gate closed / the meter read done: forget the fight's names and GUIDs.
finishMeter = function()
	local c = gclose
	gclose = nil
	if not c then return end
	local okf, err = pcall(fillRecord, c.rec, c.ctx)
	if not okf then ns.ReportOnce("record:meter", err) end
	if c.ctx.meterId and c.ctx.meterId > grp.meterSeen then grp.meterSeen = c.ctx.meterId end
end

endGroupFight = function(why)
	local f = gf
	if not f then return end
	gf = nil
	local t = f.quiet or now()
	local rec = f.rec
	rec.d = round(t - f.at, 1)
	sampleMana(f, now())
	if why == "x" then rec.f = rec.f .. "x" end
	grp.lastEnd = rel(t)
	local ctx = { members = f.members, names = f.names, uc = f.uc, deaths = f.deaths, meterBase = grp.meterSeen }
	local okf, err = pcall(fillRecord, rec, ctx)
	if not okf then ns.ReportOnce("record:meter", err) end
	if ctx.meterId and ctx.meterId > grp.meterSeen then grp.meterSeen = ctx.meterId end
	local held = groupHeld()
	if held < Record.GROUP_MAX then grp.full = false end
	if held >= Record.GROUP_MAX then
		if not grp.full then
			grp.full = true
			ns.Print(format("Dungeon recording is full (%d fights): upload with /psg export to record more.", Record.GROUP_MAX))
		end
		return
	end
	if add("g", rec) then gclose = { rec = rec, ctx = ctx, readAt = now() + Record.METER_DELAY } end
end

-- Every tick while the gate is open: fight start/end, mobs, mana each second, the sheet out of combat.
groupTick = function(t)
	if not grp.on then return end
	if not gf then
		local fighting = inCombat()
		for _, token in ipairs(PARTY) do
			if fighting then break end
			fighting = call(UnitAffectingCombat, token) == true
		end
		if fighting then
			startGroupFight()
		elseif not grp.statsAt or t - grp.statsAt >= 5 then
			grp.stats, grp.statsAt = readStats(), t
		end
	else
		if inCombatAny(gf.members) then
			gf.quiet = nil
		elseif not gf.quiet then
			gf.quiet = t
		end
		if gf and gf.quiet and t - gf.quiet >= Record.GROUP_QUIET then
			endGroupFight()
		else
			groupScan()
			if t - (gf.sampleAt or 0) >= 1 then sampleMana(gf, t) end
		end
	end
	if gclose and t >= gclose.readAt and not inCombat() then finishMeter() end
end

-- UNIT_COMBAT / ENCOUNTER_* (registered only while the gate is open).
function Record.GroupEvent(event, a1, a2, a3, a4, a5)
	if event == "UNIT_COMBAT" then
		local f = gf
		if not f or (a1 ~= "player" and not tostring(a1):match("^party%d$")) or a2 ~= "WOUND" then return end
		local u = f.uc[a1]
		if not u then
			u = { n = 0, sum = 0, phys = 0 }
			f.uc[a1] = u
		end
		u.n = u.n + 1
		local amount = num(a4)
		if not amount then
			if not f.rec.f:find("u", 1, true) then f.rec.f = f.rec.f .. "u" end
			return
		end
		u.sum = u.sum + amount
		if num(a5) == 1 then u.phys = u.phys + amount end
		if not u.max or amount > u.max then u.max = amount end
	elseif event == "ENCOUNTER_START" then
		grp.enc = num(a1)
		if gf then gf.rec.e, gf.rec.es = grp.enc or 0, -1 end
	elseif event == "ENCOUNTER_END" then
		local id, success = num(a1), num(a5)
		local rec = (gf and gf.rec) or (gclose and gclose.rec)
		if rec and id and (rec.e == id or rec.e == 0) then
			rec.e, rec.es = id, success == 1 and 1 or 0
			rec.b = 1
		end
		grp.enc = nil
	end
end

-- A party member died (UNIT_DIED with a readable GUID) or the player (PLAYER_DEAD).
groupDied = function(guid)
	local f = gf
	if not f then return end
	guid = str(guid)
	if not guid then return end
	for _, m in ipairs(f.members) do
		if m.guid == guid and m.token ~= "player" then f.deaths[m.token] = (f.deaths[m.token] or 0) + 1 return end
	end
end
groupPlayerDead = function()
	if gf then gf.deaths.player = (gf.deaths.player or 0) + 1 end
end
groupCast = function(spell)
	local f = gf
	if not f then return end
	f.rec.c[spell] = (f.rec.c[spell] or 0) + 1
	if #f.rec.ct < Record.GROUP_CASTS then f.rec.ct[#f.rec.ct + 1] = { round(now() - f.at, 1), spell } end
end
groupMealEnded = function(m)
	if not (grp.on and drinkKind(m)) then return end
	local d = (m.rec.d or 0) - (m.counted or 0)
	if d > 0 then grp.drink = grp.drink + d end
end

function Record.GroupOn() return grp.on end
function Record.GroupCheck() return groupCheck() end
-- Logout / tests: close the fight in progress and read the meter now.
function Record.GroupFlush()
	if gf then endGroupFight() end
	if gclose then finishMeter() end
end

-- For /psg group: the gate, what is held and what the last fight could read.
function Record.GroupStatus()
	local on, why = groupGate()
	local last
	local r = data()
	for _, b in ipairs(r and r.blocks or {}) do
		if type(b.g) == "table" and #b.g > 0 then last = b.g[#b.g] end
	end
	return on, why, groupHeld(), last
end

-- Snapshots and the clock ----------------------------------------------------------------------------
local function writeSheet()
	charDue = nil
	if Record.On() then
		add("c", Record.Snapshot())
		local okd, err = pcall(Record.DriftScan)
		if not okd then ns.ReportOnce("record:drift", err) end
	end
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
	if xpDue and t >= xpDue then
		xpDue = nil
		if Record.On() then xpMark("l") else xpRead() end
	elseif not xpDue then
		xpRead() -- keeps the last readable values for the logout mark
	end
	if charDue and t >= charDue and not inCombat() then writeSheet() end
	groupCheck()
	groupTick(t)
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
	Record.GroupFlush()
	if meal then
		meal.rec.d = round(now() - meal.at, 1)
		meal = nil
	end
	if lastAct and not afkAt then pause(lastAct, now()) end
	if xpDue and Record.On() then xpMark("l") end
	xpDue = nil
	if Record.On() then xpMark("e") end
	local r = data()
	if r then r.live = nil end
end)
ns.RegisterEvent("PLAYER_REGEN_DISABLED", function() activity() startPull() if groupCheck() then startGroupFight() end end)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
	activity()
	endPull()
	if charDue and Record.On() and charDue <= now() then charDue = now() + 1 end
end)
ns.RegisterEvent("UNIT_DIED", function(guid) onDied(guid, false) groupDied(guid) end)
-- the dungeon gate: zone and roster changes, the recording option
for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
	ns.RegisterEvent(e, function() if sess then groupCheck() end end)
end
ns.On("OPTIONS", function(k) if k == "record" and sess then groupCheck() end end)
ns.RegisterEvent("PARTY_KILL", function(attacker, target)
	local a = str(attacker)
	local me, pet = str(call(UnitGUID, "player")), str(call(UnitGUID, "pet"))
	onDied(target, a ~= nil and (a == me or a == pet))
end)
ns.RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN", function(text) activity() onXP(text) end)
ns.RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", onCast)
ns.RegisterEvent("PLAYER_LEVEL_UP", function()
	if not sess then return end
	xpDue = now() + Record.LEVEL_DELAY
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

-- The clock: every 5 s, every 0.5 s in a pull (the mobs engaged), every second in a dungeon group.
do
	local f = CreateFrame("Frame")
	local acc = 0
	f:SetScript("OnUpdate", function(_, elapsed)
		acc = acc + (elapsed or 0)
		if acc < (pull and 0.5 or Record.GroupOn() and 1 or 5) then return end
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
