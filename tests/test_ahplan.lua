-- The Gear Plan while the auction house is open with scan results (session only): plan rows whose item
-- is for sale say "AH: <price>"; a scan upgrade beating a slot's plan shows in the equipped strip's
-- tooltip as "AH: <item> +N (<price>)"; all gone when the auction house closes.
local T = require("t")
local F = require("winfix")
local A = require("ahstub")

local function fire(ns, e, ...) ns._frame.scripts.OnEvent(ns._frame, e, ...) end

local function setup(results, opts)
	local fx = F.load(opts)
	local api, log = A.stub(results, 50)
	_G.C_AuctionHouse = api
	fx.api, fx.log = api, log
	function fx.scan()
		fx.ns.AH.Scan()
		for _ = 1, 50 do
			if not log.pending then break end
			log.pending = nil
			fire(fx.ns, "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
		end
	end
	function fx.cleanup() _G.C_AuctionHouse = nil fx.done() end
	return fx
end

-- the Gear Plan's first row with a plan item the AH scan scores (a fresh fixture, window open; the
-- hand-made Codex's craft/drop sources keep level-less items of any item level in the plan)
local function firstPlan()
	local fx = F.load()
	fx.open()
	for _, e in ipairs(fx.ns.TabPlan.Entries()) do
		local r = fx.ns.TabPlan.PlanRow(e)
		if r and not fx.ns.LevelLessGate(fx.ns.Items.Get(r.c.inst.id), 20) then
			local inst = r.c.inst
			fx.done()
			return e.def, inst, r.gain
		end
	end
	fx.done()
end

return {
	plan_row_says_ah_price = function()
		local def, inst = firstPlan()
		T.ok(def, "a planned slot")
		local fx = setup({ A.result(inst.id, 12345, inst.bonus or 0) })
		local ns, U = fx.ns, fx.U
		fx.open()
		local p = fx.tab("plan")
		local function planSub()
			for _, row in ipairs(U.rows(p.list)) do
				if row.e and row.e.def == def or (row.e and row.e.def and row.e.def.key == def.key) then return row.plan.sub.text or "" end
			end
		end
		T.ok(not planSub():find("AH:", 1, true), "no scan yet")
		fx.scan()
		T.eq(ns.AH.PriceOf(inst), 12345)
		T.ok(planSub():find("AH: 12345c", 1, true), planSub())
		fire(ns, "AUCTION_HOUSE_CLOSED")
		T.eq(ns.AH.PriceOf(inst), nil, "session only")
		T.ok(not planSub():find("AH:", 1, true), "gone on close")
		fx.cleanup()
	end,
	-- An AH upgrade bigger than a slot's plan (a BoE/world item, a kind the default source filters leave
	-- out of the plan): that slot's strip tooltip names it with its gain and price. The plan is the
	-- player's pick of the slot's weakest row (the hand-made Codex's craft/drop sources put level-less
	-- items of any item level at the top of the suggestions, which the AH rightly leaves out).
	strip_tooltip_names_a_better_ah_item = function()
		local fx0 = F.load()
		local ns0 = fx0.ns
		fx0.open()
		local ctx = ns0.Context.Get()
		local pick
		for _, e in ipairs(ns0.TabPlan.Entries()) do
			local low = e.rows and e.rows[#e.rows]
			if low and e.def.invs and e.def.key ~= "finger" and e.def.key ~= "trinket" then
				for _, inv in ipairs(e.def.invs) do
					for _, id in ipairs(ns0.Items.ByInv()[inv] or {}) do
						local it = ns0.Items.Get(id)
						if id % 5 == 4 and it.rl <= 20 and not ns0.LevelLessGate(it, 20) and #it.sfx == 0 and ns0.Equip.CanUse(it, "priest", 20) then
							local g = ns0.Score.Score(ns0.Score.Instance(it), ctx.w, "priest", "gear") - (e.worn and e.worn.score or 0)
							if g > low.gain + 0.5 and (not pick or g - low.gain > pick[3]) then
								pick = { id, g, g - low.gain, e.def.slot, e.def.key, ns0.Browser.KeyOf(low.c.inst) }
							end
						end
					end
				end
			end
		end
		fx0.done()
		T.ok(pick, "a world drop better than a slot's plan")
		local fx = setup({ A.result(pick[1], 4200) }, { char = { plan = { shadow = { [pick[5]] = pick[6] } } } })
		local ns, U = fx.ns, fx.U
		local f = fx.open()
		fx.scan()
		ns.Window.Refresh()
		local btn
		for _, b in ipairs(f.slots) do if b.slot == pick[4] then btn = b end end
		btn.scripts.OnEnter(btn)
		local lines = table.concat(U.tip.lines, "\n")
		local name = ns.Items.Get(pick[1]).name
		T.ok(lines:find("AH: " .. name .. " " .. ns.Style.Signed(pick[2]) .. " (4200c)", 1, true), lines)
		fire(ns, "AUCTION_HOUSE_CLOSED")
		btn.scripts.OnEnter(btn)
		T.ok(not table.concat(U.tip.lines, "\n"):find("AH:", 1, true), "gone on close")
		fx.cleanup()
	end,
}
