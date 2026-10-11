--[[ Need Before Greed - UI/Minimap.lua
	The minimap button (shown unless switched off: Need Before Greed is a minigame you open from here or from
	NetherSuite's Minigames tab). Left-click opens or closes the game; drag it around the minimap's
	edge; its place is remembered. No libraries: a plain button on the Minimap frame (unnamed, so the
	addon keeps its single global). ]]

local _, ns = ...
local P = ns.P
local M = P:Module("Minimap")

local btn

local function Angle()
	local m = P.db.minimap
	local a = type(m) == "table" and tonumber(m.angle)
	return a or 235
end

local function Place()
	local ang = math.rad(Angle())
	local r = (Minimap:GetWidth() / 2) + 6
	btn:ClearAllPoints()
	btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(ang) * r, math.sin(ang) * r)
end

local function Build()
	btn = CreateFrame("Button", nil, Minimap)
	btn:SetSize(32, 32)
	btn:SetFrameStrata("MEDIUM")
	btn:SetFrameLevel(Minimap:GetFrameLevel() + 8)
	btn:RegisterForClicks("LeftButtonUp")
	btn:RegisterForDrag("LeftButton")
	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(P.MEDIA .. "Minimap")
	icon:SetSize(24, 24)
	icon:SetPoint("CENTER", 0, 1)
	local ring = btn:CreateTexture(nil, "OVERLAY")
	ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	ring:SetSize(54, 54)
	ring:SetPoint("TOPLEFT")
	btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	btn:SetScript("OnClick", function() P.Game:Toggle() end)
	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("Need Before Greed")
		GameTooltip:AddLine("Click to play. Drag to move this button.", 1, 1, 1, true)
		GameTooltip:AddLine("Hide it in Esc > Options > AddOns > Need Before Greed.", 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	btn:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local s = Minimap:GetEffectiveScale()
			local cx, cy = GetCursorPosition()
			cx, cy = cx / s, cy / s
			if type(P.db.minimap) ~= "table" then P.db.minimap = {} end
			P.db.minimap.angle = math.deg(math.atan2(cy - my, cx - mx))
			Place()
		end)
	end)
	btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	Place()
	btn:SetShown(P:Setting("minimapButton") ~= false)
end

-- Settings: "Show the minimap button" (shown unless the player hides it)
function M:SetShown(on) if btn then btn:SetShown(on and true or false) end end

P:Register("LOGIN", function() if Minimap then Build() end end)
