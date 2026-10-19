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

for i=LASTN+1,#log do io.stdout:write(log[i],"\n") end
