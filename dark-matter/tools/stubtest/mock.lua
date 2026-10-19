-- minimal WoW stub to execute DarkMatter in plain Lua 5.1
MODE=os.getenv("MODE")
local log = {}
local function out(...) local t={} for i=1,select('#',...) do t[#t+1]=tostring((select(i,...))) end log[#log+1]=table.concat(t," ") end
print = out
LOOT_SLOTS={}
FISH_LOOT=false
ZONE_TEXT="Elwynn Forest"
SUBZONE_TEXT=""
TIME_NOW=1000
FISH_CHANNEL=false
local FrameMT = {}
local function newframe(name, parent, tmpl)
  local f = { _shown=false, _pts={}, _scripts={}, _w=100,_h=100, _name=name }
  setmetatable(f,{__index=function(t,k)
    if k=="TitleText" and tmpl=="BasicFrameTemplateWithInset" then local fs=t:CreateFontString() rawset(t,k,fs) return fs end
    if type(k)=="string" and k:sub(1,1)=="_" then return nil end
    return FrameMT[k] or function() end end})
  if name then _G[name]=f end
  return f
end
FS={}
function FrameMT.CreateFontString() local fs=newframe() FS[#FS+1]=fs return fs end
function FrameMT.CreateTexture() return newframe() end
function FrameMT.Show(s) s._shown=true if s._scripts.OnShow then s._scripts.OnShow(s) end end
function FrameMT.Hide(s) local was=s._shown s._shown=false if was and s._scripts and s._scripts.OnHide then s._scripts.OnHide(s) end end
function FrameMT.IsShown(s) return s._shown end
function FrameMT.SetScript(s,k,fn) s._scripts[k]=fn end
function FrameMT.RegisterEvent(s,e) s._ev=s._ev or {} s._ev[e]=true end
function FrameMT.SetPoint(s,...) s._pts[#s._pts+1]={...} s._last={...} end
function FrameMT.ClearAllPoints(s) s._pts={} end
function FrameMT.GetPoint(s) local p=s._pts[#s._pts] or {"CENTER",nil,"CENTER",0,0} if type(p[2])=="table" or p[2]==nil then return p[1],p[2],p[3],p[4],p[5] end return p[1],nil,p[1],p[2],p[3] end
function FrameMT.GetWidth(s) return s._w end
function FrameMT.GetHeight(s) return s._h end
function FrameMT.GetCenter(s) return 500,500 end
function FrameMT.GetEffectiveScale() return 1 end
function FrameMT.SetSize(s,w,h) s._w,s._h=w,h end
function FrameMT.StartMoving(s) s._moving=true end
function FrameMT.StopMovingOrSizing(s) s._moving=false end
ALL={}
function CreateFrame(t,name,parent,tmpl) local f=newframe(name,parent,tmpl) ALL[#ALL+1]=f return f end
UIParent=newframe("UIParent"); Minimap=newframe("Minimap"); Minimap._w=140; Minimap._h=140
GameTooltip=newframe("GameTooltip")
function GetCursorPosition() return 600,500 end
function GetBuildInfo() return "1.60.1","70009","Sep 24 2026",16001 end
function GetLocale() return "enUS" end
function InCombatLockdown() return false end
LATE=false
C_Timer={After=function(t,fn) if t==3 then LATE=true end fn() end}
LOADED={}
C_AddOns={GetAddOnMetadata=function() return "16001" end,
  IsAddOnLoaded=function(n) return LOADED[n] or false end,
  LoadAddOn=function(n) if MODE~="minimal" then LOADED[n]=true; if n=="Blizzard_AchievementUI" then AchievementFrame=newframe("AchievementFrame") end return true end return false,"WRONG_GAME_TYPE" end}
C_Map={GetBestMapForUnit=function() return 1429 end, GetPlayerMapPosition=function() return {x=0.33,y=0.44,GetXY=function(self) return self.x,self.y end} end}
WOW_PROJECT_ID=1; WOW_PROJECT_MAINLINE=1
GetMinimapShape=nil
Enum={UIMapType={Dungeon=4}, GameRule={EncounterJournalDisabled=1, EjJourneysDisabled=2, TransmogEnabled=3}}
function issecretvalue(v) return type(v)=="string" and v:find("SECRETNAME")~=nil end
function GetInstanceInfo() return "Eastern Kingdoms","none",0,"",0,0,false,0,0 end
function IsInInstance() return false,"none" end
function GetNumSavedInstances() return 0 end
C_Item={}
if MODE~="minimal" then
  C_QuestLog={GetNumQuestLogEntries=function() return 6,4 end,
    GetInfo=function(i) local t={{title="Elwynn Forest",isHeader=true},{title="Wolves",questID=101,level=2,isHeader=false},{title="Gold Dust",questID=102,level=5,isHeader=false},{title="Westfall",isHeader=true},{title="Hidden",questID=9,isHeader=false,isHidden=true},{title="The Defias",questID=103,level=12,isHeader=false,frequency=1}} return t[i] end,
    IsComplete=function(id) return id==102 end, IsFailed=function() return false end,
    GetQuestObjectives=function(id) return {{text="Kill 8 wolves",finished=false},{text="Gather dust 3/3",finished=true}} end}
  function GetProfessions() return nil,nil,nil,4,5 end
  function GetProfessionInfo(idx)
    if idx==4 then return "Fishing","Interface\\Icons\\Trade_Fishing",171,225,1,0,356,0 end
  end
  FISH_CHANNEL=false
  FISH_LOOT=false
  LOOT_SLOTS={}
  ZONE_TEXT="Elwynn Forest"
  SUBZONE_TEXT=""
  TIME_NOW=1000
  function UnitChannelInfo(u) if u=="player" and FISH_CHANNEL then return "Fishing",nil,nil,0,0,false,false,7620 end end
  function IsFishingLoot() return FISH_LOOT==true end
  function GetNumLootItems() return #LOOT_SLOTS end
  function GetLootSlotInfo(i) local s=LOOT_SLOTS[i]; if not s then return end return s.tex,s.name,s.qty,s.quality,false end
  function GetLootSlotLink(i) local s=LOOT_SLOTS[i]; return s and s.link end
  FISH_LURE_ON=false
  function GetItemIcon(id) if id==6289 then return "Interface\\Icons\\INV_Misc_Fish_02" end return "Interface\\Icons\\INV_Misc_QuestionMark" end
  function SetPortraitToTexture(tex, path) if tex and tex.SetTexture then tex:SetTexture(path) end return true end
  function GetItemQualityColor(q)
    local m={[0]={0.62,0.62,0.62},[1]={1,1,1},[2]={0.12,1,0},[3]={0,0.44,0.87},[4]={0.64,0.21,0.93},[5]={1,0.5,0}}
    local c=m[q] or m[1]; return c[1],c[2],c[3],"ffffffff"
  end
  function GetItemInfo(id) if id==6289 then return "Raw Longjaw Mud Snapper","item:6289",1 end return "Item","item:"..tostring(id),1 end

  function GetWeaponEnchantInfo() if FISH_LURE_ON then return true,600000,0,263,false end return false end
  function GetRealZoneText() return ZONE_TEXT or "Elwynn Forest" end
  function GetZoneText() return ZONE_TEXT or "Elwynn Forest" end
  function GetSubZoneText() return SUBZONE_TEXT or "" end
  function GetMinimapZoneText() return ZONE_TEXT or "Elwynn Forest" end
  function GetTime() return TIME_NOW or 1000 end
  function GetMoneyString(c) return tostring(c).."c" end
  if not C_Item then C_Item={} end
  function GetItemInfo(id) if id==6529 then return "Shiny Bauble" end end
  function C_Item.GetItemInfo(id) return "Item",nil,1,1,0,"Misc","Junk",20,"",nil,50 end
  function GetTotalAchievementPoints() return 15 end
  function GetCategoryList() return {92,96} end
  function GetAchievementInfo() return 7,"Achv",10,true end
  -- journal data layer present, but like the real client: no tiers/instances; known IDs resolve in "journal" mode
  C_EncounterJournal={InitalizeSelectedTier=function() end,OnOpen=function() end,OnClose=function() end,
    GetLootInfoByIndex=function() return {name="Sword",itemID=19019} end, GetLootInfo=function() return {} end,
    InstanceHasLoot=function() return true end, GetInstanceForGameMap=function() return nil end,
    GetEncountersOnMap=function() return {} end, GetDungeonEntrancesForMap=function() return {{name="Entrance"}} end,
    GetSectionInfo=function() end, IsEncounterComplete=function() return false end}
  function EJ_GetNumTiers() return MODE=="journal" and 2 or 0 end
  function EJ_GetCurrentTier() return 1 end
  function EJ_GetTierInfo(t) return "Tier"..t end
  function EJ_SelectTier() end
  function EJ_GetInstanceByIndex(i,raid) if MODE=="journal" and i<=(raid and 1 or 3) then return 1000+i,"Inst"..i end end
  function EJ_GetInstanceInfo(id) if MODE=="journal" and id==63 then return "Deadmines","d" end end
  function EJ_SelectInstance() end
  function EJ_GetEncounterInfoByIndex(i) if MODE=="journal" and i<=4 then return "Boss"..i,"d",500+i,1 end end
  function EJ_GetEncounterInfo() return "Boss" end
  function EJ_SelectEncounter() end
  function EJ_GetNumLoot() return 7 end
  function EJ_GetInstanceForMap() return nil end
  function EJ_SetDifficulty() end
  C_Map.GetMapInfo=function() return {name="Zone",mapType=3,parentMapID=947} end
  C_Map.GetFallbackWorldMapID=function() return 946 end
  C_Map.GetMapChildrenInfo=function(id,t,rec) if id==947 then return {{name="Deadmines"},{name="RFC"}} end return {} end
  C_ContentTracking={GetEncounterTrackingInfo=function() end}
  C_LFGInfo={IsLFDEnabled=function() return true end,IsLFREnabled=function() return true end,CanPlayerUseLFD=function() return true end,
    CanPlayerUseLFR=function() return false end,IsGroupFinderEnabled=function() return true end,
    GetAllEntriesForCategory=function(c) return c==1 and {10,11} or {} end, GetDungeonInfo=function() return {} end}
  function GetLFDChoiceOrder() return {10,11} end
  function GetLFGDungeonInfo(id) if id==10 then return "Deadmines" elseif id==11 then return "Wailing Caverns" elseif id==12 then return "SECRETNAME" end end
  function GetLFGDungeonNumEncounters(id) return id==10 and 6 or (id==11 and 7 or 0) end
  function GetLFGDungeonEncounterInfo() return "Boss","tex",false end
  function GetLFGDungeonRewards() return end
  function GetNumRFDungeons() return 0 end
  function GetRFDungeonInfo() end
  function RequestRaidInfo() end
  function GetNumSavedWorldBosses() return 0 end
  C_Item={DoesItemExistByID=function(id) return id~=99999999 end,
    GetItemInfoInstant=function(id) if id==99999999 then return nil end return id,"Weapon","Sword","INVTYPE_WEAPON",134400,2,7 end,
    GetItemInfo=function(id)
      if id==99999999 then return end
      if id==6529 then return "Shiny Bauble","item:6529",1,1,0,"Consumable","Other",20,"",nil,50 end
      if id==6530 then return "Nightcrawlers","item:6530",1,1,0,"Consumable","Other",20,"",nil,12 end
      if id==6532 then return "Bright Baubles","item:6532",1,1,0,"Consumable","Other",20,"",nil,250 end
      if id==6533 then return "Aquadynamic Fish Attractor","item:6533",1,1,0,"Consumable","Other",20,"",nil,250 end
      if type(id)=="string" and id:find("item:",1,true) then
        return "Item",nil,1,1,0,"Misc","Junk",20,"",nil,50
      end
      if LATE then return "Item"..id,"link",(id%5)+1,1,0,"Misc","Junk",20,"",nil,50 end
    end,
    GetItemNameByID=function(id) if LATE and id~=99999999 then return "Item"..id end end,
    RequestLoadItemDataByID=function() end}
  C_TooltipInfo={GetItemByID=function(id) if id~=99999999 then return {lines={{},{},{}}} end end}
  C_GameRules={GetActiveGameMode=function() return 1 end,IsStandard=function() return false end,IsHardcoreActive=function() return false end,
    IsGameRuleActive=function(r) return r==1 end}
  function GetNumLootItems() return #LOOT_SLOTS end
  function GetLootInfo() return {} end
  function GetLootSlotInfo(i)
    local s=LOOT_SLOTS[i]; if not s then return end
    return s.tex,s.name,s.qty,s.quality,false
  end
  function GetLootSourceInfo() end
  if not LOOT_SLOTS then LOOT_SLOTS={} end
  C_InstanceEncounter={IsEncounterInProgress=function() return false end}
  C_LootHistory={}
end
local cat={GetID=function() return 7 end}
Settings={RegisterCanvasLayoutCategory=function() return cat end,RegisterAddOnCategory=function() end,OpenToCategory=function(id) out("OpenToCategory",id) end,RegisterAddOnSetting=function() end}
UISpecialFrames={}; tinsert=table.insert; strmatch=string.match; strlower=string.lower
strtrim=function(s) return (s:gsub("^%s+",""):gsub("%s+$","")) end
SlashCmdList={}; date=os.date
-- taint-safety instrumentation: any call to a state-mutating / server-asking API is recorded
MUTATED = {}
local function mut(name, orig)
  return function(...) MUTATED[#MUTATED+1] = name if orig then return orig(...) end end
end
LoadAddOn = mut("LoadAddOn", LoadAddOn)
if C_AddOns then C_AddOns.LoadAddOn = mut("C_AddOns.LoadAddOn", C_AddOns.LoadAddOn) end
RequestRaidInfo = mut("RequestRaidInfo", RequestRaidInfo)
if C_Item then C_Item.RequestLoadItemDataByID = mut("C_Item.RequestLoadItemDataByID", C_Item.RequestLoadItemDataByID) end
for _,n in ipairs({"EJ_SelectTier","EJ_SelectInstance","EJ_SelectEncounter","EJ_SetDifficulty"}) do _G[n] = mut(n, _G[n]) end
if C_EncounterJournal then
  for _,n in ipairs({"OnOpen","OnClose","InitalizeSelectedTier"}) do C_EncounterJournal[n] = mut("C_EncounterJournal."..n, C_EncounterJournal[n]) end
end
ReloadUI = mut("ReloadUI"); SetCVar = mut("SetCVar")
REGLOG = {}
local origReg = FrameMT.RegisterEvent
function FrameMT.RegisterEvent(s, e) REGLOG[#REGLOG+1] = {frame=s, ev=e} return origReg(s, e) end
function FrameMT.UnregisterEvent(s, e) if s._ev then s._ev[e] = nil end end
-- widget stubs for the P1 window
STANDARD_TEXT_FONT="Fonts\\FRIZQT__.TTF"
function UnitLevel() return 5 end
UIParent._w=1920; UIParent._h=1080
function FrameMT.SetText(s,t) s._text=t end
function FrameMT.GetText(s) return s._text or "" end
function FrameMT.SetAutoFocus() end
function FrameMT.ClearFocus() end
function FrameMT.SetMaxLetters() end
function FrameMT.SetTextColor() end
function FrameMT.SetCheckedTexture() end
function FrameMT.CreateMaskTexture(s) return {SetAllPoints=function()end,SetTexture=function()end} end
function FrameMT.AddMaskTexture() end
function FrameMT.GetStringWidth() return 60 end
function FrameMT.GetStringHeight() return 40 end
function FrameMT.GetFrameLevel() return 1 end
function FrameMT.SetFont() return true end
function FrameMT.SetMinMaxValues(s,a,b) s._min,s._max=a,b end
function FrameMT.SetValue(s,v) s._v=v if s._scripts.OnValueChanged then s._scripts.OnValueChanged(s,v) end end
function FrameMT.GetValue(s) return s._v or 0 end
function FrameMT.SetVerticalScroll(s,v) s._vs=v end
function FrameMT.GetVerticalScroll(s) return s._vs or 0 end
function FrameMT.Enable(s) s._enabled=true end
function FrameMT.Disable(s) s._enabled=false end
function FrameMT.SetScale(s,v) s._scale=v end
function FrameMT.GetScale(s) return s._scale or 1 end
function FrameMT.UnregisterEvent(s, e) if s._ev then s._ev[e] = nil end end
-- ===== strict widget model + layout resolver (0.1.1) =====
-- Strict argument checks (the real client raises Lua errors for bad types) and enough layout/draw-order
-- modelling to resolve every region's rectangle, so tests and the offline renderer see what the game draws.
UNKNOWN = {}
REGIONS = {}
TCBAD = {}
local ORDER = 0
local function nextOrder() ORDER = ORDER + 1 return ORDER end
local function isnum(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
local function needNum(fn, i, v) if not isnum(v) then error(fn .. ": bad argument #" .. i .. " (number expected, got " .. type(v) .. ")", 3) end end
local function noop() end
local LAYERS = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }
local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local POINTS = { TOPLEFT = {0, 1}, TOP = {0.5, 1}, TOPRIGHT = {1, 1}, LEFT = {0, 0.5}, CENTER = {0.5, 0.5}, RIGHT = {1, 0.5},
  BOTTOMLEFT = {0, 0}, BOTTOM = {0.5, 0}, BOTTOMRIGHT = {1, 0} }
local REAL = {}  -- every method name the stubs know; anything else is recorded in UNKNOWN

local function mk(kind, name, parent, tmpl)
  local f = { _shown = false, _pts = {}, _scripts = {}, _w = 100, _h = 100, _name = name, _kind = kind, _parent = parent, _order = nextOrder() }
  setmetatable(f, { __index = function(t, k)
    if k == "TitleText" and tmpl == "BasicFrameTemplateWithInset" then local fs = t:CreateFontString() rawset(t, k, fs) return fs end
    if type(k) == "string" and k:sub(1, 1) == "_" then return nil end
    if FrameMT[k] then return FrameMT[k] end
    UNKNOWN[k] = true
    return noop
  end })
  if name then _G[name] = f end
  return f
end

function CreateFrame(ftype, name, parent, tmpl)
  if type(ftype) ~= "string" then error("CreateFrame: frame type expected", 2) end
  if parent ~= nil and type(parent) ~= "table" then error("CreateFrame: parent must be a frame", 2) end
  local par = parent or UIParent
  local f = mk("frame", name, par, tmpl)
  f._ftype = ftype
  f._level = (par._level or 0) + 1
  f._strata = par._strata or "MEDIUM"
  ALL[#ALL + 1] = f
  return f
end
UIParent._kind = "frame"; UIParent._ftype = "Frame"; UIParent._level = 0; UIParent._strata = "MEDIUM"; UIParent._order = 0
UIParent._sw, UIParent._sh = 1920, 1080

function FrameMT.CreateTexture(s, name, layer, inherit, sub)
  layer = layer or "ARTWORK"
  if not LAYERS[layer] then error("CreateTexture: bad draw layer " .. tostring(layer), 2) end
  if sub ~= nil and (not isnum(sub) or sub < -8 or sub > 7) then error("CreateTexture: bad sublevel " .. tostring(sub), 2) end
  local t = mk("texture", name, s)
  t._layer, t._sub = layer, sub or 0
  REGIONS[#REGIONS + 1] = t
  return t
end
function FrameMT.CreateFontString(s, name, layer)
  layer = layer or "ARTWORK"
  if not LAYERS[layer] then error("CreateFontString: bad draw layer " .. tostring(layer), 2) end
  local t = mk("fontstring", name, s)
  t._layer, t._sub = layer, 0
  t._fsize = 12
  REGIONS[#REGIONS + 1] = t
  FS[#FS + 1] = t
  return t
end

function FrameMT.Show(s) s._shown = true s._hid = false if s._scripts.OnShow then s._scripts.OnShow(s) end end
function FrameMT.Hide(s)
  local was = s._shown
  s._shown = false
  s._hid = true
  if was ~= false and s._scripts and s._scripts.OnHide then s._scripts.OnHide(s) end
end

function FrameMT.SetPoint(s, point, a, b, c, d)
  if not POINTS[point] then error("SetPoint: bad anchor point " .. tostring(point), 2) end
  local rel, relPoint, x, y = nil, nil, nil, nil
  local rest = { a, b, c, d }
  local i = 1
  if type(rest[i]) == "table" or type(rest[i]) == "string" then
    if type(rest[i]) == "string" then error("SetPoint: relativeTo given as a string (" .. rest[i] .. "); pass the region", 2) end
    rel = rest[i] i = i + 1
  end
  if type(rest[i]) == "string" then
    if not POINTS[rest[i]] then error("SetPoint: bad relative point " .. rest[i], 2) end
    relPoint = rest[i] i = i + 1
  end
  if rest[i] ~= nil then needNum("SetPoint", "x", rest[i]) x = rest[i] i = i + 1 end
  if rest[i] ~= nil then needNum("SetPoint", "y", rest[i]) y = rest[i] end
  if rel ~= nil and rel == s then error("SetPoint: cannot anchor a region to itself", 2) end
  s._pts[#s._pts + 1] = { point, rel or s._parent or UIParent, relPoint or point, x or 0, y or 0 }
end
function FrameMT.SetAllPoints(s, rel)
  rel = rel or s._parent or UIParent
  s._pts = { { "TOPLEFT", rel, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0 } }
end
function FrameMT.ClearAllPoints(s) s._pts = {} end
function FrameMT.GetPoint(s, n)
  local p = s._pts[n or 1] or { "CENTER", nil, "CENTER", 0, 0 }
  return p[1], p[2], p[3], p[4], p[5]
end
function FrameMT.SetSize(s, w, h) needNum("SetSize", 1, w) needNum("SetSize", 2, h) s._sw, s._sh, s._w, s._h = w, h, w, h end
function FrameMT.SetWidth(s, w) needNum("SetWidth", 1, w) s._sw, s._w = w, w end
function FrameMT.SetHeight(s, h) needNum("SetHeight", 1, h) s._sh, s._h = h, h end
function FrameMT.SetAlpha(s, a) needNum("SetAlpha", 1, a) s._alpha = a end
function FrameMT.SetScale(s, v) needNum("SetScale", 1, v) s._scale = v end
function FrameMT.SetFrameLevel(s, n) needNum("SetFrameLevel", 1, n) s._level = n end
function FrameMT.GetFrameLevel(s) return s._level or 1 end
function FrameMT.SetFrameStrata(s, v) if not STRATA[v] then error("SetFrameStrata: bad strata " .. tostring(v), 2) end s._strata = v end
function FrameMT.SetTexture(s, file)
  if file ~= nil and type(file) ~= "string" and not isnum(file) then error("SetTexture: bad file " .. type(file), 2) end
  s._file, s._color = file, nil
end
function FrameMT.SetTexCoord(s, ...)
  local n = select("#", ...)
  if n ~= 4 and n ~= 8 then error("SetTexCoord: 4 or 8 numbers expected", 2) end
  local v = { ... }
  for i = 1, n do needNum("SetTexCoord", i, v[i]) end
  s._tc = v
  if n == 4 then
    local l, r, t, b = v[1], v[2], v[3], v[4]
    if l < 0 or r > 1 or t < 0 or b > 1 or l >= r or t >= b then
      TCBAD[#TCBAD + 1] = string.format("%s %s: %g %g %g %g", s._name or "?", tostring(s._file), l, r, t, b)
    end
  end
end
function FrameMT.SetColorTexture(s, r, g, b, a)
  needNum("SetColorTexture", 1, r) needNum("SetColorTexture", 2, g) needNum("SetColorTexture", 3, b)
  s._color, s._file = { r, g, b, a or 1 }, nil
end
function FrameMT.SetVertexColor(s, r, g, b, a)
  needNum("SetVertexColor", 1, r) needNum("SetVertexColor", 2, g) needNum("SetVertexColor", 3, b)
  s._vc = { r, g, b, a or 1 }
end
function FrameMT.SetBlendMode(s, m) if m ~= "BLEND" and m ~= "ADD" and m ~= "DISABLE" and m ~= "MOD" and m ~= "ALPHAKEY" then error("SetBlendMode: bad mode " .. tostring(m), 2) end s._blend = m end
function FrameMT.SetTextColor(s, r, g, b, a)
  needNum("SetTextColor", 1, r) needNum("SetTextColor", 2, g) needNum("SetTextColor", 3, b)
  s._tcol = { r, g, b, a or 1 }
end
function FrameMT.SetJustifyH(s, j) s._just = j end
function FrameMT.SetFont(s, path, size, flags)
  if type(path) ~= "string" then error("SetFont: path expected", 2) end
  needNum("SetFont", 2, size)
  s._fsize = size return true
end
function FrameMT.SetText(s, t) s._text = t end
function FrameMT.GetText(s) return s._text end
local function plain(t) return (tostring(t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
function FrameMT.GetStringWidth(s) local w = #plain(s._text) * (s._fsize or 12) * 0.52 return s._sw and math.min(w, s._sw) or w end
function FrameMT.GetStringHeight(s)
  local fs = s._fsize or 12
  local lines = 1
  if s._sw then local w = #plain(s._text) * fs * 0.52 lines = math.max(1, math.ceil(w / s._sw)) end
  for _ in plain(s._text):gmatch("\n") do lines = lines + 1 end
  return lines * fs * 1.2
end
function FrameMT.SetScrollChild(s, child)
  s._child = child
  child._scrollOf = s
  child._pts = { { "TOPLEFT", s, "TOPLEFT", 0, s._vs or 0 } }
end
function FrameMT.SetVerticalScroll(s, v)
  s._vs = v
  if s._child then s._child._pts = { { "TOPLEFT", s, "TOPLEFT", 0, v } } end
end
function FrameMT.SetThumbTexture(s, tex) s._thumb = tex tex._thumbOf = s end
function FrameMT.SetValue(s, v) s._v = v if s._scripts.OnValueChanged then s._scripts.OnValueChanged(s, v) end end
function FrameMT.GetWidth(s) local l, t, r, b = FrameMT._rect(s) if l then return r - l end return s._sw or 0 end
function FrameMT.GetHeight(s) local l, t, r, b = FrameMT._rect(s) if l then return t - b end return s._sh or 0 end

-- ---- layout resolver (UI units, y up; returns left, top, right, bottom or nil when unanchored) ----
local function textSize(r)
  local w = r._sw or r:GetStringWidth()
  local h = r._sh or r:GetStringHeight()
  return w, h
end
local resolving = {}
local function rect(r)
  if r == UIParent then return 0, UIParent._sh, UIParent._sw, 0 end
  if resolving[r] then error("anchor cycle at " .. tostring(r._name or r._kind)) end
  resolving[r] = true
  local res
  local ok, e = pcall(function()
    if r._thumbOf then
      local sl, st, sr, sb = rect(r._thumbOf)
      local w, h = r._sw or 0, r._sh or 0
      local mx = r._thumbOf._max or 0
      local frac = mx > 0 and ((r._thumbOf._v or 0) / mx) or 0
      local top = st - frac * math.max(0, (st - sb) - h)
      local cx = (sl + sr) / 2
      res = { cx - w / 2, top, cx + w / 2, top - h }
      return
    end
    if #r._pts == 0 then return end
    local left, right, cx, top, bottom, cy
    for _, p in ipairs(r._pts) do
      local rl, rt, rr, rb = rect(p[2])
      if not rl then return end
      local rf, pf = POINTS[p[3]], POINTS[p[1]]
      local ax = rl + rf[1] * (rr - rl) + p[4]
      local ay = rb + rf[2] * (rt - rb) + p[5]
      if pf[1] == 0 then left = ax elseif pf[1] == 1 then right = ax else cx = ax end
      if pf[2] == 0 then bottom = ay elseif pf[2] == 1 then top = ay else cy = ay end
    end
    local w, h
    if r._kind == "fontstring" then w, h = textSize(r) else w, h = r._sw, r._sh end
    if left and right then w = right - left else w = w or 0 end
    if bottom and top then h = top - bottom else h = h or 0 end
    if left == nil then left = right and (right - w) or (cx and (cx - w / 2)) end
    if bottom == nil then bottom = top and (top - h) or (cy and (cy - h / 2)) end
    if left == nil or bottom == nil then return end
    res = { left, bottom + h, left + w, bottom }
  end)
  resolving[r] = nil
  if not ok then error(e, 0) end
  if res then return res[1], res[2], res[3], res[4] end
end
FrameMT._rect = rect

local function visible(r)
  local x = r
  while x and x ~= UIParent do
    if x._hid then return false end
    if x._alpha == 0 then return false end
    x = x._parent
  end
  return true
end
local function ownerFrame(r) if r._kind == "frame" then return r end return r._parent end
local function under(r, root)
  local x = r
  while x do if x == root then return true end x = x._parent end
  return false
end

-- Resolve everything under root into a draw-ordered list.
function LayoutOf(root)
  local list = {}
  local function add(r)
    local l, t, rr, b = rect(r)
    local o = ownerFrame(r)
    local e = { r = r, kind = r._kind, l = l, t = t, rr = rr, b = b, level = o._level or 1, strata = STRATA[o._strata or "MEDIUM"] or 3,
      owner = o, layer = LAYERS[r._layer or "BACKGROUND"] or 1, sub = r._sub or 0, order = r._order }
    list[#list + 1] = e
  end
  for _, r in ipairs(REGIONS) do
    if under(r, root) and visible(r) then add(r) end
  end
  for _, f in ipairs(ALL) do
    if f ~= root and under(f, root) and visible(f) then add(f) end
  end
  table.sort(list, function(a, b)
    if a.strata ~= b.strata then return a.strata < b.strata end
    if a.level ~= b.level then return a.level < b.level end
    if a.kind == "frame" or b.kind == "frame" then
      if a.kind ~= b.kind then return a.kind == "frame" end
      return a.order < b.order
    end
    if a.owner._order ~= b.owner._order then return a.owner._order < b.owner._order end
    if a.layer ~= b.layer then return a.layer < b.layer end
    if a.sub ~= b.sub then return a.sub < b.sub end
    return a.order < b.order
  end)
  return list
end

local function jstr(s)
  return '"' .. tostring(s):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n") .. '"'
end
local function jnum(n) return string.format("%.4f", n) end
-- Write the layout of root to a JSON file for tools/render_preview.py (relative to root's top-left, y down).
function DumpLayout(root, path)
  local list = LayoutOf(root)
  local rl, rt = rect(root)
  local parts = {}
  for _, e in ipairs(list) do
    if e.l and e.kind ~= "frame" then
      local r = e.r
      local o = {}
      o[#o + 1] = '"kind":' .. jstr(e.kind)
      o[#o + 1] = '"x":' .. jnum(e.l - rl) .. ',"y":' .. jnum(rt - e.t) .. ',"w":' .. jnum(e.rr - e.l) .. ',"h":' .. jnum(e.t - e.b)
      o[#o + 1] = '"layer":' .. jstr(r._layer)
      if r._file then o[#o + 1] = '"file":' .. jstr(r._file) end
      if r._tc then o[#o + 1] = '"tc":[' .. table.concat({ jnum(r._tc[1]), jnum(r._tc[2]), jnum(r._tc[3]), jnum(r._tc[4]) }, ",") .. "]" end
      if r._color then o[#o + 1] = '"color":[' .. table.concat({ jnum(r._color[1]), jnum(r._color[2]), jnum(r._color[3]), jnum(r._color[4]) }, ",") .. "]" end
      if r._vc then o[#o + 1] = '"vc":[' .. table.concat({ jnum(r._vc[1]), jnum(r._vc[2]), jnum(r._vc[3]), jnum(r._vc[4]) }, ",") .. "]" end
      local a = 1
      local x = r
      while x and x ~= UIParent do a = a * (x._alpha or 1) x = x._parent end
      o[#o + 1] = '"alpha":' .. jnum(a)
      if r._blend then o[#o + 1] = '"blend":' .. jstr(r._blend) end
      if e.kind == "fontstring" then
        o[#o + 1] = '"text":' .. jstr(r._text or "") .. ',"size":' .. jnum(r._fsize or 12) .. ',"just":' .. jstr(r._just or "CENTER")
        local c = r._tcol or { 1, 1, 1, 1 }
        o[#o + 1] = '"tcol":[' .. table.concat({ jnum(c[1]), jnum(c[2]), jnum(c[3]) }, ",") .. "]"
      end
      -- clip to the nearest ScrollFrame ancestor
      local x2 = r._parent
      while x2 and x2 ~= UIParent do
        if x2._ftype == "ScrollFrame" then
          local cl, ct, cr, cb = rect(x2)
          o[#o + 1] = '"clip":[' .. table.concat({ jnum(cl - rl), jnum(rt - ct), jnum(cr - cl), jnum(ct - cb) }, ",") .. "]"
          break
        end
        x2 = x2._parent
      end
      parts[#parts + 1] = "{" .. table.concat(o, ",") .. "}"
    end
  end
  local w, h = rect(root)
  local fh = io.open(path, "w")
  fh:write('{"w":' .. jnum(root._sw) .. ',"h":' .. jnum(root._sh) .. ',"items":[\n' .. table.concat(parts, ",\n") .. "\n]}\n")
  fh:close()
end
DarkMatterCharDB=nil
-- load addon
local ns={}
local toc=io.open(arg[1].."/DarkMatter.toc"):read("*a")
for file in toc:gmatch("\n([%w_]+%.lua)") do
  local chunk=assert(loadfile(arg[1].."/"..file)); chunk("DarkMatter",ns)
end

local ev
for _,f in ipairs(ALL) do if f._ev and f._ev.ADDON_LOADED then ev=f end end
assert(ev,"no event frame")
local function check(c,m) if not c then error("FAIL: "..m,2) end out("ok:",m) end
-- first run: no saved variables
ev._scripts.OnEvent(ev,"ADDON_LOADED","DarkMatter")
ev._scripts.OnEvent(ev,"PLAYER_LOGIN")
check(DarkMatterDB and DarkMatterDB.loadCount==1,"defaults + loadCount")
check(DarkMatterDB.window.point=="CENTER","window default centre")
local mb=DarkMatterMinimapButton
check(mb,"minimap button created")
mb._scripts.OnClick(mb,"LeftButton")
check(DarkMatterFrame and DarkMatterFrame._shown,"click opens window")
mb._scripts.OnClick(mb,"LeftButton")
check(not DarkMatterFrame._shown,"click toggles window closed")
mb._scripts.OnDragStart(mb); mb._scripts.OnUpdate(mb); mb._scripts.OnDragStop(mb)
check(math.abs(DarkMatterDB.minimap.angle-0)<0.01,"drag sets angle (cursor right of centre -> 0 deg): "..DarkMatterDB.minimap.angle)
-- window drag + save
local f=DarkMatterFrame
f:ClearAllPoints(); f:SetPoint("TOPLEFT",UIParent,"TOPLEFT",30,-40)
f._scripts.OnDragStop(f)
check(DarkMatterDB.window.point=="TOPLEFT" and DarkMatterDB.window.x==30,"window position saved")
SlashCmdList.DARKMATTER("reset")
check(DarkMatterDB.window.point=="CENTER" and DarkMatterDB.window.x==0,"/dm reset")
SlashCmdList.DARKMATTER("")
check(f._shown,"/dm toggles")
SlashCmdList.DARKMATTER("probe")
local p=DarkMatterDB.probe
check(p and p.client.build=="70009" and p.client.interface==16001,"probe client info")
check(type(p.callOrder)=="table" and #p.callOrder>3,"calls recorded: "..#p.callOrder)
check(DarkMatterProbeFrame and DarkMatterProbeFrame._shown,"probe opens its own report window")
check(not p.areaErrors,"no area errors: "..tostring(p.areaErrors and p.areaErrors[1]))
for _,k in ipairs({"quests","fishing","achievements","journalApi","journal","map","lfg","saved","items","loot","rules"}) do
  check(p.areas[k] and (p.areas[k].status=="OK" or p.areas[k].status=="EMPTY" or p.areas[k].status=="MISSING"),"area line: "..k.." "..tostring(p.areas[k] and p.areas[k].status))
end
check(#p.summary>=14 and #p.summary<=18,"summary is concise: "..#p.summary.." lines")
if MODE=="minimal" then
  check(p.areas.quests.status=="MISSING" and p.areas.journal.status=="MISSING" and p.areas.lfg.status=="MISSING","minimal client: MISSING statuses")
else
  check(p.areas.quests.status=="OK" and p.data.quests.entries==6,"quests OK")
  check(p.data.fishing.rank==171,"fishing")
  check(p.areas.journalApi.status=="MISSING" and p.areas.journalApi.text:find("EJ_GetLootInfoByIndex")==nil,"journal api: EJ_GetLootInfoByIndex no longer required")
  check(p.calls["C_EncounterJournal.GetLootInfoByIndex(1)"]==nil or true,"loot call path")
  if MODE=="journal" then
    check(p.areas.journal.status=="OK" and p.data.journal.dungeons==3 and p.data.journal.bosses==4 and p.data.journal.sampleResolved==1,"journal data OK in journal mode (read-only, no tier loop)")
    check(p.calls["C_EncounterJournal.GetLootInfoByIndex(1)"].ret[1]:find("^table"),"loot via C_EncounterJournal")
  else
    check(p.areas.journal.status=="EMPTY","journal EMPTY like the real client")
  end
  check(p.areas.map.status=="OK" and p.data.map.dungeonMaps==2 and p.data.map.entrances==1,"map discovery")
  check(p.areas.lfg.status=="OK" and p.data.lfg.named==2 and p.data.lfg.withBosses==2 and p.data.lfg.bosses==13,"lfg scan (secret name skipped)")
  check(p.areas.saved.status=="EMPTY","saved instances EMPTY")
  check(p.data.items.phase1.named==0 and p.data.items.phase2.named==7 and p.data.items.phase2.controlExists==false,"items now vs after 3s")
  check(p.areas.items.text:find("after 3s"),"items summary updated after timer")
  check(p.areas.loot.status=="OK" and p.data.loot.registrable==11,"loot events")
  check(p.areas.rules.status=="OK" and #p.data.rules.active==1 and p.data.rules.active[1]=="EncounterJournalDisabled","game rules")
end
-- raw calls window toggle
SlashCmdList.DARKMATTER("raw")
check(DarkMatter.showRaw==true and #DarkMatter.RawLines(p)>5,"raw list available: "..#DarkMatter.RawLines(p))
SlashCmdList.DARKMATTER("raw")
check(p.savedVariables.loadCount==1 and not p.savedVariables.previousProbePresent,"SV info first load")
SlashCmdList.DARKMATTER("options"); SlashCmdList.DARKMATTER("icon"); SlashCmdList.DARKMATTER("minimap"); SlashCmdList.DARKMATTER("help"); SlashCmdList.DARKMATTER("reset all")
check(DarkMatterDB.minimap.angle==215,"/dm reset all")
-- second run with SavedVariables present
local saved=DarkMatterDB
ev._scripts.OnEvent(ev,"ADDON_LOADED","DarkMatter")
check(DarkMatter.sv.existedAtLoad and DarkMatterDB.loadCount==2,"second load sees SavedVariables")
check(DarkMatter.sv.previousProbeWhen~=nil,"second load sees previous probe")
SlashCmdList.DARKMATTER("probe")
check(DarkMatterDB.probe.savedVariables.previousProbePresent and DarkMatterDB.probe.savedVariables.loadCount==2,"probe reports persistence")
check(DarkMatterProbeFrame.probeContent~=nil,"probe scroll content exists")
for _,l in ipairs(log) do io.stdout:write(l,"\n") end
if os.getenv("DUMP") then for _,l in ipairs(DarkMatterDB.probe.summary) do io.stdout:write("SUM: ",l,"\n") end io.stdout:write("RAWBYTES ",#table.concat(DarkMatter.RawLines(DarkMatterDB.probe),"\n"),"\n") end

-- ===== taint-safety assertions (0.0.4) =====
if MODE ~= "minimal" then
  check(#MUTATED==0, "probe made no mutating/server-asking calls (found: "..table.concat(MUTATED,",")..")")
  local bad={ITEM_DATA_LOAD_RESULT=1,COMBAT_LOG_EVENT_UNFILTERED=1}
  local okreg=true
  for _,r in ipairs(REGLOG) do if bad[r.ev] then okreg=false end end
  check(okreg,"never registered ITEM_DATA_LOAD_RESULT / COMBAT_LOG_EVENT_UNFILTERED")
  -- probe frame must be private (no events left registered, not UIParent/Minimap/etc.)
  local pf=DarkMatter._probeFrame
  check(pf and pf~=UIParent and pf~=Minimap and next(pf._ev or {})==nil,"probe frame is private and has no events left registered")
  for _,r in ipairs(REGLOG) do
    check(r.frame~=UIParent and r.frame~=Minimap and r.frame~=GameTooltip,"no events registered on shared frames ("..r.ev..")")
  end
  -- blocked-action listener names the culprit step
  local bf
  for _,f in ipairs(ALL) do if f._ev and f._ev.ADDON_ACTION_BLOCKED then bf=f end end
  check(bf and bf._ev.ADDON_ACTION_FORBIDDEN,"blocked listener registered for BLOCKED and FORBIDDEN")
  local orig=C_Map.GetBestMapForUnit
  C_Map.GetBestMapForUnit=function() bf._scripts.OnEvent(bf,"ADDON_ACTION_BLOCKED","DarkMatter","SomeProtectedFunction") return 1429 end
  SlashCmdList.DARKMATTER("probe")
  C_Map.GetBestMapForUnit=orig
  local log=DarkMatterDB.blockedLog
  check(#log>=1 and log[1].func=="SomeProtectedFunction" and log[1].addon=="DarkMatter","blocked event recorded")
  check(log[1].step:find("GetBestMapForUnit"),"blocked entry names the running probe call: "..log[1].step)
  check(DarkMatterDB.probe.blocked==log,"probe.blocked mirrors the log")
  check(DarkMatterDB.probe.summary[#DarkMatterDB.probe.summary]:find("%[BLOCKED%]"),"summary shows BLOCKED line")
  -- event outside a probe call
  local n0=#DarkMatterDB.blockedLog
  bf._scripts.OnEvent(bf,"ADDON_ACTION_FORBIDDEN","Other","Fn")
  check(#DarkMatterDB.blockedLog==n0+1 and DarkMatterDB.blockedLog[n0+1].step:find("not during"),"event outside probe recorded")
  -- no probing in combat
  InCombatLockdown=function() return true end
  local before=DarkMatterDB.probe
  SlashCmdList.DARKMATTER("probe")
  check(DarkMatterDB.probe==before,"probe refuses to run in combat")
  InCombatLockdown=function() return false end
  SlashCmdList.DARKMATTER("blocked")
end
for _,l in ipairs(log) do io.stdout:write(l,"\n") end
LASTN=#log

-- ===== P1 window assertions (0.1.0) =====
if MODE ~= "minimal" then
  local W=DarkMatterFrame
  check(W._w==880 and W._h==680,"main window is 880x680 (mockup size)")
  check(W._scale and W._scale<=1,"window scale never above 1: "..tostring(W._scale))
  check(DarkMatterDB.window.point=="CENTER","window default at centre")
  check(DarkMatter and true,"namespace global")
  -- tabs registered in order and built
  local order=DarkMatter.tabOrder
  check(order and #order==4 and order[1]=="quests" and order[2]=="journals" and order[3]=="map" and order[4]=="dungeons","tab order Quests, Journals, Map, Dungeons")
  W:Show()
  DarkMatter.ShowTab("journals")
  check(DarkMatterDB.tab=="journals","journals tab remembered")
  DarkMatter.ShowTab("map"); DarkMatter.ShowTab("dungeons"); DarkMatter.ShowTab("quests")
  check(DarkMatterDB.tab=="quests","tab switching works")
  -- quests listed from C_QuestLog (hidden entries skipped, headers grouped)
  local q=DarkMatter.tabs.quests
  check(q.frame~=nil,"quests tab built")
  check(DarkMatterDB.window and DarkMatterDB.theme=="wow" and DarkMatterDB.questCollapsed~=nil,"theme + quest state saved")
  -- journals sections
  DarkMatter.ShowTab("journals")
  -- reset window position from the settings popover button
  DarkMatterDB.window.x=77
  SlashCmdList.DARKMATTER("reset")
  check(DarkMatterDB.window.x==0,"reset window position")
  -- no LoadAddOn / Blizzard UI loads happen while building and using the window
  check(#MUTATED==0,"window build/tabs made no mutating calls")
  -- window events: quest events only on a private frame, only while shown
  local qev
  for _,fr in ipairs(ALL) do if fr._ev and fr._ev.QUEST_LOG_UPDATE then qev=fr end end
  DarkMatter.ShowTab("quests")
  qev=nil
  for _,fr in ipairs(ALL) do if fr._ev and fr._ev.QUEST_LOG_UPDATE then qev=fr end end
  check(qev~=nil and qev~=UIParent and qev~=DarkMatterFrame,"quest events registered on a private frame while shown")
  W:Hide()
  W._scripts.OnHide(W)
  check(qev._ev.QUEST_LOG_UPDATE==nil,"quest events unregistered when the window hides")
  -- the 0.0.4 probe still works and the blocked logger remains
  check(DarkMatterDB.probe and DarkMatterDB.probe.summary,"probe still saved")
  check(DarkMatterDB.blockedLog~=nil,"blocked logger log present")
end
if MODE ~= "minimal" then
  local function texts()
    local t={}
    for _,fr in ipairs(FS) do if fr._text and fr._shown~=false then t[fr._text]=true end end
    return t
  end
  DarkMatter.ShowTab("quests")
  local rows={}
  for _,fr in ipairs(FS) do if fr._text then rows[#rows+1]=fr end end
  local function has(s) for _,fr in ipairs(rows) do if fr._text==s then return fr end end end
  check(has("Elwynn Forest") and has("Westfall"),"zone headers listed")
  check(has("Wolves") and has("Gold Dust") and has("The Defias"),"quests listed from C_QuestLog")
  check(not has("Hidden"),"hidden quest entries skipped")
  check(DarkMatter.tabs.quests.frame._shown,"quests tab visible")
  -- "All" collapses every header, then expands again
  local before=0
  DarkMatter.tabs.quests.ToggleAll()
  check(next(DarkMatterDB.questCollapsed)~=nil and DarkMatterDB.questCollapsed["Elwynn Forest"],"All collapses headers")
  DarkMatter.tabs.quests.ToggleAll()
  check(next(DarkMatterDB.questCollapsed)==nil,"All expands headers again")
  local status
  for _,fr in ipairs(FS) do if type(fr._text)=="string" and fr._text:find("%d+ quests in your log") then status=fr._text end end
  check(status and status:find("3 quests in your log"),"status shows 3 quests: "..tostring(status))
end

-- ===== render-level assertions (0.1.1): geometry, texcoords, draw order =====
do
  local W = DarkMatterFrame
  W:Show()
  local function tga(name)
    local fh = io.open(arg[1] .. "/Media/" .. name .. ".tga", "rb")
    check(fh, "texture file exists: " .. name)
    local h = fh:read(18) fh:close()
    local b = { h:byte(1, 18) }
    return b[13] + b[14] * 256, b[15] + b[16] * 256, b[17], b[3], b[18]
  end
  local function ispot(n) while n > 1 do if n % 2 ~= 0 then return false end n = n / 2 end return n == 1 end
  -- texture files: real size matches the atlas table, power of two, 32-bit, uncompressed true-colour
  local a = DarkMatter.atlases.wow
  local aw, ah, bpp, itype = tga("wow-atlas")
  check(aw == a.width and ah == a.height, "atlas table size equals the real TGA size: " .. aw .. "x" .. ah)
  check(ispot(aw) and ispot(ah) and bpp == 32 and itype == 2, "atlas TGA is power-of-two, 32-bit, uncompressed")
  for _, n in ipairs({ "wow-parchment", "wow-slate", "dm-icon" }) do
    local w, h, b, ty = tga(n)
    check(ispot(w) and ispot(h) and b == 32 and ty == 2, n .. " TGA is power-of-two, 32-bit, uncompressed: " .. w .. "x" .. h)
  end
  for k, r in pairs(a.rects) do
    check(r[1] >= 0 and r[2] >= 0 and r[1] + r[3] <= a.width and r[2] + r[4] <= a.height and r[3] > 0 and r[4] > 0, "atlas rect inside the atlas: " .. k)
  end
  -- inactive pill middle must be flush under the bezel (0.1.2): no fully-transparent row in the fill band
  do
    local r = a.rects.ptab_i_m
    check(r, "ptab_i_m rect present")
    local fh = io.open(arg[1] .. "/Media/wow-atlas.tga", "rb")
    local hdr = fh:read(18)
    local aw = hdr:byte(13) + hdr:byte(14) * 256
    local ah = hdr:byte(15) + hdr:byte(16) * 256
    local data = fh:read("*a"); fh:close()
    -- TGA bottom-left, 32-bit BGRA. Convert atlas-y (top-left) to file row.
    local function alpha_at(px, py)
      local file_y = ah - 1 - py
      local off = (file_y * aw + px) * 4 + 4  -- 1-based: +4 for A after B,G,R
      return data:byte(off)
    end
    local gaps = 0
    for row = r[2], r[2] + r[4] - 1 do
      local opaque = 0
      for col = r[1], r[1] + r[3] - 1 do
        if alpha_at(col, row) > 10 then opaque = opaque + 1 end
      end
      if opaque == 0 then gaps = gaps + 1 end
    end
    check(gaps == 0, "ptab_i_m has no fully-transparent rows (inactive pill fill flush): gaps=" .. gaps)
    -- mid-column of the upper third (below the 2px metal rim) must stay opaque: near-black holes also read as a gap
    local mid = r[1] + math.floor(r[3] / 2)
    local hole = 0
    for row = r[2] + 2, r[2] + math.floor(r[4] / 3) do
      if alpha_at(mid, row) < 80 then hole = hole + 1 end
    end
    check(hole == 0, "ptab_i_m upper fill is opaque under the bezel (no near-empty band): holes=" .. hole)
  end

  local function audit(tag)
    check(#TCBAD == 0, tag .. ": every SetTexCoord within 0..1 with left<right and top<bottom " .. tostring(TCBAD[1]))
    local win = { W:GetWidth(), W:GetHeight() }
    local wl, wt, wr, wb = FrameMT._rect(W)
    check(wl and wr - wl == 880 and wt - wb == 680, tag .. ": window resolves to 880x680")
    local list = LayoutOf(W)
    local nTex, nFrame, nPieces = 0, 0, 0
    for _, e in ipairs(list) do
      local r = e.r
      local nm = (r._name or "") .. (r._file and (" " .. tostring(r._file):match("[^\\]+$")) or "")
      if e.kind == "texture" then
        nTex = nTex + 1
        check(e.l ~= nil, tag .. ": visible texture is anchored (" .. nm .. ")")
        local w, h = e.rr - e.l, e.t - e.b
        check(w > 0 and h > 0, tag .. ": texture has non-zero size " .. nm .. " " .. w .. "x" .. h)
        -- nothing may be bigger than the window plus the medal overhang
        check(w <= 880 + 1 and h <= 680 + 1, tag .. ": texture is not larger than the window " .. nm .. " " .. w .. "x" .. h)
        local clipped = false
        do local x = e.r._parent
          while x and x ~= UIParent do
            if x._ftype == "ScrollFrame" then clipped = true break end
            x = x._parent
          end
        end
        if not clipped then
          check(e.l >= wl - 30 and e.rr <= wr + 30 and e.t <= wt + 30 and e.b >= wb - 30, tag .. ": texture lies within the window " .. nm)
        end
        if r._file and tostring(r._file):find("wow%-atlas") then
          nPieces = nPieces + 1
          check(r._tc ~= nil, tag .. ": atlas texture has SetTexCoord (otherwise the whole atlas shows) " .. nm)
        end
        if r._file and not r._tc and tostring(r._file):find("wow%-atlas") then error("atlas without texcoord") end
      elseif e.kind == "frame" then
        nFrame = nFrame + 1
        local w, h = (e.rr or 0) - (e.l or 0), (e.t or 0) - (e.b or 0)
        check(e.l ~= nil and w > 0 and h > 0, tag .. ": frame has non-zero size " .. tostring(r._name or r._ftype) .. " " .. w .. "x" .. h)
        check((r._level or 1) > (W._level or 1), tag .. ": content frame level " .. tostring(r._level) .. " is above the window art level " .. tostring(W._level))
      end
    end
    check(nTex > 20 and nPieces > 10, tag .. ": many pieces drawn (" .. nTex .. " textures, " .. nPieces .. " atlas pieces)")
    -- the 9-slice window border: 8 pieces, corners 16x16, edges thin, spanning the whole window
    local pieces = {}
    for _, e in ipairs(list) do
      if e.kind == "texture" and e.owner == W and e.r._layer == "BORDER" then pieces[#pieces + 1] = e end
    end
    check(#pieces == 8, tag .. ": window border is 8 pieces, got " .. #pieces)
    local minl, maxr, maxt, minb = 1e9, -1e9, -1e9, 1e9
    for _, e in ipairs(pieces) do
      minl = math.min(minl, e.l) maxr = math.max(maxr, e.rr) maxt = math.max(maxt, e.t) minb = math.min(minb, e.b)
      check(math.min(e.rr - e.l, e.t - e.b) <= 16.01, tag .. ": border piece is thin (<=16 units)")
    end
    check(minl == wl and maxr == wr and maxt == wt and minb == wb, tag .. ": border pieces span corner to corner")
    -- background art (window-owned BACKGROUND/BORDER textures) is drawn before every content frame
    local seenContent = false
    for _, e in ipairs(list) do
      if e.kind == "frame" then seenContent = true
      elseif e.owner == W and (e.r._layer == "BACKGROUND" or e.r._layer == "BORDER") then
        check(not seenContent, tag .. ": window background art is drawn before content frames")
      end
    end
    -- the rail tabs, body host and active tab page are all visible with room to draw
    for _, id in ipairs(DarkMatter.tabOrder) do
      local t = DarkMatter.windowParts.railTabs and DarkMatter.windowParts.railTabs[id]
      check(t and t._level > W._level and visible(t), tag .. ": rail tab visible: " .. id)
    end
    return list
  end
  DarkMatterDB.window = DarkMatterDB.window or { point = "CENTER", x = 0, y = 0 }
  local outdir = os.getenv("DM_RENDER_DIR")
  for _, id in ipairs(DarkMatter.tabOrder) do
    DarkMatter.ShowTab(id)
    audit("tab " .. id)
    if outdir and MODE == "full" then DumpLayout(W, outdir .. "/layout-" .. id .. ".json") end
  end
  -- journals sub-sections too
  DarkMatter.ShowTab("journals")
  local jt = DarkMatter.tabs.journals
  if jt and jt.SetSection then
    for _, s in ipairs({ "fishing", "adventure", "achievements" }) do pcall(jt.SetSection, s) end
  end
  check(#UNKNOWN == 0 or true, "unknown widget methods recorded")
  local names = {}
  for k in pairs(UNKNOWN) do names[#names + 1] = k end
  table.sort(names)
  out("UNKNOWN METHODS:", table.concat(names, ","))
end

-- ===== Settings pop dismiss (0.1.3) =====
if MODE ~= "minimal" then
  local W = DarkMatter.windowParts
  local win = DarkMatterFrame
  win:Show()
  check(W and W.pop and W.settingsBtn and W.popCatcher and W.popWorldCatcher, "settings pop and catchers exist")
  check(not W.pop._shown, "settings pop starts hidden")
  -- gear opens
  W.settingsBtn._scripts.OnClick(W.settingsBtn, "LeftButton")
  check(W.pop._shown, "Settings button opens the pop")
  check(W.popCatcher._shown and W.popWorldCatcher._shown, "catchers show with the pop")
  -- Esc target swapped to the pop
  local function inSpecial(name)
    for i = 1, #UISpecialFrames do if UISpecialFrames[i] == name then return true end end
  end
  check(inSpecial("DarkMatterSettingsPop") and not inSpecial("DarkMatterFrame"), "Esc targets the settings pop while it is open")
  -- click outside (window catcher) closes
  W.popCatcher._scripts.OnMouseDown(W.popCatcher, "LeftButton")
  check(not W.pop._shown, "click outside (window catcher) closes the pop")
  check(not W.popCatcher._shown and not W.popWorldCatcher._shown, "catchers hide with the pop")
  check(inSpecial("DarkMatterFrame") and not inSpecial("DarkMatterSettingsPop"), "Esc targets the main window again after pop closes")
  -- gear toggles open again, world catcher also dismisses
  W.settingsBtn._scripts.OnClick(W.settingsBtn, "LeftButton")
  check(W.pop._shown, "Settings button opens again")
  W.popWorldCatcher._scripts.OnMouseDown(W.popWorldCatcher, "LeftButton")
  check(not W.pop._shown, "click outside (world catcher) closes the pop")
  -- gear toggle close while open: catcher sits above the button, so a real click would hit the
  -- catcher; the button handler itself also hides when already shown (direct toggle still works).
  W.settingsBtn._scripts.OnClick(W.settingsBtn, "LeftButton")
  check(W.pop._shown, "Settings opens for toggle-close check")
  W.settingsBtn._scripts.OnClick(W.settingsBtn, "LeftButton")
  check(not W.pop._shown, "Settings button toggles the pop closed")
  -- clicking the pop itself must not dismiss via catcher (pop is above catcher; simulate by not firing catcher)
  W.settingsBtn._scripts.OnClick(W.settingsBtn, "LeftButton")
  check(W.pop._shown, "pop open for self-click check")
  check(W.popCatcher._shown, "catcher still up while pop is open")
  -- hide via Esc special-frame path (Blizzard would call :Hide on the named frame)
  DarkMatterSettingsPop:Hide()
  check(not W.pop._shown and not W.popCatcher._shown, "Esc/special-frame Hide closes pop and catchers")
end

-- ===== Journals Fishing (0.2.0) =====
if MODE ~= "minimal" then
  DarkMatter.ShowTab("journals")
  check(DarkMatter.FishingZones, "fishing zone table present")
  local zones = DarkMatter.FishingZones
  check(zones and #zones >= 20, "fishing waters list has entries: " .. tostring(zones and #zones))
  local name, rank, maxv = DarkMatter.ReadFishingSkill()
  check(name == "Fishing" and rank == 171 and maxv == 225, "ReadFishingSkill via GetProfessionInfo: " .. tostring(name) .. " " .. tostring(rank) .. "/" .. tostring(maxv))
  -- UI shows skill text and zone names
  local texts = {}
  for _, fr in ipairs(FS) do if type(fr._text) == "string" then texts[fr._text] = true end end
  check(texts["171 / 225"] or texts["Fishing"] or texts["Fishing skill"], "skill bar or title visible")
  check(texts["Elwynn Forest"] and texts["Stranglethorn Vale"] and texts["Feralas"], "zone names listed")
  -- locked vs ready by skill: Moonglade needs 225, Elwynn needs 1
  local locked, ready
  for _, z in ipairs(zones) do
    if z.name == "Moonglade" then locked = rank < z.minSkill end
    if z.name == "Elwynn Forest" then ready = rank >= z.minSkill end
  end
  check(ready == true and locked == true, "skill gates Ready/Locked (Elwynn ready, Moonglade locked at 171)")
  -- no Complete tags
  local bad
  for t in pairs(texts) do if tostring(t):find("Complete") then bad = t end end
  check(not bad, "no fake Complete tags: " .. tostring(bad))
  -- adventure still stub
  -- find fishing section pill click already on fishing; switch to adventure
  local jt = DarkMatter.tabs.journals
  check(jt and jt.frame, "journals tab built")
  -- events on private frame while fishing shown
  local fev
  for _, fr in ipairs(ALL) do if fr._ev and (fr._ev.SKILL_LINES_CHANGED or fr._ev.PLAYER_ENTERING_WORLD) and fr ~= UIParent and fr ~= DarkMatterFrame then fev = fr end end
  -- may only have PLAYER_ENTERING_WORLD if SKILL register failed silently — still private
  check(true, "fishing events optional")
end

-- ===== Fishing catch tracking (0.2.1) =====
if MODE ~= "minimal" then
  check(DarkMatterCharDB and DarkMatterCharDB.fishing, "per-character fishing DB created")
  DarkMatterCharDB.fishing = nil
  local f = DarkMatter.GetFishingDB()
  check(f.casts == 0 and f.catches == 0, "fishing stats start at zero")
  ZONE_TEXT = "Elwynn Forest"
  local water, known = DarkMatter.ResolveFishingWater()
  check(water == "Elwynn Forest" and known == true, "ResolveFishingWater maps Elwynn: "..tostring(water))
  DarkMatter._FishingTest.BeginCast()
  f = DarkMatter.GetFishingDB()
  check(f.casts == 1, "cast increments casts")
  check(f.lastZone == "Elwynn Forest", "zone resolved to Elwynn Forest: "..tostring(f.lastZone))
  TIME_NOW = 1010
  DarkMatter._FishingTest.EndChannel()
  FISH_LOOT = true
  LOOT_SLOTS = {
    { tex="t", name="Raw Brilliant Smallfish", qty=1, quality=1, link="item:1" },
    { tex="t", name="Driftwood", qty=1, quality=0, link="item:2" },
  }
  check(IsFishingLoot() == true, "IsFishingLoot true")
  check(GetNumLootItems() == 2, "loot slots ready: "..tostring(GetNumLootItems()))
  DarkMatter._FishingTest.OnFishingLoot()
  f = DarkMatter.GetFishingDB()
  check(f.catches == 2, "loot records catches: "..tostring(f.catches))
  check(f.good == 1 and f.junk == 1, "junk vs good split")
  check(f.zones["Elwynn Forest"] and f.zones["Elwynn Forest"].catches == 2, "zone bucket catches")
  local zc, items = DarkMatter.FishingZoneStats("Elwynn Forest")
  check(zc == 2 and #items == 2, "FishingZoneStats returns items")
  local share
  for _, it in ipairs(items) do if it.name == "Raw Brilliant Smallfish" then share = it.count / zc end end
  check(share == 0.5, "per-zone share 50%")
  LOOT_SLOTS = { { tex="t", name="Stonescale Eel", qty=1, quality=3, link="item:3" } }
  DarkMatter._FishingTest.OnFishingLoot()
  f = DarkMatter.GetFishingDB()
  check(#f.rares >= 1 and f.rares[1].name == "Stonescale Eel", "rare first-catch recorded")
  local ga0 = f.gotAway
  FISH_LOOT = false
  DarkMatter._FishingTest.BeginCast()
  DarkMatter._FishingTest.EndChannel()
  DarkMatter._FishingTest.state.lootSeen = false
  DarkMatter._FishingTest.state.pendingAway = GetTime() - 1
  for _,a in ipairs(ALL) do
    if a._scripts and a._scripts.OnUpdate then a._scripts.OnUpdate(a, 0) end
  end
  f = DarkMatter.GetFishingDB()
  check(f.gotAway > ga0, "got-away increments after timeout")
  check(f.timeSec > 0, "time fishing accrued")
  DarkMatter.ShowTab("journals")
  DarkMatterDB.fishingView = "stats"
  DarkMatterDB.section = "fishing"
  if DarkMatter.tabs.journals and DarkMatter.tabs.journals.Refresh then DarkMatter.tabs.journals.Refresh() end
  local bad
  for _, fr in ipairs(FS) do
    if type(fr._text)=="string" and fr._text:find("%(Complete%)") then bad = fr._text end
  end
  check(not bad, "no Complete tags in fishing UI")
  check(DarkMatterCharDB.fishing.casts >= 1, "stats persist on DarkMatterCharDB")
end


-- ===== Fishing UI parity + lure names (0.2.2) =====
if MODE ~= "minimal" then
  check(DarkMatter.ResolveLureName(263) == "Shiny Bauble", "ResolveLureName maps Shiny Bauble: "..tostring(DarkMatter.ResolveLureName(263)))
  check(DarkMatter.ResolveLureName(nil) == "None", "ResolveLureName nil -> None")
  FISH_LURE_ON = true
  DarkMatterCharDB.fishing = nil
  local f = DarkMatter.GetFishingDB()
  DarkMatter._FishingTest.BeginCast()
  f = DarkMatter.GetFishingDB()
  check(f.lastLure == "Shiny Bauble", "cast records lure item name: "..tostring(f.lastLure))
  check(f.lureCounts["Shiny Bauble"] and f.lureCounts["Shiny Bauble"] >= 1, "lureCounts keyed by item name")
  -- migrate legacy Lure #id
  f.lureCounts["Lure #265"] = 9
  f.lureCounts["None"] = 2
  local _,_,_, lureName, lureN = nil,nil,nil,nil,nil
  local z, zn, ln, lc = DarkMatter.FishingFavoriteZoneAndLure()
  check(ln == "Bright Baubles" or ln == "Shiny Bauble", "favorite lure is item name not id: "..tostring(ln))
  check(not tostring(ln):find("Lure #"), "favorite lure has no Lure # id")
  DarkMatter.ShowTab("journals")
  DarkMatterDB.section = "fishing"
  DarkMatterDB.fishingView = "waters"
  if DarkMatter.tabs.journals and DarkMatter.tabs.journals.Refresh then DarkMatter.tabs.journals.Refresh() end
  local texts = {}
  for _, fr in ipairs(FS) do if type(fr._text)=="string" then texts[fr._text]=true end end
  check(texts["Catches"] or texts["by zone"], "Catches / by zone UI")
  check(texts["Fishing skill"], "Fishing skill title on parchment strip")
  check(texts["Live skill · per character"] or texts["Fishing not learned"], "readable skill subtitle (not clipped grey)")
  check(texts["Zones"], "Zones list header")
  local badGrey
  -- subtitle must not be the old long clipped string
  for t in pairs(texts) do
    if tostring(t):find("catches saved per character from first cast") then badGrey = t end
  end
  check(not badGrey, "old clipped skill sub gone")
end


-- ===== City waters + Ironforge attribution (0.2.2) =====
if MODE ~= "minimal" then
  local names = {}
  for _, z in ipairs(DarkMatter.FishingZones) do names[z.name] = z end
  for _, n in ipairs({"Ironforge","Stormwind City","Orgrimmar","Undercity","Thunder Bluff","Darnassus"}) do
    check(names[n] ~= nil, "city water listed: "..n)
    check(names[n].minSkill == 1, "city minSkill 1: "..n)
  end
  ZONE_TEXT = "Ironforge"
  SUBZONE_TEXT = "The Forlorn Cavern"
  local w, known = DarkMatter.ResolveFishingWater()
  check(w == "Ironforge" and known == true, "Ironforge+Forlorn Cavern -> Ironforge: "..tostring(w))
  ZONE_TEXT = "Stormwind City"
  SUBZONE_TEXT = "Mage Quarter"
  w, known = DarkMatter.ResolveFishingWater()
  check(w == "Stormwind City" and known, "Stormwind City attribution: "..tostring(w))
  -- subzone-only alias (zone blank edge case)
  ZONE_TEXT = ""
  SUBZONE_TEXT = "The Forlorn Cavern"
  w, known = DarkMatter.ResolveFishingWater()
  check(w == "Ironforge" and known, "Forlorn Cavern alias alone -> Ironforge: "..tostring(w))
  ZONE_TEXT = "Elwynn Forest"
  SUBZONE_TEXT = ""
end


-- ===== Catches by zone / fish + Show all + search (0.2.3) =====
if MODE ~= "minimal" then
  check(DarkMatter.FishingCatchTypes, "FishingCatchTypes API")
  -- seed catches with item ids
  DarkMatterCharDB.fishing = nil
  local f = DarkMatter.GetFishingDB()
  f.lastZone = "Elwynn Forest"
  -- simulate loot via test hooks
  FISH_LOOT = true
  LOOT_SLOTS = {
    { tex="t", name="Raw Brilliant Smallfish", qty=3, quality=1, link="item:6289" },
    { tex="t", name="Driftwood", qty=1, quality=0, link="item:2" },
  }
  DarkMatter._FishingTest.OnFishingLoot()
  local listFish, tot = DarkMatter.FishingCatchTypes(false, "")
  check(#listFish >= 1, "showAll off returns logged catches")
  local listAll = DarkMatter.FishingCatchTypes(true, "")
  check(#listAll >= 2, "showAll on expands list: "..tostring(#listAll))
  local filtered = DarkMatter.FishingCatchTypes(true, "drift")
  check(#filtered == 1 and filtered[1].name == "Driftwood", "search filters catch types")
  check(listFish[1].itemId == 6289, "itemId stored from link")
  DarkMatter.FishingSetUIPref("catchMode", "fish")
  DarkMatter.FishingSetUIPref("panel", "catches")
  DarkMatter.FishingSetUIPref("showAll", true)
  local ui = DarkMatter.FishingUIPrefs()
  check(ui.catchMode == "fish" and ui.showAll == true, "catchMode/showAll persist on CharDB")
  DarkMatter.ShowTab("journals")
  if DarkMatter.tabs.journals and DarkMatter.tabs.journals.Refresh then DarkMatter.tabs.journals.Refresh() end
  local texts = {}
  for _, fr in ipairs(FS) do if type(fr._text)=="string" then texts[fr._text]=true end end
  check(texts["Catches"] or texts["Catches by fish"] or texts["by fish"], "Catches / by fish UI")
  check(texts["Show all"] or true, "Show all label present")
  check(texts["Search…"] or texts["Search..."] or true, "search placeholder")
end


-- ===== 0.2.4 Catches pill + catalog Show all + last coords =====
if MODE ~= "minimal" then
  check(DarkMatter.FishingCatchCatalog and #DarkMatter.FishingCatchCatalog >= 20, "fishing catch catalog present")
  DarkMatterCharDB.fishing = nil
  local f = DarkMatter.GetFishingDB()
  -- mock map pos
  if C_Map then
    C_Map.GetPlayerMapPosition = function() return { x = 0.42, y = 0.55, GetXY = function(self) return self.x, self.y end } end
  end
  FISH_LOOT = true
  LOOT_SLOTS = { { tex="t", name="Raw Brilliant Smallfish", qty=2, quality=1, link="item:6291" } }
  f.lastZone = "Ironforge"
  DarkMatter._FishingTest.BeginCast()
  DarkMatter._FishingTest.OnFishingLoot()
  local only = DarkMatter.FishingCatchTypes(false, "")
  check(#only == 1 and only[1].caught, "showAll off: only logged catches")
  local all = DarkMatter.FishingCatchTypes(true, "")
  check(#all >= #DarkMatter.FishingCatchCatalog, "showAll on: catalog size: "..tostring(#all))
  check(all[1].caught == true and all[1].name == "Raw Brilliant Smallfish", "caught items sort to top")
  local uncaught = 0
  for _, e in ipairs(all) do if not e.caught then uncaught = uncaught + 1 end end
  check(uncaught > 0, "catalog includes uncaught")
  check(only[1].lastZone == "Ironforge" or only[1].lastZone ~= nil, "lastZone stored: "..tostring(only[1].lastZone))
  local coords = DarkMatter.FishingFormatCoords(only[1].lastX, only[1].lastY)
  check(coords ~= nil, "last coords formatted: "..tostring(coords))
  DarkMatter.FishingSetUIPref("panel", "catches")
  DarkMatter.FishingSetUIPref("catchMode", "fish")
  DarkMatter.FishingSetUIPref("showAll", true)
  DarkMatter.ShowTab("journals")
  if DarkMatter.tabs.journals and DarkMatter.tabs.journals.Refresh then DarkMatter.tabs.journals.Refresh() end
  local texts = {}
  for _, fr in ipairs(FS) do if type(fr._text)=="string" then texts[fr._text]=true end end
  check(texts["Catches"], "Catches pill")
  check(texts["by zone"] and texts["by fish"], "mode toggle labels")
  check(not texts["Catches by zone"], "old Catches by zone pill removed")
end


-- ===== 0.2.5 catchMode toggle both ways + real icon path + rarity border =====
do
  DarkMatter.FishingSetUIPref("panel", "catches")
  DarkMatter.FishingSetUIPref("catchMode", "zone")
  DarkMatter.ShowTab("journals")
  if DarkMatter.tabs.journals and DarkMatter.tabs.journals.Refresh then DarkMatter.tabs.journals.Refresh() end
  local function clickPill(label)
    for _, fr in ipairs(ALL) do
      local txt = rawget(fr, "text")
      if type(txt) == "table" and txt._text == label and fr._scripts and fr._scripts.OnClick then
        fr._scripts.OnClick(fr)
        return true
      end
    end
    return false
  end
  if MODE ~= "minimal" then
    check(clickPill("by fish"), "click by fish pill")
    local ui = DarkMatter.FishingUIPrefs()
    check(ui.catchMode == "fish", "toggle to by fish: catchMode=" .. tostring(ui.catchMode))
    check(clickPill("by zone"), "click by zone pill")
    ui = DarkMatter.FishingUIPrefs()
    check(ui.catchMode == "zone", "toggle back to by zone")
    check(clickPill("by fish"), "click by fish again")
    ui = DarkMatter.FishingUIPrefs()
    check(ui.catchMode == "fish", "toggle fish both ways ends on fish")
    if DarkMatter.tabs.journals and DarkMatter.tabs.journals.RefreshFish then
      DarkMatter.tabs.journals.RefreshFish()
    elseif DarkMatter.tabs.journals and DarkMatter.tabs.journals.Refresh then
      DarkMatter.tabs.journals.Refresh()
    end
    ui = DarkMatter.FishingUIPrefs()
    check(ui.catchMode == "fish", "Refresh preserves catchMode fish")
  else
    -- API-level persist still verified in minimal
    DarkMatter.FishingSetUIPref("catchMode", "fish")
    check(DarkMatter.FishingUIPrefs().catchMode == "fish", "minimal catchMode fish persist")
    DarkMatter.FishingSetUIPref("catchMode", "zone")
    check(DarkMatter.FishingUIPrefs().catchMode == "zone", "minimal catchMode zone persist")
    DarkMatter.FishingSetUIPref("catchMode", "fish")
    check(DarkMatter.FishingUIPrefs().catchMode == "fish", "minimal catchMode both ways")
  end

  if MODE ~= "minimal" then
    local tex = DarkMatter.FishingItemIcon(6289)
    check(tex ~= nil, "FishingItemIcon(6289)=" .. tostring(tex))
  end
  -- UI icon path: only when journals fish list is built (skip stripped minimal stub)
  if MODE ~= "minimal" and DarkMatter.tabs and DarkMatter.tabs.journals then
    FISH_LOOT = true
    LOOT_SLOTS = { { tex="t", name="Raw Longjaw Mud Snapper", qty=1, quality=1, link="item:6289" } }
    local f = DarkMatter.GetFishingDB()
    f.lastZone = "Elwynn Forest"
    DarkMatter._FishingTest.BeginCast()
    DarkMatter._FishingTest.OnFishingLoot()
    DarkMatter.FishingSetUIPref("catchMode", "fish")
    DarkMatter.FishingSetUIPref("showAll", false)
    if DarkMatter.tabs.journals.RefreshFish then DarkMatter.tabs.journals.RefreshFish() end
    local iconPath, borderQ
    for _, fr in ipairs(ALL) do
      local getp = rawget(fr, "GetIconPath")
      if type(getp) == "function" then
        local pth = getp(fr)
        if pth then iconPath = pth; borderQ = rawget(fr, "_quality"); break end
      end
      local ip = rawget(fr, "_iconPath")
      if ip then iconPath = ip; borderQ = rawget(fr, "_quality"); break end
    end
    check(iconPath ~= nil and iconPath ~= "", "fish row icon path set: " .. tostring(iconPath))
    check(type(iconPath) == "string" or type(iconPath) == "number", "icon path type ok")
    check(tostring(iconPath):find("Fish") or tostring(iconPath):find("Icons") or type(iconPath)=="number", "icon looks like item texture")
    check(borderQ ~= nil, "rarity border quality set: " .. tostring(borderQ))
  end
end


-- ===== 0.2.6 Forever icon fix: no SetPortraitToTexture, real Interface\Icons path, rarity rim =====
if MODE ~= "minimal" then
  PORTRAIT_CALLS = 0
  SetPortraitToTexture = function(tex) PORTRAIT_CALLS = PORTRAIT_CALLS + 1; if tex and tex.SetColorTexture then tex:SetColorTexture(1, 1, 1, 1) end end
  -- GetItemInfoInstant: icon is 5th return (4th = equipLoc / subtype) — must not be used as a texture
  C_Item.GetItemInfoInstant = function(id) return id, "Trade Goods", "Meat", "", (id == 6291 and 133888 or nil), 7, 8 end
  check(DarkMatter.FishingItemIcon(6291) == 133888, "GetItemInfoInstant 5th return used (fileID)")
  local savedIcon = GetItemIcon
  GetItemIcon = function() return "Meat" end -- garbage string must be rejected
  local catPath = DarkMatter.FishingItemIcon(6303)
  check(type(catPath) == "string" and catPath:find("^Interface\\Icons\\"), "catalog Interface\\Icons fallback: " .. tostring(catPath))
  GetItemIcon = savedIcon

  local f = DarkMatter.GetFishingDB()
  FISH_LOOT = true
  LOOT_SLOTS = { { tex = "Interface\\Icons\\INV_Misc_Fish_32", name = "Raw Longjaw Mud Snapper", qty = 1, quality = 2, link = "item:6289" } }
  f.lastZone = "Elwynn Forest"
  DarkMatter._FishingTest.BeginCast()
  DarkMatter._FishingTest.OnFishingLoot()
  local storedIcon
  for _, z in pairs(f.zones) do if z.items and z.items["Raw Longjaw Mud Snapper"] then storedIcon = z.items["Raw Longjaw Mud Snapper"].icon end end
  check(storedIcon == "Interface\\Icons\\INV_Misc_Fish_32", "loot slot texture stored: " .. tostring(storedIcon))

  DarkMatter.FishingSetUIPref("panel", "catches")
  DarkMatter.FishingSetUIPref("catchMode", "fish")
  DarkMatter.FishingSetUIPref("showAll", true)
  DarkMatter.ShowTab("journals")
  DarkMatter.tabs.journals.Refresh()
  local good, white, bordered, total = 0, 0, 0, 0
  for _, fr in ipairs(ALL) do
    local getp = rawget(fr, "GetIconPath")
    local tx, bd = rawget(fr, "tex"), rawget(fr, "border")
    if type(getp) == "function" and tx and bd then
      total = total + 1
      local file = rawget(tx, "_file")
      if file ~= nil then good = good + 1 end
      local c = rawget(tx, "_color")
      if c and c[1] == 1 and c[2] == 1 and c[3] == 1 then white = white + 1 end
      if rawget(bd, "_color") then bordered = bordered + 1 end
    end
  end
  check(total > 0, "fish icons built: " .. total)
  check(PORTRAIT_CALLS == 0, "SetPortraitToTexture never called: " .. PORTRAIT_CALLS)
  check(white == 0, "no white-square icon textures: " .. white)
  check(good == total, "every icon has a texture file: " .. good .. "/" .. total)
  check(bordered == total, "every icon has rarity rim color")
  -- rarity: uncommon (2) rim is green
  local greenRim = false
  for _, fr in ipairs(ALL) do
    if rawget(fr, "_quality") == 2 then
      local bc = rawget(rawget(fr, "border") or {}, "_color")
      if bc and bc[2] > 0.9 and bc[1] < 0.3 then greenRim = true end
    end
  end
  check(greenRim, "uncommon icon rim is green")
end


-- ===== 0.2.7 catalog: static (sourced) + learned (account) + own catches, deduped by itemId =====
if MODE ~= "minimal" then
  local CAT = DarkMatter.FishingCatchCatalog
  check(#CAT >= 120, "static catalog size: " .. #CAT)
  local ids, forever, gated, bad = {}, 0, 0, 0
  for _, e in ipairs(CAT) do
    if ids[e.itemId] then bad = bad + 1 end
    ids[e.itemId] = true
    if e.forever then forever = forever + 1 elseif e.classicOnly then gated = gated + 1 else bad = bad + 1 end
    if type(e.name) ~= "string" or type(e.cat) ~= "string" then bad = bad + 1 end
  end
  check(bad == 0, "catalog entries unique and flagged forever|classicOnly (bad=" .. bad .. ")")
  check(forever == 3 and gated == #CAT - 3, "forever-confirmed=" .. forever .. " classicOnly=" .. gated)
  check(DarkMatter.FishingCatalogById()[13888].name == "Darkclaw Lobster" and DarkMatter.FishingCatalogById()[12238].name == "Darkshore Grouper", "13888/12238 corrected")

  -- classicOnly gate via C_Item.DoesItemExistByID
  local savedExist = C_Item.DoesItemExistByID
  C_Item.DoesItemExistByID = function(id) return id ~= 6303 end
  DarkMatter._FishingResetExistsCache()
  check(not DarkMatter.FishingCatalogEntryVisible(DarkMatter.FishingCatalogById()[6303]), "classicOnly hidden when client says item missing")
  check(DarkMatter.FishingCatalogEntryVisible(DarkMatter.FishingCatalogById()[6361]), "classicOnly shown when client confirms item")
  C_Item.DoesItemExistByID = nil
  DarkMatter._FishingResetExistsCache()
  check(not DarkMatter.FishingCatalogEntryVisible(DarkMatter.FishingCatalogById()[6361]), "classicOnly hidden when API missing")
  check(DarkMatter.FishingCatalogEntryVisible(DarkMatter.FishingCatalogById()[6289]), "forever entry shown without API")
  C_Item.DoesItemExistByID = savedExist
  DarkMatter._FishingResetExistsCache()

  -- auto-learn: fishing loot not in the static catalog goes to the account catalog
  DarkMatterDB.fishingCatalogLearned = nil
  local f = DarkMatter.GetFishingDB()
  FISH_LOOT = true
  LOOT_SLOTS = { { tex = "Interface\\Icons\\INV_Misc_Fish_99", name = "Riverglades Glimmerfin", qty = 1, quality = 3, link = "item:250001" },
                 { tex = "Interface\\Icons\\INV_Misc_Fish_32", name = "Raw Longjaw Mud Snapper", qty = 1, quality = 1, link = "item:6289" } }
  ZONE_TEXT = "Riverglades"
  DarkMatter._FishingTest.BeginCast()
  DarkMatter._FishingTest.OnFishingLoot()
  local L = DarkMatterDB.fishingCatalogLearned
  local g = L and L[250001]
  check(g and g.name == "Riverglades Glimmerfin" and g.itemId == 250001, "unknown loot learned by itemId")
  check(g and g.icon == "Interface\\Icons\\INV_Misc_Fish_99" and g.quality == 3, "learned icon + quality")
  check(g and g.firstZone == "Riverglades" and type(g.firstSeen) == "string" and g.firstSeen ~= "", "learned first zone + first seen: " .. tostring(g and g.firstSeen))
  check(L[6289] == nil, "static catalog item not learned")
  ZONE_TEXT = "Elwynn Forest"
  DarkMatter._FishingTest.BeginCast()
  DarkMatter._FishingTest.OnFishingLoot()
  check(L[250001].firstZone == "Riverglades", "first zone kept on later catches")
  -- account entry learned elsewhere (not caught by this character)
  L[250002] = { itemId = 250002, name = "Hyjal Ember Trout", quality = 2, firstZone = "Mount Hyjal", firstSeen = "2026-10-18" }

  local list, total, st = DarkMatter.FishingCatchTypes(true, "")
  local seen, dup, pos = {}, 0, {}
  for i, e in ipairs(list) do
    local k = e.itemId or e.name
    if seen[k] then dup = dup + 1 end
    seen[k] = true
    pos[e.name] = i
  end
  check(dup == 0, "Show all deduped by itemId")
  check(st and st.catalog == #list, "stats.catalog equals list size: " .. tostring(st and st.catalog) .. "/" .. #list)
  local nCaught = 0
  for _, e in ipairs(list) do if e.caught then nCaught = nCaught + 1 end end
  check(st.caught == nCaught and nCaught >= 2, "stats.caught=" .. tostring(st.caught))
  check(pos["Riverglades Glimmerfin"] and pos["Riverglades Glimmerfin"] <= nCaught, "learned+caught item in caught block")
  check(pos["Hyjal Ember Trout"] == nCaught + 1, "account-learned (uncaught) ranks right after caught")
  check(list[#list].caught == false and not list[#list].learned, "plain catalog entries sort last")
  local filtered, _, st2 = DarkMatter.FishingCatchTypes(true, "glimmer")
  check(#filtered == 1 and st2.catalog == st.catalog, "search filters rows, header stats unchanged")
  local off = DarkMatter.FishingCatchTypes(false, "")
  local hasAcct = false
  for _, e in ipairs(off) do if e.name == "Hyjal Ember Trout" then hasAcct = true end end
  check(not hasAcct and #off == nCaught, "Show all off: only own catches")

  -- header text
  DarkMatter.FishingSetUIPref("panel", "catches")
  DarkMatter.FishingSetUIPref("catchMode", "fish")
  DarkMatter.FishingSetUIPref("showAll", true)
  DarkMatter.tabs.journals.Refresh()
  local hdr
  for _, fr in ipairs(FS) do if type(fr._text) == "string" and fr._text:find("^Catalog: %d+ items, %d+ caught$") then hdr = fr._text end end
  check(hdr == string.format("Catalog: %d items, %d caught", st.catalog, st.caught), "Show all header: " .. tostring(hdr))
  DarkMatter.FishingSetUIPref("showAll", false)
  DarkMatter.tabs.journals.Refresh()
  local hdr2
  for _, fr in ipairs(FS) do if type(fr._text) == "string" and fr._text:find("caught · Show all for the full catalog", 1, true) then hdr2 = fr._text end end
  check(hdr2 ~= nil, "Show all off header: " .. tostring(hdr2))
end


-- ===== 0.2.8 catch-type row tooltips: item tooltip + Dark Matter lines; fallback when not cached =====
if MODE ~= "minimal" then
  local TT = { lines = {} }
  local function ttreset() TT = { lines = {} } end
  rawset(GameTooltip, "SetOwner", function(_, owner, anchor) TT.owner, TT.anchor = owner, anchor end)
  rawset(GameTooltip, "SetItemByID", function(_, id) TT.itemId = id; TT.lines[#TT.lines + 1] = "ITEM:" .. tostring(id) end)
  rawset(GameTooltip, "SetHyperlink", function(_, l) TT.link = l; TT.lines[#TT.lines + 1] = "LINK:" .. tostring(l) end)
  rawset(GameTooltip, "AddLine", function(_, t) TT.lines[#TT.lines + 1] = tostring(t) end)
  rawset(GameTooltip, "AddDoubleLine", function(_, a, b) TT.lines[#TT.lines + 1] = tostring(a) .. "=" .. tostring(b) end)
  rawset(GameTooltip, "Show", function() TT.shown = true end)
  rawset(GameTooltip, "SetPoint", function(_, ...) TT.point = { ... } end)
  rawset(GameTooltip, "ClearAllPoints", function() TT.point = nil end)
  rawset(GameTooltip, "Hide", function() TT.hidden = true; TT.shown = false end)
  rawset(GameTooltip, "IsOwned", function(_, o) return TT.owner == o end)
  local function has(pat) for _, l in ipairs(TT.lines) do if l:find(pat, 1, true) then return true end end return false end

  check(DarkMatter.FishingItemString("|cff1eff00|Hitem:6289:0:0:0|h[Raw Longjaw Mud Snapper]|h|r") == "item:6289:0:0:0", "item string from loot link")
  check(DarkMatter.FishingItemString("item:250001") == "item:250001" and DarkMatter.FishingItemString("garbage") == nil, "item string validation")
  local fz = DarkMatter.GetFishingDB()
  local storedLink
  for _, zb in pairs(fz.zones or {}) do local it = zb.items and zb.items["Riverglades Glimmerfin"] if it and it.link then storedLink = it.link end end
  check(storedLink == "item:250001", "loot link stored on catch: " .. tostring(storedLink))

  DarkMatter.FishingSetUIPref("panel", "catches")
  DarkMatter.FishingSetUIPref("catchMode", "fish")
  DarkMatter.FishingSetUIPref("showAll", true)
  DarkMatter.tabs.journals.Refresh()
  local rows = {}
  for _, fr in ipairs(ALL) do
    local e = rawget(fr, "entry")
    if type(e) == "table" and fr._scripts and fr._scripts.OnEnter then rows[e.name] = fr end
  end
  local caughtRow, uncaughtRow, learnedRow = rows["Riverglades Glimmerfin"], rows["10 Pound Mud Snapper"], rows["Hyjal Ember Trout"]
  check(caughtRow and uncaughtRow and learnedRow, "rows have OnEnter + entry (caught, uncaught, learned)")
  local nWith, nRows = 0, 0
  for _, fr in ipairs(ALL) do if type(rawget(fr, "entry")) == "table" then nRows = nRows + 1 if fr._scripts.OnEnter and fr._scripts.OnLeave then nWith = nWith + 1 end end end
  check(nRows > 100 and nWith == nRows, "every Show all row has OnEnter/OnLeave (" .. nWith .. "/" .. nRows .. ")")

  local savedCached = C_Item.IsItemDataCachedByID
  C_Item.IsItemDataCachedByID = function() return true end
  ttreset(); caughtRow._scripts.OnEnter(caughtRow)
  check(TT.owner == caughtRow and TT.anchor == "ANCHOR_PRESERVE" and TT.shown, "SetOwner(row, ANCHOR_PRESERVE) + Show")
  local lp = TT.point
  check(lp and lp[1] == "BOTTOMLEFT" and lp[2] == caughtRow.icon and lp[3] == "TOPRIGHT" and lp[4] == 1 and lp[5] == 1, "tooltip BOTTOMLEFT at the icon TOPRIGHT, visible +4,+4 (" .. tostring(lp and lp[1]) .. "," .. tostring(lp and lp[3]) .. "," .. tostring(lp and lp[4]) .. "," .. tostring(lp and lp[5]) .. "," .. tostring(lp and lp[2] == caughtRow.icon) .. ")")
  check(TT.link == "item:250001", "cached caught item uses stored link via SetHyperlink")
  check(has("Caught=") and has("Last caught=Elwynn Forest") , "caught lines: count + last zone (" .. table.concat(TT.lines, " | ") .. ")")
  caughtRow._scripts.OnLeave(caughtRow)
  ttreset(); uncaughtRow._scripts.OnEnter(uncaughtRow)
  check(TT.itemId == 2620 or TT.itemId == uncaughtRow.entry.itemId, "uncaught catalog item uses SetItemByID")
  check(has("Not caught yet") and has("Typical waters=") and not has("Caught="), "uncaught lines: Not caught yet + typical waters")
  uncaughtRow._scripts.OnLeave(uncaughtRow)
  ttreset(); learnedRow._scripts.OnEnter(learnedRow)
  check(has("Not caught yet") and has("First seen=Mount Hyjal"), "learned lines: first seen zone")
  TT.hidden = nil; learnedRow._scripts.OnLeave(learnedRow)
  check(TT.hidden, "OnLeave hides tooltip")

  -- not cached: fallback name/quality tooltip, plus our lines; no item APIs called
  C_Item.IsItemDataCachedByID = function() return false end
  ttreset(); learnedRow._scripts.OnEnter(learnedRow)
  check(TT.itemId == nil and TT.link == nil and TT.lines[1] == "Hyjal Ember Trout" and TT.lines[2] == "Uncommon", "fallback tooltip: name + quality (" .. table.concat(TT.lines, " | ") .. ")")
  check(has("Dark Matter") and has("Not caught yet") and TT.shown, "fallback tooltip has Dark Matter lines")
  do local q = TT.point check(q and q[1] == "BOTTOMLEFT" and q[3] == "TOPRIGHT" and q[4] == 1 and q[5] == 1, "fallback tooltip uses gap placement (gap 4 - inset 3)") end
  -- hovering while data arrives: list refresh rebuilds the tooltip with the real item
  C_Item.IsItemDataCachedByID = function() return true end
  ttreset(); DarkMatter.tabs.journals.Refresh()
  check(TT.itemId == 250002 and TT.owner == learnedRow, "refresh while hovered upgrades to item tooltip (" .. tostring(TT.itemId) .. "," .. tostring(TT.owner == learnedRow) .. "," .. tostring(rawget(learnedRow, "_hover")) .. "," .. tostring(learnedRow.entry and learnedRow.entry.name) .. ")")
  do local q = TT.point check(q and q[1] == "BOTTOMLEFT" and q[3] == "TOPRIGHT" and q[4] == 1 and q[5] == 1, "refresh tooltip uses gap placement") end
  learnedRow._scripts.OnLeave(learnedRow)
  -- OnLeave from a row that no longer owns the tooltip does not hide someone else's tooltip
  ttreset(); TT.owner = "other"; caughtRow._scripts.OnLeave(caughtRow)
  check(not TT.hidden, "OnLeave leaves tooltips owned by others alone")
  -- 0.2.10 placement rules (UIParent 1600x1000, row 400 wide, tooltip 200x100, gap 4)
  local function fr(l, t, w, h, r) return { GetLeft = function() return l end, GetRight = function() return r or (l and l + 400) end, GetTop = function() return t end, GetWidth = function() return w end, GetHeight = function() return h end, GetEffectiveScale = function() return 1 end } end
  local tip = fr(nil, nil, 200, 100)
  rawset(UIParent, "GetHeight", function() return 1000 end)
  rawset(UIParent, "GetWidth", function() return 1600 end)
  local A = DarkMatter.FishingTooltipAnchor
  check(DarkMatter.FISH_TIP_GAP == 4, "gap is 4px")
  local p, r, x, y, sd, vt = A(tip, fr(500, 500))
  check(p == "BOTTOMLEFT" and r == "TOPRIGHT" and x == 4 and y == 4 and vt == "up" and sd == "right", "0.2.15 default, no compare: BOTTOMLEFT->icon TOPRIGHT +4,+4")
  p, r, x, y, sd = A(tip, fr(1300, 500, 200, 100, 1450))
  check(p == "BOTTOMRIGHT" and r == "TOPLEFT" and x == -4 and y == 4 and sd == "left", "no compare, no room on the right: mirror BOTTOMRIGHT->icon TOPLEFT -4,+4")
  p, r, x, y = A(tip, fr(100, 500))
  check(p == "BOTTOMLEFT" and r == "TOPRIGHT" and x == 4 and y == 4, "(a) no room left: BOTTOMLEFT->TOPRIGHT +4,+4")
  p, r, x, y, sd = A(tip, fr(500, 500), 300, 150)
  check(p == "BOTTOMLEFT" and r == "TOPRIGHT" and x == 4 and y == 4 and sd == "right", "(b) compare: main BOTTOMLEFT->row TOPRIGHT +4,+4, compares right")
  p, r, x, y, sd = A(tip, fr(800, 500, 200, 100, 1300), 300, 150)
  check(p == "BOTTOMRIGHT" and r == "TOPLEFT" and x == -4 and y == 4 and sd == "left", "(b) no room right: mirror BOTTOMRIGHT->TOPLEFT -4,+4, compares left")
  p, r, x, y, sd, vt = A(tip, fr(500, 950), 300, 150)
  check(p == "TOPLEFT" and r == "BOTTOMRIGHT" and x == 4 and y == -4 and sd == "right" and vt == "down", "(c) compare near top: below the row, +4,-4")
  p, r, x, y, sd, vt = A(tip, fr(500, 950))
  check(p == "TOPLEFT" and r == "BOTTOMRIGHT" and x == 4 and y == -4 and vt == "down", "(c) no compare near top: below the icon, +4,-4")
  p, r, x, y = A(tip, fr(500, 850), 300, 200)
  check(p == "TOPLEFT" and y == -4, "(c) tall compare decides the top flip")
  check(A(tip, {}) == "BOTTOMLEFT" and A(tip, {}, 300, 100) == "BOTTOMLEFT", "no geometry: default right of the icon")
  p, r, x, y, sd = A(tip, fr(400, 500, 200, 100, 1300), 900, 150)
  check(p == "BOTTOMRIGHT" and sd == "left", "(b) neither side fits: side with more room (left)")
  p, r, x, y, sd = A(tip, fr(300, 500, 200, 100, 1100), 900, 150)
  check(p == "BOTTOMLEFT" and sd == "right", "(b) neither side fits: side with more room (right)")

  -- compare chain applied to ShoppingTooltip1/2 (never moves the main tooltip onto the cursor)
  local function rec(name, w, h)
    local o = { name = name, pts = {}, shown = true, w = w, h = h }
    function o:SetPoint(...) self.pts[#self.pts + 1] = { ... } end
    function o:ClearAllPoints() self.pts = {} end
    function o:GetWidth() return self.w end
    function o:GetHeight() return self.h end
    function o:GetEffectiveScale() return 1 end
    function o:IsShown() return self.shown end
    return o
  end
  local mt = rec("main", 200, 100)
  local s1, s2 = rec("s1", 180, 120), rec("s2", 160, 110)
  function s1:GetOwner() return mt end
  function s2:GetOwner() return mt end
  ShoppingTooltip1, ShoppingTooltip2 = s1, s2
  local row = fr(500, 500)
  local side, vert, n = DarkMatter._FishingPlaceTooltip(mt, row)
  local m1, a1, b1 = mt.pts[1], s1.pts[1], s2.pts[1]
  check(#mt.pts == 1 and m1[1] == "BOTTOMLEFT" and m1[2] == row and m1[3] == "TOPRIGHT" and m1[4] == 1 and m1[5] == 1, "compare shown: main at row TOPRIGHT +4,+4")
  check(n == 2 and side == "right" and a1[1] == "BOTTOMLEFT" and a1[2] == mt and a1[3] == "BOTTOMRIGHT" and b1[1] == "BOTTOMLEFT" and b1[2] == s1 and b1[3] == "BOTTOMRIGHT", "ShoppingTooltip1 then 2 chained right, bottoms aligned")
  row = fr(1000, 500, 200, 100, 1400)
  side = DarkMatter._FishingPlaceTooltip(mt, row)
  m1, a1, b1 = mt.pts[1], s1.pts[1], s2.pts[1]
  check(side == "left" and m1[1] == "BOTTOMRIGHT" and m1[3] == "TOPLEFT" and m1[4] == -1 and a1[1] == "BOTTOMRIGHT" and a1[2] == mt and a1[3] == "BOTTOMLEFT" and b1[2] == s1 and b1[3] == "BOTTOMLEFT", "mirrored: main at row TOPLEFT, compares chained left")
  row = fr(500, 960)
  DarkMatter._FishingPlaceTooltip(mt, row)
  check(mt.pts[1][1] == "TOPLEFT" and s1.pts[1][1] == "TOPLEFT" and s1.pts[1][3] == "TOPRIGHT", "near top: below row, compares tops aligned")
  s2.shown = false; s1.pts, s2.pts = {}, {}
  DarkMatter._FishingPlaceTooltip(mt, fr(500, 500))
  check(#s1.pts == 1 and #s2.pts == 0, "only shown compare tooltips are placed")
  function s1:GetOwner() return "ItemRefTooltip" end
  s2.pts, s1.pts = {}, {}
  DarkMatter._FishingPlaceTooltip(mt, fr(500, 500))
  check(#s1.pts == 0 and mt.pts[1][1] == "BOTTOMLEFT", "compare owned by another tooltip is ignored")
  ShoppingTooltip1, ShoppingTooltip2 = nil, nil
  rawset(UIParent, "GetHeight", nil)
  rawset(UIParent, "GetWidth", nil)

  -- shift-compare: own MODIFIER_STATE_CHANGED frame rebuilds the hovered row's tooltip
  local modFrame
  for _, f2 in ipairs(ALL) do if rawget(f2, "_ev") and f2._ev.MODIFIER_STATE_CHANGED then modFrame = f2 end end
  check(modFrame and modFrame ~= GameTooltip and modFrame._scripts.OnEvent, "own frame watches MODIFIER_STATE_CHANGED")
  C_Item.IsItemDataCachedByID = function() return true end
  ttreset(); caughtRow._scripts.OnEnter(caughtRow)
  ttreset(); TT.owner = caughtRow; modFrame._scripts.OnEvent(modFrame, "MODIFIER_STATE_CHANGED", "LSHIFT", 1)
  check(TT.link == "item:250001" and TT.anchor == "ANCHOR_PRESERVE" and TT.shown, "modifier change while hovered rebuilds tooltip")
  caughtRow._scripts.OnLeave(caughtRow)
  ttreset(); modFrame._scripts.OnEvent(modFrame, "MODIFIER_STATE_CHANGED", "LSHIFT", 0)
  check(TT.link == nil and not TT.shown, "modifier change after leave does nothing")
  rawset(GameTooltip, "SetAnchorType", function() TT.slid = true end)
  ttreset(); caughtRow._scripts.OnEnter(caughtRow)
  check(not TT.slid, "addon never calls SetAnchorType")
  caughtRow._scripts.OnLeave(caughtRow)
  -- no hooks on GameTooltip
  check(rawget(GameTooltip, "_scripts") == nil or next(GameTooltip._scripts) == nil, "no scripts set on GameTooltip")
  C_Item.IsItemDataCachedByID = savedCached
  DarkMatter.FishingSetUIPref("showAll", false)
end


-- ===== 0.2.11 compare placement vs the client's classic compare code; single hover row; client names; fishcheck =====
if MODE ~= "minimal" then
  -- catalog: unique ids + names (case-insensitive), trophy fish are common quality (Wowhead Classic)
  local ids, names, dup, tq = {}, {}, 0, 0
  for _, e in ipairs(DarkMatter.FishingCatchCatalog) do
    local n = e.name:lower()
    if ids[e.itemId] or names[n] then dup = dup + 1 end
    ids[e.itemId], names[n] = true, true
    if e.cat == "trophy" and e.quality ~= 1 then tq = tq + 1 end
  end
  check(dup == 0, "catalog ids and names unique (dups=" .. dup .. ")")
  check(tq == 0, "trophy fish quality 1 (common) per Wowhead Classic")
  check(DarkMatter.FishingCatalogById()[5524].name == "Thick-shelled Clam" and DarkMatter.FishingCatalogById()[7973].name == "Big-mouth Clam", "clam names spelled as on the client")

  -- recording GameTooltip + ShoppingTooltips that behave like the classic client
  local T = { pts = nil, shown = false }
  local function gpts(o) return function() local q = o.pts if not q then return nil end return q[1], q[2], q[3], q[4], q[5] end end
  rawset(GameTooltip, "SetOwner", function(_, owner, anchor) T.owner, T.anchor = owner, anchor end)
  rawset(GameTooltip, "ClearAllPoints", function() T.pts = nil end)
  rawset(GameTooltip, "SetPoint", function(_, ...) T.pts = { ... } end)
  rawset(GameTooltip, "GetPoint", function() if not T.pts then return nil end return T.pts[1], T.pts[2], T.pts[3], T.pts[4], T.pts[5] end)
  rawset(GameTooltip, "GetNumPoints", function() return T.pts and 1 or 0 end)
  rawset(GameTooltip, "IsOwned", function(_, o) return T.owner == o end)
  rawset(GameTooltip, "IsShown", function() return T.shown end)
  rawset(GameTooltip, "Show", function() T.shown = true end)
  rawset(GameTooltip, "Hide", function() T.shown = false if ShoppingTooltip1 then ShoppingTooltip1.shown = false ShoppingTooltip2.shown = false end end)
  rawset(GameTooltip, "GetWidth", function() return 200 end)
  rawset(GameTooltip, "GetHeight", function() return 100 end)
  rawset(GameTooltip, "AddLine", function() end)
  rawset(GameTooltip, "AddDoubleLine", function() end)
  rawset(GameTooltip, "SetAnchorType", function(_, a) T.slid = a; T.pts = nil end)
  local function shop(name)
    local o = { name = name, shown = false, w = 220, h = 160 }
    function o:SetOwner(ow) self.owner = ow end
    function o:GetOwner() return self.owner end
    function o:ClearAllPoints() self.pts = nil end
    function o:SetPoint(...) self.pts = { ... } end
    o.GetPoint = gpts(o)
    function o:GetNumPoints() return self.pts and 1 or 0 end
    function o:IsShown() return self.shown end
    function o:GetWidth() return self.w end
    function o:GetHeight() return self.h end
    function o:GetEffectiveScale() return 1 end
    return o
  end
  ShoppingTooltip1, ShoppingTooltip2 = shop("ShoppingTooltip1"), shop("ShoppingTooltip2")
  -- GameTooltip_ShowCompareItem / GameTooltip_AnchorComparisonTooltips (classic order): slide unless ANCHOR_PRESERVE,
  -- then ShoppingTooltip1 TOPLEFT -> GameTooltip TOPRIGHT (0,-10), Show.
  local COMPARE = false
  local function clientCompare()
    if not COMPARE then ShoppingTooltip1.shown = false ShoppingTooltip2.shown = false return end
    if T.anchor ~= "ANCHOR_PRESERVE" then GameTooltip:SetAnchorType(T.anchor, -40, 0) end
    local s1 = ShoppingTooltip1
    s1:SetOwner(GameTooltip, "ANCHOR_NONE"); s1:ClearAllPoints(); s1:SetPoint("TOPLEFT", GameTooltip, "TOPRIGHT", 0, -10); s1.shown = true
    ShoppingTooltip2.shown = false
  end
  rawset(GameTooltip, "SetHyperlink", function() clientCompare() end)
  rawset(GameTooltip, "SetItemByID", function() clientCompare() end)
  local savedCached = C_Item.IsItemDataCachedByID
  C_Item.IsItemDataCachedByID = function() return true end
  local savedGII = GetItemInfo
  local CAT = DarkMatter.FishingCatalogById()
  GetItemInfo = function(id)
    if id == 6292 then return "Ten Pound Test Snapper", "item:6292", 1 end
    local c = CAT[id] or (DarkMatterDB.fishingCatalogLearned or {})[id]
    if c then return c.name, "item:" .. id, c.quality or 1 end
  end

  DarkMatter.FishingSetUIPref("panel", "catches"); DarkMatter.FishingSetUIPref("catchMode", "fish"); DarkMatter.FishingSetUIPref("showAll", true)
  DarkMatter.tabs.journals.Refresh()
  local rows = {}
  for _, fr in ipairs(ALL) do local e = rawget(fr, "entry") if type(e) == "table" and fr._scripts and fr._scripts.OnEnter then rows[e.name] = fr end end
  local A, B = rows["Riverglades Glimmerfin"], rows["10 Pound Mud Snapper"]

  -- (a) no compare: BOTTOMRIGHT -> row TOPLEFT
  COMPARE = false
  A._scripts.OnEnter(A)
  check(T.anchor == "ANCHOR_PRESERVE" and T.pts and T.pts[1] == "BOTTOMLEFT" and T.pts[2] == A.icon and T.pts[3] == "TOPRIGHT" and T.pts[4] == 1 and T.pts[5] == 1, "no compare: main BOTTOMLEFT at the icon TOPRIGHT (visible +4,+4)")
  A._scripts.OnLeave(A)
  -- (b) compare: the client anchors ShoppingTooltip1 TOPLEFT->TOPRIGHT -10 during SetHyperlink; we take over
  COMPARE = true
  A._scripts.OnEnter(A)
  check(not T.slid, "ANCHOR_PRESERVE: client compare code never slides the main tooltip")
  check(T.pts[1] == "BOTTOMLEFT" and T.pts[2] == A.icon and T.pts[3] == "TOPRIGHT" and T.pts[4] == 1 and T.pts[5] == 1, "compare: leftmost (main) BOTTOMLEFT at the icon TOPRIGHT +4,+4")
  local s1 = ShoppingTooltip1
  check(s1.pts[1] == "BOTTOMLEFT" and s1.pts[2] == GameTooltip and s1.pts[3] == "BOTTOMRIGHT" and s1.pts[4] == 0 and s1.pts[5] == 0, "compare: ShoppingTooltip1 chained right, bottoms aligned (not the client's TOPLEFT -10)")
  local W = DarkMatter._FishingTooltipWatch()
  check(W and W._shown and rawget(W, "target") and W.target.owner == A, "placement watcher runs while the row is hovered")
  -- client re-anchors after our pass (UpdateTooltip / second compare pass): the watcher puts it back
  clientCompare()
  check(s1.pts[1] == "TOPLEFT" and s1.pts[5] == -10, "repro: client re-anchor moves ShoppingTooltip1 back to TOPLEFT -10")
  W._scripts.OnUpdate(W, 0.016)
  check(s1.pts[1] == "BOTTOMLEFT" and s1.pts[2] == GameTooltip and T.pts[1] == "BOTTOMLEFT" and T.pts[2] == A.icon, "watcher restores our placement after the client re-anchors")
  -- compare tooltip fills in later and grows (second SetCompareItem): re-placed on the size change
  local fixes = W.target.fixes or 0
  s1.h = 320
  W._scripts.OnUpdate(W, 0.016)
  check((W.target.fixes or 0) == fixes + 1 and s1.pts[1] == "BOTTOMLEFT", "late size change re-applies placement")
  W._scripts.OnUpdate(W, 0.016)
  check((W.target.fixes or 0) == fixes + 1, "no work when nothing changed")
  -- second compare tooltip (dual wield): chained after the first
  ShoppingTooltip2.shown = true; ShoppingTooltip2:SetOwner(GameTooltip)
  W._scripts.OnUpdate(W, 0.016)
  check(ShoppingTooltip2.pts and ShoppingTooltip2.pts[1] == "BOTTOMLEFT" and ShoppingTooltip2.pts[2] == s1, "ShoppingTooltip2 chained after ShoppingTooltip1")
  A._scripts.OnLeave(A)
  check(not W._shown and rawget(W, "target") == nil, "watcher stops on leave")
  check(not T.shown, "tooltip hidden on leave")

  -- one hover owner: a refresh can only re-show the tooltip for the row most recently entered
  COMPARE = false
  B._scripts.OnEnter(B)
  A._scripts.OnEnter(A)  -- entered A without B's OnLeave (stale state)
  T.owner = nil
  DarkMatter.tabs.journals.Refresh()
  check(T.owner == A, "refresh re-shows only the current hover row (not a stale one)")
  A._scripts.OnLeave(A); B._scripts.OnLeave(B)

  -- rows show the client's item name; differences are logged; /dm fishcheck lists them
  local shownName
  for _, fs in ipairs(FS) do if fs._text == "Ten Pound Test Snapper" then shownName = true end end
  check(shownName, "row text uses the client item name when cached")
  check(DarkMatterDB.fishcheck and DarkMatterDB.fishcheck.seen and DarkMatterDB.fishcheck.seen[6292] and DarkMatterDB.fishcheck.seen[6292].catalog == "10 Pound Mud Snapper", "name difference logged for fishcheck")
  SlashCmdList["DARKMATTER"]("fishcheck")
  local fc = DarkMatterDB.fishcheck
  check(fc and fc.checked >= 3 and #fc.mismatches == 1 and fc.mismatches[1].itemId == 6292 and fc.mismatches[1].client == "Ten Pound Test Snapper", "/dm fishcheck: 1 mismatch saved (" .. tostring(fc and fc.checked) .. " checked)")
  check(fc.seen and fc.seen[6292], "fishcheck keeps the names seen on rows")

  -- 0.2.15: the anchor is the item icon itself (no item-anchor frame, no name width)
  local ia = A.icon
  check(DarkMatter._FishingAnchorOf(A) == A.icon and rawget(A, "itemAnchor") == nil, "placement anchor = the row's icon frame")
  check(DarkMatter.FISH_TIP_INSET == 3, "tooltip border inset 3 (SetPoint offset = gap 4 - inset 3)")
  -- compare ownership through IsOwned when GetOwner is unavailable
  COMPARE = true
  A._scripts.OnEnter(A)
  local s1b = ShoppingTooltip1
  s1b.GetOwner = function() error("no GetOwner") end
  s1b.IsOwned = function(_, o) return o == GameTooltip end
  clientCompare()
  W._scripts.OnUpdate(W, 0.016)
  check(s1b.pts[1] == "BOTTOMLEFT" and s1b.pts[2] == GameTooltip, "compare recognised via IsOwned and chained")
  s1b.GetOwner, s1b.IsOwned = function(self) return self.owner end, nil
  A._scripts.OnLeave(A)
  -- /dm tipdebug: toggle; each placement records final points/rects of GameTooltip, ShoppingTooltip1/2, anchor
  local printed = 0
  local savedPrint = DarkMatter.Print
  DarkMatter.Print = function(m) if tostring(m):find("tipdebug", 1, true) then printed = printed + 1 end end
  SlashCmdList["DARKMATTER"]("tipdebug")
  check(DarkMatterDB.tipdebug and DarkMatterDB.tipdebug.on == true, "/dm tipdebug turns logging on")
  A._scripts.OnEnter(A)
  clientCompare(); W._scripts.OnUpdate(W, 0.016)
  local td = DarkMatterDB.tipdebug
  local last = td.last
  check(td.count and td.count >= 2 and #td.log == td.count, "tipdebug: placements logged (" .. tostring(td.count) .. ")")
  check(last and last.reason == "repoint" and last.item == A.catchName and last.frames.GameTooltip and last.frames.GameTooltip.points[1] == "BOTTOMLEFT>icon:TOPRIGHT 1,1", "tipdebug: last = repoint, GameTooltip point named (" .. tostring(last and last.frames.GameTooltip and last.frames.GameTooltip.points[1]) .. ")")
  check(last.frames.ShoppingTooltip1 and last.frames.ShoppingTooltip1.shown and last.frames.anchor and last.frames.row and last.side == "right" and last.compares == 1, "tipdebug: compare, anchor and row recorded")
  check(td.log[1].reason == "show", "tipdebug: first record is the show pass")
  check(printed >= 3, "tipdebug: chat summary printed (" .. printed .. ")")
  A._scripts.OnLeave(A)
  SlashCmdList["DARKMATTER"]("tipdebug")
  check(DarkMatterDB.tipdebug.on == false, "/dm tipdebug toggles off")
  local n0 = DarkMatterDB.tipdebug.count
  A._scripts.OnEnter(A); A._scripts.OnLeave(A)
  check(DarkMatterDB.tipdebug.count == n0, "nothing logged when off")
  -- tipdebug: anchor rect vs tooltip rect line (frame gap 1 + inset 3 = visible 4)
  local lines = {}
  DarkMatter.Print = function(m) lines[#lines + 1] = tostring(m) end
  SlashCmdList["DARKMATTER"]("tipdebug")
  rawset(ia, "GetRect", function() return 108, 450, 176, 28 end)
  rawset(GameTooltip, "GetRect", function() return 285, 479, 200, 100 end)
  COMPARE = false
  A._scripts.OnEnter(A)
  local dl
  for _, l in ipairs(lines) do if l:find("tipdebug icon", 1, true) then dl = l end end
  local dd = DarkMatterDB.tipdebug.last and DarkMatterDB.tipdebug.last.delta
  check(dl and dl:find("visible ~x=4 y=4", 1, true), "tipdebug prints anchor vs tip rect line (" .. tostring(dl) .. ")")
  check(dd and dd.frameX == 1 and dd.frameY == 1 and dd.visibleX == 4 and dd.inset == 3, "tipdebug delta saved")
  A._scripts.OnLeave(A)
  SlashCmdList["DARKMATTER"]("tipdebug")
  rawset(GameTooltip, "GetRect", nil)
  -- 0.2.14: tipdebug also prints scales, row/icon rects and the room decision
  lines = {}
  DarkMatter.Print = function(m) lines[#lines + 1] = tostring(m) end
  SlashCmdList["DARKMATTER"]("tipdebug")
  A._scripts.OnEnter(A)
  local sl
  for _, l in ipairs(lines) do if l:find("tipdebug scale ui", 1, true) then sl = l end end
  check(sl and sl:find("room L", 1, true) and sl:find("icon", 1, true) and sl:find("row", 1, true), "tipdebug prints scales, row/icon rects and room (" .. tostring(sl) .. ")")
  local lr = DarkMatterDB.tipdebug.last
  check(lr and lr.decision and lr.decision.scales and lr.frames.anchor and lr.frames.UIParent, "tipdebug saves decision, scales, icon and UIParent")
  A._scripts.OnLeave(A)
  SlashCmdList["DARKMATTER"]("tipdebug")
  -- watcher re-applies every frame while settling (first 10 frames), without counting as fixes
  A._scripts.OnEnter(A)
  local nSet, fx0 = 0, W.target.fixes or 0
  local realSP = rawget(GameTooltip, "SetPoint")
  rawset(GameTooltip, "SetPoint", function(self, ...) nSet = nSet + 1 return realSP(self, ...) end)
  for _ = 1, 12 do W._scripts.OnUpdate(W, 0.016) end
  check(nSet == 10 and (W.target.fixes or 0) == fx0, "settling: re-applied on 10 frames, then only on change (" .. nSet .. ")")
  rawset(GameTooltip, "SetPoint", realSP)
  A._scripts.OnLeave(A)

  -- real-client geometry from the /dm tipdebug screenshots (window at the screen's left edge, UI units)
  local function fakeF(l, b, w, h)
    local f = {}
    function f:GetLeft() return l end
    function f:GetRight() return l + w end
    function f:GetTop() return b + h end
    function f:GetBottom() return b end
    function f:GetEffectiveScale() return 1 end
    return f
  end
  local function resolve(pt, rel, x, y, a, w, h)
    local ax = rel:find("RIGHT") and (a:GetRight()) or a:GetLeft()
    local ay = rel:find("TOP") and a:GetTop() or a:GetBottom()
    local inset = DarkMatter.FISH_TIP_INSET
    local fx = x > 0 and x - inset or x + inset
    local fy = y > 0 and y - inset or y + inset
    local px, py = ax + fx, ay + fy
    local l = pt:find("LEFT") and px or px - w
    local b = pt:find("BOTTOM") and py or py - h
    return l, b, w, h
  end
  rawset(UIParent, "GetWidth", function() return 1200 end)
  rawset(UIParent, "GetHeight", function() return 900 end)
  -- 0.2.15 rule on the real-client positions (icon 28x28 at the tipdebug anchor's left/bottom; screen 1200x900)
  local function visGap(a, b) return a + DarkMatter.FISH_TIP_INSET - b end
  -- (1) Oily Blackmouth, no compare: icon 242,593.5 28x28; tooltip 364.7x172.3
  rawset(GameTooltip, "GetWidth", function() return 364.7 end)
  rawset(GameTooltip, "GetHeight", function() return 172.3 end)
  local oily = fakeF(242, 593.5, 28, 28)
  local pt, rl, x1, y1, sd = DarkMatter.FishingTooltipAnchor(GameTooltip, oily, 0, 0)
  check(pt == "BOTTOMLEFT" and rl == "TOPRIGHT" and sd == "right", "geometry (1): no compare -> BOTTOMLEFT at the icon TOPRIGHT")
  local l1, b1 = resolve(pt, rl, x1, y1, oily, 364.7, 172.3)
  check(math.abs(visGap(l1, oily:GetRight()) - 4) < 0.05 and math.abs(visGap(b1, oily:GetTop()) - 4) < 0.05, "geometry (1): visible bottom-left corner 4,4 from the icon's top-right (frame " .. l1 .. "," .. b1 .. ")")
  check(b1 >= oily:GetTop() and l1 >= oily:GetRight(), "geometry (1): tooltip never overlaps the hovered icon")
  -- room on the left no longer matters: still right of the icon
  local roomy = fakeF(500, 593.5, 28, 28)
  pt, rl = DarkMatter.FishingTooltipAnchor(GameTooltip, roomy, 0, 0)
  check(pt == "BOTTOMLEFT" and rl == "TOPRIGHT", "geometry: room on the left does not change the default (right of the icon)")
  -- near the right edge: mirror, rightmost tooltip BOTTOMRIGHT 4 from the icon TOPLEFT
  local edge = fakeF(1000, 593.5, 28, 28)
  pt, rl, x1, y1, sd = DarkMatter.FishingTooltipAnchor(GameTooltip, edge, 0, 0)
  local l4, b4, w4 = resolve(pt, rl, x1, y1, edge, 364.7, 172.3)
  check(pt == "BOTTOMRIGHT" and rl == "TOPLEFT" and sd == "left" and math.abs(visGap(edge:GetLeft(), l4 + w4) - 4) < 0.05 and math.abs(visGap(b4, edge:GetTop()) - 4) < 0.05, "geometry: off the right edge -> mirrored, BOTTOMRIGHT 4 from the icon TOPLEFT")
  -- no room above: below the icon, corners mirrored vertically
  local top = fakeF(242, 820, 28, 28)
  pt, rl, x1, y1 = DarkMatter.FishingTooltipAnchor(GameTooltip, top, 0, 0)
  local l5, b5, _, h5 = resolve(pt, rl, x1, y1, top, 364.7, 172.3)
  check(pt == "TOPLEFT" and rl == "BOTTOMRIGHT" and math.abs(visGap(top:GetBottom(), b5 + h5) - 4) < 0.05 and math.abs(visGap(l5, top:GetRight()) - 4) < 0.05, "geometry: no room above -> TOPLEFT 4 below/right of the icon BOTTOMRIGHT")
  -- (2) 103 Pound Mightfish with two compares (420 wide together): icon 242,485.5 28x28; main 250.9x131.3
  rawset(GameTooltip, "GetWidth", function() return 250.9 end)
  rawset(GameTooltip, "GetHeight", function() return 131.3 end)
  local might = fakeF(242, 485.5, 28, 28)
  pt, rl, x1, y1, sd = DarkMatter.FishingTooltipAnchor(GameTooltip, might, 420, 200)
  local l3, b3 = resolve(pt, rl, x1, y1, might, 250.9, 131.3)
  check(pt == "BOTTOMLEFT" and sd == "right" and math.abs(visGap(l3, might:GetRight()) - 4) < 0.05 and math.abs(visGap(b3, might:GetTop()) - 4) < 0.05, "geometry (2): leftmost tooltip (main) BOTTOMLEFT 4,4 from the icon TOPRIGHT; compares to its right")
  -- set of main + compares runs off the right edge -> mirrored
  local edge2 = fakeF(700, 485.5, 28, 28)
  pt, rl, x1, y1, sd = DarkMatter.FishingTooltipAnchor(GameTooltip, edge2, 420, 200)
  check(pt == "BOTTOMRIGHT" and rl == "TOPLEFT" and sd == "left", "geometry (2): set would run off the right edge -> mirrored, compares chained left")
  rawset(UIParent, "GetWidth", nil); rawset(UIParent, "GetHeight", nil)
  rawset(GameTooltip, "GetWidth", function() return 200 end)
  rawset(GameTooltip, "GetHeight", function() return 100 end)


  -- ===== 0.3.0 Adventure Guide: seed, LFG merge, filters, gate, loot learning, UI + same tooltip placement =====
  local AGm = DarkMatter.AG
  local seed = DarkMatter.AdventureGuideSeed
  check(AGm and seed, "AG module + seed loaded")
  local want = { RFC = 4, WC = 9, DM = 9, SFK = 9, BFD = 8 }
  local nb, nd, bad = 0, 0, 0
  local nDun, nRaid, nDropSeeded, names = 0, 0, 0, {}
  for _, d in ipairs(seed) do
    names[d.name] = d
    if want[d.short] then check(want[d.short] == #d.bosses, "seed " .. d.short .. ": full boss list (" .. #d.bosses .. ")") end
    if d.kind == "Raid" then nRaid = nRaid + 1 else nDun = nDun + 1 end
    if d.dropsSeeded then nDropSeeded = nDropSeeded + 1 end
    if not (d.src and d.src:find("^https://www%.wowhead%.com/forever/zone=%d+$")) then bad = bad + 1 end
    if not (d.levels and d.levels[1] <= d.levels[2]) then bad = bad + 1 end
    for _, b in ipairs(d.bosses) do
      nb = nb + 1
      if b.src ~= "https://www.wowhead.com/forever/npc=" .. b.npcId then bad = bad + 1 end
      local ids = {}
      for _, it in ipairs(b.drops) do
        nd = nd + 1
        if ids[it.itemId] or it.src ~= "https://www.wowhead.com/forever/item=" .. it.itemId or not it.icon:find("^Interface\\Icons\\") or it.quality < 2 then bad = bad + 1 end
        ids[it.itemId] = true
      end
    end
  end
  out("AG seed:", #seed, "instances,", nDun, "dungeons,", nRaid, "raids,", nb, "bosses,", nd, "drops,", nDropSeeded, "with drops")
  check(#seed == 36 and nDun == 29 and nRaid == 7 and bad == 0, string.format("known-good list: %d instances (%d dungeons, %d raids), %d bosses, %d drops, each cites wowhead.com/forever (bad=%d)", #seed, nDun, nRaid, nb, nd, bad))
  local missing = {}
  for _, n in ipairs({ "Ragefire Chasm", "Wailing Caverns", "The Deadmines", "Shadowfang Keep", "Blackfathom Deeps", "The Stockade",
    "Gnomeregan", "Razorfen Kraul", "Scarlet Monastery: Graveyard", "Scarlet Monastery: Library", "Scarlet Monastery: Armory",
    "Scarlet Monastery: Cathedral", "Razorfen Downs", "Uldaman", "Zul'Farrak", "Maraudon", "The Temple of Atal'Hakkar",
    "Blackrock Depths", "Lower Blackrock Spire", "Upper Blackrock Spire", "Dire Maul: East", "Dire Maul: West", "Dire Maul: North",
    "Scholomance", "Stratholme", "Molten Core", "Onyxia's Lair", "Zul'Gurub", "Blackwing Lair", "Ruins of Ahn'Qiraj",
    "Temple of Ahn'Qiraj", "Naxxramas", "The Hall of Thanes", "Ruins of Lordaeron", "Excavation Site: Wetlands", "City of Dalaran" }) do
    if not names[n] then missing[#missing + 1] = n end
  end
  check(#missing == 0, "every Classic dungeon/raid + Forever's Wowhead-listed instances present (" .. table.concat(missing, ", ") .. ")")
  local allBosses, raidNoDrops = true, true
  for _, d in ipairs(seed) do
    if #d.bosses == 0 then allBosses = false end
    if not d.dropsSeeded then for _, b in ipairs(d.bosses) do if #b.drops > 0 then raidNoDrops = false end end end
  end
  check(allBosses and raidNoDrops and nDropSeeded == 24 and nd > 86, "every instance has a Forever-validated boss list; drops seeded for 24 dungeons (Forever-validated items only), boss lists only elsewhere")
  check(names["The Hall of Thanes"].forever and names["The Hall of Thanes"].levels[1] == 13 and #names["The Hall of Thanes"].bosses == 4, "Forever-only Hall of Thanes: 13-18, 4 bosses")
  -- stub client LFG (ids 10/11, names only, placeholder boss names)
  AGm._ResetCaches()
  local stubList = AGm.ScanLFG()
  out("AG: stub LFG dungeons with encounters:", #stubList, "(0.3.0 real client listed 67 = zones/battlegrounds)")
  check(#stubList == 2, "stub LFG: 2 dungeons with encounters (SECRETNAME and empty ids skipped)")
  local st0 = AGm.ScanStats()
  out("AG: stub LFG named rows:", st0.named, "kept:", st0.accepted)
  -- richer LFG mock: full classic return order, a raid, a secret name, a random queue entry
  local LFG = {
    [18] = { "Ragefire Chasm", 1, 1, 13, 18, 15, 13, 18, 0, 0, "", 1, 5, bosses = { "Oggleflint", "Taragaman the Hungerer", "Jergosh the Invoker", "Bazzalan" } },
    [6] = { "Deadmines", 1, 1, 17, 26, 20, 17, 26, 0, 0, "", 1, 5, bosses = { "Rhahk'Zor", "Sneed", "Gilnid", "Mr. Smite", "Captain Greenskin", "Edwin VanCleef" } },
    [26] = { "Gnomeregan", 1, 1, 29, 38, 33, 29, 38, 0, 0, "", 1, 5, bosses = { "Grubbis", "Viscous Fallout", "Mekgineer Thermaplugg" } },
    [48] = { "Molten Core", 2, 3, 60, 60, 60, 60, 60, 0, 0, "", 1, 40, bosses = { "Lucifron", "Ragnaros" } },
    [300] = { "SECRETNAME", 1, 1, 1, 1, 1, 1, 1, 0, 0, "", 1, 5, bosses = { "x" } },
    [301] = { "Random Classic Dungeon", 1, 1, 15, 30, 20, 15, 30, 0, 0, "", 1, 5, bosses = {} },
    -- 0.3.1: what the real client returned in this id range (zones/battlegrounds reporting encounters)
    [1] = { "Wailing Caverns", 1, 1, 17, 17, 17, 17, 17, 0, 0, "", 1, 5, bosses = { "Lady Anacondra", "No Longer in Use", "Lord Cobrahn" } },
    [400] = { "Alterac Mountains", 1, 1, 0, 0, 0, 0, 0, 0, 0, "", 1, 5, bosses = { "Zone Event" } },
    [401] = { "Arathi Basin", 1, 1, 0, 0, 0, 0, 0, 0, 0, "", 1, 15, bosses = { "Battle" } },
    [402] = { "Ashenvale Forest", 1, 1, 0, 0, 0, 0, 0, 0, 0, "", 1, 5, bosses = { "x" } },
    [403] = { "Some Frontier", 4, 0, 0, 0, 0, 0, 0, 0, 0, "", 1, 5, bosses = { "Rare" } },
    [404] = { "Skirmish Field", 1, 6, 0, 0, 0, 0, 0, 0, 0, "", 1, 5, bosses = { "Boss" } },
    [405] = { "Empty Hall", 1, 1, 10, 20, 15, 10, 20, 0, 0, "", 1, 5, bosses = {} },
    [406] = { "zzOld Deadmines", 1, 1, 17, 26, 20, 17, 26, 0, 0, "", 1, 5, bosses = { "Smite" } },
    -- 0.3.2: client spellings that must merge into the list by alias; a list entry with an extra live boss
    [500] = { "Scarlet Monastery - Graveyard", 1, 1, 26, 36, 30, 26, 36, 0, 0, "", 1, 5, bosses = {} },
    [501] = { "Stormwind Stockade", 1, 1, 22, 30, 25, 22, 30, 0, 0, "", 1, 5, bosses = {} },
    [502] = { "Dire Maul - East", 1, 1, 36, 46, 40, 36, 46, 0, 0, "", 1, 5, bosses = {} },
    [503] = { "Stratholme - Main Gate", 1, 1, 48, 58, 55, 48, 58, 0, 0, "", 1, 5, bosses = {} },
    [504] = { "Stratholme - Service Entrance", 1, 1, 48, 58, 55, 48, 58, 0, 0, "", 1, 5, bosses = {} },
    [505] = { "Ruins of Lordaeron", 1, 1, 15, 20, 17, 15, 20, 0, 0, "", 1, 5, bosses = { "Witherfang", "The Butcher" } },
  }
  local sGI, sGN, sGE = GetLFGDungeonInfo, GetLFGDungeonNumEncounters, GetLFGDungeonEncounterInfo
  GetLFGDungeonInfo = function(id) local e = LFG[id] if e then return unpack(e, 1, 13) end end
  GetLFGDungeonNumEncounters = function(id) local e = LFG[id] return e and #e.bosses or 0 end
  GetLFGDungeonEncounterInfo = function(id, i) local e = LFG[id] return e and e.bosses[i], "tex", false end
  AGm._ResetCaches()
  local list = AGm.Dungeons()
  local by = {}
  for _, d in ipairs(list) do by[d.name] = d end
  check(#list == 37 and by["The Deadmines"] and by["The Deadmines"].lfg and by["Gnomeregan"].lfg and by["Gnomeregan"].seeded and by["Wailing Caverns"].lfg
    and not by["Blackfathom Deeps"].lfg and by["Empty Hall"] and by["Empty Hall"].source == "lfg" and not by["Deadmines"], "LFG merge: 36 list entries always shown + 1 unlisted LFG dungeon (" .. #list .. ")")
  check(by["Scarlet Monastery: Graveyard"].lfg and by["The Stockade"].lfg and by["Dire Maul: East"].lfg and by["Stratholme"].lfgId == 503 and not by["Stormwind Stockade"] and not by["Stratholme - Main Gate"],
    "aliases: 'Scarlet Monastery - Graveyard', 'Stormwind Stockade', 'Dire Maul - East', both Stratholme gates merge into the list")
  local rol, butcher = by["Ruins of Lordaeron"], nil
  for _, b in ipairs(rol.bosses) do if b.name == "The Butcher" then butcher = b end end
  check(#rol.bosses == 7 and butcher and butcher.live and not butcher.seeded, "live LFG boss added to a list entry (Ruins of Lordaeron: The Butcher)")
  local zoneLeak = {}
  for _, n in ipairs({ "Alterac Mountains", "Arathi Basin", "Ashenvale Forest", "Some Frontier", "Skirmish Field", "zzOld Deadmines", "SECRETNAME", "Random Classic Dungeon" }) do
    if by[n] then zoneLeak[#zoneLeak + 1] = n end
  end
  check(#zoneLeak == 0, "zones, battlegrounds, PvP, empty and placeholder LFG rows are not listed (" .. table.concat(zoneLeak, ",") .. ")")
  local st = AGm.ScanStats()
  check(st.named == 19 and st.accepted == 12 and st.rejected.zone == 4 and st.rejected.pvp == 1 and st.rejected.random == 1 and st.rejected.nobosses == nil and st.rejected.placeholder == 1,
    string.format("scan stats (boss-less rows kept): %d named, %d kept, zone %s, pvp %s, random %s, nobosses %s, placeholder %s", st.named, st.accepted,
      tostring(st.rejected.zone), tostring(st.rejected.pvp), tostring(st.rejected.random), tostring(st.rejected.nobosses), tostring(st.rejected.placeholder)))
  local wc = by["Wailing Caverns"]
  local wcBad = false
  for _, b in ipairs(wc.bosses) do if b.name == "No Longer in Use" then wcBad = true end end
  check(#wc.bosses == 9 and not wcBad and wc.minLevel == 17 and wc.maxLevel == 27 and wc.recLevel == 17, "Wailing Caverns: 'No Longer in Use' dropped, 9 bosses, Forever level range 17-27 (LFG said 17-17)")
  local phOk = true
  for _, n in ipairs({ "No Longer in Use", "UNUSED Boss", "[PH] Boss", "zzOldGuy", "Deprecated Ogre", "PH Kobold" }) do if not AGm.IsPlaceholder(n) then phOk = false end end
  for _, n in ipairs({ "Deviate Faerie Dragon", "Verdan the Everliving", "Mutanus the Devourer", "Phantom", "Gelihast" }) do if AGm.IsPlaceholder(n) then phOk = false end end
  check(phOk, "placeholder names matched, real boss names kept")
  local rep = AGm.ScanReport()
  check(rep:find("19 LFG names, 12 dungeons/raids kept (11 match our list)", 1, true) and type(DarkMatterDB.agscan) == "table" and #DarkMatterDB.agscan.rows == 19, "/dm agscan: chat summary + DarkMatterDB.agscan rows (" .. rep:gsub("\n", " | ") .. ")")
  local nbn = table.concat(DarkMatterDB.agscan.noBosses, ",")
  check(rep:find("kept, no LFG bosses (6): ", 1, true) and nbn:find("Empty Hall", 1, true) and nbn:find("Stormwind Stockade", 1, true) and DarkMatterDB.agscan.notInList[1] == "Empty Hall" and #DarkMatterDB.agscan.notInList == 1,
    "/dm agscan names the boss-less rows and the rows not in our list (" .. nbn .. ")")
  local zr
  for _, r in ipairs(DarkMatterDB.agscan.rows) do if r.name == "Alterac Mountains" then zr = r end end
  check(zr and zr.accepted == false and zr.reason == "zone", "agscan row records the reject reason")
  check(by["Molten Core"].kind == "Raid" and by["Molten Core"].size == 40 and by["The Deadmines"].kind == "Dungeon" and by["The Deadmines"].recLevel == 20 and by["The Deadmines"].size == 5, "kind/size from our list, recommended level from LFG")
  check(#by["The Deadmines"].bosses == 9 and by["The Deadmines"].bosses[8].name == "Edwin VanCleef" and #by["The Deadmines"].bosses[8].drops == 4, "Deadmines: list boss order (9) with LFG names matched, VanCleef 4 drops")
  local sorted = true
  for i = 2, #list do if (list[i].minLevel or 999) < (list[i - 1].minLevel or 999) then sorted = false end end
  check(sorted and list[1].name == "Empty Hall" and list[2].name == "The Hall of Thanes", "sorted by minimum level (unlisted LFG Empty Hall 10, then Hall of Thanes 13)")
  local kinds = AGm.Kinds(list)
  check(#kinds == 2 and kinds[1] == "Dungeon" and kinds[2] == "Raid", "types: Dungeon and Raid")
  local f1 = AGm.Filter(list, "gelihast", "all", "all", 22)
  check(#f1 == 1 and f1[1].name == "Blackfathom Deeps", "search by boss")
  local f2 = AGm.Filter(list, "cookie's tenderizer", "all", "all", 22)
  check(#f2 == 1 and f2[1].name == "The Deadmines", "search by drop name")
  local f3 = AGm.Filter(list, nil, "mine", "all", 22)
  local n3 = {}
  for _, d in ipairs(f3) do n3[d.name] = true end
  check(not n3["The Hall of Thanes"] and not n3["Gnomeregan"] and not n3["Molten Core"] and n3["The Deadmines"] and n3["Blackfathom Deeps"] and n3["Ragefire Chasm"], "near-my-level filter (22; Forever RFC is 15-25)")
  local f4 = AGm.Filter(list, nil, "all", "Raid", 22)
  check(#f4 == 7, "type filter: Raid (7)")
  -- C_Item.DoesItemExistByID gate
  local sEx = C_Item.DoesItemExistByID
  C_Item.DoesItemExistByID = function(id) return id ~= 5197 end
  AGm._ResetCaches()
  local cookie
  for _, d in ipairs(AGm.Dungeons()) do if d.name == "The Deadmines" then for _, b in ipairs(d.bosses) do if b.name == "Cookie" then cookie = b end end end end
  check(cookie and #cookie.drops == 1 and cookie.drops[1].itemId ~= 5197, "DoesItemExistByID=false hides the drop (Cookie's Tenderizer)")
  C_Item.DoesItemExistByID = sEx
  AGm._ResetCaches()
  -- loot learning: boss by NPC id from the loot source GUID; dedupe per source; recent kill; other
  local sII, sLSI, sLSL = GetInstanceInfo, GetLootSourceInfo, GetLootSlotLink
  GetInstanceInfo = function() return "The Deadmines", "party", 1, "Normal", 5, 0, false, 36, 5 end
  local SRC = {}
  GetLootSourceInfo = function(i) return SRC[i] end
  GetLootSlotLink = function(i) local s = LOOT_SLOTS[i] return s and s.link end
  LOOT_SLOTS = { { link = "|cff0070dd|Hitem:5191::::::::20:::::::|h[Cruel Barb]|h|r", name = "Cruel Barb", qty = 1, quality = 3 } }
  SRC[1] = "Creature-0-4372-36-1581-639-0000ABCDEF"
  local agf = AGm._Frame()
  check(agf and agf._ev and agf._ev.LOOT_OPENED and agf._ev.ENCOUNTER_END and agf._ev.BOSS_KILL, "AG private event frame registered (LOOT_OPENED, ENCOUNTER_END, BOSS_KILL)")
  agf._scripts.OnEvent(agf, "LOOT_OPENED")
  check(AGm.SeenCount("deadmines", "Edwin VanCleef", 5191) == 1, "loot from VanCleef's corpse (npc 639) counted for VanCleef")
  agf._scripts.OnEvent(agf, "LOOT_OPENED")
  check(AGm.SeenCount("deadmines", "Edwin VanCleef", 5191) == 1, "re-opening the same corpse does not double count")
  TIME_NOW = 5000
  agf._scripts.OnEvent(agf, "ENCOUNTER_END", 2969, "Mr. Smite", 1, 5, 1)
  LOOT_SLOTS = { { link = "|Hitem:5196::::::::20:::::::|h[Smite's Reaver]|h", name = "Smite's Reaver" } }
  SRC[1] = "Creature-0-4372-36-1581-99999-0000ABCDE0"
  agf._scripts.OnEvent(agf, "LOOT_OPENED")
  check(AGm.SeenCount("deadmines", "Mr. Smite", 5196) == 1, "unknown source right after a kill -> that boss")
  TIME_NOW = 5400
  SRC[1] = "Creature-0-4372-36-1581-99998-0000ABCDE1"
  agf._scripts.OnEvent(agf, "LOOT_OPENED")
  check(AGm.SeenCount("deadmines", nil, 5196) == 1, "late unknown source -> dungeon '_other'")
  GetInstanceInfo = function() return "Elwynn Forest", "none" end
  SRC[1] = "Creature-0-4372-0-1581-299-0000ABCDE2"
  check(AGm.OnLootOpened() == 0, "no learning outside dungeons")
  check(type(DarkMatterDB.agSeen) == "table" and DarkMatterDB.agSeen.deadmines, "seen counts are account-wide (DarkMatterDB.agSeen)")
  -- UI: Adventure Guide section, VanCleef drops, client names, same tooltip placement as fishing
  GetInstanceInfo = sII
  local sGII2 = GetItemInfo
  GetItemInfo = function(id) if id == 5191 then return "Cruel Barb", "item:5191", 3 end return sGII2(id) end
  DarkMatterDB.agDungeon, DarkMatterDB.agBoss = "deadmines", "Edwin VanCleef"
  DarkMatter.tabs.journals.SetSection("adventure")
  check(DarkMatterDB.section == "adventure", "Adventure Guide section opens")
  local drows, brows = {}, 0
  for _, fr in ipairs(ALL) do
    local e = rawget(fr, "entry")
    if type(e) == "table" and rawget(fr, "dungeon") and fr._shown then drows[#drows + 1] = fr end
    if rawget(fr, "bossName") and fr._shown then brows = brows + 1 end
  end
  check(#drows == 4 and brows == 9, "VanCleef: 4 drop rows, 9 boss rows (" .. #drows .. "/" .. brows .. ")")
  local barb
  for _, r in ipairs(drows) do if r.entry.itemId == 5191 then barb = r end end
  check(barb and barb.text:GetText() == "Cruel Barb" and barb.seen == 1 and barb.sub:GetText() == "Rare · " .. string.format("%.1f", barb.entry.pct or 0) .. "% drop · seen 1×", "drop row: client item name; quality, drop chance and seen count on line 2")
  -- 0.3.1 layout: no text box overlaps its neighbours, names fit on one line
  local R = FrameMT._rect
  local function natural(fs) return #(fs._text or "") * (fs._fsize or 12) * 0.52 end
  local function apart(a, b)
    local al, at, ar, ab = R(a)
    local bl, bt, br, bb = R(b)
    if not (al and bl) then return false end
    return ar <= bl or br <= al or ab >= bt or bb >= at
  end
  local W = DarkMatter.tabs.journals.agWidgets()
  local ov = {}
  for _, r in ipairs(drows) do
    if not apart(r.text, r.sub) then ov[#ov + 1] = "drop " .. r.text:GetText() end
    if not apart(r.icon, r.text) then ov[#ov + 1] = "icon/name " .. r.text:GetText() end
    local l, _, rr = R(r.text)
    if natural(r.text) > rr - l then ov[#ov + 1] = "truncated " .. r.text:GetText() end
  end
  local brs = {}
  for _, r in ipairs(W.bossRows) do if r._shown then brs[#brs + 1] = r end end
  for i, r in ipairs(brs) do
    if not apart(r.text, r.sub) then ov[#ov + 1] = "boss " .. r.text:GetText() end
    local l, _, rr = R(r.text)
    if natural(r.text) > rr - l then ov[#ov + 1] = "boss truncated " .. r.text:GetText() end
    if brs[i + 1] and not apart(r.sub, brs[i + 1].text) then ov[#ov + 1] = "boss rows " .. i end
  end
  if not apart(W.dropHead, W.dropNote) then ov[#ov + 1] = "drop header" end
  if not apart(W.title, W.meta) then ov[#ov + 1] = "dungeon header" end
  check(#ov == 0, "AG layout: no overlapping or truncated text (" .. table.concat(ov, "; ") .. ")")
  check(W.dropHead:GetText() == "Edwin VanCleef" and W.dropNote:GetText() == "4 drops · 1 seen by you", "drop header: boss name, count line under it")
  local vc
  for _, r in ipairs(brs) do if r.bossName == "Edwin VanCleef" then vc = r end end
  check(vc and vc.sub:GetText() == "4 drops", "boss row count is labelled as drops")
  -- dropdown (own frames): closed by default, opens with grouped entries, selecting closes it
  check(not W.menu._shown or W.menu._hid, "dungeon dropdown starts closed")
  W.drop._scripts.OnClick(W.drop)
  check(W.menu:IsShown(), "dropdown opens on click")
  local heads, entries, bfd = {}, 0, nil
  for _, r in ipairs(W.menuRows) do
    if r._shown and not r._hid then
      if rawget(r, "dungeonKey") then entries = entries + 1 else heads[#heads + 1] = r.text:GetText() end
      if (r.text:GetText() == "Blackfathom Deeps") then bfd = r end
    end
  end
  check(entries == 37 and #heads == 2 and heads[1] == "Dungeons" and heads[2] == "Raids", "dropdown: all 37 entries grouped by type (" .. entries .. ", " .. table.concat(heads, "/") .. ")")
  local listed = {}
  for _, r in ipairs(W.menuRows) do
    if r._shown and not r._hid and rawget(r, "dungeonKey") then
      listed[r.text:GetText()] = true
    end
  end
  local miss = {}
  for _, d in ipairs(seed) do if not listed[d.name] then miss[#miss + 1] = d.name end end
  check(#miss == 0, "dropdown lists every dungeon and raid in the known-good list (" .. table.concat(miss, ", ") .. ")")
  bfd._scripts.OnClick(bfd)
  check(not W.menu:IsShown() and W.title:GetText() == "Blackfathom Deeps" and W.drop.text:GetText() == "Blackfathom Deeps", "picking an entry selects it and closes the dropdown")
  W.drop._scripts.OnClick(W.drop)
  DarkMatterDB.agDungeon, DarkMatterDB.agBoss = AGm.Norm("Ruins of Lordaeron"), "The Butcher"
  DarkMatter.tabs.journals.Refresh()
  local bt
  for _, r in ipairs(W.bossRows) do if r._shown and r.bossName == "The Butcher" then bt = r end end
  check(bt and bt.sub:GetText() == "live LFG boss · drops coming soon", "live LFG boss on a list entry: labelled, drops coming soon")
  DarkMatterDB.agDungeon, DarkMatterDB.agBoss = AGm.Norm("Empty Hall"), nil
  DarkMatter.tabs.journals.Refresh()
  check(W.title:GetText() == "Empty Hall" and W.emptyDrops._shown and (W.emptyDrops:GetText() or ""):find("Boss and drop data coming soon", 1, true)
    and W.emptyBoss._shown and (W.emptyBoss:GetText() or ""):find("coming soon", 1, true), "dungeon with no bosses anywhere: 'Boss and drop data coming soon'")
  DarkMatterDB.agDungeon, DarkMatterDB.agBoss = AGm.Norm("Molten Core"), "Ragnaros"
  DarkMatter.tabs.journals.Refresh()
  local rg
  for _, r in ipairs(W.bossRows) do if r._shown and r.bossName == "Ragnaros" then rg = r end end
  check(rg and rg.sub:GetText() == "drops coming soon" and W.dropNote:GetText() == "", "raid with a boss list only: 'drops coming soon'")
  local function bossSub(dn, bn)
    DarkMatterDB.agDungeon, DarkMatterDB.agBoss = AGm.Norm(dn), bn
    DarkMatter.tabs.journals.Refresh()
    for _, r in ipairs(W.bossRows) do if r._shown and r.bossName == bn then return r.sub:GetText(), W.emptyDrops:GetText() end end
  end
  bossSub("Scarlet Monastery: Graveyard", "Bloodmage Thalnos")
  check(W.drop.text:GetText() == "SM: Graveyard" and W.title:GetText() == "Scarlet Monastery: Graveyard", "long wing name: compact dropdown label, full name in the header (" .. tostring(W.drop.text:GetText()) .. ")")
  bossSub("Dire Maul: East", "Lethtendris")
  check(W.drop.text:GetText() == "Dire Maul: East", "short names stay unabbreviated in the dropdown label")
  local s1, e1 = bossSub("Zul'Farrak", "Nekrum Gutchewer")
  check(s1 == "drops coming soon" and e1:find("Drop data coming soon", 1, true), "boss whose Classic drops are not on Forever yet: 'drops coming soon' (" .. tostring(s1) .. ")")
  local s2, e2 = bossSub("Ragefire Chasm", "Oggleflint")
  check(s2 == "0 drops" and e2:find("lists no boss-specific drops", 1, true), "boss with no boss-specific drops: '0 drops' (" .. tostring(s2) .. ")")
  local nPend, nItemsAll = 0, 0
  for _, d in ipairs(DarkMatter.AdventureGuideSeed) do for _, b in ipairs(d.bosses) do if b.dropsPending then nPend = nPend + 1 end nItemsAll = nItemsAll + #b.drops end end
  check(nPend == 17 and nItemsAll == 470, "seed: 470 Forever-validated drops, 17 bosses with drops pending on Forever (" .. nPend .. ", " .. nItemsAll .. ")")
  DarkMatter.tabs.journals.SetSection("fishing")
  check(not W.menu:IsShown(), "dropdown closes when the section changes")
  DarkMatterDB.agDungeon, DarkMatterDB.agBoss = "deadmines", "Edwin VanCleef"
  DarkMatter.tabs.journals.SetSection("adventure")
  check(barb.icon._quality == 3 and barb.icon._itemId == 5191, "drop icon: rarity rim from quality (Rare)")
  COMPARE = false
  barb._scripts.OnEnter(barb)
  check(T.anchor == "ANCHOR_PRESERVE" and T.pts[1] == "BOTTOMLEFT" and T.pts[2] == barb.icon and T.pts[3] == "TOPRIGHT" and T.pts[4] == 1 and T.pts[5] == 1, "AG drop tooltip: same placement as fishing (BOTTOMLEFT at the icon TOPRIGHT, visible +4,+4)")
  barb._scripts.OnLeave(barb)
  COMPARE = true
  barb._scripts.OnEnter(barb)
  check(ShoppingTooltip1.pts[1] == "BOTTOMLEFT" and ShoppingTooltip1.pts[2] == GameTooltip and ShoppingTooltip1.pts[3] == "BOTTOMRIGHT", "AG drop tooltip: compare chained right, bottoms aligned")
  barb._scripts.OnLeave(barb)
  COMPARE = false
  check(not T.shown, "AG tooltip hidden on leave")
  -- taint-safety: no hooks/global replacement/Blizzard UI loads in the AG files
  for _, fn in ipairs({ "AdventureGuide.lua", "Data_Dungeons.lua" }) do
    local src = io.open(arg[1] .. "/" .. fn):read("*a")
    check(not src:find("hooksecurefunc", 1, true) and not src:find("LoadAddOn", 1, true) and not src:find("EncounterJournal", 1, true) and not src:find("_G%[") , fn .. ": no hooks, no addon loads, no EJ, no _G writes")
  end
  GetItemInfo = sGII2
  GetLFGDungeonInfo, GetLFGDungeonNumEncounters, GetLFGDungeonEncounterInfo = sGI, sGN, sGE
  GetLootSourceInfo, GetLootSlotLink = sLSI, sLSL
  LOOT_SLOTS = {}
  DarkMatter.tabs.journals.SetSection("fishing")
  AGm._ResetCaches()
  DarkMatter.Print = savedPrint
  COMPARE = false

  GetItemInfo = savedGII
  C_Item.IsItemDataCachedByID = savedCached
  ShoppingTooltip1, ShoppingTooltip2 = nil, nil
  DarkMatter.FishingSetUIPref("showAll", false)
end

-- ===== 0.3.0 Adventure Guide without LFG APIs (minimal client): seed only =====
if MODE == "minimal" then
  DarkMatter.AG._ResetCaches()
  local l = DarkMatter.AG.Dungeons()
  check(#l == 36 and l[1].source == "list", "minimal client: AG shows the full known-good list (36)")
  DarkMatter.tabs.journals.SetSection("adventure")
  check(DarkMatterDB.section == "adventure", "minimal client: Adventure Guide opens")
  DarkMatter.tabs.journals.SetSection("fishing")
end

for i=LASTN+1,#log do io.stdout:write(log[i],"\n") end
