local _, NS = ...
WoWThreat = NS

-- Do not register a custom Edit Mode system. EditModeSystem is a closed HUD
-- enum and OnSystemLoad will not accept an addon frame. UI.lua only listens
-- for EventRegistry "EditMode.Enter" and "EditMode.Exit".

NS.MODES = { "bars", "plates", "dial" }
NS.rows = {}
NS.anim = {}
NS.apiMissing = true
NS.forceTest = false
NS.db = nil

NS.CLASS_ICON_TCOORDS = {
  WARRIOR     = { 0, 0.25, 0, 0.25 },
  MAGE        = { 0.25, 0.49609375, 0, 0.25 },
  ROGUE       = { 0.49609375, 0.7421875, 0, 0.25 },
  DRUID       = { 0.7421875, 0.98828125, 0, 0.25 },
  HUNTER      = { 0, 0.25, 0.25, 0.5 },
  SHAMAN      = { 0.25, 0.49609375, 0.25, 0.5 },
  PRIEST      = { 0.49609375, 0.7421875, 0.25, 0.5 },
  WARLOCK     = { 0.7421875, 0.98828125, 0.25, 0.5 },
  PALADIN     = { 0, 0.25, 0.5, 0.75 },
  DEATHKNIGHT = { 0.25, 0.49609375, 0.5, 0.75 },
  MONK        = { 0.49609375, 0.7421875, 0.5, 0.75 },
  DEMONHUNTER = { 0.7421875, 0.98828125, 0.5, 0.75 },
}

local DEFAULTS = {
  mode = "bars",
  locked = false,
  point = "CENTER",
  relativePoint = "CENTER",
  xOfs = 0,
  yOfs = 40,
  scale = 1,
}

function NS.ClassColor(class)
  local c = RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]
  if c then
    return c.r, c.g, c.b
  end
  if class == "WARRIOR" then return 0.78, 0.61, 0.43 end
  if class == "MAGE" then return 0.25, 0.78, 0.92 end
  if class == "ROGUE" then return 1, 0.96, 0.41 end
  if class == "DRUID" then return 1, 0.49, 0.04 end
  if class == "HUNTER" then return 0.67, 0.83, 0.45 end
  if class == "SHAMAN" then return 0, 0.44, 0.87 end
  if class == "PRIEST" then return 1, 1, 1 end
  if class == "WARLOCK" then return 0.53, 0.53, 0.93 end
  if class == "PALADIN" then return 0.96, 0.55, 0.73 end
  return 0.8, 0.8, 0.8
end

function NS.ApplyClassIcon(tex, class)
  if not tex then return end
  local map = nil
  if CLASS_ICON_TCOORDS and class and CLASS_ICON_TCOORDS[class] then
    map = CLASS_ICON_TCOORDS[class]
  elseif class and NS.CLASS_ICON_TCOORDS[class] then
    map = NS.CLASS_ICON_TCOORDS[class]
  end
  if map then
    tex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
    tex:SetTexCoord(map[1], map[2], map[3], map[4])
    tex:SetVertexColor(1, 1, 1, 1)
  else
    local r, g, b = NS.ClassColor(class)
    tex:SetTexture("Interface\\Buttons\\WHITE8X8")
    tex:SetTexCoord(0, 1, 0, 1)
    tex:SetVertexColor(r, g, b, 1)
  end
end

function NS.ShortName(name)
  name = name or "?"
  if string.len(name) > 5 then
    return string.sub(name, 1, 5)
  end
  return name
end

function NS.CopyDefaults()
  if type(WoWThreatDB) ~= "table" then
    WoWThreatDB = {}
  end
  NS.db = WoWThreatDB
  if NS.db.locked == nil and NS.db.lock ~= nil then
    NS.db.locked = NS.db.lock
  end
  local k, v
  for k, v in pairs(DEFAULTS) do
    if NS.db[k] == nil then
      NS.db[k] = v
    end
  end
  if NS.db.scale < 0.6 then NS.db.scale = 0.6 end
  if NS.db.scale > 1.6 then NS.db.scale = 1.6 end
  local known = false
  local i
  for i = 1, 3 do
    if NS.MODES[i] == NS.db.mode then known = true end
  end
  if not known then NS.db.mode = "bars" end
end

function NS.CycleMode()
  if not NS.db then NS.CopyDefaults() end
  local i = 1
  local n
  for n = 1, 3 do
    if NS.MODES[n] == NS.db.mode then i = n end
  end
  i = i + 1
  if i > 3 then i = 1 end
  NS.db.mode = NS.MODES[i]
  if NS.ApplyMode then NS.ApplyMode() end
  print("|cffd4af37WoW Threat|r mode " .. NS.db.mode .. ".")
end

function NS.ToggleLock()
  if not NS.db then NS.CopyDefaults() end
  NS.db.locked = not NS.db.locked
  if NS.ApplyLock then NS.ApplyLock() end
  if NS.db.locked then
    print("|cffd4af37WoW Threat|r window locked.")
  else
    print("|cffd4af37WoW Threat|r lock cleared. The meter moves only while Edit Mode is open.")
  end
end

function NS.ResetDB()
  if not NS.db then NS.CopyDefaults() end
  NS.db.mode = "bars"
  NS.db.locked = false
  NS.db.point = "CENTER"
  NS.db.relativePoint = "CENTER"
  NS.db.xOfs = 0
  NS.db.yOfs = 40
  NS.db.scale = 1
  NS.forceTest = false
  if NS.ApplyLayout then NS.ApplyLayout() end
  print("|cffd4af37WoW Threat|r reset.")
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" and arg1 == "WoWThreat" then
    NS.CopyDefaults()
    NS.apiMissing = type(UnitDetailedThreatSituation) ~= "function"
    if NS.OnDBReady then NS.OnDBReady() end
  elseif event == "PLAYER_LOGIN" then
    NS.apiMissing = type(UnitDetailedThreatSituation) ~= "function"
    if NS.apiMissing then
      NS.forceTest = true
    end
    if NS.RefreshChrome then NS.RefreshChrome() end
  end
end)

SLASH_WOWTHREAT1 = "/wtm"
SLASH_WOWTHREAT2 = "/wowthreat"
SlashCmdList["WOWTHREAT"] = function(msg)
  msg = string.lower(msg or "")
  msg = string.gsub(msg, "^%s+", "")
  msg = string.gsub(msg, "%s+$", "")
  local modeArg = string.match(msg, "^mode%s+(%a+)$")
  if modeArg then
    if NS.SetMode then
      NS.SetMode(modeArg)
    else
      NS.db = NS.db or {}
      NS.db.mode = modeArg
      if NS.ApplyMode then NS.ApplyMode() end
    end
  elseif msg == "mode" then
    NS.CycleMode()
  elseif msg == "lock" then
    NS.ToggleLock()
  elseif msg == "test" then
    NS.apiMissing = type(UnitDetailedThreatSituation) ~= "function"
    if NS.apiMissing then
      NS.forceTest = true
      print("|cffd4af37WoW Threat|r test roster (no threat API).")
    else
      NS.forceTest = not NS.forceTest
      if NS.forceTest then
        print("|cffd4af37WoW Threat|r test on.")
      else
        print("|cffd4af37WoW Threat|r test off.")
      end
    end
    if NS.RefreshChrome then NS.RefreshChrome() end
  elseif msg == "reset" then
    NS.ResetDB()
  else
    print("|cffd4af37WoW Threat|r /wtm mode [bars|plates|dial] | lock | test | reset")
  end
end
