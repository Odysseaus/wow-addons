-- Dark Matter main window (P1): the approved mockup layout built from stock frame types and the theme layer.
-- Opens at screen centre, auto-saves its position, Reset window position lives in the Settings popover.
-- Left vertical tabs; each tab is a module registered with NS.RegisterTab (Tab_*.lua).
local _, NS = ...
local UI = NS.UI

NS.tabs = NS.tabs or {}
NS.tabOrder = NS.tabOrder or {}

function NS.RegisterTab(def)
  NS.tabs[def.id] = def
  NS.tabOrder[#NS.tabOrder + 1] = def.id
end

local frame
local W = {} -- window parts
NS.windowParts = W

---------------------------------------------------------------------------
-- position
---------------------------------------------------------------------------
local function SavePosition()
  if not frame or not NS.db then return end
  local point, _, relPoint, x, y = frame:GetPoint(1)
  NS.db.window.point = point or "CENTER"
  NS.db.window.relPoint = relPoint or "CENTER"
  NS.db.window.x = x or 0
  NS.db.window.y = y or 0
end

local function ApplyPosition()
  local w = NS.db and NS.db.window or {}
  frame:ClearAllPoints()
  frame:SetPoint(w.point or "CENTER", UIParent, w.relPoint or "CENTER", w.x or 0, w.y or 0)
end

function NS.ResetWindowPosition()
  if NS.db then
    NS.db.window.point, NS.db.window.relPoint, NS.db.window.x, NS.db.window.y = "CENTER", "CENTER", 0, 0
  end
  if frame then ApplyPosition() end
  NS.Print("window position reset to screen centre.")
end

-- Class-theme art space: the previewer's 880x680 css window (rim 38, header 46, footer 48). Its shell box
-- (38..842 x 84..594) is mapped onto ours (pad..w-pad x shellTop..footerTop), so the art frames our layout.
local function ArtMap()
  local m = NS.theme.m
  local sx = (m.w - 2 * m.pad) / 804
  local sy = (m.footerTop - m.shellTop) / 510
  return sx, sy, m.pad - 38 * sx, m.shellTop - 84 * sy
end
NS.ClassArtMap = ArtMap

-- Shrink (never enlarge) so the 880x680 window (or a class theme's larger frame art) fits small screens.
local function FitScale(f)
  local m = NS.theme.m
  local w, h = m.w, m.h
  if NS.theme.classArt then
    local sx, sy = ArtMap()
    w, h = 880 * sx, 680 * sy
  end
  local s = 1
  local uh, uw = NS.Num(UIParent:GetHeight()), NS.Num(UIParent:GetWidth())
  if uh and uh > 0 then s = math.min(s, uh * m.maxScreenFraction / h) end
  if uw and uw > 0 then s = math.min(s, uw * m.maxScreenFraction / w) end
  f:SetScale(math.max(0.5, s))
end

-- Class frame art (theme.classArt), all data-driven: backdrop behind the window, the frame bands under the
-- content, and the overlay bands, corner ornaments, crest and base plate on a no-mouse child above it.
local function BuildClassArt(f)
  local A = { under = {}, over = {}, orn = {} }
  local top = CreateFrame("Frame", nil, f)
  top:SetAllPoints(f)
  top:SetFrameLevel(f:GetFrameLevel() + 25)
  top:EnableMouse(false)
  A.top = top
  A.backdrop = f:CreateTexture(nil, "BACKGROUND", nil, -8)
  for i = 1, 6 do
    A.under[i] = f:CreateTexture(nil, "BORDER", nil, 0)
    A.over[i] = top:CreateTexture(nil, "ARTWORK", nil, 0)
  end
  for _, k in ipairs({ "tl", "tr", "bl", "br" }) do A.orn[k] = top:CreateTexture(nil, "OVERLAY", nil, 0) end
  A.crest = top:CreateTexture(nil, "OVERLAY", nil, 1)
  A.base = top:CreateTexture(nil, "OVERLAY", nil, 1)
  local all = { A.backdrop, A.crest, A.base }
  for i = 1, 6 do all[#all + 1] = A.under[i] all[#all + 1] = A.over[i] end
  for _, k in ipairs({ "tl", "tr", "bl", "br" }) do all[#all + 1] = A.orn[k] end
  A.all = all
  local function Place(tex, file, size, r, x, y, w, h)
    tex:SetTexture(file)
    tex:SetTexCoord((r[1] + 0.5) / size, (r[1] + r[3] - 0.5) / size, (r[2] + 0.5) / size, (r[2] + r[4] - 0.5) / size)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y)
    tex:SetSize(w, h)
    tex:Show()
  end
  function A.Apply()
    local ca = NS.theme.classArt
    if not ca then
      for _, t in ipairs(all) do t:Hide() end
      top:Hide()
      return
    end
    top:Show()
    local sx, sy, ax, ay = ArtMap()
    local k = (sx + sy) / 2
    local z, R, file = ca.size, ca.rects, ca.parts
    for i, b in ipairs(ca.bands) do
      local a, t = b[2], b[3]
      local x, y, w, h = ax + a[1] * sx, ay + a[2] * sy, a[3] * sx, a[4] * sy
      Place(A.under[i], ca.frame, z, t, x, y, w, h)
      Place(A.over[i], ca.over, z, t, x, y, w, h)
    end
    local aw, ah = 880 * sx, 680 * sy
    local o = ca.orn * k
    Place(A.orn.tl, file, z, R.orn_tl, ax, ay, o, o)
    Place(A.orn.tr, file, z, R.orn_tr, ax + aw - o, ay, o, o)
    Place(A.orn.bl, file, z, R.orn_bl, ax, ay + ah - o, o, o)
    Place(A.orn.br, file, z, R.orn_br, ax + aw - o, ay + ah - o, o, o)
    local cs = ca.crest[1] * k
    Place(A.crest, file, z, R.crest, ax + (440 + ca.crest[2]) * sx - cs / 2, ay + ca.crest[3] * sy, cs, cs)
    local bw, bh = ca.base[1] * k, ca.base[2] * k
    local bs = math.min(bw, bh)
    Place(A.base, file, z, R.base, ax + 440 * sx - bs / 2, ay + 642 * sy + (bh - bs) / 2, bs, bs)
    Place(A.backdrop, file, z, R.backdrop, ax - 44 * sx, ay - 26 * sy, aw + 88 * sx, ah + 86 * sy)
  end
  return A
end

---------------------------------------------------------------------------
-- tabs
---------------------------------------------------------------------------
function NS.ShowTab(id)
  if not frame then return end
  local def = NS.tabs[id] or NS.tabs[NS.tabOrder[1]]
  if not def then return end
  id = def.id
  local prevId = W.current
  if prevId and prevId ~= id then
    local prev = NS.tabs[prevId]
    if prev and prev.OnHide then pcall(prev.OnHide) end
  end
  for _, tid in ipairs(NS.tabOrder) do
    local t = NS.tabs[tid]
    if t.frame then t.frame:Hide() end
    if W.railTabs[tid] then W.railTabs[tid]:SetActive(tid == id) end
  end
  if not def.frame then def.frame = def.Build(W.body) end
  def.frame:Show()
  W.current = id
  if NS.db then NS.db.tab = id end
  if W.pop then W.pop:Hide() end
  if def.OnShow and frame:IsShown() then pcall(def.OnShow) end
end

function NS.SetStatus(text)
  if W.statusText then W.statusText:SetText(text or "") end
end

function NS.SetAllIcon(expanded)
  if W.allIcon then NS.SetPiece(W.allIcon, expanded and "coin_minus" or "coin_plus") end
end

---------------------------------------------------------------------------
-- build
---------------------------------------------------------------------------
local function EdgeLine(parent, point1, rel1, point2, rel2, w, h, r, g, b)
  local t = parent:CreateTexture(nil, "BORDER")
  t:SetPoint(point1, parent, rel1, 0, 0)
  t:SetPoint(point2, parent, rel2, 0, 0)
  if w then t:SetWidth(w) end
  if h then t:SetHeight(h) end
  t:SetColorTexture(r, g, b, 1)
  return t
end

local function SpecialFrame(name, add)
  -- Esc closes named frames through Blizzard's UISpecialFrames list (stock, taint-safe).
  if type(UISpecialFrames) ~= "table" then return end
  if add then
    for i = 1, #UISpecialFrames do if UISpecialFrames[i] == name then return end end
    tinsert(UISpecialFrames, name)
  else
    for i = #UISpecialFrames, 1, -1 do
      if UISpecialFrames[i] == name then table.remove(UISpecialFrames, i) end
    end
  end
end

NS.SpecialFrame = SpecialFrame
-- Esc target back to the main window (after a popup or the AG dropdown closes), unless another popup is open.
function NS.RestoreEscMain()
  local f, pop, catch = _G.DarkMatterFrame, _G.DarkMatterSettingsPop, _G.DarkMatterAGMenuCatcher
  if f and f:IsShown() and not (pop and pop:IsShown()) and not (catch and catch:IsShown()) then SpecialFrame("DarkMatterFrame", true) end
end

local function BuildSettings(f)
  local m = NS.theme.m
  -- Named so Esc can close it via UISpecialFrames while it is open (instead of the main window).
  local pop = CreateFrame("Frame", "DarkMatterSettingsPop", f)
  pop:SetSize(m.popW, m.popH)
  pop:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", m.popX, m.pad + m.popBottom)
  pop:SetFrameLevel(f:GetFrameLevel() + 30)
  pop:EnableMouse(true)
  local bg = pop:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(pop)
  local lines = {
    EdgeLine(pop, "TOPLEFT", "TOPLEFT", "TOPRIGHT", "TOPRIGHT", nil, 1, 1, 1, 1),
    EdgeLine(pop, "BOTTOMLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT", nil, 1, 1, 1, 1),
    EdgeLine(pop, "TOPLEFT", "TOPLEFT", "BOTTOMLEFT", "BOTTOMLEFT", 1, nil, 1, 1, 1),
    EdgeLine(pop, "TOPRIGHT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMRIGHT", 1, nil, 1, 1, 1),
  }
  NS.OnSkin(function()
    bg:SetColorTexture(NS.Color("popBg"))
    for _, l in ipairs(lines) do l:SetColorTexture(NS.Color("popBorder")) end
  end)
  local head = UI.Text(pop, "OVERLAY", 15, "listHead", "LEFT")
  head:SetPoint("TOPLEFT", pop, "TOPLEFT", 14, -12)
  head:SetText("Settings")
  local label = UI.Text(pop, "OVERLAY", 14, "popInk", "LEFT")
  label:SetPoint("TOPLEFT", pop, "TOPLEFT", 14, -44)
  label:SetText("Theme")
  local value = UI.Text(pop, "OVERLAY", 14, "gold", "RIGHT")
  value:SetPoint("TOPRIGHT", pop, "TOPRIGHT", -14, -44)
  -- Theme picker: one plain button per registered theme (WoW + the nine class themes), 2 columns.
  -- A click applies the theme live (NS.SetTheme re-skins every widget) and saves it in DarkMatterDB.theme.
  local pick = {}
  local bw, bh = math.floor((m.popW - 28 - 8) / 2), 24
  for i, id in ipairs(NS.themeOrder) do
    local def = NS.themes[id]
    local b = UI.Button(pop, def.name, bw, bh, "grey", 12)
    local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
    b:SetPoint("TOPLEFT", pop, "TOPLEFT", 14 + col * (bw + 8), -70 - row * (bh + 6))
    b:SetScript("OnClick", function() NS.SetTheme(id) end)
    b.themeId = id
    pick[#pick + 1] = b
  end
  W.themeButtons = pick
  NS.OnSkin(function()
    value:SetText(NS.theme.name)
    for _, b in ipairs(pick) do
      local on = b.themeId == NS.theme.id
      b:SetLook(on and "red" or "grey")
      if not on then b.text:SetTextColor(NS.Color("popInk")) end -- readable, not the disabled grey
    end
  end)
  local reset = UI.Button(pop, "Reset window position", m.popW - 28, m.fbtnH, "red", m.fbtnSize)
  reset:SetPoint("BOTTOMLEFT", pop, "BOTTOMLEFT", 14, 14)
  reset:SetScript("OnClick", function() NS.ResetWindowPosition() end)

  -- Click-outside: a catcher over the main window (above content, below the pop) and a
  -- full-screen catcher under the window so a click on the world also dismisses. Both are
  -- plain Frames with private OnMouseDown handlers; neither hooks Blizzard code.
  local catcher = CreateFrame("Frame", nil, f)
  catcher:SetAllPoints(f)
  catcher:SetFrameLevel(f:GetFrameLevel() + 20)
  catcher:EnableMouse(true)
  catcher:Hide()
  catcher:SetScript("OnMouseDown", function() pop:Hide() end)

  local world = CreateFrame("Frame", nil, UIParent)
  world:SetAllPoints(UIParent)
  world:SetFrameStrata("HIGH")
  world:SetFrameLevel(math.max(0, (f:GetFrameLevel() or 1) - 1))
  world:EnableMouse(true)
  world:Hide()
  world:SetScript("OnMouseDown", function() pop:Hide() end)

  pop:SetScript("OnShow", function()
    catcher:Show()
    world:Show()
    -- Esc closes the pop first; restore the main window entry when the pop hides.
    SpecialFrame("DarkMatterFrame", false)
    SpecialFrame("DarkMatterSettingsPop", true)
  end)
  pop:SetScript("OnHide", function()
    catcher:Hide()
    world:Hide()
    SpecialFrame("DarkMatterSettingsPop", false)
    NS.RestoreEscMain()
  end)

  pop:Hide()
  W.popCatcher = catcher
  W.popWorldCatcher = world
  return pop
end

local function Build()
  local m = NS.theme.m
  local f = CreateFrame("Frame", "DarkMatterFrame", UIParent)
  f:SetSize(m.w, m.h)
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() SavePosition() end)
  f:Hide()
  frame = f
  FitScale(f)

  -- dark slate behind everything, footer tint, thin line above the footer
  local slate = f:CreateTexture(nil, "BACKGROUND", nil, 0)
  slate:SetPoint("TOPLEFT", f, "TOPLEFT", m.pad, -m.pad)
  slate:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -m.pad, m.pad)
  NS.OnSkin(function()
    if NS.ApplySurface(slate, "shell") then return end
    slate:SetTexture(NS.theme.media.slate)
    slate:SetTexCoord(0, 1, 0, 1)
    local s = NS.Metric("slateShade")
    slate:SetVertexColor(s, s, s, 1)
  end)
  local tint = f:CreateTexture(nil, "BACKGROUND", nil, 1)
  tint:SetPoint("TOPLEFT", f, "TOPLEFT", m.pad, -m.footerTop)
  tint:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -m.pad, m.pad)
  local line = f:CreateTexture(nil, "BACKGROUND", nil, 2)
  line:SetPoint("TOPLEFT", f, "TOPLEFT", m.pad, -m.footerTop)
  line:SetPoint("TOPRIGHT", f, "TOPRIGHT", -m.pad, -m.footerTop)
  line:SetHeight(1)
  NS.OnSkin(function()
    tint:SetColorTexture(0.016, 0.016, 0.016, NS.Metric("footerTint"))
    line:SetColorTexture(0, 0, 0, 1)
  end)

  -- fine border frame
  local frameNine = UI.NineSlice(f, "frame", m.frameCorner, "BORDER", 2)

  -- title plate + title text (also a drag handle)
  local tb = CreateFrame("Frame", nil, f)
  tb:SetPoint("TOPLEFT", f, "TOPLEFT", m.titleX, -m.titleY)
  tb:SetSize(m.titleW, m.titleH)
  tb:EnableMouse(true)
  tb:RegisterForDrag("LeftButton")
  tb:SetScript("OnDragStart", function() f:StartMoving() end)
  tb:SetScript("OnDragStop", function() f:StopMovingOrSizing() SavePosition() end)
  local tbSlice = UI.ThreeSlice(tb, "title", m.titleH, "ARTWORK")
  local title = UI.Text(tb, "OVERLAY", m.titleSize, "title", "CENTER")
  title:SetPoint("CENTER", tb, "CENTER", 0, 0)
  NS.OnSkin(function() title:SetText(NS.theme.title or "Dark Matter") end)
  W.title = title

  -- rail with the vertical tabs
  local rail = CreateFrame("Frame", nil, f)
  rail:SetPoint("TOPLEFT", f, "TOPLEFT", m.railX, -m.railY)
  rail:SetSize(m.railW, m.railH)
  UI.Slate(rail, "railShade", "BACKGROUND", 3)
  UI.NineSlice(rail, "pane", m.railBorder, "BORDER", 3)
  W.rail = rail
  W.railTabs = {}
  for i, tid in ipairs(NS.tabOrder) do
    local def = NS.tabs[tid]
    local t = UI.RailTab(rail, def.name, NS.theme.glyphs[def.glyph])
    t:SetPoint("TOPLEFT", rail, "TOPLEFT", m.tabX - m.railX, -(m.tabY - m.railY) - (i - 1) * (m.tabH + m.tabGap))
    t:SetScript("OnClick", function() NS.ShowTab(tid) end)
    W.railTabs[tid] = t
  end

  -- body host: tabs build into this
  local body = CreateFrame("Frame", nil, f)
  body:SetPoint("TOPLEFT", f, "TOPLEFT", m.bodyX, -m.bodyY)
  body:SetSize(m.bodyW, m.bodyH)
  W.body = body

  -- quest-log style head row over the rail ("All" collapses/expands the quest list)
  local allBtn = CreateFrame("Button", nil, f)
  allBtn:SetPoint("TOPLEFT", f, "TOPLEFT", m.lheadAllX, -m.lheadAllY)
  allBtn:SetSize(m.lheadAllW, m.lheadAllH)
  UI.ThreeSlice(allBtn, "ptab_a", m.lheadAllH, "ARTWORK")
  local allGlow = UI.ThreeSlice(allBtn, "ptab_a", m.lheadAllH, "HIGHLIGHT")
  allGlow:SetBlend("ADD")
  allGlow:SetAlpha(0.16)
  W.allIcon = allBtn:CreateTexture(nil, "OVERLAY")
  W.allIcon:SetSize(14, 14)
  W.allIcon:SetPoint("LEFT", allBtn, "LEFT", 8, 0)
  NS.OnSkin(function() NS.SetPiece(W.allIcon, "coin_minus") end)
  local allText = UI.Text(allBtn, "OVERLAY", m.lheadSize, "lheadAll", "LEFT")
  allText:SetPoint("LEFT", W.allIcon, "RIGHT", 5, 0)
  allText:SetText("All")
  allBtn:SetScript("OnClick", function()
    local def = NS.tabs[W.current]
    if def and def.ToggleAll then def.ToggleAll() end
  end)
  local trk = CreateFrame("Frame", nil, f)
  trk:SetPoint("TOPLEFT", f, "TOPLEFT", m.lheadTrkX, -m.lheadTrkY)
  trk:SetSize(100, 16)
  local trkIcon = trk:CreateTexture(nil, "OVERLAY")
  trkIcon:SetSize(14, 14)
  trkIcon:SetPoint("LEFT", trk, "LEFT", 0, 0)
  NS.OnSkin(function() NS.SetPiece(trkIcon, "coin_target") end)
  local trkText = UI.Text(trk, "OVERLAY", m.lheadSize, "lheadInk", "LEFT")
  trkText:SetPoint("LEFT", trkIcon, "RIGHT", 5, 0)
  trkText:SetText("Track Quest")

  -- footer: Settings, status field, Share stats (later phase), Exit
  local settings = UI.Button(f, "Settings", m.fbtnW, m.fbtnH, "red", m.fbtnSize)
  settings:SetPoint("TOPLEFT", f, "TOPLEFT", m.fbtnLeft, -m.fbtnY)
  local status = CreateFrame("Frame", nil, f)
  status:SetPoint("TOPLEFT", f, "TOPLEFT", m.statusX, -m.statusY)
  status:SetSize(m.statusW, m.statusH)
  UI.ThreeSlice(status, "btn_field", m.statusH, "ARTWORK")
  W.statusText = UI.Text(status, "OVERLAY", m.statusSize, "status", "CENTER")
  W.statusText:SetPoint("CENTER", status, "CENTER", 0, 0)
  W.statusText:SetShadowOffset(0, 0)
  local share = UI.Button(f, "Share stats", m.fbtnW, m.fbtnH, "grey", m.fbtnSize)
  share:SetPoint("TOPLEFT", f, "TOPLEFT", m.shareX, -m.fbtnY)
  share:Disable()
  local exit = UI.Button(f, "Exit", m.fbtnW, m.fbtnH, "red", m.fbtnSize)
  exit:SetPoint("TOPLEFT", f, "TOPLEFT", m.exitX, -m.fbtnY)
  exit:SetScript("OnClick", function() f:Hide() end)

  -- settings popover (Theme, Reset window position)
  W.pop = BuildSettings(f)
  W.settingsBtn = settings
  -- Toggle: open shows the pop (and its catchers); close hides it. While the pop is open the
  -- window catcher sits above this button, so a second click hits the catcher and dismisses
  -- without re-opening — same end state as a plain toggle close.
  settings:SetScript("OnClick", function()
    if W.pop:IsShown() then W.pop:Hide() else W.pop:Show() end
  end)

  -- medal (above the border, like the mockup) and close button
  local medal = CreateFrame("Frame", nil, f)
  medal:SetSize(m.medalSize, m.medalSize)
  medal:SetPoint("TOPLEFT", f, "TOPLEFT", m.medalX, -m.medalY)
  medal:SetFrameLevel(f:GetFrameLevel() + 40)
  local medalTex = medal:CreateTexture(nil, "ARTWORK")
  medalTex:SetAllPoints(medal)
  NS.OnSkin(function() NS.SetPiece(medalTex, "medal") end)

  local close = CreateFrame("Button", nil, f)
  close:SetSize(m.closeSize, m.closeSize)
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(m.pad + m.closeRight), -(m.pad + m.closeTop))
  close:SetFrameLevel(f:GetFrameLevel() + 20)
  local closeTex = close:CreateTexture(nil, "ARTWORK")
  closeTex:SetAllPoints(close)
  local closeGlow = close:CreateTexture(nil, "HIGHLIGHT")
  closeGlow:SetAllPoints(close)
  closeGlow:SetBlendMode("ADD")
  closeGlow:SetAlpha(0.25)
  NS.OnSkin(function() NS.SetPiece(closeTex, "xbtn") NS.SetPiece(closeGlow, "xbtn") end)
  close:SetScript("OnClick", function() f:Hide() end)

  f:SetScript("OnShow", function()
    local def = NS.tabs[W.current]
    if def and def.OnShow then pcall(def.OnShow) end
  end)
  f:SetScript("OnHide", function()
    if W.pop then W.pop:Hide() end
    local def = NS.tabs[W.current]
    if def and def.OnHide then pcall(def.OnHide) end
  end)

  -- class themes: frame art on, WoW-only chrome (frame border, title plate, medal, footer tint, quest-log head row) off
  local art = BuildClassArt(f)
  W.classArt = art
  local wowOnly = { frameNine, tbSlice, tint, line, medal, allBtn, trk }
  NS.OnSkin(function()
    art.Apply()
    local ca = NS.theme.classArt
    for _, o in ipairs(wowOnly) do if ca then o:Hide() else o:Show() end end
    title:ClearAllPoints()
    if ca then
      local sx, sy, ax, ay = ArtMap()
      NS.SetFont(title, math.floor(ca.titleSize * 0.8 + 0.5), "")
      title:SetPoint("CENTER", f, "TOPLEFT", ax + 440 * sx, -(ay + (61 + ca.titleDy) * sy))
      if f.SetClampRectInsets then f:SetClampRectInsets(ax, ax + 880 * sx - m.w, -ay, m.h - (ay + 680 * sy)) end
    else
      NS.SetFont(title, m.titleSize, "")
      title:SetPoint("CENTER", tb, "CENTER", 0, 0)
      if f.SetClampRectInsets then f:SetClampRectInsets(0, 0, 0, 0) end
    end
    FitScale(f)
    -- footer row + close button: the previewer's class layout (inset from the frame rim) or the WoW positions
    settings:ClearAllPoints() status:ClearAllPoints() share:ClearAllPoints() exit:ClearAllPoints() close:ClearAllPoints()
    if ca then
      local sx, sy, ax, ay = ArtMap()
      local ft = ca.footer
      local x, cy = ax + ft.pad * sx, ay + 618 * sy
      local widths = { 90, ft.cols[2], 90, 90 }
      for i, b in ipairs({ settings, status, share, exit }) do
        b:SetWidth(widths[i] * sx)
        b:SetPoint("LEFT", f, "TOPLEFT", x, -cy)
        x = x + (ft.cols[i] + ft.gap) * sx
      end
      close:SetPoint("TOPRIGHT", f, "TOPLEFT", ax + (880 - ca.close[1]) * sx, -(ay + ca.close[2] * sy))
      close:SetFrameLevel(f:GetFrameLevel() + 27)
    else
      settings:SetWidth(m.fbtnW) settings:SetPoint("TOPLEFT", f, "TOPLEFT", m.fbtnLeft, -m.fbtnY)
      status:SetWidth(m.statusW) status:SetPoint("TOPLEFT", f, "TOPLEFT", m.statusX, -m.statusY)
      share:SetWidth(m.fbtnW) share:SetPoint("TOPLEFT", f, "TOPLEFT", m.shareX, -m.fbtnY)
      exit:SetWidth(m.fbtnW) exit:SetPoint("TOPLEFT", f, "TOPLEFT", m.exitX, -m.fbtnY)
      close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(m.pad + m.closeRight), -(m.pad + m.closeTop))
      close:SetFrameLevel(f:GetFrameLevel() + 20)
    end
  end)

  -- ESC closes it, the stock way (plain table insert; Blizzard reads it through securecall).
  if type(UISpecialFrames) == "table" then tinsert(UISpecialFrames, "DarkMatterFrame") end
  return f
end

function NS.GetWindow()
  if not frame then
    -- Build under pcall: if anything in the build errors, never leave a half-built window behind.
    local ok, err = pcall(function()
      Build()
      ApplyPosition()
      NS.SetStatus("Dark Matter " .. NS.version)
      NS.ShowTab(NS.db and NS.db.tab or "quests")
    end)
    if not ok then
      if frame then frame:Hide() end
      frame = nil
      NS.buildError = tostring(err)
      if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff5555Dark Matter: the window could not be built:|r " .. NS.buildError)
      end
      return nil
    end
  end
  return frame
end

function NS.RefreshWindow()
  if not frame then return end
  local def = NS.tabs[W.current]
  if def and def.Refresh then pcall(def.Refresh) end
end

function NS.ToggleWindow(show)
  local f = NS.GetWindow()
  if not f then return end
  if show == nil then show = not f:IsShown() end
  if show then f:Show() else f:Hide() end
end
