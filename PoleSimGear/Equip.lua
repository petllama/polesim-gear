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
