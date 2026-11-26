-- BoP crafted items of a profession the character doesn't have, once they have two primary professions,
-- are not sources (user rule 0.7.13: Shadow Gown, Tailoring 110, was suggested to a non-tailor).
local T = require("t")
local F = require("winfix")
local FILES = { "Core.lua", "Sources.lua" }
local player = { faction = "H", classBit = 16, raceBit = 16, completed = function() return false end }

local GLOBALS = { "GetProfessions", "GetProfessionInfo", "C_SkillInfo", "GetNumSkillLines", "GetSkillLineInfo", "GetItemInfo" }
local saved = {}
for _, k in ipairs(GLOBALS) do saved[k] = _G[k] end
local function clear()
	for _, k in ipairs(GLOBALS) do _G[k] = saved[k] end
end
-- the modern professions API: indices -> { name, skillLine }
local function profs(list)
	_G.GetProfessions = function()
		local idx = {}
		for i = 1, #list do idx[i] = i end
		return idx[1], idx[2], nil, idx[3], idx[4] -- prof1, prof2, archaeology, fishing, cooking
	end
	_G.GetProfessionInfo = function(i) local p = list[i] return p[1], "icon", 50, 75, 0, 0, p[2] end
end
local TAILOR = { "Tailoring", 197 }
local MINING = { "Mining", 186 }
local HERB = { "Herbalism", 182 }
local COOK = { "Cooking", 185 }
local craft = { kind = "crafted", profession = "Tailoring", skill = 110, skillLine = 197, ok = true }
local BOP, BOE = { bd = 1 }, { bd = 2 }

return {
	-- professions from each client API; secondary skills never count; no API: nil (unknown)
	professions = function()
		local S = T.addon(FILES).Sources
		clear()
		T.eq(S.Professions(), nil, "the client can't say")
		profs({ MINING, HERB, COOK })
		local p = S.Professions()
		T.eq(p.n, 2); T.ok(p.lines[186] and p.lines[182]); T.eq(p.lines[185], nil, "cooking is secondary")
		profs({})
		T.eq(S.Professions().n, 0, "none learned (or not loaded yet)")
		clear()
		_G.C_SkillInfo = { GetSkillLineInfoByID = function(id)
			if id == 197 or id == 185 then return { rank = 40, maxRank = 75 } end
			return { rank = 0, maxRank = 0 }
		end }
		p = S.Professions()
		T.eq(p.n, 1); T.ok(p.lines[197])
		clear()
		local skills = { { "Professions", true }, { "Mining", false }, { "Skinning", false }, { "Secondary Skills", true },
			{ "First Aid", false }, { "Fishing", false } }
		_G.GetNumSkillLines = function() return #skills end
		_G.GetSkillLineInfo = function(i) return skills[i][1], skills[i][2] end
		p = S.Professions()
		T.eq(p.n, 2); T.ok(p.lines[186] and p.lines[393])
		clear()
		_G.GetProfessions = function() error("not yet") end
		_G.GetProfessionInfo = function() end
		T.eq(S.Professions(), nil, "an error: unknown")
		clear()
	end,
	-- the rule, case by case
	craft_blocked = function()
		local S = T.addon(FILES).Sources
		clear()
		local two = { lines = { [186] = true, [182] = true }, n = 2 }
		local withTailor = { lines = { [186] = true, [197] = true }, n = 2 }
		local one = { lines = { [186] = true }, n = 1 }
		T.eq(S.CraftBlocked(craft, BOP, 1, two), true, "BoP, two other professions: blocked")
		T.eq(S.CraftBlocked(craft, BOP, 1, withTailor), false, "has the profession")
		T.eq(S.CraftBlocked(craft, BOP, 1, one), false, "one profession: may still learn it")
		T.eq(S.CraftBlocked(craft, BOE, 1, two), false, "BoE: can be bought")
		T.eq(S.CraftBlocked(craft, { bd = 0 }, 1, two), false, "no binding")
		T.eq(S.CraftBlocked(craft, BOP, 1, nil), false, "professions unknown")
		T.eq(S.CraftBlocked({ kind = "crafted", profession = "Tailoring", skill = 110 }, BOP, 1, two), true, "by name without a skill line")
		T.eq(S.CraftBlocked({ kind = "crafted", skill = 110 }, BOP, 1, two), false, "profession unknown")
		T.eq(S.CraftBlocked({ kind = "crafted", profession = "Cooking", skillLine = 185 }, BOP, 1, two), false, "secondary: anyone can learn it")
		T.eq(S.CraftBlocked({ kind = "vendor" }, BOP, 1, two), false, "other kinds untouched")
		-- not shipped: the client's binding, unknown when not cached
		T.eq(S.CraftBlocked(craft, nil, 1, two), false, "binding unknown")
		_G.GetItemInfo = function(id) if id == 7 then return "Gown", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 1 end end
		T.eq(S.CraftBlocked(craft, nil, 7, two), true, "client says BoP")
		T.eq(S.CraftBlocked(craft, nil, 8, two), false, "not cached")
		clear()
	end,
	-- Sources.For: the craft goes, other sources stay
	sources_for = function()
		local S = T.addon(FILES).Sources
		clear()
		local codex = {
			Item = function() return { sources = { { type = "craft", skill = 110, skillLine = 197, profession = "Tailoring" },
				{ type = "vendor", npc = 8 } } } end,
			Quest = function() end,
			Npc = function() return { name = "Trader" } end,
		}
		local two = { lines = { [186] = true, [182] = true }, n = 2 }
		local p = { faction = "H", classBit = 16, raceBit = 16, completed = player.completed, profs = two }
		local out = S.For(1, codex, p, 30, BOP)
		T.eq(#out, 1); T.eq(out[1].kind, "vendor")
		out = S.For(1, codex, player, 30, BOP)
		T.eq(#out, 2, "professions unknown: both")
		T.eq(out[1].text, "Crafted: Tailoring 110", "the note stays")
		p.profs = { lines = { [186] = true }, n = 1 }
		T.eq(#S.For(1, codex, p, 30, BOP), 2, "one profession: kept")
	end,
	-- in the window: Shadow Gown (253967, BoP, a Tailoring craft in the fixture Codex) is no candidate for a
	-- miner/herbalist, and is one for a tailor
	window = function()
		clear()
		profs({ MINING, HERB })
		local fx = F.load({ level = 30 })
		local ns = fx.ns
		local it = ns.Items.Get(253967)
		T.eq(it.bd, 1, "Shadow Gown binds on pickup")
		local env = assert(ns.Window.Env())
		T.eq(env.player.profs.n, 2)
		local w = ns.Bands.For("priest", "shadow", 30).w
		T.eq(ns.Browser.Candidate(253967, env, 30, w, "gear"), nil, "not a source for a miner/herbalist")
		profs({ MINING, TAILOR })
		env = ns.Window.Env()
		local c = ns.Browser.Candidate(253967, env, 30, w, "gear")
		T.ok(c and c.sources[1].kind == "crafted", "a tailor keeps it")
		T.eq(c.sources[1].text, "Crafted: Tailoring 50")
		profs({ MINING })
		T.ok(ns.Browser.Candidate(253967, ns.Window.Env(), 30, w, "gear"), "one profession: kept")
		fx.done()
		clear()
	end,
}
