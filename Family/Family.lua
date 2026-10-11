--[[ Need Before Greed - Family/Family.lua
	Settings in one place, the slash commands, and Need Before Greed's tile in NetherSuite (all optional:
	Need Before Greed plays exactly the same alone).

	  P:Setting(key) / P:SetSetting(key, value)   applied at once wherever it is changed
	  /nbg, /needbeforegreed           open or close the game 
	  /nbg reset             forget this character's Need Before Greed records (asks first)
	  /nbg perf              frame time and memory
	  /nbg debug             errors and missing art ]]

local ADDON, ns = ...
local P = ns.P

local DEFAULTS = { music = true, sound = true, nudge = false, size = 0.9, followNetherUI = true, minimapButton = true,
	quick = false, shareScores = true }
P.SETTING_DEFAULTS = DEFAULTS

function P:Setting(key)
	local st = self.db and self.db.settings
	local v = st and st[key]
	if v == nil then return DEFAULTS[key] end
	return v
end

function P:SetSetting(key, value)
	if not self.db then return end
	local was = self:Setting(key)
	self.db.settings[key] = value
	if was == value then return end
	local G = self.Game
	if key == "music" then
		if not value then self.Audio:StopMusic()
		elseif G and G.IsOpen and G:IsOpen() then self.Audio:Music(G.screen and "music_ledger" or "music_table") end
	elseif key == "shareScores" then
		if self.Leaderboard then self.Leaderboard:SetEnabled(value) end
	elseif key == "size" then
		if G then G:FitScale() end
	elseif key == "minimapButton" then
		if self.Minimap and self.Minimap.SetShown then self.Minimap:SetShown(value) end
	end
	self:Fire("SETTINGS_CHANGED", key)
end

-- ------------------------------------------------------------------ NetherSuite
local LABELS = {
	{ "music", "Music", { "music", "sound" } },
	{ "sound", "Sound effects", { "sound", "sfx", "effects" } },
	{ "nudge", "Remind me after 20 minutes of play", { "reminder", "nudge", "break", "time" } },
	{ "minimapButton", "Show the minimap button", { "minimap", "button" } },
	{ "quick", "Faster table", { "speed", "fast", "quick", "animation" } },
	{ "shareScores", "Share daily scores with other players", { "scores", "leaderboard", "share", "channel", "daily" } },
	{ "followNetherUI", "Follow NetherUI's theme (options page)", { "theme", "look", "netherui", "skin" } },
}

local function Settings()
	local list = {}
	for _, l in ipairs(LABELS) do
		local key = l[1]
		list[#list + 1] = { id = key, kind = "toggle", label = l[2], page = "general", keywords = l[3],
			get = function() return P:Setting(key) and true or false end,
			set = function(v) P:SetSetting(key, v and true or false) end }
	end
	return list
end

local function Status()
	local Pr = P.Progress
	local lines = {}
	for _, dg in ipairs(Pr:Dungeons()) do
		local rec = Pr:Record(dg.id)
		local text
		if not Pr:Open(dg.id) then text = "locked"
		elseif rec and rec.best then text = ("best %d gold, %s"):format(rec.best, Pr.MEDAL_NAME[rec.medal] or "no medal")
		else text = "not finished yet" end
		lines[#lines + 1] = { dg.name, text }
	end
	return lines
end

local function Descriptor()
	return {
		id = "needbeforegreed", name = "Need Before Greed", version = P.VERSION, apiVersion = 1, addon = ADDON,
		icon = P.MEDIA .. "Logo", banner = P.MEDIA .. "Banner",
		description = "A loot-table game of bluff and nerve: Need, Greed or Pass in secret, call ninja on the greedy, and leave with the best haul without getting kicked.",
		category = "Games", slash = { "/nbg", "/needbeforegreed" },
		pages = { { id = "general", label = "General" } },
		settings = Settings(),
		open = function() P.Game:Open() return true end,
		focus = function() if P.Options and P.Options.Open then P.Options:Open() else P.Game:Open() end return true end,
		status = Status,
	}
end

local joined = false
local function JoinSuite()
	if joined then return end
	local S = rawget(_G, "NetherSuite")
	if type(S) == "table" and type(S.RegisterAddon) == "function" then
		joined = pcall(S.RegisterAddon, S, Descriptor())
	elseif C_AddOns and C_AddOns.DoesAddOnExist and C_AddOns.DoesAddOnExist("NetherSuite") then
		NetherSuite_Queue = NetherSuite_Queue or {}
		table.insert(NetherSuite_Queue, Descriptor())
		joined = true
	end
end

P:Register("LOGIN", JoinSuite)
P:On("ADDON_LOADED", function(_, name)
	if name == "NetherSuite" and P.loggedIn then P:After(0, JoinSuite) end
end)

if NetherFamily then
	if NetherFamily.Slash then NetherFamily:Slash(ADDON, "NEEDBEFOREGREED", "Need Before Greed") end
end

-- ------------------------------------------------------------------ slash commands
local confirmReset = 0
local function Slash(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")
	if msg == "perf" then
		P.Game:Perf()
	elseif msg == "debug" then
		P.debug = not P.debug
		P:Print("version %s, schema %d, %d error(s), %d missing art; error messages in chat %s.", P.VERSION, P.SCHEMA,
			#P.errors, #P.Assets.missing, P.debug and "on" or "off")
		for _, e in ipairs(P.errors) do P:Print("  %s%s", e.text, e.n > 1 and (" (x" .. e.n .. ")") or "") end
		for _, e in ipairs(P.Assets.missing) do P:Print("  missing: %s", e) end
	elseif msg == "reset" then
		local now = GetTime()
		if now - confirmReset > 10 then
			confirmReset = now
			P:Print("this forgets every dungeon record, medal, daily result and achievement of this character, and the run in progress. Type /nbg reset again within 10 seconds to confirm.")
			return
		end
		confirmReset = 0
		if P.char then
			wipe(P.char.dungeons)
			P.char.resume = nil
			P.char.daily, P.char.dailyDays, P.char.ach, P.char.seal = nil, nil, nil, nil
		end
		P.Game:Forget()
		P:Print("this character's records have been reset.")
	elseif msg == "testopen" then
		-- for testing: every dungeon open until the next /reload (nothing is saved, no medals given)
		P.testOpen = not P.testOpen
		P:Print("every dungeon is %s for this session%s.", P.testOpen and "open" or "back to normal", P.testOpen and " (results are not saved)" or "")
		local G = P.Game
		if G.screen == "dungeons" and G.screens.dungeons then G.screens.dungeons:Refresh() end
	elseif msg == "daily" then
		P.Game:Open()
		if P.Game:IsOpen() then P.Game:Screen("daily") end
	elseif msg == "help" or msg == "?" then
		P:Print("/nbg opens the game. Also: /nbg daily, /nbg perf, /nbg debug, /nbg reset.")
	else
		P.Game:Toggle()
	end
end

SLASH_NEEDBEFOREGREED1 = "/nbg"
SLASH_NEEDBEFOREGREED2 = "/needbeforegreed"
SlashCmdList.NEEDBEFOREGREED = function(msg) P:Safe("slash", Slash, msg) end
