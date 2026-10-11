--[[ Need Before Greed - Game/Daily.lua
	The daily run: one dungeon and one seed for every player in the world on the same date (UTC, from the
	realm's clock), so everyone sits at the same table with the same classes, drops and dice. It can be
	played whether or not that dungeon is open in your campaign, as often as you like (the best counts),
	and its records are kept apart: a daily run never changes campaign progress.

	  Dy:Today()              "2026-10-10", the day number
	  Dy:Dungeon([day])       the dungeon of that day (each of the five in turn, in a fixed order)
	  Dy:Seed([day])          the day's seed (the same everywhere)
	  Dy:Record([date])       this character's record for that date { best, medal, runs, inputs } or nil
	  Dy:Finish(run)          a finished daily run: keeps the best; returns medal, isNewBest, previousBest
	  Dy:DaysPlayed()         how many different days this character has finished the daily run ]]

local _, ns = ...
local P = ns.P
local Dy = P:Module("Daily")
local R, I = ns.Rules, ns.Items

local KEEP_DAYS = 60
local floor = math.floor

local function Now()
	if GetServerTime then
		local ok, t = pcall(GetServerTime)
		if ok and type(t) == "number" and t > 0 then return t end
	end
	return time and time() or 0
end

-- the UTC calendar date of a day number (days since 1970-01-01), worked out by hand so it never depends on
-- the player's time zone (Howard Hinnant's civil-from-days)
local function DateOf(day)
	local z = day + 719468
	local era = floor(z / 146097)
	local doe = z - era * 146097
	local yoe = floor((doe - floor(doe / 1460) + floor(doe / 36524) - floor(doe / 146096)) / 365)
	local y = yoe + era * 400
	local doy = doe - (365 * yoe + floor(yoe / 4) - floor(yoe / 100))
	local mp = floor((5 * doy + 2) / 153)
	local d = doy - floor((153 * mp + 2) / 5) + 1
	local m = mp < 10 and mp + 3 or mp - 9
	if m <= 2 then y = y + 1 end
	return ("%04d-%02d-%02d"):format(y, m, d)
end
Dy.DateOf = DateOf

function Dy:Day() return floor(Now() / 86400) end
function Dy:Today()
	local day = self:Day()
	return DateOf(day), day
end

-- the day's dungeon: the five in turn, stepping by 2 (so two days in a row are never neighbours in difficulty)
function Dy:Dungeon(day)
	day = day or self:Day()
	local n = #I.DUNGEONS
	return I.DUNGEONS[(day * 2) % n + 1]
end

-- the day's seed: the day number through the rules' own mixer, the same on every machine
function Dy:Seed(day)
	day = day or self:Day()
	local st = R.Stream(day * 7919 + 104729, 99)
	return st.int(1, 2147483000)
end

local function Days()
	local c = P.char
	if not c then return {} end
	if type(c.daily) ~= "table" then c.daily = {} end
	return c.daily
end

function Dy:Record(date) return Days()[date or self:Today()] end

function Dy:DaysPlayed()
	local c = P.char
	return c and tonumber(c.dailyDays) or 0
end

function Dy:Finish(run)
	local date = run.daily
	local score, how = R:Score(run)
	local kicked = how == "kicked"
	local medal = P.Progress:MedalFor(run.dungeon.id, score, kicked)
	local c = P.char
	if not c or P.readOnly or not date then return medal, false, nil end
	local days = Days()
	local r = days[date]
	if not r then
		r = { medal = 0, runs = 0 }
		days[date] = r
	end
	if not kicked and not r.finished then
		r.finished = true
		c.dailyDays = (tonumber(c.dailyDays) or 0) + 1
	end
	r.runs = (r.runs or 0) + 1
	local prev = r.best
	local newBest = false
	if not kicked and (not prev or score > prev) then
		r.best = score
		r.inputs = run.inputs
		newBest = prev ~= nil
	end
	if medal > (r.medal or 0) then r.medal = medal end
	-- old days are let go (the count of days played stays)
	local today = self:Day()
	for d in pairs(days) do
		local y, m, dd = tostring(d):match("^(%d+)-(%d+)-(%d+)$")
		if not y then days[d] = nil
		else
			local age = today - ((tonumber(y) - 1970) * 365.25 + (tonumber(m) - 1) * 30.44 + tonumber(dd))
			if age > KEEP_DAYS + 5 then days[d] = nil end
		end
	end
	return medal, newBest, prev
end
