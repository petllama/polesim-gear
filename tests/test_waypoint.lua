local T = require("t")
local FILES = { "Core.lua", "Waypoint.lua" }
local codex = {
	Instance = function() return { name = "The Deadmines", entrance = { map = 1436, x = 41.9, y = 72.8 } } end,
	Quest = function() return { start = { npc = { 7 } } } end,
	Npc = function() return { name = "Gryan", spawns = { { map = 1436, x = 56, y = 31 } } } end,
}
return {
	spots = function()
		local W = T.addon(FILES).Waypoint
		local s = W.SpotOf({ kind = "dungeon", instanceKey = "DM" }, codex)
		T.eq(s.map, 1436); T.near(s.x, 0.419); T.near(s.y, 0.728); T.eq(s.title, "The Deadmines")
		s = W.SpotOf({ kind = "quest", questId = 100, title = "Wanted" }, codex)
		T.eq(s.map, 1436); T.near(s.x, 0.56); T.eq(s.title, "Wanted (Gryan)")
		s = W.SpotOf({ kind = "vendor", npcName = "Huklah", spot = { map = 1411, x = 40.6, y = 67.9 } }, codex)
		T.near(s.x, 0.406); T.eq(s.title, "Huklah")
		T.eq(W.SpotOf({ kind = "crafted" }, codex), nil)
		T.eq(W.SpotOf({ kind = "quest", questId = 1 }, { Quest = function() error("changed") end }), nil, "guarded")
	end,
	api = function()
		local W = T.addon(FILES).Waypoint
		_G.Polestar = nil
		T.eq(W.Available(), false)
		local got
		_G.Polestar = { Nav = { API = { version = 1, Navigate = function(owner, map, x, y, title) got = { owner, map, x, y, title } return true end } } }
		T.eq(W.Available(), true)
		T.eq(W.Go({ map = 1436, x = 0.5, y = 0.25, title = "X" }), true)
		T.eq(got[1], "PoleSimGear"); T.eq(got[2], 1436); T.eq(got[5], "X")
		_G.Polestar.Nav.API.Navigate = function() error("boom") end
		T.eq(W.Go({ map = 1, x = 0, y = 0, title = "Y" }), false, "an error is a no")
		_G.Polestar.Nav.API.version = 2
		T.eq(W.Available(), false, "another version: its calls may differ, no button")
		T.eq(W.Go({ map = 1, x = 0, y = 0, title = "Y" }), false)
		_G.Polestar.Nav.API.version = 0.5
		T.eq(W.Available(), false)
		_G.Polestar = nil
	end,
}
