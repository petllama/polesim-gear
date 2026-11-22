-- The upgrade prompt: gear that newly reaches the bags (loot, a quest reward, mail, a purchase, a
-- trade) and is an upgrade the character can wear now (Arrows.Verdict) asks once to be equipped, in a
-- small card above Polestar's guide window: [Equip] [Not now], X; right-click: Never for this item.
-- Several wait in a queue ("1 of 3").
--
-- New = an item GUID not seen this session in the bags or worn: the bags at login, an item moved
-- between bags and a piece just taken off never ask. Off with the Settings switch (askEquip), under the
-- minimum gain (askMinPct, % over the replaced item), for an item on the never list (account-wide,
-- item id + random suffix), and while Polestar's own Gear module is on (its "Wear it" banner asks).
--
-- Equip is C_Item.EquipItemByName(link, slot) (ItemDocumentation: no HasRestrictions), only out of
-- combat; the slot is Equip.Compare's (the weaker ring or trinket). An item that binds when worn brings
-- up the client's own confirmation (EQUIP_BIND_CONFIRM -> StaticPopup "EQUIP_BIND"). Only our own frame
-- is made; Polestar's window is read and hooked (HookScript OnShow/OnHide), never written.
local ADDON, ns = ...
local Prompt = {}
ns.Prompt = Prompt

local format = string.format
local W, H, GAP = 280, 64, 4
local WAIT_SECONDS = 3 -- after Equip, how long the button waits for the item to go on
Prompt.MIN_CHOICES = { 0, 1, 3, 5 }
Prompt.SLOT_NAME = { [1] = "Head", [2] = "Neck", [3] = "Shoulder", [5] = "Chest", [6] = "Waist", [7] = "Legs",
	[8] = "Feet", [9] = "Wrist", [10] = "Hands", [11] = "Ring", [12] = "Ring", [13] = "Trinket", [14] = "Trinket",
	[15] = "Back", [16] = "Main hand", [17] = "Off hand", [18] = "Ranged" }

-- The client ------------------------------------------------------------------------------------------
local function bags()
	return 0, (NUM_BAG_SLOTS or (Constants and Constants.InventoryConstants and Constants.InventoryConstants.NumBagSlots) or 4)
end
local function guidAt(loc)
	if not (C_Item and C_Item.GetItemGUID and C_Item.DoesItemExist) then return nil end
	local ok, exists = pcall(C_Item.DoesItemExist, loc)
	if not (ok and exists) then return nil end
	local ok2, guid = pcall(C_Item.GetItemGUID, loc)
	return ok2 and type(guid) == "string" and guid ~= "" and guid or nil
end
-- Gear the character could wear by equip location (C_Item.GetItemInfoInstant works uncached).
local function isGear(link)
	if not (C_Item and C_Item.GetItemInfoInstant) then return false end
	local ok, _, _, _, loc = pcall(C_Item.GetItemInfoInstant, link)
	return ok and type(loc) == "string" and ns.Live.EQUIP_LOC[loc] ~= nil
end
-- The bags now: -> { key = { link, id, key } } where key is the item's GUID (else link#n: a count per link)
function Prompt.ReadBags()
	local out, n = {}, {}
	if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then return out end
	local first, last = bags()
	for bag = first, last do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local link = type(info) == "table" and info.hyperlink
			if type(link) == "string" then
				local key = ItemLocation and ItemLocation.CreateFromBagAndSlot and guidAt(ItemLocation:CreateFromBagAndSlot(bag, slot))
				if not key then
					n[link] = (n[link] or 0) + 1
					key = link .. "#" .. n[link]
				end
				out[key] = { link = link, id = info.itemID, key = key }
			end
		end
	end
	return out
end
local function wornKeys(into)
	if not (ItemLocation and ItemLocation.CreateFromEquipmentSlot) then return end
	for slot = 1, 19 do
		local g = guidAt(ItemLocation:CreateFromEquipmentSlot(slot))
		if g then into[g] = true end
	end
end

-- State -----------------------------------------------------------------------------------------------
local known        -- key -> true: in the bags or worn at some look this session (nil before the first)
local asked = {}   -- key -> true: asked about (or answered) this session
local waiting = {} -- item id -> { key = entry }: the verdict waits for the client's item data
local queue = {}   -- { key, link, id, gain, pct, slot, cmp }, oldest first
local equipping    -- the head entry after Equip, until it is worn or WAIT_SECONDS pass
local equipToken = 0
local baseline = false -- the first looks after login only learn what is there
local frame

local function db() return ns.db end
-- The never list: id:bonus (the random suffix's bonus id, 0 for none)
function Prompt.NeverKey(link)
	local id = tonumber(type(link) == "string" and link:match("item:(%d+)") or "")
	if not id then return nil end
	local bonus = ns.Live.Bonus(link, ns.Items and ns.Items.Get and ns.Items.Get(id)) or 0
	return id .. ":" .. bonus
end
local function never(link)
	local d = db()
	local k = Prompt.NeverKey(link)
	return k and d and type(d.neverEquip) == "table" and d.neverEquip[k] ~= nil
end
function Prompt.NeverCount()
	local d, n = db(), 0
	for _ in pairs(d and type(d.neverEquip) == "table" and d.neverEquip or {}) do n = n + 1 end
	return n
end
function Prompt.ClearNever()
	if db() then db().neverEquip = {} end
end

-- Asking is on: the switch, and Polestar's own Gear (with its Wear it banner) off.
function Prompt.Active()
	if ns.Options.Get("askEquip") == false then return false end
	return not (ns.Coexist and ns.Coexist.PolestarGearOn())
end

-- gain, base (the replaced item's score), min % -> enough to ask
function Prompt.EnoughGain(gain, base, minPct)
	if (minPct or 0) <= 0 then return true end
	if not base or base <= 0.01 then return true end
	return 100 * gain / base >= minPct - 1e-9
end

function Prompt.Queue() return queue end

local refresh -- (the card, below)

-- One item: queued when it is an upgrade worth asking about; waits for item data when pending.
local function consider(e, force)
	if not Prompt.Active() then return end
	if (asked[e.key] and not force) or never(e.link) then return end
	for _, q in ipairs(queue) do if q.key == e.key then return end end
	local up, gain, cmp, wait = ns.Arrows.Verdict(e.link)
	if not up then
		if wait and e.id then
			waiting[e.id] = waiting[e.id] or {}
			waiting[e.id][e.key] = e
		end
		return
	end
	if not Prompt.EnoughGain(gain, cmp and cmp.base, ns.Options.Get("askMinPct")) then return end
	asked[e.key] = true
	queue[#queue + 1] = { key = e.key, link = e.link, id = e.id, gain = gain, slot = cmp and cmp.slot,
		pct = cmp and cmp.base > 0.01 and 100 * gain / cmp.base or nil, inst = nil }
end

-- The bags against what was seen: new gear is considered; questions whose item left go.
function Prompt.Scan()
	local now = Prompt.ReadBags()
	local first = known == nil
	known = known or {}
	wornKeys(known)
	for key, e in pairs(now) do
		if not known[key] then
			known[key] = true
			if not first and not baseline and isGear(e.link) then consider(e) end
		end
	end
	local keep = {}
	for _, q in ipairs(queue) do
		if now[q.key] then keep[#keep + 1] = q end
	end
	if equipping and not now[equipping.key] then equipping = nil end
	queue = keep
	for id, list in pairs(waiting) do
		for key in pairs(list) do
			if not now[key] then list[key] = nil end
		end
		if not next(list) then waiting[id] = nil end
	end
	refresh()
end

-- Every upgrade in the bags now, whatever was seen (/psg ask).
function Prompt.AskAll()
	if not Prompt.Active() then
		ns.Print(ns.Options.Get("askEquip") == false and "Asking to equip upgrades is off (Settings)."
			or "Polestar's Gear is on: its own Wear it prompt asks instead.")
		return
	end
	local n = #queue
	for _, e in pairs(Prompt.ReadBags()) do
		if isGear(e.link) then consider(e, true) end
	end
	if #queue == n then ns.Print("No upgrades in your bags.") end
	refresh()
end
ns.Slash("ask", Prompt.AskAll)

local function drop(i)
	local q = table.remove(queue, i or 1)
	if q and equipping == q then equipping = nil end
	refresh()
end
function Prompt.NotNow() drop(1) end
function Prompt.Never()
	local q = queue[1]
	if not q then return end
	local k = Prompt.NeverKey(q.link)
	if k and db() then
		if type(db().neverEquip) ~= "table" then db().neverEquip = {} end
		db().neverEquip[k] = q.link
	end
	for i = #queue, 1, -1 do
		if Prompt.NeverKey(queue[i].link) == k then table.remove(queue, i) end
	end
	equipping = nil
	refresh()
end
function Prompt.Equip()
	local q = queue[1]
	if not q or equipping or InCombatLockdown() then return end
	if not (C_Item and C_Item.EquipItemByName) then return end
	equipping = q
	equipToken = equipToken + 1
	local token = equipToken
	C_Item.EquipItemByName(q.link, q.slot)
	refresh()
	-- not on after a while (the bind confirmation cancelled, an error): Equip again
	C_Timer.After(WAIT_SECONDS, function()
		if equipToken == token and equipping == q then
			equipping = nil
			refresh()
		end
	end)
end

local function onEquipment()
	local q = equipping
	if not (q and q.slot) then return end
	-- worn: the same item GUID in the slot (links of one item may differ in their fields), else the same link
	local loc = ItemLocation and ItemLocation.CreateFromEquipmentSlot and ItemLocation:CreateFromEquipmentSlot(q.slot)
	local on = loc and guidAt(loc) == q.key
	if not on and GetInventoryItemLink then on = GetInventoryItemLink("player", q.slot) == q.link end
	if on then
		equipping = nil
		for i, e in ipairs(queue) do if e == q then table.remove(queue, i) break end end
		ns.Print(format("Wearing %s (%s).", q.link, Prompt.GainText(q)))
		refresh()
	end
end

-- Better gear went on (or the spec changed): questions that are no longer upgrades go.
local function recheck()
	if #queue == 0 then return end
	local keep = {}
	for _, q in ipairs(queue) do
		local up, gain, cmp = ns.Arrows.Verdict(q.link)
		if up or q == equipping then
			if up then
				q.gain, q.slot = gain, cmp and cmp.slot or q.slot
				q.pct = cmp and cmp.base > 0.01 and 100 * gain / cmp.base or nil
			end
			keep[#keep + 1] = q
		end
	end
	queue = keep
	refresh()
end

function Prompt.GainText(q)
	return format("Upgrade %+.1f", q.gain or 0) .. (q.pct and format(" (%+.0f%%)", q.pct) or "")
end

-- The card ------------------------------------------------------------------------------------------
local S
local hookedPolestar
local function polestarFrame()
	local f = _G.PolestarGuideFrame
	if type(f) == "table" and type(f.IsVisible) == "function" then return f end
	return nil
end

local DEFAULT_POS = { "TOPRIGHT", -40, -240 } -- under the minimap
-- Above Polestar's guide window while it shows (below it when there is no room above); else the
-- place the player dragged it to, else under the minimap.
function Prompt.Anchor()
	if not frame then return end
	frame:ClearAllPoints()
	local pf = polestarFrame()
	if pf and not hookedPolestar and pf.HookScript then
		hookedPolestar = true
		pf:HookScript("OnShow", Prompt.Anchor)
		pf:HookScript("OnHide", Prompt.Anchor)
	end
	if pf and pf:IsVisible() then
		frame.onPolestar = true
		local top, screen = pf.GetTop and pf:GetTop(), UIParent.GetTop and UIParent:GetTop()
		if type(top) == "number" and type(screen) == "number" and top + GAP + H > screen then
			frame:SetPoint("TOP", pf, "BOTTOM", 0, -GAP)
		else
			frame:SetPoint("BOTTOM", pf, "TOP", 0, GAP)
		end
		return
	end
	frame.onPolestar = false
	local p = db() and type(db().promptPos) == "table" and db().promptPos or nil
	if p and type(p[1]) == "string" and type(p[2]) == "number" and type(p[3]) == "number" then
		frame:SetPoint(p[1], UIParent, p[1], p[2], p[3])
	else
		frame:SetPoint(DEFAULT_POS[1], UIParent, DEFAULT_POS[1], DEFAULT_POS[2], DEFAULT_POS[3])
	end
end

local function showTip(icon)
	local q = queue[1]
	if not q then return end
	GameTooltip:SetOwner(icon, "ANCHOR_RIGHT")
	GameTooltip:SetHyperlink(q.link)
	GameTooltip:AddLine("Right-click the card: never ask for this item", 0.6, 0.6, 0.6, true)
	GameTooltip:Show()
end

local function menu(self)
	if not queue[1] then return end
	S.ContextMenu(self, {
		{ text = "Never for this item", onClick = Prompt.Never },
		{ text = "Not now", onClick = Prompt.NotNow },
	})
end

local function build()
	S = ns.Style
	local C = S.C
	local f = CreateFrame("Frame", nil, UIParent)
	f.psgPrompt = true
	f:SetSize(W, H)
	f:SetFrameStrata("HIGH")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	if f.RegisterForDrag then f:RegisterForDrag("LeftButton") end
	f.bg = S.Fill(f, C.inner, 0.97)
	f.border = S.Border(f, C.ddBorder)
	f:SetScript("OnDragStart", function(self) if not self.onPolestar then self:StartMoving() end end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		if self.onPolestar then return end
		local point, _, _, x, y = self:GetPoint(1)
		if db() and point then db().promptPos = { point, math.floor(x + 0.5), math.floor(y + 0.5) } end
	end)
	f:SetScript("OnMouseUp", function(self, button) if button == "RightButton" then menu(self) end end)
	-- icon with a quality border; hover: the item's own tooltip (our score lines come from the hook)
	f.icon = CreateFrame("Button", nil, f)
	f.icon:SetSize(36, 36)
	f.icon:SetPoint("LEFT", 10, 0)
	f.icon.tex = f.icon:CreateTexture(nil, "ARTWORK")
	f.icon.tex:SetAllPoints()
	f.icon.frame = S.Frame(f.icon, f.icon.tex, C.cardBorder)
	f.icon:SetScript("OnEnter", showTip)
	f.icon:SetScript("OnLeave", function() GameTooltip_Hide() end)
	f.icon.UpdateTooltip = showTip
	if f.icon.RegisterForClicks then f.icon:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
	f.icon:SetScript("OnClick", function(_, button) if button == "RightButton" then menu(f) end end)
	f.name = S.Text(f, 12)
	f.name:SetPoint("TOPLEFT", 54, -8)
	f.name:SetWidth(W - 54 - 64)
	if f.name.SetWordWrap then f.name:SetWordWrap(false) end
	f.name:SetJustifyH("LEFT")
	f.sub = S.Text(f, 11, C.label)
	f.sub:SetPoint("TOPLEFT", 54, -24)
	f.sub:SetJustifyH("LEFT")
	f.count = S.Text(f, 10, C.label)
	f.count:SetPoint("TOPRIGHT", -26, -8)
	f.close = S.Button(f, "X", 16, 16, Prompt.NotNow, S.CLOSE)
	f.close:SetPoint("TOPRIGHT", -5, -5)
	f.close.tip = "Not now"
	f.later = S.Button(f, "Not now", 70, 20, Prompt.NotNow, S.ACTION)
	f.later:SetPoint("BOTTOMRIGHT", -8, 7)
	f.equip = S.Button(f, "Equip", 84, 20, function(self) if self:IsEnabled() then Prompt.Equip() end end, S.TAB_ON)
	f.equip:SetPoint("RIGHT", f.later, "LEFT", -6, 0)
	f:Hide()
	frame = f
	return f
end

function Prompt.Frame() return frame end

refresh = function()
	local q = Prompt.Active() and queue[1] or nil
	if not q then
		if frame then frame:Hide() end
		return
	end
	local f = frame or build()
	local inst = ns.Live.Instance(q.link)
	local id = q.id or tonumber(q.link:match("item:(%d+)"))
	local icon = inst and inst.icon or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id))
	f.icon.tex:SetTexture(S.IconPath(icon))
	local qc = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[inst and inst.quality or 1]
	S.SetBorder(f.icon.frame.border, qc and qc.r and { qc.r, qc.g, qc.b } or S.C.cardBorder)
	f.name:SetText(S.ItemText({ name = inst and inst.name or ns.Live.Name(q.link, nil, ns.Items.Get(id)) or "?", quality = inst and inst.quality }))
	f.sub:SetText((Prompt.SLOT_NAME[q.slot] or "Gear") .. "  |cff4cff4c" .. Prompt.GainText(q) .. "|r")
	f.count:SetText(format("%d of %d", 1, #queue))
	f.count:SetShown(#queue > 1)
	local combat = InCombatLockdown()
	f.equip.label:SetText(combat and "After combat" or (equipping and "Equipping" or "Equip"))
	S.SetEnabled(f.equip, not combat and not equipping)
	f.equip.tip = combat and "Equipping waits until combat ends." or nil
	Prompt.Anchor()
	f:Show()
end
Prompt.Refresh = function() refresh() end

-- Events ----------------------------------------------------------------------------------------------
ns.RegisterEvent("PLAYER_ENTERING_WORLD", function(isLogin, isReload)
	if not (isLogin or isReload) and known then return end
	-- the bags of a fresh login may still be filling: the first seconds only learn what is there
	baseline = true
	Prompt.Scan()
	C_Timer.After(2, function()
		Prompt.Scan()
		baseline = false
	end)
end)
local scanQueued = false
ns.RegisterEvent("BAG_UPDATE_DELAYED", function()
	if known == nil or scanQueued then return end
	scanQueued = true
	C_Timer.After(0, function()
		scanQueued = false
		Prompt.Scan()
	end)
end)
ns.RegisterEvent("GET_ITEM_INFO_RECEIVED", function(id)
	local list = id and waiting[id]
	if not list then return end
	waiting[id] = nil
	for _, e in pairs(list) do consider(e) end
	refresh()
end)
ns.RegisterEvent("PLAYER_EQUIPMENT_CHANGED", onEquipment)
ns.RegisterEvent("PLAYER_REGEN_DISABLED", function() refresh() end)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function() refresh() end)
ns.On("SCORES_CHANGED", function() C_Timer.After(0, recheck) end)
ns.On("OPTIONS", function(k)
	if k == "askEquip" and ns.Options.Get("askEquip") == false then queue = {} end
	if k == "askEquip" or k == "askMinPct" then refresh() end
end)
