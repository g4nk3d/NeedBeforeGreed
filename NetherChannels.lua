--[[ NetherChannels.lua - the Nether family's hidden channels stay out of the way (shared)

	Every Nether addon with a hidden data channel (AutoLayerLFG, NetherMapsNet, NetherSearchNet,
	PiggleScores) ships this same file. Whichever copy loads first defines _G.NetherChannels; a newer
	copy (a higher VERSION) replaces an older one's code and keeps its list.

	Why: a custom channel the player was in last session is re-joined at login BEFORE the game's own
	zone channels, so it takes /1 and General becomes /4: a player typing "/1 hello" talks in the wrong
	place. The game numbers channels by their place in the list, and the chat settings let the player
	drag them into another order; this file does the same drag for the family's channels: each one moves
	behind every channel that is not a family channel (the game's and the player's own), so General,
	Trade and the rest keep /1, /2... The family's channels never move past each other, so addons using
	this file can't fight over the order.

	  NetherChannels:Settle(name [, onMoved])   call after joining `name`; it checks now, after 5 s and
	                                            after 20 s (zone channels arrive late), and again after
	                                            every loading screen. onMoved(newId) when it moved.
	  NetherChannels:IsFamily(name)             one of the family's hidden channels
	  NetherChannels:Supported()                the client can reorder channels

	Never in combat (it waits). Nothing happens on clients without the reorder call. ]]

local VERSION = 1

local C = _G.NetherChannels
if type(C) == "table" and (tonumber(C.version) or 0) >= VERSION then return end
C = type(C) == "table" and C or {}
_G.NetherChannels = C
C.version = VERSION
C.family = C.family or { autolayerlfg = true, nethermapsnet = true, nethersearchnet = true, pigglescores = true }
C.watch = C.watch or {}          -- name -> onMoved

local function Swap()
	local ci = _G.C_ChatInfo
	return (ci and ci.SwapChatChannelsByChannelIndex) or _G.SwapChatChannelsByChannelIndex
end

function C:Supported() return type(Swap()) == "function" and type(_G.GetChannelList) == "function" end

function C:IsFamily(name) return type(name) == "string" and self.family[name:lower()] == true end

-- the channel list as { [id] = name }, and the highest id in use
local function List()
	local t = { GetChannelList() }
	local out, top = {}, 0
	local i = 1
	while i <= #t do
		local id, name = t[i], t[i + 1]
		-- current clients give id, name, disabled; older ones id, name
		local step = (type(t[i + 2]) == "boolean") and 3 or 2
		if type(id) == "number" and type(name) == "string" then
			out[id] = name
			if id > top then top = id end
		end
		i = i + step
	end
	return out, top
end

-- move `name` behind the last channel that isn't a family one; true when it moved
function C:Move(name)
	if not self:Supported() then return false end
	if InCombatLockdown and InCombatLockdown() then return false end
	local list, top = List()
	local at
	for id, n in pairs(list) do if n:lower() == name:lower() then at = id end end
	if not at then return false end
	local last = 0
	for id, n in pairs(list) do if not self:IsFamily(n) and id > last then last = id end end
	if last <= at then return false end
	-- one step at a time, as the chat settings' drag does: each swap moves it one place down
	local swap = Swap()
	for i = at, last - 1 do
		local ok = pcall(swap, i, i + 1)
		if not ok then return i ~= at end
	end
	return true
end

local function Check(name)
	if C:Move(name) then
		local fn = C.watch[name]
		local id = GetChannelName and GetChannelName(name)
		if fn then pcall(fn, id) end
	end
end

function C:Settle(name, onMoved)
	if type(name) ~= "string" or name == "" then return end
	self.family[name:lower()] = true
	self.watch[name] = onMoved or self.watch[name] or false
	local after = (C_Timer and C_Timer.After) or function() end
	Check(name)
	after(5, function() Check(name) end)
	after(20, function() Check(name) end)
end

-- after every loading screen (zone channels change), check every watched channel again
if not C.frame then
	C.frame = CreateFrame("Frame")
	C.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	C.frame:RegisterEvent("PLAYER_REGEN_ENABLED")
	C.frame:SetScript("OnEvent", function(_, event)
		local delay = event == "PLAYER_ENTERING_WORLD" and 6 or 1
		if C_Timer and C_Timer.After then
			C_Timer.After(delay, function() for name in pairs(C.watch) do Check(name) end end)
		end
	end)
end
