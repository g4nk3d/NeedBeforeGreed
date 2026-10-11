--[[ NetherFont.lua - the Nether family's fonts for every alphabet (shared)

	Every Nether addon ships this same file. Whichever copy loads first defines _G.NetherFont;
	a newer copy (a higher VERSION) replaces an older one and keeps its fonts.

	Why: the family's fonts (Friz Quadrata, Morpheus, Arial Narrow, Philosopher, Cinzel...) have
	no Korean or Chinese letters, and a font set with SetFont has no fallback: a Korean player's
	name came out as empty boxes. The game's own fonts are font FAMILIES: one font per alphabet.
	NetherFont builds the same kind of family around each Nether font: Latin text keeps the
	Nether font, and Korean, Chinese and Russian letters use the game's own font for them (the
	very files the game's own tooltips use, read from the game at runtime).

	  NetherFont:Apply(region, path, size [, flags])  -> true, or false when the font can't be
	      loaded (the game's standard font is used instead). For font strings, edit boxes and
	      message frames. The region keeps its text colour and shadow.
	  NetherFont:Object(path, size [, flags])         -> a font object (family) for SetFontObject
	  NetherFont:GetFont(region)                      -> path, size, flags it was given (a font
	      family's own GetFont may name another alphabet's font on a Korean or Russian client)
	  NetherFont:Supported()                          -> true when this client has font families

	Without font families (an older client) Apply is a plain SetFont, as before. ]]

local VERSION = 3

local F = _G.NetherFont
if type(F) == "table" and (tonumber(F.version) or 0) >= VERSION then return end
F = type(F) == "table" and F or {}
_G.NetherFont = F
-- a newer copy starts its fonts afresh (an older copy's may be built differently); the count
-- carries on so family names stay unique
if (tonumber(F.version) or 0) < VERSION then F.cache, F.loads = {}, {} end
F.cache = F.cache or {}          -- "path|size|flags" -> font family object (false: refused)
F.count = F.count or 0
F.version = VERSION

local type, tostring, pcall, floor, select, unpack = type, tostring, pcall, math.floor, select, unpack
local STANDARD = function() return _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF" end

-- the game's own font for each alphabet, as its own fonts use them; a known file otherwise
local FALLBACK = {
	korean             = "Fonts\\2002.TTF",
	simplifiedchinese  = "Fonts\\ARKai_T.ttf",
	traditionalchinese = "Fonts\\blei00d.TTF",
	russian            = "Fonts\\FRIZQT___CYR.TTF",
}
local ALPHABETS = { "korean", "simplifiedchinese", "traditionalchinese", "russian" }

local alphabetFiles
local function AlphabetFiles()
	if alphabetFiles then return alphabetFiles end
	alphabetFiles = {}
	local base = _G.GameFontNormal or _G.GameTooltipText or _G.SystemFont_Shadow_Med1
	for _, a in ipairs(ALPHABETS) do
		local path
		if base and base.GetFontObjectForAlphabet then
			local ok, obj = pcall(base.GetFontObjectForAlphabet, base, a)
			if ok and obj and obj.GetFont then
				local okF, p = pcall(obj.GetFont, obj)
				if okF and type(p) == "string" and p ~= "" then path = p end
			end
		end
		alphabetFiles[a] = path or FALLBACK[a]
	end
	return alphabetFiles
end

function F:Supported() return type(_G.CreateFontFamily) == "function" end

-- Fonts with Cyrillic of their own keep it; the rest borrow the game's Russian font
local HAS_CYRILLIC = { philosopher = true, ["morpheus_cyr"] = true, ["frizqt___cyr"] = true, arialn = true }
local function OwnCyrillic(path)
	local name = tostring(path):lower():match("([^\\/]+)%.[ot]tf$") or ""
	for k in pairs(HAS_CYRILLIC) do if name:find(k, 1, true) then return true end end
	return false
end

-- can this client load this font file? A yes is remembered; a no is not (the game may refuse
-- a file the first time it is asked for it and load it a moment later)
F.loads = F.loads or {}
function F:Loads(path, size, flags)
	if self.loads[path] then return true end
	if not self.probe then
		local holder = _G.CreateFrame and _G.CreateFrame("Frame")
		self.probe = holder and holder:CreateFontString()
	end
	if not self.probe then return true end
	local ok, res = pcall(self.probe.SetFont, self.probe, path, size or 12, "")
	if ok and res ~= false then self.loads[path] = true return true end
	return false
end

local function Key(path, size, flags)
	size = floor((tonumber(size) or 12) * 10 + 0.5) / 10
	return path .. "|" .. size .. "|" .. (flags or ""), size
end

function F:Object(path, size, flags)
	if not self:Supported() or type(path) ~= "string" then return nil end
	flags = flags or ""
	local key
	key, size = Key(path, size, flags)
	local obj = self.cache[key]
	if obj then return obj end
	if obj == false then return nil end           -- the game refused to build this family
	-- the Nether font itself must load (SetFont says so; a family wouldn't), else no family yet
	if not self:Loads(path, size, flags) then return nil end
	local files = AlphabetFiles()
	local members = { { alphabet = "roman", file = path, height = size, flags = flags } }
	for _, a in ipairs(ALPHABETS) do
		local file = files[a]
		if a == "russian" and OwnCyrillic(path) then file = path end
		members[#members + 1] = { alphabet = a, file = file, height = size, flags = flags }
	end
	self.count = self.count + 1
	local ok, made = pcall(_G.CreateFontFamily, "NetherFont" .. self.count, members)
	if not ok or not made then self.cache[key] = false return nil end
	self.cache[key] = made
	return made
end

-- What SetFontObject would change and the caller had set: colour, shadow, justification and
-- line spacing. Values are only counted and passed back, never looked at (some are hidden
-- from addons on nameplates).
local function Pack(...) return { n = select("#", ...), ... } end
local function Keep(region)
	local keep = {}
	if region.GetTextColor then keep.c = Pack(region:GetTextColor()) end
	if region.GetShadowOffset then keep.so = Pack(region:GetShadowOffset()) end
	if region.GetShadowColor then keep.sc = Pack(region:GetShadowColor()) end
	if region.GetJustifyH then keep.jh = Pack(region:GetJustifyH()) end
	if region.GetJustifyV then keep.jv = Pack(region:GetJustifyV()) end
	if region.GetSpacing then keep.sp = Pack(region:GetSpacing()) end
	return keep
end
local function Put(region, method, t)
	if t and t.n > 0 and region[method] then pcall(region[method], region, unpack(t, 1, t.n)) end
end
local function Restore(region, keep)
	Put(region, "SetTextColor", keep.c)
	Put(region, "SetShadowOffset", keep.so)
	Put(region, "SetShadowColor", keep.sc)
	Put(region, "SetJustifyH", keep.jh)
	Put(region, "SetJustifyV", keep.jv)
	Put(region, "SetSpacing", keep.sp)
end

-- A font string given a font the game hasn't finished preparing (a font file or a size used for
-- the first time) draws nothing - or keeps drawing its old font - until its text changes once
-- the font is ready; writing the same text again doesn't count. A label or a "?" written once
-- stayed empty for good, and a list showed its names only after scrolling. So:
--   - after a real change of font its own text is written again, at once and a few times over
--     the next seconds, so a name, a label or a mark never stays empty;
--   - a font string already wearing the font asked for is left alone (nothing to redo).
-- Only plain text is written again: never a value the game keeps secret (a nameplate's name,
-- for one), which may not even be compared, and never a forbidden or protected region.
local function Secret(v) return _G.issecretvalue ~= nil and issecretvalue(v) == true end
F.Secret = Secret
local redraw = setmetatable({}, { __mode = "k" })
local function Rewrite(region)
	if region.IsForbidden and region:IsForbidden() then return end
	if region.IsProtected then
		local okP, prot = pcall(region.IsProtected, region)
		if not okP or Secret(prot) or prot then return end
	end
	local ok, t = pcall(region.GetText, region)
	if not ok or Secret(t) or type(t) ~= "string" or t == "" then return end
	pcall(region.SetText, region, "")
	pcall(region.SetText, region, t)
end
local function Redraw()
	local list = {}
	for region in pairs(redraw) do list[#list + 1] = region end
	for _, region in ipairs(list) do Rewrite(region) end
	return list
end
-- one set of passes at a time; time-based, so a pass that never came can't stop later ones
local busyUntil = 0
local DELAYS = { 0, 0.3, 1.5, 4 }
-- the game's own nameplates are left to the game: their text is the game's to write
local function OnNameplate(region)
	local f = region.GetParent and region:GetParent()
	for _ = 1, 8 do
		if not f then return false end
		if type(f.namePlateUnitToken) ~= "nil" then return true end
		local okN, name = pcall(f.GetName, f)
		if okN and type(name) == "string" and not Secret(name) and name:find("^NamePlate") then return true end
		f = f.GetParent and f:GetParent()
	end
	return false
end

local function Watch(region)
	if not (region.GetObjectType and region.GetText and region.SetText) then return end
	local okT, kind = pcall(region.GetObjectType, region)
	if not okT or kind ~= "FontString" then return end
	if OnNameplate(region) then return end
	Rewrite(region)
	redraw[region] = true
	if not (_G.C_Timer and C_Timer.After) then return end
	local now = _G.GetTime and GetTime() or 0
	if now < busyUntil then return end
	busyUntil = now + DELAYS[#DELAYS] + 0.1
	-- the next frame, then three times more for font files that take longer to arrive
	for n, d in ipairs(DELAYS) do
		C_Timer.After(d, function()
			Redraw()
			if n == #DELAYS then
				for r in pairs(redraw) do redraw[r] = nil end
				busyUntil = 0
			end
		end)
	end
end
F.Watch = Watch

local function Wearing(region, obj)
	if region.GetFontObject then
		local ok, cur = pcall(region.GetFontObject, region)
		if ok and not Secret(cur) then return cur == obj end
	end
	return region.__netherFontObj == obj
end

local function UseFamily(region, obj, path, size, flags)
	if Wearing(region, obj) then
		region.__netherFont = { path, size, flags }
		return true
	end
	local keep = Keep(region)
	if not pcall(region.SetFontObject, region, obj) then return false end
	Restore(region, keep)
	region.__netherFontObj = obj
	-- what was asked for (a family's GetFont may name another alphabet's font)
	region.__netherFont = { path, size, flags }
	Watch(region)
	return true
end


function F:Apply(region, path, size, flags)
	if not (region and region.SetFont) then return false end
	flags = flags or ""
	if region.SetFontObject then
		local obj = self:Object(path, size, flags)
		if obj and UseFamily(region, obj, path, size, flags) then return true end
	end
	region.__netherFont = nil
	region.__netherFontObj = nil
	-- no families on this client, or this font didn't load yet: the plain way
	local okF, cp, cs, cf = pcall(region.GetFont, region)
	if okF and not (Secret(cp) or Secret(cs) or Secret(cf)) and cp == path and type(cs) == "number"
		and math.abs(cs - (tonumber(size) or 0)) < 0.05 and (cf or "") == flags
		and not (region.SetFontObject and self:Supported()) then
		return true
	end
	if region:SetFont(path, size, flags) ~= false then
		Watch(region)
		-- it loaded after all: now with its family
		if region.SetFontObject and self:Supported() then
			self.loads[path] = true
			local obj = self:Object(path, size, flags)
			if obj then UseFamily(region, obj, path, size, flags) end
		end
		return true
	end
	local std = STANDARD()
	local fallback = std ~= path and region.SetFontObject and self:Object(std, size, flags)
	if fallback and UseFamily(region, fallback, std, size, flags) then return false end
	region:SetFont(std, size, flags)
	return false
end

-- the font a region was given (path, size, flags): what Apply was asked for, else its own
function F:GetFont(region)
	if not region then return nil end
	local f = region.__netherFont
	if not (region.GetFont) then if f then return f[1], f[2], f[3] end return nil end
	local p, s, fl = region:GetFont()
	-- read from a nameplate the game may keep them secret: then what was asked for stands
	if Secret(p) or Secret(s) or Secret(fl) then
		if f then return f[1], f[2], f[3] end
		return nil
	end
	-- someone else set a plain font since (another size or outline): that one counts now
	if f and type(s) == "number" and math.abs(s - (tonumber(f[2]) or 0)) < 0.05 and (fl or "") == (f[3] or "") then
		return f[1], f[2], f[3]
	end
	region.__netherFont = nil
	return p, s, fl
end
