local T=0
local frames={}
local function obj(name) local o={scripts={},shown=true,scale=1} setmetatable(o,MT) return o end
MCACHE={}
MT={__index=function(t,k) if not k:match("^%u") then return nil end local f=MCACHE[k] if f then return f end f=function(self,a,b,c,d,e)
 if k=="GetStringWidth" then return 6*#(rawget(self,"text") or "") end
 if k=="GetFrameLevel" then return 1 end
 if k=="IsShown" then return self.shown end
 if k=="Show" then self.shown=true return end
 if k=="Hide" then self.shown=false return end
 if k=="SetScript" then self.scripts[a]=b return end
 if k=="GetScript" then return self.scripts[a] end
 if k=="SetText" then rawset(self,"text",a) return end
 if k=="SetAlpha" then self.alpha=a return end
 if k=="GetAlpha" then return self.alpha or 1 end
 if k=="SetSize" then self.w,self.h=a,b return end
 if k=="GetWidth" then return self.w or 1920 end
 if k=="GetHeight" then return self.h or 1080 end
 if k=="SetScale" then self.scale=a return end
 if k=="GetScale" or k=="GetEffectiveScale" then return self.scale end
 if k=="SetPoint" then self.p1,self.p2,self.p3,self.p4,self.p5=a,b,c,d,e self.npts=(self.npts or 0)+1 return end
 if k=="ClearAllPoints" then self.p1=nil return end
 if k=="GetPoint" then return self.p1,self.p2,self.p3,self.p4,self.p5 end
 if k=="GetLeft" then if self.p1=="TOPLEFT" then return self.p4 end return 500 end
 if k=="GetTop" then if self.p1=="TOPLEFT" then return self.p5 end return 600 end
 if k=="SetTexCoord" then self.tc1,self.tc2,self.tc3,self.tc4=a,b,c,d return end
 if k=="SetBlendMode" then self.blend=a return end
 if k=="SetVertexColor" then self.vc={a,b,c,d} return end
 if k=="GetRight" then return (self:GetLeft() or 0)+(self.w or 0) end
 if k=="SetMovable" then self.movable=a return end
 if k=="StartMoving" then self.moving=true return end
 if k=="StopMovingOrSizing" then self.moving=false return end
 if k=="SetValue" then self.val=a return end
 if (k=="CreateTexture" or k=="CreateFontString") and c~=nil and type(c)~="string" then error(k.."(): Couldn't find inherited node \""..tostring(c).."\"") end
 if k=="SetTexture" and type(a)=="string" then TEXPATHS=TEXPATHS or {} TEXPATHS[a]=true self.texpath=a end
 if k:match("^Create") then local c=obj() frames[#frames+1]=c return c end end MCACHE[k]=f return f end}
CreateFrame=function(_,name) local f=obj() frames[#frames+1]=f if name then _G[name]=f end return f end UIParent=obj() UIParent.w,UIParent.h=1920,1080
SlashCmdList={} GetTime=function() return T end
UnitExists=function(u) return u=="player" end UnitCanAttack=function() return false end UnitAffectingCombat=function() return false end
UnitDetailedThreatSituation=function() end
local combat=false InCombatLockdown=function() return combat end
local cbs={} EventRegistry={RegisterCallback=function(self,ev,fn) cbs[ev]=fn end}
EditModeManagerFrame={GetActiveLayoutInfo=function() return {layoutName="Modern"} end}
hooksecurefunc=function() end
WoWThreatDB=PRESET_DB or {}
IsInGroup=function() return INGROUP end
local MODE=os.getenv("MODE") or "proxy"
PROXY,FMT,SETVAL,NOTIFY=0,0,0,0
local reg={} local opened=nil local registeredCat=nil local buttons=0
local function newSetting(var,get,set,tbl,key,default)
  local s={var=var,cb=nil,val=default}
  function s:GetValue() if get then return get() end if tbl then return tbl[key] end return self.val end
  function s:SetValue(v) if not INTERNAL then SETVAL=SETVAL+1 end if set then set(v) elseif tbl then tbl[key]=v if self.cb then self.cb(nil,self,v) end else self.val=v if self.cb then self.cb(nil,self,v) end end end
  function s:SetValueChangedCallback(cb) self.cb=cb end
  function s:GetVariable() return self.var end
  reg[var]=s return s
end
if MODE~="none" then
Settings={VarType={Number="number",Boolean="boolean",String="string"}}
Settings.RegisterVerticalLayoutCategory=function(name) if MODE=="canvas" then error("no vertical") end local c={name=name} function c:GetID() return 42 end return c,{AddInitializer=function() buttons=buttons+1 end} end
Settings.RegisterCanvasLayoutCategory=function(f,name) local c={name=name} function c:GetID() return 43 end return c end
Settings.RegisterAddOnCategory=function(c) registeredCat=c end
Settings.OpenToCategory=function(id) opened=id end
if MODE=="proxy" then Settings.RegisterProxySetting=function(cat,var,vt,name,def,get,set) PROXY=PROXY+1 return newSetting(var,get,set) end end
Settings.RegisterAddOnSetting=function(cat,var,key,tbl,vt,name,def) if MODE=="old" then error("11.x sig") end return newSetting(var,nil,nil,tbl,key,def) end
if MODE=="old" then Settings.RegisterAddOnSetting=function(cat,name,var,vt,def) if type(var)~="string" then error("bad") end return newSetting(var,nil,nil,nil,nil,def) end end
Settings.CreateSliderOptions=function() return {SetLabelFormatter=function() FMT=FMT+1 end} end
Settings.NotifyUpdate=function() NOTIFY=NOTIFY+1 end
SettingsPanel={shown=false,IsShown=function(self) return self.shown end}
MinimalSliderWithSteppersMixin={Label={Right=1}}
Settings.CreateSlider=function() end Settings.CreateCheckbox=function() end Settings.CreateDropdown=function() end
Settings.CreateControlTextContainer=function() return {Add=function() end,GetData=function() return {} end} end
CreateSettingsButtonInitializer=function() return {} end
end

local played,stopped=0,0
PlaySoundFile=function(p,ch) played=played+1 LASTSND=p return true,played end
StopSound=function(h) stopped=stopped+1 end
local timers={}
C_Timer={After=function(d,fn) timers[#timers+1]={T+d,fn=fn} end,NewTicker=function(d,fn) local t={d=d,fn=fn,next=T+d} function t:Cancel() self.dead=true end timers[#timers+1]=t return t end}
UnitClass=function() return "Warlock","WARLOCK" end
RAID_CLASS_COLORS=nil

local NS={}
for _,f in ipairs{"Core.lua","Collector.lua","Stock.lua","Theme.lua","Fire.lua","Meter.lua","Sound.lua","EditMode.lua","Settings.lua"} do assert(loadfile(f))("WoWThreat",NS) end
for _,f in ipairs(frames) do local h=f.scripts.OnEvent if h then pcall(h,f,"ADDON_LOADED","WoWThreat") end end
local main=WoWThreatFrame
local function tick() for i=#timers,1,-1 do local t=timers[i] if t.fn and t[1] and T>=t[1] then table.remove(timers,i) t.fn() elseif t.next and not t.dead and T>=t.next then t.next=T+t.d t.fn() end end end
local function run(sec) for i=1,math.floor(sec*60) do T=T+1/60 for _,f in ipairs(frames) do local u=f.scripts.OnUpdate if u then u(f,1/60) end end tick() end end
local function event(ev) for _,f in ipairs(frames) do local h=f.scripts.OnEvent if h then h(f,ev) end end end
local fails=0 local function chk(c,msg) if c then print("ok  ",msg) else fails=fails+1 print("FAIL",msg) end end
local D=WoWThreatDB
chk(NS.settingsMode=="canvas","canvas settings built ("..tostring(NS.settingsMode)..")")
local cv=WoWThreatOptionsCanvas
local themeBtn
for _,w in ipairs(cv.widgets) do if w.text and w.Sync then w.Sync() local t=rawget(w.text,"text") or "" if t:find("^Theme: ") then themeBtn=w end end end
chk(themeBtn and themeBtn.text.text=="Theme: WoW","canvas Theme cycler shows WoW for a fresh install ("..tostring(themeBtn and themeBtn.text.text)..")")
themeBtn.scripts.OnClick() for i=#timers,1,-1 do local t=timers[i] if t.fn and t[1] then table.remove(timers,i) t.fn() end end
chk(WoWThreatDB.theme=="auto" and themeBtn.text.text=="Theme: Auto (by class)","canvas cycler: WoW -> Auto")
local seen={} for i=1,6 do themeBtn.scripts.OnClick() seen[#seen+1]=WoWThreatDB.theme end
chk(table.concat(seen,",")=="emberhall,ironforged,ursinegrove,dawnward,voidbound,wow","canvas cycler order: "..table.concat(seen,","))
print("fails",fails)
