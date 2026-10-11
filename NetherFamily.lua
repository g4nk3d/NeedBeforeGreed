--[[ NetherFamily.lua - switching a Nether addon off without disabling it (shared)

	Every Nether addon that can be switched off ships this same file. Whichever copy loads
	first defines _G.NetherFamily; a newer copy (a higher VERSION) replaces an older one's code
	and keeps its state.

	NetherSuite's "Nether Addons" page switches family addons off and on. A switched-off addon
	still loads (it stays enabled in the game's AddOns list), but does nothing: its event frames
	never run and are emptied, its public global is removed so the rest of the family treats it
	as not installed. The switch is kept account-wide in NetherFamilyDB (the family's shared saved
	table) and takes effect at the next /reload.

	  NetherFamily:IsOff(addon)            switched off (PRISM is off whenever NetherUI is)
	  NetherFamily:SetOff(addon, off)      what NetherSuite's page calls; applies after a reload
	  NetherFamily:Gate(addon, frame, ...) an addon's event frames: they run only while it is on
	  NetherFamily:Global(addon, name, ...) the addon's public globals, removed when it is off
	  NetherFamily:Slash(addon, key, name)  its slash command: says it is switched off
	  NetherFamily:SkipLoad(addon)         at the top of a file: true = switched off, stop here
	  NetherFamily:Suspended(addon)        true when it is off this session
	  NetherFamily:Running(addon)          loaded and switched on (what other addons should ask)
	  NetherFamily:WhenOn(addon, fn)       fn now if on, after the switch is known, never if off
	  NetherFamily:Guard(addon, label, names...) global functions (key bindings, the addon
	                                       compartment) that say "switched off" instead of running
	  NetherFamily:Pending()               switches changed since this session started

	Before an addon's own ADDON_LOADED (its saved tables not read yet) its gated frames hold
	their events and replay them once the switch is known. ]]

--[[ NetherSizer (shared, in this same file) - how every Nether window is moved and resized

	Whichever copy loads first defines _G.NetherSizer; a newer copy (a higher version) replaces an
	older one. The window is pinned by its top-left corner where it is drawn before anything
	moves, so nothing jumps when the drag starts; the corner then follows the cursor by how far
	it has moved since the press, inside the window's size limits and the screen, every frame.

	  NetherSizer:PinTopLeft(frame)        re-anchor by the top-left corner, where it is now
	  NetherSizer:Press(frame, opts)       a press on a resize grip: a double-click (within 0.35s)
	                                       restores the default size (opts.reset), else sizing starts
	  NetherSizer:Start(frame, opts)       start sizing from the bottom-right corner
	      opts: { minW, minH, maxW, maxH  (default: the frame's resize bounds)
	              aspect   = bool | fn()  Shift held keeps the window's proportions
	              readout  = bool | fn()  show the size by the corner while dragging
	              dblReset = bool | fn()  a double-click restores the size (needs reset)
	              reset    = fn(frame)    restore the default size
	              snap     = fn(frame, w, h) -> w, h   adjust each step (edge snapping)
	              onStep   = fn(frame, w, h), onDone = fn(frame) }
	  NetherSizer:Stop()                   end sizing or moving (also when the button is let go)
	  NetherSizer:StartMove(frame, opts)   move by hand: opts.snap = fn(frame, left, top) -> left, top
	                                       (edge snapping while dragging), opts.onDone = fn(frame)
	  NetherSizer:IsSizing([frame]), NetherSizer:IsMoving([frame])
	  NetherSizer:Readout(frame, text)     the size label (nil text hides it) ]]
do
	local SIZER_VERSION = 1
	local Z = rawget(_G, "NetherSizer")
	if type(Z) ~= "table" or (tonumber(Z.version) or 0) < SIZER_VERSION then
		Z = type(Z) == "table" and Z or {}
		_G.NetherSizer = Z
		Z.version = SIZER_VERSION
		Z.presses = Z.presses or setmetatable({}, { __mode = "k" })
		local floor, max, min, abs = math.floor, math.max, math.min, math.abs
		local function Finite(v) return type(v) == "number" and v == v and v > -math.huge and v < math.huge end
		local function Want(v) if type(v) == "function" then local ok, r = pcall(v) return ok and r and true or false end return v and true or false end
		local function Now() return (GetTime and GetTime()) or 0 end
		local function Down() return not IsMouseButtonDown or IsMouseButtonDown("LeftButton") end

		function Z:PinTopLeft(f)
			local l, t = f:GetLeft(), f:GetTop()
			if not (Finite(l) and Finite(t)) then return false end
			f:ClearAllPoints()
			f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
			return true
		end

		-- the screen in the frame's own units
		local function Screen(f)
			local s, u = f:GetEffectiveScale(), UIParent:GetEffectiveScale()
			if not (Finite(s) and Finite(u) and s > 0 and u > 0) then return nil end
			local r = s / u
			return UIParent:GetWidth() / r, UIParent:GetHeight() / r
		end

		-- the size label: by the corner being dragged, in the tooltip layer
		function Z:Readout(f, text)
			local r = self.readout
			if not text then if r then r:Hide() end return end
			if not r then
				r = CreateFrame("Frame", nil, UIParent)
				r:SetFrameStrata("TOOLTIP")
				r.bg = r:CreateTexture(nil, "BACKGROUND")
				r.bg:SetAllPoints()
				r.bg:SetColorTexture(0.03, 0.03, 0.05, 0.85)
				r.line = r:CreateTexture(nil, "BORDER")
				r.line:SetPoint("BOTTOMLEFT") r.line:SetPoint("BOTTOMRIGHT") r.line:SetHeight(1)
				r.line:SetColorTexture(0.79, 0.64, 0.29, 0.9)
				r.text = r:CreateFontString(nil, "OVERLAY")
				r.text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 11, "")
				r.text:SetShadowOffset(1, -1)
				r.text:SetShadowColor(0, 0, 0, 1)
				r.text:SetTextColor(1, 1, 1, 1)
				r.text:SetPoint("CENTER", 0, 1)
				self.readout = r
			end
			r:SetScale(1)
			r.text:SetText(text)
			r:SetSize((r.text:GetStringWidth() or 40) + 14, 18)
			r:ClearAllPoints()
			local x, y = GetCursorPosition()
			local u = UIParent:GetEffectiveScale()
			r:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / u + 14, y / u - 14)
			r:SetClampedToScreen(true)
			r:Show()
		end

		local driver = Z.driver or CreateFrame("Frame")
		Z.driver = driver
		driver:Hide()
		local st = {}
		Z.st = st

		local function SizeStep()
			local f = st.f
			if not f or not f:IsVisible() or not Down() then Z:Stop() return end
			local cx, cy = GetCursorPosition()
			local w = st.w + (cx / st.s - st.x)
			local h = st.h + (st.y - cy / st.s)
			if st.aspect and IsShiftKeyDown and IsShiftKeyDown() and st.w > 0 and st.h > 0 then
				-- keep the shape: follow whichever side moved further, the other follows it
				local k = (abs(w / st.w - 1) >= abs(h / st.h - 1)) and (w / st.w) or (h / st.h)
				local lo = max(st.minW / st.w, st.minH / st.h)
				local hi = min(st.maxW / st.w, st.maxH / st.h)
				if lo <= hi then k = max(lo, min(hi, k)) end
				w, h = st.w * k, st.h * k
			end
			w = max(st.minW, min(st.maxW, floor(w + 0.5)))
			h = max(st.minH, min(st.maxH, floor(h + 0.5)))
			if st.snap then
				local ok, sw, sh = pcall(st.snap, f, w, h)
				if ok and Finite(sw) and Finite(sh) then
					w = max(st.minW, min(st.maxW, sw))
					h = max(st.minH, min(st.maxH, sh))
				end
			end
			if w ~= st.lw or h ~= st.lh then
				st.lw, st.lh = w, h
				f:SetSize(w, h)
				if st.onStep then pcall(st.onStep, f, w, h) end
			end
			if st.readout then Z:Readout(f, floor(w + 0.5) .. " x " .. floor(h + 0.5)) end
		end

		local function MoveStep()
			local f = st.f
			if not f or not f:IsVisible() or not Down() then Z:Stop() return end
			local cx, cy = GetCursorPosition()
			local l = st.l + (cx / st.s - st.x)
			local t = st.t + (cy / st.s - st.y)
			local sw, sh = Screen(f)
			local w, h = f:GetWidth() or 0, f:GetHeight() or 0
			if sw then
				l = max(0, min(sw - w, l))
				t = min(sh, max(h, t))
			end
			if st.snap then
				local ok, sl, stp = pcall(st.snap, f, l, t)
				if ok and Finite(sl) and Finite(stp) then l, t = sl, stp end
			end
			if l ~= st.ll or t ~= st.lt then
				st.ll, st.lt = l, t
				f:ClearAllPoints()
				f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
			end
		end

		driver:SetScript("OnUpdate", function()
			if st.mode == "size" then SizeStep() elseif st.mode == "move" then MoveStep() else driver:Hide() end
		end)

		function Z:Start(f, o)
			if st.f then self:Stop() end
			o = o or {}
			if not self:PinTopLeft(f) then return false end
			local s = f:GetEffectiveScale()
			local l, t, w, h = f:GetLeft(), f:GetTop(), f:GetWidth(), f:GetHeight()
			if not (Finite(s) and s > 0 and Finite(l) and Finite(t) and Finite(w) and Finite(h)) then return false end
			local minW, minH, maxW, maxH = o.minW, o.minH, o.maxW, o.maxH
			if not minW and f.GetResizeBounds then
				local ok, a, b, c, d = pcall(f.GetResizeBounds, f)
				if ok then minW, minH, maxW, maxH = a, b, c, d end
			end
			minW, minH = tonumber(minW) or 50, tonumber(minH) or 40
			maxW = (tonumber(maxW) and maxW > 0) and maxW or 4000
			maxH = (tonumber(maxH) and maxH > 0) and maxH or 4000
			-- never past the right or the bottom edge of the screen
			local sw = Screen(f)
			if sw then maxW = min(maxW, max(minW, sw - l)) end
			maxH = min(maxH, max(minH, t))
			local cx, cy = GetCursorPosition()
			for k in pairs(st) do st[k] = nil end
			st.mode, st.f, st.s = "size", f, s
			st.x, st.y, st.w, st.h = cx / s, cy / s, w, h
			st.minW, st.minH, st.maxW, st.maxH = minW, minH, maxW, maxH
			st.lw, st.lh = w, h
			st.aspect, st.readout = Want(o.aspect), Want(o.readout)
			st.snap, st.onStep, st.onDone = o.snap, o.onStep, o.onDone
			if st.readout then self:Readout(f, floor(w + 0.5) .. " x " .. floor(h + 0.5)) end
			driver:Show()
			return true
		end

		function Z:StartMove(f, o)
			if st.f then self:Stop() end
			o = o or {}
			if not self:PinTopLeft(f) then return false end
			local s = f:GetEffectiveScale()
			local l, t = f:GetLeft(), f:GetTop()
			if not (Finite(s) and s > 0 and Finite(l) and Finite(t)) then return false end
			local cx, cy = GetCursorPosition()
			for k in pairs(st) do st[k] = nil end
			st.mode, st.f, st.s = "move", f, s
			st.x, st.y, st.l, st.t = cx / s, cy / s, l, t
			st.ll, st.lt = l, t
			st.snap, st.onDone = o.snap, o.onDone
			driver:Show()
			return true
		end

		function Z:Press(f, o)
			o = o or {}
			local now, last = Now(), self.presses[f]
			if o.reset and Want(o.dblReset == nil and true or o.dblReset) and last and now - last < 0.35 then
				self.presses[f] = nil
				if st.f then self:Stop(true) end
				pcall(o.reset, f)
				return "reset"
			end
			self.presses[f] = now
			return self:Start(f, o) and "size" or nil
		end

		function Z:Stop(quiet)
			local f, done = st.f, st.onDone
			st.f, st.mode, st.onDone = nil, nil, nil
			driver:Hide()
			self:Readout(nil, nil)
			if f and done and not quiet then pcall(done, f) end
		end

		function Z:IsSizing(f) return st.mode == "size" and st.f ~= nil and (f == nil or st.f == f) end
		function Z:IsMoving(f) return st.mode == "move" and st.f ~= nil and (f == nil or st.f == f) end
	end
end

local VERSION = 1

local F = _G.NetherFamily
if type(F) == "table" and (tonumber(F.version) or 0) >= VERSION then return end
F = type(F) == "table" and F or {}
_G.NetherFamily = F
F.version = VERSION
F.frames = F.frames or {}        -- addon -> { frame, ... }
F.globals = F.globals or {}      -- addon -> { global name, ... }
F.held = F.held or {}            -- addon -> { { frame, fn, n, ... }, ... } events before the switch is known
F.known = F.known or {}          -- addon -> true once its own saved tables are loaded
F.state = F.state or {}          -- addon -> "on" | "off" (this session)
F.atStart = F.atStart or {}      -- addon -> the switch this session started with
F.whenOn = F.whenOn or {}        -- addon -> { fn, ... } waiting for the switch to be known
F.owned = F.owned or {}          -- addon -> { [global name] = the value it registered }

-- addons whose switch follows another's: a theme pack is off when its host is
F.FOLLOWS = { NetherUI_Prism = "NetherUI" }
-- the hub and its database are never switched off
F.FIXED = { NetherSuite = true, NetherSearch = true, NetherSearch_Data = true, NetherUI_Media = true }

local type, pairs, ipairs, select, unpack = type, pairs, ipairs, select, unpack

local function DB()
	local fam = rawget(_G, "NetherFamilyDB")
	if type(fam) ~= "table" then fam = {} _G.NetherFamilyDB = fam end
	if type(fam.off) ~= "table" then fam.off = {} end
	return fam
end

-- Every family addon saves its own copy of NetherFamilyDB, and each copy loads over the last.
-- One that was disabled in the AddOns list for a while brings back an old copy: the newest
-- (the highest revision, raised by every switch) always wins.
local function Reconcile()
	local cur = rawget(_G, "NetherFamilyDB")
	local best = F.best
	if type(cur) == "table" and (not best or (tonumber(cur.rev) or 0) >= (tonumber(best.rev) or 0)) then
		F.best = cur
	elseif best then
		_G.NetherFamilyDB = best
	end
end
F.Reconcile = Reconcile

function F:IsOff(addon)
	if type(addon) ~= "string" or self.FIXED[addon] then return false end
	local off = DB().off
	if off[addon] == true then return true end
	local host = self.FOLLOWS[addon]
	return host ~= nil and off[host] == true
end

function F:SetOff(addon, off)
	if type(addon) ~= "string" or self.FIXED[addon] then return false end
	local fam = DB()
	fam.off[addon] = off and true or nil
	fam.rev = (tonumber(fam.rev) or 0) + 1
	F.best = fam
	return true
end

function F:Suspended(addon) return self.state[addon] == "off" end

-- every switch that differs from what this session started with (a reload applies them)
function F:Pending()
	local out = {}
	for addon, was in pairs(self.atStart) do
		if (self:IsOff(addon) and "off" or "on") ~= was then out[#out + 1] = addon end
	end
	return out
end

-- an addon switched off: its frames stop for good this session, its global goes
local function Shut(addon)
	for _, f in ipairs(F.frames[addon] or {}) do
		pcall(f.UnregisterAllEvents, f)
		pcall(f.SetScript, f, "OnUpdate", nil)
	end
	-- only names that still hold what the addon put there (an old Aether copy may own one)
	for name, value in pairs(F.owned[addon] or {}) do
		if rawget(_G, name) == value then _G[name] = nil end
	end
	F.whenOn[addon] = nil
end

-- the switch becomes known (the addon's saved tables are in): decide, then replay or drop
local function Decide(addon)
	if F.state[addon] then return F.state[addon] end
	F.known[addon] = true
	local st = F:IsOff(addon) and "off" or "on"
	F.state[addon] = st
	F.atStart[addon] = st
	local held = F.held[addon]
	F.held[addon] = nil
	local waiting = F.whenOn[addon]
	F.whenOn[addon] = nil
	if st == "off" then
		Shut(addon)
	else
		local report = geterrorhandler and geterrorhandler() or print
		if held then for _, h in ipairs(held) do xpcall(function() h[2](h[1], unpack(h, 4, 3 + h[3])) end, report) end end
		if waiting then for _, fn in ipairs(waiting) do xpcall(fn, report) end end
	end
	return st
end
F.Decide = Decide

local function Wrap(addon, frame, script)
	local fn = frame:GetScript(script)
	if not fn then return end
	frame:SetScript(script, function(self, ...)
		local st = F.state[addon]
		if st == "on" then return fn(self, ...) end
		if st == "off" then return end
		if script == "OnEvent" then
			local q = F.held[addon] or {}
			F.held[addon] = q
			q[#q + 1] = { self, fn, select("#", ...), ... }
		end
	end)
end

function F:Gate(addon, ...)
	self.frames[addon] = self.frames[addon] or {}
	for i = 1, select("#", ...) do
		local frame = select(i, ...)
		if type(frame) == "table" and frame.GetScript then
			Wrap(addon, frame, "OnEvent")
			Wrap(addon, frame, "OnUpdate")
			table.insert(self.frames[addon], frame)
		end
	end
	if self.state[addon] == "off" then Shut(addon) end
end

-- An addon whose host always loads first (PRISM after NetherUI) can ask at the top of its
-- file: true means it is switched off, and it should stop loading there.
function F:SkipLoad(addon)
	local off = self:IsOff(addon)
	self.state[addon] = off and "off" or "on"
	self.atStart[addon] = self.state[addon]
	return off
end

function F:Global(addon, ...)
	self.globals[addon] = self.globals[addon] or {}
	self.owned[addon] = self.owned[addon] or {}
	for i = 1, select("#", ...) do
		local name = select(i, ...)
		if type(name) == "string" then
			table.insert(self.globals[addon], name)
			local v = rawget(_G, name)
			if v ~= nil then self.owned[addon][name] = v end
		end
	end
	if self.state[addon] == "off" then Shut(addon) end
end

-- loaded and switched on: what another addon should ask before using one of the family
function F:Running(addon)
	local CA = rawget(_G, "C_AddOns")
	local isLoaded = CA and CA.IsAddOnLoaded or rawget(_G, "IsAddOnLoaded")
	if isLoaded then
		local ok, loaded = pcall(isLoaded, addon)
		if not (ok and loaded) then return false end
	end
	local st = self.state[addon]
	if st then return st == "on" end
	return not self:IsOff(addon)
end

function F:WhenOn(addon, fn)
	local st = self.state[addon]
	if st == "on" then return fn() end
	if st == "off" then return end
	self.whenOn[addon] = self.whenOn[addon] or {}
	table.insert(self.whenOn[addon], fn)
end

-- global functions the game calls directly (key bindings, the addon compartment): while the
-- addon is off they say so instead of running
function F:Guard(addon, label, ...)
	for i = 1, select("#", ...) do
		local name = select(i, ...)
		local fn = rawget(_G, name)
		if type(fn) == "function" then
			_G[name] = function(...)
				if F.state[addon] == "off" then print(F.SLASH_OFF:format(label or addon)) return end
				return fn(...)
			end
		end
	end
end

-- the slash command of a switched-off addon says so (and how to switch it back on)
F.SLASH_OFF = "|cff9a7bd6%s|r is switched off in NetherSuite > Nether Addons. Switch it on there and /reload."
function F:Slash(addon, key, name)
	local list = rawget(_G, "SlashCmdList")
	local fn = type(list) == "table" and list[key]
	if type(fn) ~= "function" then return end
	list[key] = function(msg, ...)
		if F.state[addon] == "off" then
			print(F.SLASH_OFF:format(name or addon))
			return
		end
		return fn(msg, ...)
	end
end

-- The watcher: an addon's own ADDON_LOADED (its saved tables, NetherFamilyDB among them, are
-- read just before it) decides its switch; PLAYER_LOGIN decides any still open.
if not F.watcher then
	F.watcher = CreateFrame("Frame")
	F.watcher:RegisterEvent("ADDON_LOADED")
	F.watcher:RegisterEvent("PLAYER_LOGIN")
end
F.watcher:SetScript("OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" then
		Reconcile()
		if F.frames[name] or F.globals[name] or F.whenOn[name] then Decide(name) end
	else
		for addon in pairs(F.frames) do Decide(addon) end
		for addon in pairs(F.globals) do Decide(addon) end
	end
end)
