-- The upgrade prompt (Prompt.lua): a new upgrade in the bags asks to be equipped, above Polestar's
-- guide window. The whole addon (winfix), the client's bags, GUIDs, equipping and combat stubbed here.
local T = require("t")
local F = require("winfix")

-- Items by link: name, inv, int (the score stat), quality. The client's equip location from inv.
local LOC = { [1] = "INVTYPE_HEAD", [5] = "INVTYPE_CHEST", [11] = "INVTYPE_FINGER", [12] = "INVTYPE_TRINKET",
	[13] = "INVTYPE_WEAPON", [17] = "INVTYPE_2HWEAPON" }

-- -> fx, B (B.put(bag, slot, link, guid), B.take(bag, slot), B.event(name, ...), B.equipped calls,
-- B.combat = true/false, B.items[link] = { inv, int, rl } (nil: not gear), B.pending[link] = true)
local function setup(opts)
	opts = opts or {}
	local fx = F.load({ worn = opts.worn })
	local ns = fx.ns
	local B = { bags = { [0] = {}, [1] = {} }, equipped = {}, combat = false, pending = {}, items = {}, wornGuid = {} }
	B.items["item:100"] = { inv = 1, int = 12, name = "Shiny Hat" }
	B.items["item:101"] = { inv = 1, int = 0, name = "Dull Hat" }
	B.items["item:102"] = { inv = 11, int = 9, name = "Good Ring" }
	B.items["item:103"] = { inv = 12, int = 9, name = "Good Trinket" }
	B.items["item:104"] = { inv = 5, int = 2, name = "Slightly Better Robe" }
	B.items["item:105"] = { inv = 1, int = 30, name = "Great Hat" }
	_G.C_Container = {
		GetContainerNumSlots = function(bag) return B.bags[bag] and 16 or 0 end,
		GetContainerItemInfo = function(bag, slot)
			local e = B.bags[bag] and B.bags[bag][slot]
			if not e then return nil end
			return { hyperlink = e.link, itemID = tonumber(e.link:match("item:(%d+)")), stackCount = 1 }
		end,
	}
	_G.ItemLocation = {
		CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end,
		CreateFromEquipmentSlot = function(_, s) return { equip = s } end,
	}
	_G.C_Item = {
		DoesItemExist = function(loc)
			if loc.equip then return fx.U.equipped[loc.equip] ~= nil end
			return B.bags[loc.bag] and B.bags[loc.bag][loc.slot] ~= nil
		end,
		GetItemGUID = function(loc)
			if loc.equip then return B.wornGuid[loc.equip] or ("worn-" .. loc.equip) end
			return B.bags[loc.bag][loc.slot].guid
		end,
		GetItemInfoInstant = function(link)
			local it = B.items[link:match("item:%d+")]
			local id = tonumber(link:match("item:(%d+)"))
			return id, nil, nil, it and LOC[it.inv] or "", 134400, it and 4 or 15, 1
		end,
		EquipItemByName = function(link, slot) B.equipped[#B.equipped + 1] = { link, slot } end,
	}
	_G.InCombatLockdown = function() return B.combat end
	ns.Live.Instance = function(link)
		local key = link:match("item:%d+")
		if B.pending[key] then return nil, "pending" end
		local it = B.items[key]
		if not it then return nil end
		return { id = tonumber(key:match("%d+")), link = link, name = it.name, inv = it.inv, c = it.inv == 13 and 2 or 4,
			sc = it.inv == 13 and 4 or 1, cm = 0, rl = it.rl or 1, quality = 2, stats = { int = it.int }, armor = 0, dps = 0 }
	end
	function B.put(bag, slot, link, guid) B.bags[bag][slot] = { link = link, guid = guid or link .. "-" .. bag .. "-" .. slot } end
	function B.take(bag, slot) local e = B.bags[bag][slot] B.bags[bag][slot] = nil return e end
	function B.event(name, ...) ns._frame.scripts.OnEvent(ns._frame, name, ...) fx.settle() end
	function B.login()
		_G.IsLoggedIn = function() return true end
		B.event("PLAYER_LOGIN")
		B.event("PLAYER_ENTERING_WORLD", true, false)
	end
	function B.loot(bag, slot, link, guid)
		B.put(bag, slot, link, guid)
		B.event("BAG_UPDATE_DELAYED")
	end
	function B.popup() local f = ns.Prompt.Frame() return f and f:IsShown() and f or nil end
	function B.text() return fx.U.texts(B.popup()) end
	function B.done()
		_G.C_Container, _G.ItemLocation, _G.C_Item, _G.PolestarGuideFrame = nil, nil, nil, nil
		fx.done()
	end
	return fx, B, ns
end

-- worn: a hat (score 1), rings of score 5 (11) and 2 (12), trinkets 2 (13) and 5 (14)
local function worn()
	local function w(id, inv, score) return { inst = { id = id, inv = inv, name = "w" .. id, stats = {} }, score = score } end
	return { [1] = w(900, 1, 1), [11] = w(901, 11, 5), [12] = w(902, 11, 2), [13] = w(903, 12, 2), [14] = w(904, 12, 5),
	}
end

return {
	-- a new upgrade asks: name, slot, the gain in green, Equip and Not now
	new_upgrade_prompts = function()
		local fx, B = setup({ worn = worn() })
		B.put(0, 1, "item:101") -- in the bags at login: never asked about
		B.login()
		T.eq(B.popup(), nil, "nothing at login")
		B.loot(0, 2, "item:100")
		local p = B.popup()
		T.ok(p, "the prompt shows")
		local s = B.text()
		T.ok(s:find("Shiny Hat", 1, true), s)
		T.ok(s:find("Head", 1, true), s)
		T.ok(s:find("|cff4cff4cUpgrade +", 1, true), "the gain in green: " .. s)
		T.ok(fx.U.button(p, "Equip"), "Equip"); T.ok(fx.U.button(p, "Not now"), "Not now")
		T.eq(p.count:IsShown(), false, "one: no counter")
		B.done()
	end,
	-- the bags at login, a non-upgrade, a non-gear item, a moved item: no prompt
	nothing_for_old_or_moved_or_worse = function()
		local fx, B = setup({ worn = worn() })
		B.put(0, 1, "item:100", "g1")
		B.login()
		B.loot(0, 2, "item:101") -- worse
		T.eq(B.popup(), nil, "not an upgrade")
		B.loot(0, 3, "item:555") -- not gear
		T.eq(B.popup(), nil, "not gear")
		local e = B.take(0, 1)
		B.put(1, 5, e.link, e.guid) -- moved to another bag: the same GUID
		B.event("BAG_UPDATE_DELAYED")
		T.eq(B.popup(), nil, "moved between bags")
		B.done()
	end,
	-- a GUID asked about once this session is not asked again (Not now, then back in the bags)
	seen_guid_not_again = function()
		local fx, B = setup({ worn = worn() })
		B.login()
		B.loot(0, 2, "item:100", "g7")
		fx.U.button(B.popup(), "Not now"):Click()
		T.eq(B.popup(), nil, "closed")
		local e = B.take(0, 2)
		B.event("BAG_UPDATE_DELAYED")
		B.loot(0, 4, e.link, "g7")
		T.eq(B.popup(), nil, "the same item: not again")
		B.loot(0, 5, "item:100", "g8")
		T.ok(B.popup(), "another copy asks")
		B.done()
	end,
	-- several upgrades queue: "1 of 3", the next after each action
	queue = function()
		local fx, B, ns = setup({ worn = worn() })
		B.login()
		B.put(0, 1, "item:100"); B.put(0, 2, "item:102"); B.put(0, 3, "item:103")
		B.event("BAG_UPDATE_DELAYED")
		local p = B.popup()
		T.eq(p.count:GetText(), "1 of 3")
		local first = ns.Prompt.Queue()[1].link
		fx.U.button(p, "Not now"):Click()
		T.eq(B.popup().count:GetText(), "1 of 2")
		T.ok(ns.Prompt.Queue()[1].link ~= first, "the next one")
		p.close:Click()
		T.eq(B.popup().count:IsShown(), false, "the last one")
		fx.U.button(B.popup(), "Not now"):Click()
		T.eq(B.popup(), nil)
		B.done()
	end,
	-- Equip: the item's link and the slot it replaces (the weaker ring or trinket); worn -> the next
	equip_slot_and_verify = function()
		local fx, B, ns = setup({ worn = worn() })
		B.login()
		B.put(0, 1, "item:102"); B.put(0, 2, "item:103")
		B.event("BAG_UPDATE_DELAYED")
		local p = B.popup()
		T.ok(p.count:GetText() == "1 of 2")
		local head = ns.Prompt.Queue()[1]
		fx.U.button(p, "Equip"):Click()
		T.eq(#B.equipped, 1)
		T.eq(B.equipped[1][1], head.link)
		T.eq(B.equipped[1][2], head.link == "item:102" and 12 or 13, "the weaker one")
		T.eq(p.equip:IsEnabled(), false, "waiting for the item to go on")
		-- worn: the next one shows
		-- worn: the item's GUID in the slot (the worn link may carry other fields than the bag's)
		fx.U.equipped[B.equipped[1][2]] = head.link .. ":0:bound"
		B.wornGuid[B.equipped[1][2]] = head.key
		B.take(0, head.link == "item:102" and 1 or 2)
		local said
		ns.Print = function(m) said = m end
		B.event("PLAYER_EQUIPMENT_CHANGED", B.equipped[1][2], true)
		T.ok(said and said:find("Wearing " .. head.link, 1, true), "seen worn by its GUID: " .. tostring(said))
		T.eq(B.popup().count:IsShown(), false, "the next one at once")
		B.event("BAG_UPDATE_DELAYED")
		T.eq(B.popup().count:IsShown(), false, "one left")
		local next = ns.Prompt.Queue()[1]
		T.ok(next.link ~= head.link)
		fx.U.button(B.popup(), "Equip"):Click()
		T.eq(B.equipped[2][2], next.link == "item:102" and 12 or 13)
		B.done()
	end,
	-- in combat the Equip button waits ("After combat"); it comes back when combat ends
	combat_waits = function()
		local fx, B = setup({ worn = worn() })
		B.login()
		B.combat = true
		B.event("PLAYER_REGEN_DISABLED")
		B.loot(0, 2, "item:100")
		local p = B.popup()
		T.ok(p, "shown in combat, waiting")
		T.eq(p.equip:IsEnabled(), false)
		T.eq(fx.U.ownText(p.equip), "After combat")
		p.equip:Click()
		T.eq(#B.equipped, 0, "no equip in combat")
		B.combat = false
		B.event("PLAYER_REGEN_ENABLED")
		T.eq(p.equip:IsEnabled(), true)
		T.eq(fx.U.ownText(p.equip), "Equip")
		p.equip:Click()
		T.eq(#B.equipped, 1)
		B.done()
	end,
	-- the bind confirmation cancelled (nothing went on): Equip comes back
	equip_not_worn_comes_back = function()
		local fx, B = setup({ worn = worn() })
		B.login()
		B.loot(0, 2, "item:100")
		local p = B.popup()
		p.equip:Click()
		T.eq(p.equip:IsEnabled(), false, "waiting")
		fx.settle()
		T.eq(p.equip:IsEnabled(), true, "after the wait: nothing went on")
		T.ok(B.popup(), "still asking")
		B.done()
	end,
	-- item data not loaded yet: asked once it arrives (GET_ITEM_INFO_RECEIVED)
	pending_item_data = function()
		local fx, B = setup({ worn = worn() })
		B.login()
		B.pending["item:100"] = true
		B.loot(0, 2, "item:100")
		T.eq(B.popup(), nil, "waiting for the item's data")
		B.pending["item:100"] = nil
		B.event("GET_ITEM_INFO_RECEIVED", 100, true)
		T.ok(B.popup(), "asked when the data came")
		B.done()
	end,
	-- the item leaving the bags (sold, destroyed, equipped by hand) drops its question
	left_the_bags = function()
		local fx, B = setup({ worn = worn() })
		B.login()
		B.loot(0, 2, "item:100")
		B.take(0, 2)
		B.event("BAG_UPDATE_DELAYED")
		T.eq(B.popup(), nil)
		B.done()
	end,
	-- the switch off: nothing; min gain: only bigger gains ask
	option_off_and_min_gain = function()
		local fx, B, ns = setup({ worn = worn() })
		B.login()
		ns.Options.Set("askEquip", false)
		B.loot(0, 2, "item:100")
		T.eq(B.popup(), nil, "off")
		ns.Options.Set("askEquip", true)
		ns.Options.Set("askMinPct", 1e6)
		B.loot(0, 3, "item:105")
		T.eq(B.popup(), nil, "under the minimum")
		ns.Options.Set("askMinPct", 5)
		B.loot(0, 4, "item:105", "g-great-2")
		T.ok(B.popup(), "over the minimum")
		B.done()
	end,
	-- the minimum gain in %: +3% asks under 3, not under 5
	min_gain_pct = function()
		local _, B, ns = setup()
		local P = ns.Prompt
		T.ok(P.EnoughGain(0.5, 10, 0)); T.ok(P.EnoughGain(0.3, 10, 3)); T.ok(not P.EnoughGain(0.3, 10, 5))
		T.ok(P.EnoughGain(0.1, 0, 5), "nothing worn: any gain")
		B.done()
	end,
	-- right-click "Never for this item": remembered account-wide (id + suffix), cleared in Settings
	never = function()
		local fx, B, ns = setup({ worn = worn() })
		B.login()
		B.loot(0, 2, "item:100", "a")
		local p = B.popup()
		p.scripts.OnMouseUp(p, "RightButton")
		local never
		for _, it in ipairs(fx.U.popup() or {}) do if it.text == "Never for this item" then never = it.click end end
		T.ok(never, "the right-click menu offers it")
		never()
		T.eq(B.popup(), nil)
		T.ok(PoleSimGearDB.neverEquip["100:0"], "kept account-wide")
		B.loot(0, 3, "item:100", "b")
		T.eq(B.popup(), nil, "never again for this item")
		local f = fx.open()
		local sp = fx.tab("settings")
		T.ok(fx.U.texts(sp):find("1 item never asked", 1, true), fx.U.texts(sp))
		fx.U.button(sp, "Clear"):Click()
		T.eq(next(PoleSimGearDB.neverEquip), nil, "cleared")
		B.loot(0, 4, "item:100", "c")
		T.ok(B.popup(), "asked again")
		f.close:Click()
		B.done()
	end,
	-- Polestar's own Gear module on (its Wear it banner): ours stays quiet
	polestar_gear_on = function()
		local fx, B, ns = setup({ worn = worn() })
		B.login()
		ns.Coexist.PolestarGearOn = function() return true end
		B.loot(0, 2, "item:100")
		T.eq(B.popup(), nil)
		B.done()
	end,
	-- anchored above Polestar's guide window while it shows; else the saved/default place
	anchor = function()
		local fx, B = setup({ worn = worn() })
		local U = fx.U
		local pf = U.new("Frame", _G.UIParent, "PolestarGuideFrame")
		B.login()
		B.loot(0, 2, "item:100")
		local p = B.popup()
		local pt, rel, relPt = p:GetPoint(1)
		T.eq(pt, "BOTTOM"); T.eq(rel, pf); T.eq(relPt, "TOP")
		pf:Hide()
		pt, rel = p:GetPoint(1)
		T.ok(rel ~= pf, "Polestar hidden: our own place")
		T.eq(rel, _G.UIParent)
		pf:Show()
		pt, rel = p:GetPoint(1)
		T.eq(rel, pf, "back above it when it shows")
		B.done()
	end,
	anchor_fallback_and_drag = function()
		local fx, B, ns = setup({ worn = worn() })
		B.login()
		B.loot(0, 2, "item:100")
		local p = B.popup()
		local _, rel = p:GetPoint(1)
		T.eq(rel, _G.UIParent, "no Polestar window: the default place")
		p.GetPoint = function() return "TOPLEFT", _G.UIParent, "TOPLEFT", 300, -200 end
		p.scripts.OnDragStop(p)
		T.eq(PoleSimGearDB.promptPos[1], "TOPLEFT"); T.eq(PoleSimGearDB.promptPos[2], 300)
		B.done()
	end,
	-- the icon's tooltip is the item's own, with a hint for right-click
	icon_tooltip = function()
		local fx, B = setup({ worn = worn() })
		B.login()
		B.loot(0, 2, "item:100")
		local p = B.popup()
		p.icon.scripts.OnEnter(p.icon)
		T.eq(fx.U.tip.link, "item:100")
		T.ok(table.concat(fx.U.tip.lines, "\n"):find("Right-click", 1, true))
		B.done()
	end,
	-- the Settings rows: the switch and the minimum gain
	settings = function()
		local fx, B, ns = setup()
		fx.open()
		local sp = fx.tab("settings")
		local sw = fx.U.button(sp, "Ask to equip upgrades I pick up")
		T.eq(sw.on, true, "on by default")
		sw:Click()
		T.eq(ns.Options.Get("askEquip"), false)
		local items = fx.U.menu(sp.minGain)
		T.eq(#items, 4)
		items[3].select()
		T.eq(ns.Options.Get("askMinPct"), 3)
		T.ok(fx.U.texts(sp):find("Polestar", 1, true))
		B.done()
	end,
	-- /psg ask: every upgrade in the bags now, even ones there at login
	slash_ask = function()
		local fx, B = setup({ worn = worn() })
		B.put(0, 1, "item:100")
		B.login()
		T.eq(B.popup(), nil)
		SlashCmdList.POLESIMGEAR("ask")
		T.ok(B.popup(), "asked now")
		B.done()
	end,
}
