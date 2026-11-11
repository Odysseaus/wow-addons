--------------------------------------------------------------------------------
-- Valhalla's look (v0.4.2): the one place every button, tick box, radio, text box, stepper, dropdown,
-- pager, tab, panel, scroll bar and window frame of Valhalla gets its art, in two looks:
--   Profession (the default): WoW Forever's own profession window, its bronze "-c60" art: the red and
--     gold buttons, the profession tick box and arrows, the page box, the metal frame over the
--     profession background.
--   Norse: heavy bronze frames with corner brackets over dark iron, iron and bronze controls, shield tabs,
--     Morpheus for titles only (small print stays in the game's font).
-- ValhallaDB.ui.look; Investments > Settings > Look switches it, live (every skinned widget is kept in a
-- weak list and painted again).
-- Rules: textures of our own on our own widgets (no Blizzard template is inherited here, none of the
-- game's frames is written on, no legacy dropdown menu); secure buttons are never skinned; art the client
-- lacks falls back to its standard name (without -c60), then to a plain colour, so nothing breaks; and no
-- size is ever asked here (v0.4.0.2: asking a new frame its size lays it out and fires OnSizeChanged):
-- a skin is given its widget's size, or takes it from the widget's own OnSizeChanged, which repaints
-- only that widget's own textures.
--------------------------------------------------------------------------------

local _, ns = ...
local Style = {}
ns.Style = Style

local GOLD, WHITE, GREY = { 1, 0.82, 0 }, { 1, 1, 1 }, { 0.5, 0.48, 0.45 }
local WHITE8 = "Interface\\Buttons\\WHITE8X8"
local ROCK = "Interface\\FrameGeneral\\UI-Background-Rock"
Style.GOLD, Style.WHITE = GOLD, WHITE

Style.DEFAULT = "profession"
Style.ORDER = { "profession", "norse" }
Style.THEMES = {
	profession = {
		key = "profession", label = "Profession",
		text = GOLD, hover = WHITE, selected = WHITE, dim = { 0.72, 0.63, 0.45 }, highlight = { 1, 0.85, 0.45, 0.16 },
		lit = { glow = { 1, 0.78, 0.3, 0.2 }, edge = { 1, 0.82, 0.35, 0.95 } },   -- (a toggle's chosen one)
		button = { left = "128-redbutton-left-c60", mid = "_128-redbutton-center-c60", right = "128-redbutton-right-c60",
			leftW = 114, rightW = 292, artH = 128, color = { 0.42, 0.07, 0.05, 1 } },
		square = { minus = "128-redbutton-minus-c60", plus = "128-redbutton-plus-c60",
			delete = "128-redbutton-delete-c60", close = "128-redbutton-exit-c60" },
		arrow = { left = "profession-button-arrow-left-c60", right = "profession-button-arrow-right-c60", size = 20 },
		check = { box = "profession-checkbox-c60", mark = "checkmark-minimal", pad = 3 },
		input = { box = "profession-page-box-c60", artW = 43, artH = 18, cap = 6, color = { 0.03, 0.03, 0.03, 0.92 } },
		dropdown = { arrow = "common-dropdown-a-button-c60", hover = "common-dropdown-a-button-hover-c60",
			open = "common-dropdown-a-button-open-c60" },
		menu = { atlas = "common-dropdown-bg-c60", alpha = 0.925 },
		tab = { left = "uiframe-tab-left-c60", mid = "_uiframe-tab-center-c60", right = "uiframe-tab-right-c60", capW = 35, artH = 36,
			onLeft = "uiframe-activetab-left", onMid = "_uiframe-activetab-center", onRight = "uiframe-activetab-right" },
		side = { up = "common-button-square-gray-up-c60", down = "common-button-square-gray-down-c60" },
		nav = { bar = "profession-tab-c60", glow = "profession-tab-glow-c60" },
		frame = { layout = "ButtonFrameTemplateNoPortrait", bg = "profession-background-template2-c60", shade = 0.2 },
		content = { bg = "profession-background-template2-c60", shade = 0.12 },
		panel = { fill = { 0.02, 0.015, 0.01 }, k = 0.6, edge = { 0.6, 0.45, 0.22 } },
		tile = { 0.08, 0.06, 0.04, 0.92 },
		scroll = { thumb = "minimal-scrollbar-thumb-middle-c60", up = "minimal-scrollbar-small-arrow-top-c60",
			down = "minimal-scrollbar-small-arrow-bottom-c60" },
	},
	norse = {
		key = "norse", label = "Norse",
		text = GOLD, hover = { 1, 0.93, 0.62 }, selected = { 1, 0.95, 0.72 }, dim = { 0.7, 0.62, 0.45 }, highlight = { 0.85, 0.6, 0.3, 0.18 },
		iron = { top = { 0.25, 0.22, 0.19 }, bottom = { 0.10, 0.09, 0.08 } },
		edge = { 0.69, 0.5, 0.25 }, edgeOn = { 1, 0.8, 0.35 }, glow = { 1, 0.72, 0.25, 0.22 },
		arrow = { left = "common-icon-backarrow", right = "common-icon-forwardarrow", size = 13 },
		check = { mark = "checkmark-minimal", tint = { 1, 0.85, 0.4 } },
		input = { fill = { 0.05, 0.045, 0.04, 0.95 } },
		dropdown = { arrow = "common-icon-forwardarrow", size = 11 },
		menu = { fill = { 0.07, 0.06, 0.05, 0.97 } },
		frame = { border = "heavybronze-frame-basic-c60", corner = 0.3, cornerPx = 22, bg = "heavybronze-frame-background-c60",
			bracket = "heavybronze-horz-cornerbracket-%s-c60", bracketPx = 30, shade = 0.12 },
		content = { bg = "heavybronze-frame-background-c60", shade = 0.08 },
		panel = { fill = { 0.07, 0.06, 0.05 }, k = 0.95, edge = { 0.5, 0.36, 0.18 } },
		tile = { 0.11, 0.1, 0.09, 0.95 },
		titleFont = "Fonts\\MORPHEUS.TTF",
	},
}

--------------------------------------------------------------------------------
-- The look chosen (ValhallaDB.ui.look) and switching it
--------------------------------------------------------------------------------

function Style.Look()
	local db = _G.ValhallaDB
	local v = type(db) == "table" and type(db.ui) == "table" and db.ui.look or nil
	return Style.THEMES[v] and v or Style.DEFAULT
end

function Style.Theme() return Style.THEMES[Style.Look()] end

Style.listeners = {}
function Style.OnLook(fn) Style.listeners[#Style.listeners + 1] = fn end

-- the other look, at once: every widget painted again (fonts and the game's own parts: see the note)
function Style.SetLook(v)
	if not Style.THEMES[v] then return false end
	if type(_G.ValhallaDB) ~= "table" then _G.ValhallaDB = {} end
	if type(_G.ValhallaDB.ui) ~= "table" then _G.ValhallaDB.ui = {} end
	_G.ValhallaDB.ui.look = v
	Style.Reskin()
	for _, fn in ipairs(Style.listeners) do pcall(fn, v) end
	return true
end

--------------------------------------------------------------------------------
-- Art: the client's atlas, else its standard name, else a plain colour (Style.missing says which)
--------------------------------------------------------------------------------

Style.missing = {}       -- [asked] = the standard name used instead, or false (a plain colour)
local known = {}
local function Info(name)
	if not name then return nil end
	local c = known[name]
	if c == nil then
		local ok, info = false, nil
		if C_Texture and C_Texture.GetAtlasInfo then ok, info = pcall(C_Texture.GetAtlasInfo, name) end
		c = (ok and type(info) == "table") and info or false
		known[name] = c
	end
	return c or nil
end
function Style.ForgetArt() known = {} Style.missing = {} end   -- (tests)

function Style.Atlas(name)
	if not name then return nil end
	if Info(name) then return name end
	local std = (name:gsub("%-c60", ""))
	if std ~= name and Info(std) then Style.missing[name] = std return std end
	Style.missing[name] = false
	return nil
end

-- name's pressed / disabled / hover / open art ("x-c60" -> "x-pressed-c60")
local function Variant(name, what)
	if not name then return nil end
	if name:find("%-c60$") then return (name:gsub("%-c60$", "-" .. what .. "-c60")) end
	return name .. "-" .. what
end
Style.Variant = Variant

local function Color(tex, c)
	tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
end

-- tex in name's art (else its standard name, else colour c); true when it's art
local function Art(tex, name, c)
	local a = Style.Atlas(name)
	if tex.SetVertexColor then tex:SetVertexColor(1, 1, 1, 1) end
	if a then tex:SetAtlas(a) return true end
	Color(tex, c or { 0.1, 0.08, 0.06, 1 })
	return false
end
Style.Art = Art

-- tex in a part of name's art (fractions of it: x0, x1, y0, y1; y1 < y0 turns it upside down)
local function Sub(tex, name, x0, x1, y0, y1)
	local a = Style.Atlas(name)
	local info = a and Info(a)
	local file = info and (info.file or info.filename)
	if not (file and info.leftTexCoord and info.rightTexCoord and info.topTexCoord and info.bottomTexCoord) then return false end
	tex:SetTexture(file)
	local l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
	tex:SetTexCoord(l + (r - l) * x0, l + (r - l) * x1, t + (b - t) * y0, t + (b - t) * y1)
	if tex.SetVertexColor then tex:SetVertexColor(1, 1, 1, 1) end
	return true
end
Style.Sub = Sub

local function Gradient(tex, top, bottom)
	tex:SetTexture(WHITE8)
	local ok = false
	if tex.SetGradient and _G.CreateColor then
		ok = pcall(tex.SetGradient, tex, "VERTICAL", _G.CreateColor(bottom[1], bottom[2], bottom[3], 1), _G.CreateColor(top[1], top[2], top[3], 1))
	end
	if not ok then Color(tex, { (top[1] + bottom[1]) / 2, (top[2] + bottom[2]) / 2, (top[3] + bottom[3]) / 2, 1 }) end
end

--------------------------------------------------------------------------------
-- The skinned widgets: w.vh = { kind, as, parts, state, w, h, ... }; Apply paints one in the look shown
--------------------------------------------------------------------------------

Style.all = setmetatable({}, { __mode = "k" })
Style.refused = 0
local APPLY = {}

local function Apply(w)
	local vh = w and w.vh
	if not vh then return end
	vh.used = {}
	local th = Style.Theme()
	local fn = APPLY[vh.kind]
	if fn then fn(w, vh, th) end
	for k, p in pairs(vh.parts) do if not vh.used[k] then p:Hide() end end
	vh.look = th.key
end
Style.Apply = Apply

-- what went wrong painting (v0.4.2.1: kept, the last few, for /valhalla look check)
Style.errors = {}
local function Failed(w, err)
	local e = Style.errors
	e[#e + 1] = { look = Style.Look(), kind = w and w.vh and (w.vh.as or w.vh.kind) or "?", err = tostring(err) }
	while #e > 10 do table.remove(e, 1) end
end

function Style.Reskin()
	local n = 0
	for w in pairs(Style.all) do
		local ok, err = pcall(Apply, w)
		if ok then n = n + 1 else Failed(w, err) end
	end
	return n
end

-- the look painted again on root's widgets only (v0.4.2.1: the AH's side window, each time the AH opens)
function Style.ReskinUnder(root)
	local n = 0
	if not root then return n end
	for w in pairs(Style.all) do
		local f, hops = w, 0
		while f and f ~= root and hops < 30 do f = f.GetParent and f:GetParent() or nil hops = hops + 1 end
		if f == root then
			local ok, err = pcall(Apply, w)
			if ok then n = n + 1 else Failed(w, err) end
		end
	end
	return n
end

-- /valhalla look check: the look, how many widgets wear it, framed panels, art that's missing, errors; printed and
-- saved (ValhallaDB.ui.lookCheck) so it can be read after a /reload. extra: other modules' lines (name = value)
function Style.CheckLook(extra)
	local look = Style.Look()
	local th = Style.Theme()
	local d = { look = look, at = time and time() or 0, widgets = 0, framed = 0, bronze = 0, wrongLook = 0, errors = {}, missing = {} }
	for w in pairs(Style.all) do
		local vh = w.vh or {}
		d.widgets = d.widgets + 1
		if vh.look and vh.look ~= look then d.wrongLook = d.wrongLook + 1 end
		if vh.framed then
			d.framed = d.framed + 1
			local b = vh.parts and vh.parts.n1   -- (the bronze border's first piece)
			if b and b.IsShown and b:IsShown() then d.bronze = d.bronze + 1 end
		end
	end
	for _, e in ipairs(Style.errors) do d.errors[#d.errors + 1] = ("%s %s: %s"):format(e.look, e.kind, e.err) end
	for k, v in pairs(Style.missing) do d.missing[#d.missing + 1] = k .. " -> " .. tostring(v) end
	table.sort(d.missing)
	if type(extra) == "table" then for k, v in pairs(extra) do d[k] = v end end
	d.lines = {
		("Look: %s (%s). Widgets: %d; framed panels: %d, in bronze: %d; not yet repainted: %d."):format(th.label, look, d.widgets, d.framed, d.bronze, d.wrongLook),
		("Errors: %d. Missing art: %d%s"):format(#d.errors, #d.missing, #d.missing > 0 and (" (" .. table.concat(d.missing, ", ", 1, math.min(4, #d.missing)) .. ")") or ""),
	}
	for _, e in ipairs(d.errors) do d.lines[#d.lines + 1] = "  " .. e end
	if type(extra) == "table" and extra.line then d.lines[#d.lines + 1] = extra.line end
	if type(_G.ValhallaDB) ~= "table" then _G.ValhallaDB = {} end
	if type(_G.ValhallaDB.ui) ~= "table" then _G.ValhallaDB.ui = {} end
	_G.ValhallaDB.ui.lookCheck = d
	return d
end

-- one of w's own textures, by name (made once, shown while this look uses it)
local function Part(w, key, layer, sub)
	local vh = w.vh
	local p = vh.parts[key]
	if not p then
		p = w:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
		vh.parts[key] = p
	end
	vh.used[key] = true
	p:ClearAllPoints()
	if p.SetBlendMode then p:SetBlendMode("BLEND") end
	if p.SetRotation then p:SetRotation(0) end
	p:Show()
	return p
end

local function Secure(w)
	if w.IsProtected then
		local ok, p = pcall(w.IsProtected, w)
		if ok and p then return true end
	end
	return w.GetAttribute and (w:GetAttribute("type") ~= nil or w:GetAttribute("clickbutton") ~= nil) or false
end
Style.Secure = Secure

local function Hook(w, script, fn) if w.HookScript then pcall(w.HookScript, w, script, fn) end end

local function Hooks(w, mouse)
	Hook(w, "OnSizeChanged", function(self, width, height)
		local vh = self.vh
		if vh and width and height and width > 0 and height > 0 and (vh.w ~= width or vh.h ~= height) then
			vh.w, vh.h = width, height
			Apply(self)     -- (its own textures only: nothing laid out)
		end
	end)
	if not mouse then return end
	local function Set(k, v)
		return function(self) local vh = self.vh if vh and vh.state[k] ~= v then vh.state[k] = v Apply(self) end end
	end
	Hook(w, "OnEnter", Set("hover", true))
	Hook(w, "OnLeave", function(self) local vh = self.vh if vh then vh.state.hover, vh.state.down = nil, nil Apply(self) end end)
	Hook(w, "OnMouseDown", Set("down", true))
	Hook(w, "OnMouseUp", Set("down", nil))
	Hook(w, "OnDisable", Set("off", true))
	Hook(w, "OnEnable", Set("off", nil))
end

-- w skinned as kind (opts: as, w, h, pos, ...); a secure button is left as it is
local function Track(w, kind, opts, mouse)
	if not w then return w end
	if Secure(w) then Style.refused = Style.refused + 1 return w end
	local vh = w.vh
	if not vh then
		vh = { parts = {}, used = {}, state = {} }
		w.vh = vh
		Style.all[w] = true
		Hooks(w, mouse)
	end
	vh.kind = kind
	if opts then for k, v in pairs(opts) do vh[k] = v end end
	Apply(w)
	return w
end
Style.Track = Track

-- lit (the current tab, the chosen mode, the page shown)
function Style.Select(w, on)
	local vh = w and w.vh
	if not vh then return w end
	on = on and true or nil
	local first = not vh.toggle
	vh.toggle = true   -- (one of a set: the chosen one bright, the others dimmed)
	if vh.selected ~= on or first then vh.selected = on Apply(w) end
	return w
end

--------------------------------------------------------------------------------
-- Shared painting
--------------------------------------------------------------------------------

local function FontOf(w)
	if w.text then return w.text end
	if w.GetFontString then return w:GetFontString() end
end

local function TextColor(w, vh, th)
	local fs = FontOf(w)
	if not fs or vh.keepText then return end
	local c = th.text
	if vh.state.off then c = GREY
	elseif vh.selected then c = th.selected
	elseif vh.state.hover then c = th.hover
	elseif vh.toggle and (vh.as or "button") == "button" then c = th.dim or c end
	fs:SetTextColor(c[1], c[2], c[3])
end

local function ShowText(w, shown)
	local fs = FontOf(w)
	if fs and fs.SetAlpha then fs:SetAlpha(shown and 1 or 0) end
end

-- the game's own art of a template button / box (UIPanelButtonTemplate, InputBoxTemplate): hidden under ours
local function HideTemplate(w)
	for _, k in ipairs({ "Left", "Middle", "Right", "Mid" }) do
		local t = rawget(w, k)
		if type(t) == "table" and t.SetAlpha then t:SetAlpha(0) end
	end
	local hl = w.GetHighlightTexture and w:GetHighlightTexture()
	if hl and hl.SetAlpha then hl:SetAlpha(0) end
end

-- a 1 px (or n) edge in colour c, inset i
local function Edge(w, c, i, n, layer)
	i, n = i or 0, n or 1
	local t = Part(w, "eT", layer or "BORDER", 1) t:SetPoint("TOPLEFT", i, -i) t:SetPoint("TOPRIGHT", -i, -i) t:SetHeight(n) Color(t, c)
	local b = Part(w, "eB", layer or "BORDER", 1) b:SetPoint("BOTTOMLEFT", i, i) b:SetPoint("BOTTOMRIGHT", -i, i) b:SetHeight(n) Color(b, c)
	local l = Part(w, "eL", layer or "BORDER", 1) l:SetPoint("TOPLEFT", i, -i) l:SetPoint("BOTTOMLEFT", i, i) l:SetWidth(n) Color(l, c)
	local r = Part(w, "eR", layer or "BORDER", 1) r:SetPoint("TOPRIGHT", -i, -i) r:SetPoint("BOTTOMRIGHT", -i, i) r:SetWidth(n) Color(r, c)
end

local function Highlight(w, th, inset)
	local hl = Part(w, "hl", "HIGHLIGHT")
	hl:SetPoint("TOPLEFT", inset or 1, -(inset or 1))
	hl:SetPoint("BOTTOMRIGHT", -(inset or 1), inset or 1)
	Color(hl, th.highlight)
	if hl.SetBlendMode then hl:SetBlendMode("ADD") end
end

-- Norse: dark iron, a bronze edge (gold while lit), a bevel's light line
local function Iron(w, vh, th, lit, inset, dim)
	inset = inset or 0
	local bg = Part(w, "iron", "BACKGROUND", -7)
	bg:SetPoint("TOPLEFT", inset, -inset)
	bg:SetPoint("BOTTOMRIGHT", -inset, inset)
	local top, bottom = th.iron.top, th.iron.bottom
	if vh.state.down then top, bottom = bottom, top end
	if dim then top, bottom = { top[1] * 0.7, top[2] * 0.7, top[3] * 0.7 }, { bottom[1] * 0.7, bottom[2] * 0.7, bottom[3] * 0.7 } end
	Gradient(bg, top, bottom)
	local bevel = Part(w, "bevel", "BORDER", 2)
	bevel:SetPoint("TOPLEFT", inset + 2, -inset - 2)
	bevel:SetPoint("TOPRIGHT", -inset - 2, -inset - 2)
	bevel:SetHeight(1)
	Color(bevel, { 1, 0.9, 0.7, 0.12 })
	local e = (lit or vh.state.hover) and th.edgeOn or th.edge
	local k = (dim and not vh.state.hover) and 0.6 or 1
	Edge(w, { e[1] * k, e[2] * k, e[3] * k, 1 }, inset, 1)
	if lit then
		local glow = Part(w, "glow", "BORDER", 3)
		glow:SetPoint("TOPLEFT", inset + 1, -inset - 1)
		glow:SetPoint("BOTTOMRIGHT", -inset - 1, inset + 1)
		Color(glow, th.glow)
		if glow.SetBlendMode then glow:SetBlendMode("ADD") end
	end
end

-- three pieces across w (caps at their art's width for the height, squeezed on a narrow widget)
local function Three(w, vh, l, m, r, lw, rw, color, flip)
	local width, height = vh.w or 100, vh.h or 22
	if lw + rw > width then local k = width / (lw + rw) lw, rw = lw * k, rw * k end
	local L = Part(w, "3L", "BACKGROUND", -6)
	local R = Part(w, "3R", "BACKGROUND", -6)
	L:SetPoint("TOPLEFT") L:SetPoint("BOTTOMLEFT") L:SetWidth(lw)
	R:SetPoint("TOPRIGHT") R:SetPoint("BOTTOMRIGHT") R:SetWidth(rw)
	local y0, y1 = 0, 1
	if flip then y0, y1 = 1, 0 end
	if not (flip and Sub(L, l, 0, 1, y0, y1)) then Art(L, l, color) end
	if not (flip and Sub(R, r, 0, 1, y0, y1)) then Art(R, r, color) end
	if width - lw - rw > 0.5 then
		local M = Part(w, "3M", "BACKGROUND", -6)
		M:SetPoint("TOPLEFT", L, "TOPRIGHT") M:SetPoint("BOTTOMRIGHT", R, "BOTTOMLEFT")
		if not (flip and Sub(M, m, 0, 1, y0, y1)) then Art(M, m, color) end
	end
	return height
end

-- one atlas cut in three across (its caps cap px of artW at artH), for a box of any width
local function Box(w, vh, name, artW, artH, cap, color, insetX, insetY)
	local width, height = vh.w or 100, vh.h or 22
	insetX, insetY = insetX or 0, insetY or 0
	local c = cap * (height + 2 * insetY) / artH
	local L = Part(w, "bL", "BACKGROUND", -6)
	local R = Part(w, "bR", "BACKGROUND", -6)
	local M = Part(w, "bM", "BACKGROUND", -6)
	L:SetPoint("TOPLEFT", -insetX, insetY) L:SetPoint("BOTTOMLEFT", -insetX, -insetY) L:SetWidth(c)
	R:SetPoint("TOPRIGHT", insetX, insetY) R:SetPoint("BOTTOMRIGHT", insetX, -insetY) R:SetWidth(c)
	M:SetPoint("TOPLEFT", L, "TOPRIGHT") M:SetPoint("BOTTOMRIGHT", R, "BOTTOMLEFT")
	local f = cap / artW
	if Sub(L, name, 0, f, 0, 1) and Sub(R, name, 1 - f, 1, 0, 1) and Sub(M, name, f, 1 - f, 0, 1) then return true end
	-- (no part of it to cut: the whole art stretched, else the colour)
	vh.used.bL, vh.used.bR = nil, nil
	M:ClearAllPoints()
	M:SetPoint("TOPLEFT", -insetX, insetY)
	M:SetPoint("BOTTOMRIGHT", insetX, -insetY)
	return Art(M, name, color)
end

--------------------------------------------------------------------------------
-- Buttons: as = button (the red one), minus / plus / delete / close (square), dec / inc (a stepper's
-- arrows), first / prev / next / last (a pager's), item (a menu's line), nav (a page menu's), tab,
-- side (a side icon tab), dropdown
--------------------------------------------------------------------------------

local SQUARE = { minus = true, plus = true, delete = true, close = true }
local ARROW = { dec = "left", inc = "right", prev = "left", next = "right", first = "left", last = "right" }

-- a pager's first / last (v0.4.2.1): the one arrow box, the same as < and >, with a thin gold stop bar at its far
-- side (|< and >|: no second arrow over the first)
local function ArrowArt(w, vh, th, dir, stop)
	local a = th.arrow
	local name = a[dir]
	local size = math.min(a.size, (vh.h or 20), (vh.w or 20))
	local prof = th.key == "profession"
	local t = Part(w, "a1", "ARTWORK", 1)
	t:SetSize(size, size)
	-- (Norse's bare chevron moves aside a little for its bar; Profession's arrow is a whole box: it stays put)
	local dx = (stop and not prof) and (dir == "left" and 2 or -2) or 0
	t:SetPoint("CENTER", dx, 0)
	local art = (vh.state.down and prof) and Variant(name, "pressed") or name
	if not Art(t, art, { 1, 0.82, 0, 1 }) and art ~= name then Art(t, name, { 1, 0.82, 0, 1 }) end
	if th.key == "norse" and t.SetVertexColor then t:SetVertexColor(1, 0.85, 0.45, 1) end
	if t.SetDesaturated then t:SetDesaturated(vh.state.off and true or false) end
	if stop then
		local bar = Part(w, "stop", "ARTWORK", 3)
		local bh = math.max(6, math.floor(size * (prof and 0.45 or 0.85) + 0.5))
		bar:SetSize(2, bh)
		local bx = prof and 5 or 6
		bar:SetPoint("CENTER", dir == "left" and -bx or bx, 0)
		local c = vh.state.off and { 0.5, 0.48, 0.45, 0.9 } or (prof and { 1, 0.86, 0.3, 1 } or { 1, 0.85, 0.45, 1 })
		Color(bar, c)
	end
end

APPLY.button = function(w, vh, th)
	local as = vh.as or "button"
	if vh.template then HideTemplate(w) end
	local prof = th.key == "profession"
	local lit = vh.selected
	if as == "item" then
		Highlight(w, th, 0)
		ShowText(w, true)
		TextColor(w, vh, th)
		return
	end
	if as == "tab" then
		local h = vh.h or 28
		if prof then
			local t = th.tab
			local on = lit
			Three(w, vh, on and t.onLeft or t.left, on and t.onMid or t.mid, on and t.onRight or t.right,
				t.capW * h / t.artH, t.capW * h / t.artH, { 0.12, 0.1, 0.08, 1 }, vh.pos == "top")
			Highlight(w, th, 4)
		else
			Iron(w, vh, th, lit, nil, not lit)   -- (the current one: a gold edge and glow; the others dimmer)
		end
		ShowText(w, true)
		return   -- (the window's tabs colour their own labels: Tabs.lua)
	end
	if as == "side" then
		if prof then
			local bg = Part(w, "side", "BACKGROUND", -6)
			bg:SetAllPoints()
			Art(bg, lit and th.side.down or th.side.up, { 0.15, 0.13, 0.1, 1 })
			if lit then
				local g = Part(w, "glow", "BORDER", 3)
				g:SetPoint("TOPLEFT", 2, -2) g:SetPoint("BOTTOMRIGHT", -2, 2)
				Color(g, { 1, 0.8, 0.3, 0.22 })
				if g.SetBlendMode then g:SetBlendMode("ADD") end
			end
			Highlight(w, th, 3)
		else
			Iron(w, vh, th, lit)
		end
		return
	end
	if as == "nav" then
		if prof then
			local bar = Part(w, "nav", "BACKGROUND", -6)
			bar:SetAllPoints()
			Art(bar, th.nav.bar, { 0.12, 0.1, 0.08, 0.9 })
			if lit then
				local g = Part(w, "glow", "BORDER", 3)
				g:SetAllPoints()
				if not Art(g, th.nav.glow, { 1, 0.8, 0.3, 0.2 }) then Color(g, { 1, 0.8, 0.3, 0.2 }) end
				if g.SetBlendMode then g:SetBlendMode("ADD") end
			end
			Highlight(w, th, 2)
		else
			Iron(w, vh, th, lit)
		end
		ShowText(w, true)
		TextColor(w, vh, th)
		return
	end
	if as == "dropdown" then
		local open = vh.menu and vh.menu.IsShown and vh.menu:IsShown()
		local h = vh.h or 20
		if prof then
			Box(w, vh, th.input.box, th.input.artW, th.input.artH, th.input.cap, th.input.color)
			local a = Part(w, "arrow", "ARTWORK", 1)
			a:SetSize(h + 2, h + 2)
			a:SetPoint("RIGHT", 2, 0)
			local name = open and th.dropdown.open or (vh.state.hover and th.dropdown.hover) or th.dropdown.arrow
			if not Art(a, name) then Art(a, th.dropdown.arrow, { 1, 0.82, 0, 1 }) end
		else
			Iron(w, vh, th, open)
			local a = Part(w, "arrow", "ARTWORK", 1)
			a:SetSize(th.dropdown.size, th.dropdown.size)
			a:SetPoint("RIGHT", -6, 0)
			Art(a, th.dropdown.arrow, { 1, 0.82, 0, 1 })
			if a.SetVertexColor then a:SetVertexColor(1, 0.85, 0.45, 1) end
			if a.SetRotation then pcall(a.SetRotation, a, -math.pi / 2) end   -- (pointing down)
		end
		local fs = FontOf(w)
		if fs and not vh.placed then
			vh.placed = true
			fs:ClearAllPoints()
			fs:SetPoint("LEFT", 8, 0)
			fs:SetPoint("RIGHT", -(h + 4), 0)
			if fs.SetJustifyH then fs:SetJustifyH("LEFT") end
			if fs.SetWordWrap then fs:SetWordWrap(false) end
		end
		ShowText(w, true)
		TextColor(w, vh, th)
		return
	end
	if SQUARE[as] then
		if prof then
			local t = Part(w, "sq", "ARTWORK", -1)
			local s = math.min(vh.w or 20, vh.h or 20) + 2
			t:SetSize(s, s)
			t:SetPoint("CENTER")
			local name = th.square[as]
			local art = vh.state.off and Variant(name, "disabled") or vh.state.down and Variant(name, "pressed") or name
			if not Art(t, art) then Art(t, name, th.button.color) end
			ShowText(w, Style.Atlas(name) == nil)
		else
			Iron(w, vh, th, lit)
			ShowText(w, true)
		end
		TextColor(w, vh, th)
		return
	end
	if ARROW[as] then
		if not prof then Iron(w, vh, th, lit) end
		ArrowArt(w, vh, th, ARROW[as], as == "first" or as == "last")
		ShowText(w, false)
		return
	end
	-- the button
	if prof then
		local b = th.button
		local h = vh.h or 22
		-- a toggle's chosen one: the bright art with a gold glow and edge; the others: the pressed (darker) art
		local dim = vh.toggle and not lit
		local sfx = vh.state.off and "disabled" or (vh.state.down or dim) and "pressed" or nil
		local l, m, r = b.left, b.mid, b.right
		if sfx then
			local vl = Variant(l, sfx)
			if Style.Atlas(vl) then l, m, r = vl, Variant(m, sfx), Variant(r, sfx) end
		end
		Three(w, vh, l, m, r, b.leftW * h / b.artH, b.rightW * h / b.artH, b.color)
		if dim then
			for _, k in ipairs({ "3L", "3M", "3R" }) do local t = vh.parts[k] if t and vh.used[k] and t.SetVertexColor then t:SetVertexColor(0.78, 0.74, 0.7, 1) end end
		end
		if lit then
			local g = Part(w, "glow", "BORDER", 3)
			g:SetPoint("TOPLEFT", 3, -3) g:SetPoint("BOTTOMRIGHT", -3, 3)
			Color(g, th.lit.glow)
			if g.SetBlendMode then g:SetBlendMode("ADD") end
			Edge(w, th.lit.edge, 1, 1)
		end
		Highlight(w, th, 3)
	else
		Iron(w, vh, th, lit, nil, vh.toggle and not lit)
	end
	ShowText(w, true)
	TextColor(w, vh, th)
end

local AUTO = { ["-"] = "minus", ["+"] = "plus", ["x"] = "delete", ["X"] = "delete", ["<<"] = "first", ["<"] = "prev", [">"] = "next", [">>"] = "last" }
function Style.AutoKind(label) return AUTO[label] or "button" end

-- a button of ours (a plain Button; its backdrop, if any, cleared): as, its width and height
function Style.Button(b, as, width, height, opts)
	if not b or Secure(b) then if b then Style.refused = Style.refused + 1 end return b end
	if b.SetBackdrop and b.vh == nil then b:SetBackdrop(nil) end
	local o = { as = as or (b.vh and b.vh.as) or "button" }
	if width then o.w = width end
	if height then o.h = height end
	if opts then for k, v in pairs(opts) do o[k] = v end end
	return Track(b, "button", o, true)
end

-- the game's UIPanelButtonTemplate (its own art hidden under ours: Map windows' buttons)
function Style.UIButton(parent, name)
	local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
	return Style.Button(b, "button", nil, 22, { template = true })
end

-- a stepper: its - and + as the look's arrows, its box (if any) a text box
function Style.Stepper(dec, inc, box, bw, bh)
	if dec then Style.Button(dec, "dec") end
	if inc then Style.Button(inc, "inc") end
	if box then Style.Input(box, bw, bh) end
	return dec, inc, box
end

-- a dropdown's button and its menu (the button lit while the menu is open)
-- open dropdowns close on a click anywhere else (v0.4.2.1): one listener for the game's GLOBAL_MOUSE_DOWN (an event:
-- no hook, nothing of the game's touched), registered only while a menu is open; a press on the menu or on its own
-- button is left alone (the button's click opens and closes it as before)
Style.openMenus = {}
local closer
local function Outside(f) return not (f and f.IsMouseOver and f:IsMouseOver()) end
local function CloseOutside()
	for menu, b in pairs(Style.openMenus) do
		if not (menu.IsShown and menu:IsShown()) then
			Style.openMenus[menu] = nil
		elseif Outside(menu) and Outside(b) then
			menu:Hide()
			Style.openMenus[menu] = nil
		end
	end
	if not next(Style.openMenus) and closer then closer:UnregisterEvent("GLOBAL_MOUSE_DOWN") end
end
Style.CloseOutside = CloseOutside
local function Watch(menu, b)
	if not closer then
		closer = CreateFrame("Frame")
		closer:SetScript("OnEvent", CloseOutside)
	end
	Style.openMenus[menu] = b
	closer:RegisterEvent("GLOBAL_MOUSE_DOWN")
end

function Style.Dropdown(b, menu, width, height)
	Style.Button(b, "dropdown", width, height, { menu = menu })
	if menu then
		Style.Menu(menu)
		Hook(menu, "OnShow", function() Apply(b) Watch(menu, b) end)
		Hook(menu, "OnHide", function() Apply(b) Style.openMenus[menu] = nil end)
	end
	return b
end

-- the window's tab in its place (bottom, top, side) at its size
function Style.Tab(b, pos, width, height)
	return Style.Button(b, pos == "side" and "side" or "tab", width, height, { pos = pos })
end

--------------------------------------------------------------------------------
-- Tick boxes (V.Check's: a Button with .tick; or a CheckButton) and text boxes
--------------------------------------------------------------------------------

APPLY.check = function(w, vh, th)
	local prof = th.key == "profession"
	if prof then
		local box = Part(w, "box", "BACKGROUND", -6)
		local p = th.check.pad
		box:SetPoint("TOPLEFT", -p, p)
		box:SetPoint("BOTTOMRIGHT", p, -p)
		if not Art(box, th.check.box) then
			vh.used.box = nil
			Edge(w, { 0.6, 0.45, 0.22, 1 }, 0, 1)
			local f = Part(w, "fill", "BACKGROUND", -6) f:SetAllPoints() Color(f, { 0.03, 0.03, 0.03, 0.9 })
		end
	else
		local f = Part(w, "fill", "BACKGROUND", -6)
		f:SetAllPoints()
		Gradient(f, th.iron.bottom, th.iron.top)
		local e = vh.state.hover and th.edgeOn or th.edge
		Edge(w, { e[1], e[2], e[3], 1 }, 0, 1)
	end
	local mark = w.tick or vh.mark
	if mark then
		Art(mark, th.check.mark, { 1, 0.82, 0, 1 })
		if th.check.tint and mark.SetVertexColor then mark:SetVertexColor(th.check.tint[1], th.check.tint[2], th.check.tint[3], 1) end
	end
	if vh.checkButton then
		local hl = Part(w, "hl", "HIGHLIGHT")
		hl:SetAllPoints()
		Color(hl, th.highlight)
		if hl.SetBlendMode then hl:SetBlendMode("ADD") end
	end
	if w.label and w.label.SetTextColor and not vh.keepText then
		local c = vh.state.hover and th.hover or { 0.92, 0.88, 0.8 }
		w.label:SetTextColor(c[1], c[2], c[3])
	end
end

function Style.Check(cb, size)
	if not cb or Secure(cb) then return cb end
	if cb.SetBackdrop and cb.vh == nil then cb:SetBackdrop(nil) end
	local o = { keepText = true }
	if size then o.w, o.h = size, size end
	-- a CheckButton: its checked art ours (the game shows and hides it)
	if not cb.tick and cb.SetCheckedTexture then
		local mark = cb.vhMark or cb:CreateTexture(nil, "ARTWORK")
		cb.vhMark = mark
		mark:SetAllPoints()
		pcall(cb.SetCheckedTexture, cb, mark)
		-- (its own box art, the template's or the minimal one, hidden under ours)
		for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }) do
			local t = cb[get] and cb[get](cb)
			if t and t ~= mark and t.SetAlpha then t:SetAlpha(0) end
		end
		o.mark, o.checkButton = mark, true
	end
	return Track(cb, "check", o, true)
end

APPLY.input = function(w, vh, th)
	if vh.template then HideTemplate(w) end
	local ix, iy = vh.template and 6 or 0, vh.template and 2 or 0
	if th.key == "profession" then
		Box(w, vh, th.input.box, th.input.artW, th.input.artH, th.input.cap, th.input.color, ix, iy)
	else
		local f = Part(w, "fill", "BACKGROUND", -6)
		f:SetPoint("TOPLEFT", -ix, iy) f:SetPoint("BOTTOMRIGHT", ix, -iy)
		Color(f, th.input.fill)
		local e = (vh.state.hover or (w.HasFocus and w:HasFocus())) and th.edgeOn or th.edge
		local c = { e[1], e[2], e[3], 1 }
		local t = Part(w, "eT", "BORDER", 1) t:SetPoint("TOPLEFT", -ix, iy) t:SetPoint("TOPRIGHT", ix, iy) t:SetHeight(1) Color(t, c)
		local b = Part(w, "eB", "BORDER", 1) b:SetPoint("BOTTOMLEFT", -ix, -iy) b:SetPoint("BOTTOMRIGHT", ix, -iy) b:SetHeight(1) Color(b, c)
		local l = Part(w, "eL", "BORDER", 1) l:SetPoint("TOPLEFT", -ix, iy) l:SetPoint("BOTTOMLEFT", -ix, -iy) l:SetWidth(1) Color(l, c)
		local r = Part(w, "eR", "BORDER", 1) r:SetPoint("TOPRIGHT", ix, iy) r:SetPoint("BOTTOMRIGHT", ix, -iy) r:SetWidth(1) Color(r, c)
	end
end

function Style.Input(e, width, height, opts)
	if not e then return e end
	if e.SetBackdrop and e.vh == nil then e:SetBackdrop(nil) end
	local o = { w = width, h = height or 22 }
	if opts then for k, v in pairs(opts) do o[k] = v end end
	Track(e, "input", o, false)
	Hook(e, "OnEditFocusGained", function(self) Apply(self) end)
	Hook(e, "OnEditFocusLost", function(self) Apply(self) end)
	return e
end

-- the game's InputBoxTemplate (Map windows' boxes)
function Style.UIInput(parent, name)
	local e = CreateFrame("EditBox", name, parent, "InputBoxTemplate")
	return Style.Input(e, nil, 20, { template = true })
end

--------------------------------------------------------------------------------
-- Panels, menus, the content's background, window frames, titles, tiles, scroll bars
--------------------------------------------------------------------------------

local Bronze   -- (below: Norse's heavy bronze border)
APPLY.panel = function(w, vh, th)
	if not w.SetBackdrop then return end
	local p = th.panel
	w:SetBackdrop({ bgFile = WHITE8, edgeFile = WHITE8, edgeSize = 1 })
	local a = math.min(1, (vh.alpha or 0.95) * p.k / 0.95 + (vh.subtle and 0 or 0.05))
	w:SetBackdropColor(p.fill[1], p.fill[2], p.fill[3], math.min(1, a))
	local e = p.edge
	local k = vh.subtle and 0.5 or 1
	w:SetBackdropBorderColor(e[1] * k, e[2] * k, e[3] * k, 1)
	if vh.framed and th.key ~= "profession" then Bronze(w, vh, th) end   -- (Norse: the big panels in heavy bronze, bracketed)
end

-- a dark panel with an edge (T.Skin, Look:Panel); subtle: a row's fainter edge; framed: a page's or the
-- menu's panel (Norse frames it in heavy bronze with corner brackets)
function Style.Panel(f, alpha, subtle, framed)
	if not f or not f.SetBackdrop or Secure(f) then return f end
	return Track(f, "panel", { alpha = alpha or 0.95, subtle = subtle and true or nil, framed = framed and true or nil }, false)
end

APPLY.menu = function(w, vh, th)
	if w.SetBackdrop then w:SetBackdrop(nil) end
	if th.key == "profession" then
		local bg = Part(w, "menu", "BACKGROUND", -7)
		bg:SetPoint("TOPLEFT", -10, 3)
		bg:SetPoint("BOTTOMRIGHT", 10, -3)
		if Art(bg, th.menu.atlas) then
			if bg.SetAlpha then bg:SetAlpha(th.menu.alpha) end
		else
			bg:ClearAllPoints() bg:SetAllPoints()
			Color(bg, { 0.06, 0.06, 0.07, 0.97 })
			Edge(w, { 0.66, 0.49, 0.28, 1 }, 0, 1)
		end
	else
		local bg = Part(w, "menu", "BACKGROUND", -7)
		bg:SetAllPoints()
		if bg.SetAlpha then bg:SetAlpha(1) end
		Color(bg, th.menu.fill)
		Edge(w, { th.edge[1], th.edge[2], th.edge[3], 1 }, 0, 1)
	end
end

-- a dropdown's list; returns the room to leave inside it (left, top, right, bottom), the same in both looks
function Style.Menu(f)
	Track(f, "menu", nil, false)
	return 8, 8, 8, 15
end

local function Background(w, vh, name, shade, inset)
	local bg = Part(w, "bg", "BACKGROUND", -8)
	if inset then bg:SetPoint("TOPLEFT", inset[1], inset[2]) bg:SetPoint("BOTTOMRIGHT", inset[3], inset[4]) else bg:SetAllPoints() end
	if bg.SetHorizTile then bg:SetHorizTile(false) bg:SetVertTile(false) end
	-- (a strip, the band over the map's breadcrumb: the art's top edge, not all of it squashed)
	if not ((vh.strip and Sub(bg, name, 0, 1, 0, 0.07)) or Art(bg, name)) then
		-- (no such art: the map window's rock, else the colour)
		if bg:SetTexture(ROCK, "REPEAT", "REPEAT") == false then Color(bg, { 0.1, 0.09, 0.08, 1 }) end
		if bg.SetHorizTile then bg:SetHorizTile(true) bg:SetVertTile(true) end
		shade = 0.45
	end
	local s = Part(w, "shade", "BACKGROUND", -7)
	s:SetAllPoints(bg)
	Color(s, { 0, 0, 0, shade or 0 })
end

APPLY.content = function(w, vh, th)
	Background(w, vh, th.content.bg, th.content.shade)
end

-- the Investments host's background (F2: the profession window's; Norse: heavy bronze's)
function Style.Content(f, strip)
	return Track(f, "content", { strip = strip and true or nil }, false)
end

-- Norse's heavy bronze border round w (a 9-slice of one piece of art; else plain bronze edges)
function Bronze(w, vh, th)
	local fr = th.frame
	local c, s = fr.corner, fr.cornerPx
	local cut = { 0, c, 1 - c, 1 }
	local names = { "n1", "n2", "n3", "n4", "n5", "n6", "n7", "n8" }
	local spots = { { 1, 1 }, { 2, 1 }, { 3, 1 }, { 1, 2 }, { 3, 2 }, { 1, 3 }, { 2, 3 }, { 3, 3 } }
	local ok = Style.Atlas(fr.border) ~= nil
	for i, sp in ipairs(spots) do
		local t = Part(w, names[i], "BORDER", -2)
		local x, y = sp[1], sp[2]
		-- corners s x s; edges between them
		if x == 1 then t:SetPoint("LEFT", w, "LEFT", -4, 0) end
		if x == 3 then t:SetPoint("RIGHT", w, "RIGHT", 4, 0) end
		if y == 1 then t:SetPoint("TOP", w, "TOP", 0, 4) end
		if y == 3 then t:SetPoint("BOTTOM", w, "BOTTOM", 0, -4) end
		if x == 2 then t:SetPoint("LEFT", w, "LEFT", s - 4, 0) t:SetPoint("RIGHT", w, "RIGHT", -s + 4, 0) else t:SetWidth(s) end
		if y == 2 then t:SetPoint("TOP", w, "TOP", 0, -s + 4) t:SetPoint("BOTTOM", w, "BOTTOM", 0, s - 4) else t:SetHeight(s) end
		if not (ok and Sub(t, fr.border, cut[x], cut[x + 1], cut[y], cut[y + 1])) then
			Color(t, (x == 2 and y == 2) and { 0, 0, 0, 0 } or { th.edge[1], th.edge[2], th.edge[3], 1 })
			if not ok then
				-- (plain edges: thin)
				if x == 2 then t:SetHeight(3) elseif y == 2 then t:SetWidth(3) else t:SetSize(3, 3) end
			end
		end
	end
	for _, k in ipairs({ "tl", "tr", "bl", "br" }) do
		local t = Part(w, "k" .. k, "OVERLAY", 6)
		t:SetSize(fr.bracketPx, fr.bracketPx)
		local v = k:sub(1, 1) == "t" and "TOP" or "BOTTOM"
		local h = k:sub(2, 2) == "l" and "LEFT" or "RIGHT"
		t:SetPoint(v .. h, w, v .. h, h == "LEFT" and -8 or 8, v == "TOP" and 8 or -8)
		if not Art(t, fr.bracket:format(k)) then vh.used["k" .. k] = nil end
	end
end

APPLY.frame = function(w, vh, th)
	local prof = th.key == "profession"
	if vh.nine then vh.nine:SetShown(prof) end
	if prof then
		if vh.top and vh.top > 0 then
			Background(w, vh, th.frame.bg, th.frame.shade, { 6, -21, -2, 3 })
		else
			Background(w, vh, th.frame.bg, th.frame.shade)
			Edge(w, { 0.66, 0.49, 0.28, 1 }, 0, 1)
		end
	else
		Background(w, vh, th.frame.bg, th.frame.shade, { 4, -4, -4, 4 })
		Bronze(w, vh, th)
		if vh.top and vh.top > 0 then
			local band = Part(w, "band", "BACKGROUND", -6)
			band:SetPoint("TOPLEFT", 4, -4) band:SetPoint("TOPRIGHT", -4, -4) band:SetHeight(vh.top - 2)
			Color(band, { 0, 0, 0, 0.35 })
			local rule = Part(w, "rule", "BORDER", 0)
			rule:SetPoint("TOPLEFT", 14, -vh.top) rule:SetPoint("TOPRIGHT", -14, -vh.top) rule:SetHeight(1)
			Color(rule, { th.edge[1], th.edge[2], th.edge[3], 0.8 })
		end
	end
end

-- a window's frame (Look:Window, the map menu): Profession: the map window's own metal nine-slice
-- (Blizzard's layout without the portrait, made once) over the profession background; Norse: heavy bronze.
-- Returns the title bar's height (21; 0 on a client without the layout)
function Style.Frame(f)
	if not f then return 0 end
	if f.vh and f.vh.kind == "frame" then return f.vh.top or 0 end
	local top, nine = 0, nil
	local util = _G.NineSliceUtil
	local layout = util and util.GetLayout and util.GetLayout(Style.THEMES.profession.frame.layout) and Style.THEMES.profession.frame.layout
	if layout then
		local ok, n = pcall(CreateFrame, "Frame", nil, f, "NineSlicePanelTemplate")
		if ok and n and pcall(util.ApplyLayoutByName, n, layout) then
			n:SetAllPoints()
			if n.SetFrameLevel and f.GetFrameLevel then n:SetFrameLevel(f:GetFrameLevel()) end
			nine, top = n, 21
		end
	end
	Track(f, "frame", { nine = nine, top = top }, false)
	return top
end

-- a title: Morpheus in Norse (its size a little up), the game's font in Profession
APPLY.title = function(fs, vh, th)
	if th.titleFont then
		if not (fs.SetFont and fs:SetFont(th.titleFont, (vh.size or 13) + 2, "")) then return end
	elseif vh.font and vh.font[1] then
		fs:SetFont(vh.font[1], vh.font[2] or vh.size or 13, vh.font[3] or "")
	elseif fs.SetFont then
		fs:SetFont(_G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", vh.size or 13, "")
	end
end

function Style.Title(fs, size)
	if not fs then return fs end
	if fs.vh then if size then fs.vh.size = size end Apply(fs) return fs end
	local font = fs.GetFont and { fs:GetFont() } or nil
	fs.vh = { parts = {}, used = {}, state = {}, kind = "title", size = size or (font and font[2]) or 13, font = font }
	Style.all[fs] = true
	Apply(fs)
	return fs
end

APPLY.tile = function(w, vh, th)
	if w.SetBackdropColor then local c = th.tile w:SetBackdropColor(c[1], c[2], c[3], c[4]) end
end
function Style.Tile(b) return Track(b, "tile", nil, false) end

-- a scroll frame's bar (UIPanelScrollFrameTemplate on our own frames): the thumb and arrows
APPLY.scroll = function(w, vh, th)
	local sb = rawget(w, "ScrollBar")
	if type(sb) ~= "table" then return end
	local thumb = rawget(sb, "ThumbTexture") or (sb.GetThumbTexture and sb:GetThumbTexture())
	local prof = th.key == "profession"
	if thumb then
		if prof then
			if Art(thumb, Style.THEMES.profession.scroll.thumb) then thumb:SetWidth(8) end
		else
			Color(thumb, { th.edge[1], th.edge[2], th.edge[3], 0.9 })
			thumb:SetWidth(6)
		end
	end
	local sc = Style.THEMES.profession.scroll
	for _, pair in ipairs({ { rawget(sb, "ScrollUpButton"), sc.up }, { rawget(sb, "ScrollDownButton"), sc.down } }) do
		local b, name = pair[1], pair[2]
		if b then
			for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture" }) do
				local t = b[get] and b[get](b)
				if t then
					Art(t, name)
					if not prof and t.SetVertexColor then t:SetVertexColor(1, 0.8, 0.45, 1) end
					if get == "GetDisabledTexture" and t.SetDesaturated then t:SetDesaturated(true) end
				end
			end
		end
	end
end
function Style.ScrollBar(sf) if sf then pcall(Track, sf, "scroll", nil, false) end return sf end
function Style.UIScroll(parent, name)
	local sf = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
	return Style.ScrollBar(sf)
end

-- what the look's art comes to on this client (/valhalla look check; the tests)
function Style.ArtReport()
	local out = {}
	for _, key in ipairs(Style.ORDER) do
		local function Walk(t)
			for _, v in pairs(t) do
				if type(v) == "string" and v:find("%-") and not v:find("\\") and not v:find("%%") then
					local a = Style.Atlas(v)
					if a ~= v then out[#out + 1] = v .. " -> " .. tostring(a or "colour") end
				elseif type(v) == "table" then Walk(v) end
			end
		end
		Walk(Style.THEMES[key])
	end
	table.sort(out)
	return out
end
