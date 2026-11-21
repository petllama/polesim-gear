-- PoleSim Gear core: the addon table, a message bus, game events, saved variables and /psg.
local ADDON, ns = ...
_G.PoleSimGear = ns -- for /run checks only; other addons must not build on it

ns.ADDON = ADDON
ns.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "dev"

local listeners = {}
function ns.On(msg, fn)
	listeners[msg] = listeners[msg] or {}
	table.insert(listeners[msg], fn)
end

function ns.Fire(msg, ...)
	for _, fn in ipairs(listeners[msg] or {}) do
		local ok, err = pcall(fn, ...)
		if not ok then geterrorhandler()(err) end
	end
end

local frame = CreateFrame("Frame")
ns._frame = frame
local handlers = {}
function ns.RegisterEvent(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		pcall(frame.RegisterEvent, frame, event) -- an event this client lacks is skipped, not an error
	end
	table.insert(handlers[event], fn)
end
frame:SetScript("OnEvent", function(_, event, ...)
	for _, fn in ipairs(handlers[event] or {}) do fn(...) end
end)

ns.RegisterEvent("ADDON_LOADED", function(name)
	if name ~= ADDON then return end
	PoleSimGearDB = PoleSimGearDB or {}
	PoleSimGearCharDB = PoleSimGearCharDB or {}
	PoleSimGearCharDB.spec = PoleSimGearCharDB.spec or "auto"
	ns.db, ns.char = PoleSimGearDB, PoleSimGearCharDB
	ns.Fire("DB_READY")
end)

-- Everything that changes scores: level, talents, equipment, entering the world. Context listens.
for _, e in ipairs({ "PLAYER_LEVEL_UP", "PLAYER_EQUIPMENT_CHANGED", "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE",
	"PLAYER_ENTERING_WORLD" }) do
	ns.RegisterEvent(e, function(...) ns.Fire("STATE", e, ...) end)
end

function ns.Print(...)
	print("|cff66ccffPoleSim Gear|r:", ...)
end

local commands = {}
function ns.Slash(name, fn) commands[name] = fn end
SLASH_POLESIMGEAR1 = "/psg"
SlashCmdList.POLESIMGEAR = function(msg)
	local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	local fn = commands[cmd:lower()] or commands[""]
	if fn then fn(rest) end
end
