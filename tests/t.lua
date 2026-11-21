-- Tiny test helpers. A test file returns { name = function() ... end }.
local T = { passed = 0, failed = 0 }

function T.eq(got, want, msg)
	if got ~= want then error(string.format("%s: want %s, got %s", msg or "eq", tostring(want), tostring(got)), 2) end
end

function T.near(got, want, eps, msg)
	eps = eps or 1e-6
	if type(got) ~= "number" or math.abs(got - want) > eps then
		error(string.format("%s: want %.10g, got %s", msg or "near", want, tostring(got)), 2)
	end
end

function T.ok(v, msg)
	if not v then error(msg or "expected a true value", 2) end
end

-- A fresh addon table with these files (under PoleSimGear/) loaded, as the client loads them.
function T.addon(files)
	require("wow").install()
	local ns = {}
	for _, f in ipairs(files) do
		local chunk = assert(loadfile("PoleSimGear/" .. f))
		chunk("PoleSimGear", ns)
	end
	return ns
end

function T.file(path)
	local cases = assert(loadfile(path))()
	local names = {}
	for name in pairs(cases) do names[#names + 1] = name end
	table.sort(names)
	for _, name in ipairs(names) do
		local ok, err = pcall(cases[name])
		if ok then
			T.passed = T.passed + 1
		else
			T.failed = T.failed + 1
			print("FAIL " .. path .. " " .. name .. ": " .. tostring(err))
		end
	end
end

return T
