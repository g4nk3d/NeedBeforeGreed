--[[ Need Before Greed - Family/Skin.lua (ported from NetherCombatText UI/Skin.lua; the family's settings look)
	Used by the Esc > Options page only: the game's own screens keep Need Before Greed's art.
	The settings window's look. Every control asks the skin for ROLES, never raw colours, so one
	switch re-colours all of them, live, no reload.

	  own look     the Nether family's: deep navy, gold trim, ember accent (works with nothing else
	               installed)
	  NetherUI     when NetherUI is loaded and "Follow NetherUI's theme" is ticked (the default):
	               its theme colours and fonts, its window, panel and button art (through NetherUI's
	               public Integrations.Kit), re-applied on every theme change (THEME_CHANGED)

	Roles: text, textDim, header, accent, accentLo, accent2, border, bg, bgTop, bgAlt, inset,
	rowHover, rowSel

	  Skin:Following()                   true while the NetherUI theme is in use
	  Skin:Color(role)                   r, g, b, a
	  Skin:Paint(obj, role [, opts])     colour a texture / font string by role (kept on change)
	  Skin:Font(fs, kind, size [, flags]) kind: body | title | header (kept on change)
	  Skin:Gradient(tex, roleTop, roleBottom)   vertical, kept on change
	  Skin:Window(frame)                 the window body
	  Skin:Panel(frame [, inset])        an inner panel (the page list, wells)
	  Skin:Button(button [, nav])        push-button art; nav = a flat page-list entry
	  Skin:Select(button, on)            a nav entry's chosen state
	  Skin:OnChange(fn)                  after every switch / theme change ]]

local _, ns = ...
local FCT = ns.P
FCT.counters = FCT.counters or {}
local Skin = FCT:Module("Skin")
local WHITE = "Interface\\Buttons\\WHITE8X8"
Skin.WHITE = WHITE

local type, pairs, ipairs, pcall, rawget = type, pairs, ipairs, pcall, rawget

local function rgb(r, g, b, a) return { r / 255, g / 255, b / 255, a or 1 } end

-- the family look (the same palette NetherBags and NetherGoblin use, ember for this addon)
Skin.OWN = {
	text = rgb(226, 230, 240), textDim = rgb(140, 150, 176), header = rgb(250, 222, 150),
	accent = rgb(232, 196, 120), accentLo = rgb(176, 124, 52), accent2 = rgb(255, 140, 70),
	border = rgb(54, 64, 98), bg = rgb(9, 12, 22, 0.97), bgTop = rgb(22, 28, 50, 0.97), bgAlt = rgb(16, 20, 36, 0.92),
	inset = rgb(5, 7, 14, 0.94), rowHover = rgb(110, 90, 40, 0.45), rowSel = rgb(110, 90, 40, 0.75),
}
Skin.FONTS = {
	body = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",
	title = "Fonts\MORPHEUS.TTF",
	header = "Fonts\MORPHEUS.TTF",
}

-- our roles in NetherUI's palette (anything it lacks falls back to the own look)
local FROM_NUI = { text = "text", textDim = "textDim", header = "header", accent = "accent", accentLo = "accentSoft",
	accent2 = "gem", border = "border", bg = "bg", bgTop = "bgAlt", bgAlt = "bgAlt", inset = "bgInset",
	rowHover = "accentSoft", rowSel = "accentSoft" }

local function NetherUI()
	local A = rawget(_G, "NetherUI")
	if type(A) == "table" and type(A.palette) == "table" and type(A.palette.bg) == "table" then return A end
	return nil
end
Skin.NetherUI = NetherUI

function Skin:Following()
	if not NetherUI() then return false end
	local st = FCT.db and FCT.db.settings
	return not (st and st.followNetherUI == false)
end

function Skin:Color(role)
	if self:Following() then
		local A = NetherUI()
		local c = FROM_NUI[role] and A.palette[FROM_NUI[role]]
		if type(c) == "table" and c[1] then
			local a = c[4] or 1
			if role == "rowHover" then a = math.min(a, 0.45) elseif role == "rowSel" then a = math.min(a, 0.75) end
			return c[1], c[2] or c[1], c[3] or c[1], a
		end
	end
	local c = self.OWN[role] or self.OWN.text
	return c[1], c[2], c[3], c[4] or 1
end

local function FontFile(kind)
	if Skin:Following() then
		local A = NetherUI()
		if type(A.fonts) == "table" then
			if kind == "title" and type(A.BRAND_FONT) == "string" then return A.BRAND_FONT end
			local p = (kind == "title" or kind == "header") and A.fonts.header or A.fonts.body
			if type(p) == "string" then return p end
		end
	end
	return Skin.FONTS[kind] or Skin.FONTS.body
end

---------------------------------------------------------------------------------------------
-- painted objects, re-painted on every change
---------------------------------------------------------------------------------------------
local painted = setmetatable({}, { __mode = "k" })
local fonts = setmetatable({}, { __mode = "k" })
local grads = setmetatable({}, { __mode = "k" })
local listeners = {}

local function Apply(obj, e)
	local r, g, b, a = Skin:Color(e.role)
	if e.alpha then a = a * e.alpha end
	local kind = obj.GetObjectType and obj:GetObjectType()
	if kind == "FontString" or kind == "EditBox" then obj:SetTextColor(r, g, b, a)
	elseif obj.SetVertexColor then obj:SetVertexColor(r, g, b, a) end
end

function Skin:Paint(obj, role, opts)
	if not obj then return obj end
	if obj.GetObjectType and obj:GetObjectType() == "Texture" and not obj:GetTexture() then obj:SetTexture(WHITE) end
	local e = { role = role, alpha = opts and opts.alpha }
	painted[obj] = e
	Apply(obj, e)
	return obj
end

local function ApplyFont(fs, f)
	local path = FontFile(f.kind)
	local ok
	if NetherFont and NetherFont.Apply then
		ok = NetherFont:Apply(fs, path, f.size, f.flags or "")
	else
		ok = pcall(fs.SetFont, fs, path, f.size, f.flags or "") and fs:GetFont() ~= nil
	end
	if not ok then
		pcall(fs.SetFont, fs, Skin.FONTS.body, f.size, f.flags or "")
		FCT.counters.fontFallback = (FCT.counters.fontFallback or 0) + 1
	end
	if fs.SetShadowOffset then
		fs:SetShadowOffset(1, -1)
		fs:SetShadowColor(0, 0, 0, 0.85)
	end
	-- a font change must never cost the text its colour role
	if painted[fs] then Apply(fs, painted[fs]) end
end

function Skin:Font(fs, kind, size, flags)
	if not fs then return fs end
	local f = { kind = kind or "body", size = size or 12, flags = flags }
	fonts[fs] = f
	ApplyFont(fs, f)
	return fs
end

local function SetGrad(tex, top, bottom)
	local r1, g1, b1, a1 = Skin:Color(top)
	local r2, g2, b2, a2 = Skin:Color(bottom)
	-- VERTICAL gradients run bottom -> top in the game
	if tex.SetGradient and _G.CreateColor and pcall(tex.SetGradient, tex, "VERTICAL", CreateColor(r2, g2, b2, a2), CreateColor(r1, g1, b1, a1)) then return end
	if tex.SetGradientAlpha and pcall(tex.SetGradientAlpha, tex, "VERTICAL", r2, g2, b2, a2, r1, g1, b1, a1) then return end
	tex:SetVertexColor((r1 + r2) / 2, (g1 + g2) / 2, (b1 + b2) / 2, (a1 + a2) / 2)
end

function Skin:Gradient(tex, top, bottom)
	tex:SetTexture(WHITE)
	grads[tex] = { top, bottom }
	SetGrad(tex, top, bottom)
	return tex
end

-- a 1 px frame of four edges around f, painted by role
local function Edges(owner, layer, role, alpha)
	local out = {}
	for i, p in ipairs({ { "TOPLEFT", "TOPRIGHT", "h" }, { "BOTTOMLEFT", "BOTTOMRIGHT", "h" }, { "TOPLEFT", "BOTTOMLEFT", "v" }, { "TOPRIGHT", "BOTTOMRIGHT", "v" } }) do
		local e = owner:CreateTexture(nil, layer or "BORDER")
		e:SetPoint(p[1]) e:SetPoint(p[2])
		if p[3] == "h" then e:SetHeight(1) else e:SetWidth(1) end
		Skin:Paint(e, role, alpha and { alpha = alpha })
		out[i] = e
	end
	return out
end
Skin.Edges = Edges

---------------------------------------------------------------------------------------------
-- NetherUI's art, through its public Integrations.Kit (nothing when NetherUI isn't there)
---------------------------------------------------------------------------------------------
local function Kit()
	local A = NetherUI()
	local I = A and A.Integrations
	if not (I and I.Kit and I.Kit.New) then return nil end
	if Skin.rec == nil then
		local ok, rec = pcall(I.Kit.New, I.Kit, "nethercombattext")
		Skin.rec = ok and rec or false
		if not ok then FCT:RecordError("NetherUI kit", rec) end
	end
	return Skin.rec or nil
end

local windows = setmetatable({}, { __mode = "k" })
local panels = setmetatable({}, { __mode = "k" })
local buttons = setmetatable({}, { __mode = "k" })

local function Layer(frame)
	local l = CreateFrame("Frame", nil, frame)
	l:SetAllPoints()
	l:SetFrameLevel(math.max(0, frame:GetFrameLevel()))
	return l
end

function Skin:Window(frame)
	local own = Layer(frame)
	local body = own:CreateTexture(nil, "BACKGROUND", nil, -6)
	body:SetAllPoints()
	self:Gradient(body, "bgTop", "bg")
	local band = own:CreateTexture(nil, "BACKGROUND", nil, -5)
	band:SetPoint("TOPLEFT", 1, -1) band:SetPoint("TOPRIGHT", -1, -1) band:SetHeight(36)
	self:Paint(band, "bgTop")
	local rule = own:CreateTexture(nil, "BORDER")
	rule:SetPoint("TOPLEFT", 12, -36) rule:SetPoint("TOPRIGHT", -12, -36) rule:SetHeight(1)
	self:Paint(rule, "accentLo", { alpha = 0.8 })
	Edges(own, "BORDER", "accentLo", 0.7)
	local kit
	local rec = Kit()
	if rec then
		kit = Layer(frame)
		local ok, err = pcall(rec.Panel, rec, kit, { ornate = true })
		local A = NetherUI()
		if ok and A.Spectrum and A.Spectrum.Register then pcall(A.Spectrum.Register, A.Spectrum, kit) end
		if not ok then FCT:RecordError("NetherUI window art", err) kit:Hide() kit = nil end
	end
	windows[frame] = { own = own, kit = kit }
	self:ApplyWindow(frame)
end

function Skin:ApplyWindow(frame)
	local w = windows[frame]
	if not w then return end
	local useKit = w.kit ~= nil and self:Following()
	w.own:SetShown(not useKit)
	if w.kit then w.kit:SetShown(useKit) end
end

function Skin:Panel(frame, inset)
	local own = Layer(frame)
	local fill = own:CreateTexture(nil, "BACKGROUND")
	fill:SetAllPoints()
	self:Paint(fill, inset and "inset" or "bgAlt")
	Edges(own, "BORDER", "border")
	local kit
	local rec = Kit()
	if rec then
		kit = Layer(frame)
		if not pcall(rec.Panel, rec, kit, inset and { inset = true, alpha = 0.9 } or { small = true }) then kit:Hide() kit = nil end
	end
	panels[frame] = { own = own, kit = kit }
	self:ApplyPanel(frame)
end

function Skin:ApplyPanel(frame)
	local p = panels[frame]
	if not p then return end
	local useKit = p.kit ~= nil and self:Following()
	p.own:SetShown(not useKit)
	if p.kit then p.kit:SetShown(useKit) end
end

-- push buttons: own fill + edge + hover; NetherUI's button art on top while following.
-- nav entries: flat rows with a hover wash and an accent bar when chosen.
function Skin:Button(b, nav)
	local fs = b:GetFontString()
	if not fs then
		fs = b:CreateFontString(nil, "OVERLAY")
		b:SetFontString(fs)
	end
	self:Font(fs, "body", nav and 13 or 12)
	self:Paint(fs, "text")
	local own = {}
	own.fill = b:CreateTexture(nil, "BACKGROUND", nil, -4)
	own.fill:SetAllPoints()
	if nav then
		self:Paint(own.fill, "rowSel")
		own.fill:SetAlpha(0)
		own.bar = b:CreateTexture(nil, "ARTWORK")
		own.bar:SetPoint("TOPLEFT") own.bar:SetPoint("BOTTOMLEFT") own.bar:SetWidth(3)
		self:Paint(own.bar, "accent")
		own.bar:Hide()
		fs:ClearAllPoints()
		fs:SetPoint("LEFT", 12, 0)
		fs:SetJustifyH("LEFT")
	else
		self:Gradient(own.fill, "bgTop", "bgAlt")
		own.edges = Edges(b, "BORDER", "border")
	end
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	self:Paint(hl, "rowHover")
	b:SetHighlightTexture(hl)
	local rec = not nav and Kit() or nil
	local art
	if rec then
		local ok, res = pcall(rec.Button, rec, b)
		art = ok and res or nil
	end
	buttons[b] = { own = own, art = art, nav = nav }
	b:HookScript("OnEnter", function() if not nav and own.edges then for _, e in ipairs(own.edges) do Skin:Paint(e, "accent") end end end)
	b:HookScript("OnLeave", function() if not nav and own.edges then for _, e in ipairs(own.edges) do Skin:Paint(e, "border") end end end)
	self:ApplyButton(b)
	return b
end

function Skin:ApplyButton(b)
	local e = buttons[b]
	if not e or e.nav then return end
	local useKit = e.art ~= nil and self:Following()
	e.own.fill:SetShown(not useKit)
	for _, t in ipairs(e.own.edges or {}) do t:SetShown(not useKit) end
	-- (art made while the kit record is off is still shown: hide it by hand)
	if e.art then
		for _, k in ipairs({ "fill", "border" }) do if e.art[k] then e.art[k]:SetShown(useKit) end end
	end
end

function Skin:Select(b, on)
	local e = buttons[b]
	if not (e and e.nav) then return end
	e.own.fill:SetAlpha(on and 1 or 0)
	e.own.bar:SetShown(on and true or false)
	self:Paint(b:GetFontString(), on and "header" or "text")
end

---------------------------------------------------------------------------------------------
function Skin:OnChange(fn) listeners[#listeners + 1] = fn end

function Skin:Refresh()
	local rec = Kit()
	if rec then
		if self:Following() then pcall(rec.On, rec) else pcall(rec.Off, rec) end
	end
	for fs, f in pairs(fonts) do ApplyFont(fs, f) end
	for obj, e in pairs(painted) do Apply(obj, e) end
	for tex, g in pairs(grads) do SetGrad(tex, g[1], g[2]) end
	for frame in pairs(windows) do self:ApplyWindow(frame) end
	for frame in pairs(panels) do self:ApplyPanel(frame) end
	for b in pairs(buttons) do self:ApplyButton(b) end
	for _, fn in ipairs(listeners) do FCT:Safe("skin change", fn) end
end

FCT:Register("SETTINGS_CHANGED", function(root)
	if root == "followNetherUI" or root == "profile" then Skin:Refresh() end
end)

FCT:Register("LOGIN", function()
	local A = NetherUI()
	if A and type(A.RegisterCallback) == "function" then
		local ok, err = pcall(A.RegisterCallback, A, "THEME_CHANGED", function()
			if Skin:Following() then FCT:After(0.05, function() Skin:Refresh() end) end
		end)
		if not ok then FCT:RecordError("NetherUI theme callback", err) end
	end
	Skin:Refresh()
end)
