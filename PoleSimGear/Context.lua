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
	local band, lo, sd = ns.Bands.For(cls, key, level)
	if not band then none = true return nil end
	local _, _, raceID = UnitRace("player")
	current = {
		cls = cls, spec = key, specSource = source, level = level, band = band, lo = lo, ref = sd.ref, w = band.w,
		faction = ({ Alliance = "A", Horde = "H" })[UnitFactionGroup("player") or ""],
		classBit = ns.DATA.proficiency[cls].bit, raceBit = raceID and bit.lshift(1, raceID - 1) or 0,
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
