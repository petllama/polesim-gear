-- The recorder's export (opt-in recording, Record.lua): the records summarised into one compact JSON
-- document, deflated (LibDeflate, zlib licence, Libs/LibDeflate) and printed with LibDeflate's
-- EncodeForPrint alphabet, then wrapped as
--
--   PSG1:<addon version>:<adler32 of the printed data, 8 hex>:<its length>:<part>/<parts>:<data>
--
-- one line per part (exports over PART_CHARS are split). The website (polesim.petllama.com/upload)
-- checks length and checksum (a cut-off paste fails), decodes it and answers with a 6-character
-- confirmation code, CodeFor(checksum): the addon computes the same code itself, so typing it in proves
-- the upload went through without any network access. A confirmed code deletes the blocks that export
-- carried; nothing is deleted otherwise (the storage cap aside).
local ADDON, ns = ...
local Export = {}
ns.RecordExport = Export

local floor, format, type, pairs, ipairs, tostring, concat = math.floor, string.format, type, pairs, ipairs, tostring, table.concat

Export.PART_CHARS = 100000
Export.FORMAT = 1
Export.KEEP_EXPORTS = 5

local function LD()
	return LibStub and LibStub("LibDeflate", true)
end

-- JSON ----------------------------------------------------------------------------------------------
-- Keys sorted, so the same document always gives the same text. Integers print with %.0f (never %d:
-- the client's %d takes 32-bit integers only).
local function numText(v)
	if v ~= v or v == math.huge or v == -math.huge then return "null" end
	if v == floor(v) and math.abs(v) < 2 ^ 53 then return format("%.0f", v) end
	local s = format("%.6f", v):gsub("0+$", ""):gsub("%.$", "")
	return s
end
local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
local function strText(s)
	return '"' .. s:gsub('[%c"\\]', function(c) return ESC[c] or format("\\u%04x", c:byte()) end) .. '"'
end
local function isArray(t)
	local n = #t
	for k in pairs(t) do
		if type(k) ~= "number" or k < 1 or k > n or k ~= floor(k) then return false end
	end
	return true
end
local function encode(v, out)
	local tv = type(v)
	if tv == "nil" then out[#out + 1] = "null"
	elseif tv == "boolean" then out[#out + 1] = v and "true" or "false"
	elseif tv == "number" then out[#out + 1] = numText(v)
	elseif tv == "string" then out[#out + 1] = strText(v)
	elseif tv == "table" then
		if isArray(v) then
			out[#out + 1] = "["
			for i = 1, #v do
				if i > 1 then out[#out + 1] = "," end
				encode(v[i], out)
			end
			out[#out + 1] = "]"
		else
			local keys, byText = {}, {}
			for k in pairs(v) do
				local s = tostring(k)
				keys[#keys + 1] = s
				byText[s] = k
			end
			table.sort(keys)
			out[#out + 1] = "{"
			for i, k in ipairs(keys) do
				if i > 1 then out[#out + 1] = "," end
				out[#out + 1] = strText(k)
				out[#out + 1] = ":"
				encode(v[byText[k]], out)
			end
			out[#out + 1] = "}"
		end
	end
end
function Export.Json(v)
	local out = {}
	encode(v, out)
	return concat(out)
end

-- A small JSON reader (the export's own documents: Decode, tests).
function Export.ParseJson(s)
	local i = 1
	local function ws() i = s:find("[^ \t\r\n]", i) or #s + 1 end
	local value
	local MAP = { n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f" }
	local function str()
		local out = {}
		i = i + 1
		while true do
			local c = s:sub(i, i)
			if c == "" then error("unterminated string") end
			if c == '"' then i = i + 1 break end
			if c == "\\" then
				local e = s:sub(i + 1, i + 1)
				if e == "u" then
					out[#out + 1] = string.char(tonumber(s:sub(i + 2, i + 5), 16) % 256)
					i = i + 6
				else
					out[#out + 1] = MAP[e] or e
					i = i + 2
				end
			else
				out[#out + 1] = c
				i = i + 1
			end
		end
		return concat(out)
	end
	value = function()
		ws()
		local c = s:sub(i, i)
		if c == "{" then
			local t = {}
			i = i + 1
			ws()
			if s:sub(i, i) == "}" then i = i + 1 return t end
			while true do
				ws()
				local k = str()
				ws()
				i = i + 1 -- :
				t[k] = value()
				ws()
				local d = s:sub(i, i)
				i = i + 1
				if d == "}" then return t end
			end
		elseif c == "[" then
			local t, n = {}, 0
			i = i + 1
			ws()
			if s:sub(i, i) == "]" then i = i + 1 return t end
			while true do
				n = n + 1
				t[n] = value()
				ws()
				local d = s:sub(i, i)
				i = i + 1
				if d == "]" then return t end
			end
		elseif c == '"' then return str()
		elseif s:sub(i, i + 3) == "true" then i = i + 4 return true
		elseif s:sub(i, i + 4) == "false" then i = i + 5 return false
		elseif s:sub(i, i + 3) == "null" then i = i + 4 return nil
		else
			local n = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
			if not n or n == "" then error("bad JSON at " .. i) end
			i = i + #n
			return tonumber(n)
		end
	end
	local okp, v = pcall(value)
	if not okp then return nil, v end
	return v
end

-- The summary ---------------------------------------------------------------------------------------
local function list(t, fmt1)
	local out = {}
	for _, v in ipairs(t or {}) do out[#out + 1] = fmt1(v) end
	return concat(out, ";")
end
local function n0(v) return v == nil and "" or numText(v) end

-- The summary of every stored block: one document (Export.Json gives its text).
-- pulls: column names + one row per pull; mobList "npc:level:type:caster;..." (caster 1 mana, 0 not,
-- -1 unknown), kills "npc:level:xp;...", casts "spell:count;..." (spells sorted), gap -1 for a
-- session's first pull, flags a (after a meal) d (died) s (some reads were secret).
-- drift (0.7.11): item data drift, one row per item + suffix (0 none) + stat key whose shipped value
-- differs from the client's (at most Record.DRIFT_MAX rows; the client build is the document's).
function Export.Summary()
	local r = ns.Record.Data()
	if not r or #r.blocks == 0 then return nil end
	local build, rev = nil, nil
	if GetBuildInfo then
		local okb, v, b = pcall(GetBuildInfo)
		if okb then build, rev = v, b end
	end
	local doc = { v = Export.FORMAT, addon = tostring(ns.version or "?"),
		build = build and (tostring(build) .. (rev and ("." .. tostring(rev)) or "")) or "",
		blocks = { r.blocks[1].id, r.blocks[#r.blocks].id }, chars = {}, sessions = {},
		pulls = { cols = { "sess", "start", "dur", "level", "mobs", "mobList", "kills", "casts", "gap", "flags" }, rows = {} },
		meals = { cols = { "sess", "start", "kind", "seconds", "aura", "interrupted" }, rows = {} },
		deaths = { cols = { "sess", "at", "level", "mobs", "mobLevels", "fight", "deadSeconds", "toNextPull" }, rows = {} },
		xp = { cols = { "sess", "at", "level", "xp", "xpMax", "rested", "why" }, rows = {} },
		pauses = { cols = { "sess", "start", "end", "afk" }, rows = {} },
		drift = { cols = { "sess", "at", "item", "suffix", "stat", "shipped", "live" }, rows = {} } }
	local lo, hi, active = nil, nil, 0
	local bySess, order = {}, {}
	local function level(l)
		if type(l) ~= "number" or l <= 0 then return end
		lo, hi = math.min(lo or l, l), math.max(hi or l, l)
	end
	for _, b in ipairs(r.blocks) do
		active = active + (b.a or 0)
		if not bySess[b.s] then
			bySess[b.s] = { b.s, 0 }
			order[#order + 1] = b.s
		end
		bySess[b.s][2] = bySess[b.s][2] + (b.a or 0)
		for _, c in ipairs(b.c) do
			doc.cls = doc.cls or c.cls
			doc.race = doc.race or c.race
			doc.spec = c.spec or doc.spec
			level(c.l)
			local row = {}
			for k, v in pairs(c) do row[k] = v end
			row.sess = b.s
			local sp, scr = {}, {}
			for s = 2, 7 do
				sp[s - 1] = c.sp and c.sp[s] or 0
				scr[s - 1] = c.scr and c.scr[s] or 0
			end
			row.sp, row.scr = sp, scr
			doc.chars[#doc.chars + 1] = row
		end
		for _, p in ipairs(b.p) do
			level(p.l)
			local ids = {}
			for id in pairs(p.c or {}) do ids[#ids + 1] = id end
			table.sort(ids)
			local casts = {}
			for _, id in ipairs(ids) do casts[#casts + 1] = numText(id) .. ":" .. numText(p.c[id]) end
			doc.pulls.rows[#doc.pulls.rows + 1] = { b.s, p.s, ns.Record.Round((p.e or p.s) - p.s, 1), p.l or 0, p.n or 0,
				list(p.m, function(m) return n0(m[1]) .. ":" .. n0(m[2]) .. ":" .. (m[3] or "") .. ":" .. n0(m[4]) end),
				list(p.k, function(k) return n0(k[1]) .. ":" .. n0(k[2]) .. ":" .. n0(k[3]) end),
				concat(casts, ";"), p.g == nil and -1 or p.g, p.f or "" }
		end
		for _, m in ipairs(b.m) do
			doc.meals.rows[#doc.meals.rows + 1] = { b.s, m.t, m.k or "", m.d or 0, m.a or 0, m.i or 0 }
		end
		for _, d in ipairs(b.d) do
			level(d.l)
			local ml = {}
			for i, v in ipairs(d.ml or {}) do ml[i] = numText(v) end
			doc.deaths.rows[#doc.deaths.rows + 1] = { b.s, d.t, d.l or 0, d.n or 0, concat(ml, ","), d.f or 0, d.r or -1, d.nx or -1 }
		end
		for _, x in ipairs(b.x) do
			level(x.l)
			doc.xp.rows[#doc.xp.rows + 1] = { b.s, x.t, x.l or 0, x.x or 0, x.mx or 0, x.r or 0, x.w or "" }
		end
		for _, k in ipairs(b.k) do
			doc.pauses.rows[#doc.pauses.rows + 1] = { b.s, k.s, k.e, k.afk or 0 }
		end
		for _, f in ipairs(type(b.f) == "table" and b.f or {}) do -- none in blocks saved by 0.7.10 and older
			if #doc.drift.rows < ns.Record.DRIFT_MAX then
				doc.drift.rows[#doc.drift.rows + 1] = { b.s, f.t or 0, f.i or 0, f.sx or 0, f.k or "", f.s or 0, f.v or 0 }
			end
		end
	end
	for _, s in ipairs(order) do
		doc.sessions[#doc.sessions + 1] = { bySess[s][1], ns.Record.Round(bySess[s][2], 1) }
	end
	doc.cls, doc.race, doc.spec = doc.cls or "", doc.race or "", doc.spec or ""
	doc.lv = { lo or 0, hi or 0 }
	doc.h = ns.Record.Round(active / 3600, 3)
	return doc
end

-- Checksums and the code ----------------------------------------------------------------------------
local function hex8(n) return format("%04x%04x", floor(n / 65536) % 65536, n % 65536) end
Export.Hex8 = hex8
function Export.Checksum(data)
	return hex8(LD():Adler32(data))
end
local CROCKFORD = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
local CODE_PRIME = 1073741789 -- < 2^30: h * 31 + 255 stays exact in a double
-- The confirmation code of an export: 6 characters (Crockford base 32) of a hash of its checksum.
-- The website computes the same (forever/web/upload.py code_for).
function Export.CodeFor(crc)
	local h = 0
	local s = "PSG1-OK:" .. tostring(crc):lower()
	for i = 1, #s do h = (h * 31 + s:byte(i)) % CODE_PRIME end
	local out = {}
	for i = 6, 1, -1 do
		local d = floor(h / 32 ^ (i - 1)) % 32
		out[#out + 1] = CROCKFORD:sub(d + 1, d + 1)
	end
	return concat(out)
end
-- A typed code made comparable: upper case, no spaces, O -> 0, I/L -> 1.
function Export.NormalCode(s)
	s = tostring(s or ""):upper():gsub("[%s%-]", ""):gsub("O", "0"):gsub("[IL]", "1")
	return s
end

-- Build and decode -----------------------------------------------------------------------------------
local function version()
	return (tostring(ns.version or "dev"):gsub("[^%w%.%-]", ""))
end

-- The export lines of a summary (default: everything stored) -> { part1, part2, ... }, checksum | nil
function Export.Build(doc)
	doc = doc or Export.Summary()
	if not doc then return nil end
	local lib = LD()
	-- level 9 costs ~40 ms for 4 h in plain Lua 5.1 but ~280 ms for 20 h: big summaries take level 5
	-- (~40 ms, a 20 % larger export)
	local json = Export.Json(doc)
	local data = lib:EncodeForPrint(lib:CompressDeflate(json, { level = #json <= 60000 and 9 or 5 }))
	local crc = Export.Checksum(data)
	local size = Export.PART_CHARS
	local n = math.max(1, math.ceil(#data / size))
	local parts = {}
	for i = 1, n do
		parts[i] = format("PSG1:%s:%s:%.0f:%d/%d:%s", version(), crc, #data, i, n, data:sub((i - 1) * size + 1, i * size))
	end
	return parts, crc
end

-- Export text (one or more lines) -> the document | nil, why
function Export.Decode(text)
	local parts, crc, len, total = {}, nil, nil, nil
	for line in tostring(text or ""):gmatch("[^\r\n]+") do
		line = line:gsub("^%s+", ""):gsub("%s+$", "")
		if line ~= "" then
			local c, l, i, n, data = line:match("^PSG1:[^:]*:(%x+):(%d+):(%d+)/(%d+):(.*)$")
			if not c then return nil, "not a PoleSim export (PSG1:...) or the start is cut off" end
			if (crc and c ~= crc) or (total and tonumber(n) ~= total) then return nil, "parts of different exports" end
			crc, len, total = c, tonumber(l), tonumber(n)
			parts[tonumber(i)] = data
		end
	end
	if not crc then return nil, "empty" end
	for i = 1, total do
		if not parts[i] then return nil, ("incomplete: part %d of %d is missing"):format(i, total) end
	end
	local data = concat(parts, "", 1, total)
	if #data ~= len then return nil, ("incomplete paste: %d of %d characters"):format(#data, len) end
	if Export.Checksum(data) ~= crc:lower() then return nil, "checksum mismatch: the paste was changed or cut" end
	local lib = LD()
	local raw = lib:DecodeForPrint(data)
	local json = raw and lib:DecompressDeflate(raw)
	if not json then return nil, "could not decompress" end
	return Export.ParseJson(json)
end

-- The exports made (newest last): { crc, last = the newest block id it carried, code }
local function exports()
	local r = ns.Record.Data()
	if not r then return {} end
	if type(r.exports) ~= "table" then r.exports = {} end
	return r.exports
end
function Export.Last()
	local e = exports()
	return e[#e]
end

-- Build the export of everything stored and remember it (its code clears these blocks). Recording goes
-- on into a new block. -> parts | nil
function Export.Export()
	local doc = Export.Summary()
	if not doc then return nil end
	local parts, crc = Export.Build(doc)
	local r = ns.Record.Data()
	r.cut = true
	local e = exports()
	if not (e[#e] and e[#e].crc == crc) then
		e[#e + 1] = { crc = crc, last = doc.blocks[2], code = Export.CodeFor(crc) }
		while #e > Export.KEEP_EXPORTS do table.remove(e, 1) end
	end
	return parts
end

-- The code the website showed -> ok, message. Deletes the blocks of that export (and older ones).
function Export.Confirm(code)
	code = Export.NormalCode(code)
	local e = exports()
	for i = #e, 1, -1 do
		local x = e[i]
		if x.code == code then
			local r = ns.Record.Data()
			local keep = {}
			for _, b in ipairs(r.blocks) do
				if b.id > x.last then keep[#keep + 1] = b end
			end
			r.blocks = keep
			for j = i, 1, -1 do table.remove(e, j) end
			r.since = 0
			r.askAt = ns.Record.AskSeconds()
			r.askEvery = r.askAt
			ns.Fire("RECORD_UPLOADED")
			return true, "Thanks! The uploaded records were removed from your SavedVariables."
		end
	end
	return false, "That code doesn't match this export. Check it on the website (6 characters)."
end
