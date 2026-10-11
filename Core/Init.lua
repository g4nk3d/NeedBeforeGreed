--[[ Need Before Greed - Core/Init.lua
	The namespace and the plumbing every other file uses.

	  P:Module(name)            a module table, created once (P.<name>)
	  P:On(event, fn)           game events; several handlers per event, each protected
	  P:Off(event)              stop listening (handlers stay, the frame unregisters)
	  P:Register(msg, fn)       internal messages; P:Fire(msg, ...)
	  P:After(s, fn)            a timer
	  P:Safe(context, fn, ...)  a protected call; failures are kept for /nbg debug, never thrown
	  P:Print(fmt, ...)         a chat line
	  P.db                      NeedBeforeGreedDB (account: settings, schema); P.char = this character's
	                            table, keyed by the player's GUID (ready after LOGIN)

	The one global of our own is the saved table NeedBeforeGreedDB (plus the slash command entries the game
	requires, and the shared Nether family files' own). ]]

local ADDON, ns = ...
local P = { name = ADDON, modules = {} }
ns.P = P

P.VERSION = "1.0.0"
P.SCHEMA = 1
P.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"

local type, pairs, select, tostring, pcall, format, tonumber = type, pairs, select, tostring, pcall, string.format, tonumber

function P:Module(name)
	local m = self.modules[name]
	if not m then
		m = { name = name }
		self.modules[name] = m
		self[name] = m
	end
	return m
end

P.errors = {}
P.counters = {}
function P:RecordError(context, err)
	local line = format("%s: %s", tostring(context), tostring(err))
	local last = self.errors[#self.errors]
	if last and last.text == line then
		last.n = last.n + 1          -- the same error again: count it, don't fill the list
	elseif #self.errors < 30 then
		self.errors[#self.errors + 1] = { text = line, n = 1, at = GetTime and GetTime() or 0 }
	end
	if self.debug then self:Print("|cffff6060error|r %s", line) end
end

function P:Safe(context, fn, ...)
	local ok, a, b, c = pcall(fn, ...)
	if not ok then self:RecordError(context, a) return nil end
	return a, b, c
end

-- /nbg perf's breakdown: the slowest time seen for each named part of the work (reset by each readout).
-- P:ProfStart() returns a start time (nil when the game gives no timer); P:ProfEnd(name, t0) keeps the
-- slowest. Names are fixed strings, so nothing is allocated.
P.prof = {}
local profNow = debugprofilestop
function P:ProfStart() return profNow and profNow() end
function P:ProfEnd(name, t0)
	if not t0 then return end
	local ms = profNow() - t0
	local prof = self.prof
	if ms > (prof[name] or 0) then prof[name] = ms end
end

function P:Print(fmt, ...)
	local msg = select("#", ...) > 0 and format(fmt, ...) or tostring(fmt)
	if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffe8b04aNeed Before Greed|r " .. msg) end
end

local frame = CreateFrame("Frame")
P.eventFrame = frame
-- the Nether family's switch: while NetherSuite has Need Before Greed switched off its events never run
if NetherFamily and NetherFamily.Gate then NetherFamily:Gate(ADDON, frame) end
local handlers = {}
frame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if not list then return end
	for i = 1, #list do P:Safe(event, list[i], event, ...) end
end)
function P:On(event, fn)
	if not handlers[event] then handlers[event] = {} end
	local list = handlers[event]
	list[#list + 1] = fn
	if not frame:IsEventRegistered(event) then pcall(frame.RegisterEvent, frame, event) end
end
function P:Off(event)
	if frame:IsEventRegistered(event) then frame:UnregisterEvent(event) end
end
function P:Listen(event)
	if handlers[event] and not frame:IsEventRegistered(event) then pcall(frame.RegisterEvent, frame, event) end
end

local bus = {}
function P:Register(msg, fn)
	bus[msg] = bus[msg] or {}
	local list = bus[msg]
	list[#list + 1] = fn
end
function P:Fire(msg, ...)
	local list = bus[msg]
	if not list then return end
	for i = 1, #list do self:Safe("message " .. msg, list[i], ...) end
end

function P:After(s, fn)
	if C_Timer and C_Timer.After then C_Timer.After(s, function() P:Safe("timer", fn) end) end
end

-- ------------------------------------------------------------------ saved data
-- Every value read back is checked; a broken section is reset on its own with one chat notice, so a
-- damaged file never stops the game from loading.
local function Clean(db)
	local notes = {}
	if type(db.settings) ~= "table" then
		if db.settings ~= nil then notes[#notes + 1] = "settings" end
		db.settings = {}
	end
	if type(db.chars) ~= "table" then
		if db.chars ~= nil then notes[#notes + 1] = "character records" end
		db.chars = {}
	end
	if type(db.window) ~= "table" then db.window = nil end
	-- shared daily boards: id -> list of { who, s, t, m, g }
	if type(db.board) ~= "table" then db.board = nil
	else
		for id, list in pairs(db.board) do
			if type(id) ~= "string" or type(list) ~= "table" then db.board[id] = nil
			else
				for i = #list, 1, -1 do
					local e = list[i]
					if type(e) ~= "table" or type(e.who) ~= "string" or type(e.s) ~= "number" or type(e.m) ~= "string" then table.remove(list, i) end
				end
			end
		end
	end
	if type(db.minimap) ~= "table" then db.minimap = nil end
	for guid, c in pairs(db.chars) do
		if type(guid) ~= "string" or type(c) ~= "table" then
			db.chars[guid] = nil
			notes[#notes + 1] = "a character record"
		else
			-- dungeon records: id -> { best, medal, runs, kicks }
			if type(c.dungeons) ~= "table" then c.dungeons = {}
			else
				for id, r in pairs(c.dungeons) do
					if type(id) ~= "string" or type(r) ~= "table" then
						c.dungeons[id] = nil
					else
						local best = tonumber(r.best)
						r.best = (best and best >= 0 and best < 100000) and math.floor(best) or nil
						local medal = tonumber(r.medal)
						r.medal = (medal and medal >= 0 and medal <= 3) and math.floor(medal) or 0
						for _, k in ipairs({ "runs", "kicks", "finished" }) do
							local n = tonumber(r[k])
							r[k] = (n and n >= 0 and n < 10000000) and math.floor(n) or 0
						end
					end
				end
			end
			-- the run in progress: its dungeon, seed and your inputs so far (replayed after a /reload)
			local rs = c.resume
			if rs ~= nil and (type(rs) ~= "table" or type(rs.dungeon) ~= "string" or type(rs.seed) ~= "number"
				or type(rs.inputs) ~= "string" or #rs.inputs > 64 or rs.inputs:find("[^NGP0-5]")
				or (rs.daily ~= nil and (type(rs.daily) ~= "string" or not rs.daily:match("^%d%d%d%d%-%d%d%-%d%d$")))) then
				c.resume = nil
			end
			-- daily runs: "YYYY-MM-DD" -> { best, medal, runs, finished, inputs }
			if type(c.daily) ~= "table" then c.daily = nil
			else
				for d, r in pairs(c.daily) do
					if type(d) ~= "string" or not d:match("^%d%d%d%d%-%d%d%-%d%d$") or type(r) ~= "table" then
						c.daily[d] = nil
					else
						local best = tonumber(r.best)
						r.best = (best and best >= 0 and best < 100000) and math.floor(best) or nil
						local medal = tonumber(r.medal)
						r.medal = (medal and medal >= 0 and medal <= 3) and math.floor(medal) or 0
						local runs = tonumber(r.runs)
						r.runs = (runs and runs >= 0 and runs < 1000000) and math.floor(runs) or 0
						r.finished = r.finished == true or nil
						if type(r.inputs) ~= "string" or #r.inputs > 64 or r.inputs:find("[^NGP0-5]") then r.inputs = nil end
					end
				end
			end
			if type(c.seal) ~= "string" then c.seal = nil end
			c.edited = nil
			-- achievements: id -> time earned
			if type(c.ach) ~= "table" then c.ach = nil
			else for id, tm in pairs(c.ach) do if type(id) ~= "string" or type(tm) ~= "number" then c.ach[id] = nil end end end
			local dd = tonumber(c.dailyDays)
			c.dailyDays = (dd and dd >= 0 and dd < 100000) and math.floor(dd) or nil
		end
	end
	return notes
end

local MIGRATE = {
	-- [n] = function(db) ... end   upgrades a schema n-1 table to schema n
}

local function OpenDB()
	local db = rawget(_G, "NeedBeforeGreedDB")
	if type(db) ~= "table" then db = {} end
	local from = tonumber(db.schema) or 0
	if from > P.SCHEMA then
		-- a newer Need Before Greed wrote this: keep it untouched, play from a temporary table this session
		P:Print("your saved data comes from a newer version; nothing will be saved until you update.")
		db = { schema = P.SCHEMA }
		P.readOnly = true
	else
		for v = from + 1, P.SCHEMA do
			local fn = MIGRATE[v]
			if fn then
				local ok, err = pcall(fn, db)
				if not ok then P:RecordError("migrate " .. v, err) end
			end
		end
		db.schema = P.SCHEMA
		NeedBeforeGreedDB = db
	end
	local notes = Clean(db)
	if #notes > 0 then
		P:Print("some saved data was damaged and has been reset: %s.", table.concat(notes, ", "))
	end
	return db
end

P:On("ADDON_LOADED", function(_, name)
	if name ~= ADDON then return end
	P.db = OpenDB()
	P:Fire("DB_READY")
end)

-- per-character records are keyed by GUID (several characters can share a name), known at login
P:On("PLAYER_LOGIN", function()
	P.loggedIn = true
	local guid = UnitGUID and UnitGUID("player")
	if type(guid) ~= "string" or guid == "" then guid = "unknown" end
	P.guid = guid
	local c = P.db.chars[guid]
	if type(c) ~= "table" then
		c = { dungeons = {} }
		P.db.chars[guid] = c
	end
	c.name = UnitName and UnitName("player") or c.name
	P.char = c
	P:Fire("LOGIN")
end)
