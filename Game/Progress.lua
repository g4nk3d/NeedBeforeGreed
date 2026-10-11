--[[ Need Before Greed - Game/Progress.lua
	This character's records per dungeon, the medals and which dungeons are open.

	  Pr:Record(id)              { best, medal, runs, kicks, finished } or nil
	  Pr:Open(id)                Mossgate Barrow is open; each later dungeon opens once you finish the one
	                             before without being kicked
	  Pr:MedalFor(id, score, kicked)   0 none, 1 bronze (finished, not kicked), 2 silver, 3 gold
	  Pr:Finish(run)             a finished run: keeps the best; returns medal, isNewBest, previousBest, opened
	  Pr:Next(id)                the dungeon after this one (or nil)

	Medal scores come from the balance tool (tools/nbg_sim.lua, 4,000 runs a dungeon): silver is about what
	a careful honest player averages, gold needs good luck and well-judged calls. ]]

local _, ns = ...
local P = ns.P
local Pr = P:Module("Progress")
local I = ns.Items
local R = ns.Rules

-- silver, gold
Pr.MEDALS = {
	mossgate = { 60, 200 },
	saltspire = { 60, 240 },
	gloomroot = { 100, 320 },
	cinderhold = { 90, 380 },
	sunken_observatory = { 130, 460 },
}
Pr.MEDAL_NAME = { "Bronze", "Silver", "Gold" }

function Pr:Dungeons() return I.DUNGEONS end

function Pr:Record(id)
	local c = P.char
	return c and c.dungeons and c.dungeons[id]
end

function Pr:Open(id)
	local dg = I:Dungeon(id)
	if not dg then return false end
	if dg.index == 1 or P.testOpen then return true end
	local prev = I.DUNGEONS[dg.index - 1]
	local rec = self:Record(prev.id)
	return rec ~= nil and (rec.finished or 0) > 0
end

function Pr:Next(id)
	local dg = I:Dungeon(id)
	return dg and I.DUNGEONS[dg.index + 1]
end

function Pr:MedalFor(id, score, kicked)
	if kicked then return 0 end
	local m = self.MEDALS[id]
	if not m then return 1 end
	if score >= m[2] then return 3 end
	if score >= m[1] then return 2 end
	return 1
end

-- medal points over all dungeons (for NetherSuite's status line)
function Pr:Count()
	local done, points = 0, 0
	for _, dg in ipairs(I.DUNGEONS) do
		local rec = self:Record(dg.id)
		if rec and (rec.finished or 0) > 0 then done = done + 1 end
		points = points + (rec and rec.medal or 0)
	end
	return done, #I.DUNGEONS, points
end

function Pr:Finish(run)
	local id = run.dungeon.id
	local score, how = R:Score(run)
	local kicked = how == "kicked"
	local medal = self:MedalFor(id, score, kicked)
	if not P.char or P.readOnly or P.testOpen then return medal, false, nil, nil end
	local recs = P.char.dungeons
	local rec = recs[id]
	if not rec then rec = { medal = 0, runs = 0, kicks = 0, finished = 0 } recs[id] = rec end
	local wasOpen = {}
	for _, dg in ipairs(I.DUNGEONS) do wasOpen[dg.id] = self:Open(dg.id) end
	rec.runs = rec.runs + 1
	if kicked then rec.kicks = rec.kicks + 1 else rec.finished = rec.finished + 1 end
	local prev = rec.best
	local newBest = false
	if not kicked and (not prev or score > prev) then rec.best = score newBest = prev ~= nil end
	if medal > (rec.medal or 0) then rec.medal = medal end
	local opened
	for _, dg in ipairs(I.DUNGEONS) do
		if not wasOpen[dg.id] and self:Open(dg.id) then opened = dg end
	end
	return medal, newBest, prev, opened
end
