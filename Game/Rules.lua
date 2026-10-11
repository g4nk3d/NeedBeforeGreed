--[[ Need Before Greed - Game/Rules.lua
	The whole game as plain, deterministic Lua (no game API: the balance tools run this same file).
	A run is fixed by its seed: the five secret classes, the four players at the table, the eight drops,
	every die and every choice the other players make. Only your inputs change what happens, so a run is
	recorded as its seed plus your inputs (one letter per decision) and can be replayed exactly; the
	daily run and the shared scores rely on that.

	  run = R:NewRun(dungeonId, seed [, ev])   deals drop 1; run.phase == "pick"
	  R:Pick(run, "N" | "G" | "P" [, ev])      your pick; the table reveals, calls go round, the dice roll
	  R:Call(run, seat | 0 [, ev])             your call when it is your turn to call (0 = no call)
	  R:Replay(dungeonId, seed, inputs)        the same run again from its inputs
	  R:Score(run)                             your final score (Fair Play and kicked rules applied)

	run.phase: "pick" (your pick is wanted), "call" (your call is wanted), "over".
	Events (ev, a list) tell the window what to show, in order: deal, tell, reveal, callturn, call,
	nocall, rep, kicked, roll, win, floor, over. ]]

local _, ns = ...
local I = ns.Items
local R = {}
ns.Rules = R

local floor, min, max = math.floor, math.min, math.max
local SEATS, DROPS, START_REP = 5, 8, 3
R.SEATS, R.DROPS, R.START_REP = SEATS, DROPS, START_REP
R.PERSONAS = { "snaggle", "maelle", "brokk", "pellwick", "tamsin", "vexa" }
R.PERSONA_NAME = { snaggle = "Snaggle", maelle = "Sister Maelle", brokk = "Brokk Ironpaw", pellwick = "Pellwick",
	tamsin = "Old Tamsin", vexa = "Vexa" }

-- ------------------------------------------------------------------ deterministic numbers
-- Park-Miller (16807): exact in double arithmetic, the same on every machine
local M = 2147483647
local function Mix(seed, a, b, c)
	local h = (floor(seed) % (M - 1)) + 1
	h = (h * 48271 + (a or 0) * 7919 + (b or 0) * 104729 + (c or 0) * 1299709) % M
	if h == 0 then h = 1 end
	for _ = 1, 3 do h = (h * 16807) % M end
	return h
end
-- a small stream: rnd() in [0, 1), int(lo, hi)
local function Stream(seed, a, b, c)
	local s = Mix(seed, a, b, c)
	local st = {}
	function st.rnd() s = (s * 16807) % M return (s - 1) / (M - 1) end
	function st.int(lo, hi) return lo + floor(st.rnd() * (hi - lo + 1)) end
	return st
end
R.Stream = Stream

-- what each purpose's stream is keyed by
local K_SETUP, K_DROP, K_DICE, K_AI, K_TELL, K_TIE, K_CALL = 1, 2, 3, 4, 5, 6, 7

-- ------------------------------------------------------------------ a new run
local function Shuffle(list, st)
	for i = #list, 2, -1 do
		local j = st.int(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

local function Copy(t) local c = {} for i, v in ipairs(t) do c[i] = v end return c end

function R:NewRun(dungeonId, seed, ev)
	local dg = I:Dungeon(dungeonId)
	if not dg then error("unknown dungeon " .. tostring(dungeonId)) end
	seed = floor(tonumber(seed) or 1)
	local st = Stream(seed, K_SETUP)
	local classes = Shuffle(Copy(I.CLASSES), st)
	local personas = Shuffle(Copy(R.PERSONAS), st)
	local run = { seed = seed, dungeon = dg, tier = dg.tier, d = 0, inputs = "", seats = {}, drops = {},
		known = {}, suspicion = {}, needHistory = {}, beatBy = {}, phase = "deal" }
	for s = 1, SEATS do
		run.seats[s] = { seat = s, you = (s == 1), persona = (s > 1) and personas[s - 1] or nil, class = classes[s],
			rep = START_REP, calls = dg.calls, kicked = false, won = {}, gold = 0, caught = 0, rightCalls = 0, wrongCalls = 0, ninjas = 0 }
		run.suspicion[s] = 0
		run.needHistory[s] = {}
	end
	-- the eight drops: quality by the dungeon's weights, the last one the boss's (rare or epic)
	local weights = I.QUALITY_WEIGHTS[dg.tier]
	local used = {}
	for k = 1, DROPS do
		local ds = Stream(seed, K_DROP, k)
		local q
		if k == DROPS then
			q = (ds.int(1, 100) <= I.BOSS_EPIC[dg.tier]) and 5 or 4
		else
			local total = 0
			for _, w in ipairs(weights) do total = total + w end
			local r = ds.int(1, total)
			q = 1
			while r > weights[q] do r = r - weights[q] q = q + 1 end
		end
		-- an item of that quality not yet dropped this run (nearest quality if none left)
		local pick
		for dq = 0, 4 do
			for _, qq in ipairs({ q - dq, q + dq }) do
				if not pick and qq >= 1 and qq <= 5 then
					local cands = {}
					for _, it in ipairs(dg.items) do if it.q == qq and not used[it.index] then cands[#cands + 1] = it end end
					if #cands > 0 then pick = cands[ds.int(1, #cands)] end
				end
			end
			if pick then break end
		end
		used[pick.index] = true
		local Q = I.QUALITY[pick.q]
		local dice = {}
		local dst = Stream(seed, K_DICE, k)
		for s = 1, SEATS do dice[s] = dst.int(1, 100) end
		run.drops[k] = { item = pick, value = ds.int(Q.lo, Q.hi), dice = dice }
	end
	R:Deal(run, ev)
	return run
end

-- ------------------------------------------------------------------ helpers
local function Emit(ev, ...) if ev then ev[#ev + 1] = { ... } end end
local function Active(run, s) return not run.seats[s].kicked end
local function Drop(run) return run.drops[run.d] end

-- what an observer believes: the chance that `target` cannot use `item`
function R:Doubt(run, observer, target, item)
	local known = run.known[target]
	if known then return I:CanUse(known, item) and 0 or 1 end
	-- the target's class is one nobody has seen: not the observer's own, not any shown at the table
	local taken = {}
	if observer then taken[run.seats[observer].class] = true end
	for s, c in pairs(run.known) do if s ~= target then taken[c] = true end end
	local wNo, wAll = 0, 0
	for _, c in ipairs(I.CLASSES) do
		if not taken[c] then
			local w = 1
			-- sharper tables read earlier Needs as mostly honest
			if run.tier >= 3 then
				for _, prev in ipairs(run.needHistory[target]) do
					if not I:CanUse(c, prev) then w = w * 0.55 end
				end
			end
			wAll = wAll + w
			if not I:CanUse(c, item) then wNo = wNo + w end
		end
	end
	local p = wAll > 0 and wNo / wAll or 0.5
	-- someone caught before is watched more closely
	local sus = run.suspicion[target] or 0
	if sus > 0 then p = 1 - (1 - p) * (0.82 ^ sus) end
	return p
end

-- ------------------------------------------------------------------ the other players' picks (made at the deal)
local function PickFor(run, s, st)
	local seat = run.seats[s]
	local dr = Drop(run)
	local it, q = dr.item, dr.item.q
	local p = seat.persona
	local usable = I:CanUse(seat.class, it)
	local careful = seat.rep <= 1
	local choice
	if usable then
		if q >= 3 then choice = "N"
		elseif q == 2 then choice = st.rnd() < 0.35 and "N" or "G"
		else choice = st.rnd() < 0.25 and "P" or "G" end
		if p == "snaggle" and q >= 2 then choice = "N" end
	else
		choice = (q == 1 and st.rnd() < 0.5) and "P" or "G"
		local tempt = 0
		if p == "snaggle" then tempt = (q >= 3) and 0.78 or (q == 2 and 0.3 or 0)
		elseif p == "brokk" then tempt = (q == 5) and 0.9 or (q == 4 and 0.5 or 0)
		elseif p == "vexa" then tempt = (q == 5) and 0.3 or 0
		elseif p == "pellwick" then
			-- expected value: callers left at the table, how likely each calls, what a rep costs
			local free = 1
			for o = 1, SEATS do
				if o ~= s and Active(run, o) and run.seats[o].calls > 0 then free = free * (1 - (0.28 + 0.04 * run.tier)) end
			end
			local Q = I.QUALITY[q]
			local gain = (Q.lo + Q.hi) / 2 * 0.5 * free
			local loss = (1 - free) * 45 * run.tier
			tempt = (q >= 3 and seat.rep >= 2 and gain > loss) and 1 or 0
		end
		if careful then tempt = tempt * (p == "snaggle" and 0.5 or 0.3) end
		if tempt > 0 and st.rnd() < tempt then choice = "N" end
	end
	-- Old Tamsin sometimes passes by mistake
	local mistake = false
	if p == "tamsin" and choice ~= "P" and st.rnd() < 0.12 then choice = "P" mistake = true end
	return choice, usable, mistake
end

local TELLS = {
	snaggle = { need = "need need NEED", other = "eh. greed i guess" },
	brokk = { bluff = "heh", honest = "heh heh" },
	pellwick = { calc = "Expected value says...", honest = "Hm. Within parameters." },
	maelle = { open = "Let us all be honest, friends." },
	tamsin = { oops = "Oh! Was that mine?" },
	vexa = { lost = "...Really?" },
}
R.TELLS = TELLS

function R:Deal(run, ev)
	run.d = run.d + 1
	if run.d > DROPS then return R:Finish(run, "done", ev) end
	run.picks, run.called, run.mistake = {}, {}, {}
	Emit(ev, "deal", run.d)
	local dr = Drop(run)
	for s = 2, SEATS do
		if Active(run, s) then
			local st = Stream(run.seed, K_AI, run.d, s)
			local choice, usable, mistake = PickFor(run, s, st)
			run.picks[s] = choice
			run.mistake[s] = mistake
			-- tells: written in party chat while everyone decides (not always, and not always honest)
			local ts = Stream(run.seed, K_TELL, run.d, s)
			local p = run.seats[s].persona
			local r = ts.rnd()
			local line
			if p == "snaggle" then
				if choice == "N" and r < 0.75 then line = TELLS.snaggle.need
				elseif choice ~= "N" and r < 0.15 then line = TELLS.snaggle.other end
			elseif p == "brokk" then
				if choice == "N" and not usable and r < 0.7 then line = TELLS.brokk.bluff
				elseif choice == "N" and usable and r < 0.15 then line = TELLS.brokk.bluff end
			elseif p == "pellwick" then
				if choice == "N" and not usable and r < 0.8 then line = TELLS.pellwick.calc
				elseif choice == "N" and usable and r < 0.2 then line = TELLS.pellwick.calc end
			elseif p == "maelle" then
				if run.d == 1 and r < 0.6 then line = TELLS.maelle.open end
			end
			if line then Emit(ev, "tell", s, line) end
		end
	end
	run.phase = "pick"
end

-- ------------------------------------------------------------------ your pick, then the table plays out
function R:Pick(run, choice, ev)
	if run.phase ~= "pick" or (choice ~= "N" and choice ~= "G" and choice ~= "P") then return false end
	run.inputs = run.inputs .. choice
	run.picks[1] = choice
	if choice == "N" and not I:CanUse(run.seats[1].class, Drop(run).item) then run.seats[1].ninjas = run.seats[1].ninjas + 1 end
	Emit(ev, "reveal")
	for s = 2, SEATS do
		if Active(run, s) and run.mistake[s] then Emit(ev, "tell", s, TELLS.tamsin.oops) end
	end
	-- the call round starts one seat further round the table each drop
	run.callOrder, run.callAt = {}, 0
	local start = ((run.d - 1) % SEATS) + 1
	for k = 0, SEATS - 1 do run.callOrder[#run.callOrder + 1] = ((start - 1 + k) % SEATS) + 1 end
	R:CallRound(run, ev)
	return true
end

-- who `s` could call now: Needers still standing, not themselves, not already shown this drop
function R:Targets(run, s)
	local t = {}
	for o = 1, SEATS do
		if o ~= s and Active(run, o) and run.picks[o] == "N" and not run.called[o] then t[#t + 1] = o end
	end
	return t
end

local function Lose(run, s, ev)
	local seat = run.seats[s]
	seat.rep = seat.rep - 1
	Emit(ev, "rep", s, seat.rep)
	if seat.rep <= 0 then
		seat.kicked = true
		run.picks[s] = nil
		Emit(ev, "kicked", s)
		if s == 1 then R:Finish(run, "kicked", ev) end
	end
end

local function Resolve(run, caller, target, ev)
	local c, t = run.seats[caller], run.seats[target]
	c.calls = c.calls - 1
	run.called[target] = true
	run.known[target] = t.class
	local item = Drop(run).item
	local caught = not I:CanUse(t.class, item)
	Emit(ev, "call", caller, target, caught, t.class)
	if caught then
		run.picks[target] = "X"           -- the Need is cancelled
		t.caught = t.caught + 1
		c.rightCalls = c.rightCalls + 1
		run.suspicion[target] = run.suspicion[target] + 1
		Lose(run, target, ev)
	else
		c.wrongCalls = c.wrongCalls + 1
		Lose(run, caller, ev)
	end
end

-- an AI seat's call: the Needer it doubts most, if its nature says so
local function AICall(run, s)
	local seat = run.seats[s]
	local p = seat.persona
	if p == "tamsin" or seat.calls <= 0 then return nil end
	local dr = Drop(run)
	local q = dr.item.q
	local sharp = 0.03 * (run.tier - 1)
	local best, bestP
	for _, t in ipairs(R:Targets(run, s)) do
		local pr = R:Doubt(run, s, t, dr.item)
		if not bestP or pr > bestP then best, bestP = t, pr end
	end
	if not best then return nil end
	-- Vexa goes after whoever beat her last, if they Need again
	if p == "vexa" then
		local grudge = run.beatBy[s]
		if grudge and run.picks[grudge] == "N" and not run.called[grudge] and Active(run, grudge) then return grudge end
		return bestP >= 0.75 - sharp and best or nil
	end
	if bestP >= 0.999 then return best end             -- a shown class that can't use it: everyone calls that
	if p == "maelle" then return bestP >= 0.62 - sharp and best or nil end
	if p == "pellwick" then return (q >= 3 and seat.rep >= 2 and bestP >= 0.6 - sharp) and best or nil end
	if p == "brokk" then return (q == 5 and bestP >= 0.5 - sharp) and best or nil end
	if p == "snaggle" then
		local grudge = run.beatBy[s]
		if grudge == best and bestP >= 0.5 then return best end
		return bestP >= 0.85 - sharp and best or nil
	end
	return nil
end

function R:CallRound(run, ev)
	while run.phase ~= "over" do
		run.callAt = run.callAt + 1
		local s = run.callOrder[run.callAt]
		if not s then break end
		local seat = run.seats[s]
		if Active(run, s) and seat.calls > 0 and #R:Targets(run, s) > 0 then
			if s == 1 then
				run.phase = "call"
				Emit(ev, "callturn", 1)
				return                               -- waits for R:Call
			end
			local t = AICall(run, s)
			if t then
				if run.seats[s].persona == "maelle" then Emit(ev, "tell", s, TELLS.maelle.open) end
				Resolve(run, s, t, ev)
			else
				Emit(ev, "nocall", s)
			end
		end
	end
	if run.phase == "over" then return end
	R:Roll(run, ev)
	if run.phase ~= "over" then R:Deal(run, ev) end
end

function R:Call(run, target, ev)
	if run.phase ~= "call" then return false end
	target = tonumber(target) or 0
	if target ~= 0 then
		local ok = false
		for _, t in ipairs(R:Targets(run, 1)) do if t == target then ok = true end end
		if not ok then return false end
	end
	run.inputs = run.inputs .. tostring(target)
	run.phase = "calls"
	if target == 0 then Emit(ev, "nocall", 1) else Resolve(run, 1, target, ev) end
	if run.phase == "over" then return true end
	R:CallRound(run, ev)
	return true
end

-- ------------------------------------------------------------------ the dice
function R:Roll(run, ev)
	local dr = Drop(run)
	local pool, kind = {}, "need"
	for s = 1, SEATS do if Active(run, s) and run.picks[s] == "N" then pool[#pool + 1] = s end end
	if #pool == 0 then
		kind = "greed"
		for s = 1, SEATS do if Active(run, s) and run.picks[s] == "G" then pool[#pool + 1] = s end end
	end
	if #pool == 0 then
		Emit(ev, "floor")
		return
	end
	-- highest roll wins; a tie rolls again between the tied seats
	local rolls = {}
	for _, s in ipairs(pool) do rolls[s] = dr.dice[s] end
	Emit(ev, "roll", kind, rolls)
	local rolled, winner = Copy(pool), nil
	local tie = 0
	while true do
		local top, best = -1, {}
		for _, s in ipairs(pool) do
			if rolls[s] > top then top, best = rolls[s], { s } elseif rolls[s] == top then best[#best + 1] = s end
		end
		if #best == 1 then
			local w = best[1]
			local seat = run.seats[w]
			seat.won[#seat.won + 1] = { item = dr.item, value = dr.value, drop = run.d, roll = rolls[w], pool = kind,
				ninja = kind == "need" and not I:CanUse(seat.class, dr.item) }
			seat.gold = seat.gold + dr.value
			-- who beat whom (Vexa and Snaggle remember)
			for _, s in ipairs(pool) do if s ~= w then run.beatBy[s] = w end end
			Emit(ev, "win", w, rolls[w], kind)
			winner = w
			break
		end
		tie = tie + 1
		pool = best
		local ts = Stream(run.seed, K_TIE, run.d, tie)
		rolls = {}
		for _, s in ipairs(pool) do rolls[s] = ts.int(1, 100) end
		Emit(ev, "roll", kind, rolls, true)
	end
	-- the honest-looking Needs are remembered (sharper tables read them)
	for s = 1, SEATS do
		if run.picks[s] == "N" then local h = run.needHistory[s] h[#h + 1] = dr.item end
	end
	-- Vexa, beaten on a roll: silence, then one word
	for _, s in ipairs(rolled) do
		if s ~= winner and run.seats[s].persona == "vexa" then Emit(ev, "tell", s, TELLS.vexa.lost) end
	end
end

-- ------------------------------------------------------------------ the end
function R:Finish(run, reason, ev)
	if run.phase == "over" then return end
	run.phase = "over"
	run.over = reason
	Emit(ev, "over", reason, R:Score(run))
end

function R:Score(run)
	local you = run.seats[1]
	local g = you.gold
	if you.kicked then return floor(g / 2), "kicked" end
	if run.phase == "over" and you.rep >= START_REP then return floor(g * 1.25 + 0.5), "fairplay" end
	return g, nil
end

-- the same run from its inputs ("N"/"G"/"P" picks and "0"-"5" calls, in order)
function R:Replay(dungeonId, seed, inputs, ev)
	local run = R:NewRun(dungeonId, seed, ev)
	for i = 1, #inputs do
		local c = inputs:sub(i, i)
		local ok
		if run.phase == "pick" then ok = R:Pick(run, c, ev)
		elseif run.phase == "call" then ok = R:Call(run, c, ev)
		else return run, "extra input at " .. i end
		if not ok then return run, "bad input at " .. i end
	end
	return run
end

return R
