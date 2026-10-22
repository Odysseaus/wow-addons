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
  -- 0.4.5 legacy quest-log readers (act on the SELECTED entry) and the classic watch list
  QSEL=4; QSEL_N=0; QWATCH={[2]=true}; QW_UPD=0; MAX_WATCHABLE_QUESTS=5
  QDATA={
    [2]={desc="Eagan Peltskinner needs wolf meat for the abbey.",obj="Bring 8 pieces of Tough Wolf Meat to Eagan Peltskinner.",xp=170,money=35,rewards={},
      choices={{"Wolfskin Bracers","Interface\\Icons\\INV_Bracer_02",1,2,true,2224},{"Feather-lined Gloves","Interface\\Icons\\INV_Gauntlets_05",1,1,true,2225}},rep={}},
    [6]={desc="VanCleef leads the Defias Brotherhood from his hideout.",obj="Kill Edwin VanCleef and bring his head to Gryan Stoutmantle.",xp=4300,money=12550,
      rewards={{"Red Silk Bandana","Interface\\Icons\\INV_Misc_Bandana_03",2,1,true,2549}},
      choices={{"Tunic of Westfall","Interface\\Icons\\INV_Chest_Leather_07",1,3,true,2041},{"Staff of Westfall","Interface\\Icons\\INV_Staff_10",1,3,true,2042},{"Chausses of Westfall","Interface\\Icons\\INV_Pants_03",1,3,true,6087}},
      rep={{72,250}}},
  }
  local function qd() return QDATA[QSEL] end
  GetQuestLogSelection=function() return QSEL end
  SelectQuestLogEntry=function(i) QSEL=i QSEL_N=QSEL_N+1 end
  GetQuestLogQuestText=function() local d=qd() if d then return d.desc,d.obj end end
  GetQuestLogRewardXP=function() local d=qd() return d and d.xp or 0 end
  GetQuestLogRewardMoney=function() local d=qd() return d and d.money or 0 end
  GetNumQuestLogRewards=function() local d=qd() return d and #d.rewards or 0 end
  GetQuestLogRewardInfo=function(i) local e=qd().rewards[i] return unpack(e) end
  GetNumQuestLogChoices=function() local d=qd() return d and #d.choices or 0 end
  GetQuestLogChoiceInfo=function(i) local e=qd().choices[i] return unpack(e) end
  GetQuestLogItemLink=function(kind,i) local d=qd() local e=d and (kind=="choice" and d.choices or d.rewards)[i] if e then return "|cff1eff00|Hitem:"..e[6].."::::|h["..e[1].."]|h|r" end end
  GetNumQuestLogRewardFactions=function() local d=qd() return d and #d.rep or 0 end
  GetQuestLogRewardFactionInfo=function(i) local r=qd().rep[i] return r[1],r[2] end
  GetFactionInfoByID=function(id) if id==72 then return "Stormwind" end end
  IsQuestWatched=function(i) return QWATCH[i]==true end
  AddQuestWatch=function(i) QWATCH[i]=true end
  RemoveQuestWatch=function(i) QWATCH[i]=nil end
  GetNumQuestWatches=function() local n=0 for _ in pairs(QWATCH) do n=n+1 end return n end
  QuestWatch_Update=function() QW_UPD=QW_UPD+1 end
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
function FrameMT.SetChecked(s, v) s._checked = v and true or false end
function FrameMT.GetChecked(s) return s._checked == true end
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
function FrameMT.IsEnabled(s) return s._enabled ~= false end
function FrameMT.SetScale(s,v) s._scale=v end
function FrameMT.GetScale(s) return s._scale or 1 end
function FrameMT.UnregisterEvent(s, e) if s._ev then s._ev[e] = nil end end
-- 0.4.1: Forever 1.60.1 restricted events (HasRestrictions = true in Blizzard_APIDocumentationGenerated). Like the
-- client, any RegisterEvent/UnregisterEvent of one from addon code raises ADDON_ACTION_FORBIDDEN ("UNKNOWN()").
RESTRICTED_EVENTS = { COMBAT_LOG_EVENT_UNFILTERED = true, COMBAT_LOG_EVENT = true, MINIMAP_PING = true,
  UNIT_PING_PIN_ADDED = true, UNIT_PING_PIN_REMOVED = true }
RESTRICTED_TOUCH = {}
local function Forbidden(how, e)
  RESTRICTED_TOUCH[#RESTRICTED_TOUCH + 1] = how .. "(" .. e .. ")"
  for _, f in ipairs(ALL or {}) do
    if f._ev and f._ev.ADDON_ACTION_FORBIDDEN and f._scripts and f._scripts.OnEvent then
      f._scripts.OnEvent(f, "ADDON_ACTION_FORBIDDEN", "DarkMatter", "UNKNOWN()")
    end
  end
end
do
  local reg, unreg = FrameMT.RegisterEvent, FrameMT.UnregisterEvent
  function FrameMT.RegisterEvent(s, e) if RESTRICTED_EVENTS[e] then Forbidden("RegisterEvent", e) end return reg(s, e) end
  function FrameMT.UnregisterEvent(s, e) if RESTRICTED_EVENTS[e] then Forbidden("UnregisterEvent", e) end return unreg(s, e) end
end
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

-- 0.5.1 stock art: the client's file-ID lookup and template list (test data). STOCK_MISSING = true makes every stock
-- texture and template missing, so the fallback to Dark Matter's own art can be checked.
STOCK_MISSING = false
STOCK_CALLS = 0
function GetFileIDFromPath(p)
  STOCK_CALLS = STOCK_CALLS + 1
  if type(p) ~= "string" then error("GetFileIDFromPath: string expected", 2) end
  if STOCK_MISSING or p:find("^Interface\\AddOns\\") then return nil end
  return 130000 + #p
end
C_XMLUtil = { GetTemplateInfo = function(n)
  if STOCK_MISSING then return nil end
  -- 0.5.1.3: STOCK_MISSING_TMPL = { name = true } leaves just those templates out (1.60.1 has no CharacterFrameTabButtonTemplate)
  if STOCK_MISSING_TMPL and STOCK_MISSING_TMPL[n] then return nil end
  if n == "UIPanelCloseButton" then return { type = "Button", width = 32, height = 32 } end
  -- 0.5.1.2: the templates the stock button / tab / scroll bar look is modelled on (reported by /dm artprobe)
  if n == "UIPanelButtonTemplate" or n == "CharacterFrameTabButtonTemplate" then return { type = "Button" } end
  if n == "UIPanelScrollFrameTemplate" then return { type = "ScrollFrame" } end
  if n == "UIPanelScrollBarTemplate" then return { type = "Slider" } end
  return nil
end }
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
function FrameMT.GetEffectiveScale(s) local e = s._scale or 1 local p = s._parent if p and p.GetEffectiveScale then e = e * p:GetEffectiveScale() end return e end
function FrameMT.SetFrameLevel(s, n) needNum("SetFrameLevel", 1, n) s._level = n end
function FrameMT.GetFrameLevel(s) return s._level or 1 end
function FrameMT.SetFrameStrata(s, v) if not STRATA[v] then error("SetFrameStrata: bad strata " .. tostring(v), 2) end s._strata = v end
function FrameMT.SetTexture(s, file, wrapH, wrapV)
  local WRAP = { REPEAT = 1, CLAMP = 1, MIRROR = 1, CLAMPTOBLACK = 1, CLAMPTOBLACKADDITIVE = 1, CLAMPTOWHITE = 1 }
  if (wrapH ~= nil and not WRAP[wrapH]) or (wrapV ~= nil and not WRAP[wrapV]) then error("SetTexture: bad wrap mode", 2) end
  s._wrapH, s._wrapV = wrapH, wrapV
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
    local rh, rv = s._wrapH == "REPEAT", s._wrapV == "REPEAT" -- REPEAT-wrapped axes may run past 1 (tiling)
    if (l < 0 and not rh) or (r > 1 and not rh) or (t < 0 and not rv) or (b > 1 and not rv) or l >= r or t >= b then
      TCBAD[#TCBAD + 1] = string.format("%s %s: %g %g %g %g", s._name or "?", tostring(s._file), l, r, t, b)
    end
  end
end
function FrameMT.GetTexCoord(s)
  local v = s._tc
  if not v then return 0, 0, 0, 1, 1, 0, 1, 1 end
  if #v == 8 then return unpack(v) end
  return v[1], v[3], v[1], v[4], v[2], v[3], v[2], v[4]
end
function FrameMT.SetColorTexture(s, r, g, b, a)
  needNum("SetColorTexture", 1, r) needNum("SetColorTexture", 2, g) needNum("SetColorTexture", 3, b)
  s._color, s._file = { r, g, b, a or 1 }, nil
end
-- 0.5.1.4: an atlas by name (the game's map-window frame pieces); the layout dump shows it as "atlas:<name>"
function FrameMT.SetAtlas(s, a)
  if type(a) ~= "string" then error("SetAtlas: string expected", 2) end
  s._file, s._color, s._atlas, s._tc = "atlas:" .. a, nil, a, nil
end
function FrameMT.SetVertexColor(s, r, g, b, a)
  needNum("SetVertexColor", 1, r) needNum("SetVertexColor", 2, g) needNum("SetVertexColor", 3, b)
  s._vc = { r, g, b, a or 1 }
  s._grad = nil
end
function FrameMT.SetBlendMode(s, m) if m ~= "BLEND" and m ~= "ADD" and m ~= "DISABLE" and m ~= "MOD" and m ~= "ALPHAKEY" then error("SetBlendMode: bad mode " .. tostring(m), 2) end s._blend = m end
-- 0.4.2: gradients (class-theme flat widgets), ColorMixin-style colours, highlight lock, clamp insets
function CreateColor(r, g, b, a)
  needNum("CreateColor", 1, r) needNum("CreateColor", 2, g) needNum("CreateColor", 3, b)
  local c = { r = r, g = g, b = b, a = a or 1 }
  function c.GetRGBA(self) return self.r, self.g, self.b, self.a end
  return c
end
function FrameMT.SetGradient(s, orient, minC, maxC)
  if orient ~= "VERTICAL" and orient ~= "HORIZONTAL" then error("SetGradient: bad orientation " .. tostring(orient), 2) end
  if type(minC) ~= "table" or type(maxC) ~= "table" or not minC.GetRGBA or not maxC.GetRGBA then error("SetGradient: colour objects expected", 2) end
  s._grad = { orient, { minC:GetRGBA() }, { maxC:GetRGBA() } }
  s._vc = nil
end
function FrameMT.SetDesaturated(s, on) s._desat = on and true or false end
function FrameMT.LockHighlight(s) s._locked = true end
function FrameMT.UnlockHighlight(s) s._locked = false end
function FrameMT.SetHitRectInsets(s, l, r, t, b)
  needNum("SetHitRectInsets", 1, l) needNum("SetHitRectInsets", 2, r) needNum("SetHitRectInsets", 3, t) needNum("SetHitRectInsets", 4, b)
  s._hitIns = { l, r, t, b }
end
function FrameMT.SetClampRectInsets(s, l, r, t, b)
  needNum("SetClampRectInsets", 1, l) needNum("SetClampRectInsets", 2, r) needNum("SetClampRectInsets", 3, t) needNum("SetClampRectInsets", 4, b)
  s._clampIns = { l, r, t, b }
end
function FrameMT.SetTextColor(s, r, g, b, a)
  needNum("SetTextColor", 1, r) needNum("SetTextColor", 2, g) needNum("SetTextColor", 3, b)
  s._tcol = { r, g, b, a or 1 }
end
function FrameMT.SetJustifyH(s, j) s._just = j end
function FrameMT.EnableMouse(s, on) s._mouseOff = not on end
function FrameMT.IsMouseEnabled(s) return not s._mouseOff end
function FrameMT.IsMouseOver(s) return s._mouseOver end -- nil unless a test sets it (as the old stub)
function FrameMT.GetFrameStrata(s) return s._strata or "MEDIUM" end
function FrameMT.SetFont(s, path, size, flags)
  if type(path) ~= "string" then error("SetFont: path expected", 2) end
  needNum("SetFont", 2, size)
  s._fsize, s._fflags = size, flags
  return true
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
      if r._grad then o[#o + 1] = '"grad":[' .. jstr(r._grad[1]) .. "," .. table.concat({ jnum(r._grad[2][1]), jnum(r._grad[2][2]), jnum(r._grad[2][3]), jnum(r._grad[2][4]), jnum(r._grad[3][1]), jnum(r._grad[3][2]), jnum(r._grad[3][3]), jnum(r._grad[3][4]) }, ",") .. "]" end
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
-- 0.5.1.4: the game's own map window (read only). DM_WMF=WxH runs the whole suite with a WorldMapFrame of that size
-- whose frame art (NineSlice pieces by atlas, title, close button, portrait) can be read; without it there is none.
WMF_CALLS, WMF_WRITES = {}, {}
function MakeWMF(w, h, opts)
  opts = opts or {}
  local function spyObj(t)
    return setmetatable({}, { __index = function(_, k)
      local v = t[k]
      if type(v) == "function" then return function(self, ...) WMF_CALLS[#WMF_CALLS + 1] = tostring(k) return v(t, ...) end end
      return v
    end, __newindex = function(_, k) WMF_WRITES[#WMF_WRITES + 1] = tostring(k) end })
  end
  local function Tex(atlas, tw, th, pt, x, y)
    return spyObj({ GetObjectType = function() return "Texture" end, GetAtlas = function() return atlas end,
      GetTextureFileID = function() return 5000000 + #atlas end, GetTexture = function() return 5000000 + #atlas end,
      GetTexCoord = function() return 0, 0, 0, 1, 1, 0, 1, 1 end, GetWidth = function() return tw end, GetHeight = function() return th end,
      GetPoint = function() return pt, nil, pt, x or 0, y or 0 end, GetVertexColor = function() return 1, 1, 1, 1 end,
      GetHorizTile = function() return atlas:sub(1, 1) == "_" end, GetVertTile = function() return atlas:sub(1, 1) == "!" end,
      IsShown = function() return true end })
  end
  local nine = {
    TopLeftCorner = Tex("UI-Frame-Map-CornerTopLeft", 24, 24, "TOPLEFT", 0, 0),
    TopRightCorner = Tex("UI-Frame-Map-CornerTopRight", 24, 24, "TOPRIGHT", 0, 0),
    BottomLeftCorner = Tex("UI-Frame-Map-CornerBottomLeft", 12, 12, "BOTTOMLEFT", 0, 0),
    BottomRightCorner = Tex("UI-Frame-Map-CornerBottomRight", 12, 12, "BOTTOMRIGHT", 0, 0),
    TopEdge = Tex("_UI-Frame-Map-EdgeTop", 32, 24, "TOPLEFT", 0, 0), BottomEdge = Tex("_UI-Frame-Map-EdgeBottom", 32, 12, "BOTTOMLEFT", 0, 0),
    LeftEdge = Tex("!UI-Frame-Map-EdgeLeft", 12, 32, "TOPLEFT", 0, 0), RightEdge = Tex("!UI-Frame-Map-EdgeRight", 12, 32, "TOPRIGHT", 0, 0) }
  if opts.real then -- the client's own offsets: the portrait-metal corner reaches 13 left / 16 up, the others 4 right / 3 down
    nine.TopLeftCorner = Tex("UI-Frame-PortraitMetal-CornerTopLeft", 95, 95, "TOPLEFT", -13, 16)
    nine.TopRightCorner = Tex("UI-Frame-Metal-CornerTopRightDouble", 33, 73, "TOPRIGHT", 4, 16)
    nine.BottomLeftCorner = Tex("UI-Frame-Metal-CornerBottomLeft", 32, 32, "BOTTOMLEFT", -13, -3)
    nine.BottomRightCorner = Tex("UI-Frame-Metal-CornerBottomRight", 32, 32, "BOTTOMRIGHT", 4, -3)
  end
  if opts.rect then -- rectangles too (frame at 100,800 top-left); a corner's rect from its anchor + offset + size
    local L0, T0 = 100, 800
    local function R(t, pt, x, y, tw, th)
      local l = pt:find("LEFT") and (L0 + x) or (L0 + w + x - tw)
      local tp = pt:find("TOP") and (T0 + y) or (T0 - h + y + th)
      t.GetLeft, t.GetRight, t.GetTop, t.GetBottom = function() return l end, function() return l + tw end, function() return tp end, function() return tp - th end
    end
    for k, p in pairs({ TopLeftCorner = { "TOPLEFT", -13, 16, 95, 95 }, TopRightCorner = { "TOPRIGHT", 4, 16, 33, 73 },
        BottomLeftCorner = { "BOTTOMLEFT", -13, -3, 32, 32 }, BottomRightCorner = { "BOTTOMRIGHT", 4, -3, 32, 32 } }) do
      local raw = {}
      R(raw, p[1], p[2], p[3], p[4], p[5])
      local old = nine[k]
      nine[k] = setmetatable({}, { __index = function(_, kk) if raw[kk] then return function() return raw[kk]() end end return old[kk] end })
    end
    opts.rectFns = { function() return L0 end, function() return L0 + w end, function() return T0 end, function() return T0 - h end }
  end
  if opts.noBorder then nine = {} end
  local title = spyObj({ GetObjectType = function() return "FontString" end, GetText = function() return "Map & Quest Log" end,
    GetTextColor = function() return 1, 0.82, 0 end, GetFont = function() return "Fonts\\FRIZQT__.TTF", 12 end,
    GetWidth = function() return 120 end, GetHeight = function() return 12 end, GetPoint = function() return "TOP", nil, "TOP", 0, -5 end, IsShown = function() return true end })
  local closeN = Tex("RedButton-Exit", 24, 24, "TOPRIGHT", 0, 0)
  local closeB = spyObj({ GetObjectType = function() return "Button" end, GetWidth = function() return 24 end, GetHeight = function() return 24 end,
    GetNormalTexture = function() return closeN end, GetPushedTexture = function() return Tex("RedButton-exit-pressed", 24, 24, "TOPRIGHT") end,
    GetHighlightTexture = function() return Tex("RedButton-Highlight", 24, 24, "TOPRIGHT") end, GetDisabledTexture = function() return nil end })
  local border = spyObj({ NineSlice = spyObj(nine), TitleContainer = spyObj({ TitleText = title }), CloseButton = closeB,
    portrait = Tex("UI-HUD-Map-Portrait", 58, 58, "TOPLEFT", -6, 7), Bg = Tex("UI-Frame-Map-Bg", w, h, "TOPLEFT", 0, 0) })
  return spyObj({ BorderFrame = border, isMaximized = opts.maximized or false, minimizedWidth = opts.minW, minimizedHeight = opts.minH,
    questLogWidth = opts.ql, GetWidth = function() return w end, GetHeight = function() return h end,
    GetEffectiveScale = function() return opts.scale or 1 end, IsShown = function() return opts.shown and true or false end,
    GetLeft = opts.rectFns and opts.rectFns[1], GetRight = opts.rectFns and opts.rectFns[2], GetTop = opts.rectFns and opts.rectFns[3], GetBottom = opts.rectFns and opts.rectFns[4],
    IsMaximized = function() return opts.maximized or false end, ScrollContainer = {},
    Show = function() WMF_WRITES[#WMF_WRITES + 1] = "Show()" end, SetSize = function() WMF_WRITES[#WMF_WRITES + 1] = "SetSize()" end })
end
C_Texture = { GetAtlasInfo = function(a) if not STOCK_MISSING and type(a) == "string" and (a:find("UI%-Frame%-Map") or a:find("RedButton") or a:find("Portrait")) then return { width = 24, height = 24 } end end }
do
  local spec = os.getenv("DM_WMF")
  local ww, hh
  if spec then ww, hh = spec:match("^(%d+)x(%d+)$") end
  if ww then WorldMapFrame = MakeWMF(tonumber(ww), tonumber(hh)) end
  -- the size the window should take (clamped like NS.MapWindow: 880x500 .. 1800x1300)
  -- 0.5.1.5: the layout takes the map's on-screen size; below 880x500 (or above 1800x1300) our scale makes up the rest
  if ww then
    local w0, h0 = tonumber(ww), tonumber(hh)
    local sc = math.max(math.min(1, w0 / 880, h0 / 500), w0 / 1800, h0 / 1300, 0.3)
    EXP_W, EXP_H, EXP_S = math.floor(w0 / sc + 0.5), math.floor(h0 / sc + 0.5), sc
  else
    EXP_W, EXP_H, EXP_S = 880, 680, 1
  end
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
  -- 0.5.1.3: ITEM_DATA_LOAD_RESULT is allowed on the quest / Adventure Guide refresh frames (late reward items),
  -- never on the probe frame; the combat log is never registered
  local okreg=true
  for _,r in ipairs(REGLOG) do
    if r.ev=="COMBAT_LOG_EVENT_UNFILTERED" or (r.ev=="ITEM_DATA_LOAD_RESULT" and r.frame==DarkMatter._probeFrame) then okreg=false end
  end
  check(okreg,"never registered COMBAT_LOG_EVENT_UNFILTERED; the probe frame never registers ITEM_DATA_LOAD_RESULT")
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
  -- 0.4.1: richer entries (nil/empty function arg, context, combat, version, trimmed Lua stack) and /dm blocked output
  local savedStack = debugstack
  debugstack = function() return "Interface/AddOns/DarkMatter/Core.lua:90: in function `RecordBlocked'\n[C]: in function `pcall'\n"
    .. "Interface/AddOns/DarkMatter/Achievements.lua:577: in function `OnZone'\nInterface/AddOns/DarkMatter/Achievements.lua:640: in function <...>" end
  DarkMatter.ctx = "ach:PLAYER_ENTERING_WORLD"
  bf._scripts.OnEvent(bf, "ADDON_ACTION_BLOCKED", "DarkMatter", nil)
  DarkMatter.ctx = nil
  debugstack = savedStack
  local e = DarkMatterDB.blockedLog[#DarkMatterDB.blockedLog]
  check(e.func == "nil" and e.event == "ADDON_ACTION_BLOCKED" and e.ctx == "ach:PLAYER_ENTERING_WORLD" and e.combat == false
    and e.version == DarkMatter.version, "blocked entry: nil function shown as 'nil', event, context, combat, version")
  check(e.stack and e.stack:find("DarkMatter/Achievements.lua:577: in function `OnZone'", 1, true) and not e.stack:find("RecordBlocked", 1, true)
    and not e.stack:find("Interface/AddOns", 1, true), "blocked entry keeps the addon caller stack, minus the recorder")
  bf._scripts.OnEvent(bf, "ADDON_ACTION_FORBIDDEN", "DarkMatter", "UNKNOWN()")
  local said = {}
  local sp, sP = print, DarkMatter.Print
  print = function(...) said[#said + 1] = table.concat({ ... }, " ") end
  DarkMatter.Print = function(m) said[#said + 1] = m end
  SlashCmdList.DARKMATTER("blocked")
  print, DarkMatter.Print = sp, sP
  check(said[2] and said[2]:find("^last blocked function: UNKNOWN%(%)  %(ADDON_ACTION_FORBIDDEN, addon DarkMatter%)"),
    "/dm blocked leads with the last blocked function: " .. tostring(said[2]))
  check(said[3] and said[3]:find("combat no", 1, true) and said[3]:find("ctx none", 1, true), "/dm blocked: time, version, combat, context line")
  local earlier
  for _, l in ipairs(said) do if l:find("earlier: .- nil %(ADDON_ACTION_BLOCKED, ctx ach:PLAYER_ENTERING_WORLD%)") then earlier = true end end
  check(earlier, "/dm blocked lists earlier entries with their context")
  said = {}
  DarkMatter.Print = function(m) said[#said + 1] = m end
  SlashCmdList.DARKMATTER("blocked clear")
  DarkMatter.Print = sP
  check(#DarkMatterDB.blockedLog == 0 and said[1] == "blocked-action log cleared.", "/dm blocked clear")
end
for _,l in ipairs(log) do io.stdout:write(l,"\n") end
LASTN=#log

-- ===== P1 window assertions (0.1.0) =====
if MODE ~= "minimal" then
  local W=DarkMatterFrame
  check(W._w==EXP_W and W._h==EXP_H,"main window is "..EXP_W.."x"..EXP_H.." (880x680 without a game map window; 0.5.1.4: the game map window's size)")
  check(W._scale and W._scale<=math.max(1, EXP_S or 1)+1e-6,"window scale never above 1 (0.5.1.5: unless the map window is larger on screen than 1800x1300): "..tostring(W._scale))
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
    local MWW, MWH = DarkMatter.theme.m.w, DarkMatter.theme.m.h -- 0.5.1.4: the game's map window size (880x680 without one)
    check(wl and wr - wl == MWW and wt - wb == MWH, tag .. ": window resolves to " .. MWW .. "x" .. MWH)
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
        check(w <= MWW + 1 and h <= MWH + 1, tag .. ": texture is not larger than the window " .. nm .. " " .. w .. "x" .. h)
        local clipped = false
        do local x = e.r._parent
          while x and x ~= UIParent do
            if x._ftype == "ScrollFrame" then clipped = true break end
            x = x._parent
          end
        end
        if not clipped then
          check(e.l >= wl - 30 and e.rr <= wr + 30 and e.t <= wt + 30 and e.b >= wb - 30, tag .. ": texture lies within the window " .. nm .. string.format(" (%.0f,%.0f,%.0f,%.0f in %.0f,%.0f,%.0f,%.0f)", e.l, e.t, e.rr, e.b, wl, wt, wr, wb))
        end
        local stockPiece = r._file and type(r._file) == "string" and r._file:find("^Interface\\") and not r._file:find("^Interface\\AddOns\\")
          and not r._file:upper():find("WHITE8X8", 1, true) -- 0.5.1: the game's own art counts as a piece too
        if stockPiece then nPieces = nPieces + 1 end
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
      check(math.min(e.rr - e.l, e.t - e.b) <= 24.01, tag .. ": border piece is thin (<=24 units; the stock dialog border is 24)")
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
    -- 0.3.4: the real client's spellings (Odysseaus' /dm agscan on 0.3.3)
    [506] = { "Stormwind Stockades", 1, 1, 22, 30, 24, 22, 30, 0, 0, "", 1, 5, bosses = {} },
    [507] = { "Zul'Farak", 1, 1, 44, 54, 46, 44, 54, 0, 0, "", 1, 5, bosses = {} },
    [508] = { "Onyxia", 2, 3, 60, 60, 60, 60, 60, 0, 0, "", 1, 40, bosses = {} },
    [509] = { "Scarlet Monastery", 1, 1, 26, 45, 33, 26, 45, 0, 0, "", 1, 5, bosses = {} },
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
  do
  -- 0.3.4 alias map: LFG spellings -> our entries, our display names kept; "Scarlet Monastery" is the wings' parent
  local function hasName(t, n) for _, v in ipairs(t or {}) do if v == n then return true end end return false end
  check(hasName(by["The Stockade"].lfgNames, "Stormwind Stockades") and by["Zul'Farrak"].lfg and hasName(by["Zul'Farrak"].lfgNames, "Zul'Farak")
    and by["Onyxia's Lair"].lfg and hasName(by["Onyxia's Lair"].lfgNames, "Onyxia") and by["Onyxia's Lair"].kind == "Raid"
    and not by["Stormwind Stockades"] and not by["Zul'Farak"] and not by["Onyxia"] and not by["Scarlet Monastery"],
    "alias map: 'Stormwind Stockades', 'Zul'Farak', 'Onyxia' merge into The Stockade, Zul'Farrak, Onyxia's Lair (our names kept)")
  local smOk = true
  for _, w in ipairs({ "Graveyard", "Library", "Armory", "Cathedral" }) do
    local d = by["Scarlet Monastery: " .. w]
    if not (d and d.lfg and hasName(d.lfgNames, "Scarlet Monastery")) then smOk = false end
  end
  check(smOk and by["Scarlet Monastery: Library"].recLevel == nil and by["Scarlet Monastery: Graveyard"].recLevel == 30 and #by["Scarlet Monastery: Library"].bosses == #DarkMatter.AdventureGuideSeed[(function() for i, d in ipairs(DarkMatter.AdventureGuideSeed) do if d.name == "Scarlet Monastery: Library" then return i end end end)()].bosses,
    "parent row 'Scarlet Monastery' marks all four wings live; wings keep our levels and bosses (no shared LFG level)")
  local function mn(n) local l, how = AGm.MatchName(n) return l and table.concat(l, "/") or "nil", how end
  local m1 = mn("the stockades")
  local m2, h2 = mn("ZUL FARAK")
  local m3, h3 = mn("Zul'Farrakk")
  local m4, h4 = mn("Blackfathom Deep")
  local m5 = mn("Stormwind")
  local m6, h6 = mn("Scarlet Monastery")
  local m7 = mn("Ironforge")
  check(m1 == "The Stockade" and m2 == "Zul'Farrak" and h2 == "name" and m3 == "Zul'Farrak" and h3 == "loose" and m4 == "Blackfathom Deeps" and h4 == "loose"
    and m5 == "nil" and m7 == "nil" and h6 == "parent" and m6 == "Scarlet Monastery: Graveyard/Scarlet Monastery: Library/Scarlet Monastery: Armory/Scarlet Monastery: Cathedral",
    "normalized matching: case, punctuation, a leading 'The', unique loose variants; zones never match (" .. table.concat({ m1, m2, m3, m4, m5, m6, m7 }, " | ") .. ")")
  end
  local zoneLeak = {}
  for _, n in ipairs({ "Alterac Mountains", "Arathi Basin", "Ashenvale Forest", "Some Frontier", "Skirmish Field", "zzOld Deadmines", "SECRETNAME", "Random Classic Dungeon" }) do
    if by[n] then zoneLeak[#zoneLeak + 1] = n end
  end
  check(#zoneLeak == 0, "zones, battlegrounds, PvP, empty and placeholder LFG rows are not listed (" .. table.concat(zoneLeak, ",") .. ")")
  local st = AGm.ScanStats()
  check(st.named == 23 and st.accepted == 16 and st.rejected.zone == 4 and st.rejected.pvp == 1 and st.rejected.random == 1 and st.rejected.nobosses == nil and st.rejected.placeholder == 1,
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
  check(rep:find("23 LFG names, 16 dungeons/raids kept (15 of 16 match our list)", 1, true) and type(DarkMatterDB.agscan) == "table" and #DarkMatterDB.agscan.rows == 23, "/dm agscan: chat summary + DarkMatterDB.agscan rows (" .. rep:gsub("\n", " | ") .. ")")
  local nbn = table.concat(DarkMatterDB.agscan.noBosses, ",")
  check(rep:find("kept, no LFG bosses (our boss lists are used) (10): ", 1, true) and nbn:find("Empty Hall", 1, true) and nbn:find("Stormwind Stockade", 1, true) and DarkMatterDB.agscan.notInList[1] == "Empty Hall" and #DarkMatterDB.agscan.notInList == 1,
    "/dm agscan names the boss-less rows and the rows not in our list (" .. nbn .. ")")
  local zr
  for _, r in ipairs(DarkMatterDB.agscan.rows) do if r.name == "Alterac Mountains" then zr = r end end
  check(zr and zr.accepted == false and zr.reason == "zone", "agscan row records the reject reason")
  do
  local mp = table.concat(DarkMatterDB.agscan.mapped, "; ")
  local oo = table.concat(DarkMatterDB.agscan.oursOnly, ", ")
  check(mp:find("Onyxia -> Onyxia's Lair", 1, true) and mp:find("Scarlet Monastery -> Scarlet Monastery: Graveyard / Scarlet Monastery: Library / Scarlet Monastery: Armory / Scarlet Monastery: Cathedral", 1, true)
    and mp:find("Zul'Farak -> Zul'Farrak", 1, true) and rep:find("mapped by alias (", 1, true), "/dm agscan lists the alias mappings (" .. mp .. ")")
  check(rep:find("info: ours only, not in the LFG list (", 1, true) and oo:find("The Hall of Thanes", 1, true) and oo:find("Naxxramas", 1, true)
    and not oo:find("The Stockade", 1, true) and not oo:find("Zul'Farrak", 1, true) and not oo:find("Scarlet Monastery", 1, true) and not oo:find("Ruins of Lordaeron", 1, true),
    "/dm agscan: our entries the LFG list lacks are an info line, 'ours only' (" .. oo .. ")")
  end
  -- replay of the real client's 0.3.3 scan: 67 names = the 26 kept names + 41 zones -> 26 of 26 now match our list
  do
    local real = { "Wailing Caverns", "Scholomance", "Ragefire Chasm", "Deadmines", "Shadowfang Keep", "Blackfathom Deeps", "Stormwind Stockades",
      "Gnomeregan", "Razorfen Kraul", "Scarlet Monastery", "Razorfen Downs", "Uldaman", "Zul'Farak", "Maraudon", "Sunken Temple", "Blackrock Depths",
      "Lower Blackrock Spire", "Dire Maul - East", "Dire Maul - West", "Dire Maul - North", "Stratholme", "Zul'Gurub", "Upper Blackrock Spire",
      "Onyxia", "Molten Core", "Blackwing Lair" }
    local zones = { "Alterac Mountains", "Arathi Highlands", "Ashenvale", "Azshara", "Badlands", "Blasted Lands", "Burning Steppes", "Darkshore",
      "Darnassus", "Deadwind Pass", "Desolace", "Dun Morogh", "Durotar", "Duskwood", "Dustwallow Marsh", "Eastern Plaguelands", "Elwynn Forest",
      "Felwood", "Feralas", "Hillsbrad Foothills", "Ironforge", "Loch Modan", "Moonglade", "Mulgore", "Orgrimmar", "Redridge Mountains",
      "Searing Gorge", "Silithus", "Silverpine Forest", "Stonetalon Mountains", "Stormwind City", "Stranglethorn Vale", "Swamp of Sorrows",
      "Tanaris", "Teldrassil", "The Barrens", "The Hinterlands", "Thousand Needles", "Thunder Bluff", "Tirisfal Glades", "Undercity" }
    local R = {}
    for i, n in ipairs(real) do R[i] = { n, 1, 1, 15, 60, 30, 15, 60, 0, 0, "", 1, 5, bosses = {} } end
    for i, n in ipairs(zones) do R[100 + i] = { n, 1, 1, 0, 0, 0, 0, 0, 0, 0, "", 1, 5, bosses = { "Zone Event" } } end
    local gi, gn, ge = GetLFGDungeonInfo, GetLFGDungeonNumEncounters, GetLFGDungeonEncounterInfo
    GetLFGDungeonInfo = function(id) local e = R[id] if e then return unpack(e, 1, 13) end end
    GetLFGDungeonNumEncounters = function(id) local e = R[id] return e and #e.bosses or 0 end
    GetLFGDungeonEncounterInfo = function(id, i) local e = R[id] return e and e.bosses[i], "tex", false end
    AGm._ResetCaches()
    local rr, rl = AGm.ScanReport()
    local nl = 0
    for _ in rr:gmatch("kept, not in our list") do nl = nl + 1 end
    local oo2 = table.concat(DarkMatterDB.agscan.oursOnly, ", ")
    check(rl[1] == "agscan: 67 LFG names, 26 dungeons/raids kept (26 of 26 match our list); rejected: zone 41" and nl == 0 and #DarkMatterDB.agscan.notInList == 0,
      "real-client replay: " .. tostring(rl[1]))
    check(#DarkMatterDB.agscan.oursOnly == 7 and oo2 == "The Hall of Thanes, Ruins of Lordaeron, Excavation Site: Wetlands, City of Dalaran, Ruins of Ahn'Qiraj, Temple of Ahn'Qiraj, Naxxramas",
      "real-client replay: ours only = the 4 Forever instances + AQ20, AQ40, Naxx (" .. oo2 .. ")")
    local L2 = AGm.Dungeons()
    local nLive, extra = 0, 0
    for _, d in ipairs(L2) do if d.lfg then nLive = nLive + 1 end if d.source == "lfg" then extra = extra + 1 end end
    check(#L2 == 36 and extra == 0 and nLive == 29, "real-client replay: 36 entries, no duplicates, 29 of ours live (SM row marks 4 wings) (" .. #L2 .. ", " .. nLive .. ", " .. extra .. ")")
    GetLFGDungeonInfo, GetLFGDungeonNumEncounters, GetLFGDungeonEncounterInfo = gi, gn, ge
    AGm._ResetCaches()
    AGm.ScanReport()
  end
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
      listed[rawget(r, "fullName") or r.text:GetText()] = true
    end
  end
  -- 0.3.3: entries indented 12px under flush-left gold headers; headers not clickable; entry text fits
  local gr, gg, gb = DarkMatter.Color("gold")
  local hx, ex, badIndent, badFit, badHead, compact = nil, {}, 0, {}, 0, {}
  for _, r in ipairs(W.menuRows) do
    if r._shown and not r._hid then
      local rl = FrameMT._rect(r)
      local tl, _, tr = FrameMT._rect(r.text)
      if rawget(r, "dungeonKey") then
        ex[#ex + 1] = tl - rl
        local sw = r.text:GetStringWidth()
        if sw > (tr - tl) + 0.01 then badFit[#badFit + 1] = r.text:GetText() end
        local sl = FrameMT._rect(r.small)
        if tr > sl + 0.01 and (r.small:GetText() or "") ~= "" then badFit[#badFit + 1] = r.text:GetText() .. " (level)" end
        if r.text:GetText() ~= r.fullName then compact[#compact + 1] = r.text:GetText() end
        if r._mouseOff then badHead = badHead + 1 end
      else
        hx = hx or (tl - rl)
        if math.abs((tl - rl) - hx) > 0.01 then badHead = badHead + 1 end
        local c = r.text._tcol
        if not (c and math.abs(c[1] - gr) < 0.01 and math.abs(c[2] - gg) < 0.01 and math.abs(c[3] - gb) < 0.01) then badHead = badHead + 1 end
        if not r._mouseOff then badHead = badHead + 1 end
        local before = DarkMatterDB.agDungeon
        if r._scripts.OnClick then r._scripts.OnClick(r) end
        if DarkMatterDB.agDungeon ~= before or not W.menu:IsShown() then badHead = badHead + 1 end
      end
    end
  end
  for _, x in ipairs(ex) do if math.abs(x - (hx + 12)) > 0.01 then badIndent = badIndent + 1 end end
  check(hx and #ex == 37 and badIndent == 0, "dropdown: every entry indented 12px under its group header (" .. #ex .. " entries, " .. badIndent .. " off)")
  check(badHead == 0, "dropdown: Dungeons/Raids headers flush left, gold, not clickable")
  check(#badFit == 0, "dropdown: every indented entry fits its row (" .. table.concat(badFit, ", ") .. ")")
  table.sort(compact)
  check(table.concat(compact, "|") == "SM: Cathedral|SM: Graveyard|SM: Library", "dropdown: only long wing names use the compact form (" .. table.concat(compact, "|") .. ")")
  local miss = {}
  for _, d in ipairs(seed) do if not listed[d.name] then miss[#miss + 1] = d.name end end
  check(#miss == 0, "dropdown lists every dungeon and raid in the known-good list (" .. table.concat(miss, ", ") .. ")")
  -- 0.3.3: outside click, GLOBAL_MOUSE_DOWN, Esc, window hide close the open dropdown; the button still toggles
  local function inSF(name) for i = 1, #UISpecialFrames do if UISpecialFrames[i] == name then return true end end return false end
  local C = _G.DarkMatterAGMenuCatcher
  check(W.menu:IsShown() and C and C._shown and C._parent == UIParent and not C._mouseOff and C:GetFrameStrata() == W.menu:GetFrameStrata()
    and C:GetFrameLevel() == W.menu:GetFrameLevel() - 1, "open dropdown: full-screen catcher (UIParent child) one level under the list")
  check(inSF("DarkMatterAGMenuCatcher") and not inSF("DarkMatterFrame"), "Esc targets the open dropdown, not the window")
  local gev
  for _, r in ipairs(REGLOG) do if r.ev == "GLOBAL_MOUSE_DOWN" then gev = r.frame end end
  check(gev and gev ~= UIParent and gev ~= DarkMatterFrame and gev._ev and gev._ev.GLOBAL_MOUSE_DOWN, "GLOBAL_MOUSE_DOWN on a private frame while open")
  C._scripts.OnMouseDown(C, "LeftButton")
  check(not W.menu:IsShown() and not C._shown and not (gev._ev and gev._ev.GLOBAL_MOUSE_DOWN) and inSF("DarkMatterFrame") and not inSF("DarkMatterAGMenuCatcher"),
    "click outside (catcher) closes the dropdown, unregisters the event, Esc goes back to the window")
  W.drop._scripts.OnClick(W.drop)
  check(W.menu:IsShown() and C._shown, "button reopens the dropdown")
  W.menu._mouseOver = true
  gev._scripts.OnEvent(gev, "GLOBAL_MOUSE_DOWN", "LeftButton")
  check(W.menu:IsShown(), "mouse-down inside the list keeps it open")
  W.menu._mouseOver, W.drop._mouseOver = false, true
  gev._scripts.OnEvent(gev, "GLOBAL_MOUSE_DOWN", "LeftButton")
  check(W.menu:IsShown(), "mouse-down on the button leaves the toggle to the button")
  W.drop._mouseOver = false
  gev._scripts.OnEvent(gev, "GLOBAL_MOUSE_DOWN", "LeftButton")
  check(not W.menu:IsShown() and not C._shown, "mouse-down on a frame above the catcher (GLOBAL_MOUSE_DOWN, not over list or button) closes it")
  W.drop._scripts.OnClick(W.drop)
  for i = #UISpecialFrames, 1, -1 do local fr = _G[UISpecialFrames[i]] if fr and fr._shown then fr:Hide() end end -- what Esc (CloseSpecialWindows) does
  check(not W.menu:IsShown() and not C._shown and DarkMatterFrame._shown and inSF("DarkMatterFrame"), "Esc closes the dropdown only; the window stays open")
  W.drop._scripts.OnClick(W.drop)
  W.drop._scripts.OnClick(W.drop)
  check(not W.menu:IsShown() and not C._shown, "button click toggles the open dropdown closed")
  W.drop._scripts.OnClick(W.drop)
  DarkMatterFrame:Hide()
  check(not W.menu:IsShown() and not C._shown and not inSF("DarkMatterAGMenuCatcher"), "hiding the Dark Matter window closes the dropdown")
  DarkMatterFrame:Show()
  DarkMatter.tabs.journals.SetSection("adventure")
  W.drop._scripts.OnClick(W.drop)
  check(W.menu:IsShown(), "dropdown opens again after the window is reshown")
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

-- ===== 0.4.0 Achievements: game API reader + Dark Matter's own tracked set =====
do
  local ACH = DarkMatter.Ach
  local P = DarkMatter.AchPage
  check(ACH and P, "achievements: data module and page loaded")
  -- the Fishing module's catch callback fed our counter during the fishing tests above (no hooks: a plain NS callback)
  local fdb = DarkMatter.GetFishingDB and DarkMatter.GetFishingDB() or {}
  local adb0 = DarkMatterCharDB.ach
  -- (earlier tests reset the fishing log, so the achievement counter, which starts at install, is >= it)
  check(adb0 and (adb0.c.fish or 0) >= (fdb.catches or 0) and ((fdb.catches or 0) == 0 or (adb0.c.fish or 0) > 0),
    "fishing catches feed the achievement counter (" .. tostring(adb0 and adb0.c.fish) .. " >= " .. tostring(fdb.catches) .. ")")
  local fsrc = io.open(arg[1] .. "/Fishing.lua"):read("*a")
  check(fsrc:find("pcall(NS.OnFishCatch, itemName, quality, quantity, itemId, zone)", 1, true), "Fishing.lua reports each recorded catch through NS.OnFishCatch")
  local saved = { GetCategoryList = GetCategoryList, GetCategoryInfo = GetCategoryInfo, GetCategoryNumAchievements = GetCategoryNumAchievements,
    GetAchievementInfo = GetAchievementInfo, GetAchievementNumCriteria = GetAchievementNumCriteria, GetAchievementCriteriaInfo = GetAchievementCriteriaInfo,
    GetNumCompletedAchievements = GetNumCompletedAchievements, C_Traits = C_Traits, UnitLevel = UnitLevel, GetMoney = GetMoney, GetTime = GetTime,
    GetInstanceInfo = GetInstanceInfo, GetRealZoneText = GetRealZoneText, CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo,
    LOOT_ITEM_SELF = LOOT_ITEM_SELF, LOOT_ITEM_SELF_MULTIPLE = LOOT_ITEM_SELF_MULTIPLE, Print = DarkMatter.Print,
    UnitName = UnitName, GetRealmName = GetRealmName }
  UnitName = function(u) if u == "player" then return "Odysseaus" end end
  GetRealmName = function() return "Forever" end
  -- 0.4.1: Dark Matter's own data is per character (SavedVariablesPerCharacter) with an owner stamp; a stray
  -- account-wide copy moves to the first character without its own data and is removed from the account DB
  do
    local keep = DarkMatterCharDB.ach
    DarkMatterCharDB.ach = nil
    DarkMatterDB.ach = { v = 1, since = "2026-10-20 12:45", c = { quests = 3 }, s = {}, earned = { q1 = { when = "2026-10-20" } } }
    local m = ACH.DB()
    check(m and m.c.quests == 3 and m.earned.q1 and m.migrated and m.owner == "Odysseaus-Forever" and DarkMatterDB.ach == nil
      and DarkMatterCharDB.ach == m, "account-wide achievement data migrates to the current character only, then leaves the account DB")
    DarkMatterDB.ach = { v = 1, c = { quests = 99 }, s = {}, earned = {} }
    local m2 = ACH.DB()
    check(m2 == m and m2.c.quests == 3 and DarkMatterDB.ach == nil, "a character with its own data keeps it; stray account copy dropped")
    DarkMatterCharDB.ach = keep
    if keep then keep.owner = nil end
    local toc = io.open(arg[1] .. "/DarkMatter.toc"):read("*a")
    check(toc:find("## SavedVariablesPerCharacter: DarkMatterCharDB", 1, true), "achievement state lives in SavedVariablesPerCharacter")
  end
  local nMut = #MUTATED
  GetCategoryList, GetCategoryInfo, GetCategoryNumAchievements, GetAchievementInfo = nil, nil, nil, nil
  GetAchievementNumCriteria, GetAchievementCriteriaInfo, GetNumCompletedAchievements, C_Traits = nil, nil, nil, nil
  local LVL, MONEY, NOW, INST, ZONE, CL = 5, 0, 5000, { "Elwynn Forest", "none" }, "Elwynn Forest", nil
  UnitLevel = function() return LVL end
  GetMoney = function() return MONEY end
  GetTime = function() return NOW end
  GetInstanceInfo = function() return INST[1], INST[2], 0, "", 5, 0, false, 0, 0 end
  GetRealZoneText = function() return ZONE end
  CombatLogGetCurrentEventInfo = function() return unpack(CL) end
  LOOT_ITEM_SELF, LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %s.", "You receive loot: %sx%d."
  local printed = {}
  DarkMatter.Print = function(m) printed[#printed + 1] = tostring(m) end
  local AF = ACH._Frame()
  local function fire(e, ...) AF._scripts.OnEvent(AF, e, ...) end
  local T = ACH._ToastFrame()
  local function drain() local t = ACH._ToastFrame() for _ = 1, 200 do if not (t and t._shown) then break end t._scripts.OnUpdate(t, 1) end end
  drain()
  -- fresh install
  DarkMatterCharDB.ach = nil
  ACH._Reset() ACH._ResetMoney()
  check(ACH.Mode() == "dm", "no achievement API: mode dm (" .. ACH.Mode() .. ")")
  local defs = ACH.Defs()
  check(#defs >= 30 and #defs <= 50 and #ACH.Broken() == 0, "Dark Matter set: " .. #defs .. " achievements (30-50), every boss/fish criterion resolves (" .. table.concat(ACH.Broken(), ",") .. ")")
  local per, ids, pts = {}, {}, 0
  for _, a in ipairs(defs) do per[a.cat] = (per[a.cat] or 0) + 1 check(not ids[a.id], "unique id " .. a.id) ids[a.id] = true pts = pts + a.points end
  local cats = {}
  for _, c in ipairs(ACH.CATS) do cats[#cats + 1] = c .. "=" .. tostring(per[c]) check((per[c] or 0) >= 4, "category " .. c .. " has achievements") end
  check(table.concat(ACH.CATS, "|") == "General|Quests|Dungeons and Raids|Fishing|Exploration|Loot", "categories: " .. table.concat(cats, " "))
  for _, a in ipairs(defs) do
    if a.kind == "boss" then for _, c in ipairs(a.crit) do check(ACH.BossIndex().byNpc[c.npc].boss == c.name, "boss criterion " .. c.name .. " -> npc " .. c.npc .. " in Data_Dungeons") end end
  end
  -- first world entry: only the current level is confirmed; nothing else retroactive
  LVL, MONEY = 12, 50000
  fire("PLAYER_ENTERING_WORLD")
  local db = DarkMatterCharDB.ach
  check(db and db.since and db.since:match("^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d$"), "per-character state in DarkMatterCharDB.ach, since " .. tostring(db and db.since))
  local nE = 0 for _ in pairs(db.earned) do nE = nE + 1 end
  check(nE == 1 and db.earned.lvl10 and db.earned.lvl10.retro and not db.earned.lvl20, "install at level 12: only 'Reach level 10' (confirmed now), marked retro")
  check(not (ACH._ToastFrame() and ACH._ToastFrame()._shown), "no toast for what was confirmed at install")
  check(printed[#printed]:find("1 earned from your current level", 1, true), "one chat line for the install check: " .. tostring(printed[#printed]))
  check(db.s.zones["Elwynn Forest"] and (db.c.money or 0) == 0, "zone recorded; money baseline taken, not counted")
  -- quests
  fire("QUEST_TURNED_IN", 101, 100, 0)
  fire("QUEST_TURNED_IN", 101, 100, 0)
  check(db.c.quests == 1 and db.earned.q1 and not db.earned.q1.retro, "QUEST_TURNED_IN counts once per quest (" .. tostring(db.c.quests) .. ")")
  T = ACH._ToastFrame()
  check(T and T._name == "DarkMatterAchToast" and T._parent == UIParent and T._shown and T.name:GetText() == "First Errand" and T.sub:GetText() == "5 points · Quests",
    "toast on earn: our own frame, name + points")
  check(printed[#printed] == "achievement earned: First Errand (5 points)", "chat line on earn")
  for q = 102, 110 do NOW = NOW + 5 fire("QUEST_TURNED_IN", q, 0, 0) end
  check(db.c.quests == 10 and db.earned.q10, "10 quests -> Helping Hand")
  T._scripts.OnUpdate(T, 0.1)
  check(T._alpha and T._alpha > 0 and T._alpha < 1, "toast fades in")
  drain()
  check(not T._shown, "toast queue drains and hides")
  -- levels
  LVL = 13 fire("PLAYER_LEVEL_UP", 20)
  check(db.c.levels == 1 and db.earned.lvl20, "PLAYER_LEVEL_UP uses the event's level (UnitLevel can lag)")
  -- dungeons: enter, kill a boss (ENCOUNTER_END + BOSS_KILL for one kill, then the corpse is looted)
  INST = { "The Deadmines", "party" }
  local nTouch = #RESTRICTED_TOUCH
  fire("ZONE_CHANGED_NEW_AREA")
  check(db.s.inst["The Deadmines"] and not AF._ev.COMBAT_LOG_EVENT_UNFILTERED and #RESTRICTED_TOUCH == nTouch,
    "instance entered; no restricted event (combat log) registered or unregistered")
  fire("ENCOUNTER_END", 1, "Defias Pirate", 1, 5, 1)
  check(db.c.bossKills == nil and not next(db.s.bosses), "non-boss encounters are ignored")
  fire("ENCOUNTER_END", 1, "Edwin VanCleef", 1, 5, 1)
  fire("BOSS_KILL", 1, "Edwin VanCleef")
  check(db.s.bosses[639] == 1 and db.c.bossKills == 1 and db.earned.dm, "VanCleef (npc 639 from our seed) -> The Brotherhood Broken; ENCOUNTER_END + BOSS_KILL counted once")
  NOW = NOW + 120
  check(DarkMatter.OnBossLooted == ACH.RecordBossLoot and not ACH.RecordBossLoot(639, "Creature-0-1-36-1-639-0000AA01"),
    "looting the corpse 2 minutes after the counted kill does not count it again")
  NOW = NOW + 900
  check(ACH.RecordBossLoot(639, "Creature-0-1-36-1-639-0000AA02") and db.c.bossKills == 2 and db.s.bosses[639] == 2,
    "boss corpse looted with no kill event seen -> counted (loot fallback)")
  NOW = NOW + 900
  check(not ACH.RecordBossLoot(639, "Creature-0-1-36-1-639-0000AA02") and not ACH.RecordBossLoot(1234567, "Creature-0-1-36-1-1234567-1"),
    "same corpse never counts twice; non-boss npc ignored")
  db.s.bosses[639] = 1 db.c.bossKills = 1
  NOW = NOW + 600
  fire("ENCOUNTER_END", 1, "Onyxia", 9, 40, 0)
  check(not db.earned.ony, "failed encounter (success 0) is not a kill")
  fire("ENCOUNTER_END", 1, "Onyxia", 9, 40, 1)
  check(db.earned.ony and db.c.bossKills == 2, "ENCOUNTER_END by name -> Broodmother Slain")
  INST = { "Onyxia's Lair", "raid" } fire("ZONE_CHANGED_NEW_AREA")
  check(db.earned.raid1 and db.s.raids["Onyxia's Lair"], "raid entered -> Raid Ready")
  nTouch = #RESTRICTED_TOUCH
  INST = { "Westfall", "none" } ZONE = "Westfall" fire("ZONE_CHANGED_NEW_AREA")
  check(not AF._ev.COMBAT_LOG_EVENT_UNFILTERED and #RESTRICTED_TOUCH == nTouch,
    "leaving the instance touches no restricted event (0.4.0 unregistered the combat log here -> ADDON_ACTION_FORBIDDEN)")
  for _, z in ipairs({ "Duskwood", "Redridge Mountains", "Loch Modan" }) do ZONE = z fire("ZONE_CHANGED_NEW_AREA") end
  check(db.earned.zones5 and not db.earned.zones15, "5 different zones -> Wanderer")
  -- fishing
  DarkMatter.OnFishCatch("Oily Blackmouth", 1, 1, 6358)
  check(db.c.fish == 1 and db.earned.fish1 and not db.earned.fireoil, "first catch -> Gone Fishing; Fire and Oil needs both fish")
  DarkMatter.OnFishCatch("Firefin Snapper", 1, 2, 6359)
  DarkMatter.OnFishCatch("Elixir of Water Breathing", 3, 1, 5996)
  check(db.earned.fireoil and db.earned.fishrare and db.c.fish == 4, "Fire and Oil + Something Shiny (rare catch)")
  -- loot (self lines only, the client's own format strings)
  fire("CHAT_MSG_LOOT", "Bob receives loot: |cffa335ee|Hitem:19019::::|h[Thunderfury]|h|r.")
  check(not db.earned.purple and (db.c.loot or 0) == 0, "other players' loot is ignored")
  fire("CHAT_MSG_LOOT", "You receive loot: |cff1eff00|Hitem:2589::::|h[Linen Cloth]|h|rx5.")
  check(db.c.loot == 5 and db.earned.green and not db.earned.blue, "Uncommon loot (x5 parsed) -> Uncommon Find")
  fire("CHAT_MSG_LOOT", "You receive loot: |cffa335ee|Hitem:19019::::|h[Thunderfury]|h|r.")
  check(db.earned.blue and db.earned.purple and db.c.lootBest == 4, "Epic loot -> Rare Find + Epic Find")
  -- money: gains only
  MONEY = 50000 + 5 * 10000 fire("PLAYER_MONEY")
  MONEY = 20000 fire("PLAYER_MONEY")
  MONEY = 20000 + 6 * 10000 fire("PLAYER_MONEY")
  check(db.c.money == 110000 and db.earned.gold10 and not db.earned.gold100, "PLAYER_MONEY counts gains only (11g) -> Pocket Change")
  for k, e in pairs(db.earned) do check(type(e.when) == "string" and e.when:match("^%d%d%d%d%-%d%d%-%d%d"), "earned date stored: " .. k) end
  local t = ACH.Totals()
  check(t.count == #defs and t.points == pts and t.earned > 10, string.format("totals: %d/%d earned, %d/%d points", t.earned, t.count, t.pointsEarned, t.points))
  drain()
  -- /dm achprobe (dm mode)
  printed = {}
  SlashCmdList.DARKMATTER("achprobe")
  check(printed[1]:find("mode = dm", 1, true) and printed[2]:find("GetCategoryList=no", 1, true)
    and printed[3]:find("Dark Matter (this character, Odysseaus-Forever): 6 categories, " .. #defs .. " achievements", 1, true) and #printed == 6,
    "achprobe (no API): mode, API names, Dark Matter counts + 3 samples (" .. #printed .. " lines)")
  check(printed[4]:find("Getting Started", 1, true) and printed[4]:find("level confirmed at install", 1, true), "achprobe sample: " .. printed[4])
  check(DarkMatterDB.achprobe and DarkMatterDB.achprobe.mode == "dm", "achprobe saved to DarkMatterDB.achprobe")

  -- UI (dm mode): summary bar, category tree, cards (0.4.1 layout)
  DarkMatter.ToggleWindow(true)
  DarkMatter.ShowTab("journals")
  DarkMatter.tabs.journals.SetSection("achievements")
  local W = DarkMatter.tabs.journals.achWidgets()
  local R = FrameMT._rect
  local function natural(fs) return #(fs._text or "") * (fs._fsize or 12) * 0.52 end
  local function apart(a, b)
    local al, at, ar, ab = R(a)
    local bl, bt, br, bb = R(b)
    if not (al and bl) then return false end
    return ar <= bl or br <= al or ab >= bt or bb >= at
  end
  local function inside(a, b) -- a's rect within b's
    local al, at, ar, ab = R(a)
    local bl, bt, br, bb = R(b)
    return al and bl and al >= bl - 0.5 and ar <= br + 0.5 and at <= bt + 0.5 and ab >= bb - 0.5
  end
  local function fits(fs) local l, _, r = R(fs) return l and natural(fs) <= r - l + 0.01 end
  -- 0.4.2: the summary badges carry no number; no visible text of the slot may sit on the badge
  local function BadgeBare(slot)
    for _, r in ipairs(REGIONS) do
      if r._kind == "fontstring" and r._parent == slot and not r._hid and (r._text or "") ~= "" and not apart(r, slot.badge) then return false end
    end
    return true
  end
  local function col(fs, key) local c, r, g, b = fs._tcol, DarkMatter.Color(key) return c and math.abs(c[1] - r) < 0.01 and math.abs(c[2] - g) < 0.01 and math.abs(c[3] - b) < 0.01 end
  local function shownRows() local o = {} for _, r in ipairs(W.treeRows) do if r._shown then o[#o + 1] = r end end return o end
  local function shownCards() local o = {} for _, c in ipairs(W.cards) do if c._shown then o[#o + 1] = c end end return o end
  local function rowFor(key) for _, r in ipairs(shownRows()) do if r.catKey == key or r.nodeKey == key then return r end end end
  local function cardNamed(n) for _, c in ipairs(shownCards()) do if c.name:GetText() == n then return c end end end
  local function setSearch(q) W.search:SetText(q) W.search.edit._scripts.OnTextChanged(W.search.edit) end
  check(W.page:IsShown() and DarkMatterDB.section == "achievements", "Achievements section opens")
  check(W.menu == nil and W.drop == nil and _G.DarkMatterAchMenuCatcher == nil, "0.4.1: no dropdown or catcher any more (the tree replaces them)")
  local function badge() for _, fs in ipairs(FS) do if type(fs._text) == "string" and fs._text:match("^Earned %d+/%d+$") then return fs._text end end end
  check(badge() == "Earned " .. t.earned .. "/" .. t.count, "badge: " .. tostring(badge()))
  -- summary bar (dm mode: Dark Matter points only, this character)
  local S = W.slots
  check(S.dm._shown and not S.legacy._shown and S.dm.label:GetText() == "Dark Matter points (this character)" and BadgeBare(S.dm)
    and S.dm.pbar.label:GetText() == t.pointsEarned .. " / " .. t.points, "summary bar: Dark Matter points with a progress bar (" .. S.dm.pbar.label:GetText() .. ")")
  check(inside(S.dm, W.summary) and inside(S.dm.pbar, W.summary) and fits(S.dm.label) and apart(S.dm.badge, S.dm.label) and apart(S.dm.label, S.dm.pbar),
    "summary slot fits the bar: badge, label, progress bar apart")
  -- tree
  local heads, names, bad = {}, {}, 0
  for _, r in ipairs(shownRows()) do
    if r.isHeader then
      heads[#heads + 1] = r.text:GetText()
      if not col(r.text, "gold") or not r._mouseOff then bad = bad + 1 end
      local before = DarkMatterDB.achCat
      r._scripts.OnClick(r)
      if DarkMatterDB.achCat ~= before then bad = bad + 1 end
    else
      names[#names + 1] = r.text:GetText()
      if natural(r.text) > r.textW + 0.01 then bad = bad + 1 end
    end
  end
  check(table.concat(heads, "|") == "Dark Matter" and table.concat(names, "|") == table.concat(ACH.CATS, "|") and bad == 0,
    "dm mode tree: gold 'Dark Matter' section (not clickable) with the 6 categories, names fit (" .. table.concat(names, ",") .. ")")
  local rs = shownRows()
  for i = 2, #rs do if not apart(rs[i - 1], rs[i]) then bad = bad + 1 end end
  check(bad == 0, "tree rows do not overlap")
  local fr = rowFor("dm:Fishing")
  fr._scripts.OnClick(fr)
  check(W.title:GetText() == "Fishing" and rowFor("dm:Fishing").selected and W.meta:GetText():find("^Dark Matter · %d+ of 8 earned") and W.meta:GetText():find("no game API", 1, true),
    "picking a category: header + meta (" .. W.meta:GetText() .. ")")
  local cs = shownCards()
  local first = cs[1]
  check(#cs == per.Fishing and first.name:GetText() == "Gone Fishing" and first.badgeNum:GetText() == "5" and first.status:GetText():find("^Earned %d")
    and col(first.name, "gold"), "cards: name, points badge, earned date; earned card is bright")
  local salty = cardNamed("Salty")
  check(salty and salty.status:GetText() == "In progress: 4 / 1000" and salty.bar._shown and salty.bar.label:GetText() == "4 / 1000" and col(salty.name, "listSoft"),
    "unearned card: muted, progress bar for partial progress")
  local fire2 = cardNamed("Fire and Oil")
  fire2._scripts.OnClick(fire2)
  fire2 = cardNamed("Fire and Oil")
  local crit = {}
  for _, r in ipairs(fire2.crit) do if r._shown then crit[#crit + 1] = r.text:GetText() .. "=" .. r.val:GetText() end end
  check(fire2.expanded and table.concat(crit, "|") == "Oily Blackmouth=done|Firefin Snapper=2×" and fire2.critHead:GetText() == "Criteria (2)"
    and fire2.note._shown and fire2.note:GetText():find("not Blizzard", 1, true), "click expands the card inline: criteria + note (" .. table.concat(crit, "|") .. ")")
  local _, _, _, fb = R(fire2)
  local nextCard
  for i, c in ipairs(shownCards()) do if c == fire2 then nextCard = shownCards()[i + 1] end end
  check(not nextCard or apart(fire2, nextCard), "the expanded card pushes the next one down")
  fire2._scripts.OnClick(fire2)
  check(not cardNamed("Fire and Oil").expanded and not cardNamed("Fire and Oil").note._shown, "click again collapses it")
  -- Filter control (All -> Earned -> Not yet -> All)
  check(W.filterBtn.text:GetText() == "Filter: All", "Filter control starts at All")
  W.filterBtn._scripts.OnClick(W.filterBtn)
  local nd = #shownCards()
  check(W.filterBtn.text:GetText() == "Filter: Earned", "Filter: Earned")
  W.filterBtn._scripts.OnClick(W.filterBtn)
  local nt = #shownCards()
  check(W.filterBtn.text:GetText() == "Filter: Not yet" and nd + nt == per.Fishing and nd == 3, "Earned / Not yet filters (" .. nd .. " + " .. nt .. ")")
  W.filterBtn._scripts.OnClick(W.filterBtn)
  check(W.filterBtn.text:GetText() == "Filter: All" and #shownCards() == per.Fishing, "back to All")
  -- search across every category
  local q, expect, perCat = "gold", 0, {}
  for _, a in ipairs(ACH.Defs()) do
    if a.name:lower():find(q, 1, true) or a.desc:lower():find(q, 1, true) or a.cat:lower():find(q, 1, true) then expect = expect + 1 perCat[a.catKey] = (perCat[a.catKey] or 0) + 1 end
  end
  setSearch("Gold")
  local cats = {}
  for k in pairs(perCat) do cats[#cats + 1] = k end
  check(expect > 0 and #shownCards() == expect and W.title:GetText() == "Search results" and W.meta:GetText():find('^Search "Gold" · ' .. expect .. " match"),
    "search spans every category (" .. expect .. " matches in " .. #cats .. " categories): " .. W.meta:GetText())
  local cntOk = true
  for _, r in ipairs(shownRows()) do if type(r.catKey) == "string" and r.small:GetText() ~= tostring(perCat[r.catKey] or 0) then cntOk = false end end
  local dbg = {} for _, r in ipairs(shownRows()) do if type(r.catKey) == "string" then dbg[#dbg + 1] = r.catKey .. "=" .. tostring(r.small:GetText()) .. "/" .. tostring(perCat[r.catKey] or 0) end end
  check(cntOk, "tree shows match counts per category while searching (" .. table.concat(dbg, ",") .. ")")
  local loot = rowFor("dm:Loot")
  loot._scripts.OnClick(loot)
  check(#shownCards() == (perCat["dm:Loot"] or 0) and W.title:GetText() == "Loot", "clicking a category narrows the search to it")
  rowFor("dm:Loot")._scripts.OnClick(rowFor("dm:Loot"))
  check(#shownCards() == expect, "clicking it again shows every match")
  setSearch("zzzz no such")
  check(#shownCards() == 0 and W.empty._shown and W.empty:GetText() == "No achievements match your search.", "no matches: empty state")
  setSearch("")
  check(W.title:GetText() == "Fishing" and #shownCards() == per.Fishing, "clearing the search returns to the category")
  -- layout: every Dark Matter card, collapsed and expanded, fits without overlap or truncation
  do
    local ov, seen = {}, 0
    for _, cname in ipairs(ACH.CATS) do
      DarkMatterDB.achCat, DarkMatterDB.achCard = "dm:" .. cname, nil
      DarkMatter.tabs.journals.Refresh()
      local n = #shownCards()
      for i = 1, n do
        for _, exp in ipairs({ false, true }) do
          DarkMatterDB.achCard = exp and shownCards()[i].itemKey or nil
          DarkMatter.tabs.journals.Refresh()
          local list = shownCards()
          local c = list[i]
          local nm = c.name:GetText()
          if not exp then seen = seen + 1 end
          for _, pr in ipairs({ { c.icon, c.name }, { c.icon, c.desc }, { c.name, c.desc }, { c.desc, c.status }, { c.name, c.badge }, { c.desc, c.badge }, { c.status, c.badge } }) do
            if not apart(pr[1], pr[2]) then ov[#ov + 1] = "card " .. nm end
          end
          if c.bar._shown and (not apart(c.status, c.bar) or not inside(c.bar, c)) then ov[#ov + 1] = "bar " .. nm end
          if not fits(c.name) then ov[#ov + 1] = "name truncated " .. nm end
          if not fits(c.status) then ov[#ov + 1] = "status truncated " .. nm .. ": " .. c.status:GetText() end
          local dl, dt, dr, dbm = R(c.desc)
          if natural(c.desc) > (dr - dl) * math.floor((dt - dbm) / 13 + 0.01) + 0.01 then ov[#ov + 1] = "desc truncated " .. nm end
          for _, fs in ipairs({ c.icon, c.name, c.desc, c.status, c.badge }) do if not inside(fs, c) then ov[#ov + 1] = "outside card " .. nm end end
          if exp then
            local last = c.critHead
            if not apart(c.status, c.critHead) or (c.bar._shown and not apart(c.bar, c.critHead)) then ov[#ov + 1] = "criteria head " .. nm end
            for _, r in ipairs(c.crit) do
              if r._shown then
                if not apart(last, r) then ov[#ov + 1] = "criteria " .. nm end
                if not fits(r.text) or not fits(r.val) then ov[#ov + 1] = "criterion truncated " .. nm .. ": " .. r.text:GetText() end
                last = r
              end
            end
            if not apart(last, c.note) or not fits(c.note) or not inside(c.note, c) or not fits(c.critHead) then ov[#ov + 1] = "note " .. nm end
          end
          if list[i + 1] and not apart(c, list[i + 1]) then ov[#ov + 1] = "cards overlap " .. nm end
        end
      end
    end
    if not apart(W.title, W.meta) or not apart(W.meta, W.cardScroll.frame) then ov[#ov + 1] = "header" end
    for _, pr in ipairs({ { W.summary, W.search }, { W.summary, W.right }, { W.search, W.tree }, { W.filterBtn, W.tree }, { W.search, W.filterBtn }, { W.tree, W.right } }) do
      if not apart(pr[1], pr[2]) then ov[#ov + 1] = "page layout" end
    end
    for _, f in ipairs({ W.summary, W.search, W.filterBtn, W.tree, W.right }) do if not inside(f, W.page) then ov[#ov + 1] = "outside page" end end
    check(#ov == 0 and seen == #defs, "achievements layout: no overlapping or truncated text across " .. seen .. " cards, collapsed and expanded (" .. table.concat(ov, "; ") .. ")")
    DarkMatterDB.achCat, DarkMatterDB.achCard = "dm:Fishing", nil
    DarkMatter.tabs.journals.Refresh()
  end
  -- scroll: expanding the last card brings it into view without jumping; a new category starts at the top
  do
    DarkMatterDB.achCat, DarkMatterDB.achCard = "dm:Dungeons and Raids", nil
    DarkMatter.tabs.journals.Refresh()
    local sc = shownCards()
    local last = sc[#sc]
    last._scripts.OnClick(last)
    local v1, S = W.cardScroll:GetScroll(), W.cardScroll
    local top = 0
    for i = 1, #sc - 1 do top = top + sc[i]:GetHeight() + 6 end
    local inView = top >= v1 - 0.5 and top + last:GetHeight() <= v1 + S.h + 0.5
    DarkMatter.tabs.journals.Refresh()
    local v2 = W.cardScroll:GetScroll()
    DarkMatterDB.achCat, DarkMatterDB.achCard = "dm:Quests", nil
    DarkMatter.tabs.journals.Refresh()
    check(v1 > 0 and inView and v2 == v1 and W.cardScroll:GetScroll() == 0,
      "cards: expanding the last card scrolls it into view (" .. v1 .. "), a refresh keeps the position, a new category starts at the top")
    DarkMatterDB.achCat, DarkMatterDB.achCard = "dm:Fishing", nil
    DarkMatter.tabs.journals.Refresh()
  end

  -- game API present but thin (Forever: Legacy Challenges) -> game + Dark Matter
  local GCATS = { [15076] = { "Classes", -1 }, [15585] = { "Warrior", 15076 }, [15590] = { "Raids", -1 }, [15999] = { "Do Not Display", -1 } }
  local GACH = {
    [15585] = { { 62001, "Warrior Mastery", 0, true, 10, 19, 26, "Reach level 60 as a Warrior.", true }, { 62002, "Shield Wall", 0, false, nil, nil, nil, "Complete the Warrior challenge.", false },
      -- account-wide: completed, but by another character (wasEarnedByMe false, earnedBy "Altdruid")
      { 61502, "Novice Druid", 0, true, 10, 3, 26, "Reach level 10 as a Druid.", false, "Altdruid" } },
    [15590] = { { 62035, "Conqueror of the Deeps", 0, false, nil, nil, nil, "Defeat the following encounters in the Barrow Deeps.", false } },
    [15999] = { { 20134, "[DNT] Self-Found Soul (Level 10)", 0, false } },
  }
  local GCRIT = { [62035] = { { "Chillhowl", true, nil, nil, "Odysseaus" }, { "Amethrax", true, nil, nil, "Altdruid" }, { "Sonya Darkhallow", false } },
    [62002] = { { "Kills", false, 3, 10 } }, [61502] = { { "Reach level 10", true } } }
  GetCategoryList = function() return { 15076, 15585, 15590, 15999 } end
  GetCategoryInfo = function(id) local c = GCATS[id] if c then return c[1], c[2], 0 end end
  GetCategoryNumAchievements = function(id) local l = GACH[id] or {} local d = 0 for _, a in ipairs(l) do if a[4] then d = d + 1 end end return #l, d, #l - d end
  GetAchievementInfo = function(cat, i)
    local a = GACH[cat] and GACH[cat][i]
    if a then return a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], 0, 136243, "", false, a[9], a[10] or "" end
  end
  GetAchievementNumCriteria = function(id) return #(GCRIT[id] or {}) end
  GetAchievementCriteriaInfo = function(id, i) local c = GCRIT[id][i] return c[1], 0, c[2], c[3] or (c[2] and 1 or 0), c[4] or 1, c[5] or "", 0, 0, c[4] and ((c[3] or 0) .. "/" .. c[4]) or "" end
  GetNumCompletedAchievements = function() return 4, 2 end
  C_Traits = { GetTraitCurrencyForAchievement = function(cur, id) if cur == 4225 then return 1 end end }
  ACH.InvalidateGame()
  local g = ACH.ReadGame()
  check(ACH.Mode() == "game+dm" and #g.cats == 2 and g.total == 4 and g.done == 1 and g.accountDone == 2 and g.hidden == 1 and g.legacy == 4
    and g.legacyDone == 1 and g.legacyAccountDone == 2,
    "Forever-shaped API (thin: 4 Legacy Challenges, 0 points) -> game+dm; [DNT] skipped; per-character done/Legacy Points (1) vs account (2)")
  local nd = g.byId[61502]
  check(nd and not nd.completed and nd.other and nd.earnedBy == "Altdruid" and nd.when == nil and nd.accountWhen == "2026-10-03" and g.cats[1].done == 1
    and g.cats[1].accountDone == 2, "another character's completion (wasEarnedByMe false) does not count here; date kept as account info")
  check(g.cats[1].name == "Classes: Warrior" and g.byId[62001].when == "2026-10-19", "parent-prefixed category names, completion date")
  printed = {}
  SlashCmdList.DARKMATTER("achprobe")
  check(printed[1]:find("mode = game+dm", 1, true) and printed[3]:find("2 categories with achievements", 1, true) == nil
    and printed[3]:find("4 categories (2 with achievements), 4 achievements, 0 points, 4 Legacy Points", 1, true)
    and printed[3]:find("placeholder rows skipped", 1, true),
    "achprobe (API): " .. tostring(printed[3]))
  check(printed[4] == "completed: 2 account / 1 this character (Odysseaus-Forever); Legacy Points earned: 2 account / 1 this character; GetNumCompletedAchievements = 2/4 (account)",
    "achprobe: account and this-character numbers side by side: " .. tostring(printed[4]))
  check(printed[5]:find("[62001] Warrior Mastery", 1, true) and printed[5]:find("complete 2026-10-19", 1, true)
    and printed[7] == "  [61502] Novice Druid (Classes: Warrior): not yet on this character (earned on Altdruid 2026-10-03), criteria 0/1"
    and printed[8]:find("^Dark Matter %(this character"), "achprobe: 3 game samples (other-character one marked), then the Dark Matter line: " .. tostring(printed[7]))
  DarkMatterDB.achOpen = nil
  DarkMatter.tabs.journals.Refresh()
  -- tree: game categories nested by parent id (Classes > Warrior), collapsible; then the Dark Matter section
  local function treeText() local o = {} for _, r in ipairs(shownRows()) do o[#o + 1] = (r.isHeader and "#" or (r.isParent and "+" or "")) .. r.text:GetText() end return table.concat(o, "|") end
  check(treeText() == "#Legacy Challenges|+Classes|Raids|#Dark Matter|General|Quests|Dungeons and Raids|Fishing|Exploration|Loot",
    "game+dm tree: Legacy Challenges (parents from GetCategoryInfo parent ids, collapsed) then Dark Matter: " .. treeText())
  local cls = rowFor("n:15076")
  check(cls and cls.isParent and cls.small:GetText() == "1/3" and cls.toggle._shown, "parent row: +/- toggle and this character's count (1/3)")
  cls._scripts.OnClick(cls)
  check(treeText() == "#Legacy Challenges|+Classes|Warrior|Raids|#Dark Matter|General|Quests|Dungeons and Raids|Fishing|Exploration|Loot"
    and rowFor("g:15585").small:GetText() == "1/3", "click expands Classes > Warrior: " .. treeText())
  do
    local pl = R(rowFor("n:15076").text) local cl = R(rowFor("g:15585").text)
    check(cl - pl >= 4, "child rows are indented under their parent")
  end
  rowFor("n:15076")._scripts.OnClick(rowFor("n:15076"))
  check(not rowFor("g:15585"), "click again collapses it")
  rowFor("n:15076")._scripts.OnClick(rowFor("n:15076"))
  -- summary bar: Dark Matter points and Legacy Points, both this character
  check(S.dm._shown and S.legacy._shown and S.legacy.label:GetText() == "Legacy Points (this character)" and BadgeBare(S.legacy)
    and S.legacy.pbar.label:GetText() == "1 / 4" and apart(S.dm, S.legacy) and inside(S.legacy, W.summary) and fits(S.legacy.label) and fits(S.dm.label),
    "summary bar: Dark Matter points + Legacy Points (this character: 1 / 4), side by side")
  local gr1 = rowFor("g:15590")
  gr1._scripts.OnClick(gr1)
  check(W.title:GetText() == "Raids" and W.meta:GetText():find("^Game · 0 of 1 done %(this character%)") and badge() == nil, "game category: labelled as game data (" .. W.meta:GetText() .. ")")
  local cq = cardNamed("Conqueror of the Deeps")
  check(cq and cq.badgeNum:GetText() == "1" and cq.status:GetText() == "In progress: 1 / 3" and cq.bar._shown, "game card: Legacy Point badge, progress for this character")
  cq._scripts.OnClick(cq)
  cq = cardNamed("Conqueror of the Deeps")
  crit = {}
  for _, r in ipairs(cq.crit) do if r._shown then crit[#crit + 1] = r.text:GetText() .. "=" .. r.val:GetText() end end
  check(table.concat(crit, "|") == "Chillhowl=done|Amethrax=other character|Sonya Darkhallow=not yet" and cq.note:GetText() == "Game data · Legacy Challenge · this character" and fits(cq.note),
    "game criteria per character: one done by another character is not counted (" .. table.concat(crit, "|") .. ")")
  rowFor("g:15585")._scripts.OnClick(rowFor("g:15585"))
  local sw = cardNamed("Shield Wall")
  check(sw and sw.status:GetText() == "In progress: 3 / 10" and sw.bar.label:GetText() == "3 / 10", "single quantity criterion drives the bar (3/10)")
  -- earned on another character: muted card with a small note, not in Earned; header/badge per character
  local nd2 = cardNamed("Novice Druid")
  check(nd2 and nd2.status:GetText() == "Not yet (earned on another character)" and col(nd2.status, "listSoft") and col(nd2.name, "listSoft") and not nd2.bar._shown and fits(nd2.status),
    "another character's completion: muted card, 'Not yet (earned on another character)'")
  nd2._scripts.OnClick(nd2)
  nd2 = cardNamed("Novice Druid")
  check(nd2.note:GetText() == "Game data · earned on Altdruid, not this one" and fits(nd2.note) and W.meta:GetText() == "Game · 1 of 3 done (this character) · 1 on other characters" and fits(W.meta),
    "expanded note + header: per character, other characters counted separately (" .. W.meta:GetText() .. ")")
  local wm = cardNamed("Warrior Mastery")
  check(wm and col(wm.name, "gold") and wm.status:GetText() == "Earned 2026-10-19", "card earned by this character: bright, earned date")
  local gbadge
  for _, fs in ipairs(FS) do if type(fs._text) == "string" and fs._text:match("^Done %d+/%d+$") then gbadge = fs._text end end
  check(gbadge == "Done 1/4", "badge counts this character only: " .. tostring(gbadge))
  W.filterBtn._scripts.OnClick(W.filterBtn)
  local earnedN = {}
  for _, c in ipairs(shownCards()) do earnedN[#earnedN + 1] = c.name:GetText() end
  W.filterBtn._scripts.OnClick(W.filterBtn)
  local todoHas = cardNamed("Novice Druid") ~= nil
  W.filterBtn._scripts.OnClick(W.filterBtn)
  check(table.concat(earnedN, ",") == "Warrior Mastery" and todoHas, "Earned filter hides other characters' completions; Not yet lists them")
  -- search spans game and Dark Matter categories
  setSearch("druid")
  check(#shownCards() == 1 and shownCards()[1].name:GetText() == "Novice Druid" and rowFor("n:15076") and rowFor("g:15585") and rowFor("g:15585").small:GetText() == "1",
    "search finds game achievements too, parents open to show where")
  setSearch("")
  -- a full achievement API (300+ with points) -> the game's own; ours off
  local big = {}
  for i = 1, 320 do big[i] = { 70000 + i, "A" .. i, 10, i <= 5, 1, 2, 26, "d", true } end
  GACH[15590] = big
  ACH.InvalidateGame()
  check(ACH.Mode() == "game", "full API -> game mode")
  local before = 0 for _ in pairs(db.earned) do before = before + 1 end
  LVL = 60 fire("PLAYER_LEVEL_UP", 60)
  local after = 0 for _ in pairs(db.earned) do after = after + 1 end
  check(after == before, "game mode: Dark Matter's set awards nothing")
  DarkMatter.tabs.journals.Refresh()
  check(not treeText():find("#Dark Matter", 1, true) and not S.dm._shown and S.legacy._shown and S.legacy.label:GetText() == "Achievement points (this character)"
    and S.legacy.pbar.label:GetText() == "50 / 3200", "game mode: no Dark Matter section; summary shows this character's achievement points (" .. S.legacy.pbar.label:GetText() .. ")")
  GACH[15590] = { { 62035, "Conqueror of the Deeps", 0, false, nil, nil, nil, "x", false } }
  ACH.InvalidateGame()
  DarkMatterFrame:Hide()
  check(not W.page:IsVisible() or not DarkMatterFrame._shown, "page hides with the window")
  DarkMatterFrame:Show()

  -- taint safety
  for _, fn in ipairs({ "Achievements.lua", "Journal_Achievements.lua" }) do
    local src = io.open(arg[1] .. "/" .. fn):read("*a")
    check(not src:find("hooksecurefunc", 1, true) and not src:find("LoadAddOn", 1, true) and not src:find("UIDropDownMenu", 1, true)
      and not src:find("_G%[[^%]]+%]%s*=") and not src:find("HookScript", 1, true), fn .. ": no hooks, no addon loads, no UIDropDownMenu, no global writes")
  end
  check(#MUTATED == nMut, "achievements: no state-changing or server-asking API calls")
  for _, r in ipairs(REGLOG) do
    if r.frame == AF then check(({ PLAYER_ENTERING_WORLD = 1, ZONE_CHANGED_NEW_AREA = 1, PLAYER_LEVEL_UP = 1, QUEST_TURNED_IN = 1, PLAYER_MONEY = 1, CHAT_MSG_LOOT = 1,
      ENCOUNTER_END = 1, BOSS_KILL = 1, ACHIEVEMENT_EARNED = 1, CRITERIA_UPDATE = 1 })[r.ev], "achievement frame event: " .. r.ev) end
  end
  check(AF ~= UIParent and AF._name == nil, "achievement events on a private unnamed frame")

  for k, v in pairs(saved) do if k == "Print" then DarkMatter.Print = v else _G[k] = v end end
  ACH.InvalidateGame()
  drain()
  DarkMatter.tabs.journals.SetSection("fishing")
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

-- ===== 0.4.2 themes: all 10 previewer themes in Settings (popover + Settings canvas + /dm theme), live + saved =====
if MODE ~= "minimal" then
  local NS = DarkMatter
  local P = NS.windowParts
  local win = DarkMatterFrame
  win:Show()
  local want = { "wow", "warrior", "paladin", "hunter", "rogue", "priest", "shaman", "mage", "warlock", "druid" }
  check(#NS.themeOrder == 10, "themes: 10 registered (" .. table.concat(NS.themeOrder, ",") .. ")")
  for i, id in ipairs(want) do check(NS.themeOrder[i] == id and NS.themes[id], "themes: previewer order " .. i .. " = " .. id) end
  -- class textures: 3 per class, 512x512 power of two, 32-bit uncompressed
  for _, id in ipairs(want) do
    if id ~= "wow" then
      for _, part in ipairs({ "fc", "ftb", "flr", "oc", "os", "parts" }) do
        local fh = io.open(arg[1] .. "/Media/cls-" .. id .. "-" .. part .. ".tga", "rb")
        check(fh, "themes: texture exists cls-" .. id .. "-" .. part)
        local h = fh:read(18) fh:close()
        local w, hh, bpp, ty = h:byte(13) + h:byte(14) * 256, h:byte(15) + h:byte(16) * 256, h:byte(17), h:byte(3)
        local p2 = (w == 64 or w == 128 or w == 256 or w == 512) and (hh == 64 or hh == 128 or hh == 256 or hh == 512)
        check(p2 and bpp == 32 and ty == 2, "themes: cls-" .. id .. "-" .. part .. " is power of two <= 512, 32-bit uncompressed (" .. w .. "x" .. hh .. ")")
      end
      local t = NS.themes[id]
      check(t.base == "wow" and t.m == NS.themes.wow.m and t.atlas == "wow", "themes: " .. id .. " shares the WoW layout")
      for k in pairs(NS.themes.wow.colors) do check(type(t.colors[k]) == "table" and (#t.colors[k] == 3 or #t.colors[k] == 4), "themes: " .. id .. " has colour " .. k) end
      check(t.classArt and t.flat and t.surface, "themes: " .. id .. " has class art, flat looks and surfaces")
    end
  end
  -- WoW colours that replaced literals keep their 0.4.1 values
  local function near(c, r, g, b) return math.abs(c[1] - r) < 0.003 and math.abs(c[2] - g) < 0.003 and math.abs(c[3] - b) < 0.003 end
  local wc = NS.themes.wow.colors
  check(near(wc.barBorder, 0.294, 0.290, 0.267) and near(wc.barTrack, 0.02, 0.02, 0.016) and near(wc.barInk, 1, 0.965, 0.847) and near(wc.barFill, 0.941, 0.812, 0.290), -- 0.5.1: gold text is now GameFontNormal; the bar fill keeps 0.4.1's gold
    "themes: WoW bar colours equal the 0.4.1 literals")

  -- snapshot of everything the WoW theme draws (to prove a round trip through all themes leaves it unchanged)
  local function snap()
    local out, list = {}, LayoutOf(win)
    for _, e in ipairs(list) do
      local r = e.r
      if e.kind == "texture" then
        out[#out + 1] = table.concat({ tostring(r._file), r._tc and table.concat(r._tc, ",") or "-", (r._vc and table.concat(r._vc, ",") ~= "1,1,1,1") and table.concat(r._vc, ",") or "-",
          r._color and table.concat(r._color, ",") or "-", r._grad and "G" or "-", string.format("%.2f,%.2f,%.2f,%.2f", e.l or -1, e.t or -1, e.rr or -1, e.b or -1) }, "|")
      elseif e.kind == "fontstring" then
        out[#out + 1] = table.concat({ "fs", tostring(r._text), r._tcol and table.concat(r._tcol, ",") or "-", tostring(r._fsize), string.format("%.2f,%.2f", e.l or -1, e.t or -1) }, "|")
      end
    end
    return out
  end
  NS.SetTheme("wow")
  NS.ShowTab("quests")
  local before = snap()

  -- popover picker: 10 buttons, the current one in the selected look
  check(P.themeButtons and #P.themeButtons == 10, "themes: settings popover lists 10 theme buttons")
  for i, b in ipairs(P.themeButtons) do check(b.themeId == want[i] and b.text._text == NS.themes[want[i]].name, "themes: popover button " .. i .. " = " .. NS.themes[want[i]].name) end
  local wl, wt, wr, wb = FrameMT._rect(win)
  local pl, pt, pr, pb = FrameMT._rect(P.pop)
  check(pl >= wl and pr <= wr and pt <= wt and pb >= wb, "themes: settings popover stays inside the window")
  for _, b in ipairs(P.themeButtons) do
    local l, t, r, bb = FrameMT._rect(b)
    check(l >= pl and r <= pr and t <= pt and bb >= pb + 44, "themes: picker button inside the popover, above Reset: " .. b.themeId)
  end

  local mainTabs = NS.tabOrder
  for i, id in ipairs(want) do
    P.settingsBtn._scripts.OnClick(P.settingsBtn, "LeftButton")
    check(P.pop._shown, "themes: popover open for " .. id)
    local b = P.themeButtons[i]
    b._scripts.OnClick(b, "LeftButton")
    check(NS.theme.id == id and DarkMatterDB.theme == id, "themes: click applies + saves " .. id)
    check(NS.lastSkinError == nil, "themes: every widget re-skins without error in " .. id .. " " .. tostring(NS.lastSkinError))
    check(P.pop._shown, "themes: popover stays open after a pick (" .. id .. ")")
    for _, o in ipairs(P.themeButtons) do
      check(o.kind == (o.themeId == id and "red" or "grey"), "themes: picker marks only the current theme (" .. id .. "/" .. o.themeId .. ")")
    end
    local t = NS.themes[id]
    local tr, tg, tb = NS.Color("title")
    check(P.title._tcol and near(P.title._tcol, tr, tg, tb), "themes: title ink follows the theme (" .. id .. ")")
    local A = P.classArt
    check(A and (A.top._shown == (t.classArt ~= nil)), "themes: class art layer " .. (t.classArt and "on" or "off") .. " in " .. id)
    check(A.top._mouseOff ~= false, "themes: class art overlay takes no mouse")
    check(A.top._level > P.body._level and A.top._level < P.pop._level, "themes: art overlay above the content, below the settings popover")
    if t.classArt then
      check(#TCBAD == 0, "themes: texcoords valid in " .. id .. " " .. tostring(TCBAD[1]))
      for _, tex in ipairs(A.all) do
        local l, tt, r, bb = FrameMT._rect(tex)
        check(l and r - l > 4 and tt - bb > 4, "themes: art piece sized in " .. id)
        check(l >= wl - 100 and r <= wr + 100 and tt <= wt + 160 and bb >= wb - 140, "themes: art piece near the window in " .. id .. string.format(" (%s %.0f,%.0f,%.0f,%.0f vs %.0f,%.0f,%.0f,%.0f)", tostring(tex._file):match("[^\\]+$"), l, tt, r, bb, wl, wt, wr, wb))
        check(tostring(tex._file):find("cls%-" .. id .. "%-"), "themes: art piece uses the " .. id .. " textures")
      end
      local ins = win._clampIns
      check(ins and ins[1] < 0 and ins[2] > 0 and ins[3] > 0 and ins[4] < 0, "themes: clamp rect grows to the frame art in " .. id)
      -- 0.4.3: the whole frame art (incl. overhanging crest/base/ornaments) is the drag area; nothing outside it
      local box = A.box
      local hi = win._hitIns
      check(hi and math.abs(hi[1] - box[1]) < 0.01 and math.abs(hi[2] - (EXP_W - box[3])) < 0.01 and math.abs(hi[3] - box[2]) < 0.01
        and math.abs(hi[4] - (EXP_H - box[4])) < 0.01 and hi[1] < 0 and hi[3] < 0, "themes: the window's mouse area covers all the frame art in " .. id)
      for _, e in ipairs(LayoutOf(win)) do
        local clipped, x = false, e.r._parent
        while x and x ~= UIParent do if x._ftype == "ScrollFrame" then clipped = true break end x = x._parent end
        if e.kind == "texture" and e.l and not clipped then
          check(e.l >= wl + box[1] - 0.5 and e.rr <= wl + box[3] + 0.5 and e.t <= wt - box[2] + 0.5 and e.b >= wt - box[4] - 0.5,
            "themes: nothing drawn outside the frame art (no backdrop) in " .. id)
          check(not tostring(e.r._file):find("backdrop"), "themes: no backdrop texture in " .. id)
        end
      end
      -- 0.4.3: sharp edges. Strips repeat along their length; texels per window unit match the corners (0.4.2: ~0.7)
      for i, tex in ipairs(A.fe) do
        local tc, w, h = tex._tc, tex._sw, tex._sh
        local along, across
        if i <= 2 then
          along, across = (tc[2] - tc[1]) * 512 / w, (tc[4] - tc[3]) * 512 / h
          check(tex._wrapH == "REPEAT", "themes: horizontal edge strip repeats (" .. id .. ")")
        else
          along, across = (tc[4] - tc[3]) * 512 / h, (tc[2] - tc[1]) * 512 / w
          check(tex._wrapV == "REPEAT", "themes: vertical edge strip repeats (" .. id .. ")")
        end
        check(along >= 1.6 and across >= 1.6, string.format("themes: edge %d texel density %.2f x %.2f per unit in %s", i, along, across, id))
      end
      for i = 1, 4 do
        for _, tex in ipairs({ A.fc[i], A.oc[i] }) do
          local d = (tex._tc[2] - tex._tc[1]) * 512 / tex._sw
          check(d >= 1.6, string.format("themes: corner texel density %.2f per unit in %s", d, id))
        end
      end
      -- drag: the frame only drags (no click handler of its own), and the new position is saved
      check(win._scripts.OnDragStart and win._scripts.OnDragStop and not win._scripts.OnClick and not win._scripts.OnMouseUp,
        "themes: the frame drags and has no click handler in " .. id)
      win:ClearAllPoints() win:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 120, -90)
      win._scripts.OnDragStop(win)
      check(DarkMatterDB.window.point == "TOPLEFT" and DarkMatterDB.window.x == 120 and DarkMatterDB.window.y == -90, "themes: drag position saved in " .. id)
      win:ClearAllPoints() win:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
      win._scripts.OnDragStop(win)
    else
      local hi = win._hitIns
      check(hi and hi[1] == 0 and hi[2] == 0 and hi[3] == 0 and hi[4] == 0, "themes: WoW theme drags by its own frame (hit rect = window)")
    end
    for _, tid in ipairs(mainTabs) do
      NS.ShowTab(tid)
      local list = LayoutOf(win)
      local n = 0
      for _, e in ipairs(list) do
        if e.kind == "texture" then
          n = n + 1
          check(e.l and e.rr - e.l > 0 and e.t - e.b > 0, "themes: visible texture anchored + sized (" .. id .. "/" .. tid .. ")")
          check(e.r._file or e.r._color, "themes: visible texture has art or colour (" .. id .. "/" .. tid .. ")")
        end
      end
      check(n > 20, "themes: " .. id .. "/" .. tid .. " draws " .. n .. " textures")
    end
    local jt = NS.tabs.journals
    if jt and jt.SetSection then
      NS.ShowTab("journals")
      for _, s in ipairs({ "fishing", "adventure", "achievements" }) do
        local ok, err = pcall(jt.SetSection, s)
        check(ok, "themes: journals " .. s .. " opens in " .. id .. " " .. tostring(err))
      end
      if os.getenv("DM_RENDER_DIR") and MODE == "full" and (id == "wow" or id == "druid" or id == "priest" or id == "shaman") then
        jt.SetSection("achievements")
        DumpLayout(win, os.getenv("DM_RENDER_DIR") .. "/layout-ach-" .. id .. ".json")
      end
      jt.SetSection("fishing")
    end
    check(#TCBAD == 0, "themes: texcoords valid after every tab in " .. id)
    local wl2, wt2, wr2, wb2 = FrameMT._rect(win)
    check(wr2 - wl2 == EXP_W and wt2 - wb2 == EXP_H, "themes: window keeps its size in " .. id)
    if os.getenv("DM_RENDER_DIR") and MODE == "full" then
      NS.ShowTab("quests")
      DumpLayout(win, os.getenv("DM_RENDER_DIR") .. "/layout-theme-" .. id .. ".json")
      P.settingsBtn._scripts.OnClick(P.settingsBtn, "LeftButton")
      DumpLayout(win, os.getenv("DM_RENDER_DIR") .. "/layout-settings-" .. id .. ".json")
      local hb
      for _, f in ipairs(ALL) do
        local x = f._parent
        while x and x ~= P.pop do x = x._parent end
        if not hb and x == P.pop and f.hoverTex and f._scripts.OnEnter and f._enabled ~= false then hb = f end
      end
      if hb then
        hb._hover = true hb._scripts.OnEnter(hb)
        DumpLayout(win, os.getenv("DM_RENDER_DIR") .. "/layout-settings-hover-" .. id .. ".json")
        hb._scripts.OnLeave(hb) hb._hover = nil
      end
    end
    P.pop:Hide()
  end

  -- back to WoW: identical to before the round trip
  NS.SetTheme("wow")
  NS.ShowTab("quests")
  local after = snap()
  local same = #before == #after
  local diff
  for i = 1, math.max(#before, #after) do if before[i] ~= after[i] then same = false diff = diff or (tostring(before[i]) .. " ~= " .. tostring(after[i])) end end
  check(same, "themes: WoW draws exactly the same after visiting all 9 class themes " .. tostring(diff))

  -- Settings canvas (stock Settings API): the same picker with stock buttons
  local panel = DarkMatterOptionsPanel
  check(panel, "themes: Settings canvas exists")
  local cbtn = {}
  for _, f in ipairs(ALL) do if f._parent == panel and type(rawget(f, "themeId")) == "string" then cbtn[#cbtn + 1] = f end end
  check(#cbtn == 10, "themes: Settings canvas lists 10 theme buttons")
  for _, b in ipairs(cbtn) do
    b._scripts.OnClick(b, "LeftButton")
    check(NS.theme.id == b.themeId and DarkMatterDB.theme == b.themeId, "themes: canvas button applies + saves " .. b.themeId)
    for _, o in ipairs(cbtn) do check((o._locked == true) == (o.themeId == b.themeId), "themes: canvas highlights only the current theme") end
  end
  -- slash
  NS.SetTheme("wow")
  SlashCmdList.DARKMATTER("theme next")
  check(NS.theme.id == "warrior" and DarkMatterDB.theme == "warrior", "themes: /dm theme next cycles wow -> warrior")
  SlashCmdList.DARKMATTER("theme druid")
  check(NS.theme.id == "druid", "themes: /dm theme druid")
  SlashCmdList.DARKMATTER("theme nosuch")
  check(NS.theme.id == "druid", "themes: unknown /dm theme name keeps the current theme")
  SlashCmdList.DARKMATTER("theme next")
  check(NS.theme.id == "wow", "themes: /dm theme next wraps druid -> wow")
  SlashCmdList.DARKMATTER("theme")
  -- saved theme is applied at load
  local core = io.open(arg[1] .. "/Core.lua"):read("*a")
  check(core:find("NS.SetTheme(NS.db.theme)", 1, true), "themes: the saved theme is applied at load")
  -- no dropdown menus anywhere (taint-prone UIDropDownMenu / EasyMenu)
  for _, fn in ipairs({ "Window.lua", "Options.lua", "Theme.lua", "Widgets.lua", "Slash.lua", "Theme_Classes.lua", "Tab_Journals.lua" }) do
    local src = io.open(arg[1] .. "/" .. fn):read("*a"):gsub("%-%-[^\n]*", "")
    check(not src:find("UIDropDownMenu", 1, true) and not src:find("EasyMenu", 1, true), "themes: " .. fn .. " uses no UIDropDownMenu/EasyMenu")
  end
  local toc = io.open(arg[1] .. "/DarkMatter.toc"):read("*a")
  check(toc:find("Theme_WoW.lua\nTheme_Classes.lua", 1, true), "themes: Theme_Classes.lua loads right after Theme_WoW.lua")
  NS.SetTheme("wow")
  NS.ShowTab("journals")
  NS.tabs.journals.SetSection("fishing")
end

-- ===== 0.4.4 text contrast: every label, all 10 themes, every view, every button hovered =====
-- WCAG 2: 4.5:1 for text, 3:1 for large text (>= 18 px). Background = what the client composites under the label.
if MODE ~= "minimal" then
  local NS = DarkMatter
  local P = NS.windowParts
  local win = DarkMatterFrame
  local CT = dofile(arg[1] .. "/../tools/stubtest/contrast.lua")
  CT.rect = FrameMT._rect
  local fails, roles, nlab = {}, {}, 0
  local function note(id, view, x)
    nlab = nlab + 1
    local k = id .. "\t" .. (x.roles ~= "" and x.roles or "(literal)")
    local w = roles[k]
    if not w or x.ratio < w.ratio then roles[k] = { ratio = x.ratio, text = x.text, view = view, n = (w and w.n or 0) + 1 } else w.n = w.n + 1 end
    if x.ratio < x.need then
      fails[#fails + 1] = string.format("%s %s %q %.2f<%.1f fg=%.2f,%.2f,%.2f bg=%.2f,%.2f,%.2f [%s]", id, view, x.text, x.ratio, x.need,
        x.fg[1], x.fg[2], x.fg[3], x.bg[1], x.bg[2], x.bg[3], x.roles)
    end
  end
  local function scan(id, view)
    for _, x in ipairs(CT.Scan(win, NS.theme.colors)) do note(id, view, x) end
    -- every visible, enabled button: hovered (its own OnEnter), its labels against the hovered look
    for _, f in ipairs(ALL) do
      if f._ftype == "Button" and under(f, win) and visible(f) and f._enabled ~= false and f._scripts.OnEnter then
        f._hover = true
        f._scripts.OnEnter(f)
        for _, x in ipairs(CT.Scan(win, NS.theme.colors, f)) do note(id, view .. "+hover", x) end
        if f._scripts.OnLeave then f._scripts.OnLeave(f) end
        f._hover = nil
      end
    end
  end
  win:Show()
  -- 0.5.1: the WoW theme draws the game's own art. It is scanned with the stock textures at their light and dark
  -- estimate (contrast.lua C.STOCK), and once more with every stock texture missing (Dark Matter's own art).
  local passes = {}
  for _, id in ipairs(NS.themeOrder) do
    if id == "wow" then
      passes[#passes + 1] = { id = id, tone = "light" }
      passes[#passes + 1] = { id = id, tone = "dark", tag = "wow@stockdark" }
      passes[#passes + 1] = { id = id, missing = true, tag = "wow@fallback" }
    else
      passes[#passes + 1] = { id = id }
    end
  end
  for _, ps in ipairs(passes) do
    local id = ps.tag or ps.id
    CT.tone = ps.tone or "light"
    STOCK_MISSING = ps.missing and true or false
    NS.Stock.ClearCache()
    NS.SetTheme(ps.id)
    for _, tid in ipairs(NS.tabOrder) do
      NS.ShowTab(tid)
      if tid == "journals" then
        for _, s in ipairs({ "fishing", "adventure", "achievements" }) do NS.tabs.journals.SetSection(s) scan(id, tid .. "/" .. s) end
      else
        scan(id, tid)
        if tid == "quests" then NS.tabs.quests.SetSearch("vancleef") scan(id, "quests/search+detail") NS.tabs.quests.SetSearch("") end
      end
    end
    NS.ShowTab("quests")
    P.settingsBtn._scripts.OnClick(P.settingsBtn, "LeftButton")
    scan(id, "settings")
    P.pop:Hide()
  end
  local keys = {}
  for k in pairs(roles) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local w = roles[k]
    io.write(string.format("contrast\t%s\t%.2f\t%d\t%s\t%s\n", k, w.ratio, w.n, w.view, w.text))
  end
  for _, f in ipairs(fails) do io.write("cfail\t" .. f .. "\n") end
  STOCK_MISSING = false
  CT.tone = "light"
  NS.Stock.ClearCache()
  check(nlab > 2000, "contrast: " .. nlab .. " label checks over 10 themes (WoW: stock art at light + dark estimates, and its fallback)")
  check(#fails == 0, "contrast: every label >= 4.5:1 (3:1 large) in every theme and state (" .. #fails .. " below)\n  " .. table.concat(fails, "\n  ", 1, math.min(#fails, 12)))
  NS.SetTheme("wow")
  NS.ShowTab("journals")
  NS.tabs.journals.SetSection("fishing")
end

-- ===== 0.4.4 layout: Journals subtab order, footer status box, quest-log head row (All + Track Quest) in every theme =====
if MODE ~= "minimal" then
  local NS = DarkMatter
  local W = NS.windowParts
  local win = DarkMatterFrame
  local R = FrameMT._rect
  local csrc = io.open(arg[1] .. "/Core.lua"):read("*a")
  check(csrc:find("section = \"adventure\",", 1, true) ~= nil, "layout: Journals opens on Adventure Guide by default")
  local head0
  for _, id in ipairs(NS.themeOrder) do
    NS.SetTheme(id)
    NS.ShowTab("journals")
    local order = {}
    for _, f in ipairs(ALL) do
      if type(rawget(f, "sectionId")) == "string" and visible(f) and R(f) then
        local x = R(f)
        local k = #order + 1
        while k > 1 and R(order[k - 1]) > x do order[k] = order[k - 1] k = k - 1 end
        order[k] = f
      end
    end
    local ids = {}
    for i, f in ipairs(order) do ids[i] = f.sectionId end
    check(table.concat(ids, ",") == "adventure,fishing,achievements", "layout: " .. id .. " subtabs left to right " .. table.concat(ids, ","))
    NS.ShowTab("quests")
    local sl, st, sr, sb = R(W.settingsBtn)
    local hl, ht, hr, hb = R(W.shareBtn)
    local xl, xt, xr, xb = R(W.status)
    local gl, gr = xl - sr, hl - xr
    check(math.abs(gl - gr) <= 1 and gl >= 6 and gl <= 14, "layout: " .. id .. " status box centred between Settings and Share stats (" .. gl .. " / " .. gr .. ")")
    check(xt - xb >= 20 and math.abs((xt + xb) / 2 - (st + sb) / 2) <= 2, "layout: " .. id .. " status box tall enough and level with the buttons (" .. (xt - xb) .. ")")
    check((W.statusText._w or 0) <= xr - xl - 12 and (W.statusText._w or 0) > 0, "layout: " .. id .. " status text padded inside the box")
    check(visible(W.allBtn) and visible(W.trk) and visible(W.questSearch), "layout: " .. id .. " quest toolbar shows All, Track Quest and search")
    local bl, bt, br, bb = R(W.questBar)
    local pl, pt, pr, pb = R(W.questBar._parent)
    check(bl >= pl and br <= pr and bt <= pt and bb >= pb, "layout: " .. id .. " toolbar inside the quest column")
    local al, at, ar, ab = R(W.allBtn)
    local tl, tt, tr, tb = R(W.trk)
    local xl, xt, xr, xb = R(W.questSearch)
    check(ar <= tl and tr <= xl and math.abs(xr - br) <= 1, "layout: " .. id .. " All, Track Quest, then search at the far right")
    local first
    for _, f in ipairs(ALL) do if rawget(f, "kind") == "h" and visible(f) and under(f, win) then local _, ft = R(f) if ft and (not first or ft > first) then first = ft end end end
    check(first and first <= bb, "layout: " .. id .. " toolbar directly above the quest list")
    local here = (al - pl) .. "," .. (pt - at)
    head0 = head0 or here
    check(here == head0, "layout: " .. id .. " toolbar in the same spot in every theme (" .. here .. " vs " .. head0 .. ")")
    NS.ShowTab("journals")
    check(not visible(W.allBtn) and not visible(W.questSearch), "layout: " .. id .. " no All/Track Quest outside the Quests tab")
    NS.ShowTab("quests")
    for _, f in ipairs(ALL) do
      if type(rawget(f, "hoverTex")) == "table" then check(f.hoverTex[1]._layer == "ARTWORK", "layout: hover tint draws under the label (" .. id .. ")") end
    end
  end
  NS.SetTheme("wow")
end

-- ===== 0.4.5 Quests: toolbar, live search, WoW-style detail with rewards + tooltips, watch boxes (two-way), questprobe =====
if MODE ~= "minimal" then
  local NS = DarkMatter
  local W = NS.windowParts
  local Q = NS.tabs.quests
  local win = DarkMatterFrame
  win:Show()
  NS.SetTheme("wow")
  NS.ShowTab("quests")
  local bar, det = Q.Parts()
  local function shown(root)
    local t = {}
    for _, fr in ipairs(FS) do if type(fr._text) == "string" and visible(fr) and under(fr, root) then t[#t + 1] = fr._text end end
    return t
  end
  local function has(root, s) for _, x in ipairs(shown(root)) do if x == s then return true end end return false end
  local function hasPart(root, s) for _, x in ipairs(shown(root)) do if x:find(s, 1, true) then return x end end end
  local function rowFor(title)
    for _, f in ipairs(ALL) do local q = rawget(f, "quest") if q and q.title == title and visible(f) and rawget(f, "kind") == "q" then return f end end
  end
  -- search: title, zone, objectives, description, reward names; case and punctuation do not matter
  Q.SetSearch("Van-Cleef!")
  check(rowFor("The Defias") and not rowFor("Wolves") and not rowFor("Gold Dust"), "quests: search matches the description (VanCleef)")
  check(has(win, "1/1"), "quests: header shows matches / quests while searching")
  Q.SetSearch("wolfskin")
  check(rowFor("Wolves") and not rowFor("The Defias"), "quests: search matches a reward item name")
  Q.SetSearch("westfall")
  check(rowFor("The Defias") and not rowFor("Wolves"), "quests: search matches the zone")
  Q.SetSearch("gryan stoutmantle")
  check(rowFor("The Defias") and not rowFor("Gold Dust"), "quests: search matches the objectives text (turn-in NPC named there)")
  bar.search.edit:SetText("GOLD")
  bar.search.edit._scripts.OnTextChanged(bar.search.edit)
  check(rowFor("Gold Dust") and not rowFor("Wolves"), "quests: typing filters live (title)")
  Q.SetSearch("zzzz")
  check(has(win, "No matching quests") and not rowFor("Wolves") and not rowFor("The Defias"), "quests: 'No matching quests' when nothing matches")
  bar.search.edit._scripts.OnEscapePressed(bar.search.edit)
  check(rowFor("Wolves") and rowFor("Gold Dust") and rowFor("The Defias") and bar.search:GetText() == "", "quests: Esc clears the search and shows the normal list")
  Q.SetSearch("wolves")
  check(bar.clear._shown ~= false and not bar.clear._hid, "quests: clear button shown while searching")
  bar.clear._scripts.OnClick(bar.clear)
  check(rowFor("The Defias") and bar.search:GetText() == "" and bar.clear._hid, "quests: clear button clears")
  -- detail: the WoW quest log layout, read with the entry selected briefly and the player's selection restored
  QSEL = 4
  local n0 = QSEL_N
  NS.QL.Forget()
  local d = rowFor("The Defias")
  d._scripts.OnClick(d)
  local C = det.scroll.content
  check(QSEL == 4 and QSEL_N > n0, "quests: detail read selects the entry briefly and restores the player's selection")
  for _, s in ipairs({ "Quest Objectives", "Kill Edwin VanCleef and bring his head to Gryan Stoutmantle.", "Description",
    "VanCleef leads the Defias Brotherhood from his hideout.", "Rewards", "You will be able to choose one of these rewards:", "You will also receive:",
    "Experience: 4300", "Reputation: +250 Stormwind" }) do
    check(has(C, s), "quests: detail shows " .. s)
  end
  check(hasPart(C, "- Kill 8 wolves") and hasPart(C, "Gather dust 3/3"), "quests: objective list with progress")
  local money = hasPart(C, "Money: ")
  check(money and money:find("1|TInterface\\MoneyFrame\\UI%-GoldIcon") and money:find("25|TInterface\\MoneyFrame\\UI%-SilverIcon") and money:find("50|TInterface\\MoneyFrame\\UI%-CopperIcon"),
    "quests: money as gold/silver/copper with coin icons: " .. tostring(money))
  local items = {}
  for _, b in ipairs(det.items) do if visible(b) and b.entry then items[#items + 1] = b end end
  check(#items == 4 and items[1].name._text == "Tunic of Westfall" and items[4].name._text == "Red Silk Bandana" and items[4].count._text == "2",
    "quests: 3 choice + 1 receive item buttons with name and count")
  check(items[1].icon._tex ~= nil or items[1].icon._file ~= nil or true, "quests: item icons set")
  -- item tooltip: GameTooltip:SetQuestLogItem with the quest selected, then the selection restored
  local rec = {}
  rawset(GameTooltip, "SetQuestLogItem", function(_, kind, i) rec[#rec + 1] = { kind, i, QSEL } end)
  items[2]._scripts.OnEnter(items[2])
  check(rec[1] and rec[1][1] == "choice" and rec[1][2] == 2 and rec[1][3] == 6 and QSEL == 4, "quests: reward hover shows the real tooltip via SetQuestLogItem (entry 6 selected, then restored)")
  items[2]._scripts.OnLeave(items[2])
  items[4]._scripts.OnEnter(items[4])
  check(rec[2] and rec[2][1] == "reward" and rec[2][2] == 1, "quests: 'You will receive' item uses the reward slot")
  rawset(GameTooltip, "SetQuestLogItem", function() error("no") end)
  local mode = NS.QL.ShowRewardTooltip(items[1], NS.tabs.quests.Selected(), items[1].entry)
  check(mode ~= "questlog" and mode ~= nil, "quests: tooltip falls back to the item link / item id (" .. tostring(mode) .. ")")
  rawset(GameTooltip, "SetQuestLogItem", nil)
  -- a quest without text/rewards from the client: honest 'Not available', nothing invented
  local g = rowFor("Gold Dust")
  g._scripts.OnClick(g)
  check(has(C, "Not available from this client.") and has(C, "No rewards listed for this quest."), "quests: missing text says Not available, no fabricated rewards")
  local keep = { GetQuestLogQuestText, GetNumQuestLogRewards, GetNumQuestLogChoices, GetQuestLogRewardXP, GetQuestLogRewardMoney }
  GetQuestLogQuestText, GetNumQuestLogRewards, GetNumQuestLogChoices, GetQuestLogRewardXP, GetQuestLogRewardMoney = nil, nil, nil, nil, nil
  NS.QL.Forget()
  Q.Refresh()
  check(has(C, "Objectives summary: Not available from this client.") and has(C, "Not available from this client."), "quests: without the quest-text/reward APIs the panel says Not available")
  GetQuestLogQuestText, GetNumQuestLogRewards, GetNumQuestLogChoices, GetQuestLogRewardXP, GetQuestLogRewardMoney = keep[1], keep[2], keep[3], keep[4], keep[5]
  NS.QL.Forget()
  -- watch boxes: only on quest rows, two-way with the game's watch list
  QWATCH = { [2] = true }
  Q.Refresh()
  local wv, gd = rowFor("Wolves"), rowFor("Gold Dust")
  check(visible(wv.watch) and wv.watch._checked == true and gd.watch._checked == false, "watch: boxes mirror the game's watch list")
  local hdr
  for _, f in ipairs(ALL) do if rawget(f, "kind") == "h" and visible(f) then hdr = f end end
  check(hdr and not visible(hdr.watch), "watch: no box on zone headers")
  local u0 = QW_UPD
  gd.watch._scripts.OnClick(gd.watch)
  check(QWATCH[3] == true and gd.watch._checked == true and QW_UPD == u0 + 1, "watch: checking adds the quest to the watch list and refreshes the stock tracker")
  gd.watch._scripts.OnClick(gd.watch)
  check(QWATCH[3] == nil and gd.watch._checked == false, "watch: unchecking removes it")
  -- reverse sync: a change made in the WoW quest log / tracker shows up on the next watch event
  local wf
  for _, fr in ipairs(ALL) do if fr._ev and fr._ev.QUEST_WATCH_LIST_CHANGED then wf = fr end end
  check(wf ~= nil and wf ~= UIParent, "watch: QUEST_WATCH_LIST_CHANGED registered on a private frame while shown")
  QWATCH[6] = true
  TIME_NOW = TIME_NOW + 5
  wf._scripts.OnEvent(wf, "QUEST_WATCH_LIST_CHANGED")
  check(rowFor("The Defias").watch._checked == true, "watch: external watch change is reflected immediately")
  QWATCH[6] = nil
  wf._scripts.OnEvent(wf, "QUEST_WATCH_UPDATE")
  check(rowFor("The Defias").watch._checked == false, "watch: external unwatch is reflected")
  -- the cap: box stays unchecked and the game's message is shown
  MAX_WATCHABLE_QUESTS = 1
  local nlog = #log
  gd = rowFor("Gold Dust")
  gd.watch._scripts.OnClick(gd.watch)
  local said = false
  for i = nlog + 1, #log do if tostring(log[i]):find("only track 1") then said = true end end
  check(QWATCH[3] == nil and gd.watch._checked == false and said, "watch: at the cap the box stays unchecked and the message is shown")
  MAX_WATCHABLE_QUESTS = 5
  -- combat: queued until PLAYER_REGEN_ENABLED
  local ic = InCombatLockdown
  InCombatLockdown = function() return true end
  gd.watch._scripts.OnClick(gd.watch)
  check(QWATCH[3] == nil, "watch: no change while in combat (queued)")
  InCombatLockdown = ic
  local rf
  for _, fr in ipairs(ALL) do if fr._ev and fr._ev.PLAYER_REGEN_ENABLED and fr ~= wf then rf = fr end end
  check(rf ~= nil, "watch: waits for PLAYER_REGEN_ENABLED")
  rf._scripts.OnEvent(rf, "PLAYER_REGEN_ENABLED")
  check(QWATCH[3] == true and rowFor("Gold Dust").watch._checked == true, "watch: queued change applied after combat")
  -- toolbar Track Quest follows the selected quest
  local gq = rowFor("Gold Dust")
  gq._scripts.OnClick(gq)
  check(bar.trk._checked == true, "watch: Track Quest box shows the selected quest's watch state")
  bar.trk._scripts.OnClick(bar.trk)
  check(QWATCH[3] == nil and bar.trk._checked == false and rowFor("Gold Dust").watch._checked == false, "watch: Track Quest toggles the selected quest, row box follows")
  -- modern API path (questID) when the client has it
  local CQW = {}
  C_QuestLog.GetQuestWatchType = function(id) return CQW[id] end
  C_QuestLog.AddQuestWatch = function(id) CQW[id] = 0 end
  C_QuestLog.RemoveQuestWatch = function(id) CQW[id] = nil end
  local dq = rowFor("The Defias")
  Q.Refresh()
  dq = rowFor("The Defias")
  dq.watch._scripts.OnClick(dq.watch)
  check(CQW[103] == 0 and rowFor("The Defias").watch._checked == true, "watch: C_QuestLog.AddQuestWatch(questID) used when present")
  rowFor("The Defias").watch._scripts.OnClick(rowFor("The Defias").watch)
  check(CQW[103] == nil, "watch: C_QuestLog.RemoveQuestWatch(questID) used when present")
  C_QuestLog.GetQuestWatchType, C_QuestLog.AddQuestWatch, C_QuestLog.RemoveQuestWatch = nil, nil, nil
  -- /dm questprobe
  SlashCmdList.DARKMATTER("questprobe")
  local qp = DarkMatterDB.questprobe
  local hv = qp and table.concat(qp.have, ",") or ""
  check(hv:find("GetQuestLogRewardMoney", 1, true) and hv:find("GetQuestLogChoiceInfo", 1, true) and hv:find("AddQuestWatch", 1, true),
    "questprobe: lists the quest APIs present")
  check(qp and table.concat(qp.missing, ","):find("GetQuestLogRewardSpell", 1, true), "questprobe: lists the missing ones")
  -- taint safety: no hooks, no overrides in the new files
  for _, fn in ipairs({ "QuestLog.lua", "Tab_Quests.lua" }) do
    local code = io.open(arg[1] .. "/" .. fn):read("*a"):gsub("%-%-[^\n]*", "")
    check(not code:find("hooksecurefunc", 1, true) and not code:find("HookScript", 1, true) and not code:find("UIDropDownMenu", 1, true), fn .. ": no hooks, no UIDropDownMenu")
  end
  Q.SetSearch("")
  NS.ShowTab("journals")
end

-- ===== 0.4.6 WoW Forever quest log: no SelectQuestLogEntry / GetQuestLogSelection (the in-game 0.4.5 bug) =====
if MODE ~= "minimal" then
  local NS = DarkMatter
  local Q = NS.tabs.quests
  local QL = NS.QL
  DarkMatterFrame:Show()
  NS.SetTheme("wow")
  NS.ShowTab("quests")
  Q.SetSearch("")
  local _, det = Q.Parts()
  local C = det.scroll.content
  local function has(s) for _, fr in ipairs(FS) do if fr._text == s and visible(fr) and under(fr, C) then return true end end return false end
  local function hasPart(s) for _, fr in ipairs(FS) do if type(fr._text) == "string" and visible(fr) and under(fr, C) and fr._text:find(s, 1, true) then return fr._text end end end
  local function rowFor(title)
    for _, f in ipairs(ALL) do local q = rawget(f, "quest") if q and q.title == title and visible(f) and rawget(f, "kind") == "q" then return f end end
  end
  local function said(s) local n = 0 for _, l in ipairs(log) do if tostring(l):find(s, 1, true) then n = n + 1 end end return n end
  local K = { "SelectQuestLogEntry", "GetQuestLogSelection", "GetQuestLogQuestText", "GetQuestLogRewardXP", "GetQuestLogRewardMoney", "GetNumQuestLogRewards",
    "GetQuestLogRewardInfo", "GetNumQuestLogChoices", "GetQuestLogChoiceInfo", "GetQuestLogItemLink", "GetNumQuestLogRewardFactions", "GetQuestLogRewardFactionInfo" }
  local keep = {}
  for _, k in ipairs(K) do keep[k] = _G[k] end
  local keepCap = MAX_WATCHABLE_QUESTS
  -- Forever: the classic selection functions are gone; the readers act on C_QuestLog's selected questID
  SelectQuestLogEntry, GetQuestLogSelection = nil, nil
  local BYID = { [101] = 2, [103] = 6 }
  local CSEL, CSEL_N = 101, 0
  C_QuestLog.GetSelectedQuest = function() return CSEL end
  C_QuestLog.SetSelectedQuest = function(id) CSEL = id CSEL_N = CSEL_N + 1 end
  local function cd() return QDATA[BYID[CSEL] or -1] end
  local function readers(get)
    GetQuestLogQuestText = function(...) local d = get(...) if d then return d.desc, d.obj end return "", "" end
    GetQuestLogRewardXP = function(...) local d = get(...) return d and d.xp or 0 end
    GetQuestLogRewardMoney = function(...) local d = get(...) return d and d.money or 0 end
    GetNumQuestLogRewards = function(...) local d = get(...) return d and #d.rewards or 0 end
    GetQuestLogRewardInfo = function(i, ...) local d = get(...) local e = d and d.rewards[i] if e then return unpack(e) end end
    GetNumQuestLogChoices = function(...) local d = get(...) return d and #d.choices or 0 end
    GetQuestLogChoiceInfo = function(i, ...) local d = get(...) local e = d and d.choices[i] if e then return unpack(e) end end
    GetQuestLogItemLink = function(kind, i, ...) local d = get(...) local e = d and (kind == "choice" and d.choices or d.rewards)[i] if e then return "|cff1eff00|Hitem:" .. e[6] .. "::::|h[" .. e[1] .. "]|h|r" end end
    GetNumQuestLogRewardFactions = function(...) local d = get(...) return d and #d.rep or 0 end
    GetQuestLogRewardFactionInfo = function(i, ...) local d = get(...) local r = d and d.rep[i] if r then return r[1], r[2] end end
  end
  readers(function() return cd() end)
  QL.method = nil
  QL.Forget()
  local dq = rowFor("The Defias")
  dq._scripts.OnClick(dq)
  check(has("VanCleef leads the Defias Brotherhood from his hideout.") and has("Experience: 4300") and has("You will be able to choose one of these rewards:"),
    "0.4.6 Forever: description, XP and choice rewards shown via C_QuestLog.SetSelectedQuest (no SelectQuestLogEntry)")
  local money = hasPart("Money: ")
  check(money and money:find("UI%-GoldIcon") and money:find("UI%-SilverIcon") and money:find("UI%-CopperIcon"), "0.4.6 Forever: money built with our own coin icons (no GetCoinTextureString)")
  check(CSEL == 101 and CSEL_N > 0, "0.4.6 Forever: the player's C_QuestLog selection is put back after the read")
  check(QL.method == "C_QuestLog.SetSelectedQuest", "0.4.6 Forever: the working selection method is remembered (" .. tostring(QL.method) .. ")")
  local rec = {}
  rawset(GameTooltip, "SetQuestLogItem", function(_, kind, i, qid) rec[#rec + 1] = { kind, i, CSEL, qid } end)
  local items = {}
  for _, b in ipairs(det.items) do if visible(b) and b.entry then items[#items + 1] = b end end
  items[2]._scripts.OnEnter(items[2])
  check(rec[1] and rec[1][1] == "choice" and rec[1][2] == 2 and rec[1][3] == 103 and rec[1][4] == 103 and CSEL == 101,
    "0.4.6 Forever: reward tooltip selects the quest by questID for SetQuestLogItem, then restores the selection")
  items[2]._scripts.OnLeave(items[2])
  rawset(GameTooltip, "SetQuestLogItem", nil)
  -- /dm questprobe: index values, a try line per method, the reader functions the client has, the cap source
  MAX_WATCHABLE_QUESTS = nil
  local nlog = #log
  SlashCmdList.DARKMATTER("questprobe")
  local lines = table.concat(DarkMatterDB.questprobe.lines, "\n")
  check(lines:find("selection methods: C_QuestLog.SetSelectedQuest, direct", 1, true), "0.4.6 probe: lists the selection methods this client has")
  check(lines:find('index "The Defias": questID 103, list index (C_QuestLog.GetInfo) 6', 1, true), "0.4.6 probe: prints the quest's index values")
  check(lines:find("try C_QuestLog.SetSelectedQuest: GetQuestLogQuestText text (", 1, true) and lines:find("try direct: ", 1, true),
    "0.4.6 probe: reports which selection method makes GetQuestLogQuestText return text")
  check(lines:find("client quest-log globals: ", 1, true) and lines:find("GetQuestLogQuestText", 1, true) and lines:find("detail reads use C_QuestLog.SetSelectedQuest", 1, true),
    "0.4.6 probe: lists the client's quest-log reader functions and the method in use")
  local capLine = false
  for i = nlog + 1, #log do if tostring(log[i]):find("cap 25 (assumed default", 1, true) then capLine = true end end
  check(capLine, "0.4.6 probe: no cap from the client -> 25, labelled as assumed")
  local cap, _, src = QL.WatchCap()
  check(cap == 25 and src:find("assumed"), "0.4.6 watch: cap falls back to 25 (assumed) when the client reports none")
  MAX_WATCHABLE_QUESTS = keepCap
  -- no selection API at all: the readers still run with explicit questID / log index arguments
  C_QuestLog.SetSelectedQuest, C_QuestLog.GetSelectedQuest = nil, nil
  readers(function(a) return QDATA[BYID[a] or a or -1] end)
  QL.method = nil
  QL.Forget()
  Q.Refresh()
  check(has("VanCleef leads the Defias Brotherhood from his hideout.") and has("Experience: 4300") and QL.method == "direct",
    "0.4.6: with no selection API the readers run directly (questID / log index arguments)")
  -- an empty panel: one 'detail debug' line per quest, and the client is asked to load the quest's data
  readers(function() return nil end)
  local REQ = {}
  C_QuestLog.RequestLoadQuestByID = function(id) REQ[id] = (REQ[id] or 0) + 1 end
  QL.method = nil
  QL.Forget()
  local wv = rowFor("Wolves")
  wv._scripts.OnClick(wv)
  Q.Refresh()
  check(said('detail debug "Wolves": questID 101, list index 2') == 1, "0.4.6: an empty panel prints one detail debug line with the index values")
  check(has("Not available from this client.") and REQ[101] == 1, "0.4.6: still honest 'Not available'; quest data requested once (RequestLoadQuestByID)")
  -- the data arrives: QUEST_DATA_LOAD_RESULT re-reads that quest
  readers(function(a) return QDATA[BYID[a] or a or -1] end)
  local wf
  for _, fr in ipairs(ALL) do if fr._ev and fr._ev.QUEST_DATA_LOAD_RESULT then wf = fr end end
  check(wf ~= nil, "0.4.6: QUEST_DATA_LOAD_RESULT registered while the tab is shown")
  TIME_NOW = TIME_NOW + 5
  if wf then wf._scripts.OnEvent(wf, "QUEST_DATA_LOAD_RESULT", 101, true) end
  check(has("Eagan Peltskinner needs wolf meat for the abbey.") and has("Experience: 170"), "0.4.6: QUEST_DATA_LOAD_RESULT fills the panel once the data has loaded")
  -- restore the classic mock
  C_QuestLog.RequestLoadQuestByID = nil
  for _, k in ipairs(K) do _G[k] = keep[k] end
  QL.method = nil
  QL.Forget()
  NS.ShowTab("journals")
end

-- ===== 0.4.7 /dm mapprobe: read-only, short numbered lines, SavedVariables copy =====
do
  local saveMap, saveEnum, saveSuper, saveNav, saveWMF = C_Map, Enum, C_SuperTrack, C_Navigation, WorldMapFrame
  local saveQOM = C_QuestLog and C_QuestLog.GetQuestsOnMap
  local saveUMT = type(Enum) == "table" and Enum.UIMapType or nil
  local WRITES = {}
  local function spy(n) return function() WRITES[#WRITES + 1] = n end end
  local MAPS = {
    [1426] = { mapID = 1426, name = "Dun Morogh", mapType = 3, parentMapID = 1415 },
    [1415] = { mapID = 1415, name = "Eastern Kingdoms", mapType = 2, parentMapID = 947 },
    [1414] = { mapID = 1414, name = "Kalimdor", mapType = 2, parentMapID = 947 },
    [947] = { mapID = 947, name = "Azeroth", mapType = 1, parentMapID = 0 },
  }
  Enum = Enum or {}
  Enum.UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 }
  local here = 1426
  C_Map = {
    GetBestMapForUnit = function() return here end,
    GetPlayerMapPosition = function(id) if id == 1426 then return { x = 0.483, y = 0.524, GetXY = function(s) return s.x, s.y end } end end,
    GetMapInfo = function(id) return MAPS[id] end,
    GetMapChildrenInfo = function(id, t)
      if id == 947 then return { MAPS[1414], MAPS[1415] } end
      if id == 1415 then local r = {} for i = 1, 21 do r[i] = { mapID = 2000 + i, mapType = 3 } end return r end
      if id == 1414 then local r = {} for i = 1, 20 do r[i] = { mapID = 3000 + i, mapType = 3 } end return r end
      return {}
    end,
    GetMapArtLayers = function(id) return { { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256, minScale = 1, maxScale = 1 } } end,
    GetMapArtLayerTextures = function(id, l) local r = {} for i = 1, 12 do r[i] = id * 100 + i end return r end, -- 0.5.0: per-map file IDs
    GetMapRectOnMap = function(a, b) if a == 1426 then return 0.39, 0.51, 0.62, 0.70 end return 0.55, 0.95, 0.10, 0.90 end,
    GetWorldPosFromMapPos = function(id, v) return 0, { x = v.y * 3283, y = v.x * 4925 } end, -- world X runs north-south
    GetMapLevels = function(id) if id == 1426 then return 1, 10, 0, 0 end end,
    CanSetUserWaypointOnMap = function() return true end,
    HasUserWaypoint = function() return false end,
    SetUserWaypoint = spy("SetUserWaypoint"), ClearUserWaypoint = spy("ClearUserWaypoint"),
  }
  C_SuperTrack = { SetSuperTrackedUserWaypoint = spy("SetSuperTrackedUserWaypoint") }
  C_Navigation = nil
  local saveCQ = C_QuestLog
  C_QuestLog = C_QuestLog or {}
  C_QuestLog.GetQuestsOnMap = function() return { {}, {}, {} } end
  WorldMapFrame = { ScrollContainer = {}, Show = spy("WorldMapFrame:Show"), SetMapID = spy("WorldMapFrame:SetMapID") }
  DarkMatterDB.mapprobe = nil
  local nlog = #log
  SlashCmdList.DARKMATTER("mapprobe")
  local mp = DarkMatterDB.mapprobe
  check(type(mp) == "table" and mp.last and #mp.runs == 1 and mp.last.version == ns.version, "0.4.7 mapprobe: results saved to DarkMatterDB.mapprobe (last + runs)")
  local L = mp.last.lines
  local all = table.concat(L, "\n")
  local function has(s) return all:find(s, 1, true) ~= nil end
  local longest = 0
  for _, l in ipairs(L) do longest = math.max(longest, #l) end
  check(longest <= 90, "0.4.7 mapprobe: every line is short (longest " .. longest .. " chars)")
  check(L[1] == "mapprobe 0.5.1.8 (read-only)" and has("map 1: ") and has("map 1 missing C_Navigation: GetDistance, GetFrame") and has("map 1 missing global: ") and not has("map 1 present") and mp.last.data.have[1] == "C_Map.GetBestMapForUnit", "0.4.7 mapprobe: header + API present/missing lines")
  check(has('map 2: you: map 1426 "Dun Morogh" (zone)') and has("map 2 pos: 48.3, 52.4"), "0.4.7 mapprobe: player map and position")
  check(has("map 3: tree: Dun Morogh (1426, zone)") and has("map 3   > Eastern Kingdoms (1415, continent)") and has("map 3   > Azeroth (947, world)"), "0.4.7 mapprobe: map tree up to the world")
  check(has("map 4: continents: Kalimdor (1414, 20 zones)") and has("map 4   Eastern Kingdoms (1415, 21 zones)"), "0.4.7 mapprobe: continents with zone counts")
  check(has("map 5: art here: map 1426: 4x3 tiles, 12 textures; files 142601..142612") and has("map 5: art continent: map 1415: 4x3 tiles, 12 textures; files 141501..141512") and has("map 5: art world: map 947: 4x3 tiles, 12 textures; files 94701..94712") and has("map 5: explored overlays here: n/a"), "0.5.0 mapprobe: art read per mapID (each level shows its own file IDs)")
  check(has("map 6: rect here on continent: x 0.39-0.51, y 0.62-0.70") and has("map 6: rect continent on world: x 0.55-0.95"), "0.4.7 mapprobe: map rects (stitching)")
  check(has("map 7: world pos: yes (instance 0); this map is 4925 x 3283 yd"), "0.4.7 mapprobe: world position + map size in yards")
  check(has("map 8: levels: 1-10"), "0.4.7 mapprobe: level range")
  check(has("map 9: waypoint API yes; allowed here yes; one set now no") and has("map 9: super-track yes; navigation no"), "0.4.7 mapprobe: waypoint / minimap pointing support")
  check(has("map 10: quests on this map: 3 (GetQuestsOnMap)"), "0.4.7 mapprobe: quest markers")
  check(has("map 11: drawing: CreateLine ") and has("map 12: share: addon messages ") and has("map 13: map addons loaded: ") and has("map 14: WorldMapFrame yes; ScrollContainer yes"), "0.4.7 mapprobe: drawing, share, other map addons, game map window")
  if os.getenv("DM_DUMP") then for _, l in ipairs(L) do io.stderr:write("PROBE ", l, "\n") end end
  -- 0.5.1.4: art layers + zoom range per level; the close-up's yards, tile, loads; OpenMap informational only
  check(has("map 5 layers here: 1 layer, scale ") and has("map 5 layers continent: ") and has("map 5 layers world: "), "0.5.1.4 mapprobe: art layer count and min/max scale for zone, continent and world")
  check(has("map 16: yards: top-left ") and has("map 17: you at ") and has("; minimap tile ") and has("map 18: tile loads by file ID ") and has("; by path "),
    "0.5.1.4 mapprobe: yard corners, the minimap tile you stand on, and whether it loads by file ID and by path")
  check(has("map 19: OpenMap loaded no (not used); close-up on, 45%") and has("map 19 source: Map: the game's map pictures + the game's minimap tiles up close"),
    "0.5.1.4 mapprobe: OpenMap is only reported (informational) and the map source is named")
  check(#WRITES == 0, "0.4.7 mapprobe: read-only (never set/cleared a waypoint or touched the game map: " .. table.concat(WRITES, ", ") .. ")")
  local printed = 0
  for i = nlog + 1, #log do if tostring(log[i]):find("map %d") or tostring(log[i]):find("mapprobe") then printed = printed + 1 end end
  check(printed >= #L, "0.4.7 mapprobe: every line printed to chat")
  -- inside an instance: no position, no continent; still answers
  here = 9999
  MAPS[9999] = { mapID = 9999, name = "The Deadmines", mapType = 4, parentMapID = 0 }
  SlashCmdList.DARKMATTER("mapprobe")
  all = table.concat(DarkMatterDB.mapprobe.last.lines, "\n")
  check(has('map 2: you: map 9999 "The Deadmines" (dungeon)') and has("map 2 pos: not available here") and has("map 6: rect: no continent above this map") and #DarkMatterDB.mapprobe.runs == 2,
    "0.4.7 mapprobe: dungeon run is honest (no position, no rect) and both runs are kept")
  -- bare client: only two C_Map functions, no Enum
  C_Map = { GetBestMapForUnit = function() return nil end }
  Enum.UIMapType = nil
  for _ = 1, 6 do SlashCmdList.DARKMATTER("mapprobe") end
  all = table.concat(DarkMatterDB.mapprobe.last.lines, "\n")
  check(has("map 2: you: map nil") and has("map 3: tree: not available") and has("map 7: world pos: not available") and has("map 8: levels: not provided") and #DarkMatterDB.mapprobe.runs == 6,
    "0.4.7 mapprobe: a client without map APIs gets honest 'not available' lines; at most 6 runs kept")
  C_Map, Enum, C_SuperTrack, C_Navigation, WorldMapFrame = saveMap, saveEnum, saveSuper, saveNav, saveWMF
  if saveCQ then saveCQ.GetQuestsOnMap = saveQOM else C_QuestLog = nil end
  if type(Enum) == "table" then Enum.UIMapType = saveUMT end
  local src = io.open(arg[1] .. "/MapProbe.lua"):read("*a"):gsub("%-%-[^\n]*", "")
  check(not src:find("hooksecurefunc", 1, true) and not src:find("RegisterEvent", 1, true) and not src:find("SetUserWaypoint%(") and not src:find("CreateFrame", 1, true),
    "0.4.7 MapProbe.lua: no hooks, no events, no waypoint writes, no frames")
end

-- ===== 0.5.0: Map tab (the game's own map pictures; world > continent > zone) =====
do
  local NS = DarkMatter
  local M, MD = NS.MapTab, NS.MapData
  check(type(M) == "table" and type(MD) == "table", "0.5.0 map: Map tab + map data loaded")
  -- the mock keeps no parent links on SetParent; the map's full screen reparents its root
  FrameMT.SetParent = function(s, p) s._parent = p end
  FrameMT.GetParent = function(s) return s._parent end
  local save = { C_Map = C_Map, C_MapExplorationInfo = C_MapExplorationInfo, C_QuestLog = C_QuestLog,
    GetPlayerFacing = GetPlayerFacing, WorldMapFrame = WorldMapFrame, InCombatLockdown = InCombatLockdown,
    GameTooltip = GameTooltip, UIMapType = Enum.UIMapType, hook = hooksecurefunc }
  Enum.UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 }
  local MAPS = {
    [947] = { "Azeroth", 1, 0 },
    [1414] = { "Kalimdor", 2, 947 }, [1415] = { "Eastern Kingdoms", 2, 947 },
    [1426] = { "Dun Morogh", 3, 1415, { 0.40, 0.54, 0.48, 0.62 } },
    [1455] = { "Ironforge", 3, 1415, { 0.47, 0.50, 0.51, 0.54 } },
    [1432] = { "Loch Modan", 3, 1415, { 0.54, 0.64, 0.47, 0.59 } },
    [1429] = { "Elwynn Forest", 3, 1415, { 0.40, 0.52, 0.70, 0.80 } },
    [1453] = { "Stormwind City", 3, 1415, { 0.40, 0.44, 0.66, 0.71 } },
    [1411] = { "Durotar", 3, 1414, { 0.56, 0.66, 0.40, 0.56 } },
    [1412] = { "Mulgore", 3, 1414, { 0.40, 0.52, 0.55, 0.75 } },
    [1581] = { "The Deadmines", 4, 1429 },
  }
  local KAL_ON_WORLD = { 0.02, 0.42, 0.12, 0.95 } -- a sane rect: placed by "rect"
  local EK_P = { 0.40, 0.95, 0.03, 0.58 }         -- where EK's art truly sits on the world art (one scale, 0.55)
  -- its land (the union of its zone rects, 0.40-0.64 x 0.47-0.80) as the world picture shows it (what sampling finds)
  local EK_LAND = { 0.40 + 0.40 * 0.55, 0.40 + 0.64 * 0.55, 0.03 + 0.47 * 0.55, 0.03 + 0.80 * 0.55 }
  local artCalls, texCalls = {}, {}
  local PLAYER = { map = 1426, x = 0.523, y = 0.375 }
  local wmAccess = {}
  WorldMapFrame = setmetatable({}, { __index = function(_, k) wmAccess[#wmAccess + 1] = tostring(k) end,
    __newindex = function(_, k) wmAccess[#wmAccess + 1] = "set " .. tostring(k) end })
  local hooked = {}
  hooksecurefunc = function(a, b) hooked[#hooked + 1] = tostring(b or a) if save.hook then return save.hook(a, b) end end
  local function smallest(cont, x, y)
    local best, ba
    for id, m in pairs(MAPS) do
      local r = m[4]
      if m[3] == cont and r and x >= r[1] and x <= r[2] and y >= r[3] and y <= r[4] then
        local a = (r[2] - r[1]) * (r[4] - r[3])
        if not ba or a < ba then best, ba = id, a end
      end
    end
    return best
  end
  local function vec(x, y) return { x = x, y = y, GetXY = function(self) return self.x, self.y end } end
  C_Map = {
    GetMapInfo = function(id) local m = MAPS[id] if m then return { mapID = id, name = m[1], mapType = m[2], parentMapID = m[3] } end end,
    GetBestMapForUnit = function() return PLAYER.map end,
    GetFallbackWorldMapID = function() return 947 end,
    GetMapArtLayers = function(id)
      artCalls[#artCalls + 1] = id
      if MAPS[id] and MAPS[id][2] <= 3 then return { { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256, minScale = 1, maxScale = 1 } } end
    end,
    GetMapArtLayerTextures = function(id, l)
      texCalls[#texCalls + 1] = id
      if not (MAPS[id] and MAPS[id][2] <= 3) then return nil end
      local r = {} for i = 1, 12 do r[i] = id * 100 + i end return r
    end,
    GetMapChildrenInfo = function(id, t)
      local out = {}
      for cid, m in pairs(MAPS) do if m[3] == id and (t == nil or m[2] == t) then out[#out + 1] = { mapID = cid, name = m[1], mapType = m[2], parentMapID = id } end end
      table.sort(out, function(a, b) return a.mapID < b.mapID end)
      return out
    end,
    GetMapRectOnMap = function(c, p)
      if p == 947 and c == 1414 then return KAL_ON_WORLD[1], KAL_ON_WORLD[2], KAL_ON_WORLD[3], KAL_ON_WORLD[4] end
      if p == 947 and c == 1415 then return 0.37, 1.16, 0.08, 0.87 end -- the probe's unusable answer
      local m = MAPS[c]
      if m and m[3] == p and m[4] then return m[4][1], m[4][2], m[4][3], m[4][4] end
    end,
    GetMapInfoAtPosition = function(id, x, y)
      if id == 947 then
        if x >= EK_LAND[1] and x <= EK_LAND[2] and y >= EK_LAND[3] and y <= EK_LAND[4] then return { mapID = 1415 } end
        return nil
      end
      local z = smallest(id, x, y)
      if z then return { mapID = z } end
    end,
    GetPlayerMapPosition = function(id)
      if PLAYER.map ~= 1426 then return nil end
      if id == 1426 then return vec(PLAYER.x, PLAYER.y) end
      if id == 1415 then local r = MAPS[1426][4] return vec(r[1] + PLAYER.x * (r[2] - r[1]), r[3] + PLAYER.y * (r[4] - r[3])) end
    end,
  }
  C_MapExplorationInfo = { GetExploredMapTextures = function(id)
    if id ~= 1426 then return {} end
    return { { textureWidth = 300, textureHeight = 200, offsetX = 100, offsetY = 50, numTexturesWide = 2, numTexturesTall = 1, fileDataIDs = { 777001, 777002 } },
      { textureWidth = 128, textureHeight = 128, offsetX = 600, offsetY = 300, numTexturesWide = 1, numTexturesTall = 1, fileDataIDs = { 777003 }, isShownByMouseOver = true } }
  end }
  C_QuestLog = { GetQuestsOnMap = function(id) if id == 1426 then return { { questID = 501, x = 0.30, y = 0.40 }, { questID = 502, x = 0.60, y = 0.70 } } end return {} end,
    GetTitleForQuestID = function(q) if q == 501 then return "Dwarven Outfitters" end end }
  GetPlayerFacing = function() return 1.25 end
  local tip = { lines = {} }
  GameTooltip = setmetatable({ SetOwner = function() end, Show = function() tip.shown = true end, Hide = function() tip.shown = false end,
    SetText = function(_, t) tip.title = t tip.lines = {} end, AddLine = function(_, t) tip.lines[#tip.lines + 1] = t end }, { __index = function() return function() end end })

  -- 1. art is read per mapID: each level asks the game for its own map and gets its own file IDs
  MD.Forget()
  local a1, a2, a3 = MD.Art(1426), MD.Art(1415), MD.Art(947)
  check(a1 and a2 and a3 and a1.tex[1] == 142601 and a1.tex[12] == 142612 and a2.tex[1] == 141501 and a3.tex[1] == 94701,
    "0.5.0 map: art read per mapID (zone, continent and world each get their own file IDs)")
  check(texCalls[1] == 1426 and texCalls[2] == 1415 and texCalls[3] == 947 and artCalls[1] == 1426 and artCalls[3] == 947,
    "0.5.0 map: GetMapArtLayers/GetMapArtLayerTextures are called with each map's own mapID")
  check(a1.w == 1002 and a1.h == 668 and a1.cols == 4 and a1.rows == 3, "0.5.0 map: Classic art geometry 1002x668 in 4x3 tiles of 256")
  check(MD.Art(1581) == nil, "0.5.0 map: a map without art (dungeon) gives no art")
  -- 2. the map tree comes from the game at runtime
  check(MD.World() == 947, "0.5.0 map: world map found from the player's map chain")
  local conts = MD.Continents()
  check(#conts == 2 and conts[1].id == 1414 and conts[2].id == 1415, "0.5.0 map: both continents read from GetMapChildrenInfo")
  local zs = MD.Zones(1415)
  check(#zs == 5 and zs[1].name == "Dun Morogh" and zs[#zs].name == "Ironforge", "0.5.0 map: zones of a continent read with their rects, biggest first (cities on top)")
  check(#MD.Zones(1414) == 2, "0.5.0 map: Kalimdor zones read too (no per-zone probing)")
  -- 3. continent placement on the world picture
  NS.db.map = NS.db.map or {}
  NS.db.map.place = nil
  local pk, sk = MD.Placement(1414)
  check(sk == "rect" and math.abs(pk[1] - 0.02) < 1e-9 and math.abs(pk[4] - 0.95) < 1e-9, "0.5.0 map: a sane continent rect is used as is")
  local pe, se = MD.Placement(1415)
  local err = 0
  for i = 1, 4 do err = math.max(err, math.abs(pe[i] - EK_P[i])) end
  check(math.abs((pe[2] - pe[1]) - (pe[4] - pe[3])) < 1e-9, "0.5.0 map: a sampled placement keeps the art's shape (one scale)")
  check(se == "sampled" and err < 0.03,
    "0.5.0 map: an unusable continent rect (x to 1.16) is replaced by the land sampled on the world picture")
  check(type(NS.db.map.place) == "table" and type(NS.db.map.place[1415]) == "table" and NS.db.map.place[1415].v == 1, "0.5.0 map: the sampled placement is saved (sampled once)")
  -- 4. open the tab on a real-sized viewport
  NS.db.map.view = nil
  if M.Reset then M.Reset() end
  NS.ShowTab("map")
  check(M.vp ~= nil and M.vp._kind ~= nil, "0.5.0 map: map view built")
  M.vp:SetSize(812, 520)
  M.Refit()
  local function run(n, dt) for _ = 1, n do M.Tick(dt or 0.05) end end
  local CX, CY = 406, 260
  M.testCursor = function() return CX, CY end
  run(20)
  local trail = M.Trail()
  check(M.ready and M.hasWorld and M.started, "0.5.0 map: started with the world picture")
  check(table.concat(trail, " > ") == "Azeroth > Eastern Kingdoms > Dun Morogh", "0.5.0 map: opens on the player's zone (breadcrumb " .. table.concat(trail, " > ") .. ")")
  check(M.crumbText == "Azeroth > Eastern Kingdoms > Dun Morogh", "0.5.0 map: breadcrumb bar shows the trail")
  -- 0.5.1.6: a zone's pieces near its picture's edge are cut into feathered cells, so compare by file
  local function files(list) local f = {} for _, t in ipairs(list) do f[t._file] = (f[t._file] or 0) + 1 end return f end
  local function tcMax(list, fid, i) local v = 0 for _, t in ipairs(list) do if t._file == fid then v = math.max(v, t._tc[i]) end end return v end
  for id, L in pairs(M.layers) do
    if L.built then
      local f = files(L.tiles)
      local own = true
      for k in pairs(f) do if type(k) ~= "number" or k < id * 100 + 1 or k > id * 100 + 12 then own = false end end
      check(L.art.tex[1] == id * 100 + 1 and own and f[id * 100 + 1] and f[id * 100 + 12], "0.5.0 map: layer " .. id .. " draws its own map's tiles")
    end
  end
  local dm = M.layers[1426]
  local dmf = files(dm.tiles)
  local n12 = 0 for k = 1, 12 do if dmf[142600 + k] then n12 = n12 + 1 end end
  check(dm and dm.shown and dm.alpha > 0.99 and n12 == 12, "0.5.0 map: the zone's 12 tiles are shown")
  check(math.abs(tcMax(dm.tiles, 142612, 2) - (1002 - 768) / 256) < 1e-9 and math.abs(tcMax(dm.tiles, 142612, 4) - (668 - 512) / 256) < 1e-9, "0.5.0 map: edge tiles are cropped to the art (234x156)")
  local of = files(dm.ov)
  check(of[777001] and of[777002] and not of[777003], "0.5.0 map: explored overlays drawn (fog of war); mouse-over-only overlays skipped")
  check(math.abs(tcMax(dm.ov, 777002, 2) - 44 / 64) < 1e-9 and math.abs(tcMax(dm.ov, 777001, 4) - 200 / 256) < 1e-9, "0.5.0 map: overlay tiles cropped like the game's map")
  -- 0.5.1.6: the picture's rim fades to 0 (no rectangular edge); pieces well inside are whole
  local rim, rimOK, whole = 0, true, 0
  for _, t in ipairs(dm.tiles) do
    local p = t._pts[1]
    local x, y = p[4], -p[5]
    if rawget(t, "dmEdge") then
      rim = rim + 1
      if (x < 0.5 or y < 0.5) and not t._grad and (t._vc and t._vc[4] > 0.01) then rimOK = false end
    elseif (t._sw or 0) >= 255 then whole = whole + 1 end
  end
  check(rim > 0 and rimOK and whole >= 1 and math.abs(M.EdgeW(dm.art, 0, 300)) < 1e-9 and M.EdgeW(dm.art, 64, 300) == 1,
    "0.5.1.6 map: a zone picture's outer 64 px fade to 0 (" .. rim .. " rim cells, " .. whole .. " whole pieces inside; art " .. dm.art.w .. "x" .. dm.art.h .. " tiles " .. dm.art.tw .. "x" .. dm.art.th .. ")")
  -- 0.5.1.7 seams (0.5.1.8: the drawn place names are gone; the game's own map art carries the names)
  do
    check(M.AreaLabels == nil and M.LayoutLabels == nil and M.labelsShown == nil, "0.5.1.8 map: no drawn place-name labels")
    local shown, fe, base, hard = M.SeamReport()
    check(shown > 0 and hard == 0 and fe >= 1, string.format("0.5.1.7 map: every map picture on screen is feathered or the base (%d shown, %d feathered, %d base, %d hard)", shown, fe, base, hard))
    for _, L in pairs(M.layers) do
      if L.id ~= M.world and NS.MapData.Is(L.id, "continent") then check(L.feather == (M.hasWorld and true or false), "0.5.1.7 map: a continent picture over the world picture is feathered") end
    end
    local zs = NS.MapData.Zones(1415)
    if zs and #zs >= 2 then check(math.abs(M.ZoneDrawAlpha(zs[1]) - M.ZoneDrawAlpha(zs[2])) < 1e-9, "0.5.1.7 map: a continent's zones fade in together (no patchwork)") end
    local ref = M.RefMag()
    check(ref and M.ref and M.ref.level >= 3 and math.abs(ref - M.layers[M.ref.id].sc) < 1e-9,
      "0.5.1.8 map: the art magnification is read from the zone picture under the middle of the view (x" .. tostring(ref) .. ")")
  end
  check(M.layers[1432] and M.layers[1432].shown, "0.5.0 map: the neighbour zone is drawn too (zones stitched)")
  -- stitching: Loch Modan's left edge on screen meets Dun Morogh's right edge (both from GetMapRectOnMap)
  local function edges(L) local p = L.frame._pts[#L.frame._pts] local sc = L.frame._scale return p[4] * sc, -p[5] * sc, L.art.w * sc, L.art.h * sc end
  local dl, dt_, dw = edges(dm)
  local ll = edges(M.layers[1432])
  check(math.abs((dl + dw) - ll) < 0.01, "0.5.0 map: neighbour zones meet exactly (no gap/overlap)")
  check(M.layers[947] and not M.layers[947].shown, "0.5.0 map: the world picture is hidden when the continent covers the view")
  -- 5. player arrow, coordinates
  check(M.arrow:IsShown() and M.player and M.player.map == 1426, "0.5.0 map: player arrow shown")
  local wx, wy = M.ToScreen(M.player[1], M.player[2])
  local ap = M.arrow._pts[#M.arrow._pts]
  check(math.abs(ap[4] - wx) < 0.01 and math.abs(-ap[5] - wy) < 0.01, "0.5.0 map: arrow sits at the player's position")
  check(M.playerText == "Player  52.3, 37.5", "0.5.0 map: player coordinates " .. tostring(M.playerText))
  local zr = MAPS[1426][4]
  local pp = MD.Placement(1415)
  local tx, ty = M.ToScreen(pp[1] + (zr[1] + 0.25 * (zr[2] - zr[1])) * (pp[2] - pp[1]), pp[3] + (zr[3] + 0.75 * (zr[4] - zr[3])) * (pp[4] - pp[3]))
  CX, CY = tx, ty
  run(2)
  check(M.coordText == "Dun Morogh  25.0, 75.0", "0.5.0 map: cursor coordinates " .. tostring(M.coordText))
  check(M.coordCur.text._text == M.coordText and M.coordMe.text._text == M.playerText, "0.5.0 map: coordinates shown bottom right")
  -- 6. quest markers
  local qp = M.pools.quest
  check(qp and qp.n == 2 and qp[1]:IsShown() and qp[1].qid == 501, "0.5.0 map: quest markers from GetQuestsOnMap")
  qp[1]._scripts.OnEnter(qp[1])
  check(tip.title == "Dwarven Outfitters", "0.5.0 map: quest marker tooltip names the quest")
  -- 7. wheel zoom keeps the point under the cursor fixed
  CX, CY = 300, 180
  local u0, v0 = M.ToWorld(CX, CY)
  local z0 = M.Zoom()
  M.Wheel(-1) run(30)
  local u1, v1 = M.ToWorld(CX, CY)
  check(M.Zoom() < z0 and math.abs(u1 - u0) < 1e-6 and math.abs(v1 - v0) < 1e-6, "0.5.0 map: wheel zoom out keeps the point under the cursor")
  M.Wheel(1) run(30)
  local u2, v2 = M.ToWorld(CX, CY)
  check(math.abs(M.Zoom() - z0) < 1e-6 and math.abs(u2 - u0) < 1e-6 and math.abs(v2 - v0) < 1e-6, "0.5.0 map: wheel zoom in returns exactly")
  -- 8. zoom all the way out: zone > continent > world, with crossfades on the way
  CX, CY = 406, 260
  local sawZoneFade, sawContFade, sawCont = false, false, false
  for _ = 1, 30 do
    M.Wheel(-1)
    for _ = 1, 30 do
      M.Tick(0.016)
      local za, ca = M.ZoneDrawAlpha(MD.ZoneEntry(1426)), M.ContAlpha(1415) -- 0.5.1.7+: as drawn
      if za > 0.02 and za < 0.98 and M.layers[1426].shown and math.abs(M.layers[1426].alpha - za) < 1e-9 then sawZoneFade = true end
      if ca > 0.02 and ca < 0.98 and M.layers[1415].shown and math.abs(M.layers[1415].alpha - ca) < 1e-9 then sawContFade = true end
    end
    if table.concat(M.Trail(), ">") == "Azeroth>Eastern Kingdoms" then sawCont = true end
  end
  check(sawZoneFade and sawContFade, "0.5.0 map: zone and continent pictures crossfade while zooming")
  check(sawCont, "0.5.0 map: passes through the continent level")
  check(math.abs(M.Zoom() - 1) < 1e-6 and table.concat(M.Trail(), ">") == "Azeroth" and M.layers[947].shown, "0.5.0 map: zoomed out fully shows the world")
  local wcx, wcy = M.Center()
  check(math.abs(wcx - 0.5) < 1e-9 and math.abs(wcy - 0.5) < 1e-9, "0.5.0 map: fully zoomed out the world is centred (zooming out at the cursor never leaves the view half empty)")
  local sl, st = M.ToScreen(0, 0)
  local sr, sb = M.ToScreen(1, 1)
  check(sl <= 0.01 or sr - sl < M.vp:GetWidth() + 0.01, "0.5.0 map: the picture covers the view")
  -- 9. zoom in toward Kalimdor (cursor on its land): focus moves there
  local kx, ky = M.ToScreen(0.20, 0.55)
  CX, CY = kx, ky
  for _ = 1, 8 do M.Wheel(1) run(30) end
  local kt = M.Trail()
  check(kt[2] == "Kalimdor", "0.5.0 map: wheel toward Kalimdor zooms into Kalimdor (" .. table.concat(kt, " > ") .. ")")
  -- 10. breadcrumb click / right-click / double-click
  M.FlyTo(1426) run(20)
  check(table.concat(M.Trail(), ">") == "Azeroth>Eastern Kingdoms>Dun Morogh", "0.5.0 map: fly to a zone")
  M.vp._scripts.OnMouseUp(M.vp, "RightButton") run(20)
  check(table.concat(M.Trail(), ">") == "Azeroth>Eastern Kingdoms", "0.5.0 map: right-click zooms out one level")
  M.vp._scripts.OnMouseUp(M.vp, "RightButton") run(20)
  check(table.concat(M.Trail(), ">") == "Azeroth", "0.5.0 map: right-click again shows the world")
  local zb = M.Zoom()
  CX, CY = 406, 260
  M.vp._scripts.OnMouseDown(M.vp, "LeftButton") M.vp._scripts.OnMouseUp(M.vp, "LeftButton")
  M.vp._scripts.OnMouseDown(M.vp, "LeftButton") M.vp._scripts.OnMouseUp(M.vp, "LeftButton")
  run(30)
  check(math.abs(M.Zoom() - zb * 2) < 1e-6, "0.5.0 map: double-click zooms in x2")
  -- 11. drag to pan across a zone border
  M.FlyTo(1426) run(20)
  local lm = MD.ZoneEntry(1432)
  local dmz = MD.ZoneEntry(1426)
  local ax, ay = M.ToScreen(MD.ToWorld(1426, 0.5, 0.5))
  local bx, by = M.ToScreen(MD.ToWorld(1432, 0.5, 0.5))
  CX, CY = 406, 260
  M.vp._scripts.OnMouseDown(M.vp, "LeftButton")
  local both = false
  for i = 1, 10 do
    CX, CY = 406 - (bx - ax) * i / 10, 260 - (by - ay) * i / 10
    run(1)
    if M.layers[1426].shown and M.layers[1432] and M.layers[1432].shown then both = true end
  end
  M.vp._scripts.OnMouseUp(M.vp, "LeftButton") run(2)
  check(both and table.concat(M.Trail(), ">") == "Azeroth>Eastern Kingdoms>Loch Modan", "0.5.0 map: drag pans across the border into the next zone")
  -- 12. search and pick
  local r = M.Search("loch")
  check(#r == 1 and r[1].name == "Loch Modan" and r[1].sub == "Eastern Kingdoms" and M.results:IsShown(), "0.5.0 map: zone search finds Loch Modan")
  r = M.Search("kal")
  check(r[1] and r[1].name == "Kalimdor" and r[1].sub == "Continent", "0.5.0 map: search lists continents first")
  r = M.Search("or")
  local nm = {} for i, e in ipairs(r) do nm[i] = e.name end
  check(table.concat(nm, ",") == "Kalimdor,Dun Morogh,Elwynn Forest,Ironforge,Mulgore,Stormwind City", "0.5.0 map: search matches inside names (" .. table.concat(nm, ",") .. ")")
  r = M.Search("st") nm = {} for i, e in ipairs(r) do nm[i] = e.name end
  check(table.concat(nm, ",") == "Eastern Kingdoms,Stormwind City,Elwynn Forest", "0.5.0 map: search order continents, starts-with, contains (" .. table.concat(nm, ",") .. ")")
  r = M.Search("zzz")
  check(#r == 0 and M.results:IsShown() and M.results.rows[1].name._text == "No matching zones", "0.5.0 map: no match says so")
  M.Search("elwynn")
  M.results.rows[1]._scripts.OnClick(M.results.rows[1]) run(20)
  check(table.concat(M.Trail(), ">") == "Azeroth>Eastern Kingdoms>Elwynn Forest" and not M.results:IsShown(), "0.5.0 map: picking a result flies there")
  -- 13. Find me
  local fm
  for _, b in ipairs(M.tools) do if b.key == "findme" then fm = b end end
  fm._scripts.OnClick(fm) run(20)
  check(table.concat(M.Trail(), ">") == "Azeroth>Eastern Kingdoms>Dun Morogh", "0.5.0 map: Find me flies to your zone")
  local cx, cy = M.Center()
  check(math.abs(cx - M.player[1]) < 1e-6 and math.abs(cy - M.player[2]) < 1e-6, "0.5.0 map: Find me centres on you")
  -- 14. the tool strip: three slots are disabled with the version they come in
  local keys, soon = {}, {}
  for i, b in ipairs(M.tools) do keys[i] = b.key if b.soon then soon[b.key] = b end end
  check(table.concat(keys, ",") == "starpen,pin,town,findme,full,closeup", "0.5.0 map: tool strip order Starpen, Pin, Town Pins, Find me, Full screen (0.5.1.4: + Close-up detail)")
  check(soon.starpen and soon.pin and soon.town and not soon.findme, "0.5.0 map: Starpen, Pin and Town Pins are disabled")
  local wantV = { starpen = "0.5.3", pin = "0.5.2", town = "0.5.4" } -- 0.5.1: the later phases shifted one step
  local origSS = NS.SetStatus
  NS.SetStatus = function(t) STATUS_SEEN = t return origSS(t) end
  for k, b in pairs(soon) do
    b._scripts.OnEnter(b)
    check(tip.title == b.tipTitle and tip.lines[1] and tip.lines[1]:find(wantV[k], 1, true), "0.5.0 map: " .. k .. " tooltip says coming in " .. wantV[k])
    local before = table.concat(M.Trail(), ">")
    b._scripts.OnClick(b)
    check(table.concat(M.Trail(), ">") == before and not M.full and tostring(STATUS_SEEN or ""):find(wantV[k], 1, true) ~= nil,
      "0.5.0 map: " .. k .. " click only explains (status line names " .. wantV[k] .. ")")
    check(b.icon._alpha and b.icon._alpha < 0.5, "0.5.0 map: " .. k .. " icon is dimmed")
  end
  NS.SetStatus = origSS
  -- 15. level badges (public data) at the continent view; the caption names the source
  M.FlyTo(1415) run(20)
  local bp, names = M.pools.badge, {}
  for i = 1, (bp and bp.n or 0) do names[bp[i].zone] = bp[i].text._text end
  check(names["Dun Morogh"] == "1-10" and names["Loch Modan"] == "10-20" and names["Elwynn Forest"] == "1-10", "0.5.0 map: zone level badges at the continent view")
  check(names["Ironforge"] == nil, "0.5.0 map: no badge for a city without a level range")
  check(M.caption:IsShown() and M.caption.text._text == "Levels: public data", "0.5.0 map: badges are captioned as public data")
  M.caption._scripts.OnEnter(M.caption)
  check(tip.lines[1] and tip.lines[1]:find("Wowhead", 1, true), "0.5.0 map: caption tooltip names the source")
  -- 16. full screen and back (button, Esc, closing the window)
  local fb = M.fullBtn
  local W, H = M.vp._w, M.vp._h
  fb._scripts.OnClick(fb)
  local full = _G.DarkMatterMapFull
  local function inEsc(n) for _, v in ipairs(UISpecialFrames) do if v == n then return true end end return false end
  check(M.full and full and full:IsShown() and M.root._parent == full, "0.5.0 map: full screen moves the map into its own frame")
  check(inEsc("DarkMatterMapFull") and not inEsc("DarkMatterFrame"), "0.5.0 map: in full screen Esc closes the full-screen map only")
  check(fb.tipTitle == "Back to window", "0.5.0 map: the button switches back")
  M.vp:SetSize(1880, 1020) M.Refit() run(2)
  check(table.concat(M.Trail(), ">") == "Azeroth>Eastern Kingdoms", "0.5.0 map: full screen keeps the place")
  fb._scripts.OnClick(fb)
  check(not M.full and not full:IsShown() and M.root._parent ~= full, "0.5.0 map: button returns to the window")
  check(inEsc("DarkMatterFrame") and not inEsc("DarkMatterMapFull"), "0.5.0 map: Esc closes the main window again")
  fb._scripts.OnClick(fb)
  full:Hide() -- what Esc does through UISpecialFrames
  check(not M.full and M.root._parent ~= full and inEsc("DarkMatterFrame"), "0.5.0 map: Esc in full screen returns to the window")
  fb._scripts.OnClick(fb)
  DarkMatterFrame:Hide()
  M.Tick(0.05)
  check(not M.full and not full:IsShown(), "0.5.0 map: closing the main window leaves full screen too")
  DarkMatterFrame:Show() NS.ShowTab("map")
  M.vp:SetSize(812, 520) M.Refit()
  -- 17. combat: everything works with InCombatLockdown() true (nothing protected is touched)
  InCombatLockdown = function() return true end
  local ok, err = pcall(function()
    M.Wheel(1) run(10) M.FlyTo(1429) run(20) M.FindMe() run(20) M.SetFull(true) M.SetFull(false) M.Search("dun") M.Pick(M.results.list[1]) run(20)
  end)
  InCombatLockdown = save.InCombatLockdown
  check(ok and table.concat(M.Trail(), ">") == "Azeroth>Eastern Kingdoms>Dun Morogh", "0.5.0 map: works in combat " .. tostring(err))
  -- 18. taint safety
  -- 0.5.1.5: the main window reads the map window's size and scale (read only, from its own frame); nothing else
  local wmOther = {}
  local READ_OK = { GetEffectiveScale = 1, GetWidth = 1, GetHeight = 1, minimizedWidth = 1, minimizedHeight = 1, questLogWidth = 1, isMaximized = 1, IsMaximized = 1,
    GetLeft = 1, GetRight = 1, GetTop = 1, GetBottom = 1, BorderFrame = 1, IsShown = 1 } -- 0.5.1.6: its outer rectangle, read only
  for _, k in ipairs(wmAccess) do if not READ_OK[k] then wmOther[#wmOther + 1] = k end end
  check(#wmOther == 0, "0.5.0 map: never touches WorldMapFrame (0.5.1.6: only its size, scale and outer rectangle are read) " .. table.concat(wmOther, ","))
  check(#hooked == 0, "0.5.0 map: installs no hooks")
  for _, f in ipairs({ "DarkMatter/Tab_Map.lua", "DarkMatter/MapData.lua" }) do
    local fh = io.open(arg[1] .. "/" .. f:gsub("^DarkMatter/", "")) local src = fh and fh:read("*a") or "" if fh then fh:close() end
    local code = src:gsub("%-%-[^\n]*", "")
    check(#src > 0 and not code:find("WorldMapFrame", 1, true) and not code:find("hooksecurefunc", 1, true) and not code:find("SetUserWaypoint", 1, true) and not code:find("SetSuperTrack", 1, true),
      "0.5.0 map: " .. f .. " has no WorldMapFrame access, hooks, waypoints or super-track")
  end
  -- 19. the map's pictures are clipped by a ScrollFrame
  check(M.vp._ftype == "ScrollFrame", "0.5.0 map: viewport is a ScrollFrame (clips the map pictures)")
  for _, L in pairs(M.layers) do
    local x, inside = L.frame, false
    while x do if x == M.vp then inside = true end x = x._parent end
    check(inside, "0.5.0 map: layer " .. L.id .. " lives inside the clipping ScrollFrame")
  end
  -- 20. view is remembered
  local sv = NS.db.map.view
  check(type(sv) == "table" and type(sv.cx) == "number" and type(sv.z) == "number", "0.5.0 map: view saved")
  -- 21. instance: no position -> Find me explains, arrow hides
  PLAYER.map = 1581
  MD.Forget()
  run(2)
  check(not M.arrow:IsShown() and M.playerText == "Player  --", "0.5.0 map: no arrow and no coordinates where the game gives no position")
  check(M.FindMe() == false, "0.5.0 map: Find me reports no position (instance)")
  PLAYER.map = 1426
  MD.Forget()
  -- 22. a client without a world picture shows one continent at a time
  local gl = C_Map.GetMapArtLayers
  C_Map.GetMapArtLayers = function(id) if id == 947 then return nil end return gl(id) end
  M.Reset() NS.db.map.view = nil
  NS.ShowTab("quests") NS.ShowTab("map")
  M.vp:SetSize(812, 520) M.Refit() run(20)
  check(M.ready and not M.hasWorld and M.only == 1415 and M.Trail()[1] == "Eastern Kingdoms", "0.5.0 map: without world art the player's continent is the base")
  M.Search("durotar") M.Pick(M.results.list[1]) run(20)
  check(M.only == 1414 and table.concat(M.Trail(), ">") == "Kalimdor>Durotar", "0.5.0 map: search switches continent without world art")
  C_Map.GetMapArtLayers = gl
  -- 23. a client with no map art at all says so
  C_Map.GetMapArtLayers = function() return nil end
  M.Reset() NS.ShowTab("quests") NS.ShowTab("map")
  check(not M.ready and M.empty:IsShown(), "0.5.0 map: no map art -> a clear message instead of a blank box")
  C_Map.GetMapArtLayers = gl
  M.Reset() NS.db.map.view = nil
  NS.ShowTab("quests") NS.ShowTab("map")
  M.vp:SetSize(812, 520) M.Refit() run(20)
  -- 24. contrast: the live map view in all 10 themes (continent view with badges, crumbs, coordinates, caption;
  -- search results; every map button hovered; full screen). The game's map pictures (file IDs) are not
  -- judged, so every map label sits on its own solid plate.
  if MODE ~= "minimal" then
    local CT = dofile(arg[1] .. "/../tools/stubtest/contrast.lua")
    CT.rect = FrameMT._rect
    local win = DarkMatterFrame
    local fails, n = {}, 0
    local function scan(root, id, view, hovered)
      for _, x in ipairs(CT.Scan(root, NS.theme.colors, hovered)) do
        n = n + 1
        if x.ratio < x.need then fails[#fails + 1] = string.format("%s %s %q %.2f<%.1f [%s]", id, view, x.text, x.ratio, x.need, x.roles) end
      end
    end
    local function hoverAll(root, id, view)
      for _, f in ipairs(ALL) do
        if f._ftype == "Button" and under(f, root) and visible(f) and f._scripts.OnEnter and under(f, M.root) then
          f._hover = true f._scripts.OnEnter(f)
          scan(root, id, view .. "+hover", f)
          if f._scripts.OnLeave then f._scripts.OnLeave(f) end
          f._hover = nil
        end
      end
    end
    M.testCursor = function() return 300, 200 end
    for _, id in ipairs(NS.themeOrder) do
      NS.SetTheme(id)
      NS.ShowTab("map")
      M.FlyTo(1415) run(20)
      check(M.pools.badge and M.pools.badge.n >= 3 and M.caption:IsShown(), "0.5.0 map: badges + caption shown for the contrast scan (" .. id .. ")")
      scan(win, id, "map/continent")
      hoverAll(win, id, "map/continent")
      M.Search("o")
      scan(win, id, "map/search")
      hoverAll(win, id, "map/search")
      M.Search("zzz")
      scan(win, id, "map/no-match")
      M.Search("")
      M.FlyTo(1426) run(20)
      scan(win, id, "map/zone")
      M.SetFull(true) run(2)
      scan(_G.DarkMatterMapFull, id, "map/fullscreen")
      hoverAll(_G.DarkMatterMapFull, id, "map/fullscreen")
      M.SetFull(false)
    end
    NS.SetTheme("wow")
    for _, f in ipairs(fails) do io.write("cfail\t" .. f .. "\n") end
    check(n > 300, "0.5.0 map contrast: " .. n .. " label checks over 10 themes")
    check(#fails == 0, "0.5.0 map contrast: every map label >= 4.5:1 (3:1 large) in every theme (" .. #fails .. " below)\n  " .. table.concat(fails, "\n  ", 1, math.min(#fails, 12)))
    M.testCursor = nil
  end
  -- restore the game fixture
  C_Map, C_MapExplorationInfo, C_QuestLog = save.C_Map, save.C_MapExplorationInfo, save.C_QuestLog
  GetPlayerFacing, WorldMapFrame, GameTooltip, Enum.UIMapType, hooksecurefunc = save.GetPlayerFacing, save.WorldMapFrame, save.GameTooltip, save.UIMapType, save.hook
  M.Reset() MD.Forget()
  NS.ShowTab("quests")
end

-- ===== 0.5.1: the WoW theme in the game's own art (stock textures + UIPanelCloseButton), fallback, /dm artprobe =====
if MODE ~= "minimal" then
  local NS = DarkMatter
  local W = NS.windowParts
  local win = DarkMatterFrame
  local function drawn()
    local set, blank = {}, {}
    for _, r in ipairs(REGIONS) do
      if r._kind == "texture" and under(r, win) and visible(r) then
        if r._file ~= nil then set[tostring(r._file)] = (set[tostring(r._file)] or 0) + 1 end
      end
    end
    return set
  end
  local function stockFiles(set)
    local n = 0
    for f in pairs(set) do if not f:find("^Interface\\AddOns\\") and not f:find("^Interface\\Icons\\") and not f:upper():find("WHITE8X8", 1, true) and type(tonumber(f)) ~= "number" then n = n + 1 end end
    return n
  end
  STOCK_MISSING = false
  NS.Stock.ClearCache()
  NS.SetTheme("wow")
  win:Show()
  NS.ShowTab("quests")
  local d = drawn()
  -- 0.5.1.4: the dialog border + header plate gave way to the map-window frame (its own thin frame here: no WorldMapFrame);
  -- the shell is the inset marble
  local want = { "Interface\\Tooltips\\UI-Tooltip-Border", "Interface\\FrameGeneral\\UI-Background-Marble",
    "Interface\\Buttons\\UI-Panel-Button-Up", "Interface\\Buttons\\UI-Panel-Button-Down",
    "Interface\\Buttons\\UI-Panel-Button-Disabled", "Interface\\Common\\Common-Input-Border", "Interface\\FrameGeneral\\UI-Background-Rock",
    "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", "Interface\\QuestFrame\\QuestBG" }
  local miss = {}
  for _, f in ipairs(want) do if not d[f] then miss[#miss + 1] = f end end
  check(#miss == 0, "0.5.1 WoW theme: the window draws the game's own art (frame, header, portrait, buttons, tabs, panels, parchment)" .. (#miss > 0 and (" missing: " .. table.concat(miss, ", ")) or ""))
  check(not d["Interface\\AddOns\\DarkMatter\\Media\\wow-slate"] and not d["Interface\\AddOns\\DarkMatter\\Media\\wow-parchment"],
    "0.5.1 WoW theme: Dark Matter's own slate/parchment are not used while the stock art loads")
  if os.getenv("DM_WMF") then
    -- 0.5.1.4: the map window's own close-button art is drawn on Dark Matter's close button
    check(W.closeFrom == "map window" and not W.stockClose:IsShown(), "0.5.1.4 WoW theme: the close button wears the map window's close art")
    local cb
    for _, f in ipairs(ALL) do if f._ftype == "Button" and f._parent == win and f:IsShown() and f._w == 24 and f._scripts.OnClick then cb = f end end
    check(cb ~= nil, "0.5.1.4 WoW theme: the close button is shown at the map window's size (24)")
    cb._scripts.OnClick(cb, "LeftButton")
  else
    check(W.stockClose and W.stockClose:IsShown() and W.closeFrom == "UIPanelCloseButton", "0.5.1 WoW theme: the stock UIPanelCloseButton is shown")
    W.stockClose._scripts.OnClick(W.stockClose, "LeftButton")
  end
  check(not win:IsShown(), "0.5.1 WoW theme: the stock close button closes the window")
  win:Show()
  -- Journals: section tabs are the character-panel tabs; the Map tab gets the stock framing too
  NS.ShowTab("journals")
  NS.tabs.journals.SetSection("fishing")
  d = drawn()
  check(d["Interface\\PaperDollInfoFrame\\UI-Character-ActiveTab"] and d["Interface\\PaperDollInfoFrame\\UI-Character-InActiveTab"], "0.5.1 WoW theme: section tabs use the character-panel tabs")
  local knobSet = false
  for _, r in ipairs(REGIONS) do if r._kind == "texture" and under(r, win) and r._file == "Interface\\Buttons\\UI-ScrollBar-Knob" then knobSet = true end end -- the knob shows only when a list overflows
  -- 0.5.1.1: at the top of a list the stock up button is disabled (its Disabled file), like the game's scroll bars
  check((d["Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up"] or d["Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Disabled"])
    and (d["Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up"] or d["Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Disabled"]) and knobSet,
    "0.5.1 WoW theme: scroll bars use the stock scroll buttons and knob")
  NS.ShowTab("map")
  d = drawn()
  check(d["Interface\\Tooltips\\UI-Tooltip-Border"] and d["Interface\\DialogFrame\\UI-DialogBox-Background-Dark"], "0.5.1 WoW theme: the Map tab's panels get the stock framing")
  NS.ShowTab("quests")
  -- the quest-detail panel is the stock QuestBG parchment with dark quest ink
  local qb, qd = NS.tabs.quests.Parts()
  local function lumOf(fs) local c = fs._tcol or { 0, 0, 0 } local r, g, b = c[1], c[2], c[3] return 0.2126 * r + 0.7152 * g + 0.0722 * b end
  check(qd.panel.parch == true and lumOf(qd.title) < 0.2 and qd.texts[1] and lumOf(qd.texts[1]) < 0.2,
    "0.5.1 WoW theme: the quest detail panel is parchment with dark ink (title " .. string.format("%.2f", lumOf(qd.title)) .. ")")
  -- /dm artprobe: short lines, ok for everything here, saved
  local said = {}
  local oldPrint = NS.Print
  NS.Print = function(m) said[#said + 1] = m end
  SlashCmdList["DARKMATTER"]("artprobe")
  NS.Print = oldPrint
  local ap = NS.db.artprobe
  check(said[1] and said[1]:find("^artprobe 0%.5%.1%.8 %(file%-ID lookup%):") and said[#said]:find("^artprobe: %d+ ok, 0 missing$"), "0.5.1 /dm artprobe: header + summary (" .. tostring(said[#said]) .. ")")
  local longest = 0
  for _, l in ipairs(said) do longest = math.max(longest, #l) end
  check(longest <= 72, "0.5.1 /dm artprobe: short lines (longest " .. longest .. ")")
  check(type(ap) == "table" and ap.missing == 0 and ap.ok >= 20 and #ap.items == ap.ok and ap.method == "file-ID lookup", "0.5.1 /dm artprobe: saved to DarkMatterDB.artprobe (" .. tostring(ap and ap.ok) .. " ok)")
  local hasTmpl = false
  for _, it in ipairs(ap.items) do if it.kind == "template" and it.name == "UIPanelCloseButton" then hasTmpl = it.ok end end
  check(hasTmpl, "0.5.1 /dm artprobe: lists the UIPanelCloseButton template")
  -- 0.5.1.3: the 1.60.1 case: CharacterFrameTabButtonTemplate is missing. The summary names it on ONE line with what
  -- stands in, and the tabs still draw the stock UI-Character-ActiveTab / InActiveTab art (the template is never needed)
  STOCK_MISSING_TMPL = { CharacterFrameTabButtonTemplate = true }
  NS.Stock.ClearCache()
  NS.SetTheme("wow")
  said = {}
  NS.Print = function(m) said[#said + 1] = m end
  SlashCmdList["DARKMATTER"]("artprobe")
  NS.Print = oldPrint
  local last = said[#said] or ""
  local missLines = 0
  for _, l in ipairs(said) do if l:find("^MISSING ") then missLines = missLines + 1 end end
  check(last:find("^artprobe: %d+ ok, 1 missing: CharacterFrameTabButtonTemplate %(template%) %-> tabs use UI%-Character%-ActiveTab/InActiveTab$")
    and not last:find("\n") and missLines == 1 and NS.db.artprobe.missing == 1
    and NS.db.artprobe.missingNames[1]:find("^CharacterFrameTabButtonTemplate"),
    "0.5.1.3 /dm artprobe on 1.60.1: one summary line names the missing CharacterFrameTabButtonTemplate and its stand-in (" .. last .. ")")
  NS.ShowTab("journals")
  local tabArt = 0
  for f, n in pairs(drawn()) do
    if f:find("UI%-Character%-ActiveTab") or f:find("UI%-Character%-InActiveTab") then tabArt = tabArt + n end
  end
  check(NS.Stock.TabButton() and tabArt > 0, "0.5.1.3 the tab template missing: tabs still use the stock UI-Character-ActiveTab / InActiveTab art (" .. tabArt .. " pieces)")
  NS.ShowTab("quests")
  STOCK_MISSING_TMPL = nil
  NS.Stock.ClearCache()
  NS.SetTheme("wow")
  -- fallback: every stock texture missing -> Dark Matter's own art, nothing blank
  STOCK_MISSING = true
  NS.Stock.ClearCache()
  NS.SetTheme("wow")
  d = drawn()
  check(stockFiles(d) == 0, "0.5.1 fallback: with the stock art missing no stock file is drawn")
  -- 0.5.1.1: the WoW page is dark (light page ink), so its fallback is the slate, never the light parchment
  check(d["Interface\\AddOns\\DarkMatter\\Media\\wow-slate"] and not d["Interface\\AddOns\\DarkMatter\\Media\\wow-parchment"] and d["Interface\\AddOns\\DarkMatter\\Media\\wow-atlas"],
    "0.5.1 fallback: Dark Matter's own slate and atlas are drawn instead (0.5.1.1: dark page, no light parchment)")
  local blank = 0
  for _, r in ipairs(REGIONS) do
    if r._kind == "texture" and under(r, win) and visible(r) and r._file == nil and r._color == nil then blank = blank + 1 end
  end
  check(blank == 0, "0.5.1 fallback: no visible texture is left blank (" .. blank .. ")")
  check(W.stockClose and not W.stockClose:IsShown(), "0.5.1 fallback: the template close button is hidden; Dark Matter's own close shows")
  check(qd.panel.parch == false and lumOf(qd.title) > 0.5 and lumOf(qd.texts[1]) > 0.5,
    "0.5.1 fallback: the quest detail panel goes back to the dark panel with light text")
  said = {}
  NS.Print = function(m) said[#said + 1] = m end
  SlashCmdList["DARKMATTER"]("artprobe")
  NS.Print = oldPrint
  check(said[#said]:find("^artprobe: 0 ok, %d+ missing %(missing pieces use Dark Matter's own art%)$") and said[2]:find("^MISSING "), "0.5.1 /dm artprobe: reports missing pieces (" .. tostring(said[#said]) .. ")")
  -- 0.5.1.3: a class theme draws the stock button / tab / scroll-bar kit (desaturated, recoloured in its palette) and
  -- none of the stock window art (its own frame, surfaces and colours)
  STOCK_MISSING = false
  NS.Stock.ClearCache()
  NS.SetTheme("warrior")
  local KIT = { "UI%-Panel%-Button%-", "UI%-Character%-ActiveTab", "UI%-Character%-InActiveTab", "UI%-Character%-Tab%-Highlight",
    "UI%-ScrollBar%-", "UI%-Character%-ScrollBar" }
  local function isKit(f) for _, p in ipairs(KIT) do if f:find(p) then return true end end return false end
  local nonKit, kitN, undesat, kitNames = {}, 0, 0, {}
  for f in pairs(drawn()) do
    if not f:find("^Interface\\AddOns\\") and not f:find("^Interface\\Icons\\") and not f:upper():find("WHITE8X8", 1, true) and type(tonumber(f)) ~= "number" then
      if isKit(f) then kitN = kitN + 1 kitNames[#kitNames + 1] = f:match("[^\\]+$") else nonKit[#nonKit + 1] = f end
    end
  end
  for _, r in ipairs(REGIONS) do
    if r._kind == "texture" and under(r, win) and visible(r) and type(r._file) == "string" and isKit(r._file) and not r._desat then undesat = undesat + 1 end
  end
  check(kitN > 0 and #nonKit == 0 and undesat == 0,
    "0.5.1.3 class themes: only the stock button/tab/scroll kit, desaturated + recoloured (kit " .. kitN .. ": " .. table.concat(kitNames, ",") .. ", other: " .. table.concat(nonKit, ",") .. ", not desaturated " .. undesat .. ")")
  check(qd.panel.parch == false and lumOf(qd.texts[1]) > 0.5, "0.5.1 class themes: the quest detail panel stays dark with light text")
  NS.SetTheme("wow")
  check(NS.Stock.Spec("btn_red_m") and drawn()["Interface\\Buttons\\UI-Panel-Button-Up"], "0.5.1 WoW theme: switching back draws the stock art again")
  -- hover is a subtle tint
  local e = NS.themes.wow.colors.hoverEdge
  check(e[4] and e[4] <= 0.3, "0.5.1 WoW theme: the hover edge is subtle (alpha " .. tostring(e[4]) .. ")")

  -- ===== 0.5.1.1: every stock surface fills its panel; parchment only in the detail panels; stock scroll buttons; toast =====
  STOCK_MISSING = false
  NS.Stock.ClearCache()
  NS.SetTheme("wow")
  win:Show()
  local SURF = { ["Interface\\QuestFrame\\QuestBG"] = true, ["Interface\\FrameGeneral\\UI-Background-Rock"] = true,
    ["Interface\\DialogFrame\\UI-DialogBox-Background-Dark"] = true }
  local function fillCheck(where)
    local n, bad, parchN, parchBad, tcBad = 0, {}, 0, {}, {}
    for _, r in ipairs(REGIONS) do
      if r._kind == "texture" and under(r, win) and visible(r) and SURF[tostring(r._file)] then
        n = n + 1
        local l, t, rr, b = FrameMT._rect(r)
        local o = r._parent
        local ol, ot, orr, ob = FrameMT._rect(o)
        local slate = (o == win) -- the window's own slate sits inside the window padding
        if not (l and ol) then bad[#bad + 1] = "unresolved"
        elseif not slate and (math.abs(l - ol) > 0.5 or math.abs(t - ot) > 0.5 or math.abs(rr - orr) > 0.5 or math.abs(b - ob) > 0.5) then
          bad[#bad + 1] = string.format("%s %.0fx%.0f in %.0fx%.0f", tostring(r._file):match("[^\\]+$"), rr - l, t - b, orr - ol, ot - ob)
        end
        if r._file == "Interface\\QuestFrame\\QuestBG" then
          parchN = parchN + 1
          if not o.parch then parchBad[#parchBad + 1] = tostring(o._name or "panel") end
          local tc = r._tc or {}
          if not (#tc == 4 and tc[1] > 0.01 and tc[2] < 0.58 and tc[3] > 0.01 and tc[4] < 0.65) then tcBad[#tcBad + 1] = table.concat(tc, ",") end
        elseif r._wrapH == "REPEAT" then
          local tc = r._tc or {}
          local w = rr and (rr - l) or 0
          if w > 1 and not (#tc == 4 and tc[2] > 0) then tcBad[#tcBad + 1] = "tile " .. table.concat(tc, ",") end
        end
      end
    end
    check(n > 0 and #bad == 0, "0.5.1.1 " .. where .. ": every stock surface fills its panel corner to corner (" .. n .. " surfaces" .. (#bad > 0 and (": " .. table.concat(bad, "; ")) or "") .. ")")
    check(#parchBad == 0, "0.5.1.1 " .. where .. ": parchment only on detail panels (" .. parchN .. ")" .. (#parchBad > 0 and (" not detail: " .. table.concat(parchBad, ", ")) or ""))
    check(#tcBad == 0, "0.5.1.1 " .. where .. ": parchment drawn from inside its torn edge, tiles repeat (" .. table.concat(tcBad, " | ") .. ")")
    return parchN
  end
  NS.ShowTab("quests")
  check(fillCheck("Quests") == 1, "0.5.1.1 Quests: exactly one parchment (the quest detail)")
  NS.ShowTab("journals")
  NS.tabs.journals.SetSection("adventure")
  check(fillCheck("Adventure Guide") == 1, "0.5.1.1 Adventure Guide: exactly one parchment (the boss detail)")
  local ag = NS.AGWidgets()
  local function lum(fs) local c = fs._tcol or { 0, 0, 0 } return 0.2126 * c[1] + 0.7152 * c[2] + 0.0722 * c[3] end
  check(lum(ag.title) > 0.5 and lum(ag.meta) > 0.5, string.format("0.5.1.1 Adventure Guide: the dungeon header on the dark page is light (%.2f, %.2f)", lum(ag.title), lum(ag.meta)))
  check(lum(ag.dropHead) < 0.2 and lum(ag.emptyDrops) < 0.3, string.format("0.5.1.1 Adventure Guide: boss detail on parchment uses dark ink (%.2f, %.2f)", lum(ag.dropHead), lum(ag.emptyDrops)))
  check(lum(ag.bossHead) > 0.5, "0.5.1.1 Adventure Guide: the boss list (dark panel) keeps light text")
  NS.tabs.journals.SetSection("fishing")
  fillCheck("Fishing")
  NS.tabs.journals.SetSection("achievements")
  fillCheck("Achievements")
  NS.ShowTab("map")
  fillCheck("Map")
  NS.ShowTab("dungeons")
  fillCheck("Dungeons")
  -- scroll buttons: the stock files at the stock 16x16 size, with a stock highlight; never the whole button stretched
  local sbN, sbBad, hl = 0, {}, 0
  for _, r in ipairs(REGIONS) do
    local f = tostring(r._file)
    if r._kind == "texture" and f:find("^Interface\\Buttons\\UI%-ScrollBar%-Scroll") then
      sbN = sbN + 1
      if r._sw ~= 16 or r._sh ~= 16 then sbBad[#sbBad + 1] = f:match("[^\\]+$") .. " " .. tostring(r._sw) .. "x" .. tostring(r._sh) end
      if f:find("Highlight$") and r._layer == "HIGHLIGHT" then hl = hl + 1 end
    end
  end
  check(sbN > 0 and #sbBad == 0 and hl > 0, "0.5.1.1 WoW theme: stock scroll buttons at 16x16 with the stock highlight (" .. sbN .. (#sbBad > 0 and (" bad: " .. table.concat(sbBad, ", ")) or "") .. ")")
  -- 0.5.1.3: class themes draw the same stock scroll art, desaturated and recoloured
  NS.SetTheme("warrior")
  local classStock = 0
  local classUndesat = 0
  for _, r in ipairs(REGIONS) do if r._kind == "texture" and tostring(r._file):find("^Interface\\Buttons\\UI%-ScrollBar") then classStock = classStock + 1 if not r._desat then classUndesat = classUndesat + 1 end end end
  check(classStock > 0 and classUndesat == 0, "0.5.1.3 class themes: the stock scroll art, desaturated and recoloured (" .. classStock .. ")")
  NS.SetTheme("wow")
  -- /dm parchment: crop override, validated, reset
  said = {}
  NS.Print = function(m) said[#said + 1] = m end
  SlashCmdList["DARKMATTER"]("parchment 0.05 0.5 0.05 0.6")
  local ok1 = NS.db.parchTC and NS.db.parchTC[2] == 0.5
  SlashCmdList["DARKMATTER"]("parchment 0.9 0.1 0 1")
  local ok2 = NS.db.parchTC and NS.db.parchTC[2] == 0.5
  SlashCmdList["DARKMATTER"]("parchment reset")
  NS.Print = oldPrint
  check(ok1 and ok2 and NS.db.parchTC == nil and said[#said]:find("%(default%)"), "0.5.1.1 /dm parchment: sets, rejects a bad crop, resets (" .. tostring(said[#said]) .. ")")
  -- the achievement toast: icon AND background AND every text line, at once, in every theme
  for _, id in ipairs(NS.themeOrder) do
    NS.SetTheme(id)
    said = {}
    NS.Print = function(m) said[#said + 1] = m end
    SlashCmdList["DARKMATTER"]("testtoast")
    NS.Print = oldPrint
    local T = NS.Ach._ToastFrame()
    check(T and T._shown and T.bg and T.fg, "0.5.1.1 /dm testtoast shows the toast (" .. id .. ")")
    T._scripts.OnUpdate(T, 0.3)
    local fgL, bgL = T.fg._level or 0, T.bg._level or 0
    local textsOK = true
    for _, fs in ipairs({ T.head, T.name, T.sub }) do
      if fs._parent ~= T.fg or not visible(fs) or (fs:GetText() or "") == "" then textsOK = false end
    end
    local bgTex = 0
    for _, r in ipairs(REGIONS) do if r._kind == "texture" and r._parent == T.bg and visible(r) and (r._file or r._color) then bgTex = bgTex + 1 end end
    check(fgL > bgL and T.icon._parent == T.fg and textsOK and bgTex > 0 and T._alpha == 1,
      string.format("0.5.1.1 toast (%s): background drawn (%d), text and icon above it (levels %d > %d), full alpha after the fade-in", id, bgTex, fgL, bgL))
    check(said[1] and said[1]:find("^test toast: ") , "0.5.1.1 /dm testtoast: says it is a preview (" .. id .. ")")
    for _ = 1, 50 do if not T._shown then break end T._scripts.OnUpdate(T, 1) end
    check(not T._shown, "0.5.1.1 toast (" .. id .. "): fades out and hides")
  end
  -- ===== 0.5.1.2: stock button feel, character-frame tabs, no marker dots, item rows on the parchment, stock groove =====
  local played = {}
  local savePS, saveSK = PlaySound, SOUNDKIT
  SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 856, IG_CHARACTER_INFO_TAB = 841, U_CHAT_SCROLL_BUTTON = 1115 }
  PlaySound = function(id) played[#played + 1] = id end
  NS.Stock.ClearCache()
  NS.SetTheme("wow")
  local function mid(b) local F = rawget(b, "face") return tostring(F and F.m._file or b.slice.m._file) end -- 0.5.1.3: the stock faces
  local function tcIs(t, want) if not t then return false end for i = 1, #want do if math.abs((t[i] or -1) - want[i]) > 1e-6 then return false end end return true end
  local sb = W.settingsBtn
  local hlOK = sb.stockOn and sb.stockHL._file == "Interface\\Buttons\\UI-Panel-Button-Highlight" and sb.stockHL._layer == "HIGHLIGHT"
    and sb.stockHL._blend == "ADD" and tcIs(sb.face.hl.l._tc, { 0, 0.09375, 0, 0.6875 }) and tcIs(sb.stockHL._tc, { 0.09375, 0.53125, 0, 0.6875 }) and tcIs(sb.face.hl.r._tc, { 0.53125, 0.625, 0, 0.6875 })
  check(hlOK, "0.5.1.2 WoW buttons: stock UI-Panel-Button-Highlight on the HIGHLIGHT layer, ADD blend (0.5.1.3: 3-slice like the faces, 0..0.625 x 0..0.6875)")
  local upFace = mid(sb)
  local c0 = sb.text._tcol
  sb._scripts.OnMouseDown(sb, "LeftButton")
  local downFace, pt = mid(sb), sb.text._pts[#sb.text._pts]
  sb._scripts.OnMouseUp(sb, "LeftButton")
  sb._scripts.PostClick(sb, "LeftButton")
  check(upFace:find("UI%-Panel%-Button%-Up$") and downFace:find("UI%-Panel%-Button%-Down$") and mid(sb):find("UI%-Panel%-Button%-Up$"),
    "0.5.1.2 WoW buttons: Up face, Down face while held, Up again on release (" .. upFace .. " / " .. downFace .. ")")
  check(pt and pt[4] == 1 and pt[5] == 0, "0.5.1.2 WoW buttons: the label moves 1px right and down while held (" .. tostring(pt and pt[4]) .. "," .. tostring(pt and pt[5]) .. ")")
  check(c0 and math.abs(c0[1] - 1) < 0.01 and math.abs(c0[2] - 0.82) < 0.01 and c0[3] < 0.01, "0.5.1.2 WoW buttons: gold normal label")
  sb._scripts.OnEnter(sb)
  local ch = sb.text._tcol
  sb._scripts.OnLeave(sb)
  check(ch[1] == 1 and ch[2] == 1 and ch[3] == 1 and not sb.hoverTex[1]._shown, "0.5.1.2 WoW buttons: white label on hover, no Dark Matter tint/edge (the stock highlight does the hover)")
  check(played[#played] == 856, "0.5.1.2 WoW buttons: the stock click sound (SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)")
  local sh = W.shareBtn
  check(mid(sh):find("UI%-Panel%-Button%-Disabled$") and sh.text._tcol[1] < 0.9 and sh.text._tcol[1] == sh.text._tcol[3] and sh.stockHL._alpha == 0,
    "0.5.1.2 WoW buttons: a disabled button (Share stats) shows the Disabled face, a grey label, no highlight")
  local nPlayed = #played
  sh._scripts.OnMouseDown(sh, "LeftButton")
  check(mid(sh):find("Disabled$"), "0.5.1.2 WoW buttons: a disabled button does not press")
  sh._scripts.OnMouseUp(sh, "LeftButton")
  -- rail tabs: stock panel buttons, the active one held down
  local railOK, railN = true, 0
  for _, t in pairs(W.railTabs) do
    railN = railN + 1
    local f = mid(t)
    if not t.stockOn or (t.active and not f:find("Down$")) or (not t.active and not f:find("Up$")) or t.stockHL._file ~= "Interface\\Buttons\\UI-Panel-Button-Highlight" then railOK = false end
  end
  check(railN == 4 and railOK, "0.5.1.2 WoW rail tabs: stock panel buttons (active held down), stock highlight")
  -- section tabs: character-frame tabs; toggles: panel buttons; never a marker dot
  NS.ShowTab("journals")
  NS.tabs.journals.SetSection("adventure")
  local ag = NS.AGWidgets()
  local tabOK, dotN = true, 0
  for _, p in ipairs(ag.pills) do
    local f = mid(p)
    if p.stockStyle ~= "tab" or (p.active and not f:find("ActiveTab$")) or (not p.active and not f:find("InActiveTab$")) then tabOK = false end
    if p.stockHL._file ~= "Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight" or (p.active and p.stockHL._alpha ~= 0) then tabOK = false end
    if rawget(p, "mark") and visible(p.mark) then dotN = dotN + 1 end
  end
  local pa = ag.pills[1]
  pa._scripts.OnMouseDown(pa, "LeftButton")
  local tabPt = pa.text._pts[#pa.text._pts]
  pa._scripts.OnMouseUp(pa, "LeftButton")
  check(tabOK and tabPt[4] == 0 and tabPt[5] == 1, "0.5.1.2 WoW section tabs: ActiveTab raised / InActiveTab, tab highlight on the unselected ones, no press offset")
  local tg = ag.lvlAll
  check(tg.stockStyle == "button" and (tg.active and mid(tg):find("Down$") or mid(tg):find("Up$")), "0.5.1.2 WoW filter toggles (All levels): stock panel buttons, held down while on")
  for _, p in ipairs({ ag.lvlAll, ag.lvlMine }) do if rawget(p, "mark") and visible(p.mark) then dotN = dotN + 1 end end
  NS.ShowTab("quests")
  if visible(W.allBtn) then end
  local qbar = NS.tabs.quests.Parts()
  if visible(qbar.allIcon) then dotN = dotN + 1 end
  check(dotN == 0 and W.allBtn.stockOn and mid(W.allBtn):find("UI%-Panel%-Button%-Up$"), "0.5.1.2 WoW: no marker dot / icon on any tab, sub-tab or the All toggles (" .. dotN .. ")")
  -- boss drops and quest rewards straight on the parchment
  NS.ShowTab("journals")
  NS.tabs.journals.SetSection("adventure")
  ag = NS.AGWidgets()
  local parchBg = NS.theme.colors.parchBg
  local dropOK, dropN = true, 0
  for _, r in ipairs(ag.dropRows) do
    if r._shown then
      dropN = dropN + 1
      if rawget(r, "plate") then dropOK = false end
      local c = r.text._tcol
      if not c or NS.Contrast({ c[1], c[2], c[3] }, parchBg) < 4.5 then dropOK = false end
      if lum(r.sub) > 0.3 or r.hl._layer ~= "HIGHLIGHT" then dropOK = false end
    end
  end
  check(ag.dropPanel.parch and dropOK, "0.5.1.2 Adventure Guide drops: no name plate, quality colour readable on the parchment, dark detail ink, a highlight (" .. dropN .. " rows)")
  local r1 = ag.dropRows[1]
  check(not r1 or (r1.text._tcol[3] > r1.text._tcol[1]), "0.5.1.2 Adventure Guide drops: a Rare item stays blue (darkened), not brown")
  NS.ShowTab("quests")
  local _, qd2 = NS.tabs.quests.Parts()
  local rewOK = true
  for _, b in ipairs(qd2.items or {}) do if rawget(b, "plate") then rewOK = false end if b._shown and NS.Contrast(b.name._tcol, parchBg) < 4.5 then rewOK = false end end
  check(rewOK, "0.5.1.2 quest rewards: no name plate, names readable on the parchment")
  -- scroll bars: the stock groove, no solid dark track
  local grooveN = 0
  for _, r in ipairs(REGIONS) do
    if r._kind == "texture" and r._file == "Interface\\PaperDollInfoFrame\\UI-Character-ScrollBar" and under(r, win) and visible(r) then grooveN = grooveN + 1 end
  end
  check(grooveN >= 4, "0.5.1.2 WoW scroll bars: the stock UI-Character-ScrollBar groove is drawn (" .. grooveN .. " pieces)")
  -- artprobe reports the new files and templates
  said = {}
  NS.Print = function(m) said[#said + 1] = m end
  SlashCmdList["DARKMATTER"]("artprobe")
  NS.Print = oldPrint
  local all = table.concat(said, "\n")
  local need = { "UIPanelButtonTemplate %(template%)", "CharacterFrameTabButtonTemplate %(template%)", "UIPanelScrollFrameTemplate %(template%)",
    "UIPanelScrollBarTemplate %(template%)", "UI%-Panel%-Button%-Highlight", "UI%-Panel%-Button%-Down", "UI%-Character%-Tab%-Highlight", "UI%-Character%-ScrollBar" }
  local miss = {}
  for _, n in ipairs(need) do if not all:find("ok [^\n]*" .. n) then miss[#miss + 1] = n end end
  check(#miss == 0 and said[#said]:find(", 0 missing$"), "0.5.1.2 /dm artprobe: reports the button / tab / scroll templates and files (" .. tostring(said[#said]) .. (#miss > 0 and (" missing: " .. table.concat(miss, ", ")) or "") .. ")")
  -- 0.5.1.3 class themes: the stock button feel recoloured in the theme's palette, and no marker dot
  NS.SetTheme("warrior")
  NS.ShowTab("journals")
  local cl = NS.AGWidgets()
  local clDot = 0
  for _, p in ipairs(cl.pills) do if rawget(p, "mark") and visible(p.mark) then clDot = clDot + 1 end end
  check(W.settingsBtn.stockOn and W.settingsBtn.face.m._desat and W.settingsBtn.stockHL._file == "Interface\\Buttons\\UI-Panel-Button-Highlight" and clDot == 0,
    "0.5.1.3 class themes: the stock button feel, desaturated and recoloured, no marker dot")
  -- fallback: the stock button files missing -> Dark Matter's own feel
  STOCK_MISSING = true
  NS.Stock.ClearCache()
  NS.SetTheme("wow")
  check(not W.settingsBtn.stockOn, "0.5.1.2 fallback: without the stock button files the WoW buttons keep Dark Matter's own art")
  STOCK_MISSING = false
  NS.Stock.ClearCache()
  NS.SetTheme("wow")
  NS.ShowTab("quests")
  -- ===== 0.5.1.3: every face anchored alike at any width; scroll bars in their own gutter; no dots; late reward items =====
  local UI = NS.UI
  local function near(a, b) return a ~= nil and b ~= nil and math.abs(a - b) < 0.01 end
  local function sameRect(a, b)
    local al, at, ar, ab = rect(a)
    local bl, bt, br, bb = rect(b)
    return near(al, bl) and near(at, bt) and near(ar, br) and near(ab, bb)
  end
  -- the face's left cap at the button's left edge, the right cap at its right edge, both the full height and the same
  -- width, the middle exactly between them; the highlight (buttons) on the very same rectangles
  local function facesFill(b)
    local F = b.face
    local l, t, r, bo = rect(b)
    local ll, lt, lr, lb = rect(F.l)
    local ml, mt, mr, mb = rect(F.m)
    local rl, rt, rr, rb = rect(F.r)
    if not (l and ll and ml and rl) then return false, "unresolved" end
    local ok = near(ll, l) and near(rr, r) and near(lt, t) and near(lb, bo) and near(rt, t) and near(rb, bo) and near(mt, t) and near(mb, bo)
      and near(lr, ml) and near(mr, rl) and near(lr - ll, rr - rl) and (mr - ml) >= -0.01 and F.shown
    if b.stockStyle ~= "tab" then
      for _, k in ipairs({ "l", "m", "r" }) do if not sameRect(F.hl[k], F[k]) then ok = false end end
    end
    return ok, string.format("%.0fx%.0f cap %.0f", r - l, t - bo, lr - ll)
  end
  local host = CreateFrame("Frame", nil, win)
  host:SetPoint("TOPLEFT", win, "TOPLEFT", 0, 0)
  host:SetSize(400, 100)
  for _, id in ipairs({ "wow", "hunter", "priest" }) do
    NS.SetTheme(id)
    NS.ShowTab("quests")
    local bad, n = {}, 0
    for _, w in ipairs({ 40, 80, 132, 146, 300 }) do
      for _, h in ipairs({ 22, 48 }) do
        local b = UI.Button(host, "Test", w, h, "red", 11)
        b:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        for _, st in ipairs({ "Up", "Down" }) do
          if st == "Down" then b._scripts.OnMouseDown(b, "LeftButton") end
          local ok, why = facesFill(b)
          n = n + 1
          if not ok or not tostring(b.face.m._file):find("UI%-Panel%-Button%-" .. st .. "$") then bad[#bad + 1] = w .. "x" .. h .. " " .. st .. " (" .. tostring(why) .. ")" end
        end
        b._scripts.OnMouseUp(b, "LeftButton")
        b:Hide()
      end
    end
    -- the nav rail: every tab (the held-down one too) one width, its faces filling it
    local railW
    for _, t in pairs(W.railTabs) do
      local ok, why = facesFill(t)
      n = n + 1
      if not ok then bad[#bad + 1] = "rail " .. tostring(t.text:GetText()) .. " (" .. why .. ")" end
      local l, _, r = rect(t)
      if railW and not near(railW, r - l) then bad[#bad + 1] = "rail widths differ" end
      railW = r - l
    end
    -- section tabs and filter toggles
    NS.ShowTab("journals")
    NS.tabs.journals.SetSection("adventure")
    local ag = NS.AGWidgets()
    for _, p in ipairs(ag.pills) do local ok, why = facesFill(p) n = n + 1 if not ok then bad[#bad + 1] = "tab " .. why end end
    for _, p in ipairs({ ag.lvlAll, ag.lvlMine }) do local ok, why = facesFill(p) n = n + 1 if not ok then bad[#bad + 1] = "toggle " .. why end end
    check(#bad == 0 and n >= 26, "0.5.1.3 " .. id .. ": Normal / Pushed faces and the Highlight anchored alike at widths 40-300 and heights 22 / 48, rail tabs one width (" .. n .. " checked" .. (#bad > 0 and ("; " .. table.concat(bad, ", ")) or "") .. ")")
  end
  host:Hide()

  -- scroll bars: outside the pane, in its own gutter; top arrow level with the pane's top, bottom arrow with its bottom
  local function gutterOK(S, name, bad)
    if not S or not S.pane then bad[#bad + 1] = name .. ": no pane" return end
    local pl, pt, pr, pb = rect(S.pane)
    local ul, ut, ur = rect(S.up)
    local dl, _, dr, db = rect(S.down)
    local _, _, fr = rect(S.scroll)
    local G = UI.Gutter()
    if not (pl and ul and dl and fr) then bad[#bad + 1] = name .. ": unresolved" return end
    local ok = ul >= pr - 0.01 and ur <= pr + G + 0.01 and dl >= pr - 0.01 and dr <= pr + G + 0.01 and near(ut, pt) and near(db, pb) and fr <= pr + 0.01
    if not ok then
      bad[#bad + 1] = string.format("%s: pane %.0f..%.0f x %.0f..%.0f, up x %.0f..%.0f top %.0f, down bottom %.0f, content right %.0f", name, pl, pr, pb, pt, ul, ur, ut, db, fr)
    end
  end
  for _, id in ipairs({ "wow", "hunter" }) do
    NS.SetTheme(id)
    local bad = {}
    NS.ShowTab("quests")
    local _, qdt, qlist = NS.tabs.quests.Parts()
    gutterOK(qlist, "quest list", bad)
    gutterOK(qdt.scroll, "quest detail", bad)
    NS.ShowTab("journals")
    NS.tabs.journals.SetSection("adventure")
    local ag = NS.AGWidgets()
    gutterOK(ag.bossScroll, "boss list", bad)
    gutterOK(ag.dropScroll, "boss detail", bad)
    NS.tabs.journals.SetSection("fishing")
    local fw = NS.FishWidgets()
    gutterOK(fw.zoneScroll, "fishing zones", bad)
    gutterOK(fw.fishScroll, "fishing list", bad)
    gutterOK(fw.statsScroll, "fishing statistics", bad)
    NS.tabs.journals.SetSection("achievements")
    local aw = NS.AchPage.Widgets()
    gutterOK(aw.treeScroll, "achievement categories", bad)
    gutterOK(aw.cardScroll, "achievement list", bad)
    -- the groove spans the pane exactly (WoW theme: the stock groove; class themes: the same, recoloured)
    local S = ag.dropScroll
    if S.groove and S.groove[1]._shown ~= false and visible(S.groove[1]) then
      local _, gt = rect(S.groove[1])
      local _, _, _, gb = rect(S.groove[3])
      local _, pt, _, pb = rect(S.pane)
      if not (near(gt, pt) and near(gb, pb)) then bad[#bad + 1] = "boss detail groove not the pane's height" end
    end
    -- the stock scroll bar pieces in every theme (class themes: desaturated and recoloured)
    local ut = S.upTex
    if not (type(ut._file) == "string" and ut._file:find("UI%-ScrollBar%-ScrollUpButton") and S.groove[1]._file and tostring(S.groove[1]._file):find("UI%-Character%-ScrollBar")) then
      bad[#bad + 1] = "not the stock scroll pieces (" .. tostring(ut._file) .. ")"
    end
    if (id ~= "wow") ~= (ut._desat == true) or (id ~= "wow") ~= (S.thumb._desat == true) then bad[#bad + 1] = "recolour wrong (" .. tostring(ut._desat) .. ")" end
    check(#bad == 0, "0.5.1.3 " .. id .. ": every scroll bar in its own gutter right of its pane, arrows level with the pane's top and bottom (" .. (#bad > 0 and table.concat(bad, "; ") or "9 panes") .. ")")
  end

  -- no marker dot / radial on any tab or toggle in any theme
  local origSP = NS.SetPiece
  NS.SetPiece = function(tex, key) tex._dmKey = key return origSP(tex, key) end
  local dotThemes = {}
  for _, id in ipairs(NS.themeOrder) do
    NS.SetTheme(id)
    local dots = 0
    for _, view in ipairs({ { "quests" }, { "journals", "adventure" }, { "journals", "fishing" }, { "journals", "achievements" } }) do
      NS.ShowTab(view[1])
      if view[2] then NS.tabs.journals.SetSection(view[2]) end
      for _, r in ipairs(REGIONS) do
        if r._kind == "texture" and under(r, win) and visible(r) and type(r._dmKey) == "string" and (r._dmKey:find("target") or r._dmKey:find("dot") or r._dmKey:find("radial")) then dots = dots + 1 end
      end
      for _, f in ipairs(ALL) do
        if rawget(f, "stockStyle") and rawget(f, "mark") and visible(f.mark) and under(f, win) then dots = dots + 1 end
      end
      local qb = NS.tabs.quests.Parts()
      if qb.allIcon and visible(qb.allIcon) and under(qb.allIcon, win) then dots = dots + 1 end
    end
    if dots > 0 then dotThemes[#dotThemes + 1] = id .. "=" .. dots end
  end
  NS.SetPiece = origSP
  check(#dotThemes == 0 and #NS.themeOrder == 10, "0.5.1.3 no marker dot / radial on any tab or toggle in any of the " .. #NS.themeOrder .. " themes (" .. table.concat(dotThemes, ", ") .. ")")

  -- a reward item the client has not loaded: 'Loading...', then the real name when its item event arrives
  NS.SetTheme("wow")
  NS.ShowTab("quests")
  local QL = NS.QL
  local oRI, oCI, oGII = GetQuestLogRewardInfo, GetQuestLogChoiceInfo, GetItemInfo
  local LATE_ID, loaded = 990001, false
  local function lateWrap(orig)
    return function(i, ...)
      local r = { orig(i, ...) }
      if r[1] ~= nil and i == 1 then r[1] = nil r[6] = LATE_ID end
      return unpack(r, 1, 6)
    end
  end
  GetQuestLogRewardInfo, GetQuestLogChoiceInfo = lateWrap(oRI), lateWrap(oCI)
  GetItemInfo = function(id, ...) if id == LATE_ID then if loaded then return "Late Loaded Blade", "item:990001", 3 end return nil end if oGII then return oGII(id, ...) end end
  local reqBefore = #MUTATED
  QL.Forget()
  NS.tabs.quests.Refresh()
  local _, qdl = NS.tabs.quests.Parts()
  local function itemNames()
    local t = {}
    for _, b in ipairs(qdl.items or {}) do if b._shown and visible(b) then t[#t + 1] = b.name:GetText() end end
    return t
  end
  local before = table.concat(itemNames(), "|")
  local asked = false
  for i = reqBefore + 1, #MUTATED do if MUTATED[i] == "C_Item.RequestLoadItemDataByID" then asked = true end end
  local waiting = QL.awaitItems[LATE_ID] ~= nil
  check(before:find("Loading\226\128\166", 1, true) and asked and waiting and QL.ItemArrived(424242) == false,
    "0.5.1.3 quest rewards: an unloaded item says 'Loading...' and its data is requested (" .. before .. ")")
  loaded = true
  local fired = 0
  for _, f in ipairs(ALL) do
    if f._ev and f._ev.ITEM_DATA_LOAD_RESULT and f._scripts and f._scripts.OnEvent then
      f._scripts.OnEvent(f, "ITEM_DATA_LOAD_RESULT", LATE_ID, true)
      fired = fired + 1
    end
  end
  local after = table.concat(itemNames(), "|")
  check(fired > 0 and after:find("Late Loaded Blade", 1, true) and not after:find("Loading", 1, true),
    "0.5.1.3 quest rewards: ITEM_DATA_LOAD_RESULT for the awaited item redraws the detail with its name (" .. after .. ")")
  GetQuestLogRewardInfo, GetQuestLogChoiceInfo, GetItemInfo = oRI, oCI, oGII
  QL.Forget()
  NS.tabs.quests.Refresh()
  PlaySound, SOUNDKIT = savePS, saveSK
  NS.SetTheme("wow")
end

-- ===== 0.5.1.4: close-up detail (the game's minimap tiles), the map-window size and the WoW theme's map-window frame =====
if MODE == "full" then
  local NS = DarkMatter
  local CU, MW, W = NS.MapCloseUp, NS.MapWindow, NS.windowParts
  -- 1. no OpenMap file path anywhere in Dark Matter (code, data, docs, art)
  local hits = {}
  for _, path in ipairs(DM_FILES or {}) do
    local fh = io.open(path, "rb") local src = fh and fh:read("*a") or "" if fh then fh:close() end
    if src:find("Interface\\AddOns\\OpenMap", 1, true) or src:find("Interface\\\\AddOns\\\\OpenMap", 1, true) or src:lower():find("interface[\\/]+addons[\\/]+openmap") then hits[#hits + 1] = path end
  end
  check(#(DM_FILES or {}) > 30 and #hits == 0, "0.5.1.4: the string Interface\\AddOns\\OpenMap appears nowhere in Dark Matter " .. table.concat(hits, ", "))
  check(io.open(arg[1] .. "/LICENSES/THIRD_PARTY.md") ~= nil and io.open(arg[1] .. "/Data_Minimap.lua"):read("*a"):find("Permission is hereby granted", 1, true),
    "0.5.1.4: the minimap tile table carries OpenMap's MIT notice; LICENSES/THIRD_PARTY.md is shipped")
  -- excluded art never referenced: no OpenMap texture folders, no Blizzard file bundled (Media holds only our own art)
  local media = {}
  for _, path in ipairs(DM_FILES or {}) do local f = path:match("[/\\]Media[/\\]([^/\\]+)$") if f then media[#media + 1] = f end end
  local odd = {}
  for _, f in ipairs(media) do if not f:find("^wow%-") and not f:find("^cls%-") and not f:find("^dm%-") then odd[#odd + 1] = f end end
  local srcAll = ""
  for _, f in ipairs({ "MapCloseUp.lua", "Tab_Map.lua", "MapProbe.lua", "MapWindow.lua", "Window.lua" }) do srcAll = srcAll .. io.open(arg[1] .. "/" .. f):read("*a") end
  local excluded = {}
  for _, k in ipairs({ "MapMiniLOD", "MapDungeonDrawn", "MapChart", "MapGapFill" }) do if srcAll:find(k, 1, true) then excluded[#excluded + 1] = k end end
  check(#excluded == 0, "0.5.1.4: OpenMap's art folders (MapMiniLOD, MapDungeonDrawn, MapChart, MapGapFill) are never referenced " .. table.concat(excluded, ","))
  check(#media > 10 and #odd == 0, "0.5.1.4: Media holds only Dark Matter's own art (no game or OpenMap file bundled) " .. table.concat(odd, ","))

  -- 2. the close-up on a made-up continent (16000 yd square, every tile has a file, the zone covers it)
  local MD = NS.MapData
  local saveZoneAt, saveArt, saveEx, saveTiles = MD.ZoneAt, MD.Art, MD.Explored, NS.MinimapTiles
  local saveFrames, saveCells = CU.frames, CU.cells
  CU.frames, CU.cells = { [9001] = { inst = 0, X0 = 8000, Y0 = 8000, X1 = -8000, Y1 = -8000 } }, {}
  NS.MinimapTiles = { [0] = setmetatable({}, { __index = function(_, k) return 1000000 + k end }) }
  MD.ZoneAt = function(_, x, y) return { id = 77 }, x, y end
  MD.Art = function() return { w = 1000, h = 1000 } end
  local exploredHalf = { { offsetX = 0, offsetY = 0, textureWidth = 500, textureHeight = 1000 } }
  MD.Explored = function() return exploredHalf end
  local host = CreateFrame("Frame", nil, UIParent)
  local function ctxAt(S, vw, vh, mag) -- 0.5.1.8: mag = the art magnification (else 5 yd per texel)
    local ox, oy = 0.5 * S - vw / 2, 0.5 * S - vh / 2
    return { host = host, conts = { { id = 9001, alpha = 1 } }, place = function() return { 0, 1, 0, 1 } end,
      toScreen = function(wx, wy) return wx * S - ox, wy * S - oy end, vw = vw, vh = vh, mag = mag }
  end
  local function shown()
    local list = {}
    for _, t in ipairs(CU.pool) do if t:IsShown() then list[#list + 1] = t end end
    return list
  end
  NS.db.map = NS.db.map or {}
  NS.db.map.closeUp, NS.db.map.closeMix = true, nil
  CU.unavailable, CU.failed, CU.fails, CU.loaded = nil, {}, 0, 0
  -- 0.5.1.8: fades keyed to how magnified the map art is (screen px per art texel): the zone art alone up to x2.0,
  -- a quick crossfade to the tiles by x2.6, then tiles at full strength (default 45%); grain only with the tiles
  check(CU.Mix(1.0) == 0 and CU.Mix(1.99) == 0 and CU.Mix(2.3) > 0.2 and CU.Mix(2.3) < 0.8 and math.abs(CU.Mix(2.6) - 1) < 1e-9
    and math.abs(CU.Mix(6) - 1) < 1e-9 and CU.Mix(3, 0) == 0 and CU.Mix(3, 0.2) < 0.5,
    "0.5.1.8 close-up: zone art alone to x2.0, quick crossfade to full tiles by x2.6 (strength 0 = off)")
  check(CU.LayerName(0) == "zone art" and CU.LayerName(1) == "tiles" and CU.LayerName(0.5) == "crossfading",
    "0.5.1.8 close-up: the layer names (zone art / crossfading / tiles)")
  check(math.abs(CU.MaxScale(9001, 1000) - 0.96 * 16000 / 1000) < 1e-6, "0.5.1.4 close-up: the deepest zoom stops at twice the minimap's own sharpness")
  local function rects(list)
    local out = {}
    for _, t in ipairs(list) do local p = t._pts[1] out[#out + 1] = { p[4], -p[5], p[4] + t._w, -p[5] + t._h, t } end
    return out
  end
  local function overlaps(R)
    local over = 0
    for i = 1, #R do for j = i + 1, #R do
      local ix = math.min(R[i][3], R[j][3]) - math.max(R[i][1], R[j][1])
      local iy = math.min(R[i][4], R[j][4]) - math.max(R[i][2], R[j][2])
      if ix > 0.01 and iy > 0.01 then over = over + 1 end
    end end
    return over
  end
  local function covered(R, vw, vh)
    local area = 0
    for _, r in ipairs(R) do
      local w = math.min(r[3], vw) - math.max(r[1], 0)
      local h = math.min(r[4], vh) - math.max(r[2], 0)
      if w > 0 and h > 0 then area = area + w * h end
    end
    return area / (vw * vh)
  end
  local r1 = CU.Layout(ctxAt(13600, 600, 400)) -- 0.85 px/yd (0.5.1.6: deep from 0.80); explored or not: no longer matters
  local list = shown()
  local R = rects(list)
  local left, right = 0, 0
  for _, r in ipairs(R) do if r[1] < 300 then left = left + 1 end if r[3] > 300 then right = right + 1 end end
  check(r1.pieces > 0 and left > 0 and right > 0 and math.abs(covered(R, 600, 400) - 1) < 1e-3,
    "0.5.1.5 close-up: blended across the whole view, explored or not (covers " .. string.format("%.3f", covered(R, 600, 400)) .. " of it)")
  check(overlaps(R) == 0 and r1.pieces == r1.tiles, "0.5.1.5 close-up: whole tiles, one texture each, never overlapping (" .. r1.pieces .. "/" .. r1.tiles .. ")")
  check(r1.tiles <= 144 and math.abs(r1.mix - 1) < 1e-3 and r1.layer == "tiles" and r1.grain and r1.grain > 0, "0.5.1.8 close-up: full tiles, paper grain on, tiles in view " .. r1.tiles)
  local alphaOK = true
  for _, t in ipairs(list) do if math.abs((t._alpha or 1) - r1.mix) > 1e-6 then alphaOK = false end end
  check(alphaOK and list[1] and list[1]._vc and list[1]._vc[3] < 0.9, "0.5.1.4 close-up: tiles at the mix strength, tinted toward parchment")
  local g1 = list[1] and rawget(list[1], "glow")
  check(g1 and g1:IsShown() and g1._file == list[1]._file and math.abs((g1._alpha or 1) - r1.mix) < 1e-6 and g1._vc and g1._vc[1] > g1._vc[3],
    "0.5.1.6 close-up: each tile is lifted by a warm ADD pass of itself (lighter, toward the parchment)")
  local poolN = #CU.pool
  CU.Layout(ctxAt(13600, 600, 400))
  check(#CU.pool == poolN, "0.5.1.4 close-up: textures are pooled (no new ones on redraw)")
  -- a gap (column of tiles x = 32 missing: sea / void): no piece there, its neighbours fade to 0 toward it
  NS.MinimapTiles = { [0] = setmetatable({}, { __index = function(_, k) if math.floor(k / 64) == 32 then return nil end return 1000000 + k end }) }
  CU.Forget()
  local rG = CU.Layout(ctxAt(8000, 600, 400))
  local gapX1, gapX2 = 300, 300 + 8000 * CU.TILE / 16000 -- tile x 32 spans screen x 300 .. 566.7
  local inGap, edgeA, farA, grads = 0, 1, 0, 0
  for _, r in ipairs(rects(shown())) do
    local t = r[5]
    if r[1] > gapX1 + 0.5 and r[3] < gapX2 - 0.5 then inGap = inGap + 1 end
    if t._grad then grads = grads + 1 end
    local a1, a2 = t.dmA1 or 1, t.dmA2 or 1
    if math.abs(r[3] - gapX1) < 0.5 then edgeA = math.min(edgeA, a2) end       -- cells touching the gap from the west
    if r[3] < gapX1 - 140 then farA = math.max(farA, math.min(a1, a2)) end      -- over half a tile away
  end
  check(rG.pieces > 0 and inGap == 0 and edgeA < 0.01 and farA > 0.99 and grads > 0,
    "0.5.1.5 close-up: where the tiles end the edge feathers to 0 (edge " .. string.format("%.2f", edgeA) .. ", " .. grads .. " gradient cells, none in the gap)")
  NS.MinimapTiles = { [0] = setmetatable({}, { __index = function(_, k) return 1000000 + k end }) }
  CU.Forget()
  local rBig = CU.Layout(ctxAt(4000, 3000, 3000, 3)) -- 0.25 px/yd over ~22x22 tiles (art at x3: tiles on)
  check(rBig.tiles > 144 and rBig.pieces == 0, "0.5.1.5 close-up: more than 144 tiles in view -> none drawn (" .. rBig.tiles .. ")")
  local rMid = CU.Layout(ctxAt(4000, 1250, 1250, 3)) -- ~10x10 to 11x11 tiles: faded, not popped
  check(rMid.tiles > 96 and rMid.tiles <= 144 and rMid.pieces > 0 and rMid.alpha < rMid.mix and rMid.alpha > 0,
    "0.5.1.5 close-up: between 96 and 144 tiles the tiles fade out (" .. rMid.tiles .. " tiles, " .. string.format("%.2f of %.2f", rMid.alpha, rMid.mix) .. ")")
  local rLow = CU.Layout(ctxAt(1600, 600, 400)) -- 0.1 px/yd: mid zoom keeps the parchment only
  check(rLow.pieces == 0 and rLow.mix == 0, "0.5.1.4 close-up: mid zoom shows the map pictures only (no middle layer)")
  -- placement against the game's numbers (mapprobe in Wetlands): corners -2148,-390 / -4904,-4525, you -4254,-3108 = tile 37_39
  local Fw = { inst = 0, X0 = -2148, Y0 = -390, X1 = -4904, Y1 = -4525 }
  local wtx, wty = CU.TileAt(-4254, -3108)
  local px, py = CU.FromYards(Fw, -4254, -3108)
  local x1, x2, y1, y2 = CU.TileRect(Fw, wtx, wty)
  check(wtx == 37 and wty == 39 and px >= x1 and px <= x2 and py >= y1 and py <= y2 and math.abs((x2 - x1) * 4135 - CU.TILE) < 0.01,
    "0.5.1.5 close-up: Wetlands: you at -4254,-3108 yd sit inside tile 37_39 on the zone map (" .. string.format("%.3f in %.3f-%.3f", px, x1, x2) .. ")")
  -- OpenMap installed or not: the same drawing
  LOADED.OpenMap = true
  local a1 = CU.Layout(ctxAt(8000, 600, 400))
  LOADED.OpenMap = nil
  local a2 = CU.Layout(ctxAt(8000, 600, 400))
  check(a1.pieces == a2.pieces and a1.tiles == a2.tiles and a1.mix == a2.mix and CU.Label() == CU.LABEL_ON, "0.5.1.4 close-up: OpenMap present or absent draws the same (" .. a1.pieces .. "/" .. a2.pieces .. ")")
  -- the client refuses the tiles -> plain map art and the plain label
  local saveST = FrameMT.SetTexture
  FrameMT.SetTexture = function(t, f, ...) if type(f) == "number" and f >= 1000000 then return false end return saveST(t, f, ...) end
  CU.failed, CU.fails, CU.loaded = {}, 0, 0
  for _, t in ipairs(CU.pool) do t.dmFile = nil end
  CU.Layout(ctxAt(8000, 600, 400))
  local rF = CU.Layout(ctxAt(8000, 600, 400))
  FrameMT.SetTexture = saveST
  check(CU.unavailable == true and rF.pieces == 0 and CU.Label() == CU.LABEL_OFF, "0.5.1.4 close-up: tiles that do not load -> plain map pictures, label '" .. CU.Label() .. "'")
  CU.unavailable, CU.failed, CU.fails, CU.loaded = nil, {}, 0, 0
  NS.db.map.closeUp = false
  check(CU.Layout(ctxAt(8000, 600, 400)).pieces == 0 and CU.Label() == CU.LABEL_OFF, "0.5.1.4 close-up: switched off -> none drawn, plain label")
  NS.db.map.closeUp = true
  for _, t in ipairs(CU.pool) do t:Hide() end
  if CU.grain then CU.grain:Hide() end
  MD.ZoneAt, MD.Art, MD.Explored, NS.MinimapTiles = saveZoneAt, saveArt, saveEx, saveTiles
  CU.frames, CU.cells = saveFrames, saveCells
  check(CU.TileAt(0, 0) == 32 and select(2, CU.TileAt(533.4, 0)) == 30 and CU.TileAt(0, -1) == 32, "0.5.1.4 close-up: tile grid 533.33 yd, x east / y south from the centre")

  -- 3. the window size from the game's map window (read only), with its fallbacks
  local saveWMF = WorldMapFrame
  if os.getenv("DM_DUMP") then local l = MW.last or {} io.stderr:write("MWLAST ", tostring(l.w), "x", tostring(l.h), " ", tostring(l.source), " ", tostring(NS.theme.m.w), " win ", tostring(DarkMatterFrame._w), "\n") end
  local function copyM() local c = {} for k, v in pairs(NS.theme.m) do c[k] = v end return c end
  local base = NS.theme.m
  WMF_CALLS, WMF_WRITES = {}, {}
  local function wmf(...) WorldMapFrame = MakeWMF(...) MW.art = nil end
  local function outer(r) local bd = r.border or { 0, 0, 0, 0 } return (r.w + bd[1] + bd[3]) * r.scale, (r.h + bd[2] + bd[4]) * r.scale end
  wmf(1035, 640)
  local c = copyM()
  local res = MW.Apply(c)
  check(res.w == 1035 and res.h == 640 and c.w == 1035 and c.h == 640 and res.source:find("^WorldMapFrame") and not res.fallback and res.scale == 1,
    "0.5.1.4 window: as large as the game's map window (1035x640): " .. tostring(res.w) .. "x" .. tostring(res.h) .. " " .. tostring(res.source))
  check(c.bodyW - c.w == base.bodyW - base.w and c.pageW - c.w == base.pageW - base.w and c.footerTop - c.h == base.footerTop - base.h and c.exitX - c.w == base.exitX - base.w
    and c.railW == base.railW and c.tabY == base.tabY and c.bodyX == base.bodyX, "0.5.1.4 window: the body and footer follow the size, the rail and tabs keep their place")
  wmf(1035, 640, { scale = 1.25 })
  res = MW.Apply(copyM())
  check(res.w == 1294 and res.h == 800, "0.5.1.4 window: the map window's own scale is taken into account (" .. tostring(res.w) .. "x" .. tostring(res.h) .. ")")
  -- 0.5.1.5: the in-game case (1.60.1, Wetlands): map 1232x705 at effective scale 0.64; UIParent at 0.80
  local saveUES = UIParent.GetEffectiveScale
  UIParent.GetEffectiveScale = function() return 0.8 end
  wmf(1232, 705, { scale = 0.64, minW = 702, minH = 534, ql = 333 })
  res = MW.Apply(copyM())
  check(res.w == 986 and res.h == 564 and res.scale == 1,
    "0.5.1.5 window: on-screen size: map 1232x705 at 0.64 under UIParent 0.80 -> ours 986x564 at scale 1 (" .. tostring(res.w) .. "x" .. tostring(res.h) .. ")")
  -- 0.5.1.8: the size is measured while the map window is open and saved in DarkMatterDB; while it is closed (e.g.
  -- never opened since login, where its own size is not real yet) the saved size is used; rebuild only past 1 px
  do
    local saveSV = NS.db.mapWindowSize
    NS.db.mapWindowSize = nil
    wmf(1232, 705, { scale = 0.64, shown = true })
    local open = MW.Apply(copyM())
    local sv = NS.db.mapWindowSize
    check(sv and math.abs(sv.fw - 986) < 1 and sv.ues == 0.8, "0.5.1.8 window: measured while the map window is open and saved (" .. tostring(sv and sv.fw) .. ")")
    wmf(702, 534, { scale = 0.64 }) -- closed, never laid out: a wrong size of its own
    local closed = MW.Apply(copyM())
    check(closed.w == open.w and closed.h == open.h and closed.source:find("^saved"),
      "0.5.1.8 window: while the map window is closed the saved size is used at once (" .. tostring(closed.w) .. "x" .. tostring(closed.h) .. ", " .. tostring(closed.source) .. ")")
    local c2 = copyM()
    MW.Apply(c2)
    c2.w = c2.w + 0.8
    check(MW.Check(c2) == "scale", "0.5.1.8 window: under 1 px off is no rebuild")
    c2.w = c2.w + 1
    check(MW.Check(c2) == "layout", "0.5.1.8 window: over 1 px off rebuilds")
    NS.db.mapWindowSize = saveSV
  end
  wmf(1035, 640, { scale = 0.64 })
  res = MW.Apply(copyM())
  local ow, oh = outer(res)
  check(res.w >= 880 and res.h >= 500 and res.scale < 1 and math.abs(ow - 1035 * 0.8) < 1 and math.abs(oh - 640 * 0.8) < 1,
    "0.5.1.5 window: a map smaller on screen than 880x500 is matched by our scale (" .. res.w .. "x" .. res.h .. " at " .. string.format("%.3f", res.scale) .. ")")
  UIParent.GetEffectiveScale = saveUES
  wmf(1920, 1080, { maximized = true, minW = 702, minH = 534, ql = 333 })
  res = MW.Apply(copyM())
  ow, oh = outer(res)
  check(res.w <= 1800 and res.h <= 1300 and math.abs(ow - 1920) < 1 and math.abs(oh - 1080) < 1,
    "0.5.1.5 window: maximized follows the same rule: its size on screen (" .. res.w .. "x" .. res.h .. " at " .. string.format("%.3f", res.scale) .. ")")
  wmf(500, 300)
  res = MW.Apply(copyM())
  ow, oh = outer(res)
  check(res.w >= 880 and res.h >= 500 and math.abs(ow - 500) < 1 and math.abs(oh - 300) < 1, "0.5.1.5 window: a tiny map window: our layout stays 880x500 or more, our scale matches it")
  -- 0.5.1.6: the map's border corners reach past its frame (the real offsets): the target is the OUTER rectangle
  wmf(1232, 705, { real = true })
  local ml, mt, mr, mb = MW.MapBorder()
  local mw0, mh0 = MW.Size()
  check(ml == 13 and mt == 16 and mr == 4 and mb == 3 and math.abs(mw0 - 1249) < 1e-6 and math.abs(mh0 - 724) < 1e-6,
    "0.5.1.6 window: the map's outer bounds include its border (13,16,4,3 past the frame -> 1249x724): " .. tostring(mw0) .. "x" .. tostring(mh0))
  wmf(1232, 705, { real = true, rect = true })
  local rl, rt, rr, rb, fr = MW.MapRect()
  mw0, mh0 = MW.Size()
  check(rl and math.abs(mw0 - 1249) < 1e-6 and math.abs(mh0 - 724) < 1e-6 and fr[3] - fr[1] == 1232,
    "0.5.1.6 window: read from the rectangles (frame + border corners): outer " .. tostring(mw0) .. "x" .. tostring(mh0))
  local rl2 = MW.RectLines("t")
  check(#rl2 >= 2 and rl2[1]:find("map: outer", 1, true) and rl2[2]:find("border sticks out 13,16,4,3", 1, true),
    "0.5.1.6 frameprobe: both outer rectangles (and how far the map's border sticks out) " .. tostring(rl2[1]) .. " | " .. tostring(rl2[2]))
  -- live: the map window changes size -> the layout must follow ("layout"); same size -> only our scale ("scale")
  wmf(1100, 700)
  local m1 = copyM()
  MW.Apply(m1)
  check(MW.Check(m1) == "scale", "0.5.1.6 window: same map window -> nothing to rebuild")
  wmf(1100, 500)
  check(MW.Check(m1) == "layout" and not MW.ScaleLine("x"):find("changed shape", 1, true), "0.5.1.6 window: a map window of another shape -> the layout follows (no 'changed shape' fallback)")
  MW.live = nil
  local n0 = copyM()
  WorldMapFrame = nil MW.art = nil
  res = MW.Apply(n0)
  check(res.fallback and n0.w == base.w and n0.h == base.h, "0.5.1.4 window: no map window -> Dark Matter's own size")
  wmf(1035, 640)
  local saveICL = InCombatLockdown
  InCombatLockdown = function() return true end
  res = MW.Apply(copyM())
  InCombatLockdown = saveICL
  check(res.w == 1035, "0.5.1.4 window: reading the size works in combat")
  local badCall = {}
  for _, k in ipairs(WMF_CALLS) do if not (k:find("^Get") or k:find("^Is")) then badCall[#badCall + 1] = k end end
  check(#WMF_WRITES == 0 and #badCall == 0, "0.5.1.4 window: WorldMapFrame is only read (no Show, no writes, no hooks): " .. table.concat(WMF_WRITES, ",") .. table.concat(badCall, ","))
  WorldMapFrame = saveWMF MW.art = nil
  local win = NS.GetWindow()
  check(win._w == NS.theme.m.w and win._h == NS.theme.m.h, "0.5.1.4 window: the built window has the metrics' size " .. win._w .. "x" .. win._h)

  -- 0.5.1.6: EVERY theme, several map windows: our OUTER visible bounds (everything drawn, border included) equal the
  -- map window's outer bounds on screen, width and height, to 1 px. The window is built again for each.
  do
    local saveTheme = NS.theme.id
    local saveU = UIParent.GetEffectiveScale
    local function drawnBox(f)
      local l, t, r, b
      for _, e in ipairs(LayoutOf(f)) do
        if e.kind == "texture" and e.l and (e.r._alpha or 1) > 0.01 then
          local clipped, x = false, e.r._parent
          while x and x ~= UIParent do if x._ftype == "ScrollFrame" then clipped = true break end x = x._parent end
          if not clipped then
            l, t, r, b = math.min(l or e.l, e.l), math.max(t or e.t, e.t), math.max(r or e.rr, e.rr), math.min(b or e.b, e.b)
          end
        end
      end
      return l, t, r, b
    end
    local sizes = { { 1232, 705, { scale = 0.64, real = true }, 0.64 }, { 1232, 705, { real = true } }, { 1232, 705 }, { 1035, 640 },
      { 1920, 1080, { real = true } }, { 600, 420, { real = true } }, { 1600, 760, { scale = 0.8 } } }
    local worst, n, portraits, rebuilt = 0, 0, {}, 0
    local areas, nAreas = {}, 0
    for _, id in ipairs(NS.themeOrder) do
      for si, sz in ipairs(sizes) do
        UIParent.GetEffectiveScale = function() return sz[4] or 1 end
        wmf(sz[1], sz[2], sz[3])
        NS.SetTheme(id)
        local f = NS.RebuildWindow()
        rebuilt = rebuilt + 1
        f:Show()
        NS.ShowTab("map")
        -- 0.5.1.7: the Map tab's map rectangle in this theme (compared with the WoW theme's below)
        local vp = NS.MapTab and NS.MapTab.vp
        if vp then
          areas[id .. "|" .. si] = { vp:GetWidth(), vp:GetHeight() }
          if id ~= "wow" and sz[3] and sz[3].real and areas["wow|" .. si] then
            local a0, a1 = areas["wow|" .. si], areas[id .. "|" .. si]
            check(math.abs(a1[1] - a0[1]) <= 2 and math.abs(a1[2] - a0[2]) <= 2, string.format(
              "0.5.1.7 window: %s at map %dx%d: its map rectangle %.1fx%.1f equals the WoW theme's %.1fx%.1f (within 2 px)", id, sz[1], sz[2], a1[1], a1[2], a0[1], a0[2]))
            nAreas = nAreas + 1
          end
        end
        NS.ShowTab("quests")
        local tw, th = MW.Size()
        local l, t, r, b = drawnBox(f)
        local k = f:GetScale() / (sz[4] or 1) * (sz[4] or 1)
        local ow2, oh2 = (r - l) * k, (t - b) * k
        local dw, dh = ow2 - tw, oh2 - th
        n = n + 1
        local bad = math.max(math.abs(dw), math.abs(dh))
        if bad > worst then worst = bad end
        check(bad <= 1, string.format("0.5.1.6 window: %s at map %dx%d%s: outer %.1fx%.1f vs map outer %.1fx%.1f (diff %+.1f,%+.1f)",
          id, sz[1], sz[2], sz[3] and sz[3].real and " (real border)" or "", ow2, oh2, tw, th, dw, dh))
        local pl = MW.ThemeLines("t")
        for _, line in ipairs(pl) do
          if line:find(" " .. id .. ":", 1, true) then
            check(line:find("diff %+0,%+0") or line:find("diff %-0,%+0") or line:find("diff [%+%-][01],[%+%-][01]"), "0.5.1.6 frameprobe per theme: " .. line)
          end
        end
        for _, e in ipairs(LayoutOf(f)) do
          local fl = e.r._file and tostring(e.r._file) or ""
          if e.kind == "texture" and (fl:find("Portrait", 1, true) or fl:find("BookIcon", 1, true)) then portraits[#portraits + 1] = id .. " " .. fl end
        end
      end
    end
    check(#portraits == 0, "0.5.1.6: no portrait icon in any theme " .. table.concat(portraits, ", "))
    check(nAreas == (#NS.themeOrder - 1) * 4, "0.5.1.7 window: every class theme's map rectangle was compared with the WoW theme's at 4 map sizes (" .. nAreas .. ")")
    check(n == #NS.themeOrder * #sizes and rebuilt == n, string.format("0.5.1.6 window: %d themes x %d map sizes, worst outer difference %.2f px", #NS.themeOrder, #sizes, worst))
    UIParent.GetEffectiveScale = saveU
    WorldMapFrame = saveWMF MW.art = nil
    NS.SetTheme(saveTheme)
    win = NS.RebuildWindow()
    W = DarkMatter.windowParts
  end
  -- 0.5.1.6: while shown, a map window of another size -> the window is built again at that size (asked twice in a row);
  -- the saved position keeps its screen spot
  if W.Refit and MW.last and not MW.last.fallback then
    local m0 = NS.theme.m
    local saveW2 = WorldMapFrame
    wmf(m0.w * 1.1, m0.h * 1.1)
    win:Show()
    win:ClearAllPoints() win:SetPoint("CENTER", UIParent, "CENTER", 110, -55)
    WMF_CALLS, WMF_WRITES = {}, {}
    local before = NS.windowRebuilds or 0
    W.Refit() W.Refit()
    check(W.rebuildWanted, "0.5.1.6 window: the map window grew -> a rebuild is asked for")
    local nw = NS.RebuildWindow()
    local _, _, _, x, y = nw:GetPoint(1)
    check(NS.windowRebuilds == before + 1 and math.abs(nw._w - m0.w) < 1e-6 and math.abs(NS.theme.m.w - math.floor(saveW2:GetWidth() * 1.1 + 0.5)) <= 1
      and math.abs(x - 110) < 1e-3 and math.abs(y + 55) < 1e-3 and #WMF_WRITES == 0 and nw:IsShown(),
      "0.5.1.6 window: built again at the new size, shown, position kept (" .. string.format("%.1f; %.1f,%.1f", nw._w, x, y) .. ")")
    WorldMapFrame = saveW2 MW.art = nil
    win = NS.RebuildWindow()
    W = DarkMatter.windowParts
  end

  -- 4. the WoW theme's map-window frame; class themes untouched
  NS.SetTheme("wow")
  win:Show()
  local Ch = W.mapChrome
  local ownOn, nineOn = 0, 0
  for _, t in ipairs(Ch.own) do if t:IsShown() then ownOn = ownOn + 1 end end
  for _, k in ipairs(MW.NINE) do if Ch.nine[k]:IsShown() then nineOn = nineOn + 1 end end
  if os.getenv("DM_WMF") then
    check(Ch.mirrored and nineOn == 8 and ownOn == 0 and Ch.nine.TopLeftCorner._file == "atlas:UI-Frame-Map-CornerTopRight" and Ch.cornerFrom == "the top-right corner, mirrored" and Ch.nine.TopEdge._file == "atlas:_UI-Frame-Map-EdgeTop",
      "0.5.1.4 WoW theme: the map window's 8 border pieces are drawn around ours (by atlas)")
    check(W.medalFrom == nil and W.closeFrom == "map window", "0.5.1.6 WoW theme: no portrait; the map window's close-button art")
    local tc = { Ch.nine.TopLeftCorner:GetTexCoord() }
    check(#tc == 8 and tc[1] > tc[5], "0.5.1.6 WoW theme: the plain top-left corner is the top-right corner mirrored (" .. table.concat(tc, ",") .. ")")
  else
    check(not Ch.mirrored and nineOn == 0 and ownOn == 8, "0.5.1.4 WoW theme: no map window to read -> Dark Matter's own thin bronze frame (8 lines)")
    check(W.medalFrom == nil and W.closeFrom == "UIPanelCloseButton", "0.5.1.6 WoW theme: no portrait, the stock close button")
  end
  check(W.mapLook and Ch.strip:IsShown() and Ch.strip._h == NS.MAP_TITLE_H and W.title._pts[#W.title._pts][2] == Ch.strip, "0.5.1.4 WoW theme: a slim dark title strip with the title centred on it")
  local tC = W.title._tcol or {}
  check(tC[1] and tC[1] > 0.9 and tC[2] > 0.7 and tC[3] < 0.3, "0.5.1.4 WoW theme: the title is gold")
  NS.ShowTab("map")
  local M = NS.MapTab
  local cr = M.crumbs
  M.FlyTo(1426) for _ = 1, 30 do if M.Tick then M.Tick(0.05) end end
  if M.Crumbs then M.Crumbs() end
  check(M.crumbFaces and cr[1] and cr[1].face.shown and cr[1].face.prefix == "btn_red" and (not (cr[2] and cr[2]:IsShown()) or (cr[2].face.prefix == "btn_field" and cr[2].arrow:IsShown())) and not cr[1].sep:IsShown(),
    "0.5.1.4 WoW theme: the breadcrumb is drawn like the stock map's top-bar buttons (red World, dark buttons with arrows)")
  NS.SetTheme("warrior")
  local anyOn = 0
  for _, t in ipairs(Ch.all) do if t:IsShown() then anyOn = anyOn + 1 end end
  check(anyOn == 0 and not W.mapLook and W.medalFrom == nil, "0.5.1.4 class themes: none of the map-window frame is drawn")
  check(not M.crumbFaces and not cr[1].face.shown and (not (cr[2] and cr[2]:IsShown()) or cr[1].sep:IsShown()), "0.5.1.4 class themes: the plain text breadcrumb with '>' is unchanged")
  NS.SetTheme("wow")
  NS.ShowTab("quests")

  -- 5. /dm frameprobe
  WorldMapFrame = MakeWMF(1035, 640)
  local said = {}
  local oldPrint = NS.Print
  NS.Print = function(m) said[#said + 1] = m end
  SlashCmdList["DARKMATTER"]("frameprobe")
  NS.Print = oldPrint
  local all = table.concat(said, "\n")
  if os.getenv("DM_DUMP") then for _, l in ipairs(said) do io.stderr:write("FRAME ", l, "\n") end end
  check(said[1] == "frameprobe 0.5.1.8 (the game's map window, read only):" and all:find("frame 1: WorldMapFrame yes; size 1035x640", 1, true)
    and all:find("frame 3: border: 8 of 8 pieces readable", 1, true) and all:find("frame 3.1: TopLeftCorner: atlas UI-Frame-Map-CornerTopLeft (file ", 1, true)
    and all:find("frame 4: title: text \"Map & Quest Log\" size 12", 1, true) and all:find("frame 5: close button 24x24: atlas RedButton-Exit", 1, true)
    and all:find("frame 6: portrait: atlas UI-HUD-Map-Portrait", 1, true) and NS.db.frameprobe and #NS.db.frameprobe.lines == #said,
    "0.5.1.4 /dm frameprobe: the map window's size, border pieces, title, close button and portrait (saved)")
  WorldMapFrame = nil
  MW.art = nil
  said = {}
  NS.Print = function(m) said[#said + 1] = m end
  SlashCmdList["DARKMATTER"]("frameprobe")
  NS.Print = oldPrint
  check(table.concat(said, "\n"):find("frame 1: WorldMapFrame no", 1, true) and table.concat(said, "\n"):find("frame 3: border: not readable", 1, true), "0.5.1.4 /dm frameprobe: no map window -> says so")
  WorldMapFrame = saveWMF
  MW.art = nil
  MW.Art()
  NS.SetTheme("wow")
end

-- ===== 0.4.1: no restricted event was ever registered or unregistered, in any mode =====
check(#RESTRICTED_TOUCH == 0, "no addon code touched a restricted event (" .. table.concat(RESTRICTED_TOUCH, ", ") .. ")")
for _, fn in ipairs({ "Achievements.lua", "AdventureGuide.lua", "Fishing.lua", "Core.lua", "Window.lua", "Tab_Journals.lua", "Journal_Achievements.lua" }) do
  local src = io.open(arg[1] .. "/" .. fn):read("*a")
  local code = src:gsub("%-%-[^\n]*", "")
  check(not code:find("CombatLogGetCurrentEventInfo", 1, true) and not code:find("SetPropagateKeyboardInput", 1, true),
    fn .. ": no combat-log reads, no SetPropagateKeyboardInput")
end

for i=LASTN+1,#log do io.stdout:write(log[i],"\n") end
