-- The upgrade browser's model (pure: the window in BrowserUI.lua only draws it). Layout "B": best
-- per slot right now, every upgrade of a slot, and "coming up" (the next levels, each scored with the
-- weights of the band it would be worn in).
local ADDON, ns = ...
local Browser = {}
ns.Browser = Browser

Browser.SLOTS = {
	{ key = "head", label = "Head", slot = 1, invs = { 1 } }, { key = "neck", label = "Neck", slot = 2, invs = { 2 } },
	{ key = "shoulder", label = "Shoulder", slot = 3, invs = { 3 } }, { key = "back", label = "Back", slot = 15, invs = { 16 } },
	{ key = "chest", label = "Chest", slot = 5, invs = { 5, 20 } }, { key = "wrist", label = "Wrist", slot = 9, invs = { 9 } },
	{ key = "hands", label = "Hands", slot = 10, invs = { 10 } }, { key = "waist", label = "Waist", slot = 6, invs = { 6 } },
	{ key = "legs", label = "Legs", slot = 7, invs = { 7 } }, { key = "feet", label = "Feet", slot = 8, invs = { 8 } },
	{ key = "finger", label = "Rings", slot = 11, invs = { 11 } }, { key = "trinket", label = "Trinkets", slot = 13, invs = { 12 } },
	{ key = "mainhand", label = "Main hand", slot = 16 }, { key = "offhand", label = "Off hand", slot = 17 },
	{ key = "ranged", label = "Ranged / wand", slot = 18, invs = { 15, 25, 26, 28 } },
}

-- The weapons PoleSim gives the spec at that band (armory: mh_invs / oh_invs by weapon style; casters
-- "any"). Dual wield is left out: no Priest can (later classes add it with their data).
local MH = { ["2h"] = { 17 }, dw = { 13, 21 }, shield = { 13, 21 }, ["1h"] = { 13, 21 }, any = { 13, 17, 21 } }
local OH = { ["2h"] = {}, shield = { 14 }, ["1h"] = { 14, 23 }, any = { 14, 23 } }
function Browser.Invs(def, style)
	if def.key == "mainhand" then return MH[style] or MH.any end
	if def.key == "offhand" then return OH[style] or OH.any end
	return def.invs
end

-- One item -> { id, inst (best suffix), score, sources (ok ones), kinds, rl } | nil (unusable, retired,
-- no quest/dungeon/crafted source the character can use).
function Browser.Candidate(id, env, lim, w, role)
	local it = env.items.Get(id)
	if not it or it.rl > lim then return nil end
	if not ns.Equip.CanUse(it, env.cls, math.max(env.level, it.rl)) then return nil end
	if (it.rm or 0) ~= 0 and bit.band(it.rm, env.player.raceBit) == 0 then return nil end
	local srcs = ns.Sources.For(id, env.codex, env.player, lim)
	if not srcs then return nil end
	local ok, kinds = {}, {}
	for _, s in ipairs(srcs) do
		if s.ok then
			if s.questId then s.route = env.routeStep(s.questId) end
			ok[#ok + 1] = s
			kinds[s.kind] = true
		end
	end
	if #ok == 0 then return nil end
	local inst, score = ns.Score.BestSuffix(it, w, env.cls, role)
	return { id = id, inst = inst, score = score, sources = ok, kinds = kinds, rl = it.rl }
end

-- Candidates per slot for items with rlFrom <= required level <= rlTo, scored with the band of `at`.
-- yield (optional) is called every 50 items so the window can spread the work over frames.
function Browser.Collect(env, at, rlFrom, rlTo, lim, yield)
	local band = env.at(at)
	local byInv = env.items.ByInv()
	local cands, n = {}, 0
	for _, def in ipairs(Browser.SLOTS) do
		local role = ns.Equip.ROLE_OF_SLOT[def.slot] or "gear"
		local list = {}
		for _, inv in ipairs(Browser.Invs(def, band.style)) do
			for _, id in ipairs(byInv[inv] or {}) do
				local it = env.items.Get(id)
				if it and it.rl >= rlFrom and it.rl <= rlTo then
					local c = Browser.Candidate(id, env, lim, band.w, inv == 17 and "mh" or role)
					if c then list[#list + 1] = c end
					n = n + 1
					if yield and n % 50 == 0 then yield() end
				end
			end
		end
		table.sort(list, function(a, b)
			if a.score ~= b.score then return a.score > b.score end
			return a.id < b.id
		end)
		cands[def.key] = list
	end
	return cands, band
end
