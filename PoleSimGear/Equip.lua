-- What the character can wear, and how an item compares with what is worn (the website's rules:
-- rings and trinkets against the weaker of the two, a two-hander against main + off hand, the off
-- hand's weapon DPS at half).
local ADDON, ns = ...
local Equip = {}
ns.Equip = Equip

function Equip.CanUse(it, cls, level)
	local p = ns.DATA.proficiency[cls]
	if not p then return false end
	if (it.cm or 0) ~= 0 and bit.band(it.cm, p.bit) == 0 then return false end
	if it.c == 4 then
		if it.inv == 16 then return true end -- every class wears a cloak
		local need = p.armor[it.sc]
		return need ~= nil and level >= need
	end
	if it.c == 2 then return p.weapons[it.sc] == true end
	return false
end

local SLOT_OF_INV = { [1] = 1, [2] = 2, [3] = 3, [5] = 5, [20] = 5, [6] = 6, [7] = 7, [8] = 8, [9] = 9, [10] = 10,
	[16] = 15, [15] = 18, [25] = 18, [26] = 18, [28] = 18 }
Equip.SLOT_OF_INV = SLOT_OF_INV
local RANGED = { [15] = true, [25] = true, [26] = true, [28] = true }
local MAIN = { [13] = true, [21] = true }
local OFF = { [14] = true, [22] = true, [23] = true }
Equip.ROLE_OF_SLOT = { [16] = "mh", [17] = "oh", [18] = "ranged" }

local function same(a, b) return a and b and a.id == b.id and (a.bonus or 0) == (b.bonus or 0) end

-- -> { score, gain, base, slot, note, equipped }
function Equip.Compare(inst, w, cls, worn, canDw)
	local S = ns.Score
	local function at(slot) local e = worn[slot] return e and e.score or 0, e end
	local inv = inst.inv
	if inv == 11 or inv == 12 then
		local a, b = inv == 11 and 11 or 13, inv == 11 and 12 or 14
		local s = S.Score(inst, w, cls, "gear")
		local sa, ea = at(a)
		local sb, eb = at(b)
		if same(ea and ea.inst, inst) then return { score = s, gain = 0, base = s, slot = a, equipped = true } end
		if same(eb and eb.inst, inst) then return { score = s, gain = 0, base = s, slot = b, equipped = true } end
		-- unique-equipped and worn with another suffix: it can only replace that one
		if inst.unique then
			for _, k in ipairs({ a, b }) do
				local sk, ek = at(k)
				if ek and ek.inst.id == inst.id then
					return { score = s, gain = s - sk, base = sk, slot = k, note = "unique: replaces the one you wear" }
				end
			end
		end
		local weak, base = a, sa
		if sb < sa then weak, base = b, sb end
		return { score = s, gain = s - base, base = base, slot = weak, note = "against your weaker one" }
	end
	local mhScore, mh = at(16)
	local mh2h = mh and mh.inst.inv == 17
	if inv == 17 then
		local s = S.Score(inst, w, cls, "mh")
		if same(mh and mh.inst, inst) then return { score = s, gain = 0, base = s, slot = 16, equipped = true } end
		local base = mhScore + (mh2h and 0 or (at(17)))
		return { score = s, gain = s - base, base = base, slot = 16,
			note = (worn[17] and not mh2h) and "replaces main and off hand" or nil }
	end
	if MAIN[inv] then
		local s = S.Score(inst, w, cls, "mh")
		if same(mh and mh.inst, inst) then return { score = s, gain = 0, base = s, slot = 16, equipped = true } end
		return { score = s, gain = s - mhScore, base = mhScore, slot = 16, note = mh2h and "leaves the off hand empty" or nil }
	end
	if OFF[inv] then
		local s = S.Score(inst, w, cls, "oh")
		local ohScore, oh = at(17)
		if same(oh and oh.inst, inst) then return { score = s, gain = 0, base = s, slot = 17, equipped = true } end
		if mh2h then return { score = s, gain = s - mhScore, base = mhScore, slot = 17, note = "needs a one-hander" } end
		return { score = s, gain = s - ohScore, base = ohScore, slot = 17 }
	end
	local slot = SLOT_OF_INV[inv]
	if not slot then return nil end
	local s = S.Score(inst, w, cls, RANGED[inv] and "ranged" or "gear")
	local base, e = at(slot)
	if same(e and e.inst, inst) then return { score = s, gain = 0, base = s, slot = slot, equipped = true } end
	return { score = s, gain = s - base, base = base, slot = slot }
end
