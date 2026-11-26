-- Update notices (Update.lua): versions, trust, joining the hidden channel (no chat window, notices
-- filtered, slots, combat/instance waits), the hello/answer flow between simulated players over a fake
-- channel, suppression, throttles, the setting, the once-a-login notice and expiry.
local T = require("t")
local FILES = { "Core.lua", "Options.lua", "Update.lua" }

-- T.addon runs wow.install, which resets C_Timer/GetTime: load the players first, then the network.
-- Each player has its own channel membership; timers and sends remember whose they are.
local function setup(versions, dbs)
	local P = {}
	for i, v in ipairs(versions) do
		local ns = T.addon(FILES)
		ns.version = v
		local printed = {}
		ns.printed = printed
		ns.Print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end
		_G.PoleSimGearDB, _G.PoleSimGearCharDB = (dbs and dbs[i]) or {}, {}
		ns._frame.scripts.OnEvent(ns._frame, "ADDON_LOADED", "PoleSimGear")
		P[i] = { ns = ns, name = v, channels = {}, delay = 5 }
		ns.Update.ReplyDelay = function() return P[i].delay end
	end
	local N = { t = 0, timers = {}, peers = P, sent = {}, current = P[1], joins = {}, filters = {} }
	local function cur() return N.current end
	_G.time = function() return 1000000000 + math.floor(N.t) end
	_G.C_Timer = { After = function(d, fn) N.timers[#N.timers + 1] = { at = N.t + d, fn = fn, owner = N.current } end }
	_G.Enum = { SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3 } }
	_G.InCombatLockdown = function() return cur().combat == true end
	_G.IsInInstance = function() return cur().instance == true end
	_G.GetChannelName = function(name)
		for i, c in ipairs(cur().channels) do if c:lower() == name:lower() then return i, c end end
		return 0
	end
	_G.GetChannelList = function()
		local out = {}
		for i, c in ipairs(cur().channels) do out[#out + 1] = i; out[#out + 1] = c; out[#out + 1] = false end
		return unpack(out)
	end
	_G.JoinTemporaryChannel = function(name, password, frameId)
		N.joins[#N.joins + 1] = { who = cur(), name = name, frameId = frameId }
		if not N.refuse then table.insert(cur().channels, name) end
		return 1, name
	end
	_G.LeaveChannelByName = function(name)
		for i, c in ipairs(cur().channels) do if c == name then table.remove(cur().channels, i) break end end
	end
	_G.ChatFrame_AddMessageEventFilter = function(e, fn) N.filters[e] = fn end
	_G.C_ChatInfo = {
		RegisterAddonMessagePrefix = function(p) N.prefix = p return 0 end,
		IsAddonMessagePrefixRegistered = function(p) return N.prefix == p end,
		InChatMessagingLockdown = function() return cur().lockdown == true end,
		SendAddonMessage = function(prefix, text, chatType, target)
			if N.result then return N.result end
			local me = cur()
			local name = me.channels[tonumber(target)]
			if chatType ~= "CHANNEL" or not name then return 7 end -- InvalidChannel
			N.sent[#N.sent + 1] = { from = me, text = text, chatType = chatType, target = target }
			for _, p in ipairs(P) do -- everyone in the channel hears it, the sender too
				local idx
				for i, c in ipairs(p.channels) do if c == name then idx = i end end
				if idx then
					local before = N.current
					N.current = p
					p.ns._frame.scripts.OnEvent(p.ns._frame, "CHAT_MSG_ADDON", prefix, text, "CHANNEL", "Someone",
						name, 0, idx, name, 0)
					N.current = before
				end
			end
			return 0
		end,
	}
	function N.run(seconds)
		local stop = N.t + seconds
		while true do
			local best, bi
			for i, tm in ipairs(N.timers) do
				if tm.at <= stop and (not best or tm.at < best.at) then best, bi = tm, i end
			end
			if not best then break end
			table.remove(N.timers, bi)
			N.t = math.max(N.t, best.at)
			local before = N.current
			N.current = best.owner
			best.fn()
			N.current = before
		end
		N.t = stop
	end
	function N.event(p, e, ...)
		local before = N.current
		N.current = p
		p.ns._frame.scripts.OnEvent(p.ns._frame, e, ...)
		N.current = before
	end
	function N.by(p)
		local out = {}
		for _, s in ipairs(N.sent) do if s.from == p then out[#out + 1] = s.text end end
		return out
	end
	-- a message from someone outside the test's players, into p's view of the channel
	function N.hear(p, text)
		local before = N.current
		N.current = p
		local idx = _G.GetChannelName("PoleSimGear")
		N.current = before
		N.event(p, "CHAT_MSG_ADDON", "PoleSimGear", text, "CHANNEL", "Stranger", "PoleSimGear", 0, idx, "PoleSimGear", 0)
	end
	return N, P
end

return {
	parse_and_compare = function()
		local N, P = setup({ "0.7.8" })
		local U = P[1].ns.Update
		T.eq(U.Parse("0.7.9")[3], 9)
		for _, bad in ipairs({ "dev", "0.7", "0.7.9-rc1", "1.2.3.4", "0.7.9 ", "a.b.c", "1000.0.0", "", "0.7.99999" }) do
			T.eq(U.Parse(bad), nil, bad)
		end
		T.eq(U.Parse(nil), nil); T.eq(U.Parse(7), nil)
		T.eq(U.Compare("0.7.10", "0.7.9"), 1, "numeric, not text"); T.eq(U.Compare("0.7.8", "0.7.8"), 0)
		T.eq(U.Compare("0.6.99", "0.7.0"), -1); T.eq(U.Compare("x", "0.7.0"), nil)
	end,
	-- at most one minor version ahead (or the next major's x.0): a made-up 9.9.9 is dropped
	one_minor_ahead = function()
		local N, P = setup({ "0.7.8" })
		local U = P[1].ns.Update
		T.eq(U.Plausible("0.7.9"), true); T.eq(U.Plausible("0.7.30"), true); T.eq(U.Plausible("0.8.4"), true)
		T.eq(U.Plausible("0.9.0"), false, "two minors ahead"); T.eq(U.Plausible("9.9.9"), false)
		T.eq(U.Plausible("1.0.2"), true, "the next major's first minor"); T.eq(U.Plausible("1.1.0"), false)
		T.eq(U.Plausible("0.7.8"), false, "ours"); T.eq(U.Plausible("0.7.7"), false, "older")
		T.eq(U.Heard("9.9.9"), false); T.eq(U.Known(), nil)
		P[1].ns.version = "dev"
		T.eq(U.Plausible("0.7.9"), false, "a dev build trusts nothing")
	end,
	-- login: the channel is joined after JOIN_DELAY into no chat window, its chatter is filtered, one hello
	join_hidden_and_hello = function()
		local N, P = setup({ "0.7.9" })
		local p = P[1]
		N.event(p, "PLAYER_LOGIN")
		T.eq(N.prefix, "PoleSimGear")
		N.run(p.ns.Update.JOIN_DELAY - 1)
		T.eq(#N.joins, 0, "not at once")
		N.run(10)
		T.eq(#N.joins, 1); T.eq(N.joins[1].name, "PoleSimGear"); T.eq(N.joins[1].frameId, nil, "no chat window")
		T.eq(table.concat(N.by(p), ","), "hello 0.7.9")
		T.eq(N.sent[1].chatType, "CHANNEL"); T.eq(N.sent[1].target, "1")
		for _, e in ipairs({ "CHAT_MSG_CHANNEL", "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER" }) do
			local f = N.filters[e]
			T.ok(f, e)
			T.eq(f(nil, e, "YOU_CHANGED", "", "", "1. PoleSimGear", "", "", 0, 1, "PoleSimGear"), true, e .. " hidden")
			T.eq(f(nil, e, "hi", "Bob", "", "2. Trade", "", "", 0, 2, "Trade"), false, "other channels shown")
		end
		-- a /reload: still in the channel, no second hello within 30 min
		N.event(p, "PLAYER_LOGIN")
		N.run(60)
		T.eq(#N.joins, 1, "already in it"); T.eq(#N.by(p), 1, "no second hello")
		N.t = N.t + p.ns.Update.HELLO_GAP
		N.event(p, "PLAYER_LOGIN")
		N.run(60)
		T.eq(#N.by(p), 2, "after 30 min")
	end,
	-- in combat / an instance / the lockdown it waits; no free slot or a refused join: quietly nothing
	join_waits_and_slots = function()
		local N, P = setup({ "0.7.9" })
		local p = P[1]
		p.combat = true
		N.event(p, "PLAYER_LOGIN")
		N.run(60)
		T.eq(#N.joins, 0, "in combat")
		p.combat, p.instance = false, true
		N.run(60)
		T.eq(#N.joins, 0, "in an instance")
		p.instance, p.lockdown = false, true
		N.run(60)
		T.eq(#N.joins, 0, "chat lockdown")
		p.lockdown = false
		N.run(60)
		T.eq(#N.joins, 1, "joined once allowed"); T.eq(#N.by(p), 1)
		local N2, P2 = setup({ "0.7.9" })
		P2[1].channels = { "General", "Trade", "LocalDefense", "LookingForGroup", "a", "b", "c", "d", "e", "f" }
		N2.event(P2[1], "PLAYER_LOGIN")
		N2.run(120)
		T.eq(#N2.joins, 0, "10 channels: no slot, skipped"); T.eq(#N2.sent, 0)
		local N3, P3 = setup({ "0.7.9" })
		N3.refuse = true
		N3.event(P3[1], "PLAYER_LOGIN")
		N3.run(300)
		T.eq(#N3.joins, 1, "a refused join is not retried this session"); T.eq(#N3.sent, 0)
		T.ok(table.concat(P3[1].ns.Update.VersionText(), "\n"):find("not in the channel", 1, true))
	end,
	-- An older player's hello: of two newer members exactly one answers, the old one learns the version
	-- and gets one chat line; nobody sends anything but a version.
	hello_answer_suppression = function()
		local N, P = setup({ "0.7.8", "0.7.9", "0.7.9" })
		local old, a, b = P[1], P[2], P[3]
		a.delay, b.delay = 3, 7
		N.event(a, "PLAYER_LOGIN"); N.event(b, "PLAYER_LOGIN")
		N.run(100)
		T.eq(table.concat(N.by(b), ","), "hello 0.7.9", "same versions answer nothing")
		T.eq(#N.by(a), 1)
		N.event(old, "PLAYER_LOGIN")
		N.run(60)
		T.eq(table.concat(N.by(old), ","), "hello 0.7.8")
		T.eq(table.concat(N.by(a), ","), "hello 0.7.9,ver 0.7.9", "a answers")
		T.eq(#N.by(b), 1, "b heard a's answer and held back")
		for _, s in ipairs(N.sent) do T.ok(s.text:match("^%l+ %d+%.%d+%.%d+$"), "only a version: " .. s.text) end
		T.eq(old.ns.Update.Known(), "0.7.9")
		T.eq(#old.ns.printed, 1, "one chat line")
		T.ok(old.ns.printed[1]:find("version 0.7.9 is out (you have 0.7.8)", 1, true), old.ns.printed[1])
		T.ok(old.ns.printed[1]:find("github.com/petllama/polesim-gear/releases/latest", 1, true))
		T.eq(#a.ns.printed, 0); T.eq(a.ns.Update.Known(), nil, "the newer ones learn nothing")
		T.eq(old.ns.Update.Line(), "Update available: 0.7.9"); T.eq(a.ns.Update.Line(), nil)
	end,
	-- answers: once per 5 min, only to hellos, dropped on the client's throttle without spending the gap
	answer_throttles = function()
		local N, P = setup({ "0.7.9" })
		local p = P[1]
		local U = p.ns.Update
		N.event(p, "PLAYER_LOGIN")
		N.run(60)
		T.eq(#N.by(p), 1, "hello")
		N.hear(p, "hello 0.7.8"); N.run(15)
		T.eq(#N.by(p), 2, "answered")
		N.hear(p, "hello 0.7.8"); N.run(15)
		T.eq(#N.by(p), 2, "not again within 5 min")
		N.t = N.t + U.REPLY_GAP
		N.hear(p, "ver 0.7.7"); N.run(15)
		T.eq(#N.by(p), 2, "an older answer is not a question")
		for _, m in ipairs({ "hello", "hello 0.7", "hi 0.7.1", "hello 0.7.1 x", "hello 0.7.1|x" }) do N.hear(p, m) end
		N.event(p, "CHAT_MSG_ADDON", "PoleSimGear", "hello 0.7.1", "GUILD", "X", "", 0, 0, "", 0)
		N.event(p, "CHAT_MSG_ADDON", "Other", "hello 0.7.1", "CHANNEL", "X", "PoleSimGear", 0, 1, "PoleSimGear", 0)
		N.event(p, "CHAT_MSG_ADDON", "PoleSimGear", "hello 0.7.1", "CHANNEL", "X", "Trade", 0, 2, "Trade", 0)
		N.run(15)
		T.eq(#N.by(p), 2, "garbage, other prefixes and channels dropped")
		N.result = 3 -- AddonMessageThrottle
		N.hear(p, "hello 0.7.1"); N.run(15)
		N.result = nil
		N.hear(p, "hello 0.7.1"); N.run(15)
		T.eq(table.concat(N.by(p), ","), "hello 0.7.9,ver 0.7.9,ver 0.7.9", "answered once the throttle let it")
	end,
	-- Settings off: never joins, sends nothing; turning it off leaves the channel, on joins again
	setting_off = function()
		local N, P = setup({ "0.7.9" }, { { options = { shareVersion = false } } })
		local p = P[1]
		N.event(p, "PLAYER_LOGIN")
		N.run(120)
		T.eq(#N.joins, 0); T.eq(#N.sent, 0)
		N.hear(p, "hello 0.7.8"); N.run(15)
		T.eq(#N.sent, 0, "no answer")
		T.ok(table.concat(p.ns.Update.VersionText(), "\n"):find("off", 1, true))
		p.ns.Options.Set("shareVersion", true)
		N.run(10)
		T.eq(#N.joins, 1, "on: joins"); T.eq(#N.by(p), 1)
		p.ns.Options.Set("shareVersion", false)
		T.eq(#p.channels, 0, "off: left the channel")
		local N2, P2 = setup({ "0.7.8" })
		T.eq(P2[1].ns.Options.Get("shareVersion"), true, "on by default")
	end,
	-- the chat line: once per login, waits for combat to end
	notice_once_and_not_in_combat = function()
		local N, P = setup({ "0.7.8" })
		local p = P[1]
		local U = p.ns.Update
		p.combat = true
		U.Heard("0.7.9")
		T.eq(#p.ns.printed, 0, "in combat: later")
		p.combat = false
		N.event(p, "PLAYER_REGEN_ENABLED")
		T.eq(#p.ns.printed, 1)
		U.Heard("0.7.10")
		N.event(p, "PLAYER_LOGIN")
		N.run(60)
		T.eq(#p.ns.printed, 1, "once per login")
		T.eq(U.Known(), "0.7.10", "the newer one is kept")
		U.Heard("0.7.9")
		T.eq(U.Known(), "0.7.10", "an older one does not replace it")
		local lines = table.concat(U.VersionText(), "\n")
		T.ok(lines:find("version 0.7.8", 1, true) and lines:find("newest known: 0.7.10", 1, true), lines)
		-- the next login says it once again
		local N2, P2 = setup({ "0.7.8" }, { { update = { peer = "0.7.9", peerAt = 1000000000 } } })
		N2.event(P2[1], "PLAYER_LOGIN")
		N2.run(60)
		T.eq(#P2[1].ns.printed, 1)
		-- updated to it: nothing to say
		local N3, P3 = setup({ "0.7.9" }, { { update = { peer = "0.7.9", peerAt = 1000000000 } } })
		N3.event(P3[1], "PLAYER_LOGIN")
		N3.run(60)
		T.eq(#P3[1].ns.printed, 0); T.eq(P3[1].ns.Update.Line(), nil)
	end,
	expires_after_7_days = function()
		local N, P = setup({ "0.7.8" })
		local U = P[1].ns.Update
		U.Heard("0.7.9")
		N.t = N.t + 7 * 86400 - 10
		T.eq(U.Known(), "0.7.9")
		N.t = N.t + 20
		T.eq(U.Known(), nil, "kept 7 days")
		T.eq(U.Line(), nil)
	end,
	secret_values = function()
		local N, P = setup({ "0.7.8" })
		local p = P[1]
		N.event(p, "PLAYER_LOGIN")
		N.run(30)
		_G.issecretvalue = function(v) return v == "ver 0.7.9" end
		N.hear(p, "ver 0.7.9")
		T.eq(p.ns.Update.Known(), nil, "a secret value is not read")
		_G.issecretvalue = nil
		N.hear(p, "ver 0.7.9")
		T.eq(p.ns.Update.Known(), "0.7.9")
	end,
	slash_version = function()
		local N, P = setup({ "0.7.8" })
		SlashCmdList.POLESIMGEAR("version")
		T.ok(P[1].ns.printed[1]:find("version 0.7.8", 1, true), P[1].ns.printed[1])
		T.ok(P[1].ns.printed[2]:find("no newer version", 1, true))
	end,
}
