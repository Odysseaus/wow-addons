-- WoWThreat Sound: optional fire crackle (PLAN-visuals 4). Default OFF.
-- Bundled original 8 s loops (procedural, tools/gen_fire_sound.py) in three
-- loudness variants, played on the SFX channel only while in combat with the
-- meter showing fire, re-triggered every 8 s and stopped with a short fade.
local _, NS = ...

local SND = "Interface\\AddOns\\WoWThreat\\Sounds\\fire_"
local LOOP = 8.0
local handle, ticker, playing = nil, nil, false
NS.soundPlays = 0

local function Level()
  local top = NS.topRaw or 0
  if top >= 20000 then return "high" end
  if top >= 6000 then return "med" end
  return "low"
end

local function StopHandle()
  if handle and type(StopSound) == "function" then pcall(StopSound, handle, 500) end
  handle = nil
end

local function PlayOnce()
  if type(PlaySoundFile) ~= "function" then return end
  local prev = handle
  local ok, willPlay, h = pcall(PlaySoundFile, SND .. Level() .. ".ogg", "SFX")
  if ok and willPlay then
    handle = h
    NS.soundPlays = NS.soundPlays + 1
  end
  -- let the previous loop overlap briefly, then fade it
  if prev and type(StopSound) == "function" then
    if C_Timer and C_Timer.After then C_Timer.After(0.25, function() pcall(StopSound, prev, 300) end)
    else pcall(StopSound, prev, 300) end
  end
end

local function Wanted()
  local db = WoWThreatDB
  if not db or db.fireSound ~= true then return false end
  if NS.FireStyle and NS.FireStyle() == "off" then return false end
  local combat = NS.inCombat
  if type(UnitAffectingCombat) == "function" then combat = combat or UnitAffectingCombat("player") end
  return combat and (NS.MeterShowing and NS.MeterShowing()) and true or false
end

function NS.SoundPlaying() return playing end

function NS.UpdateSound()
  local want = Wanted()
  if want and not playing then
    playing = true
    PlayOnce()
    if C_Timer and C_Timer.NewTicker then
      ticker = C_Timer.NewTicker(LOOP - 0.25, function()
        if Wanted() then PlayOnce() else NS.UpdateSound() end
      end)
    end
  elseif not want and playing then
    playing = false
    if ticker then ticker:Cancel(); ticker = nil end
    StopHandle()
  end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("PLAYER_LEAVING_WORLD")
pcall(f.RegisterEvent, f, "UNIT_THREAT_LIST_UPDATE")
pcall(f.RegisterEvent, f, "UNIT_THREAT_SITUATION_UPDATE")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_REGEN_DISABLED" then
    NS.inCombat = true
    if NS.OnCombatStart then NS.OnCombatStart() end
  elseif event == "PLAYER_REGEN_ENABLED" then
    NS.inCombat = false
    if NS.OnCombatEnd then NS.OnCombatEnd() end
  elseif event == "PLAYER_LEAVING_WORLD" then
    NS.inCombat = false
  end
  NS.dirty = true
  if event ~= "UNIT_THREAT_LIST_UPDATE" and event ~= "UNIT_THREAT_SITUATION_UPDATE" then NS.UpdateSound() end
end)
