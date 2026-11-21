-- Polestar's own Gear module (tooltip scores, bag arrows, reward picks; setting gear.enabled) is
-- being removed upstream. While it exists and is on, ask once whether to turn it off so the player
-- sees one score; change the setting only on yes. If both stay on, our tooltip line says "PoleSim".
-- Polestar.Gear and Polestar.Get/Set are Polestar internals (not in its docs/API.md): every read is
-- guarded, and a Polestar without the module finds nothing to do.
local ADDON, ns = ...
local Coexist = {}
ns.Coexist = Coexist

function Coexist.PolestarGearOn()
	local P = _G.Polestar
	local G = type(P) == "table" and P.Gear
	if type(G) ~= "table" or type(G.IsEnabled) ~= "function" then return false end
	local ok, on = pcall(G.IsEnabled)
	return ok and on == true
end

-- gearOn: Polestar's Gear is on; asked: the remembered answer (nil until the player answered)
function Coexist.ShouldAsk(gearOn, asked)
	return gearOn and not asked
end

-- Polestar 0.4.1.1 Core/Init.lua ns.Set(path, value): stores the setting and fires its
-- SETTING_CHANGED, which its Gear module answers at once (Gear.lua: invalidate -> GEAR_UPDATED repaints
-- its bag arrows; its tooltip and reward picks read Gear.IsEnabled() on each use): no /reload.
function Coexist.TurnOff()
	local P = _G.Polestar
	if type(P) ~= "table" or type(P.Set) ~= "function" then return false end
	return (pcall(P.Set, "gear.enabled", false))
end

-- Our tooltip line is labelled while both score items.
function Coexist.Label()
	return Coexist.PolestarGearOn()
end
