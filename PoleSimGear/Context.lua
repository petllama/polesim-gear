-- The character now: class, spec, level, band and worn items' scores, built on demand and kept until
-- something that changes scores happens (Core's STATE: level, talents, equipment, a setting).
local ADDON, ns = ...
local Context = {}
ns.Context = Context

local SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }
-- The spec (key, source) is kept apart: only talents, entering the world or the player's choice change it.
local current, worn, spec, pendingItems = nil, {}, nil, {}
local none = false -- Get found no weights or no band: kept like current (until STATE)
local SPEC_EVENTS = { TRAIT_CONFIG_UPDATED = true, CHARACTER_POINTS_CHANGED = true, PLAYER_TALENT_UPDATE = true,
	PLAYER_ENTERING_WORLD = true, SPEC = true }
-- Right after login the talents may not be readable yet (Detect finds no points): the default spec is
-- then read again after a short wait, a few times, instead of being kept until the talents change.
local RETRY_DELAY, RETRY_MAX = 2, 5
local retries, retryQueued = 0, false

ns.On("STATE", function(event, arg)
	if event == "PLAYER_LEVEL_UP" then ns.level = arg end
	if event == "PLAYER_ENTERING_WORLD" then ns.level, retries = nil, 0 end
	if SPEC_EVENTS[event] then spec = nil end
	current, worn, pendingItems, none = nil, {}, {}, false
	ns.Score.ClearCache()
	ns.Fire("SCORES_CHANGED")
end)
ns.On("DB_READY", function() spec, current, none = nil, nil, false end) -- the saved spec choice is known now

-- A worn item the client had not loaded yet: score again once it has (this event fires for every
-- item the client loads, so only for those).
ns.RegisterEvent("GET_ITEM_INFO_RECEIVED", function(itemID)
	if itemID and pendingItems[itemID] then ns.Fire("STATE", "ITEM_INFO") end
end)

function Context.ClassKey()
	local _, file = UnitClass("player")
	local key = file and file:lower()
	return key and ns.DATA.specs[key] and key or nil
end

-- A class with no shipped weights -> "<Class> isn't supported yet" (said once at login; the window and
-- /psg say it again on demand), else nil.
function Context.Unsupported()
	if Context.ClassKey() then return nil end
	local name, file = UnitClass("player")
	if not (name or file) then return nil end
	return (name or file) .. " isn't supported yet"
end
-- The class is supported but the spec in use has no weights (Feral, Enhancement, Protection,
-- Retribution from the talents): "<Class> <Spec> isn't supported yet. ...", spec key (Get says it once
-- per spec in chat; the window shows it), else nil. Nothing is scored with another spec's weights.
local unsupportedSpec, toldSpec = nil, {}
function Context.SpecUnsupported()
	if not unsupportedSpec then return nil end
	local name, file = UnitClass("player")
	local key = unsupportedSpec
	return string.format("%s %s isn't supported yet. Pick a supported spec in Settings to use its weights.",
		name or file or "", key:sub(1, 1):upper() .. key:sub(2)), key
end
local toldUnsupported = false
ns.RegisterEvent("PLAYER_LOGIN", function()
	local msg = not toldUnsupported and Context.Unsupported()
	if msg then
		toldUnsupported = true
		ns.Print(msg)
	end
end)

function Context.Level()
	return ns.level or UnitLevel("player") or 1
end

-- The worn items scored with a band's weights: slot -> { inst, score } (cached per band).
function Context.WornAt(cls, band)
	local hit = worn[band]
	if hit then return hit end
	local out = {}
	for _, slot in ipairs(SLOTS) do
		local link = GetInventoryItemLink("player", slot)
		if link then
			local inst, pending = ns.Live.Instance(link)
			if inst then
				out[slot] = { inst = inst, score = ns.Score.Score(inst, band.w, cls, ns.Equip.ROLE_OF_SLOT[slot] or "gear") }
			elseif pending then
				local id = tonumber(link:match("item:(%d+)"))
				if id then pendingItems[id] = true end
			end
		end
	end
	worn[band] = out
	return out
end

function Context.RetrySpec(cls)
	if retryQueued or retries >= RETRY_MAX or not (C_Timer and C_Timer.After) then return end
	retryQueued = true
	C_Timer.After(RETRY_DELAY, function()
		retryQueued, retries = false, retries + 1
		if ns.Spec.Detect(cls) then
			retries = 0
			ns.Fire("STATE", "SPEC") -- read the spec again and rescore
		else
			Context.RetrySpec(cls)
		end
	end)
end

-- A race's bit in the Codex's race masks (numbers, not 32-bit ints): Era races 1 << (ChrRaces id - 1);
-- Skyborne 2^32 (High Order, Alliance, id 95) and 2^33 (Windshaper, Horde, id 96), as Polestar reads
-- them (QuestDB raceHigh). nil for a race with no known bit: a mask never excludes it (Polestar's rule).
local SKYBORNE = { [95] = 2 ^ 32, [96] = 2 ^ 33, Alliance = 2 ^ 32, Horde = 2 ^ 33 }
function Context.RaceBit(raceID, raceFile, faction)
	if raceID and raceID >= 1 and raceID <= 8 then return 2 ^ (raceID - 1) end
	if raceID and SKYBORNE[raceID] then return SKYBORNE[raceID] end
	if raceFile == "Skyborne" and faction then return SKYBORNE[faction] end
	return nil
end

-- -> { cls, spec, specSource, level, band, lo, ref, w, worn, faction, classBit, raceBit } | nil (no weights)
function Context.Get()
	if current then return current end
	if none then return nil end
	local cls = Context.ClassKey()
	if not cls then none = true return nil end
	local level = Context.Level()
	if not spec then
		spec = { ns.Spec.Current(cls) }
		if spec[2] == "default" and ns.Spec.ORDER[cls] then Context.RetrySpec(cls) end
	end
	local key, source = spec[1], spec[2]
	unsupportedSpec = nil
	if not ns.Spec.Supported(cls, key) then
		unsupportedSpec = key
		none = true
		if key and not toldSpec[key] then
			toldSpec[key] = true
			ns.Print((Context.SpecUnsupported()))
		end
		return nil
	end
	local band, lo, sd = ns.Bands.For(cls, key, level)
	if not band then none = true return nil end
	local _, raceFile, raceID = UnitRace("player")
	local factionName = UnitFactionGroup("player")
	current = {
		cls = cls, spec = key, specSource = source, level = level, band = band, lo = lo, ref = sd.ref, w = band.w,
		faction = ({ Alliance = "A", Horde = "H" })[factionName or ""],
		classBit = ns.DATA.proficiency[cls].bit, raceBit = Context.RaceBit(raceID, raceFile, factionName),
	}
	current.worn = Context.WornAt(cls, band)
	return current
end

-- The band's weights and worn scores at another level (the browser's "coming up").
function Context.At(level)
	local ctx = Context.Get()
	if not ctx then return nil end
	local band, lo = ns.Bands.For(ctx.cls, ctx.spec, level)
	if not band then return nil end
	return { cls = ctx.cls, spec = ctx.spec, level = level, band = band, lo = lo, w = band.w, worn = Context.WornAt(ctx.cls, band) }
end
