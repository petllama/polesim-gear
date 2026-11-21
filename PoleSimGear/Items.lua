-- The shipped item table (Data/Items.lua): one "\n<id>\t<fields>" line per item, decoded on first use.
-- Fields: name, quality, item level, required level, inventory type, class, subclass, icon, armor,
-- weapon DPS, stats (k=v;...), suffix budget, suffix ids (a,b), class mask, race mask, unique, bind.
local ADDON, ns = ...
local Items = {}
ns.Items = Items

local tonumber, find, sub, gmatch = tonumber, string.find, string.sub, string.gmatch
local cache, byInv = {}, nil

local function split(s)
	local t = {}
	for f in (s .. "\t"):gmatch("([^\t]*)\t") do t[#t + 1] = f end
	return t
end

local function stats(s)
	local t = {}
	for k, v in gmatch(s, "(%w+)=([^;]+)") do t[k] = tonumber(v) end
	return t
end

local function numbers(s)
	local t = {}
	for n in gmatch(s, "%d+") do t[#t + 1] = tonumber(n) end
	return t
end

local function decode(id, line)
	local f = split(line)
	return {
		id = id, name = f[1], q = tonumber(f[2]), il = tonumber(f[3]), rl = tonumber(f[4]), inv = tonumber(f[5]),
		c = tonumber(f[6]), sc = tonumber(f[7]), icon = f[8] ~= "" and f[8] or nil, ar = tonumber(f[9]) or 0,
		dps = tonumber(f[10]) or 0, s = stats(f[11]), b = tonumber(f[12]) or 0, sfx = numbers(f[13]),
		cm = tonumber(f[14]) or 0, rm = tonumber(f[15]) or 0, u = f[16] == "1", bd = tonumber(f[17]) or 0,
	}
end

function Items.Get(id)
	id = tonumber(id)
	if not id then return nil end
	local hit = cache[id]
	if hit ~= nil then return hit or nil end
	local blob = ns.DATA.items
	local _, e = find(blob, "\n" .. id .. "\t", 1, true)
	local rec = false
	if e then
		local stop = find(blob, "\n", e + 1, true)
		rec = decode(id, sub(blob, e + 1, (stop or #blob + 1) - 1))
	end
	cache[id] = rec
	return rec or nil
end

-- Decoded only as asked: Peek decodes an item without keeping it (an item Get kept is shared). The
-- browser walks thousands of items per build; keeping them all decoded cost ~8 MB for the session.
-- With the index built (ByInv) the line is read at its recorded offset, without searching the blob
-- (if the id is there: else it is searched for).
local lineOf -- id -> offset * 128 + required level (one number per item: the index stays as small)
local function line(blob, id)
	local v = lineOf and lineOf[id]
	local key, _, e = "\n" .. id .. "\t"
	if v then
		e = math.floor(v / 128) - 1 -- the tab before the fields
		if sub(blob, e - #key + 1, e) ~= key then e = nil end -- the table changed under the index
	end
	if not e then
		_, e = find(blob, key, 1, true)
		if not e then return nil end
	end
	local stop = find(blob, "\n", e + 1, true)
	return sub(blob, e + 1, (stop or #blob + 1) - 1)
end

function Items.Peek(id)
	id = tonumber(id)
	if not id then return nil end
	local hit = cache[id]
	if hit ~= nil then return hit or nil end
	local l = line(ns.DATA.items, id)
	return l and decode(id, l)
end

-- inventory type -> { id, ... } in id order, and each item's required level (Items.Rl) and line offset,
-- read off the lines without decoding them. Kept until ReleaseIndex (the browser's window closing).
function Items.ByInv()
	if byInv then return byInv end
	byInv, lineOf = {}, {}
	for id, pos, rl, inv in gmatch(ns.DATA.items, "\n(%d+)\t()[^\t\n]*\t[^\t\n]*\t[^\t\n]*\t(%d*)\t(%d*)\t") do
		id, inv = tonumber(id), tonumber(inv)
		lineOf[id] = pos * 128 + (tonumber(rl) or 0)
		if inv then
			local list = byInv[inv]
			if not list then
				list = {}
				byInv[inv] = list
			end
			list[#list + 1] = id
		end
	end
	return byInv
end

function Items.Rl(id)
	if not lineOf then Items.ByInv() end
	local v = lineOf[id]
	return v and v % 128
end

function Items.ReleaseIndex() byInv, lineOf = nil, nil end

function Items._cached()
	local n = 0
	for _ in pairs(cache) do n = n + 1 end
	return n
end
