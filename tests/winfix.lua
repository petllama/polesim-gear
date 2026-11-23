-- The whole addon offline with the window (every TOC file, in order), a hand-made Polestar Codex (no
-- Codex data in the repo: an item's id picks its source kind) and a level 20 Shadow priest.
local T = require("t")
local U = require("ui")
local F = {}
F.CLASS = { priest = { "Priest", "PRIEST", 5 }, mage = { "Mage", "MAGE", 8 }, warlock = { "Warlock", "WARLOCK", 9 },
	druid = { "Druid", "DRUID", 11 }, shaman = { "Shaman", "SHAMAN", 7 }, paladin = { "Paladin", "PALADIN", 2 },
	warrior = { "Warrior", "WARRIOR", 1 }, rogue = { "Rogue", "ROGUE", 4 }, hunter = { "Hunter", "HUNTER", 3 } }
F.RACE = { priest = { "H", 16 }, mage = { "H", 16 }, warlock = { "H", 16 }, druid = { "H", 32 }, shaman = { "H", 2 }, paladin = { "A", 1 },
	warrior = { "H", 2 }, rogue = { "H", 16 }, hunter = { "H", 2 } }

function F.files()
	local out = {}
	for line in io.lines("PoleSimGear/PoleSimGear.toc") do
		line = line:gsub("\r", "")
		if line ~= "" and not line:match("^#") then out[#out + 1] = (line:gsub("\\", "/")) end
	end
	return out
end

local NPCS = {
	[7] = { name = "Boss", level = 20, boss = true, instance = "DM" },
	[8] = { name = "Trader", faction = "H", spawns = { { map = 1411, x = 40, y = 60 } } },
	[9] = { name = "Ogre", level = 18, spawns = { { map = 1431, x = 50, y = 50 } } },
	[10] = { name = "Giver", spawns = { { map = 1436, x = 56, y = 31 } } },
}
function F.codex()
	return {
		Item = function(id)
			local k = id % 5
			if k == 0 then return { sources = { { type = "quest", quest = 100 + id % 3 } } } end
			if k == 1 then return { sources = { { type = "drop", npc = 7, chance = 10, instance = "DM" } } } end
			if k == 2 then return { sources = { { type = "craft", skill = 50, skillLine = 197, profession = "Tailoring" } } } end
			if k == 3 then return { sources = { { type = "vendor", npc = 8, cost = 1000 } } } end
			return { sources = { { type = "drop", npc = 9, chance = 2 } } }
		end,
		Quest = function(id) return { id = id, title = "Quest " .. id, level = 18, zone = 40, start = { npc = { 10 } }, objectives = {} } end,
		Zone = function(id) return ({ [40] = { name = "Westfall" }, [1411] = { name = "Durotar" }, [1431] = { name = "Duskwood" } })[id] end,
		Npc = function(id) return NPCS[id] end,
		Instance = function() return { name = "The Deadmines", kind = "dungeon", levels = { 10, 16, 21 }, entrance = { map = 1436, x = 41.9, y = 72.8 } } end,
		Load = function() return true end,
	}
end

-- opts: { db, char, done = { [questId] = true }, worn, cls ("priest" | "mage" | "warlock" | "druid" | "shaman" |
-- "paladin"), spec (default: the class's), unsupportedSpec (a detected spec with no weights, e.g. "feral":
-- Context.Get is nil and SpecUnsupported says so),
-- level (default 20), codex = false (keep
-- the caller's _G.Polestar, e.g. the real one), minimap = true (a client Minimap: the button is made) }
-- -> fixture
function F.load(opts)
	opts = opts or {}
	local L = opts.level or 20
	if opts.codex ~= false then
		_G.Polestar = { Codex = F.codex(), Compat = { IsQuestCompleted = function(q) return (opts.done or {})[q] == true end } }
	end
	local ns = T.addon(F.files())
	local W = require("wow")
	W.level = L
	U.install()
	_G.Minimap = nil -- another test file's minimap stub (test_minimap leaves one): no button here
	if opts.minimap then
		_G.Minimap = U.new("Frame", _G.UIParent, "Minimap")
		_G.Minimap:SetSize(198, 198)
		_G.Minimap.GetCenter = function() return 500, 400 end
		_G.Minimap.GetEffectiveScale = function() return 1 end
	end
	_G.PoleSimGearDB, _G.PoleSimGearCharDB = opts.db or {}, opts.char or {}
	ns._frame.scripts.OnEvent(ns._frame, "ADDON_LOADED", "PoleSimGear")
	ns.Print = function() end
	local cls = opts.cls or "priest"
	W.class = F.CLASS[cls]
	-- a race of the class (faction, race bit): undead priest/mage/warlock, tauren druid, orc shaman,
	-- human paladin
	local who = F.RACE[cls] or F.RACE.priest
	local spec = opts.spec or ns.Spec.DEFAULT[cls]
	local band, lo, sd = ns.Bands.For(cls, spec, L)
	local worn = opts.worn or { [1] = { inst = { id = 999001, name = "Old Hat", quality = 1, icon = "inv_helmet_01", inv = 1, stats = {} }, score = 1 } }
	local unsupported = opts.unsupportedSpec
	local canDw = ns.Context.CanDw -- the real rule (class Dual Wield level + the band's "dw" style)
	ns.Context = {
		CanDw = canDw,
		ClassKey = function() return cls end,
		Unsupported = function() return nil end,
		SpecUnsupported = function()
			if not unsupported or (ns.char and ns.char.spec or "auto") ~= "auto" then return nil end
			return (W.class[1] .. " " .. unsupported:sub(1, 1):upper() .. unsupported:sub(2)
				.. " isn't supported yet. Pick a supported spec in Settings to use its weights."), unsupported
		end,
		Get = function()
			local key, source = spec, "talents"
			if unsupported then -- auto lands on the unsupported spec; a chosen one is scored
				local o = ns.char and ns.char.spec
				if not o or o == "auto" then return nil end
				key, source = o, "chosen"
				band, lo, sd = ns.Bands.For(cls, key, L)
			end
			return { cls = cls, spec = key, specSource = source, level = L, lo = lo, band = band,
				ref = sd.ref, w = band.w, worn = worn, faction = who[1], classBit = ns.DATA.proficiency[cls].bit, raceBit = who[2],
				canDw = canDw(cls, L, band), rules = sd.rules }
		end,
		At = function(L2)
			local b, l = ns.Bands.For(cls, spec, L2)
			return { band = b, lo = l, w = b.w, worn = worn, canDw = canDw(cls, L2, b), rules = sd.rules }
		end,
	}
	local fx = { ns = ns, W = W, U = U, worn = worn }
	function fx.settle()
		local n = 0
		while #W.timers > 0 and n < 100000 do W.flush() n = n + 1 end
		return n
	end
	function fx.open() SlashCmdList.POLESIMGEAR("") fx.settle() return _G.PoleSimGearFrame end
	function fx.tab(key) ns.Window.SetTab(key) return ns.Window.Panel(key) end
	function fx.done() _G.Polestar, _G.PoleSimGearFrame = nil, nil end
	return fx
end

return F
