--[[ Need Before Greed - UI/Window.lua
	The game window: the table (UI/Table.lua), your controls (Need, Greed, Pass, No call), the counters,
	the screens (menu, dungeons, how to play, the Ledger results, who-can-use-what, paused, welcome),
	keyboard, combat safety and the one OnUpdate driver.

	  G:Open() / G:Close() / G:Toggle()
	  G:Start(dungeonId [, seed, inputs])   a new run (seed and inputs: the same run again, e.g. after /reload)
	  G:Pick("N" | "G" | "P"), G:Call(seat | 0)
	  G:Screen(name)                        a screen over the table (nil = back to the table)
	  G:Perf()                              the /nbg perf readout

	States: Menu -> Table (picks and calls) -> Ledger (results) -> Table / Menu. Combat at any time: the
	table is skipped to the end of what was playing, the keyboard is let go and the window hides; after
	combat it comes back paused and only a click on Resume continues. The run is saved as its seed plus
	your inputs after every decision, so a /reload comes back to the same drop. ]]

local _, ns = ...
local P = ns.P
local G = P:Module("Game")
local A, Au, UI, Tb, Pr = P.Assets, P.Audio, P.UI, P.Table, P.Progress
local R, I = ns.Rules, ns.Items

local floor, max, min = math.floor, math.max, math.min
local WIN_W, WIN_H = 1000, 700

local W                 -- the window, built on first open
local hud = {}
local screens = {}
local run               -- the run on the table
local ready = false     -- the table has finished playing and waits for you
local perf = { n = 0, sum = 0, max = 0, over = 0, tags = {} }

local function InCombat() return InCombatLockdown and InCombatLockdown() end

-- ------------------------------------------------------------------ helpers
local function Panel(parent, w, h)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(w, h)
	f:EnableMouse(true)
	UI:Slice9(f, "BACKGROUND", 0, "inner_panel", 40, 64)
	return f
end

local MEDAL = { "bronze", "silver", "gold" }
local function MedalSprite(m, size)
	if not m or m < 1 then return nil end
	return ("medal_%s_%s_earned"):format(MEDAL[m], size or "64")
end

-- a texture on the window by its centre (top-left origin, window pixels)
local function Place(region, x, y, w, h)
	region:ClearAllPoints()
	region:SetPoint("CENTER", W, "TOPLEFT", x, -y)
	if w then region:SetSize(w, h) end
end

local function NewSeed()
	local t = (time and time() or 0) % 1000000
	local g = floor(((GetTime and GetTime() or 0) * 1000) % 1000000)
	return (t * 7919 + g * 104729) % 2147483646 + 1
end

-- the ribbon title: only the parchment between the rolled ends takes text (measured on the art:
-- x 270..760 of 1024, its middle row at y 105 of 192), so the words shrink until they fit there
local RIBBON_W, RIBBON_H = 440, 83
local PARCH_W = (760 - 270) / 1024 * RIBBON_W - 16
local PARCH_DY = (105 - 96) / 192 * RIBBON_H

local function FitRibbon(fs, text)
	fs:SetText(text)
	for size = 20, 10, -1 do
		local font, _, flags = fs:GetFont()
		if font then fs:SetFont(font, size, flags) end
		local w = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
		if not w or w <= PARCH_W then break end
	end
end

local function Ribbon(parent, text, dy)
	local r = parent:CreateTexture(nil, "ARTWORK")
	A:Sprite(r, "title_ribbon")
	r:SetSize(RIBBON_W, RIBBON_H)
	r:SetPoint("TOP", parent, "TOP", 0, dy or 40)
	local fs = UI:Text(parent, 20, "ink")
	fs:SetPoint("CENTER", r, "CENTER", 0, -PARCH_DY)
	fs:SetWordWrap(false)
	fs.SetTitle = FitRibbon
	FitRibbon(fs, text)
	parent.ribbon = fs
	return fs
end

-- ------------------------------------------------------------------ your controls
local CHOICES = { { "N", "need", "Need", "1" }, { "G", "greed", "Greed", "2" }, { "P", "pass", "Pass", "3" } }
local CHOICE_TIP = {
	N = "Roll Need: you win before anyone who Greeds. Honest if your class can use it. If not, and someone calls ninja on you, you lose 1 reputation and your Need is cancelled.",
	G = "Roll Greed: you roll only if nobody Needs. Always safe.",
	P = "Pass: you don't roll for this item.",
}

local CHOICE_ART = {}
for _, k in ipairs({ "need", "greed", "pass" }) do
	CHOICE_ART[k] = {}
	for _, s in ipairs({ "normal", "hover", "pressed", "disabled", "locked_in" }) do CHOICE_ART[k][s] = ("choice_%s_%s"):format(k, s) end
end
local function ChoiceArt(b, state) A:Sprite(b.art, CHOICE_ART[b.key][state]) end

local function RefreshChoices()
	local mine = run and run.picks and run.picks[1]
	local can = ready and run and run.phase == "pick"
	for _, b in ipairs(hud.choices) do
		b.pickable = can
		if can then ChoiceArt(b, b.hover and "hover" or "normal")
		elseif mine == b.choice or (mine == "X" and b.choice == "N") then ChoiceArt(b, "locked_in")
		else ChoiceArt(b, "disabled") end
		b.label:SetAlpha((can or mine == b.choice) and 1 or 0.55)
	end
end

local function Status(text) hud.status:SetText(text or "") end

local DROP_TEXT = {}
for d = 1, R.DROPS do DROP_TEXT[d] = ("%d/%d"):format(d, R.DROPS) end
local function UpdateCounters()
	if not run then return end
	local d = min(run.d, R.DROPS)
	G.FitLine(hud.drop, DROP_TEXT[max(1, d)], hud.drop.fitW, 14)
	G.FitLine(hud.haul, Tb.NUM[#run.seats[1].won] or "", hud.haul.fitW, 14)
end

-- the table finished playing: what do you do now?
local function Ready()
	ready = true
	if not run then return end
	UpdateCounters()
	if run.phase == "pick" then
		Tb:ShowCalls(nil)
		hud.nocall:Hide()
		local dr = run.drops[run.d]
		local yours = I:CanUse(run.seats[1].class, dr.item)
		Status(yours and "Your pick. Your class can use this." or "Your pick. Your class can't use this.")
	elseif run.phase == "call" then
		local targets = R:Targets(run, 1)
		Tb:ShowCalls(targets)
		hud.nocall:Show()
		Status(("Your call (%d left): click a Needer to call ninja, or No call."):format(run.seats[1].calls))
	elseif run.phase == "over" then
		Tb:ShowCalls(nil)
		hud.nocall:Hide()
		Status("")
		G:ShowResults()
	end
	RefreshChoices()
end

local function SaveRun()
	if not P.char or P.readOnly then return end
	if run and run.phase ~= "over" then
		P.char.resume = { dungeon = run.dungeon.id, seed = run.seed, inputs = run.inputs, daily = run.daily }
	else
		P.char.resume = nil
	end
end

-- ------------------------------------------------------------------ building
local function Build()
	W = CreateFrame("Frame", nil, UIParent)
	G.W = W
	G.hud = hud
	W:SetSize(WIN_W, WIN_H)
	W:SetPoint("CENTER")
	W:SetFrameStrata("HIGH")
	W:SetToplevel(true)
	W:SetClampedToScreen(true)
	W:SetMovable(true)
	W:EnableMouse(true)
	W:Hide()

	local base = W:CreateTexture(nil, "BACKGROUND", nil, -8)
	base:SetPoint("TOPLEFT", 12, -12)
	base:SetPoint("BOTTOMRIGHT", -12, 12)
	base:SetColorTexture(0.06, 0.045, 0.035, 1)

	-- the table scene
	Tb:Build(W)
	Tb.scene:SetFrameLevel(W:GetFrameLevel() + 2)
	Tb.onSeat = function(s) G:Call(s) end
	Tb.onDrop = function() UpdateCounters() end
	Tb.onWin = function(w)
		UpdateCounters()
		if w == 1 then Au:Play("coin_tally_loop") end
	end

	-- the carved frame over everything
	local frame = CreateFrame("Frame", nil, W)
	frame:SetAllPoints()
	frame:SetFrameLevel(W:GetFrameLevel() + 30)
	-- the frame art with its leather middle cleared at build time: only the rim and the corners cover the edge
	local border = UI:Slice9(frame, "BORDER", 0, "main_window_frame", 44, 64)
	border[5]:Hide()

	-- the top: drag strip with the dungeon's ribbon, the drop and haul counters, close
	local top = CreateFrame("Frame", nil, W)
	top:SetPoint("TOPLEFT", 0, 0)
	top:SetPoint("TOPRIGHT", 0, 0)
	top:SetHeight(84)
	top:SetFrameLevel(W:GetFrameLevel() + 32)
	top:EnableMouse(true)
	top:RegisterForDrag("LeftButton")
	top:SetScript("OnDragStart", function() if not InCombat() then W:StartMoving() end end)
	top:SetScript("OnDragStop", function()
		W:StopMovingOrSizing()
		local p, _, rp, x, y = W:GetPoint(1)
		P.db.window = { p, rp, x, y }
	end)
	hud.title = Ribbon(top, "Need Before Greed", -2)
	-- the counters: only the small parchment window between the two jewels takes the number (measured on the
	-- art: x 94..162 of 256, 0.27 of the width), so it holds just "3/8"; the word goes on a caption under it
	local function Counter(sprite, x, caption, tip)
		local f = CreateFrame("Frame", nil, top)
		f:SetSize(190, 71)
		f:SetPoint("CENTER", W, "TOPLEFT", x, -44)
		local t = f:CreateTexture(nil, "ARTWORK")
		t:SetAllPoints()
		A:Sprite(t, sprite)
		local fs = UI:Text(f, 14, "ink")
		fs:SetPoint("CENTER", 0, 0)
		fs:SetWordWrap(false)
		fs.fitW = 190 * 68 / 256 - 6
		local cap = UI:Text(f, 11, "light")
		cap:SetPoint("TOP", f, "BOTTOM", 0, 8)
		cap:SetText(caption)
		f:EnableMouse(true)
		UI:Tip(f, tip[1], tip[2])
		return fs
	end
	hud.drop = Counter("drop_counter", 182, "Drop", { "Drops", "Eight drops a run. The last one is the boss's: rare or epic." })
	hud.haul = Counter("haul_counter", 818, "Won", { "Your haul", "Items you have won. What they are worth stays a secret until the Ledger at the end of the run." })
	local close = UI:Close(top, function() G:Close() end)
	close:SetPoint("TOPRIGHT", W, "TOPRIGHT", -16, -16)
	UI:Tip(close, "Close", "Your run is kept: open Need Before Greed again to carry on.")

	-- the front: menu buttons at the left, your choices in the middle (the party chat is the table's)
	local front = CreateFrame("Frame", nil, W)
	front:SetAllPoints()
	front:SetFrameLevel(W:GetFrameLevel() + 20)
	hud.front = front
	local function Sq(y, icon, tip, fn)
		local b = UI:Square(front, icon, 44, tip, fn)
		b:SetPoint("CENTER", W, "TOPLEFT", 48, -y)
		return b
	end
	Sq(534, "icon_pause", "Menu  (Esc)", function() G:Screen("menu") end)
	Sq(584, "icon_help", "Who can use what?  (C)", function() G:Screen("reference") end)
	hud.sound = Sq(634, "icon_sound_on", "Sound on or off", function()
		P:SetSetting("sound", not P:Setting("sound"))
		hud.sound:SetIcon(P:Setting("sound") and "icon_sound_on" or "icon_sound_off")
	end)
	hud.sound:SetIcon(P:Setting("sound") and "icon_sound_on" or "icon_sound_off")

	hud.status = UI:Text(front, 13, "light")
	hud.status:SetPoint("CENTER", W, "TOPLEFT", 480, -518)
	hud.status:SetWidth(380)
	hud.status:SetWordWrap(true)
	hud.choices = {}
	for i, c in ipairs(CHOICES) do
		local b = CreateFrame("Button", nil, front)
		b:SetSize(80, 80)
		b:SetPoint("CENTER", W, "TOPLEFT", 480 + (i - 2) * 96, -572)
		b.choice, b.key = c[1], c[2]
		b.art = b:CreateTexture(nil, "ARTWORK")
		b.art:SetAllPoints()
		b.label = UI:Text(b, 13, "title")
		b.label:SetPoint("TOP", b, "BOTTOM", 0, -2)
		b.label:SetText(("%s |cffb8a888(%s)|r"):format(c[3], c[4]))
		b:SetScript("OnEnter", function(self) self.hover = true if self.pickable then ChoiceArt(self, "hover") Au:Play("ui_hover") end end)
		b:SetScript("OnLeave", function(self) self.hover = false if self.pickable then ChoiceArt(self, "normal") end end)
		b:SetScript("OnMouseDown", function(self) if self.pickable then ChoiceArt(self, "pressed") end end)
		b:SetScript("OnClick", function(self) G:Pick(self.choice) end)
		UI:Tip(b, c[3], CHOICE_TIP[c[1]])
		hud.choices[i] = b
	end
	hud.nocall = UI:Wide(front, "No call", 160, function() G:Call(0) end, "ui_cancel")
	hud.nocall:SetPoint("CENTER", W, "TOPLEFT", 480, -654)
	hud.nocall:SetFrameLevel(front:GetFrameLevel() + 4)
	UI:Tip(hud.nocall, "No call  (Space)", "Let every Need stand this drop.")
	hud.nocall:Hide()
	RefreshChoices()

	-- the screens' shade
	local shade = CreateFrame("Frame", nil, W)
	shade:SetPoint("TOPLEFT", 14, -14)
	shade:SetPoint("BOTTOMRIGHT", -14, 14)
	shade:SetFrameLevel(W:GetFrameLevel() + 50)
	shade:EnableMouse(true)
	local sh = shade:CreateTexture(nil, "BACKGROUND")
	sh:SetAllPoints()
	sh:SetColorTexture(0.03, 0.02, 0.02, 0.8)
	shade:Hide()
	G.shade = shade

	W:SetScript("OnKeyDown", function(self, key)
		if InCombat() then return end
		local handled = G:Key(key)
		self:SetPropagateKeyboardInput(not handled)
	end)
	W:SetScript("OnShow", function() G:Shown() end)
	W:SetScript("OnHide", function() G:Hidden() end)
	G:FitScale()
	local wp = P.db.window
	if type(wp) == "table" and type(wp[1]) == "string" and type(wp[3]) == "number" and type(wp[4]) == "number" then
		W:ClearAllPoints()
		if not pcall(W.SetPoint, W, wp[1], UIParent, wp[2] or wp[1], wp[3], wp[4]) then W:SetPoint("CENTER") end
	end
end

-- ------------------------------------------------------------------ screens (each built the first time it is shown)
local function ScreenFrame(name, w, h, bare)
	local f = bare and CreateFrame("Frame", nil, G.shade) or Panel(G.shade, w, h)
	if bare then f:SetSize(w, h) f:EnableMouse(true) end
	f:SetPoint("CENTER", G.shade, "CENTER")
	f:SetFrameLevel(G.shade:GetFrameLevel() + 2)
	f:Hide()
	screens[name] = f
	return f
end
G.ScreenFrame, G.Ribbon, G.MedalSprite, G.screens = ScreenFrame, Ribbon, MedalSprite, screens

local lazy = {}
G.lazy = lazy

-- the main menu: the Ledger's cover at the left, the title and the buttons at the right
lazy.menu = function()
	local m = ScreenFrame("menu", 972, 672, true)
	local cover = m:CreateTexture(nil, "ARTWORK")
	A:Sprite(cover, "S_ledger_cover")
	cover:SetSize(560, 560)
	cover:SetPoint("TOPLEFT", m, "TOPLEFT", 24, -60)
	-- the brass plate on the cover (x 344..840, y 176..376 of 1024): engraved lettering
	local k = 560 / 1024
	local plate = UI:Text(m, 22, "ink")
	plate:SetPoint("CENTER", cover, "TOPLEFT", 592 * k, -268 * k)
	plate:SetWidth(230)
	plate:SetText("The Loot Ledger")
	plate:SetTextColor(0.2, 0.12, 0.04)
	m.who = UI:Text(m, 13, "ink")
	m.who:SetPoint("TOP", plate, "BOTTOM", 0, -4)
	m.who:SetWidth(230)
	m.who:SetTextColor(0.24, 0.15, 0.06)
	local wm = m:CreateTexture(nil, "ARTWORK")
	wm:SetTexture(P.MEDIA .. "Wordmark")
	wm:SetTexCoord(0, 1, 0, 151 / 256)
	wm:SetSize(340, 100)
	wm:SetPoint("TOP", m, "TOPLEFT", 776, -56)
	local tag = UI:Text(m, 13, "light")
	tag:SetPoint("TOP", wm, "BOTTOM", 0, -8)
	tag:SetWidth(320)
	tag:SetText("Five strangers, one loot table. Need only what your class can use... or don't get caught.")
	-- this character's totals, tooled into the leather under the plate
	m.records = UI:Text(m, 14, "title")
	m.records:SetPoint("CENTER", cover, "TOPLEFT", 300, -330)
	m.records:SetWidth(300)
	m.records:SetSpacing(6)
	local n = 0
	local function MB(label, fn, sound)
		local b = UI:Wide(m, label, 220, fn, sound)
		b:SetPoint("TOP", m, "TOPLEFT", 776, -222 - n * 60)
		n = n + 1
		return b
	end
	m.cont = MB("Continue", function() G:Screen(nil) end, "ui_confirm")
	MB("Dungeons", function() G:Screen("dungeons") end)
	MB("Daily Run", function() G:Screen("daily") end)
	MB("Achievements", function() G:Screen("achievements") end)
	MB("How to Play", function() G:Screen("help") end)
	MB("Who Can Use What", function() G:Screen("reference") end)
	MB("Close", function() G:Close() end, "ui_cancel")
	function m:Refresh()
		self.cont:SetEnabled(run ~= nil and run.phase ~= "over")
		local done, total, points = Pr:Count()
		local got, all = P.Awards:Count()
		self.records:SetText(("Dungeons finished: %d of %d\nMedal points: %d of %d\nAchievements: %d of %d\nDaily runs finished: %d"):format(
			done, total, points, total * 3, got, all, P.Daily:DaysPlayed()))
		self.who:SetText(UnitName and UnitName("player") or "")
	end
end

-- the dungeons: five cards, each opens once the one before is finished without being kicked
local CARD_W, CARD_H = 360, 180
local CARD_POS = { { 260, 150 }, { 712, 150 }, { 260, 352 }, { 712, 352 }, { 486, 554 } }
lazy.dungeons = function()
	local d = ScreenFrame("dungeons", 972, 672, true)
	Ribbon(d, "Choose a Dungeon", -4)
	d.cards = {}
	local L = ns.Layout.mossgate_select_card
	local k = CARD_W / L.size[1]
	for i, dg in ipairs(I.DUNGEONS) do
		local b = CreateFrame("Button", nil, d)
		b:SetSize(CARD_W, CARD_H)
		b:SetPoint("CENTER", d, "TOPLEFT", CARD_POS[i][1], -CARD_POS[i][2])
		b.art = b:CreateTexture(nil, "ARTWORK")
		b.art:SetAllPoints()
		A:Sprite(b.art, dg.id .. "_select_card")
		local tr, dr = L.scene_title, L.description_and_selection
		b.name = UI:Text(b, 13, "title")
		b.name:SetPoint("TOPLEFT", b, "TOPLEFT", tr[1] * k, -tr[2] * k)
		b.name:SetSize(tr[3] * k, tr[4] * k)
		b.name:SetText(dg.name)
		b.info = UI:Text(b, 10, "light", "LEFT")
		b.info:SetPoint("TOPLEFT", b, "TOPLEFT", dr[1] * k + 2, -dr[2] * k)
		b.info:SetSize(dr[3] * k - 4, dr[4] * k)
		b.info:SetJustifyV("TOP")
		b.info:SetSpacing(2)
		b.medal = b:CreateTexture(nil, "OVERLAY")
		b.medal:SetSize(44, 44)
		b.medal:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -8, 8)
		b.lock = b:CreateTexture(nil, "OVERLAY")
		A:Sprite(b.lock, "lock")
		b.lock:SetSize(48, 48)
		b.lock:SetPoint("CENTER", b, "TOPLEFT", 152 * k, -128 * k)
		b.dg = dg
		b:SetScript("OnEnter", function(self) if not self.locked then self.art:SetVertexColor(1.15, 1.1, 1) Au:Play("ui_hover") end end)
		b:SetScript("OnLeave", function(self) self.art:SetVertexColor(1, 1, 1) end)
		b:SetScript("OnClick", function(self)
			if self.locked then Au:Play("ui_error") return end
			Au:Play("ui_confirm")
			G:Start(self.dg.id)
		end)
		UI:Tip(b, function(self)
			if self.locked then
				local prev = I.DUNGEONS[i - 1]
				return dg.name, ("Finish a run in %s without being kicked to open it."):format(prev and prev.name or "the dungeon before")
			end
			local m = Pr.MEDALS[dg.id]
			return dg.name, ("%s\n\nBronze: finish without being kicked.\nSilver: %d gold.   Gold: %d gold."):format(dg.about or "", m[1], m[2])
		end)
		d.cards[i] = b
	end
	local back = UI:Wide(d, "Back", 160, function() G:Screen(run and run.phase ~= "over" and nil or "menu") end, "ui_cancel")
	back:SetPoint("CENTER", d, "TOPLEFT", 110, -630)
	function d:Refresh()
		for _, b in ipairs(self.cards) do
			local dg = b.dg
			local open = Pr:Open(dg.id)
			b.locked = not open
			b.art:SetDesaturated(not open)
			b.art:SetAlpha(open and 1 or 0.7)
			b.lock:SetShown(not open)
			local rec = Pr:Record(dg.id)
			local lines = { ("Boss: %s"):format(dg.boss), ("Calls: %d each"):format(dg.calls) }
			if rec and rec.best then lines[#lines + 1] = ("Best: %d gold"):format(rec.best) end
			if rec and (rec.runs or 0) > 0 then lines[#lines + 1] = ("Runs: %d   Kicked: %d"):format(rec.runs, rec.kicks or 0) end
			b.info:SetText(table.concat(lines, "\n"))
			local ms = MedalSprite(rec and rec.medal)
			if ms then A:Sprite(b.medal, ms) b.medal:Show() else b.medal:Hide() end
		end
	end
end

-- the daily run: the day's card (date, dungeon, your best) and Play
lazy.daily = function()
	local d = ScreenFrame("daily", 620, 560)
	Ribbon(d, "Daily Run")
	local card = d:CreateTexture(nil, "ARTWORK")
	A:Sprite(card, "daily_card")
	card:SetSize(448, 224)
	card:SetPoint("TOP", d, "TOP", 0, -52)
	local L = ns.Layout.daily_card
	local k = 448 / L.size[1]
	local function Well(r, size, role)
		local fs = UI:Text(d, size, role)
		fs:SetPoint("TOPLEFT", card, "TOPLEFT", r[1] * k, -r[2] * k)
		fs:SetSize(r[3] * k, r[4] * k)
		fs:SetJustifyV("MIDDLE")
		return fs
	end
	d.date = Well(L.live_daily_date, 15, "title")
	d.dungeon = Well(L.live_daily_dungeon, 20, "title")
	d.best = Well(L.live_personal_and_guild_best, 13, "light")
	d.best:SetSpacing(3)
	-- today's shared board (the best scores other players' games have checked by replaying them)
	d.board = UI:Text(d, 12, "light", "LEFT")
	d.board:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 10, -8)
	d.board:SetWidth(430)
	d.board:SetSpacing(2)
	d.about = UI:Text(d, 11, "light")
	d.about:SetPoint("TOP", d.board, "BOTTOM", 0, -8)
	d.about:SetPoint("LEFT", d, "LEFT", 40, 0)
	d.about:SetPoint("RIGHT", d, "RIGHT", -40, 0)
	d.about:SetWidth(540)
	d.about:SetSpacing(3)
	d.play = UI:Wide(d, "Play", 180, function() G:StartDaily() end, "ui_confirm")
	d.play:SetPoint("BOTTOM", d, "BOTTOM", -100, 20)
	local back = UI:Wide(d, "Back", 180, function() G:Screen(run and run.phase ~= "over" and nil or "menu") end, "ui_cancel")
	back:SetPoint("BOTTOM", d, "BOTTOM", 100, 20)
	function d:Refresh()
		local date, day = P.Daily:Today()
		local dg = P.Daily:Dungeon(day)
		self.date:SetText(date .. "  (UTC)")
		self.dungeon:SetText(dg.name)
		local rec = P.Daily:Record(date)
		if rec and rec.best then
			local ms = Pr.MEDAL_NAME[rec.medal or 0]
			self.best:SetText(("Your best today: %d gold%s\nRuns today: %d"):format(rec.best, ms and (", " .. ms) or "", rec.runs or 0))
		elseif rec then
			self.best:SetText(("Not finished yet today (runs: %d)."):format(rec.runs or 0))
		else
			self.best:SetText("You haven't played today's run yet.")
		end
		self.about:SetText(("The same dungeon, classes, drops and dice for everyone today. Play as often as you like: your best counts. A new run every day at midnight UTC.\n|cffb8a888Days finished: %d|r"):format(P.Daily:DaysPlayed()))
		self.play:SetLabel(run and run.daily == date and run.phase ~= "over" and "Start Over" or "Play")
		local LB = P.Leaderboard
		local list = LB and LB:Board(LB:BoardId(date)) or {}
		local out = { "|cffe8c27aToday's best scores|r" }
		if not (LB and LB:Enabled()) then out[2] = "|cffb8a888Sharing scores is off (Settings).|r"
		elseif #list == 0 then out[2] = "|cffb8a888No scores heard yet today.|r" end
		for i = 1, math.min(5, #list) do
			local e = list[i]
			out[#out + 1] = ("%d.  %s  |cffe8c27a%d|r%s"):format(i, e.who, e.s, e.who == LB.me and "  |cff7fff7f(you)|r" or "")
		end
		self.board:SetText(table.concat(out, "\n"))
	end
	P:Register("LEADERBOARD_CHANGED", function() if G.screen == "daily" then d:Refresh() end end)
end

-- achievements: twelve badges, earned ones bright in their frames
lazy.achievements = function()
	local f = ScreenFrame("achievements", 900, 620)
	Ribbon(f, "Achievements")
	f.cells = {}
	for i, a in ipairs(P.Awards.LIST) do
		local c = CreateFrame("Frame", nil, f)
		c:SetSize(200, 160)
		c:SetPoint("TOP", f, "TOP", ((i - 1) % 4 - 1.5) * 210, -50 - math.floor((i - 1) / 4) * 158)
		c.frame = c:CreateTexture(nil, "ARTWORK", nil, 0)
		c.frame:SetSize(84, 84)
		c.frame:SetPoint("TOP", 0, -4)
		c.badge = c:CreateTexture(nil, "ARTWORK", nil, 1)
		c.badge:SetSize(70, 70)
		c.badge:SetPoint("CENTER", c.frame, "CENTER")
		A:Sprite(c.badge, "achievement_" .. a[1])
		c.name = UI:Text(c, 13, "title")
		c.name:SetPoint("TOP", c.frame, "BOTTOM", 0, -2)
		c.name:SetWidth(196)
		c.how = UI:Text(c, 10, "light")
		c.how:SetPoint("TOP", c.name, "BOTTOM", 0, -2)
		c.how:SetWidth(190)
		c.how:SetText(a[3])
		c.name:SetText(a[2])
		c.id = a[1]
		f.cells[i] = c
	end
	f.count = UI:Text(f, 12, "light")
	f.count:SetPoint("BOTTOM", 0, 64)
	local back = UI:Wide(f, "Back", 160, function() G:Screen(run and run.phase ~= "over" and nil or "menu") end, "ui_cancel")
	back:SetPoint("BOTTOM", 0, 16)
	function f:Refresh()
		for _, c in ipairs(self.cells) do
			local has = P.Awards:Has(c.id)
			A:Sprite(c.frame, has and "badge_frame_earned" or "badge_frame_locked")
			c.badge:SetDesaturated(not has)
			c.badge:SetAlpha(has and 1 or 0.45)
			c.name:SetAlpha(has and 1 or 0.6)
		end
		local got, all = P.Awards:Count()
		self.count:SetText(("%d of %d earned"):format(got, all))
	end
end

-- how to play: four pages, each a picture and a few lines
local HELP = {
	{ "tutorial_picks", "Pick in secret",
		"Every drop goes to the table. Everyone picks at once: |cffe8c27aNeed|r, |cffe8c27aGreed|r or |cffe8c27aPass|r. Needers roll first; Greed rolls only if nobody Needs. Your class is secret, and so is everyone else's. Your class card sits by your portrait." },
	{ "tutorial_flip", "Watch the table",
		"The picks flip face up together. Before that, watch party chat: some players can't help giving themselves away. The card's tooltip says which classes can use the item, and the ? button lists everything." },
	{ "tutorial_call_ninja", "Call ninja",
		"After the flip, each seat in turn may call ninja on one Needer. They show their class card. Caught: they lose 1 reputation and their Need is cancelled. Honest: the caller loses 1. You have few calls a run (2 in the first three dungeons, 1 in the last two)." },
	{ "tutorial_roll", "Roll, and keep your name",
		"The highest roll wins the item; what it is worth stays hidden until the Ledger. Lose all 3 reputation and you are kicked: you keep half your gold. Finish with all 3 and Fair Play adds a quarter. Bronze for finishing; silver and gold for big hauls." },
}
lazy.help = function()
	local h = ScreenFrame("help", 640, 600)
	Ribbon(h, "How to Play")
	h.art = h:CreateTexture(nil, "ARTWORK")
	h.art:SetSize(504, 252)
	h.art:SetPoint("TOP", 0, -52)
	h.head = UI:Text(h, 17, "title")
	h.head:SetPoint("TOP", h.art, "BOTTOM", 0, -12)
	h.text = UI:Text(h, 13, "light", "LEFT")
	h.text:SetPoint("TOP", h.head, "BOTTOM", 0, -10)
	h.text:SetWidth(540)
	h.text:SetSpacing(4)
	h.page = UI:Text(h, 11, "light")
	h.page:SetPoint("BOTTOM", 0, 74)
	h.prev = UI:Wide(h, "Previous", 150, function() h.at = max(1, h.at - 1) h:Show2() end)
	h.prev:SetPoint("BOTTOM", h, "BOTTOM", -170, 20)
	local back = UI:Wide(h, "Back", 150, function() G:Screen(run and run.phase ~= "over" and nil or "menu") end, "ui_cancel")
	back:SetPoint("BOTTOM", h, "BOTTOM", 0, 20)
	h.next = UI:Wide(h, "Next", 150, function() h.at = min(#HELP, h.at + 1) h:Show2() end)
	h.next:SetPoint("BOTTOM", h, "BOTTOM", 170, 20)
	h.at = 1
	function h:Show2()
		local pg = HELP[self.at]
		A:Sprite(self.art, pg[1])
		self.head:SetText(pg[2])
		self.text:SetText(pg[3])
		self.page:SetText(("%d / %d"):format(self.at, #HELP))
		self.prev:SetEnabled(self.at > 1)
		self.next:SetEnabled(self.at < #HELP)
	end
	function h:Refresh() self.at = 1 self:Show2() end
end

-- who can use what: a row per class with a badge for each kind of gear it can use
lazy.reference = function()
	local f = ScreenFrame("reference", 660, 600)
	Ribbon(f, "Who Can Use What")
	local note = UI:Text(f, 12, "light")
	note:SetPoint("TOP", 0, -50)
	note:SetWidth(580)
	note:SetText("Everyone can use cloth, rings, necklaces, cloaks and trinkets. Hover a row for the full list.")
	f.rows = {}
	local SKIP = { cloth = true, trinket = true }
	for i, c in ipairs(I.CLASSES) do
		local row = CreateFrame("Frame", nil, f)
		row:SetSize(600, 44)
		row:SetPoint("TOP", f, "TOP", 0, -76 - (i - 1) * 48)
		row:EnableMouse(true)
		row.hi = row:CreateTexture(nil, "BACKGROUND")
		row.hi:SetAllPoints()
		row.hi:SetColorTexture(1, 0.82, 0.42, 0.12)
		row.hi:Hide()
		local card = row:CreateTexture(nil, "ARTWORK")
		A:Sprite(card, "class_card_" .. c)
		card:SetSize(28, 42)
		card:SetPoint("LEFT", 6, 0)
		local name = UI:Text(row, 13, "title", "LEFT")
		name:SetPoint("LEFT", card, "RIGHT", 8, 0)
		name:SetWidth(90)
		name:SetText(I.CLASS_NAME[c])
		local x = 140
		local names = {}
		local shown = {}
		for _, t in ipairs(I.TYPE_ORDER) do
			local T = I.TYPES[t]
			if T.use[c] then
				names[#names + 1] = T.name
				if not SKIP[t] and not shown[T.badge] then
					shown[T.badge] = true
					local b = row:CreateTexture(nil, "ARTWORK")
					A:Sprite(b, "item_type_" .. T.badge)
					b:SetSize(32, 32)
					b:SetPoint("LEFT", row, "LEFT", x, 0)
					x = x + 36
				end
			end
		end
		local list = table.concat(names, ", ")
		UI:Tip(row, I.CLASS_NAME[c], list .. ".")
		row.class = c
		f.rows[i] = row
	end
	local back = UI:Wide(f, "Back", 160, function() G:Screen(run and run.phase ~= "over" and nil or "menu") end, "ui_cancel")
	back:SetPoint("BOTTOM", 0, 14)
	function f:Refresh()
		local mine = run and run.seats[1].class
		for _, row in ipairs(self.rows) do row.hi:SetShown(row.class == mine) end
	end
end

-- the Ledger: the run written up, drop by drop
-- a ledger line: set smaller until it fits its part of the ruled line
local function FitLine(fs, text, width, top)
	fs:SetText(text)
	local font, cur, flags = fs:GetFont()
	cur = cur and math.floor(cur + 0.5)
	top = top or 12
	-- SetFont is the costly call: change the size only when it must change
	for size = top, 9, -1 do
		if font and cur ~= size then fs:SetFont(font, size, flags) cur = size end
		local w = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
		if not w or w <= width then break end
	end
end
G.FitLine = FitLine

local INK_Q = { { 0.38, 0.36, 0.33 }, { 0.2, 0.14, 0.08 }, { 0.08, 0.42, 0.04 }, { 0.05, 0.25, 0.6 }, { 0.42, 0.1, 0.58 } }
local PAGE = 600
lazy.results = function()
	local r = ScreenFrame("results", 972, 672, true)
	r.title = Ribbon(r, "The Ledger", -4)
	local page = r:CreateTexture(nil, "ARTWORK")
	A:Sprite(page, "S_ledger_results")
	page:SetSize(PAGE, PAGE)
	page:SetPoint("TOPLEFT", r, "TOPLEFT", 20, -64)
	-- the ruled lines run x 280..848 of 1024, the first at y 224, then every 51.5
	local k = PAGE / 1024
	r.rows = {}
	for i = 1, 11 do
		local y = -(224 + (i - 1) * 51.5) * k + 2
		local left = UI:Text(r, 12, "ink", "LEFT")
		left:SetPoint("BOTTOMLEFT", page, "TOPLEFT", 284 * k, y)
		left:SetWidth(330 * k)
		left:SetWordWrap(false)
		local right = UI:Text(r, 12, "ink", "RIGHT")
		right:SetPoint("BOTTOMRIGHT", page, "TOPLEFT", 846 * k, y)
		right:SetWidth(230 * k)
		right:SetWordWrap(false)
		left.fitW, right.fitW = 330 * k, 230 * k
		r.rows[i] = { left, right }
	end
	-- the right column: medal, score, records, buttons
	r.medal = r:CreateTexture(nil, "ARTWORK")
	r.medal:SetSize(150, 150)
	r.medal:SetPoint("TOP", r, "TOPLEFT", 790, -70)
	r.headline = UI:Text(r, 22, "title")
	r.headline:SetPoint("TOP", r.medal, "BOTTOM", 0, -6)
	r.headline:SetWidth(320)
	r.line = UI:Text(r, 13, "light")
	r.line:SetPoint("TOP", r.headline, "BOTTOM", 0, -6)
	r.line:SetWidth(320)
	r.line:SetSpacing(3)
	-- achievements this run earned: their badges in a row above the buttons
	r.badges = {}
	for i = 1, 4 do
		local b = CreateFrame("Frame", nil, r)
		b:SetSize(52, 52)
		b:SetPoint("TOP", r, "TOPLEFT", 790 + (i - 2.5) * 58, -372)
		b.tex = b:CreateTexture(nil, "ARTWORK")
		b.tex:SetAllPoints()
		b:EnableMouse(true)
		UI:Tip(b, function(self) if self.a then return self.a[2], "Achievement earned: " .. self.a[3] end end)
		b:Hide()
		r.badges[i] = b
	end
	r.a = UI:Wide(r, "Play Again", 220, function() G:Again() end, "ui_confirm")
	r.a:SetPoint("TOP", r, "TOPLEFT", 790, -432)
	r.b = UI:Wide(r, "Next Dungeon", 220, function() G:NextDungeon() end, "ui_confirm")
	r.b:SetPoint("TOP", r.a, "BOTTOM", 0, -6)
	r.c = UI:Wide(r, "Dungeons", 220, function() G:Screen("dungeons") end)
	r.c:SetPoint("TOP", r.b, "BOTTOM", 0, -6)
	r.d = UI:Wide(r, "Menu", 220, function() G:Screen("menu") end)
	r.d:SetPoint("TOP", r.c, "BOTTOM", 0, -6)
end

-- paused for combat
lazy.paused = function()
	local pz = ScreenFrame("paused", 460, 260)
	Ribbon(pz, "Paused")
	pz.text = UI:Text(pz, 14, "light")
	pz.text:SetPoint("TOP", 0, -64)
	pz.text:SetWidth(380)
	pz.resume = UI:Wide(pz, "Resume", 180, function()
		if InCombat() then Au:Play("ui_error") return end
		G:Screen(run and run.phase ~= "over" and nil or "menu")
		G:Keyboard(true)
	end, "ui_confirm")
	pz.resume:SetPoint("BOTTOM", 0, 26)
end

-- the first time: a welcome and a choice of window size
lazy.welcome = function()
	local w = ScreenFrame("welcome", 600, 400)
	Ribbon(w, "Welcome to the Table")
	local logo = w:CreateTexture(nil, "ARTWORK")
	logo:SetTexture(P.MEDIA .. "Logo")
	logo:SetSize(110, 110)
	logo:SetPoint("TOPLEFT", 36, -60)
	local t = UI:Text(w, 13, "light", "LEFT")
	t:SetPoint("TOPLEFT", logo, "TOPRIGHT", 18, 0)
	t:SetWidth(400)
	t:SetSpacing(3)
	t:SetText("You've joined a pickup group. Eight items will drop; everyone picks Need, Greed or Pass in secret, and anyone may call ninja on a Needer whose class can't use the item.\n\nWin loot, keep your reputation, and don't get kicked. How to Play has the details.\n\nHow big should the window be? You can change it any time in the options.")
	local function Size(label, v, x)
		local b = UI:Wide(w, label, 170, function()
			P:SetSetting("size", v)
			P.db.welcomed = true
			G:Screen("menu")
		end, "ui_confirm")
		b:SetPoint("BOTTOM", w, "BOTTOM", x, 24)
	end
	Size("Large", 1, -180)
	Size("Normal", 0.9, 0)
	Size("Small", 0.75, 180)
end

function G:Prebuild(name)
	if screens[name] or not lazy[name] then return end
	local build = lazy[name]
	lazy[name] = nil
	P:Safe("build " .. name, build)
	if screens[name] then screens[name]:Hide() end
end

function G:Screen(name, quiet)
	if not W then return end
	if name and not screens[name] and lazy[name] then
		local build = lazy[name]
		lazy[name] = nil
		P:Safe("build " .. name, build)
	end
	for k, f in pairs(screens) do f:SetShown(k == name) end
	self.screen = name
	G.shade:SetShown(name ~= nil)
	if name then
		UI:HideTip()
		if not quiet then Au:Play("ui_menu_open") end
		local f = screens[name]
		if f and f.Refresh then P:Safe("screen " .. name, f.Refresh, f) end
	end
	if name == "results" then if not quiet then Au:Music("music_results") end
	elseif name and name ~= "paused" and name ~= "help" and name ~= "reference" then Au:Music("music_ledger")
	elseif not name and run then Au:Music("music_table") end
end

-- ------------------------------------------------------------------ the run
-- daily: the date when this is that day's daily run (its records are kept apart from the campaign)
function G:Start(id, seed, inputs, daily)
	local dg = I:Dungeon(id)
	if not dg then return end
	if not W then Build() end
	if Tb:Busy() then Tb:Finish() end
	seed = seed or NewSeed()
	local ev
	if inputs and inputs ~= "" then
		-- the same run again (after a /reload): replayed in one go, shown as it stands
		local r, err = R:Replay(id, seed, inputs)
		if err then P:RecordError("resume", err) r = R:NewRun(id, seed) end
		run = r
	else
		ev = {}
		run = R:NewRun(id, seed, ev)
	end
	run.daily = daily
	G.run = run
	ready = false
	Tb:Load(run)
	Tb:ClearChat()
	hud.title:SetTitle(daily and ("Daily: " .. dg.name) or dg.name)
	UpdateCounters()
	SaveRun()
	if self.screen then self:Screen(nil) end
	Au:Music("music_table")
	if ev then
		Tb:Chat("Loot", ("%s %s. Your class: %s."):format(daily and "Today's daily run:" or "Your party enters", dg.name, I.CLASS_NAME[run.seats[1].class]), "e8c27a")
		Tb:Play(ev, Ready)
	else
		Tb:Chat("Loot", "Back at the table.", "e8c27a")
		if run.phase == "pick" then
			-- the drop on the table again, face up
			local re = { { "deal", run.d } }
			Tb:Play(re, Ready)
			Tb:Finish()
		else
			Ready()
		end
	end
	RefreshChoices()
end

function G:Pick(choice)
	if not run or run.phase ~= "pick" or not ready or self.screen or InCombat() then return end
	if Tb:Busy() then Tb:Finish() end
	local ev = {}
	if not R:Pick(run, choice, ev) then return end
	ready = false
	Au:Play(choice == "N" and "need_pick" or (choice == "G" and "greed_pick" or "pass_pick"))
	if run.phase == "over" then G:PrepareLedger() end
	SaveRun()
	Status("")
	RefreshChoices()
	Tb:Play(ev, Ready)
end

function G:Call(target)
	if not run or run.phase ~= "call" or not ready or self.screen or InCombat() then return end
	local ev = {}
	if not R:Call(run, target, ev) then Au:Play("ui_error") return end
	ready = false
	Tb:ShowCalls(nil)
	hud.nocall:Hide()
	if run.phase == "over" then G:PrepareLedger() end
	SaveRun()
	Status("")
	Tb:Play(ev, Ready)
end

-- The Ledger is written a line or two per frame (the table's job queue), the way a hand fills a page: the
-- frame the run ends in only opens the screen and sets the headline (one frame did all of it: 5 ms).
local function WhoTook(i)
	for s = 1, R.SEATS do
		for _, w in ipairs(run.seats[s].won) do
			if w.drop == i then return s == 1 and "|cff1a5a10You|r" or R.PERSONA_NAME[run.seats[s].persona] end
		end
	end
end

-- Everything the Ledger says is worked out at the click that ends the run (an input frame, where the work is
-- allowed): the record is saved, every line's words are made and the writing jobs are made. The frame the
-- table finishes in then only opens the page; the jobs write a line per frame.
function G:PrepareLedger()
	if not run or run.phase ~= "over" or run.ledger then return end
	if not run.recorded then
		run.recorded = true
		if run.daily then
			local medal, newBest, prevBest = P.Daily:Finish(run)
			run.medal, run.newBest, run.prevBest = medal, newBest, prevBest
			-- a new best for the day goes on the shared daily board (checked by everyone who hears it)
			local rec = P.Daily:Record(run.daily)
			local score, how = R:Score(run)
			if how ~= "kicked" and rec and rec.best == score and rec.inputs == run.inputs and P.Leaderboard then
				P.Leaderboard:Record(run.daily, score, run.inputs)
			end
		else
			local medal, newBest, prevBest, opened = Pr:Finish(run)
			run.medal, run.newBest, run.prevBest, run.opened = medal, newBest, prevBest, opened
		end
	end
	local medal, newBest, prevBest, opened = run.medal, run.newBest, run.prevBest, run.opened
	local you = run.seats[1]
	local score, how = R:Score(run)
	local L = { rows = {} }
	L.awards = P.Awards:Check(run)
	for _, a in ipairs(L.awards) do P:Print("achievement earned: |cffe8c27a%s|r (%s)", a[2], a[3]) end
	L.badgeArt = {}
	for i, a in ipairs(L.awards) do L.badgeArt[i] = "achievement_" .. a[1] end
	for i = 1, R.DROPS do
		local dr = run.drops[i]
		if dr and i <= run.d then
			local who = WhoTook(i)
			L.rows[i] = { ("%d. %s"):format(i, dr.item.name), INK_Q[dr.item.q],
				who and ("%s, %d g"):format(who, dr.value) or ((i == run.d and you.kicked) and "not rolled: you were kicked" or "left on the floor") }
		end
	end
	L.title = run.daily and ("The Daily Ledger: " .. run.daily) or ("The Ledger: " .. run.dungeon.name)
	L.haul = ("Your haul: %d item%s"):format(#you.won, #you.won == 1 and "" or "s")
	L.gold = ("%d g"):format(you.gold)
	L.note = how == "kicked" and "Kicked: you keep half" or (how == "fairplay" and "Fair Play bonus: +25%" or ("Reputation left: %d of 3"):format(you.rep))
	L.score = ("|cff000000%d g|r"):format(score)
	L.medal = MedalSprite(medal, "256") or "medal_bronze_256_not_earned"
	L.headline = how == "kicked" and "Kicked from the Group" or ("%s: %d gold"):format(Pr.MEDAL_NAME[medal] or "Finished", score)
	L.stinger = how == "kicked" and "stinger_kicked" or "stinger_run_won"
	local lines = {}
	local rec = run.daily and P.Daily:Record(run.daily) or Pr:Record(run.dungeon.id)
	if run.daily then lines[#lines + 1] = ("Today's daily run: %s."):format(run.dungeon.name) end
	if newBest then lines[#lines + 1] = ("|cff7fff7fNew best!|r (was %d)"):format(prevBest or 0)
	elseif rec and rec.best then lines[#lines + 1] = ("Your best here: %d"):format(rec.best) end
	local m = Pr.MEDALS[run.dungeon.id]
	if m and how ~= "kicked" and medal < 3 then lines[#lines + 1] = ("Silver at %d, gold at %d."):format(m[1], m[2]) end
	if you.rightCalls + you.wrongCalls > 0 then lines[#lines + 1] = ("Your calls: %d right, %d wrong."):format(you.rightCalls, you.wrongCalls) end
	if you.caught > 0 then lines[#lines + 1] = ("Caught ninja-ing: %d time%s."):format(you.caught, you.caught == 1 and "" or "s") end
	if opened then lines[#lines + 1] = ("|cffe8c27a%s is open!|r"):format(opened.name) end
	if P.testOpen then lines[#lines + 1] = "|cffaaaaaaTest mode: nothing was saved.|r" end
	L.lines = table.concat(lines, "\n")
	local nxt = Pr:Next(run.dungeon.id)
	L.next = not run.daily and nxt ~= nil and Pr:Open(nxt.id)

	-- the writing jobs, one per frame once the page is open
	local shown = run
	local r
	local function Still() r = screens.results return run == shown and G.screen == "results" and r ~= nil end
	L.jobs = {
		function()
			if not Still() then return end
			local t1 = P:ProfStart()
			Au:Play(L.stinger)
			Au:Music("music_results")
			P:ProfEnd("results: music", t1)
		end,
	}
	for i = 1, R.DROPS do
		local row = L.rows[i]
		if row then
			L.jobs[#L.jobs + 1] = function()
				if not Still() then return end
				local t1 = P:ProfStart()
				local fs = r.rows[i]
				FitLine(fs[1], row[1], fs[1].fitW)
				fs[1]:SetTextColor(row[2][1], row[2][2], row[2][3])
				FitLine(fs[2], row[3], fs[2].fitW)
				P:ProfEnd("results: line", t1)
			end
		end
	end
	L.jobs[#L.jobs + 1] = function()
		if not Still() then return end
		local t1 = P:ProfStart()
		local ink = UI.INK
		r.rows[10][1]:SetText(L.haul)
		r.rows[10][1]:SetTextColor(ink[1], ink[2], ink[3])
		r.rows[10][2]:SetText(L.gold)
		r.rows[11][1]:SetTextColor(ink[1], ink[2], ink[3])
		r.rows[11][1]:SetText(L.note)
		r.rows[11][2]:SetText(L.score)
		r.line:SetText(L.lines)
		P:ProfEnd("results: line", t1)
	end
	if #L.awards > 0 then
		L.jobs[#L.jobs + 1] = function()
			if not Still() then return end
			for i, b in ipairs(r.badges) do
				local a = L.awards[i]
				b.a = a
				if a then A:Sprite(b.tex, L.badgeArt[i]) b:Show() end
			end
			Au:Play("ui_achievement")
		end
	end
	run.ledger = L
end

function G:ShowResults()
	if not run or run.phase ~= "over" then return end
	if not run.ledger then self:PrepareLedger() SaveRun() end
	local L = run.ledger
	local t0 = P:ProfStart()
	self:Screen("results", true)
	local r = screens.results
	if not r then return end
	r.title:SetTitle(L.title)
	for i = 1, #r.rows do r.rows[i][1]:SetText("") r.rows[i][2]:SetText("") end
	r.line:SetText("")
	A:Sprite(r.medal, L.medal)
	r.headline:SetText(L.headline)
	r.b:SetEnabled(L.next)
	for i, b in ipairs(r.badges) do b:Hide() b.a = nil end
	P:ProfEnd("results: open", t0)
	Tb:WarmUp(L.jobs)
end

function G:Again()
	if run and run.daily then self:StartDaily()
	elseif run then self:Start(run.dungeon.id) end
end

-- today's daily run (open in every campaign: the day's dungeon whether or not you have reached it)
function G:StartDaily()
	local date, day = P.Daily:Today()
	local dg = P.Daily:Dungeon(day)
	self:Start(dg.id, P.Daily:Seed(day), nil, date)
end

function G:NextDungeon()
	local nxt = run and Pr:Next(run.dungeon.id)
	if nxt and Pr:Open(nxt.id) then self:Start(nxt.id) end
end

-- ------------------------------------------------------------------ keyboard
local PICK_KEYS = { ["1"] = "N", N = "N", ["2"] = "G", G = "G", ["3"] = "P", P = "P" }

function G:Key(key)
	if IsModifierKeyDown and IsModifierKeyDown() then return false end
	if key == "ESCAPE" then
		if self.screen == "paused" or self.screen == "welcome" then return true end
		if self.screen == "menu" then
			if run and run.phase ~= "over" then self:Screen(nil) else self:Close() end
		elseif self.screen == "results" then self:Screen("menu")
		elseif self.screen then self:Screen(run and run.phase ~= "over" and nil or "menu")
		else self:Screen("menu") end
		return true
	end
	if self.screen then
		if self.screen == "results" and (key == "ENTER" or key == "SPACE") then self:Again() return true end
		return false
	end
	if key == "C" then self:Screen("reference") return true end
	if not run then return false end
	if key == "SPACE" then
		if Tb:Busy() and not ready then Tb:Finish()
		elseif run.phase == "call" then self:Call(0) end
		return true
	end
	local c = PICK_KEYS[key]
	if c and run.phase == "pick" then self:Pick(c) return true end
	if run.phase == "call" then
		local s = tonumber(key)
		if s and s >= 2 and s <= R.SEATS then self:Call(s) return true end
		if key == "0" then self:Call(0) return true end
	end
	return false
end

function G:Keyboard(on)
	if not W then return end
	if InCombat() then on = false end
	W:EnableKeyboard(on and true or false)
end

-- ------------------------------------------------------------------ the driver
local function OnError(err)
	P:RecordError("game loop", err)
	return err
end

local debugprofilestop = debugprofilestop
local stepDt = 0
local function Step() Tb:Update(stepDt) end      -- made once: the frame loop allocates nothing
local function Drive(_, elapsed)
	if elapsed > 0.1 then elapsed = 0.1 end   -- a hitch (alt-tab, loading) never jumps the animations
	local t0 = debugprofilestop and debugprofilestop()
	local kb = collectgarbage("count")
	stepDt = elapsed
	Tb.tag = nil
	local ok = xpcall(Step, OnError)
	-- the game's Lua memory went down during this frame: its cleanup ran here (it runs in whatever code is
	-- allocating when it is due), so the frame is tagged for that rather than for what the table was doing
	if collectgarbage("count") < kb then Tb.tag = "Lua cleanup" end
	if not ok then
		W:SetScript("OnUpdate", nil)
		P:Print("something went wrong drawing the table, so it stopped. /nbg debug shows details; reopening restarts it.")
		return
	end
	if P:Setting("nudge") then
		G.played = (G.played or 0) + elapsed
		if G.played >= 1200 and not G.nudged then
			G.nudged = true
			Tb:Chat("Old Tamsin", "We've been at this twenty minutes, dearie. Stretch your legs?", "d8b8ff")
		end
	end
	if t0 then
		local ms = debugprofilestop() - t0
		P:ProfEnd("whole frame", t0)
		perf.n = perf.n + 1
		perf.sum = perf.sum + ms
		local tag = Tb.tag or "animation"
		if ms > perf.max then perf.max = ms perf.worstTag = tag end
		if ms > 0.5 then
			perf.over = perf.over + 1
			perf.tags[tag] = (perf.tags[tag] or 0) + 1
		end
	end
end

function G:Shown()
	self:FitScale()
	W:SetScript("OnUpdate", Drive)
	-- after the art: the screens a run ends on, built ahead (each in a frame of its own) so the frame a
	-- run ends in only fills them in
	Tb:WarmUp({ function() G:Prebuild("results") end, function() G:Prebuild("dungeons") end })
	self:Keyboard(true)
	P:Listen("PLAYER_REGEN_DISABLED")
	if self.screen then self:Screen(self.screen)
	elseif run then Au:Music("music_table") end
end

function G:Hidden()
	W:SetScript("OnUpdate", nil)       -- closed costs nothing
	if Tb:Busy() then Tb:Finish() end
	UI:HideTip()
	Au:StopMusic()
	Au:Cancel()
	if not self.combatHidden then P:Off("PLAYER_REGEN_DISABLED") end
	A:Trim()                           -- the unpacked sprite records come back on the next draw
end

-- ------------------------------------------------------------------ open / close
function G:FitScale()
	if not W then return end
	local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
	local size = tonumber(P:Setting("size")) or 0.9
	local sc = min(uw / WIN_W, uh / WIN_H) * max(0.5, min(1, size))
	W:SetScale(max(0.35, min(1.6, sc)))
end

function G:Open()
	if InCombat() then
		P:Print("opens after combat.")
		return
	end
	if not P.char then return end
	if not W then Build() end
	if not run then
		local rs = P.char.resume
		local today = P.Daily:Today()
		local daily = type(rs) == "table" and rs.daily
		if type(rs) == "table" and I:Dungeon(rs.dungeon) and ((daily and daily == today) or (not daily and Pr:Open(rs.dungeon))) then
			-- a daily run comes back only on the same day (after midnight UTC it is yesterday's)
			self:Start(rs.dungeon, rs.seed, rs.inputs, daily or nil)
			if run and run.phase == "over" then self:Screen("menu") end
		else
			-- something on the table behind the menu: a fresh run in the first dungeon
			self:Start(I.DUNGEONS[1].id)
			self:Screen("menu")
		end
		if P.db and not P.db.welcomed then self:Screen("welcome") end
	end
	W:Show()
	Au:Play("ui_menu_open")
end

function G:Close()
	if not W or not W:IsShown() then return end
	Au:Play("ui_menu_close")
	W:Hide()
end

function G:Toggle()
	if W and W:IsShown() then self:Close() else self:Open() end
end

function G:IsOpen() return W ~= nil and W:IsShown() end

-- forget the run on screen (after /nbg reset): the next open starts from the menu
function G:Forget()
	if W and W:IsShown() then W:Hide() end
	run = nil
	G.run = nil
	ready = false
end

-- ------------------------------------------------------------------ combat: step aside at once
P:On("PLAYER_REGEN_DISABLED", function()
	if not W or not W:IsShown() then return end
	G.combatHidden = true
	if Tb:Busy() then Tb:Finish() end
	W:EnableKeyboard(false)
	G:Screen("paused")
	screens.paused.text:SetText("You're in combat. The run is frozen exactly as it was.\nWhen the fight is over, click Resume.")
	screens.paused.resume:SetEnabled(false)
	W:Hide()
	P:Listen("PLAYER_REGEN_ENABLED")
end)
P:Off("PLAYER_REGEN_DISABLED")

P:On("PLAYER_REGEN_ENABLED", function()
	P:Off("PLAYER_REGEN_ENABLED")
	if not G.combatHidden then return end
	G.combatHidden = false
	if not W then return end
	screens.paused.text:SetText("The fight is over. Your run is waiting.")
	screens.paused.resume:SetEnabled(true)
	W:Show()
	G:Keyboard(false)            -- the keyboard comes back with the Resume click, not before
	G:Screen("paused")
end)
P:Off("PLAYER_REGEN_ENABLED")

P:On("DISPLAY_SIZE_CHANGED", function() G:FitScale() end)
P:On("UI_SCALE_CHANGED", function() G:FitScale() end)

-- ------------------------------------------------------------------ perf / debug
function G:Perf()
	local avg = perf.n > 0 and perf.sum / perf.n or 0
	local mem
	if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
		UpdateAddOnMemoryUsage()
		mem = GetAddOnMemoryUsage(P.name)
	end
	P:Print("frame time %.3f ms average, %.3f ms worst over %d frames, %d frame(s) over the 0.5 ms budget; %s; memory %s KB.",
		avg, perf.max, perf.n, perf.over, (W and W:IsShown()) and "window open" or "window closed: 0 ms, no OnUpdate",
		mem and ("%.0f"):format(mem) or "?")
	if perf.n > 0 then
		local parts = {}
		for tag, n in pairs(perf.tags) do parts[#parts + 1] = ("%s %d"):format(tag, n) end
		P:Print("worst frame: %s. Over budget: %s.", perf.worstTag or "-", #parts > 0 and table.concat(parts, ", ") or "none")
	end
	-- the slowest single piece of work by name (the parts of a frame)
	local parts = {}
	for name, ms in pairs(P.prof) do if ms >= 0.2 and name ~= "whole frame" then parts[#parts + 1] = name end end
	table.sort(parts, function(a, b) return P.prof[a] > P.prof[b] end)
	for i = 1, #parts do parts[i] = ("%s %.2f"):format(parts[i], P.prof[parts[i]]) end
	if #parts > 0 then P:Print("slowest parts (ms): %s.", table.concat(parts, ", ")) end
	wipe(P.prof)
	perf.n, perf.sum, perf.max, perf.over, perf.worstTag = 0, 0, 0, 0, nil
	wipe(perf.tags)
end
