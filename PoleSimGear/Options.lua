-- Settings: account-wide switches (PoleSimGearDB.options) and the window's per-character view state
-- (PoleSimGearCharDB.view: source filters, show mode, look ahead, tab). Read at call time; a change
-- fires OPTIONS(key, value) so tooltips, arrows, reward marks and the window follow at once.
local ADDON, ns = ...
local Options = {}
ns.Options = Options

Options.DEFAULTS = { tooltip = true, arrows = true, rewardMark = true, ahead = 0, preferQuest = true, ahPanel = true,
	askEquip = true, askMinPct = 0 }
Options.KINDS = { "quest", "dungeon", "crafted", "vendor", "world" } -- Browser.KINDS (Browser loads later)
Options.FILTER_DEFAULTS = { quest = true, dungeon = true, crafted = true, vendor = true, world = false }
Options.SHOWS = { all = true, upgrades = true, wishlist = true }
Options.TABS = { plan = true, slot = true, sources = true, weights = true, settings = true }
Options.AHEAD_MAX = 5

-- Before ADDON_LOADED (or in a test without it) the settings live in spare tables for the session; a
-- switch Set then is queued and saved at load (the player's latest word wins over the saved value).
local spareDb, spareChar = {}, {}
local queued = {}
local function opts()
	local db = ns.db or spareDb
	if type(db.options) ~= "table" then db.options = {} end
	local o = db.options
	for k, v in pairs(Options.DEFAULTS) do
		if type(o[k]) ~= type(v) then o[k] = v end
	end
	return o
end

function Options.Get(key) return opts()[key] end

function Options.Set(key, value)
	if Options.DEFAULTS[key] == nil or type(value) ~= type(Options.DEFAULTS[key]) then return false end
	if not ns.db then queued[key] = value end
	opts()[key] = value
	ns.Fire("OPTIONS", key, value)
	return true
end

ns.On("DB_READY", function()
	local q = queued
	queued = {}
	for key, value in pairs(q) do Options.Set(key, value) end
end)

local function clampAhead(a)
	if type(a) ~= "number" then return nil end
	return math.max(0, math.min(Options.AHEAD_MAX, math.floor(a)))
end

-- The character's view state, repaired and filled with defaults (the same table every call).
function Options.View()
	local char = ns.char or spareChar
	if type(char.view) ~= "table" then char.view = {} end
	local v = char.view
	if type(v.filters) ~= "table" then v.filters = {} end
	for _, k in ipairs(Options.KINDS) do
		if type(v.filters[k]) ~= "boolean" then v.filters[k] = Options.FILTER_DEFAULTS[k] end
	end
	if not Options.SHOWS[v.show] then v.show = "upgrades" end
	if not Options.TABS[v.tab] then v.tab = "plan" end
	v.ahead = clampAhead(v.ahead) or clampAhead(Options.Get("ahead")) or 0
	return v
end
