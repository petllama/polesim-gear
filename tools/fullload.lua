-- Full-load run (local only, not part of the suite): the whole addon (every TOC file, in order) with
-- the test client and widget stub, the REAL Polestar Codex read from the installed Polestar, a level L
-- character (Shadow priest unless the argument names a class/spec). Fires login, opens the window from
-- the minimap button, waits for the build over frames, then visits everything: every tab, show mode,
-- look ahead 0-5, Sources filter, slot (and its Show all), Sources kind and place (with waypoints), weights band and spec, setting; sets and clears a
-- pick, stars and unstars an item; closes. Lists are walked through a window of 12 frames (U.scroll:
-- every row's initializer runs, as scrolling does).
--
--   luajit|lua5.1 tools/fullload.lua [level[:class[/spec]] ...]   (default 10 30 60, Shadow priest)
--     e.g. 18:mage/frost 30:mage/fire 60:mage/arcane; TOP=5 prints the Gear Plan's first rows with sources
--   POLESTAR_ADDONS=<AddOns folder with Polestar and Polestar_Codex>   (default: the Forever one)
--
-- One line per level: build ms (open -> model shown), the longest frame during the build, KB before
-- open / with the model / after close (an open-wait-close pass), KB after close of the visiting pass,
-- and the errors (client error handler + raised). Exit 1 on any error.
package.path = "./tests/?.lua;" .. package.path
local AD = os.getenv("POLESTAR_ADDONS") or "/mnt/games/BattleNet/World of Warcraft/_forever_/Interface/AddOns/"
if AD:sub(-1) ~= "/" then AD = AD .. "/" end
local clock = os.clock
local format = string.format
local levels, runs = {}, {}
for _, a in ipairs(arg) do
	local lv, cls, spec = a:match("^(%d+):?(%a*)/?(%a*)$")
	assert(lv, "level[:class[/spec]]: " .. a)
	levels[#levels + 1] = tonumber(lv)
	runs[#levels] = { cls = cls ~= "" and cls or nil, spec = spec ~= "" and spec or nil }
end
if #levels == 0 then levels = { 10, 30, 60 } end
local TOP = tonumber(os.getenv("TOP") or "")
local VISIBLE = 12 -- rows a list shows at once

-- 1. Polestar's Codex standalone (Lookup/Codex.lua + the Polestar_Codex pack), loaded once
local P = { Fire = function() end, Compat = { GetPlayerFaction = function() return "Horde" end, GetItemName = function() end } }
P.Data = { Pack = function(name)
	for line in io.lines(AD .. name .. "/" .. name .. ".toc") do
		line = line:gsub("\r", "")
		if line:match("%.lua$") and not line:match("^#") then assert(loadfile(AD .. name .. "/" .. line))(name, P) end
	end
	return true
end }
_G.Polestar = P
assert(loadfile(AD .. "Polestar/Lookup/Codex.lua"))("Polestar", P)
P.Compat.IsQuestCompleted = function() return false end
assert(P.Codex.Load(), "Polestar_Codex did not load")
-- Polestar's Nav API (docs/API.md, version 1) as a recorder: waypoints are checked against real places
local navs = {}
P.Nav = { API = { version = 1, Navigate = function(owner, map, x, y, title)
	navs[#navs + 1] = { owner, map, x, y, title }
	return type(map) == "number" and x >= 0 and x <= 1 and y >= 0 and y <= 1
end } }

-- Polestar's guide engine as a fake: one active guide (100 steps) whose turn-ins are filled from the
-- model's quest sources in the visiting pass; the bus (Polestar.On) records handlers to fire STEP_CHANGED.
local bus, route = {}, { guide = { id = "fake/guide", title = "Fake Guide", steps = {} }, live = 75 }
P.On = function(msg, fn) bus[msg] = bus[msg] or {}; table.insert(bus[msg], fn) end
local function fire(msg, ...) for _, fn in ipairs(bus[msg] or {}) do fn(...) end end
P.Engine = { GetGuide = function() return route.guide end, GetLiveStep = function() return route.live end,
	TabLiveSteps = function() return { { guide = route.guide, live = route.live } } end }

local F = require("winfix")
_G.debugprofilestop = function() return clock() * 1000 end
local failures = 0

local function kb() collectgarbage("collect") return collectgarbage("count") end

for li, L in ipairs(levels) do
	local run = runs[li] or {}
	_G.Polestar = P
	local errors = {}
	local function note(where, e) errors[#errors + 1] = where .. ": " .. tostring(e) end
	-- 2. the addon with the window fixture, the real Codex kept, level L, the client's Minimap
	local okLoad, fx = pcall(F.load, { codex = false, level = L, minimap = true, cls = run.cls, spec = run.spec })
	if not okLoad then
		note("load", fx)
		print(format("level %d: the addon did not load", L))
		for i = 1, #errors do print("  " .. errors[i]) end
		failures = failures + 1
	else
		local ns, U, W = fx.ns, fx.U, fx.W
		-- SYNTH=1: the run's melee/hunter spec with synthetic weapon weights (speed, off hand, ranged speed and
		-- the reference speeds) and weaponModel, as its bands will look after the melee results run (0.7.0)
		if os.getenv("SYNTH") and run.cls then
			local SYN = { warrior = { speed = 14, _mhSpeed = 3.1 }, rogue = { speed = 20, ohDps = 1.2, ohSpeed = -10, _mhSpeed = 2.4, _ohSpeed = 1.4 },
				hunter = { rspeed = 3, _rSpeed = 2.8 }, shaman = { speed = 30, _mhSpeed = 2.7 }, paladin = { speed = 15, _mhSpeed = 3.3 },
				druid = {} }
			local sd = ns.DATA.specs[run.cls][run.spec]
			sd.weaponModel = 1
			for _, b in ipairs(sd.bands) do for k, v in pairs(SYN[run.cls] or {}) do b.w[k] = v end end
			ns.Fire("STATE", "SPEC")
		end
		-- WORN="16:5306,17:..." wears those items (scored with the level's band) instead of the Old Hat
		if os.getenv("WORN") then
			for k in pairs(fx.worn) do fx.worn[k] = nil end
			local c = ns.Context.Get()
			for slot, id in os.getenv("WORN"):gmatch("(%d+):(%d+)") do
				slot, id = tonumber(slot), tonumber(id)
				local inst = ns.Score.Instance(ns.Items.Get(id))
				local role = slot == 17 and "oh" or (slot == 16 and "mh" or (ns.Equip.ROLE_OF_SLOT[slot] or "gear"))
				fx.worn[slot] = { inst = inst, score = ns.Score.Score(inst, c.w, c.cls, role) }
			end
		end
		-- 3. errors reported to the client's handler
		_G.geterrorhandler = function() return function(e) note("handler", e) end end
		-- frames: each W.flush is one client frame (C_Timer.After(0) runs on the next)
		local frames, maxFrame = 0, 0
		local function settle()
			local n = 0
			while #W.timers > 0 and n < 100000 do
				local t = clock()
				W.flush()
				local ms = (clock() - t) * 1000
				if ms > maxFrame then maxFrame = ms end
				n = n + 1
			end
			frames = frames + n
		end
		local function step(where, fn, ...)
			local ok, e = pcall(fn, ...)
			if not ok then note(where, e) end
			settle()
		end
		-- login (ADDON_LOADED ran in F.load)
		_G.IsLoggedIn = function() return true end
		local ev = ns._frame.scripts.OnEvent
		step("PLAYER_LOGIN", ev, ns._frame, "PLAYER_LOGIN")
		step("PLAYER_ENTERING_WORLD", ev, ns._frame, "PLAYER_ENTERING_WORLD", true, false)
		local Win = ns.Window

		-- 4. memory and build time: open (minimap button), wait, close
		local kb0 = kb()
		frames, maxFrame = 0, 0
		local t0 = clock()
		step("open", function() ns.Minimap.button:Click("LeftButton") end)
		local buildMs, buildFrames, buildMax = (clock() - t0) * 1000, frames, maxFrame
		if not Win.state.model then note("open", "no model after the build: " .. tostring(Win.state.why)) end
		local kbOpen = kb()
		if TOP then
			local c = ns.Context.Get()
			print(format("Gear Plan, level %d %s/%s (points of %s):", L, c.cls, c.spec, c.ref))
			local shown = 0
			for _, e in ipairs(ns.TabPlan.Entries()) do
				local r = ns.TabPlan.PlanRow(e)
				if r and shown < TOP then
					shown = shown + 1
					local src = {}
					for i = 1, math.min(2, #r.c.sources) do src[i] = r.c.sources[i].text or r.c.sources[i].kind end
					print(format("  %d. %-10s %-38s %+6.1f (score %.1f)  %s%s", shown, e.def.label, r.c.inst.name or r.c.id,
						r.gain, r.c.score, table.concat(src, "; "), r.note and ("  [" .. r.note .. "]") or ""))
				end
			end
			-- the weapon rows whatever their rank (worn, plan, gain, note)
			for _, e in ipairs(ns.View.PlanEntries(Win.state.model, c.worn, (function() local s = Win.St() s.show = "all" return s end)())) do
				if e.def and (e.def.key == "mainhand" or e.def.key == "offhand") then
					local r = ns.TabPlan.PlanRow(e)
					print(format("  weapons: %-9s worn %-22s %5.1f -> %s", e.def.label, e.worn and e.worn.inst.name or "-",
						e.worn and e.worn.score or 0, r and format("%s %+.1f (score %.1f)%s", r.c.inst.name, r.gain, r.c.score,
						r.note and ("  [" .. r.note .. "]") or "") or (e.entry and e.entry.twoHander and "uses the two-hander" or "nothing")))
				end
			end
			-- the suggestions a near quest (upcoming guide quest within 2 levels) would change if every
			-- available quest were on the route (the fake guide has none yet): an upper bound
			-- NEAR="279874,..." tags only those items' quests (the player's guide, e.g. The Stitcher)
			local only
			if os.getenv("NEAR") then
				only = {}
				for id in os.getenv("NEAR"):gmatch("%d+") do only[tonumber(id)] = true end
			end
			local m, put = Win.state.model, {}
			for _, def in ipairs(ns.Browser.SLOTS) do
				for _, list in ipairs({ m.now[def.key] or {}, m.coming[def.key] or {}, (m.under2h or {})[def.key] or {} }) do
					for _, r in ipairs(list) do
						for _, s in ipairs(r.c.sources) do
							if s.questId and not s.route and (not only or only[r.c.id]) then s.route = { ahead = 1, guide = "all" }; put[#put + 1] = s end
						end
					end
				end
			end
			local st = Win.St()
			st.show, st.preferQuest = "upgrades", true
			print(format("Near quests (level <= %d) over BiS, if their quests were on your route (look ahead %d):", L + 2, st.ahead))
			local any
			for _, e in ipairs(ns.View.PlanEntries(m, c.worn, st)) do
				local en = e.entry
				if en.near and en.best and en.best ~= en.plan then
					any = true
					local q
					for _, s in ipairs(en.plan.c.sources) do if s.kind == "quest" then q = s break end end
					print(format("  %-10s %-34s %+6.1f (%s)  vs BiS %-30s %+6.1f", e.def.label, en.plan.c.inst.name, en.plan.gain,
						q and q.text or "?", en.best.c.inst.name, en.best.gain))
				end
			end
			if not any then print("  none") end
			for _, e in ipairs(ns.View.PlanEntries(m, c.worn, (function() local s2 = Win.St() s2.show, s2.preferQuest = "all", true return s2 end)())) do
				if e.def and (e.def.key == "mainhand" or e.def.key == "offhand") then
					local r = ns.TabPlan.PlanRow(e)
					print(format("  weapons (near quests): %-9s -> %s", e.def.label, r and format("%s %+.1f (score %.1f)%s%s", r.c.inst.name, r.gain,
						r.c.score, r.note and ("  [" .. r.note .. "]") or "", r.setText and ("  [" .. r.setText .. "]") or "")
						or (e.entry.twoHander and "uses the two-hander" or "nothing")))
				end
			end
			for _, s in ipairs(put) do s.route = nil end
		end
		step("close", function() _G.PoleSimGearFrame.close:Click() end)
		local kbClosed = kb()

		-- 5. the visiting pass
		local frame = _G.PoleSimGearFrame
		step("reopen", function() SlashCmdList.POLESIMGEAR("") end)
		local function scroll(box) return U.scroll(box, VISIBLE) end
		local function hover(box, n)
			for _, row in ipairs(U.rows(box, n or 3)) do
				if row.scripts.OnEnter then row.scripts.OnEnter(row) end
				if row.scripts.OnLeave then row.scripts.OnLeave(row) end
			end
		end
		local counts = {}
		-- every tab
		for _, t in ipairs(Win.TABS) do step("tab " .. t.key, Win.SetTab, t.key) end
		-- Gear Plan: show modes x look ahead, hovers, the strip
		step("plan", Win.SetTab, "plan")
		local plan = Win.Panel("plan")
		for _, show in ipairs(Win.SHOW_ROWS) do
			for _, b in ipairs(frame.radios) do if b.show == show[1] then step("show " .. show[1], b.Click, b) end end
			for a = 0, ns.Options.AHEAD_MAX do
				step(format("ahead %d (%s)", a, show[1]), function()
					Win.SetAhead(a)
					counts["plan " .. show[1] .. " +" .. a] = scroll(plan.list)
					hover(plan.list)
				end)
			end
		end
		step("ahead 0", Win.SetAhead, 0)
		for _, b in ipairs(frame.radios) do if b.show == "upgrades" then step("show upgrades", b.Click, b) end end
		step("strip hover", function() for _, b in ipairs(frame.slots) do b.scripts.OnEnter(b) b.scripts.OnLeave(b) end end)
		-- every Sources filter off and on again
		for _, c in ipairs(frame.checks) do
			step("filter " .. c.kind, function()
				local on = ns.Options.View().filters[c.kind]
				c:Click(); scroll(plan.list); c:Click(); scroll(plan.list)
				assert(ns.Options.View().filters[c.kind] == on, "filter restored")
			end)
		end
		step("filters all on", function()
			for _, c in ipairs(frame.checks) do if not ns.Options.View().filters[c.kind] then c:Click() end end
		end)
		-- Slot Upgrades: every slot, its hovers and its Show all
		local slotPanel
		for _, d in ipairs(ns.Browser.SLOTS) do
			step("slot " .. d.key, function()
				Win.OpenSlot(d.key)
				slotPanel = Win.Panel("slot")
				counts["slot " .. d.key] = scroll(slotPanel.list)
				hover(slotPanel.list)
			end)
			step("show all " .. d.key, function()
				for _, row in ipairs(U.rows(slotPanel.list)) do
					if row.d and row.d.showAll then row:Click() end
				end
			end)
			step("after show all " .. d.key, function()
				counts["all " .. d.key] = scroll(slotPanel.list)
				hover(slotPanel.list)
			end)
		end
		-- a pick: Set as plan on a slot's 2nd row, Gear Plan's right-click "Back to suggestion"; a star
		step("pick and star", function()
			local spec = ns.Context.Get().spec
			for _, d in ipairs(ns.Browser.SLOTS) do
				Win.OpenSlot(d.key)
				local rows = U.rows(Win.Panel("slot").list)
				if rows[2] and rows[2].d and rows[2].d.c then
					local key = ns.Browser.KeyOf(rows[2].d.c.inst)
					rows[2].action:Click(); settle()
					assert(ns.Plan.Get(spec, d.key) == key, "picked")
					Win.SetTab("plan")
					local hit
					for _, row in ipairs(U.rows(plan.list)) do
						if row.e and row.e.def and row.e.def.key == d.key then hit = row end
					end
					assert(hit, "the pick's Gear Plan row")
					assert(U.texts(hit):find("Your pick", 1, true), "Your pick shown")
					hit.scripts.OnEnter(hit); hit.scripts.OnLeave(hit)
					hit.scripts.OnClick(hit, "RightButton")
					local back
					for _, it in ipairs(U.popup() or {}) do if it.text == "Back to suggestion" then back = it.click end end
					assert(back, "Back to suggestion in our popup")
					back(); settle()
					assert(U.popup() == nil, "the popup closed")
					assert(ns.Plan.Get(spec, d.key) == nil, "back to the suggestion")
					Win.OpenSlot(d.key)
					rows = U.rows(Win.Panel("slot").list)
					rows[1].star:Click(); settle()
					assert(ns.Wishlist.Has(rows[1].d.c.inst), "starred")
					for _, b in ipairs(frame.radios) do if b.show == "wishlist" then b:Click() end end
					Win.SetTab("plan"); scroll(plan.list); hover(plan.list)
					for _, b in ipairs(frame.radios) do if b.show == "upgrades" then b:Click() end end
					Win.OpenSlot(d.key)
					U.rows(Win.Panel("slot").list)[1].star:Click(); settle()
					assert(not ns.Wishlist.Has(rows[1].d.c.inst), "unstarred")
					counts.picked = d.key
					return
				end
			end
			error("no slot with two upgrades")
		end)
		-- Sources: every kind, every place, hovers and waypoints
		-- the Polestar route: quests of the model turned in at steps 76.. of the fake guide, live step 75;
		-- a step change (STEP_CHANGED) moves every count down by one, in place (no rebuild)
		local routeInfo = "none"
		step("route", function()
			local qs, seen = {}, {}
			for _, def in ipairs(ns.Browser.SLOTS) do
				for _, r in ipairs(Win.state.model.now[def.key] or {}) do
					for _, s in ipairs(r.c.sources) do
						if s.questId and not seen[s.questId] and #qs < 24 then seen[s.questId] = r.c.id; qs[#qs + 1] = s.questId end
					end
				end
			end
			local steps = {}
			for i = 1, 100 do steps[i] = { goals = {} } end
			for k, q in ipairs(qs) do steps[75 + k].goals[1] = { t = "turnin", quest = q } end
			route.guide.steps, route.live = steps, 75
			fire("GUIDE_CHANGED", route.guide.id)
			settle()
			local function count()
				local n, sample = 0, nil
				for _, def in ipairs(ns.Browser.SLOTS) do
					for _, r in ipairs(Win.state.model.now[def.key] or {}) do
						for _, s in ipairs(r.c.sources) do
							if s.route then n = n + 1; sample = sample or s end
						end
					end
				end
				return n, sample
			end
			local n, s = count()
			if #qs > 0 and n == 0 then error("no source on the route") end
			if not s then return end
			local ahead, line = s.route.ahead, ns.Route.ItemLine(seen[s.questId])
			if not line then error("no tooltip line for item " .. tostring(seen[s.questId])) end
			route.live = 76
			fire("STEP_CHANGED", 76)
			local n2, s2 = count()
			local after = s.route and s.route.ahead
			if s.route and after ~= ahead - 1 then error(("ahead %s -> %s"):format(ahead, tostring(after))) end
			routeInfo = ("%d quests, %d sources tagged; %q -> %q; tooltip %q"):format(#qs, n, ns.Route.Tag({ active = true, ahead = ahead }),
				s.route and ns.Route.Tag(s.route) or "passed", line)
		end)
		step("sources", Win.SetTab, "sources")
		local src = Win.Panel("sources")
		local TS = ns.TabSources
		for _, k in ipairs(TS.KINDS) do
			step("kind " .. k[1], function()
				for _, b in ipairs(src.pills) do if b.kind == k[1] then b:Click() end end
				local places = {}
				for _, d in ipairs(src.groups.provided or {}) do if d.g then places[#places + 1] = d.g.key end end
				counts["places " .. k[1]] = #places
				local rows = 0
				if #places == 0 then rows = scroll(src.detail) hover(src.detail) end
				for _, key in ipairs(places) do
					for _, row in ipairs(U.rows(src.groups)) do
						if row.d and row.d.g and row.d.g.key == key then row:Click() end
					end
					rows = rows + scroll(src.detail)
					hover(src.detail)
					for _, row in ipairs(U.rows(src.detail, VISIBLE)) do
						if row.way:IsShown() then row.way:Click() end
					end
				end
				counts["rows " .. k[1]] = rows
			end)
		end
		step("sources look ahead", function()
			for a = 0, ns.Options.AHEAD_MAX do Win.SetAhead(a) scroll(src.detail) end
			Win.SetAhead(0)
		end)
		-- Weights: every band both ways, every spec radio, back to Automatic
		step("weights", Win.SetTab, "weights")
		local wp = Win.Panel("weights")
		step("bands", function()
			local n = #ns.View.Bands(ns.Context.Get().cls, ns.Context.Get().spec)
			for _ = 1, n do ns.TabWeights.Step(1) scroll(wp.list) end
			for _ = 1, n do ns.TabWeights.Step(-1) scroll(wp.list) end
			assert(not wp.prev:IsEnabled(), "first band: < disabled")
		end)
		for _, b in ipairs(wp.radios) do step("spec " .. b.spec, function() b:Click() end) end
		for _, b in ipairs(wp.radios) do if b.spec == "auto" then step("spec auto", function() b:Click() end) end end
		-- Settings: every switch off and on, the look ahead default, Ask again
		step("settings", Win.SetTab, "settings")
		local sp = Win.Panel("settings")
		for i, c in ipairs(sp.checks) do step("switch " .. i, function() c:Click() c:Click() end) end
		step("default ahead", function()
			for _, it in ipairs(U.menu(sp.ahead)) do it.select() end
			U.menu(sp.ahead)[1].select()
		end)
		step("ask again", function() sp.ask:Click() end)
		step("slash minimap", function() SlashCmdList.POLESIMGEAR("minimap") SlashCmdList.POLESIMGEAR("minimap") end)
		-- close (the X), then the closed window's memory
		step("close", function() frame.close:Click() end)
		if frame:IsShown() then note("close", "still shown") end
		local kbVisit = kb()

		-- 6. the auction house pass: a fake browse server over the real shipped items the character can
		-- wear up to level + 2 (look ahead 2) that an auction can hold (not bind on pickup or quest
		-- items: shipped `bd` 1/4) and the scan's query asks for (common..epic: no Poor), one result per item (suffix items: every other one with a
		-- suffix of its own in the key, the rest without: the row stands for every suffix), a price from
		-- the item level and quality; pages of 50. The panel, a scan, its list (sorts, hovers, a click),
		-- the Gear Plan with prices, then the auction house closes.
		local ahInfo, ahTop = "not run", {}
		do
			local A = require("ahstub")
			local ahead = 2
			ns.Options.View().ahead = ahead
			local c = ns.Context.Get()
			local top = math.min(60, L + ahead)
			local pool = {}
			for _, ids in pairs(ns.Items.ByInv()) do
				for _, id in ipairs(ids) do
					local it = ns.Items.Peek(id)
					if it and (it.c == 2 or it.c == 4) and it.bd ~= 1 and it.bd ~= 4 and it.q >= 1 and it.q <= 4 and it.rl <= top and ns.Equip.CanUse(it, c.cls, math.max(L, it.rl)) then
						local suffix = (#it.sfx > 0 and id % 2 == 0) and it.sfx[1 + id % #it.sfx] or 0
						local price = math.floor((it.il * it.il * 25 + (id % 97) * 100) * (it.q + 1))
						pool[#pool + 1] = { c = it.c, sc = it.sc, inv = it.inv, rl = it.rl,
							r = { itemKey = { itemID = id, itemLevel = 0, itemSuffix = suffix, battlePetSpeciesID = 0 }, minPrice = price,
								totalQuantity = 1 + id % 3, containsOwnerItem = false } }
					end
				end
			end
			-- items the shipped table does not have (the client lists them too): not scored
			for i = 1, 5 do pool[#pool + 1] = { c = 4, sc = 1, inv = 5, rl = 1, r = A.result(990000 + i, 100) } end
			local function server(q)
				local out = {}
				for _, p in ipairs(pool) do
					local ok = p.rl >= (q.minLevel or 0) and p.rl <= (q.maxLevel or 60)
					local cls = false
					for _, f in ipairs(q.itemClassFilters or {}) do
						if f.classID == p.c and (f.subClassID == nil or f.subClassID == p.sc) and (f.inventoryType == nil or f.inventoryType == p.inv) then cls = true end
					end
					if ok and cls then out[#out + 1] = p.r end
				end
				table.sort(out, function(a, b) return a.minPrice < b.minPrice end)
				return out
			end
			local api, log = A.stub(server, 50)
			_G.C_AuctionHouse = api
			_G.AuctionHouseFrameDisplayMode = { Buy = { "BrowseResultsFrame" }, ItemBuy = { "ItemBuyFrame" } }
			_G.AuctionHouseSearchContext = { BuyItems = 9 }
			local ahf = U.new("Frame", _G.UIParent, "AuctionHouseFrame")
			ahf:SetSize(800, 540)
			ahf.BrowseResultsFrame, ahf.ItemBuyFrame = false, false
			function ahf:GetDisplayMode() return self.mode end
			function ahf:SelectBrowseResult(r) self.selected = r end
			-- the window built once and closed (as after the AH pass) before the baseline
			step("AH baseline", function() SlashCmdList.POLESIMGEAR("") frame.close:Click() end)
			local kbA = kb()
			local P = ns.AHPanel
			local t0 = clock()
			local ms, served
			step("AH load", ev, ns._frame, "ADDON_LOADED", "Blizzard_AuctionHouseUI")
			-- each answer is one client frame; then the scoring's frames (settle)
			frames, maxFrame = 0, 0
			step("AH scan", function()
				U.button(P.frame, "Scan for upgrades"):Click()
				for _ = 1, 10000 do
					local p = log.pending
					if not p then break end
					log.pending = nil
					local t = clock()
					ev(ns._frame, p == "updated" and "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or "AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
					maxFrame = math.max(maxFrame, (clock() - t) * 1000)
				end
			end)
			ms = (clock() - t0) * 1000
			local scoreFrames, longest = frames, maxFrame
			if ns.AH.Scanning() then note("AH scan", "not finished: " .. tostring(ns.AH.Status())) end
			local kbScan = kb()
			step("AH list", function()
				for _, s in ipairs(P.SORTS) do
					U.button(P.frame, s[2]):Click()
					scroll(P.list)
					hover(P.list, 5)
				end
				-- the Slot dropdown: every slot in the results, then All again
				local slots = P.SlotList()
				for i = 2, #slots do
					P.SetSlot(slots[i].value)
					for _, row in ipairs(U.rows(P.list, 50)) do
						assert(row.d.slot.key == slots[i].value, "slot filter shows only " .. slots[i].text)
					end
				end
				if #slots > 1 then print(string.format("  AH slot filter: %d slots (%s ... %s)", #slots - 1, slots[2].text, slots[#slots].text)) end
				P.SetSlot("all")
				U.button(P.frame, "Gain"):Click()
				local first = U.rows(P.list, 1)[1]
				if first then first:Click("LeftButton") assert(ahf.selected == first.d.result, "click selects the row's result") end
			end)
			step("AH plan", function()
				SlashCmdList.POLESIMGEAR("")
				Win.SetTab("plan")
				scroll(Win.Panel("plan").list)
				for _, b in ipairs(frame.slots) do b.scripts.OnEnter(b) b.scripts.OnLeave(b) end
				frame.close:Click()
			end)
			local function line(r)
				return format("%-38s %-8s %+6.1f  %8s  %+6.2f/g%s%s", (r.c.inst.name or "?"):sub(1, 38), r.slot.short or r.slot.label, r.gain,
					format("%.2fg", r.price / 10000), r.value, r.at and ("  lvl " .. r.at) or "", r.anySuffix and "  (any suffix)" or "")
			end
			do -- (no reference to the rows outlives this block: the closed measure is the addon's own)
				local byGain, byValue = ns.AH.Sort(ns.AH.Rows(), "gain"), ns.AH.Sort(ns.AH.Rows(), "value")
				ahTop[#ahTop + 1] = "  AH top 5 by gain:"
				for i = 1, math.min(5, #byGain) do ahTop[#ahTop + 1] = "    " .. line(byGain[i]) end
				ahTop[#ahTop + 1] = "  AH top 5 by value (gain per gold):"
				for i = 1, math.min(5, #byValue) do ahTop[#ahTop + 1] = "    " .. line(byValue[i]) end
			end
			local st = ns.AH.Status()
			step("AH close", ev, ns._frame, "AUCTION_HOUSE_CLOSED")
			if #ns.AH.Rows() ~= 0 or next(ns.AH.Found()) then note("AH close", "results kept after close") end
			local kbAClosed = kb()
			served = #pool
			ahInfo = format("%d queries, %d more-pages, %d items served; %s; scan+score %.0f ms (scoring over %d frames, longest frame %.1f ms); KB before %.0f, with results %.0f (%+.0f), closed %.0f (%+.0f); bought %d",
				#log.sent, log.more, served, tostring(st), ms or -1, scoreFrames, longest, kbA, kbScan, kbScan - kbA, kbAClosed, kbAClosed - kbA, log.bought)
			_G.C_AuctionHouse, _G.AuctionHouseFrame, _G.AuctionHouseFrameDisplayMode, _G.AuctionHouseSearchContext = nil, nil, nil, nil
		end

		-- 7. the loot pass: bags with one item at login, then a real shipped head piece the character
		-- can wear now that scores over the worn one is looted (a new GUID); the equip prompt shows
		-- above a stand-in Polestar guide window, its icon is hovered, Equip puts it on (the client's
		-- EquipItemByName recorded), the item goes on and the prompt closes; then Polestar's window hides
		-- and another loot asks at the prompt's own place.
		local lootInfo = "not run"
		do
			local c = ns.Context.Get()
			local bagsT, equips, LOC = { [0] = {} }, {}, {}
			for k, v in pairs(ns.Live.EQUIP_LOC) do LOC[v] = LOC[v] or k end
			LOC[5], LOC[13] = "INVTYPE_CHEST", "INVTYPE_WEAPON"
			local function rec(link) return ns.Items.Get(tonumber(link:match("item:(%d+)"))) end
			_G.C_Container = {
				GetContainerNumSlots = function(b) return bagsT[b] and 16 or 0 end,
				GetContainerItemInfo = function(b, s)
					local e = bagsT[b] and bagsT[b][s]
					return e and { hyperlink = e.link, itemID = tonumber(e.link:match("item:(%d+)")), stackCount = 1 } or nil
				end,
			}
			_G.ItemLocation = { CreateFromBagAndSlot = function(_, b, s) return { b = b, s = s } end,
				CreateFromEquipmentSlot = function(_, s) return { e = s } end }
			_G.C_Item = {
				DoesItemExist = function(l) return l.e == nil and bagsT[l.b] and bagsT[l.b][l.s] ~= nil end,
				GetItemGUID = function(l) return bagsT[l.b][l.s].guid end,
				GetItemInfoInstant = function(link)
					local r = rec(link)
					return r and r.id, nil, nil, r and LOC[r.inv] or "", 134400, r and r.c or 15, r and r.sc or 0
				end,
				GetItemInfo = function(link)
					local r = rec(link)
					if not r then return nil end
					return r.name, link, r.q, r.il, r.rl, nil, nil, 1, LOC[r.inv], r.icon, 0, r.c, r.sc
				end,
				EquipItemByName = function(link, slot) equips[#equips + 1] = { link, slot } end,
			}
			-- the best-scoring head piece the character can wear now
			local best, bestGain
			for _, id in ipairs(ns.Items.ByInv()[1] or {}) do
				local it = ns.Items.Peek(id)
				if it and it.rl <= L and ns.Equip.CanUse(it, c.cls, L) and #it.sfx == 0 then
					local up, gain = ns.Arrows.Verdict("item:" .. id)
					if up and (not bestGain or gain > bestGain) then best, bestGain = id, gain end
				end
			end
			local pf = U.new("Frame", _G.UIParent, "PolestarGuideFrame")
			pf:SetSize(340, 200)
			step("loot login", function()
				bagsT[0][1] = { link = "item:" .. (best or 0), guid = "Item-old" }
				ev(ns._frame, "PLAYER_ENTERING_WORLD", false, true)
			end)
			local P = ns.Prompt
			if P.Frame() and P.Frame():IsShown() then note("loot", "a prompt for the bags at login") end
			step("loot", function()
				assert(best, "no head upgrade in the shipped table")
				bagsT[0][2] = { link = "item:" .. best, guid = "Item-new" }
				ev(ns._frame, "BAG_UPDATE_DELAYED")
			end)
			local f = P.Frame()
			local shown = f and f:IsShown()
			if not shown then note("loot", "no prompt for " .. tostring(best)) end
			local rel, relPt
			if f then _, rel, relPt = f:GetPoint(1) end
			if shown and not (rel == pf and relPt == "TOP") then note("loot", "not above Polestar's window") end
			local text = shown and U.texts(f) or ""
			step("loot hover", function()
				f.icon.scripts.OnEnter(f.icon)
				f.icon.scripts.OnLeave(f.icon)
			end)
			step("loot equip", function() U.button(f, "Equip"):Click() end)
			if not (equips[1] and equips[1][1] == "item:" .. tostring(best) and equips[1][2] == 1) then
				note("loot", "EquipItemByName not called with the item and slot 1")
			end
			step("loot worn", function()
				U.equipped[1] = "item:" .. best
				bagsT[0][2] = nil
				ev(ns._frame, "PLAYER_EQUIPMENT_CHANGED", 1, true)
				ev(ns._frame, "BAG_UPDATE_DELAYED")
			end)
			if f and f:IsShown() then note("loot", "the prompt stayed after equipping") end
			step("loot away", function()
				pf:Hide()
				bagsT[0][3] = { link = "item:" .. best, guid = "Item-new2" }
				ev(ns._frame, "BAG_UPDATE_DELAYED")
				if f:IsShown() then
					local _, r2 = f:GetPoint(1)
					assert(r2 == _G.UIParent, "Polestar hidden: our own place")
					U.button(f, "Not now"):Click()
				end
			end)
			lootInfo = format("%s %+.1f; prompt %q; equip %s", tostring(best and ns.Items.Get(best).name), bestGain or 0,
				(text:gsub("\n", " | ")), equips[1] and (equips[1][1] .. " -> slot " .. equips[1][2]) or "none")
			U.equipped[1] = nil
			_G.C_Container, _G.ItemLocation, _G.C_Item, _G.PolestarGuideFrame = nil, nil, nil, nil
		end

		-- 8. recording on (Record.lua): 200 pulls through the client's events, then the handler cost per
		-- event (1000 each of a player cast, a creature death and an XP line in a pull) and the export
		local recInfo = "-"
		step("record", function()
			ns.Options.Set("record", true)
			ns.Options.Set("recAsked", true)
			W.time = 100
			local mobs = {}
			_G.UnitExists = function(u) return mobs[u] ~= nil or u == "player" end
			_G.UnitGUID = function(u) return mobs[u] and mobs[u].guid or (u == "player" and "Player-1-1" or nil) end
			_G.UnitCanAttack = function(_, u) return mobs[u] ~= nil end
			_G.UnitThreatSituation = function(_, u) return mobs[u] and 1 or nil end
			_G.UnitCreatureType = function(u) return mobs[u] and "Beast" or nil end
			_G.UnitAffectingCombat = function() return false end
			for i = 1, 200 do
				mobs.target = { guid = "Creature-0-1-0-1-" .. (400 + i % 9) .. "-" .. i }
				ev(ns._frame, "PLAYER_REGEN_DISABLED")
				ns.Record.Tick()
				ev(ns._frame, "UNIT_SPELLCAST_SUCCEEDED", "player", "c", 585)
				W.time = W.time + 15
				ev(ns._frame, "UNIT_DIED", mobs.target.guid)
				ev(ns._frame, "CHAT_MSG_COMBAT_XP_GAIN", "Wolf dies, you gain 55 experience.")
				ev(ns._frame, "PLAYER_REGEN_ENABLED")
				mobs.target = nil
				W.time = W.time + 25
				ns.Record.Tick()
				settle()
			end
			mobs.target = { guid = "Creature-0-1-0-1-448-1" }
			ev(ns._frame, "PLAYER_REGEN_DISABLED")
			local t = clock()
			for i = 1, 1000 do
				ev(ns._frame, "UNIT_SPELLCAST_SUCCEEDED", "player", "c", 585)
				ev(ns._frame, "UNIT_DIED", "Creature-0-1-0-1-999-" .. i)
				ev(ns._frame, "CHAT_MSG_COMBAT_XP_GAIN", "Wolf dies, you gain 55 experience.")
			end
			local us = (clock() - t) * 1e6 / 3000
			ev(ns._frame, "PLAYER_REGEN_ENABLED")
			settle()
			local parts = ns.RecordExport.Build()
			local doc, why = ns.RecordExport.Decode(table.concat(parts, "\n"))
			if not doc then error("export does not decode: " .. tostring(why)) end
			recInfo = format("%d pulls, %.1f us per event (3000 events), export %d chars, %d pull rows decoded", #doc.pulls.rows, us,
				#parts[1], #doc.pulls.rows)
			for _, k in ipairs({ "UnitExists", "UnitGUID", "UnitCanAttack", "UnitThreatSituation", "UnitCreatureType", "UnitAffectingCombat" }) do
				_G[k] = nil
			end
		end)
		local function n(k) return counts[k] or 0 end
		local bad = 0
		for _, w in ipairs(navs) do
			if not (w[1] == "PoleSimGear" and type(w[2]) == "number" and w[3] >= 0 and w[3] <= 1 and w[4] >= 0 and w[4] <= 1 and type(w[5]) == "string") then bad = bad + 1 end
		end
		if bad > 0 then note("waypoints", bad .. " outside a map (0-1) or without a title") end
		print(format("level %d: build %.0f ms over %d frames (longest %.1f ms); KB before %.0f, open %.0f, closed %.0f (%+.0f); after visiting, closed %.0f (%+.0f); waypoints %d (bad %d); errors %d",
			L, buildMs, buildFrames, buildMax, kb0, kbOpen, kbClosed, kbClosed - kb0, kbVisit, kbVisit - kb0, #navs, bad, #errors))
		print(format("  rows: plan now %d, +5 %d, all %d, wishlist %d; places dungeon %d quest %d crafted %d vendor %d; detail rows dungeon %d quest %d crafted %d vendor %d world %d; pick on %s",
			n("plan upgrades +0"), n("plan upgrades +5"), n("plan all +0"), n("plan wishlist +0"), n("places dungeon"), n("places quest"),
			n("places crafted"), n("places vendor"), n("rows dungeon"), n("rows quest"), n("rows crafted"), n("rows vendor"), n("rows world"),
			tostring(counts.picked)))
		print("  route: " .. routeInfo)
		print("  AH: " .. ahInfo)
		print("  loot: " .. lootInfo)
		print("  record: " .. recInfo)
		for _, l in ipairs(ahTop) do print(l) end
		for i = 1, math.min(10, #errors) do print("  " .. errors[i]) end
		if #errors > 0 then failures = failures + 1 end
		for i = #navs, 1, -1 do navs[i] = nil end
		fx.done()
	end
end
os.exit(failures == 0 and 0 or 1)
