-- The level band of a spec for a level (armory.bands_for): (band, its first level, spec data).
local ADDON, ns = ...
local Bands = {}
ns.Bands = Bands

function Bands.For(cls, spec, level)
	local sd = ns.DATA.specs[cls] and ns.DATA.specs[cls][spec]
	if not sd then return nil end
	local lo = 1
	for _, b in ipairs(sd.bands) do
		if level <= b.upTo then return b, lo, sd end
		lo = b.upTo + 1
	end
	return sd.bands[#sd.bands], lo, sd
end
