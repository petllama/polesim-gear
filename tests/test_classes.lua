-- 0.6.0 classes: Warlock (Affliction, Demonology, Destruction), Druid Balance/Restoration, Shaman
-- Elemental/Restoration, Paladin Holy. Feral, Enhancement, Retribution and Protection have no shipped
-- weights (melee weapon rules not done): detected, but never scored with another spec's weights.
local T = require("t")
local FILES = { "Core.lua", "Data/Weights.lua", "Data/Suffixes.lua", "Data/Items.lua", "Items.lua", "Score.lua", "Bands.lua",
	"Spec.lua", "Equip.lua", "Live.lua", "Context.lua" }
local CLASS = { warlock = { "Warlock", "WARLOCK", 9 }, druid = { "Druid", "DRUID", 11 }, shaman = { "Shaman", "SHAMAN", 7 },
	paladin = { "Paladin", "PALADIN", 2 }, warrior = { "Warrior", "WARRIOR", 1 } }

local function addon(cls)
	local ns = T.addon(FILES)
	require("wow").class = CLASS[cls]
	_G.GetInventoryItemLink = function() return nil end
	ns.char = { spec = "auto" }
	return ns
end

-- The website's armory.score for these items (forever/web/armory.py, band files of the 2026-11 run):
-- python3 -c 'A.score(A.instance(d, id), A.bands_for(spec, level)[0]["weights"], cls, role)'
local WEBSITE = {
	{ "warlock/affliction", 20, 11288, "ranged", 59.95 },     -- Greater Magic Wand
	{ "warlock/destruction", 20, 6540, "gear", 0.154 },       -- Willow Pants (armor only)
	{ "shaman/elemental", 40, 4007, "gear", 5.376 },          -- Overlinked Chain Armor (mail at 40)
	{ "paladin/holy", 40, 7922, "gear", 73.11 },              -- Steel Plate Helm (plate at 40)
	{ "paladin/holy", 40, 4068, "oh", 105.003 },              -- Chief Brigadier Shield
	{ "druid/balance", 60, 23197, "ranged", 0 },              -- Idol of the Moon: no stats (its effect isn't scored)
	{ "shaman/restoration", 57, 22345, "ranged", 0 },         -- Totem of Tides
}

return {
	-- Forever's talent columns (Polestar's Talents/Builds.lua specs order) for the new classes.
	order = function()
		local S = addon("druid").Spec
		T.eq(table.concat(S.ORDER.warlock, ","), "affliction,demonology,destruction")
		T.eq(table.concat(S.ORDER.druid, ","), "balance,feral,restoration")
		T.eq(table.concat(S.ORDER.shaman, ","), "elemental,enhancement,restoration")
		T.eq(table.concat(S.ORDER.paladin, ","), "holy,protection,retribution")
	end,
	-- Most points wins (columns by header, else position); ties go to the larger key (the website's rule).
	pick = function()
		local S = addon("druid").Spec
		T.eq(S.Pick({ 0, 31, 0 }, { "Balance", "Feral Combat", "Restoration" }, "druid"), "feral")
		T.eq(S.Pick({ 14, 0, 2 }, nil, "druid"), "balance")
		T.eq(S.Pick({ 0, 0, 11 }, nil, "druid"), "restoration")
		T.eq(S.Pick({ 10, 0, 21 }, nil, "warlock"), "destruction")
		T.eq(S.Pick({ 0, 15, 0 }, nil, "warlock"), "demonology")
		T.eq(S.Pick({ 5, 5, 0 }, nil, "warlock"), "demonology", "tie: the larger key")
		T.eq(S.Pick({ 21, 0, 0 }, nil, "shaman"), "elemental")
		T.eq(S.Pick({ 0, 21, 0 }, nil, "shaman"), "enhancement")
		T.eq(S.Pick({ 11, 0, 0 }, nil, "paladin"), "holy")
		T.eq(S.Pick({ 0, 0, 11 }, nil, "paladin"), "retribution")
		T.eq(S.Pick({ 5, 5, 0 }, nil, "druid"), "feral", "tie: the larger key, even an unsupported one")
	end,
	-- Only specs with shipped weights are offered (Settings, Weights tab, /psg spec).
	supported_keys = function()
		local S = addon("druid").Spec
		T.eq(table.concat(S.Keys("warlock"), ","), "affliction,demonology,destruction")
		T.eq(table.concat(S.Keys("druid"), ","), "balance,feral,restoration")
		T.eq(table.concat(S.Keys("shaman"), ","), "elemental,enhancement,restoration")
		T.eq(table.concat(S.Keys("paladin"), ","), "holy,protection,retribution")
		T.eq(table.concat(S.Keys("warrior"), ","), "arms,fury,protection")
		T.ok(S.Supported("druid", "balance")); T.ok(S.Supported("druid", "feral"))
		T.ok(S.Supported("paladin", "retribution")); T.ok(S.Supported("warrior", "arms"))
		-- tanks since 0.7.1 (their bands carry weaponModel)
		T.ok(S.Supported("paladin", "protection")); T.ok(S.Supported("warrior", "protection"))
	end,
	-- No talent points: the website's default when shipped, else the class's first shipped spec; the
	-- hybrids start as casters in the addon (Balance, Elemental, Holy: Spec.CASTER_DEFAULT), the data
	-- (the website's default) stays Feral/Enhancement/Retribution.
	defaults = function()
		local ns = addon("druid")
		T.eq(ns.Spec.DEFAULT.warlock, "affliction"); T.eq(ns.Spec.DEFAULT.druid, "balance")
		T.eq(ns.Spec.DEFAULT.shaman, "elemental"); T.eq(ns.Spec.DEFAULT.paladin, "holy")
		T.eq(ns.Spec.DEFAULT.priest, "shadow"); T.eq(ns.Spec.DEFAULT.mage, "frost")
		T.eq(ns.Spec.DEFAULT.warrior, "arms"); T.eq(ns.Spec.DEFAULT.rogue, "combat"); T.eq(ns.Spec.DEFAULT.hunter, "beastmastery")
		T.eq(ns.DATA.defaultSpec.druid, "feral", "the website's default is untouched")
		for cls, spec in pairs({ druid = "balance", shaman = "elemental", paladin = "holy" }) do
			local n = addon(cls)
			n.char = n.char or { spec = "auto" }
			T.eq(n.Spec.Current(cls), spec, cls)
		end
		for cls, ref in pairs({ warlock = "spShadow", druid = "sp", shaman = "sp", paladin = "str" }) do
			local n = addon(cls)
			local ctx = n.Context.Get()
			T.eq(ctx.cls, cls); T.eq(ctx.specSource, "default"); T.eq(ctx.ref, ref, cls)
			T.eq(ctx.classBit, n.DATA.proficiency[cls].bit)
		end
	end,
	-- Every new spec has its six bands (up to 19/29/39/49/59/60) and its ref stat weighted 1.
	weights_per_band = function()
		local ns = addon("druid")
		local refs = { ["warlock/affliction"] = "spShadow", ["warlock/demonology"] = "sp", ["warlock/destruction"] = "sp",
			["druid/balance"] = "sp", ["druid/restoration"] = "sp", ["shaman/elemental"] = "sp", ["shaman/restoration"] = "str",
			["paladin/holy"] = "str" }
		for key, ref in pairs(refs) do
			local cls, spec = key:match("(%a+)/(%a+)")
			local sd = ns.DATA.specs[cls][spec]
			T.eq(#sd.bands, 6, key)
			for i, up in ipairs({ 19, 29, 39, 49, 59, 60 }) do T.eq(sd.bands[i].upTo, up, key) end
			local b, lo = ns.Bands.For(cls, spec, 45)
			T.eq(b.upTo, 49, key); T.eq(lo, 40, key)
			T.eq(sd.ref, ref, key)
			T.near(b.w[ref], 1, 1e-9, key .. " ref weight")
		end
		-- melee specs ship gated (needsWeaponModel) until their weights run carries the weapon model
		for _, k in ipairs({ "druid/feral", "shaman/enhancement", "paladin/retribution", "paladin/protection" }) do
			local c, s = k:match("(%a+)/(%a+)")
			T.ok(ns.DATA.specs[c][s].needsWeaponModel, k)
		end
	end,
	-- A known item scores in the addon exactly as on the website.
	scores_equal_the_website = function()
		local ns = addon("druid")
		for _, r in ipairs(WEBSITE) do
			local cls, spec = r[1]:match("(%a+)/(%a+)")
			local w = ns.Bands.For(cls, spec, r[2]).w
			local inst = ns.Score.Instance(ns.Items.Get(r[3]))
			T.near(ns.Score.Score(inst, w, cls, r[4]), r[5], 1e-6, r[1] .. " " .. r[3])
		end
	end,
	-- Proficiencies (armory.PROFICIENCY, Classic rules): armor by level, shields, relics, weapons.
	can_use = function()
		local ns = addon("druid")
		local E = ns.Equip
		local function it(c, sc, inv) return { c = c, sc = sc, inv = inv, cm = 0 } end
		local MAIL, PLATE, LEATHER, SHIELD = it(4, 3, 5), it(4, 4, 5), it(4, 2, 5), it(4, 6, 14)
		local LIBRAM, IDOL, TOTEM = it(4, 7, 28), it(4, 8, 28), it(4, 9, 28)
		local function wp(sc, inv) return it(2, sc, inv or 13) end
		-- shaman: leather, mail at 40, shields, totems; axes, maces, staves, fist, daggers, 2H axes/maces
		T.ok(E.CanUse(LEATHER, "shaman", 1)); T.ok(not E.CanUse(MAIL, "shaman", 39)); T.ok(E.CanUse(MAIL, "shaman", 40))
		T.ok(not E.CanUse(PLATE, "shaman", 60)); T.ok(E.CanUse(SHIELD, "shaman", 1)); T.ok(E.CanUse(TOTEM, "shaman", 1))
		T.ok(not E.CanUse(IDOL, "shaman", 60)); T.ok(not E.CanUse(LIBRAM, "shaman", 60))
		for _, sc in ipairs({ 0, 1, 4, 5, 10, 13, 15 }) do T.ok(E.CanUse(wp(sc), "shaman", 60), "shaman weapon " .. sc) end
		for _, sc in ipairs({ 6, 7, 8, 19, 2 }) do T.ok(not E.CanUse(wp(sc), "shaman", 60), "shaman not " .. sc) end
		-- paladin: mail from 1, plate at 40, shields, librams; axes, maces, swords (1H and 2H), polearms
		T.ok(E.CanUse(MAIL, "paladin", 1)); T.ok(not E.CanUse(PLATE, "paladin", 39)); T.ok(E.CanUse(PLATE, "paladin", 40))
		T.ok(E.CanUse(SHIELD, "paladin", 1)); T.ok(E.CanUse(LIBRAM, "paladin", 1)); T.ok(not E.CanUse(TOTEM, "paladin", 60))
		for _, sc in ipairs({ 0, 1, 4, 5, 6, 7, 8 }) do T.ok(E.CanUse(wp(sc), "paladin", 60), "paladin weapon " .. sc) end
		for _, sc in ipairs({ 10, 13, 15, 19 }) do T.ok(not E.CanUse(wp(sc), "paladin", 60), "paladin not " .. sc) end
		-- druid: leather, idols, no mail/shields; maces (1H and 2H), staves, fist, daggers; no wands
		T.ok(E.CanUse(LEATHER, "druid", 1)); T.ok(not E.CanUse(MAIL, "druid", 60)); T.ok(not E.CanUse(SHIELD, "druid", 60))
		T.ok(E.CanUse(IDOL, "druid", 1)); T.ok(not E.CanUse(TOTEM, "druid", 60))
		for _, sc in ipairs({ 4, 5, 10, 13, 15 }) do T.ok(E.CanUse(wp(sc), "druid", 60), "druid weapon " .. sc) end
		for _, sc in ipairs({ 0, 6, 7, 19 }) do T.ok(not E.CanUse(wp(sc), "druid", 60), "druid not " .. sc) end
		-- warlock: cloth; daggers, swords, staves, wands
		T.ok(E.CanUse(it(4, 1, 5), "warlock", 1)); T.ok(not E.CanUse(LEATHER, "warlock", 60)); T.ok(not E.CanUse(SHIELD, "warlock", 60))
		for _, sc in ipairs({ 7, 10, 15, 19 }) do T.ok(E.CanUse(wp(sc), "warlock", 60), "warlock weapon " .. sc) end
		for _, sc in ipairs({ 4, 0, 5 }) do T.ok(not E.CanUse(wp(sc), "warlock", 60), "warlock not " .. sc) end
		-- none of them dual wields
		for _, c in ipairs({ "warlock", "druid", "shaman", "paladin" }) do T.eq(ns.DATA.proficiency[c].dw, nil, c) end
	end,
	-- A relic goes in the ranged slot and scores its stats only (no weapon DPS); a shield in the off hand.
	relic_and_shield = function()
		local ns = addon("shaman")
		local E = ns.Equip
		local w = { int = 1, rdps = 5, dps = 3, armor = 0.1 }
		local totem = { id = 1, inv = 28, stats = { int = 4 }, armor = 0, dps = 0, weapon = false }
		local c = E.Compare(totem, w, "shaman", {}, false)
		T.eq(c.slot, 18); T.near(c.score, 4)
		local shield = { id = 2, inv = 14, stats = { int = 2 }, armor = 500, dps = 0, weapon = false }
		local worn = { [16] = { inst = { id = 3, inv = 13, stats = {}, armor = 0, dps = 10, weapon = true }, score = 30 },
			[17] = { inst = { id = 4, inv = 14, stats = {}, armor = 300, dps = 0, weapon = false }, score = 30 } }
		c = E.Compare(shield, w, "shaman", worn, false)
		T.eq(c.slot, 17); T.near(c.score, 52); T.near(c.gain, 22)
	end,
	-- A spec with no weights (here Protection, its bands made to lack the weapon model as before 0.7.1):
	-- no context (never another spec's weights), one chat line saying how to pick a supported one;
	-- choosing Holy scores again.
	unsupported_spec = function()
		local ns = addon("paladin")
		ns.DATA.specs.paladin.protection.weaponModel = nil
		local said = {}
		ns.Print = function(...) said[#said + 1] = table.concat({ ... }, " ") end
		ns.Spec.Detect = function() return "protection", { 0, 31, 0 } end
		T.eq(ns.Context.ClassKey(), "paladin")
		T.eq(ns.Context.Unsupported(), nil, "the class is supported")
		T.eq(ns.Context.Get(), nil)
		local msg = "Paladin Protection isn't supported yet. Pick a supported spec in Settings to use its weights."
		T.eq(ns.Context.SpecUnsupported(), msg)
		T.eq(#said, 1); T.eq(said[1], msg)
		ns.Fire("STATE", "SPEC")
		T.eq(ns.Context.Get(), nil)
		T.eq(#said, 1, "said once")
		ns.char.spec = "holy"
		ns.Fire("STATE", "SPEC")
		local ctx = ns.Context.Get()
		T.eq(ctx.spec, "holy"); T.eq(ctx.specSource, "chosen")
		T.eq(ns.Context.SpecUnsupported(), nil)
		-- the other unsupported spec
		for cls, key in pairs({ warrior = "protection" }) do
			local n = addon(cls)
			n.DATA.specs[cls][key].weaponModel = nil
			n.Print = function() end
			n.Spec.Detect = function() return key end
			T.eq(n.Context.Get(), nil, key)
			T.ok(n.Context.SpecUnsupported():find(" isn't supported yet. Pick a supported spec in Settings", 1, true), key)
		end
		local p = addon("paladin")
		p.DATA.specs.paladin.protection.weaponModel = nil
		p.Print = function() end
		p.Spec.Detect = function() return "protection" end
		p.Context.Get()
		T.eq(p.Context.SpecUnsupported(), "Paladin Protection isn't supported yet. Pick a supported spec in Settings to use its weights.")
	end,
	-- /psg spec lists only supported specs and refuses an unsupported one.
	slash_spec = function()
		local ns = addon("paladin")
		ns.DATA.specs.paladin.protection.weaponModel = nil -- a spec without weights (Protection before 0.7.1)
		ns.Context = { ClassKey = function() return "paladin" end, SpecUnsupported = function() return nil end }
		local said
		ns.Print = function(...) said = table.concat({ ... }, " ") end
		SlashCmdList.POLESIMGEAR("spec protection")
		T.eq(ns.char.spec, "auto", "protection has no weights: not chosen")
		T.ok(said:find("auto|holy|retribution", 1, true), said)
		SlashCmdList.POLESIMGEAR("spec retribution")
		T.eq(ns.char.spec, "retribution")
	end,
	-- 0.7.1: the tanks have weights; /psg spec protection picks them and Protection talents score.
	tanks_supported = function()
		for _, cls in ipairs({ "paladin", "warrior" }) do
			local ns = addon(cls)
			ns.Context = { ClassKey = function() return cls end, SpecUnsupported = function() return nil end }
			ns.Print = function() end
			SlashCmdList.POLESIMGEAR("spec protection")
			T.eq(ns.char.spec, "protection", cls)
			local n = addon(cls)
			n.Print = function() end
			n.Spec.Detect = function() return "protection", { 0, 31, 0 } end
			local ctx = n.Context.Get()
			T.ok(ctx, cls .. ": Protection from the talents scores")
			T.eq(ctx.spec, "protection"); T.eq(ctx.ref, "str")
			T.eq(n.Context.SpecUnsupported(), nil)
		end
	end,
	-- The auction house scan asks for the armor the class wears by level + ahead, shields, its weapons.
	ah_queries = function()
		local files = { unpack(FILES) }
		for _, f in ipairs({ "Sources.lua", "Browser.lua", "AH.lua" }) do files[#files + 1] = f end
		local ns = T.addon(files)
		local function labels(cls, level, ahead)
			local out = {}
			for i, q in ipairs(ns.AH.Queries(cls, level, ahead)) do out[i] = q.label end
			return table.concat(out, ",")
		end
		T.eq(labels("shaman", 38, 1), "Cloth,Leather,Shields,Neck rings trinkets off hands,One-handed axes,Two-handed axes,Maces,"
			.. "Two-handed maces,Staves,Fist weapons,Daggers")
		T.ok(labels("shaman", 38, 2):find("Leather,Mail,Shields", 1, true), "mail by level 40")
		T.ok(not labels("paladin", 30, 5):find("Plate", 1, true)); T.ok(labels("paladin", 38, 2):find("Mail,Plate,Shields", 1, true))
		T.eq(labels("warlock", 20, 0), "Cloth,Neck rings trinkets off hands,Swords,Staves,Daggers,Wands")
		T.eq(labels("druid", 20, 0), "Cloth,Leather,Neck rings trinkets off hands,Maces,Two-handed maces,Staves,Fist weapons,Daggers")
	end,
}
