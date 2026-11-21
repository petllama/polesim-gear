-- docs/CHECKLIST.md is what the user pastes in game: its /run lines must fit the chat box (255
-- characters) and name only addon functions and /psg commands that exist (no drift from the code).
local T = require("t")

local function read(path)
	local f = assert(io.open(path, "rb"))
	local s = f:read("*a")
	f:close()
	return s
end

local function sources()
	local all = {}
	local p = io.popen("ls PoleSimGear/*.lua")
	for f in p:lines() do all[#all + 1] = read(f) end
	p:close()
	return table.concat(all, "\n")
end

local function defined(src, mod, fn)
	local alias = src:match("\nns%." .. mod .. " = (%a%w*)\n") -- e.g. ns.Window = Win
	if not fn then return alias ~= nil end
	return alias ~= nil and (src:find("function " .. alias .. "%." .. fn .. "%(") ~= nil
		or src:find("\n" .. alias .. "%." .. fn .. " = ") ~= nil)
end

return {
	run_lines_fit_the_chat_box = function()
		local doc, n = read("docs/CHECKLIST.md"), 0
		for line in doc:gmatch("[^\n]+") do
			local cmd = line:match("^%s*(/run .*)$") or line:match("`(/run [^`]*)`")
			if cmd then
				n = n + 1
				T.ok(#cmd < 255, #cmd .. " characters: " .. cmd:sub(1, 60))
			end
		end
		T.ok(n >= 20, "/run lines found: " .. n)
	end,
	names_exist = function()
		local doc, src, n = read("docs/CHECKLIST.md"), sources(), 0
		for mod, fn in doc:gmatch("PoleSimGear%.(%u%w*)%.?(%u?%w*)") do
			n = n + 1
			T.ok(defined(src, mod, fn ~= "" and fn or nil), "PoleSimGear." .. mod .. (fn ~= "" and ("." .. fn) or ""))
		end
		T.ok(n >= 10, "addon names found: " .. n)
		for cmd in doc:gmatch("/psg (%l+)") do
			T.ok(src:find('ns%.Slash%("' .. cmd .. '"') ~= nil, "/psg " .. cmd)
		end
	end,
	one_checklist = function()
		local p = io.popen("ls docs")
		for f in p:lines() do T.ok(not f:match("^INGAME"), "folded into CHECKLIST.md: " .. f) end
		p:close()
	end,
}
