--[[ NetherSound.lua - the Nether family's interface sounds (shared)

	Every Nether addon ships this same file, so a button, a tab or a checkbox sounds the same
	in all of them. Whichever copy loads first defines _G.NetherSound; a newer copy (a higher
	VERSION) replaces an older one's sounds and keeps its state.

	  NetherSound:Play(kind)       kind: one of the names below
	  NetherSound:SetMuted(muted)  the family-wide switch (NetherSuite's "UI sounds" setting)
	  NetherSound:IsMuted()

	  click     a push button: apply, reset, copy, open something, an icon button, a link
	  tab       a tab, page or category in a window
	  on / off  a checkbox or switch turned on / off
	  select    a choice: a list or dropdown entry, a cycle button, a theme, a colour, a slider
	            let go at a new value
	  open      a window the player opened
	  close     a window the player closed

	The sounds are the game's own interface sounds (no files to ship), played on the SFX
	channel, so the game's sound options apply to them too.

	One action, one sound: everything asked for during a frame is played as ONE sound at the
	end of that frame, the most meaningful one (open/close, then on/off, then tab, then select,
	then click). A button that opens a window plays "open", not "click" and "open"; a control
	template's own "click" gives way to the "tab" or "select" its owner asks for. ]]

local VERSION = 1

local S = _G.NetherSound
if type(S) == "table" and (tonumber(S.version) or 0) >= VERSION then return end
S = type(S) == "table" and S or { muted = false }
_G.NetherSound = S
S.version = VERSION

local K = _G.SOUNDKIT or {}
S.ids = {
	click  = K.IG_MAINMENU_OPTION or 852,
	tab    = K.IG_CHARACTER_INFO_TAB or 841,
	on     = K.IG_MAINMENU_OPTION_CHECKBOX_ON or 856,
	off    = K.IG_MAINMENU_OPTION_CHECKBOX_OFF or 857,
	select = K.U_CHAT_SCROLL_BUTTON or 1115,
	open   = K.IG_MAINMENU_OPEN or 850,
	close  = K.IG_MAINMENU_CLOSE or 851,
}

S.priority = { open = 6, close = 6, on = 5, off = 5, tab = 4, select = 3, click = 2 }

local pending                        -- the kind waiting to be played at the end of this frame

local function Flush()
	local kind = pending
	pending = nil
	local id = kind and S.ids[kind]
	if id and not S.muted and type(PlaySound) == "function" then pcall(PlaySound, id, "SFX") end
end

function S:Play(kind)
	kind = kind or "click"
	if self.muted or not self.ids[kind] then return end
	if pending then
		if (self.priority[kind] or 0) > (self.priority[pending] or 0) then pending = kind end
		return
	end
	pending = kind
	if C_Timer and C_Timer.After then C_Timer.After(0, Flush) else Flush() end
end

function S:SetMuted(muted) self.muted = muted and true or false end
function S:IsMuted() return self.muted == true end
