--[[ Need Before Greed - Comm/Leaderboard.lua
	The SHARED DAILY LEADERBOARD: the best scores anyone has made in each day's daily run, passed between
	Need Before Greed players and checked by replaying the run before an entry counts. Only the daily run is
	shared: everyone plays it with the same seed, so a score there is a fair comparison (a campaign run's
	seed is the player's own).

	How scores travel (chat channels keep no history, so players tell each other; the same way as Piggle and
	Body Pull):
	  * the family's ONE hidden games channel, "PiggleScores", with our own message prefix "NBG1" (every
	    message under another game's prefix is ignored), plus the guild. The channel is removed from every
	    chat window, its notices are hidden, and it is kept behind the game's own channels (NetherChannels);
	  * on login a player asks ("Q"); everyone who hears it answers after a random 2-9 s with the best entries
	    they know, skipping anything someone else has just sent;
	  * a new best that makes a day's top ten is sent at once;
	  * every entry carries its inputs. It is stored only after this client replays that day's run with them
	    and gets exactly the claimed score. Replays run a few decisions per frame (never a spike).
	  Messages go out one every 0.35 s, never in combat. The setting "Share scores" turns all of it off.

	SEALED RECORDS: on logout this character's daily records are sealed (a digest of them, the character and
	a salt). If the saved file was edited outside the game the seal fails and every daily record is replayed
	again: only records whose own inputs really make that score are kept.

	  LB:Board(id) -> top ten { who, s, t, m, g }   (id: "d" .. date)
	  LB:Record(date, score, inputs)                 a finished daily run by this player
	  LB:Enabled() / LB:SetEnabled(on)
	  LB:Pending()                                   replays waiting to be checked ]]

local _, ns = ...
local P = ns.P
local LB = P:Module("Leaderboard")
local R = ns.Rules

local PREFIX, CHANNEL, SEP = "NBG1", "PiggleScores", "~"      -- the shared channel; our own prefix
local TOP, MAX_INPUTS = 10, 64
local INPUTS_PER_FRAME = 4
local SALT = "needbeforegreed-seal-1"
LB.CHANNEL, LB.PREFIX = CHANNEL, PREFIX
LB.BOARD_PREFIX = "d"
-- the other Nether games on the same channel: it is left only when none of them is loaded
local SIBLINGS = { "Piggle", "BodyPull" }

local function DB()
	local d = P.db and P.db.board
	if type(d) ~= "table" then
		d = {}
		if P.db then P.db.board = d end
	end
	return d
end

function LB:Enabled() return P:Setting("shareScores") ~= false end
function LB:Board(id) return DB()[id] or {} end
function LB:BoardId(date) return self.BOARD_PREFIX .. date end

-- ------------------------------------------------------------------ which run a board is
local function DayOfDate(date)
	local y, m, d = tostring(date):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	y, m, d = tonumber(y), tonumber(m), tonumber(d)
	if not y or m < 1 or m > 12 or d < 1 or d > 31 then return nil end
	if m <= 2 then y = y - 1 end
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local mp = m > 2 and m - 3 or m + 9
	local doy = math.floor((153 * mp + 2) / 5) + d - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end
LB.DayOfDate = DayOfDate

-- the day number a board id is, or nil if it is not a real board (only yesterday, today or tomorrow:
-- realms' clocks differ a little)
function LB:DayOf(id, any)
	if type(id) ~= "string" then return nil end
	local date = id:match("^" .. self.BOARD_PREFIX .. "(%d%d%d%d%-%d%d%-%d%d)$")
	if not date then return nil end
	local day = DayOfDate(date)
	if not day or P.Daily.DateOf(day) ~= date then return nil end
	if not any and math.abs(day - P.Daily:Day()) > 1 then return nil end
	return day
end

-- ------------------------------------------------------------------ the shared tables
-- one entry per player per board (their best), highest score first, at most ten
local function Qualifies(list, e)
	for _, o in ipairs(list) do
		if o.who == e.who and o.s >= e.s then return false end
	end
	return #list < TOP or e.s > list[#list].s
end

local function Insert(id, e)
	local d = DB()
	local list = d[id] or {}
	d[id] = list
	if not Qualifies(list, e) then return false end
	for i = #list, 1, -1 do if list[i].who == e.who then table.remove(list, i) end end
	local at = #list + 1
	while at > 1 and (list[at - 1].s < e.s or (list[at - 1].s == e.s and (list[at - 1].t or 0) > (e.t or 0))) do at = at - 1 end
	table.insert(list, at, { who = e.who, s = e.s, t = e.t, m = e.m, g = e.g or nil })
	while #list > TOP do table.remove(list) end
	P:Fire("LEADERBOARD_CHANGED", id)
	return true
end
LB.Insert = Insert

-- boards older than a week are let go
local function Prune()
	local d, today = DB(), P.Daily:Day()
	for id in pairs(d) do
		local day = LB:DayOf(id, true)
		if not day or today - day > 7 then d[id] = nil end
	end
end

-- ------------------------------------------------------------------ replay checks (a few decisions a frame)
local jobs, job = {}, nil
local checker = CreateFrame("Frame")
checker:Hide()

local function Finish(ok)
	local j = job
	job = nil
	if j and j.done then P:Safe("replay check", j.done, ok) end
end

checker:SetScript("OnUpdate", function(self)
	if not job then
		job = table.remove(jobs, 1)
		if not job then self:Hide() return end
		local dg = P.Daily:Dungeon(job.day)
		local ok, run = pcall(R.NewRun, R, dg.id, P.Daily:Seed(job.day))
		if not ok then Finish(false) return end
		job.run, job.i = run, 0
		return                                  -- dealing the run was this frame's work
	end
	local j = job
	for _ = 1, INPUTS_PER_FRAME do
		local run = j.run
		if run.phase == "over" or j.i >= #j.m then
			local score = R:Score(run)
			Finish(run.phase == "over" and j.i == #j.m and score == j.score)
			return
		end
		j.i = j.i + 1
		local c = j.m:sub(j.i, j.i)
		local okStep
		if run.phase == "pick" then okStep = R:Pick(run, c) elseif run.phase == "call" then okStep = R:Call(run, c) end
		if not okStep then Finish(false) return end
	end
end)

-- queue a check: inputs must make exactly `score` in that day's daily run; done(ok) afterwards
local function Check(day, score, inputs, done)
	if type(inputs) ~= "string" or #inputs == 0 or #inputs > MAX_INPUTS or inputs:find("[^NGP0-5]") then
		if done then done(false) end
		return
	end
	if #jobs >= 60 then return end
	jobs[#jobs + 1] = { day = day, score = score, m = inputs, done = done }
	checker:Show()
end
LB.Check = Check
function LB:Pending() return #jobs + (job and 1 or 0) end

-- ------------------------------------------------------------------ sending (queued, paced, out of combat)
local outq = {}
local sender = CreateFrame("Frame")
sender:Hide()
local nextAt = 0
sender:SetScript("OnUpdate", function(self)
	if #outq == 0 then self:Hide() return end
	if InCombatLockdown and InCombatLockdown() then return end
	local now = GetTime()
	if now < nextAt then return end
	nextAt = now + 0.35
	local m = table.remove(outq, 1)
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		local ok, err = pcall(C_ChatInfo.SendAddonMessage, PREFIX, m[1], m[2], m[3])
		if not ok then P:RecordError("leaderboard send", err) end
	end
end)

local function Queue(text, kind, target)
	if #outq >= 120 then return end
	outq[#outq + 1] = { text, kind, target }
	sender:Show()
end

local function ChannelId()
	if not GetChannelName then return nil end
	local id = GetChannelName(CHANNEL)
	return (type(id) == "number" and id > 0) and id or nil
end

local function Targets(only)
	local t = {}
	local id = ChannelId()
	if id and (not only or only == "CHANNEL") then t[#t + 1] = { "CHANNEL", id } end
	if IsInGuild and IsInGuild() and (not only or only == "GUILD") then t[#t + 1] = { "GUILD" } end
	return t
end

local Join
local lastJoin = 0
local function SendEntry(id, e, only)
	-- the shared channel can be gone (another game's sharing switched off left it): join again, at most once a minute
	if not ChannelId() and GetTime() - lastJoin > 60 then lastJoin = GetTime() Join() end
	local body = table.concat({ id, e.s, e.who, e.t or 0, e.m }, SEP)
	local mid = ("%06x"):format(math.random(0, 16777215))
	for _, tg in ipairs(Targets(only)) do
		Queue(table.concat({ "E", mid, 1, 1, body }, SEP), tg[1], tg[2])
	end
end

-- ------------------------------------------------------------------ receiving
local seenAt = {}     -- id..who..score -> time last heard (answers skip what was just sent)
local answerAt
local me

local function SeenKey(id, e) return id .. "|" .. e.who .. "|" .. e.s end

local function Parse(body)
	local f = {}
	for x in (body .. SEP):gmatch("(.-)" .. SEP) do f[#f + 1] = x end
	if #f ~= 5 then return nil end
	local id, s, who, t, m = f[1], tonumber(f[2]), f[3], tonumber(f[4]), f[5]
	if not s or s < 0 or s > 100000 or s ~= math.floor(s) or who == "" or #who > 60 or who:find("[|\n]") then return nil end
	return id, { s = s, who = who, t = t, m = m }
end

local function Heard(id, e, kind)
	seenAt[SeenKey(id, e)] = GetTime()
	local day = LB:DayOf(id)
	if not day then return end
	if not Qualifies(DB()[id] or {}, e) then return end
	if kind == "GUILD" then e.g = true end
	Check(day, e.s, e.m, function(ok) if ok then Insert(id, e) end end)
end

local function Answer(kind)
	answerAt = nil
	local now, sent = GetTime(), 0
	for id, list in pairs(DB()) do
		for i = 1, math.min(3, #list) do
			local e = list[i]
			local k = SeenKey(id, e)
			if not (seenAt[k] and now - seenAt[k] < 60) and sent < 15 then
				seenAt[k] = now
				SendEntry(id, e, kind)
				sent = sent + 1
			end
		end
	end
end

local function OnMessage(_, prefix, text, kind, from)
	-- the channel is shared by the Nether games: only our own prefix is ours
	if prefix ~= PREFIX or not LB:Enabled() or type(text) ~= "string" then return end
	if from and me and (from == me or from:match("^([^%-]+)") == me:match("^([^%-]+)")) then return end
	local tag = text:sub(1, 1)
	if tag == "Q" then
		if not answerAt and C_Timer and C_Timer.After then
			answerAt = GetTime() + 2 + math.random() * 7
			local reply = kind == "GUILD" and "GUILD" or "CHANNEL"
			C_Timer.After(answerAt - GetTime(), function() P:Safe("leaderboard answer", Answer, reply) end)
		end
	elseif tag == "E" then
		local body = text:match("^E" .. SEP .. "%x+" .. SEP .. "1" .. SEP .. "1" .. SEP .. "(.*)$")
		if not body or #body > 240 then return end
		local id, e = Parse(body)
		if id then Heard(id, e, kind) end
	end
end
LB.OnMessage = OnMessage

-- ------------------------------------------------------------------ the hidden channel
local function HideChannel()
	local remove = (ChatFrameUtil and ChatFrameUtil.RemoveChannel) or ChatFrame_RemoveChannel
	if not remove then return end
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local cf = _G["ChatFrame" .. i]
		if cf then pcall(remove, cf, CHANNEL) end
	end
end

local function NoticeFilter(_, _, ...)
	for i = 1, select("#", ...) do
		local a = select(i, ...)
		if type(a) == "string" and a:lower():find(CHANNEL:lower(), 1, true) then return true end
	end
	return false
end

function Join()
	if not LB:Enabled() then return end
	if not ChannelId() then
		local join = JoinTemporaryChannel or JoinChannelByName
		if join then pcall(join, CHANNEL) end
	end
	P:After(2, function()
		HideChannel()
		if NetherChannels and NetherChannels.Settle then NetherChannels:Settle(CHANNEL) end
		if LB:Enabled() then
			for _, tg in ipairs(Targets()) do Queue("Q" .. SEP .. "1", tg[1], tg[2]) end
		end
	end)
end

-- another Nether game that also uses the channel is loaded (then the channel is never left)
local function SiblingLoaded()
	local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or rawget(_G, "IsAddOnLoaded")
	if not loaded then return false end
	for _, name in ipairs(SIBLINGS) do
		local ok, on = pcall(loaded, name)
		if ok and on then return true end
	end
	return false
end
LB.SiblingLoaded = SiblingLoaded

function LB:SetEnabled(on)
	if on then Join()
	else
		local leave = LeaveChannelByName
		if leave and ChannelId() and not SiblingLoaded() then pcall(leave, CHANNEL) end
		wipe(outq)
	end
end

-- ------------------------------------------------------------------ this player's daily runs
function LB:Record(date, score, inputs)
	if P.readOnly or P.testOpen or not me then return end
	local c = P.char
	if c and c.edited then return end              -- records still being re-checked after an outside edit
	local e = { who = me, s = score, t = (GetServerTime and GetServerTime()) or 0, m = inputs, g = true }
	if Insert(self:BoardId(date), e) and self:Enabled() then SendEntry(self:BoardId(date), e) end
end

-- ------------------------------------------------------------------ sealed records
local function Hash(str)
	local h = 7
	for i = 1, #str do h = (h * 31 + str:byte(i)) % 4294967291 end
	return ("%08x"):format(h)
end

local function Digest(c, guid)
	local out = {}
	local days = {}
	for d in pairs(c.daily or {}) do days[#days + 1] = d end
	table.sort(days)
	for _, d in ipairs(days) do
		local r = c.daily[d]
		out[#out + 1] = d .. ":" .. tostring(r.best) .. ":" .. tostring(r.medal) .. ":" .. tostring(r.inputs)
	end
	out[#out + 1] = tostring(c.dailyDays)
	return Hash(table.concat(out, ";") .. guid .. SALT)
end
LB.Digest = Digest

-- an outside edit: every daily record is replayed; what does not check out is dropped
local function Recheck(c)
	c.edited = true
	local left = 0
	local function Done() left = left - 1 if left == 0 then c.edited = nil end end
	for d, r in pairs(c.daily or {}) do
		local day = DayOfDate(d)
		if r.best and r.inputs and day then
			left = left + 1
			local claimed = r.best
			Check(day, claimed, r.inputs, function(ok)
				if not ok then c.daily[d] = nil
				else r.medal = P.Progress:MedalFor(P.Daily:Dungeon(day).id, claimed, false) end
				Done()
			end)
		elseif r.best then
			c.daily[d] = nil
		end
	end
	if left == 0 then c.edited = nil end
end
LB.Recheck = Recheck

-- ------------------------------------------------------------------ start up
P:Register("LOGIN", function()
	local name = UnitName and UnitName("player")
	local realm = GetNormalizedRealmName and GetNormalizedRealmName()
	me = name and (realm and realm ~= "" and (name .. "-" .. realm) or name) or nil
	LB.me = me
	local c = P.char
	if c and c.seal and c.seal ~= Digest(c, P.guid) then P:Safe("records check", Recheck, c) end
	P:Safe("leaderboard prune", Prune)
	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
	local addFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
	if addFilter then
		for _, ev in ipairs({ "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER", "CHAT_MSG_CHANNEL_JOIN", "CHAT_MSG_CHANNEL_LEAVE" }) do
			pcall(addFilter, ev, NoticeFilter)
		end
	end
	-- channels are not ready the moment the world loads
	P:After(10, Join)
end)
P:On("CHAT_MSG_ADDON", OnMessage)
P:On("PLAYER_LOGOUT", function()
	local c = P.char
	if c and P.guid and not c.edited and not P.readOnly then c.seal = Digest(c, P.guid) end
end)
