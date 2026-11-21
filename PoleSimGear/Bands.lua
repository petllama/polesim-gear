-- The level band of a spec for a level (armory.bands_for): (band, its first level, spec data).
local ADDON, ns = ...
local Bands = {}
ns.Bands = Bands

function Bands.For(cls, spec, level)
	local sd = ns.DATA.specs[cls] and ns.DATA.specs[cls][spec]
	if not sd or type(level) ~= "number" then return nil end
	local lo, last, lastLo = 1, nil, 1
	for _, b in ipairs(sd.bands) do
		if level <= b.upTo then return b, lo, sd end
		last, lastLo = b, lo
		lo = b.upTo + 1
	end
	return last, lastLo, sd -- above the last band: that band, with its own first level
end
