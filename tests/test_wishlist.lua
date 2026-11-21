local T = require("t")
local FILES = { "Core.lua", "Data/Weights.lua", "Data/Suffixes.lua", "Data/Items.lua", "Items.lua", "Score.lua",
	"Equip.lua", "Sources.lua", "Browser.lua", "Wishlist.lua" }
local function load(char)
	local ns = T.addon(FILES)
	_G.PoleSimGearDB, _G.PoleSimGearCharDB = {}, char
	ns._frame.scripts.OnEvent(ns._frame, "ADDON_LOADED", "PoleSimGear")
	return ns
end
return {
	toggle = function()
		local char = {}
		local W = load(char).Wishlist
		T.eq(W.Has({ id = 5, bonus = 2 }), false)
		T.eq(W.Toggle({ id = 5, bonus = 2 }), true); T.eq(char.wish["5:2"], true)
		T.eq(W.Has({ id = 5, bonus = 2 }), true); T.eq(W.HasId(5), true); T.eq(W.HasId(6), false)
		T.eq(W.Toggle({ id = 5, bonus = 2 }), false); T.eq(char.wish["5:2"], nil)
		T.eq(W.HasId(5), false)
	end,
	keys_sorted = function()
		local W = load({ wish = { ["9:0"] = true, ["10:3"] = true, junk = true } }).Wishlist
		T.eq(table.concat(W.Keys(), ","), "9:0,10:3", "id order, junk ignored")
	end,
}
