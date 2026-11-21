-- The wishlist: items the player starred (any window row), per character, by item and suffix.
local ADDON, ns = ...
local Wishlist = {}
ns.Wishlist = Wishlist

local function list()
	local char = ns.char
	if not char then return {} end
	if type(char.wish) ~= "table" then char.wish = {} end
	return char.wish
end

function Wishlist.Has(inst) return list()[ns.Browser.KeyOf(inst)] == true end

-- Any suffix of this item (the tooltip: a link's suffix may differ from the starred one).
function Wishlist.HasId(id)
	local prefix = tostring(id) .. ":"
	for k in pairs(list()) do
		if type(k) == "string" and k:sub(1, #prefix) == prefix then return true end
	end
	return false
end

-- -> starred now
function Wishlist.Toggle(inst)
	local w, k = list(), ns.Browser.KeyOf(inst)
	if w[k] then w[k] = nil else w[k] = true end
	ns.Fire("WISHLIST_CHANGED", k)
	return w[k] == true
end

-- The starred keys, in item id order (then suffix), well-formed only.
function Wishlist.Keys()
	local out = {}
	for k, v in pairs(list()) do
		if v == true and type(k) == "string" and k:match("^%d+:%d+$") then out[#out + 1] = k end
	end
	table.sort(out, function(a, b)
		local ia, ba = a:match("^(%d+):(%d+)$")
		local ib, bb = b:match("^(%d+):(%d+)$")
		if tonumber(ia) ~= tonumber(ib) then return tonumber(ia) < tonumber(ib) end
		return tonumber(ba) < tonumber(bb)
	end)
	return out
end
