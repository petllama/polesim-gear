-- The whole addon offline with the window (every TOC file, in order), a hand-made Polestar Codex (no
-- Codex data in the repo: an item's id picks its source kind) and a level 20 Shadow priest.
local T = require("t")
local U = require("ui")
local F = {}

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

-- opts: { db, char, done = { [questId] = true }, worn, spec } -> fixture
function F.load(opts)
	opts = opts or {}
	_G.Polestar = { Codex = F.codex(), Compat = { IsQuestCompleted = function(q) return (opts.done or {})[q] == true end } }
	local ns = T.addon(F.files())
	local W = require("wow")
	U.install()
	_G.Minimap = nil -- another test file's minimap stub (test_minimap leaves one): no button here
	_G.PoleSimGearDB, _G.PoleSimGearCharDB = opts.db or {}, opts.char or {}
	ns._frame.scripts.OnEvent(ns._frame, "ADDON_LOADED", "PoleSimGear")
	ns.Print = function() end
	local band, lo, sd = ns.Bands.For("priest", "shadow", 20)
	local worn = opts.worn or { [1] = { inst = { id = 999001, name = "Old Hat", quality = 1, icon = "inv_helmet_01", inv = 1, stats = {} }, score = 1 } }
	ns.Context = {
		ClassKey = function() return "priest" end,
		Get = function()
			return { cls = "priest", spec = opts.spec or "shadow", specSource = "talents", level = 20, lo = lo, band = band,
				ref = sd.ref, w = band.w, worn = worn, faction = "H", classBit = 16, raceBit = 16 }
		end,
		At = function(L) local b, l = ns.Bands.For("priest", "shadow", L) return { band = b, lo = l, w = b.w, worn = worn } end,
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
