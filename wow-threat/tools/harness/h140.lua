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
if PRESET=="v2" then
  chk(D.version==3,"migrate v2->v3 version="..tostring(D.version))
  chk(D.rowHeight==30,"v2 default rowHeight 28 -> 30")
  chk(D.maxRows==7 and D.barWidth==300,"v2 user settings kept")
  chk(D.layout.default.scale==1.2 and D.layout.Modern.ux==100,"layouts kept")
  chk(D.theme=="wow" and D.themeWowMigrated==true and D.fireStyle=="fireplace" and D.fireSound==false and D.reducedEffects==false and D.animateFrame==true and D.fireSpeed==1 and D.flameOverflow==10,"v3 defaults filled")
  print("fails",fails) return
elseif PRESET=="v2custom" then
  chk(D.rowHeight==24,"v2 custom rowHeight 24 kept") print("fails",fails) return
end
chk(D.version==3 and D.rowHeight==30 and D.theme=="wow" and D.themeWowMigrated==true,"fresh install defaults (1.4.0: theme wow, migration flag set)") D.theme="auto"
-- auto theme
for c,t in pairs{WARRIOR="ironforged",DRUID="ursinegrove",PALADIN="dawnward",WARLOCK="voidbound",MAGE="emberhall",PRIEST="emberhall",ROGUE="emberhall",HUNTER="emberhall",SHAMAN="emberhall"} do chk(NS.AutoTheme(c)==t,"auto "..c.." -> "..t) end
chk(NS.ThemeId()=="voidbound","auto resolves via UnitClass (warlock)")
-- setters / sync
local function flush() for i=#timers,1,-1 do local t=timers[i] if t.fn and t[1] and t[1]<=T then table.remove(timers,i) t.fn() end end end
local function S(k) local real=reg["WoWThreat_"..k] return {GetValue=function() return real:GetValue() end,SetValue=function(_,v) real:SetValue(v) flush() end} end
S("theme"):SetValue("dawnward") chk(D.theme=="dawnward" and NS.ThemeId()=="dawnward","settings theme -> DB")
SlashCmdList.WOWTHREAT("theme ironforged") chk(MODE=="old" or S("theme"):GetValue()=="ironforged","slash theme -> settings")
SlashCmdList.WOWTHREAT("theme bogus") chk(D.theme=="ironforged","bad theme rejected")
SlashCmdList.WOWTHREAT("style classic") chk(MODE=="old" or S("fireStyle"):GetValue()=="classic","slash style -> settings")
cbs["EditMode.Enter"]() WoWThreatSelection.scripts.OnClick() local dlg=WoWThreatEditDialog
dlg.theme.scripts.OnClick(nil,"LeftButton") chk(D.theme=="ursinegrove" and (MODE=="old" or S("theme"):GetValue()=="ursinegrove"),"dialog theme cycler -> DB+settings ("..tostring(D.theme)..")")
dlg.style.scripts.OnClick(nil,"LeftButton") chk(D.fireStyle=="castbar","dialog style cycler classic -> castbar")
S("fireStyle"):SetValue("fireplace") chk(dlg.style.text.text=="Style: Fireplace","settings -> dialog style text: "..tostring(dlg.style.text.text))
S("theme"):SetValue("auto") chk(dlg.theme.text.text=="Theme: Auto (by class)","settings -> dialog theme text")
cbs["EditMode.Exit"]()
S("fireSpeed"):SetValue(1.27) chk(math.abs(D.fireSpeed-1.25)<1e-9,"fireSpeed step 0.05")
S("flameOverflow"):SetValue(40) chk(D.flameOverflow==14,"overflow clamped 14")
NS.SetOption("fireSpeed",1) NS.SetOption("flameOverflow",10)
-- rows / caps
local function liveRows() local out={} for _,f in ipairs(frames) do if f.tiles and f.shown and f.key then out[#out+1]=f end end return out end
local function count(rs) local tiles,glow,sparks,core=0,0,0,0 for _,r in ipairs(rs) do for _,t in ipairs(r.tiles) do if t.body.a.shown then tiles=tiles+1 end if t.glow.a.shown then glow=glow+1 end end for _,sp in ipairs(r.sparks) do if sp.tex.shown then sparks=sparks+1 end end if r.core.shown then core=core+1 end end return tiles,glow,sparks,core end
NS.SetOption("maxRows",5) SlashCmdList.WOWTHREAT("test") run(3)
local rs=liveRows() local t,g,sp,c=count(rs) print("party5 rows",#rs,"tiles",t,"glow",g,"sparks",sp,"core",c)
chk(#rs==5 and g==t and sp>0,"party: glow on all tiles, sparks on")
-- no stretch: tile width independent of pct, = 256 * inner/12
local bh=(D.rowHeight-14) local inner=bh-2*math.max(2,bh*6/32) local want=256*inner/12 local okw=true
for _,r in ipairs(rs) do local tw=r.tiles[1].body.a.w if math.abs(tw-want)>1e-6 then okw=false end end
chk(okw,"tile width fixed "..string.format("%.1f",want).." for every %% (crop, no stretch)")
local okc=true for _,r in ipairs(rs) do local cw=r.fireClip.w if cw>D.barWidth then okc=false end end chk(okc,"clip width <= bar width")
local top=rs[1] for _,r in ipairs(rs) do if r.rank==1 then top=r end end
chk(top.fireClip.h==inner,"1.3.0 clip height = bevel seat, no overflow ("..tostring(top.fireClip.h)..")")
NS.SetOption("maxRows",10) NS.SetOption("columns",4) SlashCmdList.WOWTHREAT("test raid40") run(3)
rs=liveRows() t,g,sp,c=count(rs) print("raid40 rows",#rs,"tiles",t,"glow",g,"sparks",sp,"core",c)
local maxRankSpark=0 for _,r in ipairs(rs) do for _,s in ipairs(r.sparks) do if s.tex.shown and r.rank>maxRankSpark then maxRankSpark=r.rank end end end
chk(#rs==40 and g==0,"raid40: no glow layer (>20 rows)")
chk(maxRankSpark<=10,"raid40: sparks only top 10 (max rank "..maxRankSpark..")")
local tex=0 for _,r in ipairs(rs) do for _,tt in ipairs(r.tiles) do if tt.body.a.shown then tex=tex+1 end end end
NS.SetOption("reducedEffects",true) run(0.5) rs=liveRows() t,g,sp,c=count(rs) print("reduced rows",#rs,"tiles",t,"glow",g,"sparks",sp,"core",c)
chk(t<=#rs and g==0 and sp==0 and c==0,"reduced: 1 tile, no glow/sparks/core")
chk(NS.ThemeGroupCount()>=0,"theme groups "..NS.ThemeGroupCount())
NS.SetOption("reducedEffects",false)
SlashCmdList.WOWTHREAT("style off") run(0.3) rs=liveRows() t=count(rs) chk(t==0,"style off: no fire tiles")
SlashCmdList.WOWTHREAT("style fireplace")
-- theme switch every id builds
local function boundsCheck(label)
  local W,H=NS.ThemeSize() local TOL=3 local worst=0 local bad=0
  for _,m in ipairs(NS._motion) do
    local x0,y0,x1,y1,disp
    if m.kind=="rotate" then local r=math.sqrt(m.w^2+m.h^2)/2 disp=2*r*math.sin(math.rad(m.deg)/2)
      x0,y0,x1,y1=m.cx-m.w/2-disp,m.cy-m.h/2-disp,m.cx+m.w/2+disp,m.cy+m.h/2+disp
      if disp>worst then worst=disp end
      if disp>TOL then bad=bad+1 print("  big rotate disp",disp) end
    elseif m.kind=="spin" then local r=math.sqrt(m.w^2+m.h^2)/2 x0,y0,x1,y1=m.cx-r,m.cy-r,m.cx+r,m.cy+r
    else local ex,ey=m.cx+m.dx,m.cy-m.dy x0=math.min(m.cx,ex)-m.w/2 x1=math.max(m.cx,ex)+m.w/2 y0=math.min(m.cy,ey)-m.h/2 y1=math.max(m.cy,ey)+m.h/2
      disp=math.sqrt(m.dx^2+m.dy^2) end
    if x0< -TOL or y0< -TOL or x1>W+TOL or y1>H+TOL then bad=bad+1 print(string.format("  OUT %s (%.1f,%.1f)-(%.1f,%.1f) frame %dx%d",m.kind,x0,y0,x1,y1,W,H)) end
  end
  chk(bad==0,string.format("%s: %d moving pieces stay inside %dx%d (max rock disp %.2f px)",label,#NS._motion,W,H,worst))
end
for _,sz in ipairs{"test","test raid40"} do
 if sz=="test raid40" then NS.SetOption("maxRows",10) NS.SetOption("columns",4) end
 SlashCmdList.WOWTHREAT(sz) run(0.3)
 for _,id in ipairs(NS.THEME_IDS) do SlashCmdList.WOWTHREAT("theme "..id) run(0.5) boundsCheck(id.." ("..sz..")") print("   anim groups",NS.ThemeGroupCount(),"rockers",NS.ThemeRockerCount()) end
end
-- 1.1.3: CreateTexture arg check + Test mode via Settings path
do local f=CreateFrame("Frame") local ok=pcall(f.CreateTexture,f,nil,"ARTWORK",0) chk(not ok,"stub CreateTexture errors on numeric 3rd arg") ok=pcall(f.CreateTexture,f,nil,"ARTWORK",nil,3) chk(ok,"stub CreateTexture accepts (nil,layer,nil,sub)") end
SlashCmdList.WOWTHREAT("test") if NS.forceTest then SlashCmdList.WOWTHREAT("test") end run(2)
for _,f in ipairs(frames) do if f.tiles then f.key=nil f.shown=false end end
local before=#timers
local okT,errT=pcall(function() (function(v) INTERNAL=true reg["WoWThreat_testMode"]:SetValue(v) INTERNAL=false end)(true) end)
chk(okT,"Settings path: Test mode on runs clean "..tostring(errT))
chk(#timers>before,"Settings path: refresh deferred via C_Timer.After(0)")
local okR,errR=pcall(run,1) chk(okR,"deferred refresh + rows/fire build clean "..tostring(errR))
chk(#liveRows()>0 and count(liveRows())>0,"test rows show with fire after Settings toggle")
okT=pcall(function() (function(v) INTERNAL=true reg["WoWThreat_testMode"]:SetValue(v) INTERNAL=false end)(false) end) run(1.5) chk(okT,"Settings path: Test mode off runs clean")
local _=(function(v) INTERNAL=true reg["WoWThreat_testMode"]:SetValue(v) INTERNAL=false end)(true) run(0.5)
-- 1.1.2 smooth playback: steady state, monotonic clock, speed change, cost
NS.SetOption("theme","emberhall") NS.SetOption("maxRows",5) NS.SetOption("columns","auto") NS.SetOption("reducedEffects",false)
SlashCmdList.WOWTHREAT("test") if not NS.forceTest then SlashCmdList.WOWTHREAT("test") end run(2)
local c0=NS.fireAnimCalls local p0=NS.fireAnimStarts local last=NS.FireClock() local mono=true local idxChanges=0 local r1=liveRows()[1] local lastI=r1 and r1.tiles[1].body.i
for i=1,600 do T=T+1/60 for _,f in ipairs(frames) do local u=f.scripts.OnUpdate if u then u(f,1/60) end end tick()
  local c=NS.FireClock() if c<last then mono=false end last=c
  if i==300 then NS.SetOption("fireSpeed",1.5) elseif i==450 then NS.SetOption("fireSpeed",0.5) end
  if r1 and r1.tiles[1].body.i~=lastI then idxChanges=idxChanges+1 lastI=r1.tiles[1].body.i end end
chk(NS.fireAnimCalls==c0,"steady state 10 s (threat changing, slides, poll, 2 speed changes): fire Stop/SetDuration (restarts) = "..(NS.fireAnimCalls-c0))
local maxStarts=0 for _,r in ipairs(liveRows()) do maxStarts=maxStarts+#r.sparks+1 end
chk(NS.fireAnimStarts-p0<=maxStarts,"no re-Play: first-start Plays "..(NS.fireAnimStarts-p0).." <= one per spark/core ("..maxStarts..")")
chk(mono,"shared fire clock advances monotonically across speed changes")
chk(idxChanges>=60,"frame index advanced "..idxChanges.." times in 10 s (8 fps at speed 1)")
NS.SetOption("fireSpeed",1)
local rs5=liveRows() local tb=rs5[1].tiles[1].body local seen=0 for i=1,30 do NS._FireDrive(nil,1/60) if tb.bShown and tb.fb>0 and tb.fa>0 then seen=seen+1 end end chk(rs5[1].fSmooth and seen>=20,"party: frames i and i+1 crossfading ("..seen.."/30 ticks both visible)")
local function cost(n) local t0=os.clock() for i=1,n do NS._FireDrive(nil,1/60) end return (os.clock()-t0)/n*1e6 end
print(string.format("driver cost party5: %.1f us/frame (%d active rows)",cost(2000),NS.FireActiveCount()))
NS.SetOption("maxRows",10) NS.SetOption("columns",4) SlashCmdList.WOWTHREAT("test raid40") run(2)
local stepOnly=true for _,r in ipairs(liveRows()) do if r.fSmooth then stepOnly=false end end
chk(stepOnly,"raid40: crossfade skipped (frame stepping)")
print(string.format("driver cost raid40: %.1f us/frame (%d active rows)",cost(2000),NS.FireActiveCount()))
-- 1.1.4: one fire (Ironforged) for every theme; no deleted file referenced
local IRON="Interface\\AddOns\\WoWThreat\\Textures\\Fire_Fireplace_ironforged"
NS.SetOption("maxRows",5) NS.SetOption("columns","auto") NS.SetOption("reducedEffects",false)
local fr,fg,fb
for _,id in ipairs(NS.THEME_IDS) do
  for _,st in ipairs{"fireplace","classic"} do
    SlashCmdList.WOWTHREAT("theme "..id) SlashCmdList.WOWTHREAT("style "..st) run(0.5)
    local r=liveRows()[1]
    if st=="fireplace" then chk(r and r.tiles[1].body.a.texpath==IRON,"theme "..id.." fireplace -> Ironforged sheet ("..tostring(r and r.tiles[1].body.a.texpath)..")") end
    local cr,cg,cb=NS.ThemeFireColor() if not fr then fr,fg,fb=cr,cg,cb end
    chk(cr==fr and cg==fg and cb==fb,"theme "..id.." "..st.." tint = Ironforged tint")
  end
end
SlashCmdList.WOWTHREAT("style fireplace")
local missing=0 local n=0
for path in pairs(TEXPATHS or {}) do
  if path:find("^Interface\\AddOns\\WoWThreat\\") then n=n+1
    local f=path:gsub("^Interface\\AddOns\\WoWThreat\\",""):gsub("\\","/")
    local h=io.open(f..".tga","rb") or io.open(f,"rb") if h then h:close() else missing=missing+1 print("  MISSING",path) end
  end
end
chk(missing==0,"all "..n.." texture paths used at runtime exist on disk")
-- sound
SlashCmdList.WOWTHREAT("test") SlashCmdList.WOWTHREAT("test") run(0.2)
UnitAffectingCombat=function() return true end NS.forceTest=true
event("PLAYER_REGEN_DISABLED") run(1) chk(played==0,"sound off by default: no PlaySoundFile")
NS.SetOption("fireSound",true) run(17) chk(played>=3,"sound on in combat, re-triggered: plays="..played)
UnitAffectingCombat=function() return false end
event("PLAYER_REGEN_ENABLED") local p=played run(10) chk(played==p and stopped>0 and not NS.SoundPlaying(),"sound stops after combat")
-- 1.1.5: Options search taint fix
chk(PROXY==0,"no RegisterProxySetting used (calls="..PROXY..")")
chk(buttons==0,"no custom initializers added to the Settings layout ("..buttons..")")
chk(FMT==0,"stock sliders: no SetLabelFormatter ("..FMT..")")
chk(NS.settingsMode=="vertical" or MODE~="proxy","vertical layout built with RegisterAddOnSetting")
local sv,nt=SETVAL,NOTIFY
SettingsPanel.shown=true
SlashCmdList.WOWTHREAT("theme ironforged") SlashCmdList.WOWTHREAT("style classic") NS.SetOption("scale",1.2,"editmode") NS.SetOption("maxRows",6,"editmode") run(0.5)
chk(SETVAL==sv,"/wtm + Edit Mode never SetValue the Blizzard setting ("..(SETVAL-sv)..")")
chk(NOTIFY==nt,"panel open: no NotifyUpdate ("..(NOTIFY-nt)..")")
SettingsPanel.shown=false
SlashCmdList.WOWTHREAT("theme dawnward") NS.SetOption("maxRows",5,"editmode") run(0.5)
chk(SETVAL==sv,"panel closed: still no SetValue")
chk(NOTIFY>nt,"panel closed: NotifyUpdate used ("..(NOTIFY-nt)..")")
if MODE~="old" and reg["WoWThreat_theme"] then chk(reg["WoWThreat_theme"]:GetValue()=="dawnward","backing table follows /wtm (theme="..tostring(reg["WoWThreat_theme"]:GetValue())..")") end
if reg["WoWThreat_maxRows"] then INTERNAL=true reg["WoWThreat_maxRows"]:SetValue(7) INTERNAL=false run(0.2) chk(NS.GetOption("maxRows")==7,"Options control -> option via callback (maxRows="..NS.GetOption("maxRows")..")") end
SlashCmdList.WOWTHREAT("style fireplace")
-- 1.2.0: Castbar fire
local CBT={"CB_Base","CB_Flow","CB_Veil","CB_Spark","CB_Ember"}
for _,n in ipairs(CBT) do local h=io.open("Textures/"..n..".tga","rb") chk(h~=nil,"texture exists: "..n) if h then h:close() end end
NS.SetOption("maxRows",5) NS.SetOption("columns","auto") NS.SetOption("reducedEffects",false) NS.SetOption("fireIntensity",0.8) NS.SetOption("fireSpeed",1)
SlashCmdList.WOWTHREAT("style castbar") chk(D.fireStyle=="castbar","/wtm style castbar -> DB")
do local okM=pcall(NS.MigrateDB) chk(okM and WoWThreatDB.fireStyle=="castbar","saved castbar survives MigrateDB (/reload)")
  WoWThreatDB.fireStyle="flamewall" pcall(NS.MigrateDB) chk(WoWThreatDB.fireStyle=="fireplace","unknown saved style -> fireplace") WoWThreatDB.fireStyle="castbar" D=WoWThreatDB NS.db=WoWThreatDB end
if NS.forceTest then SlashCmdList.WOWTHREAT("test") end SlashCmdList.WOWTHREAT("test") run(2)
local rows=liveRows() local r=rows[1]
chk(r and r.cb and r.cb.on,"castbar layers built and shown")
chk(r and r.cb.base.texpath:find("CB_Base") and r.cb.flow.blend=="ADD" and r.cb.veil.blend=="ADD" and r.cb.base.blend=="BLEND","blend: base BLEND, flow/veil ADD")
local tilesHidden=true for _,rr in ipairs(rows) do for j=1,#rr.tiles do if rr.tiles[j].body.a.shown then tilesHidden=false end end end
chk(tilesHidden,"fireplace tiles hidden in castbar style")
-- aspect: span = barW/(512*inner/64) and layer size = full bar
local cb=r.cb chk(math.abs(cb.span-cb.barW/(512*cb.inner/64))<1e-6 and cb.base.w==cb.barW and cb.base.h==cb.inner,string.format("aspect: span %.3f, layer %dx%d (full bar, cropped by clip)",cb.span,cb.base.w,cb.base.h))
-- seamless offsets advance; never reset by data updates
local u0,v0=cb.u,cb.v local c0=NS.fireAnimCalls local mono=true local lastV=cb.v local wraps=0
for i=1,600 do T=T+1/60 for _,f in ipairs(frames) do local u=f.scripts.OnUpdate if u then u(f,1/60) end end tick()
  if i%100==0 then NS.SetOption("fireIntensity", i%200==0 and 0.4 or 0.9) end
  if i==300 then NS.SetOption("fireSpeed",1.5) end end
chk(NS.fireAnimCalls==c0,"castbar 10 s (threat changes, intensity+speed changes): restarts = "..(NS.fireAnimCalls-c0))
chk(cb.u~=u0 and cb.v~=v0,"layers scrolled (u "..string.format("%.3f->%.3f",u0,cb.u)..")")
local uu=cb.u NS.FireUpdate(r,0.3,50,12,0,2,5) NS.FireUpdate(r,0.8,180,12,0,2,5) chk(cb.u==uu,"data update never resets scroll offsets")
chk(cb.flow.tc3==cb.v and cb.flow.tc4==cb.v+1,"flow scrolls in v via SetTexCoord")
local diff=false for i=2,#rows do if rows[i].cb and math.abs(rows[i].cb.u-cb.u)>0.01 then diff=true end end chk(diff,"random start offset per row")
NS.SetOption("fireSpeed",1)
-- speed: dt scales
local a=cb.uv NS._FireDrive(nil,1) local d1=(cb.uv-a)%1 NS.SetOption("fireSpeed",0.5) a=cb.uv NS._FireDrive(nil,1) local d2=(cb.uv-a)%1 NS.SetOption("fireSpeed",1)
chk(math.abs(d1-2*d2)<1e-6,string.format("Fire speed scales scroll (veil %.4f vs %.4f)",d1,d2))
-- intensity scales embers
NS.SetOption("fireIntensity",1) run(0.3) local n1=cb.nEmbers NS.SetOption("fireIntensity",0.2) run(0.3) local n2=cb.nEmbers NS.SetOption("fireIntensity",0.8)
chk(n1>n2 and n1<=6,"intensity scales embers ("..n1.." vs "..n2..")")
-- spark at leading edge
chk(rows[2].cb.sparkOn and rows[2].cb.spark.p1=="CENTER","leading-edge spark on (non-full bar)")
NS.FireUpdate(rows[1],1.0,200,12,0,1,5) chk(not rows[1].cb.sparkOn,"spark off at 100%")
-- reduced effects
NS.SetOption("reducedEffects",true) run(0.5) chk(not cb.veilOn and cb.nEmbers==0 and not cb.flicker,"Reduced effects: no veil, no embers, no flicker")
NS.SetOption("reducedEffects",false) run(0.5)
-- per-frame allocations (GC stopped)
run(1) collectgarbage("collect") collectgarbage("stop") local m0=collectgarbage("count")
for i=1,600 do NS._FireDrive(nil,1/60) end
local alloc=(collectgarbage("count")-m0)*1024 collectgarbage("restart")
chk(alloc<64,string.format("castbar driver: %d bytes allocated over 600 frames (%d active rows)",alloc,NS.FireActiveCount()))
local t0=os.clock() for i=1,2000 do NS._FireDrive(nil,1/60) end print(string.format("castbar driver cost party5: %.1f us/frame",(os.clock()-t0)/2000*1e6))
-- raid caps
NS.SetOption("maxRows",10) NS.SetOption("columns",4) SlashCmdList.WOWTHREAT("test raid40") run(2)
local capOK=true local nr=0 for _,rr in ipairs(liveRows()) do nr=nr+1 if rr.cb and rr.cb.on and (rr.cb.veilOn or rr.cb.nEmbers>0) then capOK=false end end
chk(capOK and nr>20,"raid40 ("..nr.." rows): no veil, no embers")
local t1=os.clock() for i=1,1000 do NS._FireDrive(nil,1/60) end print(string.format("castbar driver cost raid40: %.1f us/frame (%d rows)",(os.clock()-t1)/1000*1e6,NS.FireActiveCount()))
collectgarbage("collect") collectgarbage("stop") m0=collectgarbage("count") for i=1,300 do NS._FireDrive(nil,1/60) end alloc=(collectgarbage("count")-m0)*1024 collectgarbage("restart")
chk(alloc<64,string.format("raid40 castbar driver: %d bytes allocated over 300 frames",alloc))
-- switch back and forth
SlashCmdList.WOWTHREAT("style fireplace") run(0.5) local back=true for _,rr in ipairs(liveRows()) do if rr.cb and rr.cb.on then back=false end end chk(back and liveRows()[1].tiles[1].body.a.shown,"castbar -> fireplace: castbar layers hidden, tiles back")
SlashCmdList.WOWTHREAT("style castbar") run(0.3) chk(liveRows()[1].cb.on,"fireplace -> castbar again")
-- all themes
for _,id in ipairs(NS.THEME_IDS) do SlashCmdList.WOWTHREAT("theme "..id) run(0.3) chk(liveRows()[1].cb.on,"theme "..id.." castbar ok") end
-- stock settings only
local found=false for _,c in ipairs(NS.STYLE_CHOICE_LIST) do if c[1]=="castbar" then found=true end end chk(found,"Options dropdown lists Castbar fire (stock dropdown)")
chk(PROXY==0 and buttons==0 and FMT==0,"still stock settings only (no proxy/initializers/formatters)")
-- every runtime texture path exists
local miss=0 for path in pairs(TEXPATHS or {}) do if path:find("^Interface\\AddOns\\WoWThreat\\") then local f=path:gsub("^Interface\\AddOns\\WoWThreat\\",""):gsub("\\","/") local h=io.open(f..".tga","rb") or io.open(f,"rb") if h then h:close() else miss=miss+1 print("  MISSING",path) end end end
chk(miss==0,"all runtime texture paths exist (incl. castbar)")
SlashCmdList.WOWTHREAT("style fireplace")

-- ===== 1.3.0 checks =====
do
  local function lr() local out={} for _,f in ipairs(frames) do if f.tiles and f.shown and f.key then out[#out+1]=f end end table.sort(out,function(a,b) return (a.rank or 99)<(b.rank or 99) end) return out end
  NS.SetOption("maxRows",5) NS.SetOption("columns","auto") NS.SetOption("showFire",true)
  if not NS.forceTest then SlashCmdList.WOWTHREAT("test") end
  for _,st in ipairs{"fireplace","classic","castbar","gem","off"} do
    SlashCmdList.WOWTHREAT("style "..st) run(1)
    local ok=true for _,r in ipairs(lr()) do local b=r.bevel
      if not (b and b.L.shown and b.M.shown and b.R.shown and b.L.texpath:find("Bar_Bevel")) then ok=false end
      if r.seat.p1~="BOTTOMLEFT" or math.abs(r.seat.p4-r.bevB)>1e-9 then ok=false end
      if r.fireClip.shown and (math.abs(r.fireClip.w-r.seatW)>1e-6 or math.abs(r.fireClip.h-r.seatH)>1e-6 or math.abs(r.fireClip.p4-r.bevB)>1e-9) then ok=false end end
    if not ok then local r=lr()[1] print("DBG",#lr(),r.bevel and r.bevel.L.shown,r.bevel and r.bevel.L.texpath,r.seat.p1,r.seat.p4,r.bevB,r.fireClip.shown,r.fireClip.w,r.seatW,r.fireClip.h,r.seatH,r.fireClip.p4) end
    chk(ok and #lr()>=5,"1.3.0 bevel frame on every row ("..#lr().." rows) + contents clipped to seat: "..st)
  end
  SlashCmdList.WOWTHREAT("style gem") run(1)
  local rs=lr() local cols={}
  for i,r in ipairs(rs) do cols[i]=r.gem and r.gem.stone.vc end
  local function near(c,t) return c and math.abs(c[1]-math.min(1,t[1]/255*1.12))<1e-6 and math.abs(c[2]-math.min(1,t[2]/255*1.12))<1e-6 end
  chk(rs[1].gemOn and not rs[1].fireClip.shown,"gem shown, fire clip hidden")
  chk(near(cols[1],{176,16,14}) and near(cols[2],{226,98,14}) and near(cols[3],{214,150,28}) and near(cols[4],{100,58,18}),"gem rank colors red/orange/gold/bronze")
  chk(rs[1].gem.stone.texpath:find("Gem_Stone") and rs[1].gem.gloss.texpath:find("Gem_Gloss"),"gem textures")
  local x0=rs[1].gem.sheen.p4 run(0.5) chk(rs[1].gem.sheen.shown and rs[1].gem.sheen.p4~=x0,"gem sheen moves on shared clock")
  local c0=NS.fireAnimCalls run(3) chk(NS.fireAnimCalls==c0,"gem: no animation restarts")
  NS.SetOption("rowHeight",24) run(1) local h1=lr()[1].bevH NS.SetOption("rowHeight",32) run(1) local h2=lr()[1].bevH
  chk(h1==10 and h2==18 and math.abs(lr()[1].gem.h-(18-2*18*6/32))<1e-6,"bar height follows row height ("..tostring(h1).."/"..tostring(h2)..")")
  NS.SetOption("rowHeight",30)
  NS.SetOption("showFire",false) run(0.5) chk(lr()[1].gemOn and not lr()[1].gem.sheen.shown,"gem with Show fire off: stone stays, no sheen")
  NS.SetOption("showFire",true)
  WoWThreatDB.fireStyle="tongues" pcall(NS.MigrateDB) chk(WoWThreatDB.fireStyle=="fireplace","saved tongues -> fireplace")
  WoWThreatDB.fireStyle="gem" pcall(NS.MigrateDB) chk(WoWThreatDB.fireStyle=="gem","saved gem survives MigrateDB (/reload)")
  NS.db=WoWThreatDB
  local hasT,hasG=false,false for _,c in ipairs(NS.STYLE_CHOICE_LIST) do if c[1]=="tongues" then hasT=true end if c[1]=="gem" then hasG=true end end
  chk(hasG and not hasT,"style list has Gem, no Flame tongues")
  chk(NS.SetOption("fireStyle","tongues")==nil and WoWThreatDB.fireStyle=="gem","setting tongues rejected")
  chk(NS.VERSION=="1.4.0","version 1.4.0")
  local r,g,b=NS.ThemeFireColor() chk(math.abs(r-1)<1e-6 and math.abs(g-95/255)<1e-6 and math.abs(b-20/255)<1e-6,"fire tint = Ironforged mid 255,95,20")
  local okT=true for _,id in ipairs(NS.THEME_IDS) do SlashCmdList.WOWTHREAT("theme "..id) local r2,g2,b2=NS.ThemeFireColor() if r2~=r or g2~=g or b2~=b then okT=false end end
  chk(okT,"every theme uses Ironforged fire tint")
  chk(PROXY==0 and buttons==0 and FMT==0,"1.3.0 still stock settings only")
  local miss=0 for path in pairs(TEXPATHS or {}) do if path:find("^Interface\\AddOns\\WoWThreat\\") then local f=path:gsub("^Interface\\AddOns\\WoWThreat\\",""):gsub("\\","/") local h=io.open(f..".tga","rb") if h then h:close() else miss=miss+1 print("  MISSING",path) end end end
  chk(miss==0,"1.3.0 all runtime texture paths exist")
  SlashCmdList.WOWTHREAT("style fireplace")
end
-- ===== 1.4.0 checks: the 'wow' theme in the game's own art, default + one-time migration, /wtm artprobe =====
do
  local function lr() local out={} for _,f in ipairs(frames) do if f.tiles and f.shown and f.key then out[#out+1]=f end end table.sort(out,function(a,b) return (a.rank or 99)<(b.rank or 99) end) return out end
  local saved=WoWThreatDB
  -- migration: a saved 'auto' becomes 'wow' once; choosing Auto afterwards sticks; other themes are kept
  WoWThreatDB={version=3,theme="auto"} NS.MigrateDB()
  chk(WoWThreatDB.theme=="wow" and WoWThreatDB.themeWowMigrated==true,"1.4.0 migrate: saved auto -> wow once, flag set")
  WoWThreatDB.theme="auto" NS.MigrateDB() NS.MigrateDB()
  chk(WoWThreatDB.theme=="auto","1.4.0 migrate: Auto chosen after the migration sticks across reloads")
  WoWThreatDB={version=3,theme="voidbound"} NS.MigrateDB()
  chk(WoWThreatDB.theme=="voidbound" and WoWThreatDB.themeWowMigrated==true,"1.4.0 migrate: a chosen class theme is kept")
  WoWThreatDB={} NS.MigrateDB()
  chk(WoWThreatDB.theme=="wow","1.4.0 fresh install: theme wow")
  WoWThreatDB={version=3,theme="bogus"} NS.MigrateDB()
  chk(WoWThreatDB.theme=="wow","1.4.0 unknown saved theme -> wow")
  WoWThreatDB=saved NS.db=saved D=saved
  -- choices everywhere
  chk(NS.THEME_CHOICES.wow and NS.THEME_CHOICE_LIST[1][1]=="wow" and NS.THEME_CHOICE_LIST[1][2]=="WoW" and NS.THEME_CHOICE_LIST[2][1]=="auto","1.4.0 theme list: WoW first, Auto kept")
  local nIds=0 for _,id in ipairs(NS.THEME_IDS) do if NS.THEMES[id] then nIds=nIds+1 end end
  chk(NS.THEME_IDS[1]=="wow" and nIds==6,"1.4.0 six themes (wow + five class themes)")
  local said={} local oldPrint=print print=function(...) local t={} for i=1,select("#",...) do t[#t+1]=tostring((select(i,...))) end said[#said+1]=table.concat(t," ") end
  SlashCmdList.WOWTHREAT("help")
  SlashCmdList.WOWTHREAT("theme nonsense")
  print=oldPrint
  local all=table.concat(said,"\n")
  chk(all:find("theme <wow|auto|",1,true) and all:find("/wtm artprobe",1,true) and all:find("castbar|gem|off",1,true),"1.4.0 slash help lists wow, artprobe and gem")
  -- the wow theme draws the stock art
  NS.SetOption("maxRows",5) NS.SetOption("columns","auto") NS.SetOption("showFire",true) NS.SetOption("fireStyle","fireplace")
  SlashCmdList.WOWTHREAT("theme wow") if not NS.forceTest then SlashCmdList.WOWTHREAT("test") end run(1)
  chk(NS.ThemeId()=="wow","1.4.0 /wtm theme wow")
  local u=NS.stockUsed or {}
  chk(u.edge=="Interface\\Tooltips\\UI-Tooltip-Border" and u.bg=="Interface\\Tooltips\\UI-Tooltip-Background" and u.header=="Interface\\DialogFrame\\UI-DialogBox-Header","1.4.0 wow frame: tooltip border + background, dialog title plate")
  chk(TEXPATHS["Interface\\Tooltips\\UI-Tooltip-Border"] and TEXPATHS["Interface\\DialogFrame\\UI-DialogBox-Header"] and TEXPATHS["Interface\\TargetingFrame\\UI-StatusBar"],"1.4.0 stock textures set on regions")
  local rows=lr()
  chk(#rows>=5 and rows[1].bg.texpath=="Interface\\TargetingFrame\\UI-StatusBar","1.4.0 bar track is the stock status bar ("..tostring(rows[1] and rows[1].bg.texpath)..")")
  chk(NS.ThemeGroupCount()==0 and NS.ThemeRockerCount()==0,"1.4.0 wow frame is still (no theme animations)")
  SlashCmdList.WOWTHREAT("style off") run(0.5)
  rows=lr()
  chk(rows[1].fill.shown and rows[1].fill.texpath=="Interface\\TargetingFrame\\UI-StatusBar","1.4.0 plain fill (style off) is the stock status bar")
  SlashCmdList.WOWTHREAT("style fireplace") run(0.5)
  -- /wtm artprobe
  said={} print=function(...) local t={} for i=1,select("#",...) do t[#t+1]=tostring((select(i,...))) end said[#said+1]=table.concat(t," ") end
  SlashCmdList.WOWTHREAT("artprobe")
  print=oldPrint
  local longest=0 for _,l in ipairs(said) do longest=math.max(longest,#l) end
  chk(said[1] and said[1]:find("artprobe 1.4.0 (",1,true) and said[#said]=="artprobe: 4 ok, 0 missing","1.4.0 /wtm artprobe header + summary ("..tostring(said[#said])..")")
  chk(longest<=80,"1.4.0 /wtm artprobe short lines (longest "..longest..")")
  local ap=WoWThreatDB.artprobe
  chk(ap and ap.ok==4 and ap.missing==0 and #ap.items==4 and ap.version=="1.4.0","1.4.0 artprobe saved to WoWThreatDB.artprobe")
  for _,l in ipairs(said) do print("   "..l) end
  -- fallback: the client has none of the stock files
  GetFileIDFromPath=function() return nil end
  NS.Stock.ClearCache() NS.ThemeRefresh() run(0.5)
  u=NS.stockUsed or {}
  chk(next(u)==nil,"1.4.0 fallback: no stock texture used when the client lacks them")
  rows=lr()
  chk(NS.ThemeStyleBar(nil,nil)==false and rows[1].bg.shown~=false,"1.4.0 fallback: bar track back to the 1.3.0 black track")
  said={} print=function(...) local t={} for i=1,select("#",...) do t[#t+1]=tostring((select(i,...))) end said[#said+1]=table.concat(t," ") end
  SlashCmdList.WOWTHREAT("artprobe")
  print=oldPrint
  chk(said[1]:find("(file-ID lookup)",1,true) and said[#said]:find("artprobe: 0 ok, 4 missing",1,true) and all~=nil,"1.4.0 fallback: artprobe reports MISSING ("..tostring(said[#said])..")")
  local miss=0 for _,l in ipairs(said) do if l:find("^MISSING ") then miss=miss+1 end end
  chk(miss==4,"1.4.0 fallback: four MISSING lines")
  GetFileIDFromPath=function(p) return 1000+#p end
  NS.Stock.ClearCache() NS.ThemeRefresh() run(0.5)
  chk((NS.stockUsed or {}).edge~=nil,"1.4.0 file-ID lookup finds the stock art again")
  GetFileIDFromPath=nil NS.Stock.ClearCache()
  -- switching to a class theme and back
  SlashCmdList.WOWTHREAT("theme ironforged") run(0.5)
  chk(NS.ThemeId()=="ironforged" and NS.ThemeRockerCount()>0,"1.4.0 class theme still builds its animations after wow")
  rows=lr()
  chk(NS.ThemeStyleBar(nil,nil)==false,"1.4.0 class themes keep the black track")
  SlashCmdList.WOWTHREAT("theme wow") run(0.5)
  chk(NS.ThemeId()=="wow" and (NS.stockUsed or {}).edge~=nil,"1.4.0 back to wow")
  -- every fire style in the wow theme
  for _,st in ipairs{"fireplace","classic","castbar","gem","off"} do
    local okS=pcall(function() SlashCmdList.WOWTHREAT("style "..st) run(0.5) end)
    chk(okS and #lr()>=5,"1.4.0 wow theme with style "..st)
  end
  SlashCmdList.WOWTHREAT("style fireplace")
  chk(WoWThreatDB.fireStyle=="fireplace","1.4.0 fire style default unchanged (fireplace)")
  chk(PROXY==0 and buttons==0 and FMT==0,"1.4.0 still stock settings only")
end
print("probe:") NS.Probe()
print("fails",fails)
