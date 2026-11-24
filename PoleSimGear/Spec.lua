-- The character's PoleSim spec: from the talents (the column with the most points on Forever's
-- C_Traits class tree), or the one the player chose (/psg spec).
local ADDON, ns = ...
local Spec = {}
ns.Spec = Spec

-- Talent columns left to right on Forever's class tree (Polestar's class table has the same order).
-- A class's columns may name specs with no shipped weights (Feral, Enhancement, Protection,
-- Retribution: the melee weapon rules aren't done): they are detected, never scored (Context).
Spec.ORDER = {
	priest = { "discipline", "holy", "shadow" }, mage = { "arcane", "fire", "frost" },
	warlock = { "affliction", "demonology", "destruction" }, druid = { "balance", "feral", "restoration" },
	shaman = { "elemental", "enhancement", "restoration" }, paladin = { "holy", "protection", "retribution" },
	warrior = { "arms", "fury", "protection" }, rogue = { "assassination", "combat", "subtlety" },
	hunter = { "beastmastery", "marksmanship", "survival" },
}
-- The spec with no talent points: armory.DEFAULT_BUILD, shipped in Data/Weights.lua (the website's),
-- except the hybrids, which start as casters here (CASTER_DEFAULT, when that spec has weights).
Spec.CASTER_DEFAULT = { druid = "balance", shaman = "elemental", paladin = "holy" }
Spec.DEFAULT = {}
for cls, key in pairs((ns.DATA and ns.DATA.defaultSpec) or {}) do Spec.DEFAULT[cls] = key end
for cls, key in pairs(Spec.CASTER_DEFAULT) do
	if ns.DATA and ns.DATA.specs and ns.DATA.specs[cls] and ns.DATA.specs[cls][key] then Spec.DEFAULT[cls] = key end
end

-- points[column], names[column] (the client's column headers, any language) -> spec key | nil.
-- A column is named by its header when that is a spec key, else by its position. Most points wins;
-- a tie goes to the larger key, as the website's import (armory.guess_build: max of (points, build)).
function Spec.Pick(points, names, cls)
	local order = Spec.ORDER[cls]
	if not order then return nil end
	local isKey = {}
	for _, key in ipairs(order) do isKey[key] = true end
	local best, most = nil, 0
	for i = 1, #order do
		local p = points[i] or 0
		local name = names and names[i] and names[i]:lower()
		local key = isKey[name] and name or order[i]
		if p > 0 and (p > most or (p == most and key > best)) then best, most = key, p end
	end
	return best
end

-- A node's column from its x position: the n columns stand apart, so the n - 1 widest gaps split them.
function Spec.ColumnsByX(xs, n)
	local s = {}
	for i, x in ipairs(xs) do s[i] = x end
	table.sort(s)
	local gaps = {}
	for i = 2, #s do
		if s[i] > s[i - 1] then gaps[#gaps + 1] = { at = (s[i] + s[i - 1]) / 2, size = s[i] - s[i - 1] } end
	end
	table.sort(gaps, function(a, b) return a.size > b.size end)
	local cuts = {}
	for i = 1, math.min(n - 1, #gaps) do cuts[i] = gaps[i].at end
	return function(x)
		local col = 1
		for _, c in ipairs(cuts) do
			if x > c then col = col + 1 end
		end
		return col
	end
end

-- -> spec key | nil, points per column (for /psg spec)
function Spec.Detect(cls)
	if not Spec.ORDER[cls] then return nil end -- columns of this class unknown: the default
	local CT, Tr = C_ClassTalents, C_Traits
	if not (CT and CT.GetActiveConfigID and Tr and Tr.GetConfigInfo and Tr.GetTreeNodes and Tr.GetNodeInfo) then return nil end
	local ok, cfg = pcall(CT.GetActiveConfigID)
	if not (ok and cfg) then return nil end
	local ok2, info = pcall(Tr.GetConfigInfo, cfg)
	local tree = ok2 and info and info.treeIDs and info.treeIDs[1]
	if not tree then return nil end
	local groups = {}
	if Tr.GetGroupDisplayInfoByTreeID then
		local ok3, list = pcall(Tr.GetGroupDisplayInfoByTreeID, tree)
		if ok3 and type(list) == "table" then
			for i, g in ipairs(list) do groups[#groups + 1] = { id = g.groupID, name = g.displayName, order = g.orderIndex or i } end
		end
	end
	table.sort(groups, function(a, b) return a.order < b.order end)
	local colOf, names = {}, {}
	for i, g in ipairs(groups) do colOf[g.id], names[i] = i, g.name end
	local points, loose, xs = {}, {}, {}
	local ok4, nodes = pcall(Tr.GetTreeNodes, tree)
	for _, id in ipairs(ok4 and type(nodes) == "table" and nodes or {}) do
		local ok5, node = pcall(Tr.GetNodeInfo, cfg, id)
		if ok5 and node and node.ID and node.ID ~= 0 then
			if node.isVisible ~= false and type(node.posX) == "number" then xs[#xs + 1] = node.posX end
			local rank = node.ranksPurchased or 0
			if rank > 0 then
				local col
				for _, g in ipairs(node.groupIDs or {}) do col = col or colOf[g] end
				if col then
					points[col] = (points[col] or 0) + rank
				elseif type(node.posX) == "number" then
					loose[#loose + 1] = { x = node.posX, rank = rank }
				end
			end
		end
	end
	if #loose > 0 and #xs > 0 then
		local colAt = Spec.ColumnsByX(xs, #Spec.ORDER[cls])
		for _, l in ipairs(loose) do
			local c = colAt(l.x)
			points[c] = (points[c] or 0) + l.rank
		end
	end
	return Spec.Pick(points, #names > 0 and names or nil, cls), points
end

-- Whether the addon ships weights it can score with for this spec: melee and hunter specs
-- (needsWeaponModel) only once their bands come from a weights run with the weapon speed / off-hand
-- measurement (weaponModel; PoleSim design 2026-11-22-melee-weapon-weights): they light up with that data.
function Spec.Supported(cls, key)
	local specs = ns.DATA.specs[cls]
	local sd = key ~= nil and specs ~= nil and specs[key]
	return sd ~= nil and sd ~= false and (not sd.needsWeaponModel or sd.weaponModel ~= nil)
end

-- The class's specs with weights (the ones a player can pick): its talent columns in order, else its
-- weight files by name.
function Spec.Keys(cls)
	local out = {}
	if Spec.ORDER[cls] then
		for _, k in ipairs(Spec.ORDER[cls]) do
			if Spec.Supported(cls, k) then out[#out + 1] = k end
		end
		return out
	end
	for k in pairs(ns.DATA.specs[cls] or {}) do out[#out + 1] = k end
	table.sort(out)
	return out
end

-- -> spec key, "chosen" | "talents" | "default"
function Spec.Current(cls)
	local o = ns.char and ns.char.spec
	if o and o ~= "auto" and Spec.Supported(cls, o) then return o, "chosen" end
	local key = Spec.Detect(cls)
	if key then return key, "talents" end
	return Spec.DEFAULT[cls] or Spec.Keys(cls)[1], "default"
end

ns.Slash("spec", function(arg)
	local cls = ns.Context and ns.Context.ClassKey()
	if not cls then return ns.Print(ns.Context and ns.Context.Unsupported and ns.Context.Unsupported() or "no weights for this class yet") end
	arg = (arg or ""):lower()
	if arg == "auto" or Spec.Supported(cls, arg) then
		ns.char.spec = arg
		ns.Fire("STATE", "SPEC")
	end
	local key, source = Spec.Current(cls)
	local _, points = Spec.Detect(cls)
	local keys, shown = Spec.Keys(cls), {}
	for i = 1, #(Spec.ORDER[cls] or {}) do shown[i] = (points and points[i]) or 0 end -- columns without points: 0
	ns.Print("spec " .. tostring(key) .. " (" .. source .. ")" ..
		(#shown > 0 and ("; talent points " .. table.concat(shown, "/")) or "") ..
		". /psg spec auto|" .. table.concat(keys, "|"))
	local why = ns.Context and ns.Context.SpecUnsupported and ns.Context.SpecUnsupported()
	if why then ns.Print(why) end
end)
