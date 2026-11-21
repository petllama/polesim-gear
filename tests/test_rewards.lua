local T = require("t")
local FILES = { "Core.lua", "Rewards.lua" }
return {
	pick = function()
		local R = T.addon(FILES).Rewards
		local best, up = R.Pick({ { index = 1, usable = true, gain = -1, score = 3 }, { index = 2, usable = true, gain = 2, score = 5 },
			{ index = 3, usable = false } })
		T.eq(best, 2); T.ok(up)
		best, up = R.Pick({ { index = 1, usable = true, gain = -3, score = 1 }, { index = 2, usable = true, gain = -1, score = 4 } })
		T.eq(best, 2); T.ok(not up)
		best = R.Pick({ { index = 1, usable = true, gain = 1, score = 3 }, { index = 2, usable = true, gain = 1, score = 4 } })
		T.eq(best, 2, "tie: higher score")
		best = R.Pick({ { index = 1, usable = true, gain = 1, score = 4 }, { index = 2, usable = true, gain = 1, score = 4 } })
		T.eq(best, 1, "full tie: the earlier choice")
		T.eq(R.Pick({ { index = 1, usable = false } }), nil)
		T.eq(R.Pick({ { index = 1, pending = true, usable = true, gain = 9 } }), nil, "wait for item data")
	end,
}
