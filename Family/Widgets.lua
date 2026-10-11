--[[ Need Before Greed - Family/Widgets.lua (ported from NetherCombatText UI/Widgets.lua)
	The settings window's controls, drawn by the skin (UI/Skin.lua): the Nether family look on
	its own, the current NetherUI theme when NetherUI is installed.

	  W.Check(parent, label, get, set [, tip])          a tick box
	  W.Slider(parent, label, min, max, step, get, set [, fmt])
	  W.Cycle(parent, label, choices, get, set)          a button that steps through { {value, label}, ... }
	  W.Button(parent, text, width, onClick)
	  W.Input(parent, label, width, get, set)            a text box (Enter or leaving it saves)
	  W.Header(parent, text)
	  W.Note(parent, text [, width])
	  W.Stack(parent)                                    lays controls top to bottom: stack:Add(widget, height)

	Every control re-reads its value when shown (W.Refresh(page)), so a change made elsewhere (the
	hub, a profile switch, a slash command) is always what the window shows. ]]

local _, ns = ...
local FCT = ns.P
local W = FCT:Module("Widgets")
local Skin = FCT.Skin

local function Sound(kind)
	if NetherSound and NetherSound.Play then NetherSound:Play(kind) end
end

local function Tip(owner, title, text)
	if not text then return end
	owner:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(title, 1, 0.82, 0)
		GameTooltip:AddLine(text, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	owner:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Text(parent, kind, size, role)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	Skin:Font(fs, kind, size)
	Skin:Paint(fs, role)
	return fs
end
W.Text = Text

function W.Header(parent, text)
	local fs = Text(parent, "header", 15, "header")
	fs:SetText(text)
	fs:SetJustifyH("LEFT")
	fs.refresh = function() end
	return fs
end

function W.Note(parent, text, width)
	local fs = Text(parent, "body", 11, "textDim")
	fs:SetWidth(width or 520)
	fs:SetJustifyH("LEFT")
	fs:SetText(text)
	return fs
end

function W.Check(parent, label, get, set, tip)
	local cb = CreateFrame("CheckButton", nil, parent)
	cb:SetSize(18, 18)
	local fill = cb:CreateTexture(nil, "BACKGROUND")
	fill:SetAllPoints()
	Skin:Paint(fill, "inset")
	local edges = Skin.Edges(cb, "BORDER", "border")
	local mark = cb:CreateTexture(nil, "ARTWORK")
	mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	mark:SetPoint("TOPLEFT", -4, 4) mark:SetPoint("BOTTOMRIGHT", 4, -4)
	Skin:Paint(mark, "accent")
	cb:SetCheckedTexture(mark)
	local hl = cb:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	Skin:Paint(hl, "rowHover")
	cb:SetHighlightTexture(hl)
	cb.label = Text(cb, "body", 12, "text")
	cb.label:SetPoint("LEFT", cb, "RIGHT", 8, 0)
	cb.label:SetText(label)
	-- the label is part of the box: clicking the words ticks it too
	cb:SetHitRectInsets(0, -math.min(420, (cb.label:GetStringWidth() or 0) + 10), -3, -3)
	cb:HookScript("OnEnter", function() for _, e in ipairs(edges) do Skin:Paint(e, "accent") end end)
	cb:HookScript("OnLeave", function() for _, e in ipairs(edges) do Skin:Paint(e, "border") end end)
	cb:SetScript("OnClick", function(self)
		local on = self:GetChecked() and true or false
		Sound(on and "on" or "off")
		set(on)
		W.RefreshAll()
	end)
	cb.refresh = function() cb:SetChecked(get() and true or false) end
	Tip(cb, label, tip)
	return cb
end

function W.Slider(parent, label, lo, hi, step, get, set, fmt)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(260, 40)
	f.label = Text(f, "body", 12, "text")
	f.label:SetPoint("TOPLEFT", 4, 0)
	f.value = Text(f, "body", 12, "header")
	f.value:SetPoint("TOPRIGHT", -4, 0)
	local s = CreateFrame("Slider", nil, f)
	s:SetPoint("BOTTOMLEFT", 4, 2)
	s:SetPoint("BOTTOMRIGHT", -4, 2)
	s:SetHeight(16)
	s:SetOrientation("HORIZONTAL")
	s:EnableMouse(true)
	local track = s:CreateTexture(nil, "BACKGROUND")
	track:SetPoint("LEFT", 0, 0)
	track:SetPoint("RIGHT", 0, 0)
	track:SetHeight(6)
	Skin:Paint(track, "inset")
	local line = s:CreateTexture(nil, "BORDER")
	line:SetPoint("LEFT", 0, 0)
	line:SetPoint("RIGHT", 0, 0)
	line:SetHeight(1)
	Skin:Paint(line, "border")
	local thumb = s:CreateTexture(nil, "OVERLAY")
	thumb:SetSize(10, 16)
	Skin:Paint(thumb, "accent")
	s:SetThumbTexture(thumb)
	s:SetMinMaxValues(lo, hi)
	s:SetValueStep(step)
	if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
	local function Show(v) f.value:SetText(fmt and fmt:format(v) or tostring(v)) end
	f.label:SetText(label)
	local busy = false
	s:SetScript("OnValueChanged", function(_, v)
		if busy then return end
		v = math.floor(v / step + 0.5) * step
		Show(v)
		set(v)
	end)
	s:SetScript("OnMouseUp", function() Sound("select") end)
	f.refresh = function()
		busy = true
		local v = tonumber(get()) or lo
		s:SetValue(v)
		Show(v)
		busy = false
	end
	f.slider = s
	return f
end

local function PushButton(parent, width, height)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width or 160, height or 24)
	Skin:Button(b)
	return b
end
W.PushButton = PushButton

function W.Cycle(parent, label, choices, get, set)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(360, 26)
	f.label = Text(f, "body", 12, "text")
	f.label:SetPoint("LEFT", 4, 0)
	f.label:SetText(label)
	local b = PushButton(f, 170, 22)
	b:SetPoint("LEFT", f, "LEFT", 180, 0)
	local function Choices() return type(choices) == "function" and choices() or choices end
	local function Label(v)
		for _, c in ipairs(Choices()) do if c[1] == v then return c[2] end end
		return tostring(v)
	end
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetScript("OnClick", function(_, button)
		local list, cur, at = Choices(), get(), 1
		for i, c in ipairs(list) do if c[1] == cur then at = i end end
		at = at + (button == "RightButton" and -1 or 1)
		if at > #list then at = 1 elseif at < 1 then at = #list end
		Sound("select")
		set(list[at][1])
		W.RefreshAll()
	end)
	Tip(b, label ~= "" and label or "Choice", "Click for the next choice, right-click for the one before.")
	f.refresh = function() b:SetText(Label(get())) end
	f.button = b
	return f
end

function W.Button(parent, text, width, onClick)
	local b = PushButton(parent, width or 160, 24)
	b:SetText(text)
	b:SetScript("OnClick", function(...) Sound("click") onClick(...) end)
	b.refresh = function() end
	return b
end

-- a nav entry (the page list on the left)
function W.NavButton(parent, text, width, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width or 150, 26)
	Skin:Button(b, true)
	b:SetText(text)
	b:SetScript("OnClick", function(...) Sound("select") onClick(...) end)
	return b
end

function W.Input(parent, label, width, get, set)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize((width or 200) + 184, 26)
	f.label = Text(f, "body", 12, "text")
	f.label:SetPoint("LEFT", 4, 0)
	f.label:SetText(label)
	local e = CreateFrame("EditBox", nil, f)
	e:SetSize(width or 200, 22)
	e:SetPoint("LEFT", f, "LEFT", 186, 0)
	e:SetAutoFocus(false)
	e:SetTextInsets(6, 6, 0, 0)
	Skin:Font(e, "body", 12)
	Skin:Paint(e, "text")
	local fill = e:CreateTexture(nil, "BACKGROUND")
	fill:SetAllPoints()
	Skin:Paint(fill, "inset")
	local edges = Skin.Edges(e, "BORDER", "border")
	local function Save() set(e:GetText() or "") e:ClearFocus() end
	e:SetScript("OnEnterPressed", Save)
	e:SetScript("OnEditFocusGained", function() for _, x in ipairs(edges) do Skin:Paint(x, "accent") end end)
	e:SetScript("OnEditFocusLost", function()
		for _, x in ipairs(edges) do Skin:Paint(x, "border") end
		set(e:GetText() or "")
	end)
	e:SetScript("OnEscapePressed", function() e:ClearFocus() f.refresh() end)
	f.refresh = function() if not e:HasFocus() then e:SetText(tostring(get() or "")) end end
	f.edit = e
	return f
end

-- a column of controls
function W.Stack(parent, x, y)
	local st = { parent = parent, x = x or 16, y = y or -16, items = {} }
	function st:Add(widget, height, indent)
		widget:ClearAllPoints()
		widget:SetPoint("TOPLEFT", self.parent, "TOPLEFT", self.x + (indent or 0), self.y)
		self.y = self.y - (height or 28)
		self.items[#self.items + 1] = widget
		return widget
	end
	function st:Gap(h) self.y = self.y - (h or 10) end
	return st
end

W.pages = {}
function W.RefreshAll()
	for _, page in ipairs(W.pages) do
		if page:IsShown() then W.Refresh(page) end
	end
	FCT:Fire("UI_REFRESH")
end

function W.Refresh(page)
	for _, w in ipairs(page.widgets or {}) do
		if w.refresh then FCT:Safe("refresh", w.refresh) end
	end
end

-- a theme change re-draws what paints itself by hand (the style tiles)
Skin:OnChange(function() W.RefreshAll() end)
