-- Quest reward pick: at turn-in, mark the choice that is best for the character (our arrow and the
-- gain on the icon). Choices it cannot use are never picked.
local ADDON, ns = ...
local Rewards = {}
ns.Rewards = Rewards

-- choices = { { index, usable, gain, score, pending }, ... } -> best index | nil, is an upgrade
-- Best: the largest gain; ties: the higher score, then the earlier choice. Nothing while any choice's
-- item data is still pending.
function Rewards.Pick(choices)
	local best
	for _, c in ipairs(choices) do
		if c.pending then return nil end
		if c.usable then
			if not best or c.gain > best.gain + 1e-9 or (math.abs(c.gain - best.gain) <= 1e-9 and c.score > best.score + 1e-9) then
				best = c
			end
		end
	end
	if not best then return nil end
	return best.index, best.gain > 1e-6
end
