-- Just enough of the client for the modules' load-time code: frames, timers, slash commands, the
-- player. Pure modules are tested through their functions; client glue is checked in game.
local W = { level = 20 }

-- The client's `bit` (LuaBitOp): LuaJIT has it; plain lua5.1 uses an installed bit library, else this
-- small stand-in (band/bor/lshift for the non-negative masks the addon uses).
local function bitlib()
	local ok, lib = pcall(require, "bit")
	if ok then return lib end
	local function op(a, b, f)
		local r, p = 0, 1
		a, b = a % 4294967296, b % 4294967296
		while a > 0 or b > 0 do
			if f(a % 2, b % 2) then r = r + p end
			a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
		end
		return r
	end
	return {
		band = function(a, b) return op(a, b, function(x, y) return x == 1 and y == 1 end) end,
		bor = function(a, b) return op(a, b, function(x, y) return x == 1 or y == 1 end) end,
		lshift = function(a, n) return (a * 2 ^ n) % 4294967296 end,
	}
end
_G.bit = _G.bit or bitlib()

local function frame()
	local f = { events = {}, scripts = {} }
	function f:RegisterEvent(e) self.events[e] = true end
	function f:SetScript(k, fn) self.scripts[k] = fn end
	return f
end

-- Run the timers due (C_Timer.After(0, ...) runs on the next frame).
function W.flush()
	local due = W.timers
	W.timers = {}
	for _, fn in ipairs(due) do fn() end
end

function W.install()
	_G.CreateFrame = function() return frame() end
	W.timers = {}
	_G.C_Timer = { After = function(_, fn) W.timers[#W.timers + 1] = fn end }
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
