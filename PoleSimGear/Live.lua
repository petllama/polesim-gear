-- The actual item from the client (tooltips, arrows, reward pick): C_Item.GetItemStats with our stat
-- keys, ratings to % (ns.DATA.rating: 10 hit, 14 crit ... rating per 1%; 2 decimals like a suffix),
-- random suffixes and any server-side change included. Equip bonuses the client may leave out are filled per family from
-- the shipped table, and the instance lists them (inst.filled) so the tooltip can say so. Enchants are
-- not read (the website ignores them too).
local ADDON, ns = ...
local Live = {}
ns.Live = Live

Live.EQUIP_LOC = { INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3, INVTYPE_CHEST = 5, INVTYPE_ROBE = 20,
	INVTYPE_WAIST = 6, INVTYPE_LEGS = 7, INVTYPE_FEET = 8, INVTYPE_WRIST = 9, INVTYPE_HAND = 10, INVTYPE_FINGER = 11,
	INVTYPE_TRINKET = 12, INVTYPE_WEAPON = 13, INVTYPE_SHIELD = 14, INVTYPE_RANGED = 15, INVTYPE_CLOAK = 16,
	INVTYPE_2HWEAPON = 17, INVTYPE_WEAPONMAINHAND = 21, INVTYPE_WEAPONOFFHAND = 22, INVTYPE_HOLDABLE = 23,
	INVTYPE_THROWN = 25, INVTYPE_RANGEDRIGHT = 26, INVTYPE_RELIC = 28 }

local PLAIN = {
	ITEM_MOD_STRENGTH_SHORT = "str", ITEM_MOD_AGILITY_SHORT = "agi", ITEM_MOD_STAMINA_SHORT = "sta",
	ITEM_MOD_INTELLECT_SHORT = "int", ITEM_MOD_SPIRIT_SHORT = "spi", ITEM_MOD_HEALTH_SHORT = "health",
	ITEM_MOD_MANA_SHORT = "mana", ITEM_MOD_ATTACK_POWER_SHORT = "ap", ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "rap",
	ITEM_MOD_SPELL_POWER_SHORT = "sp", ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "spDmg", ITEM_MOD_SPELL_HEALING_DONE_SHORT = "heal",
	ITEM_MOD_ARCANE_SPELL_DAMAGE_DONE_SHORT = "spArcane", ITEM_MOD_FIRE_SPELL_DAMAGE_DONE_SHORT = "spFire",
	ITEM_MOD_FROST_SPELL_DAMAGE_DONE_SHORT = "spFrost", ITEM_MOD_HOLY_SPELL_DAMAGE_DONE_SHORT = "spHoly",
	ITEM_MOD_NATURE_SPELL_DAMAGE_DONE_SHORT = "spNature", ITEM_MOD_SHADOW_SPELL_DAMAGE_DONE_SHORT = "spShadow",
	ITEM_MOD_MANA_REGENERATION_SHORT = "mp5", ITEM_MOD_POWER_REGEN0_SHORT = "mp5", ITEM_MOD_HEALTH_REGEN_SHORT = "hp5",
	ITEM_MOD_HEALTH_REGENERATION_SHORT = "hp5", ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "defense",
	ITEM_MOD_BLOCK_VALUE_SHORT = "blockValue", ITEM_MOD_SPELL_PENETRATION_SHORT = "spellPen",
	RESISTANCE1_NAME = "resHoly", RESISTANCE2_NAME = "resFire", RESISTANCE3_NAME = "resNature",
	RESISTANCE4_NAME = "resFrost", RESISTANCE5_NAME = "resShadow", RESISTANCE6_NAME = "resArcane",
}
-- Ratings: our stat key and the ns.DATA.rating divisor (rating per 1%) it uses.
local RATED = {
	ITEM_MOD_HIT_RATING_SHORT = { "hit", "hit" }, ITEM_MOD_CRIT_RATING_SHORT = { "crit", "crit" },
	ITEM_MOD_HIT_MELEE_RATING_SHORT = { "mhit", "hit" }, ITEM_MOD_HIT_RANGED_RATING_SHORT = { "mhit", "hit" },
	ITEM_MOD_CRIT_MELEE_RATING_SHORT = { "mcrit", "crit" }, ITEM_MOD_CRIT_RANGED_RATING_SHORT = { "mcrit", "crit" },
	ITEM_MOD_HIT_SPELL_RATING_SHORT = { "spellHit", "hit" }, ITEM_MOD_CRIT_SPELL_RATING_SHORT = { "spellCrit", "crit" },
	ITEM_MOD_DODGE_RATING_SHORT = { "dodge", "dodge" }, ITEM_MOD_PARRY_RATING_SHORT = { "parry", "parry" },
	ITEM_MOD_BLOCK_RATING_SHORT = { "block", "block" }, ITEM_MOD_HASTE_RATING_SHORT = { "haste", "haste" },
}
-- Equip-bonus families: a family the client reports is taken whole from the client; one it does not
-- report comes from the shipped table (no double count of e.g. "sp" vs "spDmg").
local FAMILY = { sp = "spell", spDmg = "spell", heal = "spell", spArcane = "spell", spFire = "spell", spFrost = "spell",
	spHoly = "spell", spNature = "spell", spShadow = "spell", ap = "attack", rap = "attack", apFeral = "attack",
	hit = "rating", crit = "rating", mhit = "rating", mcrit = "rating", spellHit = "rating", spellCrit = "rating",
	dodge = "rating", parry = "rating", block = "rating", defense = "rating", haste = "rating",
	mp5 = "regen", hp5 = "regen", spellPen = "pen", blockValue = "blockValue" }

local secret = issecretvalue or function() return false end

-- client stat table, shipped record (or nil) -> stats, armor, dps, filled ({ key = true } from the table)
function Live.Stats(t, rec)
	local out, armor, dps, have, filled = {}, 0, 0, {}, {}
	for k, v in pairs(t or {}) do
		if type(v) == "number" and not secret(v) then
			local key, r = PLAIN[k], RATED[k]
			if k == "RESISTANCE0_NAME" then
				armor = v
			elseif k == "ITEM_MOD_DAMAGE_PER_SECOND_SHORT" then
				dps = v
			-- Two client names for one key are one bonus reported twice (mp5 as MANA_REGENERATION and
			-- POWER_REGEN0, melee and ranged hit/crit): the larger counts, not the sum.
			elseif key then
				out[key] = math.max(out[key] or v, v)
			elseif r then -- to %, rounded like a suffix's rating (Score.SuffixStats)
				local pct = ns.Score.Round(v / ns.DATA.rating[r[2]], 2)
				out[r[1]] = math.max(out[r[1]] or pct, pct)
			end
		end
	end
	for k in pairs(out) do
		if FAMILY[k] then have[FAMILY[k]] = true end
	end
	if rec then
		for k, v in pairs(rec.s) do
			local f = FAMILY[k]
			if f and not have[f] and out[k] == nil then out[k], filled[k] = v, true end
		end
	end
	return out, armor, dps, filled
end

-- The link's random suffix: a bonus id in the link's bonus-ID list that is one of the item's known
-- suffixes, else the classic suffixID field when positive and known. Item string fields after
-- "item:": 1 itemID, 2 enchant, 3-6 gems, 7 suffixID, 8 uniqueID, 9 linkLevel, 10 specID,
-- 11 modifiersMask, 12 itemContext, 13 numBonusIDs, then the bonus ids, then the modifiers (Blizzard's
-- PTR reporter, Blizzard_Reports.lua). Other fields (uniqueID, modifier values) are never read as a
-- suffix. -> bonus id | nil
function Live.Bonus(link, rec)
	if not (rec and rec.sfx and #rec.sfx > 0) or type(link) ~= "string" then return nil end
	local fields = link:match("item:([%d:%-]+)")
	if not fields then return nil end
	local known = {}
	for _, b in ipairs(rec.sfx) do known[b] = true end
	local f, i = {}, 0
	for x in (fields .. ":"):gmatch("([^:]*):") do
		i = i + 1
		f[i] = tonumber(x) -- nil for an empty field
	end
	local n = f[13] or 0
	for k = 14, 13 + n do
		if f[k] and known[f[k]] then return f[k] end
	end
	local sfx = f[7]
	if sfx and sfx > 0 and known[sfx] then return sfx end
	return nil
end

Live.Client = {
	-- -> equipLoc, minLevel, classID, subclassID, quality (nil: not cached yet)
	Info = function(link)
		if not (C_Item and C_Item.GetItemInfo) then return nil end
		local ok, name, _, quality, _, minLevel, _, _, _, equipLoc, _, _, classID, subclassID = pcall(C_Item.GetItemInfo, link)
		if ok and name and not secret(equipLoc) then return equipLoc, minLevel, classID, subclassID, quality end
		return nil
	end,
	Stats = function(link)
		local f = C_Item and C_Item.GetItemStats
		if not f then return nil end
		local ok, t = pcall(f, link)
		return ok and type(t) == "table" and next(t) ~= nil and t or nil
	end,
}

-- link -> instance | nil, "pending" (the client has not got the item yet)
function Live.Instance(link, client)
	client = client or Live.Client
	local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
	if not id then return nil end
	local equipLoc, minLevel, classID, subclassID, quality = client.Info(link)
	if not equipLoc then return nil, "pending" end
	local inv = Live.EQUIP_LOC[equipLoc]
	if not inv then return nil end
	local t = client.Stats(link)
	local rec = ns.Items.Get(id)
	if not t and not rec then return nil, "pending" end
	local bonus = Live.Bonus(link, rec)
	local stats, armor, dps, filled
	if t then
		stats, armor, dps, filled = Live.Stats(t, rec)
	else -- the client knows the item but gave no stats yet: the shipped facts, all of them from the table
		local inst = ns.Score.Instance(rec, bonus)
		stats, armor, dps, filled = inst.stats, inst.armor, inst.dps, {}
		for k in pairs(stats) do filled[k] = true end
	end
	return {
		id = id, link = link, bonus = bonus, inv = inv, rl = minLevel or (rec and rec.rl) or 0, c = classID or (rec and rec.c),
		sc = subclassID or (rec and rec.sc), cm = rec and rec.cm or 0, unique = rec and rec.u or false,
		quality = quality, stats = stats, armor = armor, dps = dps, weapon = dps > 0, filled = filled,
	}
end
