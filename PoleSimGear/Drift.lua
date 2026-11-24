-- /psg drift: the shipped stats (Data/Items.lua, what the browser and the website score) against the
-- client's live stats (the tooltip's path: C_Item.GetItemStats through Live.Stats, with the same
-- filling of equip-bonus families the client leaves out) for every worn and bagged item, or one item
-- id. Catches Blizzard hotfixes the shipped table lacks. Items the client has not loaded are requested
-- and counted ("run again"); the command runs at most every THROTTLE seconds.
local ADDON, ns = ...
local Drift = {}
ns.Drift = Drift

Drift.THROTTLE = 5
Drift.MAX_LINES = 15
Drift.client = nil -- tests set a fake client; nil = ns.Live.Client
local EPS = { dps = 0.06, armor = 0.5 } -- client DPS is rounded; anything else: 0.011 (2-decimal %)

local function num(v)
	return string.format("%g", ns.Score.Round(v, 2))
end

-- link [, client] -> nil (the same, not shipped or not gear) | "pending" (not loaded: requested) |
-- { { key, shipped, live }, ... } sorted by key
function Drift.Diff(link, client)
	client = client or Drift.client or ns.Live.Client
	local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
	local rec = id and ns.Items.Get(id)
	if not rec then return nil end
	local loc = client.Info(link)
	if not loc then return "pending" end
	if not ns.Live.EQUIP_LOC[loc] then return nil end
	local t = client.Stats(link)
	if not t then
		if next(rec.s) or (rec.ar or 0) > 0 or (rec.dps or 0) > 0 then return "pending" end
		return nil
	end
	local live, armor, dps = ns.Live.Stats(t, rec)
	live.armor, live.dps = armor, dps
	local inst = ns.Score.Instance(rec, ns.Live.Bonus(link, rec))
	local shipped = {}
	for k, v in pairs(inst.stats) do shipped[k] = v end
	shipped.armor, shipped.dps = inst.armor or 0, inst.dps or 0
	local keys, seen = {}, {}
	for _, src in ipairs({ shipped, live }) do
		for k in pairs(src) do
			if not seen[k] then seen[k], keys[#keys + 1] = true, k end
		end
	end
	table.sort(keys)
	local out = {}
	for _, k in ipairs(keys) do
		local a, b = shipped[k] or 0, live[k] or 0
		if math.abs(a - b) > (EPS[k] or 0.011) then out[#out + 1] = { k, a, b } end
	end
	return #out > 0 and out or nil
end

-- diff -> "spi 4 -> 6, sp 2 -> 4"
function Drift.Text(d)
	local parts = {}
	for _, e in ipairs(d or {}) do parts[#parts + 1] = e[1] .. " " .. num(e[2]) .. " -> " .. num(e[3]) end
	return table.concat(parts, ", ")
end

-- The worn and bagged item links, each once.
function Drift.Links()
	local out, seen = {}, {}
	local function add(link)
		if type(link) == "string" and not seen[link] then seen[link], out[#out + 1] = true, link end
	end
	if GetInventoryItemLink then
		for slot = 1, 19 do
			local ok, link = pcall(GetInventoryItemLink, "player", slot)
			if ok then add(link) end
		end
	end
	if C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo then
		local last = NUM_BAG_SLOTS or (Constants and Constants.InventoryConstants and Constants.InventoryConstants.NumBagSlots) or 4
		for bag = 0, last do
			for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
				local info = C_Container.GetContainerItemInfo(bag, slot)
				add(type(info) == "table" and info.hyperlink or nil)
			end
		end
	end
	return out
end

local function request(link)
	local id = tonumber(link:match("item:(%d+)"))
	if id and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
end

-- Compare these links and print the result.
function Drift.Report(links)
	local checked, pending, lines, more = 0, 0, 0, 0
	for _, link in ipairs(links) do
		local ok, d = pcall(Drift.Diff, link)
		if not ok then
			ns.ReportOnce("drift:" .. link, d)
		elseif d == "pending" then
			pending = pending + 1
			request(link)
		else
			local id = tonumber(link:match("item:(%d+)"))
			if ns.Items.Get(id) then checked = checked + 1 end
			if d then
				if lines < Drift.MAX_LINES then
					lines = lines + 1
					local name = ns.Live.Name(link, nil, ns.Items.Get(id)) or "item"
					ns.Print(string.format("%s (%d): %s", name, id, Drift.Text(d)))
				else
					more = more + 1
				end
			end
		end
	end
	if more > 0 then ns.Print(string.format("and %d more", more)) end
	if lines == 0 and checked > 0 then
		ns.Print(string.format("drift: no differences (%d item%s checked)", checked, checked == 1 and "" or "s"))
	elseif lines == 0 and pending == 0 then
		ns.Print("drift: no worn or bagged items from PoleSim's item table")
	end
	if pending > 0 then
		ns.Print(string.format("drift: %d item%s not loaded yet, run again", pending, pending == 1 and "" or "s"))
	end
end

local last
ns.Slash("drift", function(rest)
	local now = GetTime and GetTime() or 0
	if last and now - last < Drift.THROTTLE then
		return ns.Print(string.format("drift: ran a moment ago, try again in %d s", math.ceil(Drift.THROTTLE - (now - last))))
	end
	last = now
	local id = tonumber(rest or "")
	if rest and rest ~= "" and not id then return ns.Print("usage: /psg drift [itemID]") end
	if not id then return Drift.Report(Drift.Links()) end
	if not ns.Items.Get(id) then return ns.Print(string.format("drift: %d is not in PoleSim's item table", id)) end
	local link = "item:" .. id
	for _, l in ipairs(Drift.Links()) do -- a worn/bagged copy keeps its random suffix
		if tonumber(l:match("item:(%d+)")) == id then link = l break end
	end
	Drift.Report({ link })
end)
