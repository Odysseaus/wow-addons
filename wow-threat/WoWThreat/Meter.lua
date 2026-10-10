-- WoWThreat meter: rows, slides, pop, fire, and listen-only Edit Mode hooks.
local _, NS = ...

local POLL = 0.2
local HEADER = 18
local PAD = 6
local TEX = "Interface\\AddOns\\WoWThreat\\Textures\\"

local main, title, rows = nil, nil, {}
local editModeOpen, editModeBound, dragging = false, false, false
local pollAcc = 0

local function DB()
  if not NS.db and NS.MigrateDB then NS.MigrateDB() end
  return NS.db or {}
end

local SNAP = 8
local currentLayout = nil

local function Note(msg)
  if NS.Print then NS.Print(msg) end
end

local function InCombat()
  return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

-- Save as TOPLEFT of UIParent BOTTOMLEFT, snapped to an 8 px screen grid
-- and clamped so the frame stays fully on screen.
local function SnapAndSave()
  if not main then return end
  local lay = NS.Layout(currentLayout)
  local s = main:GetEffectiveScale() or 1
  local ps = UIParent:GetEffectiveScale() or 1
  local left, top = main:GetLeft(), main:GetTop()
  if not left or not top then return end
  -- frame units -> screen px
  local sx, sy = left * s, top * s
  sx = math.floor(sx / SNAP + 0.5) * SNAP
  sy = math.floor(sy / SNAP + 0.5) * SNAP
  local sw = (UIParent:GetWidth() or 0) * ps
  local sh = (UIParent:GetHeight() or 0) * ps
  local fw = (main:GetWidth() or 0) * s
  local fh = (main:GetHeight() or 0) * s
  if sw > 0 then
    if sx + fw > sw then sx = math.floor((sw - fw) / SNAP) * SNAP end
    if sx < 0 then sx = 0 end
  end
  if sh > 0 then
    if sy > sh then sy = math.floor(sh / SNAP) * SNAP end
    if sy - fh < 0 then sy = math.ceil(fh / SNAP) * SNAP end
  end
  lay.point = "TOPLEFT"
  lay.relativePoint = "BOTTOMLEFT"
  lay.xOfs = sx / s
  lay.yOfs = sy / s
  main:ClearAllPoints()
  main:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", lay.xOfs, lay.yOfs)
end

-- ---------------------------------------------------------------- Edit Mode
-- Listen-only integration (PLAN 3). Never RegisterSystemFrame or call
-- secure EditMode methods; only read GetActiveLayoutInfo via pcall.
local editHighlight

function NS.IsEditMode() return editModeOpen end
function NS.MainFrame() return main end

local function DragAllowed()
  return editModeOpen and not InCombat()
end

-- Blue selection drawn from plain textures (no atlas on this client).
local function CreateEditHighlight(target)
  local sel = CreateFrame("Button", "WoWThreatSelection", target)
  sel:SetPoint("TOPLEFT", target, "TOPLEFT", -4, 4)
  sel:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 4, -4)
  sel:SetFrameLevel((target:GetFrameLevel() or 1) + 30)
  sel.fill = sel:CreateTexture(nil, "BACKGROUND")
  sel.fill:SetAllPoints()
  sel.fill:SetColorTexture(0.18, 0.5, 1, 0.18)
  sel.edges = {}
  local spec = {
    { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
    { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false },
  }
  local i
  for i = 1, 4 do
    local t = sel:CreateTexture(nil, "BORDER")
    t:SetColorTexture(0.3, 0.68, 1, 0.95)
    t:SetPoint(spec[i][1], sel, spec[i][1], 0, 0)
    t:SetPoint(spec[i][2], sel, spec[i][2], 0, 0)
    if spec[i][3] then t:SetHeight(2) else t:SetWidth(2) end
    sel.edges[i] = t
  end
  sel.hover = sel:CreateTexture(nil, "ARTWORK")
  sel.hover:SetAllPoints()
  sel.hover:SetColorTexture(0.45, 0.75, 1, 0.12)
  sel.hover:Hide()
  sel.label = sel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  sel.label:SetPoint("CENTER", sel, "TOP", 0, 0)
  sel.label:SetText("WoW Threat")
  if sel.SetIgnoreParentAlpha then sel:SetIgnoreParentAlpha(true) end

  sel:EnableMouse(true)
  sel:RegisterForClicks("LeftButtonUp")
  sel:RegisterForDrag("LeftButton")
  sel:SetScript("OnEnter", function() sel.hover:Show() end)
  sel:SetScript("OnLeave", function() sel.hover:Hide() end)
  sel:SetScript("OnDragStart", function()
    if not DragAllowed() then
      if InCombat() then Note("can't move the meter in combat.") end
      return
    end
    dragging = true
    main:SetMovable(true)
    main:StartMoving()
  end)
  sel:SetScript("OnDragStop", function()
    if not dragging then return end
    dragging = false
    main:StopMovingOrSizing()
    SnapAndSave()
    if NS.AnchorDialog then NS.AnchorDialog() end
  end)
  sel:SetScript("OnClick", function()
    if dragging then return end
    if InCombat() then
      Note("settings are unavailable in combat.")
      return
    end
    if NS.ToggleDialog then NS.ToggleDialog() end
  end)
  sel:Hide()
  return sel
end

local function ApplyDrag()
  if not main then return end
  main:EnableMouse(false)
  if editHighlight then
    if editModeOpen then editHighlight:Show() else editHighlight:Hide() end
  end
  if not editModeOpen then
    if dragging then
      dragging = false
      main:StopMovingOrSizing()
      SnapAndSave()
    end
    main:SetMovable(false)
    if NS.HideDialog then NS.HideDialog() end
  end
end

-- Reapply when the active Edit Mode layout changed.
local function CheckLayout()
  local name = NS.ActiveLayoutName()
  if name ~= currentLayout and NS.ApplyLayout then NS.ApplyLayout() end
end
NS.CheckLayout = CheckLayout

local function BindEditModeSignals()
  if editModeBound or not main then return end
  if not EventRegistry or type(EventRegistry.RegisterCallback) ~= "function" then return end
  EventRegistry:RegisterCallback("EditMode.Enter", function()
    editModeOpen = true
    CheckLayout()
    ApplyDrag()
    if NS.Refresh then NS.Refresh() end
  end, main)
  EventRegistry:RegisterCallback("EditMode.Exit", function()
    editModeOpen = false
    CheckLayout()
    ApplyDrag()
    if NS.Refresh then NS.Refresh() end
  end, main)
  -- Post-hook only (hooksecurefunc does not taint the manager).
  local em = EditModeManagerFrame
  if em and type(hooksecurefunc) == "function" then
    local names = { "SelectLayout", "UpdateLayoutInfo" }
    local i
    for i = 1, #names do
      if type(em[names[i]]) == "function" then
        pcall(hooksecurefunc, em, names[i], function() CheckLayout() end)
      end
    end
  end
  editModeBound = true
end

-- ---------------------------------------------------------------- rows
local ELLIPSIS = "\226\128\166" -- UTF-8 "…"
local COL_GAP = 12
local FADE_TIME = 1.0
local SAFETY_POLL = 0.5
local TEST_TICK = 0.1

local state = {}      -- eased values per member key (GUID or name)
local rowByKey = {}   -- live row frame per member key
local pool = {}       -- released row frames
local animFrame = nil
local EASE_RATE = 8
local MOVE_RATE = 12
local SNAP_PX = 0.5
local FIRE_TEX = TEX .. "Fire_Flipbook"
local FIRE_COLS, FIRE_FRAMES = 4, 16
local fadeT = nil     -- seconds left in the leave-combat fade, or nil
local lastShown = 0

-- Pop (PLAN 6)
local POP_HOLD = 0.4
local POP_COOLDOWN = 1.5
local POP_GLOW = 1.2
local POP_FLASH = 0.3
local leaderKey, candKey, candSince = nil, nil, 0
local lastPopAt = -100
local suppressPop = true

local function Now()
  return type(GetTime) == "function" and (GetTime() or 0) or 0
end

local function CreateRow()
  local r = CreateFrame("Frame", nil, main)
  -- Opaque backing so a sliding row covers the one it passes.
  r.solid = r:CreateTexture(nil, "BACKGROUND", nil, -1)
  r.solid:SetPoint("TOPLEFT", r, "TOPLEFT", -1, 1)
  r.solid:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 1, 0)
  r.solid:SetColorTexture(0.07, 0.055, 0.06, 1)
  r.hl = r:CreateTexture(nil, "BACKGROUND", nil, 1)
  r.hl:SetAllPoints()
  r.hl:SetColorTexture(0.91, 0.77, 0.42, 0.12)
  r.hl:Hide()
  r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.name:SetPoint("TOPLEFT", r, "TOPLEFT", 1, 0)
  r.name:SetJustifyH("LEFT")
  if r.name.SetWordWrap then r.name:SetWordWrap(false) end
  r.value = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.value:SetPoint("TOPRIGHT", r, "TOPRIGHT", -1, 0)
  r.value:SetJustifyH("RIGHT")

  r.bar = CreateFrame("Frame", nil, r)
  r.bar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 2)
  r.bar:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 2)
  r.bg = r.bar:CreateTexture(nil, "BACKGROUND")
  r.bg:SetAllPoints()
  r.bg:SetColorTexture(0.04, 0.035, 0.04, 1)
  r.fill = r.bar:CreateTexture(nil, "ARTWORK")
  r.fill:SetPoint("TOPLEFT", r.bar, "TOPLEFT", 1, -1)
  r.fill:SetPoint("BOTTOMLEFT", r.bar, "BOTTOMLEFT", 1, 1)
  r.fill:SetTexture(TEX .. "BarFill")
  r.shine = r.bar:CreateTexture(nil, "OVERLAY")
  r.shine:SetAllPoints(r.fill)
  r.shine:SetTexture(TEX .. "BarShine")
  r.shine:SetBlendMode("ADD")
  r.shine:SetAlpha(0.35)
  r.bevel = r.bar:CreateTexture(nil, "OVERLAY", nil, 1)
  r.bevel:SetAllPoints()
  r.bevel:SetTexture(TEX .. "BarBevel")
  r.border = r.bar:CreateTexture(nil, "OVERLAY", nil, 2)
  r.border:SetPoint("TOPLEFT", r.bar, "TOPLEFT", -1, 1)
  r.border:SetPoint("BOTTOMRIGHT", r.bar, "BOTTOMRIGHT", 1, -1)
  r.border:SetColorTexture(0.91, 0.77, 0.42, 0.25)
  r.border:Hide()

  -- Fire (PLAN 7): clip frame sized to the fill width, fire anchored at the
  -- bottom with ADD blend. Created once per row and reused.
  r.fireClip = CreateFrame("Frame", nil, r.bar)
  r.fireClip:SetPoint("TOPLEFT", r.bar, "TOPLEFT", 1, -1)
  r.fireClip:SetPoint("BOTTOMLEFT", r.bar, "BOTTOMLEFT", 1, 1)
  r.fireClip:SetWidth(1)
  if r.fireClip.SetClipsChildren then r.fireClip:SetClipsChildren(true) end
  r.fireClip:SetFrameLevel(r.bar:GetFrameLevel() + 1)
  r.fire = r.fireClip:CreateTexture(nil, "ARTWORK")
  r.fire:SetTexture(FIRE_TEX)
  r.fire:SetBlendMode("ADD")
  r.fire:SetPoint("BOTTOMLEFT", r.fireClip, "BOTTOMLEFT", 0, 0)
  r.fire:SetPoint("BOTTOMRIGHT", r.fireClip, "BOTTOMRIGHT", 0, 0)
  r.fire:SetHeight(1)
  r.fireDur = 1.0
  r.fireFrame = 0
  r.fireAcc = 0
  if NS.FlipBookOK ~= false and r.fire.CreateAnimationGroup then
    local ok = pcall(function()
      local ag = r.fire:CreateAnimationGroup()
      local fb = ag:CreateAnimation("FlipBook")
      fb:SetFlipBookRows(4)
      fb:SetFlipBookColumns(FIRE_COLS)
      fb:SetFlipBookFrames(FIRE_FRAMES)
      fb:SetFlipBookFrameWidth(0)
      fb:SetFlipBookFrameHeight(0)
      fb:SetDuration(1.0)
      ag:SetLooping("REPEAT")
      r.fireAG, r.fireFB = ag, fb
    end)
    if not ok then
      r.fireAG, r.fireFB = nil, nil
      NS.FlipBookOK = false
    end
  end
  if not r.fireAG then
    r.fire:SetTexCoord(0, 0.25, 0, 0.25)
  end
  -- White-hot layer above 90%: pulsing via a bouncing Alpha animation.
  r.hot = CreateFrame("Frame", nil, r.fireClip)
  r.hot:SetAllPoints(r.fireClip)
  r.hotTex = r.hot:CreateTexture(nil, "OVERLAY")
  r.hotTex:SetAllPoints()
  r.hotTex:SetColorTexture(1, 1, 0.94, 1)
  r.hotTex:SetBlendMode("ADD")
  r.hotTex:SetAlpha(0.35)
  pcall(function()
    local ag = r.hotTex:CreateAnimationGroup()
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(0.15)
    a:SetToAlpha(0.55)
    a:SetDuration(0.3)
    ag:SetLooping("BOUNCE")
    r.hotAG = ag
  end)
  r.hot:Hide()
  r.fireClip:Hide()

  -- Pop: white ADD flash over the row.
  r.flash = r:CreateTexture(nil, "OVERLAY", nil, 6)
  r.flash:SetAllPoints()
  r.flash:SetColorTexture(1, 1, 1, 1)
  r.flash:SetBlendMode("ADD")
  r.flash:SetAlpha(0)
  -- Pop: gold glow border from four plain textures (no atlas).
  r.glow = {}
  local edges = {
    { "TOPLEFT", "TOPRIGHT", -2, 2, 2, 2, true },
    { "BOTTOMLEFT", "BOTTOMRIGHT", -2, -2, 2, -2, true },
    { "TOPLEFT", "BOTTOMLEFT", -2, 2, -2, -2, false },
    { "TOPRIGHT", "BOTTOMRIGHT", 2, 2, 2, -2, false },
  }
  local i
  for i = 1, 4 do
    local e = edges[i]
    local t = r:CreateTexture(nil, "OVERLAY", nil, 7)
    t:SetColorTexture(1, 0.82, 0.35, 1)
    t:SetBlendMode("ADD")
    t:SetPoint(e[1], r, e[1], e[3], e[4])
    t:SetPoint(e[2], r, e[2], e[5], e[6])
    if e[7] then t:SetHeight(2) else t:SetWidth(2) end
    t:SetAlpha(0)
    r.glow[i] = t
  end
  -- Pop: Scale 1 -> 1.08 -> 1 from the LEFT edge.
  if r.CreateAnimationGroup then
    local ok = pcall(function()
      local ag = r:CreateAnimationGroup()
      local up = ag:CreateAnimation("Scale")
      local down = ag:CreateAnimation("Scale")
      if up.SetScaleFrom and up.SetScaleTo then
        up:SetScaleFrom(1, 1); up:SetScaleTo(1.08, 1.08)
        down:SetScaleFrom(1.08, 1.08); down:SetScaleTo(1, 1)
      else
        up:SetScale(1.08, 1.08)
        down:SetScale(1 / 1.08, 1 / 1.08)
      end
      up:SetOrigin("LEFT", 0, 0); down:SetOrigin("LEFT", 0, 0)
      up:SetDuration(0.12); up:SetOrder(1)
      down:SetDuration(0.18); down:SetOrder(2)
      r.popAnim = ag
    end)
    if not ok then r.popAnim = nil end
  end
  r:Hide()
  rows[#rows + 1] = r
  return r
end

local function StopFire(r)
  if r.fireAG and r.fireOn then pcall(r.fireAG.Stop, r.fireAG) end
  if r.hotAG and r.hotOn then pcall(r.hotAG.Stop, r.hotAG) end
  r.fireOn, r.hotOn = false, false
  r.hot:Hide()
  r.fireClip:Hide()
end

-- pct is 0..1 of the bar; width is the eased fill width in px.
local function UpdateFire(r, pct, width, barH, class, dt)
  local db = DB()
  local inten = type(db.fireIntensity) == "number" and db.fireIntensity or 0.8
  if db.showFire == false or inten <= 0 or width < 2 or not r:IsShown() then
    if r.fireOn or r.fireClip:IsShown() then StopFire(r) end
    return false
  end
  if pct < 0 then pct = 0 elseif pct > 1 then pct = 1 end
  r.fireClip:SetWidth(width)
  r.fireClip:Show()
  local inner = math.max(1, barH - 2)
  r.fire:SetHeight(math.max(1, inner * (0.35 + 0.65 * pct)))
  local a = 0.25 + 0.75 * pct * inten
  if a > 1 then a = 1 end
  r.fire:SetAlpha(a)
  -- Orange, blended 25% toward the class color.
  local cr, cg, cb = NS.ClassColor(class)
  r.fire:SetVertexColor(1 * 0.75 + cr * 0.25, 0.55 * 0.75 + cg * 0.25, 0.15 * 0.75 + cb * 0.25, 1)
  local dur = 1.0 - 0.4 * pct
  local needsTick = false
  if r.fireAG then
    if math.abs(dur - r.fireDur) > 0.05 then
      r.fireDur = dur
      pcall(r.fireFB.SetDuration, r.fireFB, dur)
    end
    if not r.fireOn then
      pcall(r.fireAG.Play, r.fireAG)
      r.fireOn = true
    end
  else
    -- SetTexCoord fallback; keeps the anim driver alive while fire shows.
    r.fireDur = dur
    r.fireAcc = r.fireAcc + (dt or 0)
    local step = dur / FIRE_FRAMES
    if r.fireAcc >= step then
      r.fireFrame = (r.fireFrame + math.floor(r.fireAcc / step)) % FIRE_FRAMES
      r.fireAcc = r.fireAcc % step
      local c = r.fireFrame % FIRE_COLS
      local rr = math.floor(r.fireFrame / FIRE_COLS)
      r.fire:SetTexCoord(c * 0.25, c * 0.25 + 0.25, rr * 0.25, rr * 0.25 + 0.25)
    end
    r.fireOn = true
    needsTick = true
  end
  if pct > 0.9 then
    r.hot:SetAlpha(math.min(1, (pct - 0.9) / 0.1 * inten))
    if not r.hotOn then
      r.hot:Show()
      if r.hotAG then pcall(r.hotAG.Play, r.hotAG) end
      r.hotOn = true
    end
  elseif r.hotOn then
    if r.hotAG then pcall(r.hotAG.Stop, r.hotAG) end
    r.hot:Hide()
    r.hotOn = false
  end
  return needsTick
end


local function AcquireRow()
  local r = table.remove(pool)
  if not r then r = CreateRow() end
  r.popT = nil
  r.flash:SetAlpha(0)
  local i
  for i = 1, 4 do r.glow[i]:SetAlpha(0) end
  return r
end

local function ReleaseRow(r)
  StopFire(r)
  if r.popAnim and r.popAnim.Stop then pcall(r.popAnim.Stop, r.popAnim) end
  r.key = nil
  r:Hide()
  pool[#pool + 1] = r
end

local function ClearRows()
  local k, r
  for k, r in pairs(rowByKey) do ReleaseRow(r) end
  rowByKey = {}
  state = {}
end

local function StartPop(r)
  r.popT = 0
  if r.popAnim and r.popAnim.Play then
    pcall(r.popAnim.Stop, r.popAnim)
    pcall(r.popAnim.Play, r.popAnim)
  end
end

-- Leader debounce: pop when a new key holds rank 1 for POP_HOLD seconds,
-- at most once per POP_COOLDOWN, never on the first sort of a fight.
function NS.UpdateLeader(key, now)
  if key ~= candKey then
    candKey, candSince = key, now
  end
  if not key or key == leaderKey then return false end
  if now - candSince < POP_HOLD then return false end
  local popped = false
  if suppressPop or leaderKey == nil then
    suppressPop = false
  elseif now - lastPopAt >= POP_COOLDOWN then
    lastPopAt = now
    popped = true
  else
    return false -- keep the old leader until the cooldown ends
  end
  leaderKey = key
  return popped
end

function NS.ResetLeader()
  leaderKey, candKey, candSince = nil, nil, 0
  suppressPop = true
end

-- Drop one UTF-8 character from the end.
local function DropLastChar(s)
  local n = string.len(s)
  while n > 1 do
    local b = string.byte(s, n)
    n = n - 1
    if b < 128 or b >= 192 then break end
  end
  return string.sub(s, 1, n)
end

function NS.Truncate(fs, text, maxW)
  text = text or "?"
  fs:SetText(text)
  if not fs.GetStringWidth or not maxW or maxW <= 0 then return text end
  local width = fs:GetStringWidth()
  if not width or width <= maxW then return text end
  local s = text
  while string.len(s) > 1 do
    s = DropLastChar(s)
    fs:SetText(s .. ELLIPSIS)
    width = fs:GetStringWidth()
    if not width or width <= maxW then break end
  end
  return s .. ELLIPSIS
end

local function EntryKey(e, i)
  if type(e.guid) == "string" and e.guid ~= "" then return e.guid end
  if type(e.name) == "string" then return "n:" .. e.name end
  return "i:" .. i
end

local function Ease(cur, target, k)
  return cur + (target - cur) * k
end

-- Columns: "auto" = ceil(n / maxRows) clamped 1..4, else 1..4 fixed.
function NS.ColumnCount(n, maxRows, columns)
  if columns == "auto" or columns == nil then
    return math.max(1, math.min(4, math.ceil((n or 0) / math.max(1, maxRows))))
  end
  local c = tonumber(columns) or 1
  if c < 1 then c = 1 elseif c > 4 then c = 4 end
  return math.floor(c)
end

-- Global ranking across columns plus player pin. Returns visible list and C.
function NS.LayoutEntries(entries, maxRows, columns)
  local C = NS.ColumnCount(#entries, maxRows, columns)
  local N = math.min(maxRows * C, #entries)
  local vis, you, youVisible = {}, nil, false
  local i
  for i = 1, #entries do
    if entries[i].isPlayer then you = entries[i] end
    if i <= N then
      vis[i] = entries[i]
      if entries[i].isPlayer then youVisible = true end
    end
  end
  if you and not youVisible and N > 0 then
    vis[N] = you
    you.pinned = true
  end
  return vis, C
end

local function SetGlow(r, a)
  local i
  for i = 1, 4 do r.glow[i]:SetAlpha(a) end
end

local function Step(dt)
  local db = DB()
  local w = db.barWidth or 240
  local full = w - 2
  dt = dt or 0
  local k = 1 - math.exp(-EASE_RATE * dt)
  local km = 1 - math.exp(-MOVE_RATE * dt)
  local moving = false
  local baseLevel = main:GetFrameLevel() or 1

  if fadeT then
    fadeT = fadeT - dt
    if fadeT <= 0 then
      fadeT = nil
      ClearRows()
      lastShown = 0
      NS.ResetLeader()
      if not editModeOpen then main:SetAlpha(0) end
      return false
    end
    main:SetAlpha(fadeT / FADE_TIME)
    moving = true
  end

  local key, r
  for key, r in pairs(rowByKey) do
    local st = state[key]
    if st then
      -- Position: ease x/y toward the sorted slot.
      local slid = false
      r.x = Ease(r.x, r.tx, km)
      if math.abs(r.tx - r.x) < SNAP_PX then r.x = r.tx else slid = true end
      r.y = Ease(r.y, r.ty, km)
      if math.abs(r.ty - r.y) < SNAP_PX then r.y = r.ty else slid = true end
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", main, "TOPLEFT", r.x, r.y)
      -- Moving rows draw above settled ones; the popping row above all.
      local lvl = baseLevel + 2
      if slid then lvl = baseLevel + 6 end
      if r.popT then lvl = baseLevel + 10 end
      if r.lvl ~= lvl then r.lvl = lvl; r:SetFrameLevel(lvl) end
      -- New rows fade in at their slot.
      if r.a < 1 then
        r.a = Ease(r.a, 1, k)
        if r.a > 0.99 then r.a = 1 else slid = true end
        r:SetAlpha(r.a)
      end
      if slid then moving = true end

      -- Bar width and counters.
      local tw = st.tfrac * full
      st.w = Ease(st.w, tw, k)
      if math.abs(tw - st.w) < SNAP_PX then st.w = tw else moving = true end
      st.pct = Ease(st.pct, st.tpct, k)
      if math.abs(st.tpct - st.pct) < 0.05 then st.pct = st.tpct else moving = true end
      st.raw = Ease(st.raw, st.traw, k)
      if math.abs(st.traw - st.raw) < 0.5 then st.raw = st.traw else moving = true end

      r.value:SetText(string.format("%.1f%%  %s", st.pct, NS.FormatThreat(st.raw)))
      local vw = r.value.GetStringWidth and r.value:GetStringWidth() or 60
      if not vw or vw <= 0 then vw = 60 end
      if r.lastVW ~= math.floor(vw) then
        r.lastVW = math.floor(vw)
        -- PLAN 8: names get at most barWidth-90, less if the value text is wider.
        local nameW = math.min(w - 90, w - vw - 8)
        r.name:SetWidth(math.max(10, nameW))
        NS.Truncate(r.name, r.label, nameW)
      end
      if st.w < 1 then
        r.fill:Hide(); r.shine:Hide()
      else
        r.fill:Show(); r.shine:Show()
        r.fill:SetWidth(st.w)
      end
      if UpdateFire(r, full > 0 and st.w / full or 0, st.w, r.barH or 14, r.class, dt) then
        moving = true
      end

      -- Pop flash (0 -> 0.7 -> 0 over 0.3 s) and glow fade (1.2 s).
      if r.popT then
        r.popT = r.popT + dt
        local t = r.popT
        local fa = 0
        if t < POP_FLASH / 2 then fa = 0.7 * t / (POP_FLASH / 2)
        elseif t < POP_FLASH then fa = 0.7 * (1 - (t - POP_FLASH / 2) / (POP_FLASH / 2)) end
        r.flash:SetAlpha(fa)
        if t < POP_GLOW then
          SetGlow(r, 1 - t / POP_GLOW)
          moving = true
        else
          r.popT = nil
          r.flash:SetAlpha(0)
          SetGlow(r, 0)
        end
      end
    end
  end
  return moving
end

local function AnimOnUpdate(self, elapsed)
  if not Step(elapsed) then
    self:SetScript("OnUpdate", nil)
  end
end

local function StartAnim()
  if not animFrame then animFrame = CreateFrame("Frame") end
  if not animFrame:GetScript("OnUpdate") then
    animFrame:SetScript("OnUpdate", AnimOnUpdate)
  end
end

local function StartFade()
  if lastShown > 0 and not fadeT then
    fadeT = FADE_TIME
    StartAnim()
  end
end

function NS.OnCombatEnd()
  if not NS.forceTest and not NS.apiMissing then StartFade() end
end

function NS.OnCombatStart()
  NS.ResetLeader()
end

local function Render(entries)
  if not main then return end
  local db = DB()
  local maxRows = db.maxRows or 5
  local w = db.barWidth or 240
  local rh = db.rowHeight or 28
  local barH = math.max(8, rh - 14)
  entries = type(entries) == "table" and entries or {}

  if #entries == 0 then
    if lastShown > 0 and not editModeOpen then StartFade() return end
    if not fadeT then
      ClearRows()
      NS.ResetLeader()
      main:SetAlpha(editModeOpen and 1 or 0)
    end
    return
  end
  if fadeT then
    -- Data came back mid-fade: restore.
    fadeT = nil
  end

  local i
  for i = 1, #entries do entries[i].pinned = nil end
  local vis, C = NS.LayoutEntries(entries, maxRows, db.columns)

  local top = 100
  for i = 1, #entries do
    local p = entries[i].pct
    if type(p) == "number" and p > top then top = p end
  end

  local live = {}
  local colW = w + COL_GAP
  for i = 1, #vis do
    local e = vis[i]
    local key = EntryKey(e, i)
    live[key] = true
    local pct = type(e.pct) == "number" and e.pct or 0
    local raw = type(e.raw) == "number" and e.raw or 0
    local frac = pct / top
    if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
    local st = state[key]
    if not st then
      st = { w = 0, pct = 0, raw = 0 }
      state[key] = st
    end
    st.tfrac, st.tpct, st.traw = frac, pct, raw

    local col = math.floor((i - 1) / maxRows)
    local slot = (i - 1) % maxRows
    local tx = PAD + col * colW
    local ty = -(HEADER + slot * rh)
    local r = rowByKey[key]
    if not r then
      r = AcquireRow()
      rowByKey[key] = r
      r.x, r.y, r.a = tx, ty, 0
      r:SetAlpha(0)
      r.lastVW = nil
    end
    r.tx, r.ty = tx, ty
    r:SetSize(w, rh)
    r.bar:SetHeight(barH)
    r.barH = barH
    r.class = e.class
    local label = NS.FirstName(e.name)
    if r.key ~= key or r.label ~= label then r.lastVW = nil end
    r.key = key
    r.label = label
    if e.isPlayer then
      r.name:SetTextColor(1, 0.9, 0.64)
      r.hl:Show(); r.border:Show()
    else
      r.name:SetTextColor(0.93, 0.89, 0.8)
      r.hl:Hide(); r.border:Hide()
    end
    local cr, cg, cb = 0.5, 0.56, 0.65
    if db.classColors ~= false then cr, cg, cb = NS.ClassColor(e.class) end
    r.fill:SetVertexColor(cr, cg, cb, 1)
    r:Show()
  end
  local k, r
  for k, r in pairs(rowByKey) do
    if not live[k] then
      ReleaseRow(r)
      rowByKey[k] = nil
    end
  end
  for k in pairs(state) do
    if not live[k] then state[k] = nil end
  end

  -- Pop on a debounced leader change.
  local lead = EntryKey(entries[1], 1)
  if NS.UpdateLeader(lead, Now()) and rowByKey[lead] then
    StartPop(rowByKey[lead])
    NS.popCount = (NS.popCount or 0) + 1
  end

  local usedRows = math.min(#vis, maxRows)
  main:SetSize(C * colW - COL_GAP + PAD * 2, HEADER + math.max(1, usedRows) * rh + 4)
  main:SetAlpha(1)
  lastShown = #vis
  Step(0)
  StartAnim()
end

local function LiveVisible()
  if not (UnitExists and UnitExists("target")) then return false end
  if not (UnitCanAttack and UnitCanAttack("player", "target")) then return false end
  local combat = NS.inCombat
  if type(UnitAffectingCombat) == "function" then
    combat = combat or (UnitAffectingCombat("player") and true or false)
  end
  return combat and true or false
end

function NS.Refresh()
  if not main then return end
  NS.dirty = false
  local ok, entries = pcall(NS.CollectThreat)
  if not ok then entries = {} end
  if not NS.forceTest and not NS.apiMissing and not LiveVisible() then
    entries = {}
  end
  if editModeOpen and #entries == 0 and NS.CollectSample then
    local ok2, fake = pcall(NS.CollectSample)
    if ok2 and type(fake) == "table" then entries = fake end
  end
  Render(entries)
end

function NS.ApplyLayout()
  if not main then return end
  currentLayout = NS.ActiveLayoutName()
  local lay = NS.Layout(currentLayout)
  main:SetScale(lay.scale or 1)
  main:ClearAllPoints()
  main:SetPoint(lay.point or "CENTER", UIParent, lay.relativePoint or "CENTER", lay.xOfs or 0, lay.yOfs or 40)
  ApplyDrag()
  if NS.AnchorDialog then NS.AnchorDialog() end
end

-- Live scale change that keeps the top-left corner in place on screen.
function NS.SetScale(v)
  if not main then return end
  local lay = NS.Layout(currentLayout)
  if v < 0.6 then v = 0.6 elseif v > 1.6 then v = 1.6 end
  local old = main:GetScale() or 1
  local left, top = main:GetLeft(), main:GetTop()
  lay.scale = v
  main:SetScale(v)
  if left and top then
    main:ClearAllPoints()
    main:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * old / v, top * old / v)
    SnapAndSave()
  end
end

local function Build()
  if main then return end
  main = CreateFrame("Frame", "WoWThreatFrame", UIParent)
  main:SetFrameStrata("MEDIUM")
  main:SetClampedToScreen(true)
  main:SetSize(252, 80)

  local bg = main:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.07, 0.055, 0.06, 0.75)

  title = main:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  title:SetPoint("TOPLEFT", main, "TOPLEFT", PAD + 2, -4)
  title:SetText("WoW Threat")

  editHighlight = CreateEditHighlight(main)
  main:SetMovable(false)
  main:EnableMouse(false)

  -- Driver: dirty -> refresh at most every 0.2 s; safety poll every 0.5 s;
  -- test mode ticks every 0.1 s.
  main:SetScript("OnUpdate", function(_, elapsed)
    pollAcc = pollAcc + (elapsed or 0)
    local test = NS.forceTest or NS.apiMissing
    if (test and pollAcc >= TEST_TICK)
      or (NS.dirty and pollAcc >= POLL)
      or pollAcc >= SAFETY_POLL then
      pollAcc = 0
      NS.Refresh()
    end
  end)

  BindEditModeSignals()
  NS.ApplyLayout()
  NS.Refresh()
end

function NS.OnDBReady()
  Build()
  NS.ApplyLayout()
end
