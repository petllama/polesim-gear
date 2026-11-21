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
-- -> ok (Set ran without an error), stored (Polestar.Get reads the value back as off)
function Coexist.TurnOff()
	local P = _G.Polestar
	if type(P) ~= "table" or type(P.Set) ~= "function" then return false, false end
	local ok = pcall(P.Set, "gear.enabled", false)
	local stored = false
	if type(P.Get) == "function" then
		local got, v = pcall(P.Get, "gear.enabled")
		stored = got and v == false
	end
	return ok, stored
end

local OPTIONS = "Polestar options: Questing > Rewards & gear > Gear advice"

-- Our tooltip line is labelled while both score items.
function Coexist.Label()
	return Coexist.PolestarGearOn()
end

-- The one-time question. The answer ("yes"/"no") is kept account-wide in PoleSimGearDB.askedPolestarGear;
-- `/psg polestar` forgets it and asks again. A dialog the client could not show (OnCancel without a
-- dialog) or that another dialog replaced ("override") is no answer: the next login asks again.
local KEY = "POLESIMGEAR_POLESTAR_GEAR"
local askedThisSession, waitingForCombat = false, false

local function answer(a)
	if ns.db then ns.db.askedPolestarGear = a end
end

if type(StaticPopupDialogs) == "table" then
	StaticPopupDialogs[KEY] = {
		text = "Polestar's gear scores are on. Turn them off so you see one score?",
		button1 = YES or "Yes",
		button2 = NO or "No",
		OnAccept = function()
			answer("yes")
			local ok, stored = Coexist.TurnOff()
			if ok then
				ns.Print("Polestar's gear scores are off (" .. OPTIONS .. " to turn them back on).")
			elseif stored then
				ns.Print("Polestar's gear scores are set off, but Polestar reported an error applying it: /reload if they still show.")
			else
				ns.Print("Could not turn off Polestar's gear scores: turn them off in " .. OPTIONS .. ".")
			end
			ns.Fire("STATE", "COEXIST")
		end,
		OnCancel = function(dialog, _, reason)
			if not dialog or reason ~= "clicked" then return end -- not shown, or replaced: no answer
			answer("no")
			ns.Print("Both score items: ours is the line that says PoleSim.")
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
	}
end

-- Ask now if it is due: saved variables loaded, a class we score, Polestar's Gear on, no answer yet,
-- not asked already this session. In combat it waits for PLAYER_REGEN_ENABLED.
function Coexist.MaybeAsk()
	if askedThisSession or not (ns.db and ns.Context and ns.Context.ClassKey()) then return end
	if not Coexist.ShouldAsk(Coexist.PolestarGearOn(), ns.db.askedPolestarGear) then return end
	if InCombatLockdown() then
		waitingForCombat = true
		return
	end
	waitingForCombat = false
	if not (StaticPopupDialogs and StaticPopupDialogs[KEY] and StaticPopup_Show) then return end
	askedThisSession = true
	StaticPopup_Show(KEY)
end

ns.RegisterEvent("PLAYER_LOGIN", function()
	C_Timer.After(5, Coexist.MaybeAsk)
end)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
	if waitingForCombat then Coexist.MaybeAsk() end
end)

-- Forget the answer and ask again now (the Settings tab and /psg polestar).
function Coexist.AskAgain()
	if ns.db then ns.db.askedPolestarGear = nil end
	askedThisSession = false
	if not Coexist.PolestarGearOn() then ns.Print("Polestar's gear scores are off: nothing to ask.") end
	Coexist.MaybeAsk()
end
ns.Slash("polestar", Coexist.AskAgain)
