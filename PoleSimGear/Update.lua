-- Update notices: addons can't go online, so PoleSim Gear learns of a newer release from other players'
-- PoleSim Gear on a hidden custom chat channel ("PoleSimGear"), with hidden addon messages that carry
-- our version number and nothing else ("hello 0.7.9" / "ver 0.7.9"): no names, gear or recordings.
--
-- The channel: JOIN_DELAY seconds after login, out of combat, outside instances and outside the
-- game's chat lockdown (else it tries again every RETRY seconds), PoleSim Gear joins the temporary
-- channel (JoinTemporaryChannel: not saved with the chat settings) without adding it to any chat
-- window, so no chat frame shows it (the client adds only regional channels by itself); a message
-- filter also drops its join/leave notices and any text in it, should a player add it to a window by
-- hand. With no free channel slot (MAX_CHANNELS taken) or a failed join it skips quietly this session.
-- On joining: one "hello <ours>" (at most once per HELLO_GAP, saved, so a /reload sends none). A member
-- on a NEWER version answers "ver <theirs>" after a random 2-10 s, unless someone said that version or
-- newer in the channel first, and at most once per REPLY_GAP (saved). Sends go through
-- C_ChatInfo.SendAddonMessage(prefix, text, "CHANNEL", number); any refused result (throttle,
-- lockdown) is dropped quietly.
-- Trust: a version counts only as a plain x.y.z newer than ours and at most one minor version ahead (or
-- the next major's x.0.z): a made-up "9.9.9" is dropped. Kept KEEP_DAYS days per account
-- (PoleSimGearDB.update = { peer, peerAt, helloAt, replyAt }).
-- Notice: one chat line per login (in combat it waits for the fight to end) and a line under the
-- window's title. No popup. Setting "shareVersion" (on by default) off = leave the channel, never join,
-- send nothing (and so hear nothing). A dev build ("dev") does nothing at all.
--
--   Update.Parse(v), .Compare(a, b), .Plausible(v), .Known() -> version, at | nil
--   Update.Heard(v), .Join(), .Leave(), .OnMessage(...), .Notify(), .NoticeText(), .Line(), .VersionText()
local ADDON, ns = ...
local Update = {}
ns.Update = Update

Update.PREFIX = "PoleSimGear"
Update.CHANNEL = "PoleSimGear"
Update.KEEP_DAYS = 7
Update.JOIN_DELAY = 20 -- seconds after login before joining
Update.JOIN_WAIT = 3 -- seconds for the join to land before reading the channel's number
Update.RETRY = 60 -- seconds between tries while in combat/an instance/the lockdown
Update.MAX_CHANNELS = 10 -- the client's channel slots
Update.HELLO_GAP = 1800 -- seconds between two hellos (saved)
Update.REPLY_GAP = 300 -- seconds between two answers (saved)
Update.NOTICE_DELAY = 10 -- seconds after login before the chat line
Update.RELEASES = "https://github.com/petllama/polesim-gear/releases/latest"

local DAY = 86400

-- Overridable in tests: the saved clock (seconds), a timer, the answer's wait.
function Update.Now() return time and time() or 0 end
function Update.After(s, fn) C_Timer.After(s, fn) end
function Update.ReplyDelay() return 2 + math.random() * 8 end

-- "0.7.9" -> { 0, 7, 9 }; nil for anything else ("dev", "0.7", "0.7.9-rc1", "1.2.3.4", 4-digit parts).
function Update.Parse(v)
	if type(v) ~= "string" or #v > 11 then return nil end
	local a, b, c = v:match("^(%d+)%.(%d+)%.(%d+)$")
	if not a then return nil end
	a, b, c = tonumber(a), tonumber(b), tonumber(c)
	if a > 999 or b > 999 or c > 999 then return nil end
	return { a, b, c }
end

-- -1, 0, 1 as a is older than, the same as, newer than b; nil when either does not parse.
function Update.Compare(a, b)
	local pa, pb = Update.Parse(a), Update.Parse(b)
	if not (pa and pb) then return nil end
	for i = 1, 3 do
		if pa[i] ~= pb[i] then return pa[i] > pb[i] and 1 or -1 end
	end
	return 0
end

-- Our version, when it is a release's (a dev build's is not).
local function mine()
	local v = tostring(ns.version or "")
	return Update.Parse(v) and v or nil
end

-- A heard version we believe: newer than ours and at most one minor version ahead (0.7.8 -> 0.7.x or
-- 0.8.x), or the next major's first minor (1.0.x).
function Update.Plausible(v)
	local m = mine()
	if not m or Update.Compare(v, m) ~= 1 then return false end
	local p, q = Update.Parse(v), Update.Parse(m)
	return (p[1] == q[1] and p[2] <= q[2] + 1) or (p[1] == q[1] + 1 and p[2] == 0)
end

local spare = {}
local function state()
	local db = ns.db or spare
	if type(db.update) ~= "table" then db.update = {} end
	return db.update
end

-- The newest believed release newer than ours, heard within KEEP_DAYS: version, at; else nil.
function Update.Known()
	local s = state()
	local v, at = s.peer, tonumber(s.peerAt)
	if type(v) ~= "string" or not at or not Update.Plausible(v) then return nil end
	if Update.Now() - at >= Update.KEEP_DAYS * DAY then return nil end
	return v, at
end

-- A version heard in the channel, noted when it counts. -> true when it counts
function Update.Heard(v)
	if not Update.Plausible(v) then return false end
	local s = state()
	local known = Update.Known()
	if known and Update.Compare(v, known) < 0 then return true end
	s.peer, s.peerAt = v, Update.Now()
	if not known or Update.Compare(v, known) > 0 then
		ns.Fire("UPDATE_KNOWN", v)
		Update.Notify()
	end
	return true
end

---------------------------------------------------------------------------
-- The channel
---------------------------------------------------------------------------

local function on() return ns.Options.Get("shareVersion") == true and mine() ~= nil end

local function lockdown()
	local C = C_ChatInfo
	if not (C and C.InChatMessagingLockdown) then return false end
	local ok, locked = pcall(C.InChatMessagingLockdown)
	return ok and locked == true
end

local function inInstance()
	if not IsInInstance then return false end
	local ok, inside = pcall(IsInInstance)
	return ok and inside == true
end

-- The channel's number while we are in it, else 0.
local function channelNumber()
	if not GetChannelName then return 0 end
	local ok, id = pcall(GetChannelName, Update.CHANNEL)
	return ok and type(id) == "number" and id or 0
end
Update.Number = channelNumber

-- How many channels the character is in (GetChannelList: number, name, disabled per channel).
local function channelCount()
	if not GetChannelList then return 0 end
	return math.floor(select("#", GetChannelList()) / 3)
end

local function registerPrefix()
	local C = C_ChatInfo
	if not (C and C.RegisterAddonMessagePrefix) then return end
	if C.IsAddonMessagePrefixRegistered and C.IsAddonMessagePrefixRegistered(Update.PREFIX) then return end
	pcall(C.RegisterAddonMessagePrefix, Update.PREFIX)
end

-- text into the channel. -> true when the client took it (any other result is dropped quietly).
function Update.Send(text)
	local n = channelNumber()
	if not on() or n == 0 or lockdown() or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false end
	registerPrefix()
	local ok, r = pcall(C_ChatInfo.SendAddonMessage, Update.PREFIX, text, "CHANNEL", tostring(n))
	if not ok then return false end
	local success = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success or 0
	return r == nil or r == true or r == success
end

-- "hello" once per HELLO_GAP.
function Update.Hello()
	local s = state()
	if Update.Now() - (tonumber(s.helloAt) or 0) < Update.HELLO_GAP then return false end
	if not Update.Send("hello " .. mine()) then return false end
	s.helloAt = Update.Now()
	return true
end

-- Join the channel when allowed (see the top), else try again later.
-- -> "joined" | "waiting" | "full" | "off" | "failed"
local gaveUp, waiting, joining = false, false, false
function Update.Join()
	if not on() then return "off" end
	if gaveUp then return "failed" end
	if channelNumber() > 0 then
		Update.Hello()
		return "joined"
	end
	if joining then return "waiting" end
	if (InCombatLockdown and InCombatLockdown()) or inInstance() or lockdown() then
		if not waiting then
			waiting = true
			Update.After(Update.RETRY, function()
				waiting = false
				Update.Join()
			end)
		end
		return "waiting"
	end
	if channelCount() >= Update.MAX_CHANNELS then
		gaveUp = true
		return "full"
	end
	local join = JoinTemporaryChannel or JoinChannelByName
	if not join then
		gaveUp = true
		return "failed"
	end
	registerPrefix()
	joining = true
	pcall(join, Update.CHANNEL) -- no chat window given: it shows in none
	Update.After(Update.JOIN_WAIT, function()
		joining = false
		if channelNumber() == 0 then
			gaveUp = true -- no slot, a password, a refusal: quietly not this session
			return
		end
		Update.Hello()
	end)
	return "joined"
end

local pending
function Update.Leave()
	pending = nil
	if channelNumber() > 0 and LeaveChannelByName then pcall(LeaveChannelByName, Update.CHANNEL) end
end

local function answer()
	if pending or not on() then return end
	local s = state()
	if Update.Now() - (tonumber(s.replyAt) or 0) < Update.REPLY_GAP then return end
	local me = {}
	pending = me
	Update.After(Update.ReplyDelay(), function()
		if pending ~= me then return end
		pending = nil
		if Update.Send("ver " .. mine()) then state().replyAt = Update.Now() end
	end)
end
function Update.Pending() return pending ~= nil end

local function secret(v) return v ~= nil and issecretvalue ~= nil and issecretvalue(v) and true or false end

local function ours(target, localID, name)
	local n = channelNumber()
	if n > 0 and localID == n then return true end
	local want = Update.CHANNEL:lower()
	for _, s in ipairs({ target or false, name or false }) do
		if type(s) == "string" and (s:lower() == want or s:lower():match("^%d+%. (.*)$") == want) then return true end
	end
	return false
end

-- CHAT_MSG_ADDON: only our prefix in our channel, "hello x.y.z" or "ver x.y.z"; everything else dropped.
-- Our own message comes back with our version: neither newer nor older.
function Update.OnMessage(prefix, text, channel, sender, target, zoneChannelID, localID, name)
	for _, v in ipairs({ prefix or false, text or false, channel or false, sender or false, target or false,
		localID or false, name or false }) do
		if secret(v) then return end
	end
	if prefix ~= Update.PREFIX or channel ~= "CHANNEL" or type(text) ~= "string" or #text > 20 then return end
	if not ours(target, localID, name) or not on() then return end
	local kind, v = text:match("^(%l+) (%d+%.%d+%.%d+)$")
	if (kind ~= "hello" and kind ~= "ver") or not Update.Parse(v) then return end
	local c = Update.Compare(v, mine())
	if c > 0 then Update.Heard(v) end
	if c < 0 then
		if kind == "hello" then answer() end
	else
		pending = nil -- someone said ours or newer: ours would add nothing
	end
end

-- Chat windows never show the channel: its notices and any text in it are dropped (it is in no window
-- unless a player adds it by hand). arg9 of the CHAT_MSG_CHANNEL* events is the channel's name.
function Update.Filter(_, _, ...)
	local base = select(9, ...)
	return type(base) == "string" and not secret(base) and base:lower() == Update.CHANNEL:lower()
end

---------------------------------------------------------------------------
-- Saying so
---------------------------------------------------------------------------

function Update.NoticeText()
	local v = Update.Known()
	if not v then return nil end
	return string.format("version %s is out (you have %s): download it from %s", v, mine(), Update.RELEASES)
end

-- The window's line under the title, or nil.
function Update.Line()
	local v = Update.Known()
	return v and ("Update available: " .. v) or nil
end

-- The chat line, once per login, never during combat (it waits for combat to end).
local told, waitCombat = false, false
function Update.Notify()
	if told or not ns.db then return false end
	local text = Update.NoticeText()
	if not text then return false end
	if InCombatLockdown and InCombatLockdown() then
		waitCombat = true
		return false
	end
	told, waitCombat = true, false
	ns.Print(text)
	return true
end

local function ago(s)
	if s < 3600 then return math.max(1, math.floor(s / 60)) .. " min ago" end
	if s < DAY then return math.floor(s / 3600) .. " h ago" end
	return math.floor(s / DAY) .. " days ago"
end

-- /psg version
function Update.VersionText()
	local lines = { "version " .. tostring(ns.version) }
	local v, at = Update.Known()
	if v then
		lines[#lines + 1] = string.format("newest known: %s, heard %s (%s)", v, ago(Update.Now() - at), Update.RELEASES)
	else
		lines[#lines + 1] = "no newer version heard of in the last " .. Update.KEEP_DAYS .. " days"
	end
	if not ns.Options.Get("shareVersion") then
		lines[#lines + 1] = "update notices: off (Settings): no channel, nothing sent"
	elseif channelNumber() > 0 then
		lines[#lines + 1] = "update notices: on, in the hidden " .. Update.CHANNEL .. " channel"
	else
		lines[#lines + 1] = "update notices: on, not in the channel (yet, or no free channel slot)"
	end
	return lines
end

ns.Slash("version", function()
	for _, l in ipairs(Update.VersionText()) do ns.Print(l) end
end)

local filtered = false
ns.RegisterEvent("PLAYER_LOGIN", function()
	registerPrefix()
	if not filtered and ChatFrame_AddMessageEventFilter then
		filtered = true
		for _, e in ipairs({ "CHAT_MSG_CHANNEL", "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER",
			"CHAT_MSG_CHANNEL_JOIN", "CHAT_MSG_CHANNEL_LEAVE" }) do
			ChatFrame_AddMessageEventFilter(e, Update.Filter)
		end
	end
	Update.After(Update.NOTICE_DELAY, Update.Notify)
	Update.After(Update.JOIN_DELAY, Update.Join)
end)
ns.RegisterEvent("CHAT_MSG_ADDON", Update.OnMessage)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
	if waitCombat then Update.Notify() end
end)
ns.On("OPTIONS", function(key, value)
	if key ~= "shareVersion" then return end
	if value then
		gaveUp = false
		Update.Join()
	else
		Update.Leave()
	end
end)
