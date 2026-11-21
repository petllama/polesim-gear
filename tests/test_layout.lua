-- The window's size: a larger default, a resize grip (bounds, saved per account with the position),
-- columns that reflow with the width, and no text cut at the default or the minimum size (the 0.2.0
-- screenshot: "Range...", "Main h...", "130...", "+30....", "Dunge...", "Necrology Ro...", weights).
local T = require("t")
local F = require("winfix")

local function resize(f, w, h)
	f:SetSize(w, h)
	f.scripts.OnSizeChanged(f, w, h)
end

-- The screenshot's rows (long names, wide numbers) as Gear Plan entries.
local function screenshotEntries(ns)
	local S = ns.Browser.SLOTS
	local function def(key) for _, d in ipairs(S) do if d.key == key then return d end end end
	local function inst(id, name, q) return { id = id, name = name, quality = q or 2, icon = "inv_misc_questionmark", stats = {} } end
	local rows = {
		{ "ranged", "Smoldering Wand", 130.4, "Firebelcher", 139.5, 11.85, "dungeon" },
		{ "mainhand", "Magician's Mantle", 6.1, "Abomination Skirt", 26.7, 9.33, "vendor" },
		{ "offhand", "Spidersilk Boots", 5.5, "Necrology Robes", 17.0, 5.47, "world" },
		{ "trinket", "Abomination Skirt", 11.2, "Magician's Mantle", 13.4, 11.2, "crafted" },
		{ "shoulder", "Necrology Robes", 99.9, "Spidersilk Boots", 99.9, 99.95, "quest" },
	}
	local out = {}
	for i, r in ipairs(rows) do
		local plan = { c = { inst = inst(900 + i, r[4], 3), sources = { { kind = r[7], text = "x" } } }, gain = r[5], base = r[6] }
		out[i] = { def = def(r[1]), worn = { inst = inst(800 + i, r[2]), score = r[3] }, entry = { plan = plan }, priority = i, index = i }
	end
	return out
end

local function showRows(fx)
	local ns, U = fx.ns, fx.U
	local p = ns.Window.Panel("plan")
	ns.Style.SetList(p.list, screenshotEntries(ns))
	return U.rows(p.list), p
end

-- x of a widget anchored by its LEFT (or TOPLEFT) point, from the last SetPoint
local function leftOf(w)
	local p = w.points[#w.points]
	return p and (type(p[2]) == "number" and p[2] or p[4])
end

local function noOverlap(row, list)
	-- the row's cells left to right: each ends before the next starts, the last inside the list
	local cells = {
		{ "star", leftOf(row.star), row.star.w }, { "badge", leftOf(row.badge), row.badge.w },
		{ "slot", leftOf(row.slotText), row.slotText.w },
	}
	if row.cur.name:IsVisible() then
		cells[#cells + 1] = { "cur", leftOf(row.cur), row.cur.w }
	else
		cells[#cells + 1] = { "cur icon", leftOf(row.cur), row.cur.icon.w }
	end
	for _, c in ipairs({ { "curScore", row.curScore }, { "plan", row.plan }, { "delta", row.delta }, { "pct", row.pct },
		{ "srcIcon", row.srcIcon }, { "kind", row.kind }, { "choose", row.choose } }) do
		cells[#cells + 1] = { c[1], leftOf(c[2]), c[2].w }
	end
	for i = 2, #cells do
		local a, b = cells[i - 1], cells[i]
		T.ok(a[2] + a[3] <= b[2], string.format("%s (%d+%d) overlaps %s (%d)", a[1], a[2], a[3], b[1], b[2]))
	end
	local last = cells[#cells]
	T.ok(last[2] + last[3] <= list.w, string.format("%s ends at %d, list %d", last[1], last[2] + last[3], list.w))
end

return {
	default_size_and_grip = function()
		local fx = F.load()
		local ns, U = fx.ns, fx.U
		local f = fx.open()
		T.eq(f.w, 980); T.eq(f.h, 600)
		T.eq(f.resizable, true)
		T.eq(f.bounds[1], 780); T.eq(f.bounds[2], 500)
		local grip = f.grip
		T.ok(grip and grip.normalTexture:find("SizeGrabber", 1, true), "the client's size grabber")
		T.eq(grip.points[1][1], "BOTTOMRIGHT")
		grip.scripts.OnMouseDown(grip, "LeftButton")
		T.eq(f.sizing, "BOTTOMRIGHT")
		f.points = { { "TOPLEFT", UIParent, "BOTTOMLEFT", 40, 700 } }
		resize(f, 1100, 650)
		grip.scripts.OnMouseUp(grip, "LeftButton")
		T.eq(f.sizing, nil)
		local w = PoleSimGearDB.window
		T.eq(w.w, 1100); T.eq(w.h, 650); T.eq(w.point, "TOPLEFT"); T.eq(w.x, 40)
		-- moving keeps the size
		f.bar.scripts.OnDragStop(f.bar)
		T.eq(PoleSimGearDB.window.w, 1100)
		-- reopen: the same frame, the same size
		f:Hide(); fx.open()
		T.eq(f.w, 1100)
		fx.done()
	end,
	size_restored_after_reload = function()
		local fx = F.load({ db = { window = { point = "CENTER", relPoint = "CENTER", x = 0, y = 0, w = 1050, h = 640 } } })
		local f = fx.open()
		T.eq(f.w, 1050); T.eq(f.h, 640)
		T.eq(fx.ns.Window.frame.content.w, 1050 - 154, "the content follows")
		fx.done()
		-- a saved size out of bounds (a smaller screen, an older save): clamped
		fx = F.load({ db = { window = { point = "CENTER", x = 0, y = 0, w = 300, h = 9000 } } })
		UIParent:SetSize(1600, 900)
		f = fx.open()
		T.eq(f.w, 780); T.eq(f.h, 900)
		UIParent:SetSize(0, 0)
		fx.done()
	end,
	columns_reflow_on_size_change = function()
		local fx = F.load()
		local ns = fx.ns
		local f = fx.open()
		local rows, p = showRows(fx)
		local before = rows[1].plan.name.w
		resize(f, 1200, 700)
		T.eq(f.content.w, 1200 - 154); T.eq(f.content.h, 700 - 230)
		T.eq(p.list.w, f.content.w - 10, "the list stretches"); T.eq(p.list.h, f.content.h - 20)
		T.ok(rows[1].plan.name.w > before, "rows in view take the new width without a redraw")
		T.eq(rows[1].delta.w, rows[2].delta.w)
		noOverlap(rows[1], p.list)
		-- the bottom strip follows the height, the weights card the right edge
		T.eq(leftOf(f.eq) , 12); T.eq(f.eq.points[#f.eq.points][5] or f.eq.points[#f.eq.points][3], -(700 - 100))
		T.eq(leftOf(f.wc) + f.wc.w, 1200 - 12)
		fx.done()
	end,
	nothing_cut_at_default_and_min = function()
		local fx = F.load()
		local ns, U = fx.ns, fx.U
		local f = fx.open()
		for _, size in ipairs({ { 980, 600 }, { 780, 500 } }) do
			resize(f, size[1], size[2])
			local rows, p = showRows(fx)
			local cut = U.overflows(f)
			T.eq(#cut, 0, size[1] .. "x" .. size[2] .. ": " .. table.concat(cut, ", "))
			for _, r in ipairs(rows) do noOverlap(r, p.list) end
			local head = U.texts(p.header)
			T.ok(not head:find("Priority", 1, true), "a narrow # column"); T.ok(head:find("#", 1, true))
			T.eq(rows[1].slotText.text, "Ranged"); T.eq(rows[2].slotText.text, "Main hand")
			T.eq(rows[1].curScore.text, "130.4"); T.eq(rows[1].delta.text, "+139.5"); T.eq(rows[1].pct.text, "+1177%")
			T.eq(rows[1].kind.text, "Dungeon")
			T.ok(rows[1].plan.name.text:find("Firebelcher", 1, true))
		end
		-- at the default size both item names show
		resize(f, 980, 600)
		local rows = showRows(fx)
		T.eq(rows[2].cur.name:IsVisible(), true, "current item name at the default size")
		fx.done()
	end,
	other_tabs_fit_and_stretch = function()
		local fx = F.load()
		local ns, U = fx.ns, fx.U
		local f = fx.open()
		for _, size in ipairs({ { 980, 600 }, { 780, 500 }, { 1300, 760 } }) do
			resize(f, size[1], size[2])
			for _, key in ipairs({ "slot", "sources", "weights", "settings" }) do
				local p = fx.tab(key)
				for _, box in ipairs({ p.list, p.groups, p.detail }) do
					if box and box.provided then U.rows(box, 12) end
				end
				local cut = {}
				for _, s in ipairs(U.overflows(p)) do cut[#cut + 1] = s end
				T.eq(#cut, 0, key .. " " .. size[1] .. ": " .. table.concat(cut, ", "))
			end
			local slot = ns.Window.Panel("slot")
			T.eq(slot.list.w, f.content.w - 10); T.eq(slot.list.h, f.content.h - 30)
			local src = ns.Window.Panel("sources")
			T.eq(src.detail.w + leftOf(src.detail) + 10, f.content.w, "the detail list takes the rest")
			T.eq(src.groups.h, f.content.h - 30)
			T.eq(ns.Window.Panel("weights").list.h, f.content.h - 66)
		end
		fx.done()
	end,
}
