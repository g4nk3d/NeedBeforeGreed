--[[ Need Before Greed - UI/Table.lua
	The table scene: the dungeon backdrop with the loot glow, the loot card in the middle, the four other
	players in an arc (portrait, seat plate with reputation and calls, choice token, class card once shown)
	and your own seat at the front. It plays what the rules decided (Game/Rules.lua events) on a timeline,
	so every pick, flip, call, stamp and roll is seen in order.

	  Tb:Build(parent)            made the first time the window opens
	  Tb:Load(run)                a new run (or one resumed after a /reload): seats, portraits, card back
	  Tb:Play(events)             queue a turn's events; Tb:Busy() while they play; Tb:Finish() skips ahead
	  Tb:Update(dt)               the one driver (called by the window's OnUpdate)
	  Tb.onSeat(seat)             a click on a seat (calls); Tb.onIdle() when the timeline runs out

	Per-frame work allocates nothing: the timeline is built when a turn is played (an input), and the
	animation pool reuses its entries. ]]

local _, ns = ...
local P = ns.P
local Tb = P:Module("Table")
local A, Au, UI = P.Assets, P.Audio, P.UI
local R, I = ns.Rules, ns.Items

local floor, max, min, sin = math.floor, math.max, math.min, math.sin

Tb.W, Tb.H = 1000, 700
-- seat centres (portrait centre) in window pixels, top-left origin; seat 1 is you, at the front
local SEAT_POS = { [2] = { 300, 300 }, [3] = { 150, 168 }, [4] = { 862, 168 }, [5] = { 700, 300 } }
local PORT = 112
local CARD_X, CARD_Y, CARD_W, CARD_H = 500, 236, 180, 270      -- card centre and size

local scene, card, chatLines
local WarmIcons                 -- set in the warm-up section below
local seats = {}
local fxPool = {}
local timeline, tlN, clock = {}, 0, 0
local run

local function XY(f, x, y, w, h)   -- place a region by its centre in window pixels
	f:ClearAllPoints()
	f:SetPoint("CENTER", scene, "TOPLEFT", x, -y)
	if w then f:SetSize(w, h) end
end

-- ------------------------------------------------------------------ animations (pooled)
local function FX(name, x, y, w, h, opts)
	local t0 = P:ProfStart()
	local an = A:Anim(name)
	P:ProfEnd("animation decode", t0)
	if not an then return nil end
	local e
	for i = 1, #fxPool do if not fxPool[i].an then e = fxPool[i] break end end
	if not e then
		e = { tex = scene.fx:CreateTexture(nil, "OVERLAY", nil, 3) }
		fxPool[#fxPool + 1] = e
	end
	e.an, e.t, e.frame, e.loop = an, 0, 1, opts and opts.loop
	e.done = opts and opts.done
	e.tex:SetBlendMode(opts and opts.add and "ADD" or "BLEND")
	e.tex:SetVertexColor(1, 1, 1)
	if opts and opts.tint then e.tex:SetVertexColor(opts.tint[1], opts.tint[2], opts.tint[3]) end
	A:Sprite(e.tex, an[1])
	XY(e.tex, x, y, w or an.w, h or an.h)
	e.tex:Show()
	return e
end

local function UpdateFX(dt)
	for i = 1, #fxPool do
		local e = fxPool[i]
		local an = e.an
		if an then
			e.t = e.t + dt
			local f = floor(e.t * an.fps) + 1
			if f > #an then
				if e.loop then f = (f - 1) % #an + 1
				else
					e.an = nil
					e.tex:Hide()
					if e.done then local d = e.done e.done = nil d() end
				end
			end
			if e.an and f ~= e.frame then
				e.frame = f
				A:Frame(e.tex, an, f)
			end
		end
	end
end

-- ------------------------------------------------------------------ the timeline
local curTag = "table"
local function At(t, fn, tag)
	tlN = tlN + 1
	timeline[tlN] = { at = t, fn = fn, tag = tag or curTag }
end

function Tb:Busy() return tlN > 0 end

-- run every step that is due, always the earliest first (a roll's stop must never run before its start,
-- even when a slow frame makes both due at once)
local function RunDue()
	while tlN > 0 do
		local bi, bat = nil, clock
		for i = 1, tlN do
			local at = timeline[i].at
			if at <= bat and (not bi or at < bat) then bi, bat = i, at end
		end
		if not bi then return end
		local s = timeline[bi]
		-- remove first (a step may queue more)
		timeline[bi] = timeline[tlN]
		timeline[tlN] = nil
		tlN = tlN - 1
		Tb.tag = s.tag             -- what an over-budget frame was doing (/nbg perf)
		local t0 = P:ProfStart()
		P:Safe("table step", s.fn)
		P:ProfEnd(s.tag, t0)
	end
end

-- skip to the end of what is playing (a click or Space while the table plays)
function Tb:Finish()
	local guard = 0
	while tlN > 0 and guard < 500 do
		-- jump the clock to the next step and run it (and anything it queues that is due)
		local first = timeline[1].at
		for i = 2, tlN do if timeline[i].at < first then first = timeline[i].at end end
		if first > clock then clock = first end
		RunDue()
		guard = guard + 1
	end
	for i = 1, #fxPool do local e = fxPool[i] if e.an and not e.loop then e.an = nil e.tex:Hide() if e.done then local d = e.done e.done = nil d() end end end
end

-- ------------------------------------------------------------------ seats
local EXPR = { "neutral", "thinking", "smug", "shocked", "angry", "delighted", "kicked" }

-- names and strings made once, so the steps that play a turn allocate nothing (garbage made inside a frame
-- makes the game's Lua cleanup run inside that frame: the stray over-budget frames)
local NUM = {}
for i = 0, 100 do NUM[i] = tostring(i) end
Tb.NUM = NUM
local FACE = {}
for _, p in ipairs(R.PERSONAS) do
	FACE[p] = {}
	for _, e in ipairs({ "neutral", "thinking", "smug", "shocked", "angry", "delighted", "kicked" }) do FACE[p][e] = p .. "_portrait_" .. e end
	FACE[p].idle = p .. "_seat_idle"
	FACE[p].blip = "persona_blip_" .. p
end
local CLASS_CARD = {}
for _, c in ipairs(I.CLASSES) do CLASS_CARD[c] = "class_card_" .. c end
local STAMP, STAMP_DOWN = {}, {}
for _, k in ipairs({ "ninja", "honest", "kicked" }) do STAMP[k] = "stamp_" .. k STAMP_DOWN[k] = "stamp_" .. k .. "_down" end
local FX_ADD = { add = true }
local SHINE = {}
for q, Q in ipairs(I.QUALITY) do SHINE[q] = { add = true, tint = Q.color } end

local function SetFace(st, expr, hold)
	st.face = expr
	st.faceHold = hold or 0
	if st.you then
		if expr == "kicked" then A:Sprite(st.port, "player_fallback_kicked") st.usingPlayer = false
		elseif expr == "delighted" and not st.usingPlayer then A:Sprite(st.port, "player_fallback_delighted") end
		return
	end
	if expr == "neutral" then
		st.idle = A:Anim(FACE[st.persona].idle)
		st.idleT = (st.seat * 0.37) % 1
		if st.idle then A:Sprite(st.port, st.idle[1]) end
	else
		st.idle = nil
		A:Sprite(st.port, FACE[st.persona][expr])
	end
end
Tb.SetFace = SetFace

local function Pips(st)
	local seat = run and run.seats[st.seat]
	if not seat then return end
	for i = 1, 3 do A:Sprite(st.pips[i], i <= seat.rep and "reputation_pip_full" or "reputation_pip_lost") end
	for i = 1, 2 do
		local tok = st.callTok[i]
		if i <= run.dungeon.calls then
			tok:Show()
			A:Sprite(tok, i <= seat.calls and "call_ninja_ready" or "call_ninja_used")
		else
			tok:Hide()
		end
	end
end

local function Plate(st, state)
	st.plateState = state
	for k, h in pairs(st.plates) do h:SetShown(k == state) end
end

local function BuildSeat(s)
	local st = { seat = s, you = (s == 1) }
	local f = CreateFrame("Button", nil, scene.seats)
	st.f = f
	local x, y
	if s == 1 then x, y = 188, 560 else x, y = SEAT_POS[s][1], SEAT_POS[s][2] end
	st.x, st.y = x, y
	local size = s == 1 and 96 or PORT
	f:SetSize(size + 8, size + 8)
	XY(f, x, y)
	st.port = f:CreateTexture(nil, "ARTWORK")
	st.port:SetSize(size, size)
	st.port:SetPoint("CENTER")
	-- the seat plate: name, three reputation pips and the call tokens
	local plate = CreateFrame("Frame", nil, scene.seats)
	plate:SetSize(216, 54)
	XY(plate, x, y + size / 2 + 26)
	st.plateFrame = plate
	st.plates = {}
	for _, k in ipairs({ "waiting", "deciding", "decided", "kicked" }) do
		st.plates[k] = UI:Slice3(plate, "BACKGROUND", 0, "seat_plate_" .. k, 54, 0.22)
	end
	Plate(st, "waiting")
	-- the name sits on the plate's parchment (x 36..180, y 11..45 of the 216 x 54 plate), above the pips
	st.name = UI:Text(plate, 11, "ink")
	st.name:SetPoint("TOP", plate, "TOP", 0, -14)
	st.name:SetWidth(136)
	st.name:SetWordWrap(false)
	st.pips, st.callTok = {}, {}
	for i = 1, 3 do
		local t = plate:CreateTexture(nil, "ARTWORK")
		t:SetSize(16, 16)
		t:SetPoint("BOTTOMLEFT", plate, "BOTTOMLEFT", 46 + (i - 1) * 18, 11)
		st.pips[i] = t
	end
	for i = 1, 2 do
		local t = plate:CreateTexture(nil, "ARTWORK")
		t:SetSize(20, 20)
		t:SetPoint("BOTTOMRIGHT", plate, "BOTTOMRIGHT", -46 - (2 - i) * 22, 9)
		st.callTok[i] = t
	end
	-- the face-down / face-up choice token
	st.token = f:CreateTexture(nil, "OVERLAY", nil, 1)
	st.token:SetSize(46, 46)
	-- the token sits on the portrait's top corner nearer the middle of the table: top right on the left side,
	-- top left on the right side (seat 5's top-right token covered seat 4's plate)
	local half = (size + 8) / 2 - 6
	st.tokDX = (s == 4 or s == 5) and -half or half
	st.tokDY = -half
	st.token:SetPoint("CENTER", f, "CENTER", st.tokDX, -st.tokDY)
	st.token:Hide()
	st.ShowToken = function() A:Sprite(st.token, st.tokFace) st.token:Show() end   -- made once: the reveal reuses it
	-- the class card, shown once someone calls this seat (always shown for you)
	st.class = f:CreateTexture(nil, "OVERLAY", nil, 0)
	st.class:SetSize(44, 66)
	st.class:SetPoint("CENTER", f, "BOTTOMLEFT", 2, 22)
	st.class:Hide()
	-- the roll, big
	st.roll = UI:Text(f, 26, "title")
	st.roll:SetPoint("CENTER", f, "CENTER", 0, -8)
	st.roll:Hide()
	-- glow for the winner, and the "click to call" highlight
	st.glow = f:CreateTexture(nil, "BACKGROUND")
	A:Sprite(st.glow, "roll_display_winner_glow")
	st.glow:SetBlendMode("ADD")
	st.glow:SetSize(size * 1.9, size * 0.9)
	st.glow:SetPoint("CENTER", f, "CENTER", 0, -size * 0.2)
	st.glow:Hide()
	st.callBtn = CreateFrame("Button", nil, f)
	st.callBtn:SetSize(64, 64)
	st.callBtn:SetPoint("CENTER", f, "CENTER", 0, 0)
	st.callBtn.n = st.callBtn:CreateTexture(nil, "OVERLAY", nil, 4)
	st.callBtn.n:SetAllPoints()
	A:Sprite(st.callBtn.n, "call_ninja_ready")
	st.callBtn:SetScript("OnEnter", function(b) A:Sprite(b.n, "call_ninja_hover") Au:Play("ui_hover") end)
	st.callBtn:SetScript("OnLeave", function(b) A:Sprite(b.n, "call_ninja_ready") end)
	st.callBtn:SetScript("OnClick", function() if Tb.onSeat then Tb.onSeat(s) end end)
	UI:Tip(st.callBtn, "Call Ninja", function()
		local who = run and (s == 1 and "you" or R.PERSONA_NAME[run.seats[s].persona]) or "?"
		return "Call Ninja", ("Accuse %s of Needing an item their class can't use. They show their class card: if they can't use it, they lose 1 reputation and their Need is cancelled. If they can, you lose 1."):format(who)
	end)
	st.callBtn:Hide()
	UI:Tip(f, function()
		if not run then return nil end
		local seat = run.seats[s]
		local name = s == 1 and "You" or R.PERSONA_NAME[seat.persona]
		local class
		if s == 1 then class = ("Your class: %s."):format(I.CLASS_NAME[seat.class])
		elseif run.known[s] then class = ("Class shown: %s."):format(I.CLASS_NAME[run.known[s]])
		else class = "Class: secret." end
		return name, ("Reputation %d of 3.  Calls left: %d.\n%s\nItems won: %d."):format(seat.rep, seat.calls, class, #seat.won)
	end)
	seats[s] = st
	return st
end

-- ------------------------------------------------------------------ the loot card
-- the size a name fits the card's one-line name well at, measured on a hidden copy of the name text
local nameSize, detailText = {}, {}
local function NameSize(name)
	local size = nameSize[name]
	if size then return size end
	local m = card.measure
	m:SetText(name)
	local font, _, flags = m:GetFont()
	for sz = 13, 9, -1 do
		size = sz
		if font then m:SetFont(font, sz, flags) end
		local w = m.GetUnboundedStringWidth and m:GetUnboundedStringWidth() or m:GetStringWidth()
		if not w or w <= card.nameW then break end
	end
	nameSize[name] = size
	return size
end

local function CardFace(dr)
	card.dr = dr                      -- the drop on show (the rules may already be a drop further on)
	local it = dr.item
	local Q = I.QUALITY[it.q]
	A:Sprite(card.frame, "loot_card_" .. Q.card)
	local t0 = P:ProfStart()
	card.icon:SetTexture(Tb.Icon(it.icon))
	P:ProfEnd("item icon", t0)
	-- the name well holds one line: a long name is set smaller until it fits (worked out once per item)
	t0 = P:ProfStart()
	local size = NameSize(it.name)      -- worked out ahead while the drop was dealt (the warm-up queue)
	local font, cur, flags = card.name:GetFont()
	if font and math.floor((cur or 0) + 0.5) ~= size then card.name:SetFont(font, size, flags) end
	card.name:SetText(it.name)
	P:ProfEnd("item name fit", t0)
	card.name:SetTextColor(Q.color[1], Q.color[2], Q.color[3])
	local T = I.TYPES[it.t]
	local det = detailText[it]
	if not det then
		det = ("%s   %s\n%s\nValue: hidden (%s: %d to %d gold)"):format(it.slot, T.name, Q.name, Q.name, Q.lo, Q.hi)
		detailText[it] = det
	end
	card.details:SetText(det)
	A:Sprite(card.badge, "item_type_" .. T.badge)
	card.icon:Show() card.name:Show() card.details:Show() card.badge:Show()
end

local function CardBack()
	A:Sprite(card.frame, "loot_card_back")
	card.icon:Hide() card.name:Hide() card.details:Hide() card.badge:Hide()
end

local function CardHome()
	card.f:ClearAllPoints()
	card.f:SetPoint("CENTER", scene, "TOPLEFT", CARD_X, -CARD_Y)
	card.f:SetScale(1)
	card.f:SetAlpha(1)
	card.f:Show()
	card.move = nil
end

-- a game icon by file path, or the question mark when this client does not have it. The check is only
-- trusted when it knows the question mark itself (so a client where the lookup works differently still
-- shows every icon rather than a table of question marks).
local QM = "Interface\\Icons\\INV_Misc_QuestionMark"
local iconOK, canCheck = {}, nil
function Tb.Icon(path)
	if canCheck == nil then
		canCheck = false
		if GetFileIDFromPath then
			local ok, id = pcall(GetFileIDFromPath, QM)
			canCheck = ok and type(id) == "number" and id > 0
		end
	end
	if not canCheck then return path end
	local ok = iconOK[path]
	if ok == nil then
		local fine, id = pcall(GetFileIDFromPath, path)
		ok = fine and type(id) == "number" and id > 0
		iconOK[path] = ok
	end
	return ok and path or QM
end

-- ------------------------------------------------------------------ party chat
local CHAT_LINES = 7
local chat = {}
local function PushLine(line)
	for i = 1, CHAT_LINES - 1 do chat[i] = chat[i + 1] end
	chat[CHAT_LINES] = line
	for i = 1, CHAT_LINES do chatLines[i]:SetText(chat[i] or "") end
end
local function ChatLine(who, text, color) return ("|cff%s[%s]|r %s"):format(color or "8fd0ff", who, text) end
function Tb:Chat(who, text, color) PushLine(ChatLine(who, text, color)) end
function Tb:ClearChat()
	for i = 1, CHAT_LINES do chat[i] = nil chatLines[i]:SetText("") end
end

local PERSONA_COLOR = { snaggle = "7fff7f", maelle = "ffd27f", brokk = "ff9f6f", pellwick = "9fd8ff", tamsin = "d8b8ff", vexa = "ff6f6f" }
-- a party-chat line for seat s, made when the turn is laid out; returns the line and the voice blip
local function SayLine(s, text)
	if s == 1 then return ChatLine("You", text, "ffffff"), nil end
	local p = run.seats[s].persona
	return ChatLine(R.PERSONA_NAME[p], text, PERSONA_COLOR[p]), FACE[p].blip
end
local function Say(s, text)
	if not run then return end
	local line, blip = SayLine(s, text)
	PushLine(line)
	if blip then Au:Play(blip) end
end
Tb.Say = Say

-- ------------------------------------------------------------------ building
function Tb:Build(parent)
	scene = CreateFrame("Frame", nil, parent)
	scene:SetSize(self.W, self.H)
	scene:SetPoint("TOPLEFT")
	self.scene = scene
	scene.bg = scene:CreateTexture(nil, "BACKGROUND", nil, -8)
	scene.bg:SetPoint("TOPLEFT", 16, -16)
	scene.bg:SetSize(968, 484)
	scene.glow = scene:CreateTexture(nil, "BACKGROUND", nil, -6)
	XY(scene.glow, 500, 440, 560, 140)
	-- the table edge and front: a dark leather band under the scene
	scene.front = scene:CreateTexture(nil, "BACKGROUND", nil, -7)
	scene.front:SetPoint("TOPLEFT", 16, -500)
	scene.front:SetPoint("BOTTOMRIGHT", -16, 16)
	scene.front:SetColorTexture(0.09, 0.06, 0.045, 1)
	scene.seats = CreateFrame("Frame", nil, scene)
	scene.seats:SetAllPoints()
	scene.seats:SetFrameLevel(scene:GetFrameLevel() + 4)
	scene.cardLayer = CreateFrame("Frame", nil, scene)
	scene.cardLayer:SetAllPoints()
	scene.cardLayer:SetFrameLevel(scene:GetFrameLevel() + 8)
	scene.fx = CreateFrame("Frame", nil, scene)
	scene.fx:SetAllPoints()
	scene.fx:SetFrameLevel(scene:GetFrameLevel() + 12)

	-- the card (frame art with live icon, name and details in the art's wells)
	card = { mv = {} }
	local cf = CreateFrame("Frame", nil, scene.cardLayer)
	cf:SetSize(CARD_W, CARD_H)
	card.f = cf
	card.frame = cf:CreateTexture(nil, "ARTWORK", nil, 0)
	card.frame:SetAllPoints()
	local L = ns.Layout.loot_card_epic
	local k = CARD_W / L.size[1]
	local function Well(r, region)
		region:ClearAllPoints()
		region:SetPoint("TOPLEFT", cf, "TOPLEFT", r[1] * k, -r[2] * k)
		region:SetSize(r[3] * k, r[4] * k)
	end
	card.icon = cf:CreateTexture(nil, "ARTWORK", nil, 1)
	Well(L.live_item_icon, card.icon)
	card.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	card.name = UI:Text(cf, 13, "title")
	Well(L.live_item_name, card.name)
	card.name:SetWordWrap(false)
	card.nameW = L.live_item_name[3] * k - 4
	card.measure = UI:Text(cf, 13, "title")
	card.measure:SetWordWrap(false)
	card.measure:Hide()
	card.details = UI:Text(cf, 10, "light")
	Well(L.live_item_details, card.details)
	card.details:SetSpacing(2)
	card.details:SetJustifyV("TOP")
	card.badge = cf:CreateTexture(nil, "OVERLAY")
	card.badge:SetSize(30, 30)
	card.badge:SetPoint("TOPRIGHT", card.icon, "TOPRIGHT", 6, 6)
	CardHome()
	CardBack()
	cf:EnableMouse(true)
	UI:Tip(cf, function()
		if not run or not card.dr or not card.icon:IsShown() then return nil end
		local it = card.dr.item
		return it.name, ("Usable by: %s.\nYour class (%s) %s."):format(I:UsableBy(it), I.CLASS_NAME[run.seats[1].class],
			I:CanUse(run.seats[1].class, it) and "|cff7fff7fcan use it: a Need is honest|r" or "|cffff7f7fcan't use it: a Need would be a ninja|r")
	end)

	for s = 1, R.SEATS do BuildSeat(s) end

	-- stamps over a seat (NINJA!, HONEST, KICKED)
	scene.stamp = scene.fx:CreateTexture(nil, "OVERLAY", nil, 6)
	scene.stamp:Hide()

	-- party chat
	local chatF = CreateFrame("Frame", nil, scene)
	chatF:SetPoint("TOPLEFT", scene, "TOPLEFT", 676, -508)
	chatF:SetSize(304, 176)
	chatF:SetFrameLevel(scene:GetFrameLevel() + 6)
	UI:Slice9(chatF, "BACKGROUND", 0, "chat_panel", 26, 64)
	local head = UI:Text(chatF, 11, "title", "LEFT")
	head:SetPoint("TOPLEFT", 16, -10)
	head:SetText("Party")
	chatLines = {}
	for i = 1, CHAT_LINES do
		local l = UI:Text(chatF, 11, "light", "LEFT")
		l:SetPoint("TOPLEFT", 16, -24 - (i - 1) * 20)
		l:SetWidth(274)
		l:SetWordWrap(false)
		chatLines[i] = l
	end
end

-- ------------------------------------------------------------------ a run on the table
function Tb:Load(r)
	run = r
	WarmIcons(r)
	tlN = 0
	wipe(timeline)
	clock = 0
	local dg = r.dungeon
	A:Sprite(scene.bg, "BG_" .. dg.id)
	A:Sprite(scene.glow, dg.id .. "_loot_glow")
	CardHome()
	CardBack()
	card.dr = nil
	scene.stamp:Hide()
	for s = 1, R.SEATS do
		local st = seats[s]
		local seat = r.seats[s]
		st.persona = seat.persona
		st.token:Hide()
		st.roll:Hide()
		st.glow:Hide()
		st.callBtn:Hide()
		st.f:SetAlpha(seat.kicked and 0.45 or 1)
		if s == 1 then
			st.name:SetText(UnitName and UnitName("player") or "You")
			st.usingPlayer = false
			if SetPortraitTexture and UnitExists and UnitExists("player") then
				local ok = pcall(SetPortraitTexture, st.port, "player")
				st.usingPlayer = ok
			end
			if not st.usingPlayer then A:Sprite(st.port, "player_fallback_neutral") end
			A:Sprite(st.class, CLASS_CARD[seat.class])
			st.class:Show()
		else
			st.name:SetText(R.PERSONA_NAME[seat.persona])
			SetFace(st, seat.kicked and "kicked" or "neutral")
			if r.known[s] then A:Sprite(st.class, CLASS_CARD[r.known[s]]) st.class:Show() else st.class:Hide() end
		end
		Plate(st, seat.kicked and "kicked" or "waiting")
		Pips(st)
	end
end

-- ------------------------------------------------------------------ playing a turn
local Q_SOUND = { "quality_reveal_poor", "quality_reveal_common", "quality_reveal_uncommon", "quality_reveal_rare", "quality_reveal_epic" }
local TOKEN = { N = "choice_token_need", G = "choice_token_greed", P = "choice_token_pass", X = "choice_token_need" }

local stampSeat, stampKind
local function StampLand()
	local st = seats[stampSeat]
	A:Sprite(scene.stamp, STAMP[stampKind])
	XY(scene.stamp, st.x, st.y, 200, 100)
	scene.stamp:Show()
end
local function Stamp(s, kind)
	local st = seats[s]
	stampSeat, stampKind = s, kind
	local e = FX(STAMP_DOWN[kind], st.x, st.y, 200, 100)
	if e then e.done = StampLand end
	FX("stamp_dust_effect", st.x, st.y + 30, 160, 80)
end
local function CardShow() card.f:Show() end

function Tb:Play(ev, onDone)
	-- the turn is laid out from now: the clock keeps running from turn to turn, so a turn that started at 0
	-- would have every step due at once (the rolls that never stopped, 2026-10-10)
	local t = clock
	local step = P:Setting("quick") and 0.5 or 1
	-- each step learns its own start time (t keeps growing while the turn is laid out)
	local function After(d, fn)
		t = t + d * step
		local at = t
		At(at, function() fn(at) end)
	end
	for _, e in ipairs(ev) do
		local kind = e[1]
		curTag = kind
		if kind == "deal" then
			local d = e[2]
			After(0.25, function()
				scene.stamp:Hide()
				for s = 1, R.SEATS do
					local st = seats[s]
					st.token:Hide() st.roll:Hide() st.glow:Hide() st.callBtn:Hide()
					if not run.seats[s].kicked then Plate(st, s == 1 and "waiting" or "deciding") end
					if s > 1 and not run.seats[s].kicked and st.face ~= "neutral" then SetFace(st, "neutral") end
				end
				CardHome()
				CardBack()
				card.dr = nil
				Au:MusicLayer(false)
				card.f:SetAlpha(0)
				card.fadeIn = 0.25
				Au:Play("card_deal")
				if Tb.onDrop then Tb.onDrop(d) end
			end)
			After(0.45, function()
				Au:Play("card_flip")
				local e2 = FX("card_flip_effect", CARD_X, CARD_Y, CARD_W, CARD_H)
				card.f:Hide()
				if e2 then e2.done = CardShow else card.f:Show() end
			end)
			local dr = run.drops[d]
			local q = dr.item.q
			After(0.2, function()
				CardFace(dr)
				-- the others start deciding
				for s = 2, R.SEATS do
					if not run.seats[s].kicked then SetFace(seats[s], "thinking", 0) end
				end
			end)
			-- the sound and the shine a frame later: the face alone fills that frame
			At(t + 0.02, function()
				Au:Play(Q_SOUND[q])
				FX("quality_shine_effect", CARD_X, CARD_Y, CARD_W, CARD_H, SHINE[q])
				if q == 5 then FX("epic_reveal_effect", CARD_X, CARD_Y, 420, 420, FX_ADD) Au:MusicLayer(true) end
			end, "deal: shine")
			-- each of the others locks in a moment later
			for s = 2, R.SEATS do
				if not run.seats[s].kicked then
					local st = seats[s]
					local lock = 0.5 + ((s * 0.43 + d * 0.31) % 1) * 1.3
					At(t + lock * step, function()
						Plate(st, "decided")
						A:Sprite(st.token, "choice_token_back")
						st.token:Show()
						Au:Play("lock_in")
						SetFace(st, "neutral")
					end, "lock-in")
				end
			end
		elseif kind == "tell" then
			local line, blip = SayLine(e[2], e[3])
			After(0.35, function() PushLine(line) if blip then Au:Play(blip) end end)
		elseif kind == "reveal" then
			After(0.3, function()
				Au:Play("reveal_hit")
				for s = 1, R.SEATS do
					local st = seats[s]
					local pk = run.picks[s]
					if pk and not run.seats[s].kicked then
						local e2 = FX("token_flip_effect", st.x + st.tokDX, st.y + st.tokDY, 46, 46)
						st.tokFace = TOKEN[pk] or "choice_token_pass"
						st.token:Hide()
						if e2 then e2.done = st.ShowToken else st.ShowToken() end
						Plate(st, "decided")
					end
				end
			end)
			After(0.5, function() end)
		elseif kind == "callturn" then
			After(0.2, function() if Tb.onCallTurn then Tb.onCallTurn() end end)
		elseif kind == "call" then
			local caller, target, caught, cls = e[2], e[3], e[4], e[5]
			local line, blip = SayLine(caller, caller == 1 and ("I call ninja on %s!"):format(R.PERSONA_NAME[run.seats[target].persona]) or
				(target == 1 and "Ninja! Show us your class." or ("Ninja! %s, show your class."):format(R.PERSONA_NAME[run.seats[target].persona])))
			After(0.45, function()
				Au:Play("call_ninja")
				if caller > 1 then SetFace(seats[caller], "angry", 1.5) end
				PushLine(line)
				if blip then Au:Play(blip) end
			end)
			After(0.55, function()
				Pips(seats[caller])
				local st = seats[target]
				A:Sprite(st.class, CLASS_CARD[cls])
				st.class:Show()
				if target > 1 then SetFace(st, caught and "shocked" or "smug", 2) end
			end)
			After(0.35, function()
				Stamp(target, caught and "ninja" or "honest")
				if caught then
					seats[target].token:Hide()
					FX("ninja_smoke_effect", seats[target].x + seats[target].tokDX, seats[target].y + seats[target].tokDY, 110, 110)
				end
			end)
			At(t + 0.12 * step, function() Au:Play(caught and "caught" or "honest") end)
			After(0.9, function() end)
		elseif kind == "nocall" then
			-- quiet: nothing to show
		elseif kind == "rep" then
			local s = e[2]
			After(0.25, function()
				local st = seats[s]
				local lost = e[3] + 1
				local pip = st.pips[lost]
				if pip then
					local px, py = st.x - 108 + 46 + (lost - 1) * 18 + 8, st.y + (s == 1 and 48 or 56) + 26 + 27 - 19
					FX("reputation_crack_effect", px, py, 24, 24)
				end
				Pips(st)
			end)
		elseif kind == "kicked" then
			local s = e[2]
			local line, blip = SayLine(s, s == 1 and "...I'll see myself out." or "Fine! I didn't want your loot anyway.")
			After(0.6, function()
				local st = seats[s]
				Stamp(s, "kicked")
				Au:Play("kicked")
				SetFace(st, "kicked")
				Plate(st, "kicked")
				st.token:Hide()
				st.f:SetAlpha(0.45)
				Tb.shake = 0.35
				PushLine(line)
				if blip then Au:Play(blip) end
			end)
			After(1.0, function() end)
		elseif kind == "roll" then
			local rolls, again = e[3], e[4]
			After(again and 0.4 or 0.5, function()
				Au:Play("dice_roll")
				for s, v in pairs(rolls) do
					local st = seats[s]
					st.roll:SetText("")
					st.roll:Show()
					st.rolling = v
					st.rollT = 0
				end
			end)
			After(1.1, function()
				for s, v in pairs(rolls) do
					local st = seats[s]
					st.rolling = nil
					st.roll:SetText(NUM[v] or tostring(v))
					st.roll:SetTextColor(1, 0.82, 0.42)
				end
			end)
		elseif kind == "win" then
			local w = e[2]
			After(0.35, function()
				local st = seats[w]
				st.glow:Show()
				st.roll:SetTextColor(0.6, 1, 0.5)
				Au:Play("roll_win")
				FX("winner_burst_effect", st.x, st.y - 20, 150, 150, FX_ADD)
				if w == 1 then FX("coin_burst_effect", st.x, st.y, 140, 140) end
				if w > 1 then SetFace(st, card.dr and card.dr.item.q >= 4 and "delighted" or "smug", 2) end
				-- the card flies to the winner
				local m = card.mv
				m.t, m.dur, m.x0, m.y0, m.x1, m.y1 = 0, 0.5, CARD_X, CARD_Y, st.x, st.y
				card.move = m
				if Tb.onWin then Tb.onWin(w) end
			end)
			After(0.8, function() end)
		elseif kind == "floor" then
			local line = ChatLine("Loot", "Nobody rolled. The item stays on the floor.", "aaaaaa")
			After(0.4, function()
				PushLine(line)
				card.fadeOut = 0.4
			end)
		elseif kind == "over" then
			After(0.8, function() if Tb.onOver then Tb.onOver(e[2], e[3]) end end)
		end
	end
	After(0.05, function() if onDone then onDone() end end)
end

-- ------------------------------------------------------------------ warm-up
-- The first draw from an atlas makes the game read and upload the whole texture (several ms for the
-- 4-8 MB sheets: the over-budget "animation" frames in the first tests). When the window opens, each atlas
-- is touched once, one per frame, so that cost is paid while the menu shows instead of at the first stamp or
-- epic. Once a session: the game keeps them after that.
local warmList, warmAt, warmTex = {}, 0, nil
local warmed = false
function Tb:WarmUp(jobs)
	if not warmed then
		warmed = true
		for _, t in ipairs(ns.Atlas.tex) do warmList[#warmList + 1] = A.TEX .. t[1] end
	end
	-- jobs: functions to run one per frame after the textures (screens built ahead of time)
	for _, j in ipairs(jobs or {}) do warmList[#warmList + 1] = j end
end

-- the run's eight item icons, read one per frame while the first drop is dealt (each is its own file)
function WarmIcons(r)      -- forward-declared near the top (Tb:Load uses it)
	for _, dr in ipairs(r.drops) do
		warmList[#warmList + 1] = Tb.Icon(dr.item.icon)
		local name = dr.item.name
		if not nameSize[name] then warmList[#warmList + 1] = function() NameSize(name) end end
	end
end

local function WarmStep()
	if not warmTex then
		warmTex = scene:CreateTexture(nil, "BACKGROUND", nil, -8)
		warmTex:SetSize(1, 1)
		warmTex:SetPoint("TOPLEFT", scene, "TOPLEFT", 0, 0)
		warmTex:SetAlpha(0.01)
	end
	warmAt = warmAt + 1
	Tb.tag = "warm-up"
	local job = warmList[warmAt]
	local t0 = P:ProfStart()
	if type(job) == "function" then
		P:Safe("warm-up", job)
	else
		warmTex:SetTexture(job)
		warmTex:SetTexCoord(0, 0.001, 0, 0.001)
		warmTex:Show()
	end
	P:ProfEnd("warm-up", t0)
	if warmAt >= #warmList then
		warmTex:Hide()
		wipe(warmList)
		warmAt = 0
	end
end

-- ------------------------------------------------------------------ the driver
local shakeX = 0
function Tb:Update(dt)
	if warmAt < #warmList then WarmStep() end
	if tlN > 0 then
		clock = clock + dt
		RunDue()
	else
		-- failsafe: nothing left to play, so no die may still be spinning
		for s = 1, R.SEATS do
			local st = seats[s]
			if st.rolling then st.roll:SetText(NUM[st.rolling] or "") st.rolling = nil end
		end
	end
	UpdateFX(dt)
	-- the idle loops of the four faces
	for s = 2, R.SEATS do
		local st = seats[s]
		local an = st.idle
		if an then
			st.idleT = st.idleT + dt
			local f = floor(st.idleT * an.fps) % #an + 1
			if f ~= st.idleF then st.idleF = f A:Frame(st.port, an, f) end
		elseif st.faceHold and st.faceHold > 0 then
			st.faceHold = st.faceHold - dt
			if st.faceHold <= 0 and st.face ~= "kicked" and not (run and run.seats[s].kicked) then SetFace(st, "neutral") end
		end
		if st.rolling then
			st.rollT = st.rollT + dt
			local shown = floor(st.rollT * 30)
			if shown ~= st.rollShown then
				st.rollShown = shown
				st.roll:SetText(NUM[(shown * 37 + s * 11) % 100 + 1])
			end
		end
	end
	local me = seats[1]
	if me.rolling then
		me.rollT = me.rollT + dt
		local shown = floor(me.rollT * 30)
		if shown ~= me.rollShown then me.rollShown = shown me.roll:SetText(NUM[(shown * 37 + 7) % 100 + 1]) end
	end
	-- the deciding plates pulse
	local pulse = 0.75 + 0.25 * sin(clock * 6)
	for s = 2, R.SEATS do
		local st = seats[s]
		if st.plateState == "deciding" then st.plates.deciding:SetAlpha(pulse) end
	end
	-- the card: fade in/out, fly to the winner
	if card.fadeIn then
		card.fadeIn = card.fadeIn - dt
		card.f:SetAlpha(max(0, 1 - card.fadeIn / 0.25))
		if card.fadeIn <= 0 then card.fadeIn = nil card.f:SetAlpha(1) end
	end
	if card.fadeOut then
		card.fadeOut = card.fadeOut - dt
		card.f:SetAlpha(max(0, card.fadeOut / 0.4))
		if card.fadeOut <= 0 then card.fadeOut = nil card.f:Hide() end
	end
	local m = card.move
	if m then
		m.t = m.t + dt
		local f = min(1, m.t / m.dur)
		local e = f * f * (3 - 2 * f)
		local sc = 1 - 0.7 * e
		card.f:SetScale(sc)
		card.f:ClearAllPoints()
		card.f:SetPoint("CENTER", scene, "TOPLEFT", (m.x0 + (m.x1 - m.x0) * e) / sc, -(m.y0 + (m.y1 - m.y0) * e) / sc)
		card.f:SetAlpha(1 - 0.6 * e)
		if f >= 1 then card.move = nil card.f:Hide() end
	end
	-- the door-slam shake when someone is kicked
	if Tb.shake then
		Tb.shake = Tb.shake - dt
		local x = Tb.shake > 0 and floor(sin(Tb.shake * 80) * 6) or 0
		if x ~= shakeX then
			shakeX = x
			scene:ClearAllPoints()
			scene:SetPoint("TOPLEFT", x, 0)
		end
		if Tb.shake <= 0 then Tb.shake = nil end
	end
end

-- calls: Call Ninja buttons on the seats you may call
function Tb:ShowCalls(targets)
	for s = 1, R.SEATS do seats[s].callBtn:Hide() end
	for _, s in ipairs(targets or {}) do seats[s].callBtn:Show() end
end

function Tb:Seat(s) return seats[s] end
function Tb:Run() return run end
