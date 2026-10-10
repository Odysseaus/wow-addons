local _, NS = ...
WoWThreat = NS

-- Do not register a custom Edit Mode system. EditModeSystem is a closed HUD
-- enum. Meter.lua only listens for EventRegistry "EditMode.Enter"/"Exit".

NS.VERSION = "0.3.0"
NS.DB_VERSION = 2
NS.apiMissing = true
NS.forceTest = false
NS.db = nil

local PREFIX = "|cffd4af37WoW Threat|r "

local LAYOUT_DEFAULTS = {
  point = "CENTER",
  relativePoint = "CENTER",
  xOfs = 0,
  yOfs = 40,
  scale = 1,
}

local DEFAULTS = {
  maxRows = 5,
  barWidth = 240,
  rowHeight = 28,
  numberFormat = "short",
  classColors = true,
  columns = "auto",
}

local OLD_KEYS = { "mode", "locked", "lock", "point", "relativePoint", "xOfs", "yOfs", "scale" }

local function Clamp(v, lo, hi, def)
  if type(v) ~= "number" then return def end
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

function NS.Print(msg)
  print(PREFIX .. tostring(msg))
end

function NS.ClassColor(class)
  local c = RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]
  if c and c.r then
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

-- First name only: strip "-Realm".
function NS.FirstName(name)
  if type(name) ~= "string" then return "?" end
  if type(Ambiguate) == "function" then
    local ok, short = pcall(Ambiguate, name, "short")
    if ok and type(short) == "string" then name = short end
  end
  return (string.match(name, "^[^%-]+") or name)
end

-- 999, 12.3k, 1.23M
function NS.FormatThreat(v)
  if type(v) ~= "number" then return "0" end
  v = math.floor(v + 0.5)
  if NS.db and NS.db.numberFormat == "full" then return tostring(v) end
  if v < 1000 then return tostring(v) end
  if v < 1000000 then return string.format("%.1fk", v / 1000) end
  return string.format("%.2fM", v / 1000000)
end

-- SavedVariables v1 -> v2. Safe on fresh installs and repeat runs.
function NS.MigrateDB()
  if type(WoWThreatDB) ~= "table" then
    WoWThreatDB = {}
  end
  local db = WoWThreatDB
  if type(db.layout) ~= "table" then db.layout = {} end
  if type(db.layout.default) ~= "table" then db.layout.default = {} end
  local lay = db.layout.default

  if (tonumber(db.version) or 1) < 2 then
    if type(db.point) == "string" and lay.point == nil then lay.point = db.point end
    if type(db.relativePoint) == "string" and lay.relativePoint == nil then lay.relativePoint = db.relativePoint end
    if type(db.xOfs) == "number" and lay.xOfs == nil then lay.xOfs = db.xOfs end
    if type(db.yOfs) == "number" and lay.yOfs == nil then lay.yOfs = db.yOfs end
    if type(db.scale) == "number" and lay.scale == nil then lay.scale = db.scale end
  end
  local i
  for i = 1, #OLD_KEYS do
    db[OLD_KEYS[i]] = nil
  end
  db.version = NS.DB_VERSION

  local k, v
  for k, v in pairs(LAYOUT_DEFAULTS) do
    if lay[k] == nil or type(lay[k]) ~= type(v) then lay[k] = v end
  end
  lay.scale = Clamp(lay.scale, 0.6, 1.6, 1)
  for k, v in pairs(DEFAULTS) do
    if db[k] == nil or type(db[k]) ~= type(v) then db[k] = v end
  end
  db.maxRows = Clamp(db.maxRows, 1, 10, 5)
  db.barWidth = Clamp(db.barWidth, 160, 320, 240)
  db.rowHeight = Clamp(db.rowHeight, 20, 32, 28)
  if db.columns ~= "auto" then
    local c = tonumber(db.columns)
    db.columns = (c and c >= 1 and c <= 4) and math.floor(c) or "auto"
  end
  if db.threatScale ~= 1 and db.threatScale ~= 100 then db.threatScale = "auto" end
  if db.numberFormat ~= "short" and db.numberFormat ~= "full" then db.numberFormat = "short" end

  NS.db = db
  return db
end

function NS.Layout()
  if not NS.db then NS.MigrateDB() end
  return NS.db.layout.default
end

function NS.ResetDB()
  if not NS.db then NS.MigrateDB() end
  NS.db.layout.default = nil
  NS.forceTest = false
  NS.MigrateDB()
  if NS.ApplyLayout then NS.ApplyLayout() end
  if NS.Refresh then NS.Refresh() end
  NS.Print("reset.")
end

-- /wtm probe: one plain line per item so the chat can be copied.
local function yn(v) return v and "yes" or "no" end

function NS.Probe()
  local lines = {}
  local function add(label, ok) lines[#lines + 1] = label .. ": " .. yn(ok) end
  local S = type(Settings) == "table" and Settings or nil
  local em = EditModeManagerFrame

  add("EditModeManagerFrame", em ~= nil)
  add("EditModeSystemMixin", EditModeSystemMixin ~= nil)
  add("EventRegistry", EventRegistry ~= nil)
  add("Settings", S ~= nil)
  add("Settings.RegisterAddOnCategory", S and type(S.RegisterAddOnCategory) == "function")
  add("Settings.RegisterVerticalLayoutCategory", S and type(S.RegisterVerticalLayoutCategory) == "function")
  add("Settings.RegisterCanvasLayoutCategory", S and type(S.RegisterCanvasLayoutCategory) == "function")
  add("Settings.OpenToCategory", S and type(S.OpenToCategory) == "function")
  add("InterfaceOptions_AddCategory", type(InterfaceOptions_AddCategory) == "function")

  local flip = false
  if type(CreateFrame) == "function" then
    local ok, res = pcall(function()
      local f = CreateFrame("Frame")
      local t = f:CreateTexture()
      local ag = t:CreateAnimationGroup()
      return ag:CreateAnimation("FlipBook") ~= nil
    end)
    flip = ok and res
  end
  add("FlipBook animation", flip)

  add("EditModeManagerFrame.IsShowingGrid", em and type(em.IsShowingGrid) == "function")
  add("EditModeManagerFrame.GetGridSpacing", em and type(em.GetGridSpacing) == "function")
  add("EditModeManagerFrame.GetActiveLayoutInfo", em and type(em.GetActiveLayoutInfo) == "function")

  local atlas = false
  if type(C_Texture) == "table" and type(C_Texture.GetAtlasInfo) == "function" then
    local ok, info = pcall(C_Texture.GetAtlasInfo, "editmode-actionbar-highlight")
    atlas = ok and info ~= nil
  end
  add("C_Texture.GetAtlasInfo('editmode-actionbar-highlight')", atlas)
  add("UnitDetailedThreatSituation", type(UnitDetailedThreatSituation) == "function")

  local build = "unknown"
  if type(GetBuildInfo) == "function" then
    local ok, ver, bnum, bdate, toc = pcall(GetBuildInfo)
    if ok then
      build = tostring(ver) .. " build " .. tostring(bnum) .. " (" .. tostring(bdate) .. ") toc " .. tostring(toc)
    end
  end

  NS.Print("probe v" .. NS.VERSION)
  local i
  for i = 1, #lines do print(lines[i]) end
  print("GetBuildInfo: " .. build)
end

local HELP = "commands: /wtm test [raid20|raid40] | /wtm reset | /wtm probe | /wtm debug"

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" and arg1 == "WoWThreat" then
    NS.MigrateDB()
    NS.apiMissing = type(UnitDetailedThreatSituation) ~= "function"
    if NS.OnDBReady then NS.OnDBReady() end
  elseif event == "PLAYER_LOGIN" then
    NS.apiMissing = type(UnitDetailedThreatSituation) ~= "function"
    if NS.apiMissing then NS.forceTest = true end
    if NS.Refresh then NS.Refresh() end
  end
end)

SLASH_WOWTHREAT1 = "/wtm"
SLASH_WOWTHREAT2 = "/wowthreat"
SlashCmdList["WOWTHREAT"] = function(msg)
  msg = string.lower(msg or "")
  msg = string.gsub(msg, "^%s+", "")
  msg = string.gsub(msg, "%s+$", "")
  local testArg = string.match(msg, "^test%s*(%w*)$")
  if testArg then
    local size = 5
    if testArg == "raid20" then size = 20
    elseif testArg == "raid40" then size = 40
    elseif testArg ~= "" then testArg = nil end
    if testArg then
      NS.apiMissing = type(UnitDetailedThreatSituation) ~= "function"
      if NS.apiMissing or (testArg ~= "" and not (NS.forceTest and NS.testSize == size)) then
        NS.forceTest = true
      else
        NS.forceTest = not NS.forceTest
      end
      NS.testSize = size
      if NS.ResetSample then NS.ResetSample() end
      NS.Print(NS.forceTest and ("test on (" .. size .. " players).") or "test off.")
      if NS.Refresh then NS.Refresh() end
      return
    end
  end
  if msg == "debug" then
    NS.debug = not NS.debug
    if NS.ResetThreatDebug then NS.ResetThreatDebug() end
    NS.Print(NS.debug and "debug on: one threatValue line per unit per target." or "debug off.")
  elseif msg == "reset" then
    NS.ResetDB()
  elseif msg == "probe" then
    NS.Probe()
  else
    NS.Print(HELP)
  end
end
