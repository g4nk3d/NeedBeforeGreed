--[[ Need Before Greed - Game/Awards.lua
	Twelve achievements, each with its own badge. All are decided from the finished run alone (the rules
	keep everything needed), at the click that ends the run, so nothing is replayed or scanned later.

	  Aw.LIST                 { id, name, how } in the order the achievements screen shows them
	  Aw:Has(id)              earned by this character (the time it was earned, or nil)
	  Aw:Check(run)           a finished run: the achievements it earns now (a list, possibly empty)
	  Aw:Count()              earned, total ]]

local _, ns = ...
local P = ns.P
local Aw = P:Module("Awards")
local R = ns.Rules

Aw.LIST = {
	{ "first_win", "First Loot", "Win an item." },
	{ "lucky_low", "Lucky Low", "Win a roll with 10 or less." },
	{ "fair_play", "Fair Play", "Finish a run with all 3 reputation." },
	{ "clean_hands", "Clean Hands", "Finish a run without ever Needing an item your class can't use." },
	{ "sharp_eye", "Sharp Eye", "Catch two ninjas in one run." },
	{ "silver_tongue", "Silver Tongue", "Win an item your class can't use, Needed and never called." },
	{ "full_table", "Full Table", "Finish a run where nobody was kicked." },
	{ "mossgate_clear", "Mossgate Barrow", "Finish a run in Mossgate Barrow without being kicked." },
	{ "saltspire_clear", "Saltspire Keep", "Finish a run in Saltspire Keep without being kicked." },
	{ "gloomroot_clear", "Gloomroot Warren", "Finish a run in Gloomroot Warren without being kicked." },
	{ "cinderhold_clear", "Cinderhold", "Finish a run in Cinderhold without being kicked." },
	{ "sunken_observatory_clear", "The Sunken Observatory", "Finish a run in the Sunken Observatory without being kicked." },
}
local byId = {}
for _, a in ipairs(Aw.LIST) do byId[a[1]] = a end
Aw.byId = byId

local function Store()
	local c = P.char
	if not c then return nil end
	if type(c.ach) ~= "table" then c.ach = {} end
	return c.ach
end

function Aw:Has(id) local s = Store() return s and s[id] end

function Aw:Count()
	local s, n = Store(), 0
	if s then for _, a in ipairs(self.LIST) do if s[a[1]] then n = n + 1 end end end
	return n, #self.LIST
end

-- what a finished run proves (true/false per achievement)
function Aw.Earned(run)
	local you = run.seats[1]
	local kicked = you.kicked
	local got = {}
	got.first_win = #you.won > 0
	for _, w in ipairs(you.won) do
		if w.roll and w.roll <= 10 then got.lucky_low = true end
		if w.ninja then got.silver_tongue = true end
	end
	if not kicked then
		got.fair_play = you.rep >= R.START_REP
		got.clean_hands = you.ninjas == 0
		local anyKicked = false
		for s = 2, R.SEATS do if run.seats[s].kicked then anyKicked = true end end
		got.full_table = not anyKicked
		got[run.dungeon.id .. "_clear"] = true
	end
	got.sharp_eye = you.rightCalls >= 2
	return got
end

function Aw:Check(run)
	local new = {}
	local s = Store()
	if not s or P.readOnly or P.testOpen then return new end
	local got = self.Earned(run)
	local now = time and time() or 0
	for _, a in ipairs(self.LIST) do
		if got[a[1]] and not s[a[1]] then
			s[a[1]] = now
			new[#new + 1] = a
		end
	end
	return new
end
