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
					print(format("  %d. %-10s %-38s %+6.1f (score %.1f)  %s", shown, e.def.label, r.c.inst.name or r.c.id,
						r.gain, r.c.score, table.concat(src, "; ")))
				end
			end
			-- the suggestions a near quest (upcoming guide quest within 2 levels) would change if every
			-- available quest were on the route (the fake guide has none yet): an upper bound
			local m, put = Win.state.model, {}
			for _, def in ipairs(ns.Browser.SLOTS) do
				for _, list in ipairs({ m.now[def.key] or {}, m.coming[def.key] or {} }) do
					for _, r in ipairs(list) do
						for _, s in ipairs(r.c.sources) do
							if s.questId and not s.route then s.route = { ahead = 1, guide = "all" }; put[#put + 1] = s end
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
					for _, it in ipairs(U.contextMenu or {}) do if it.text == "Back to suggestion" then back = it.fn end end
					assert(back, "Back to suggestion in the menu")
					U.contextMenu = nil -- (the stub keeps the last menu; the client lets it go when it closes)
					back(); settle()
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
		for i = 1, math.min(10, #errors) do print("  " .. errors[i]) end
		if #errors > 0 then failures = failures + 1 end
		for i = #navs, 1, -1 do navs[i] = nil end
		fx.done()
	end
end
os.exit(failures == 0 and 0 or 1)
