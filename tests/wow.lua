-- Just enough of the client for the modules' load-time code: frames, timers, slash commands, the
-- player. Pure modules are tested through their functions; client glue is checked in game.
local W = { level = 20 }

local function frame()
	local f = { events = {}, scripts = {} }
	function f:RegisterEvent(e) self.events[e] = true end
	function f:SetScript(k, fn) self.scripts[k] = fn end
	return f
end

function W.install()
	_G.CreateFrame = function() return frame() end
	_G.C_Timer = { After = function(_, fn) fn() end }
	_G.hooksecurefunc = function() end
	_G.SlashCmdList = {}
	_G.UnitLevel = function() return W.level end
	_G.UnitClass = function() return "Priest", "PRIEST", 5 end
	_G.UnitRace = function() return "Undead", "Scourge", 5 end
	_G.UnitFactionGroup = function() return "Horde", "Horde" end
	_G.C_AddOns = { GetAddOnMetadata = function() return "test" end }
	_G.geterrorhandler = function() return function(e) error(e, 0) end end
	_G.C_Traits, _G.C_ClassTalents = nil, nil -- a test that needs talents installs them
end

return W
