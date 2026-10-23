-- Dark Matter 0.5.2b: M and L open Dark Matter (the Map tab with the Quest Log panel); ALT-M and ALT-L open the game's
-- own world map and quest log. Override bindings owned by our own frame: they live only for this session and are never
-- written to the bindings file (never saved). Applied out of combat only (queued until combat ends). An option
-- (/dm keys off, or the Settings page) turns them off.
local _, NS = ...

local K = { applied = false }
NS.Keys = K

K.BINDS = {
  { key = "M", click = "DarkMatterKeyMap" },
  { key = "L", click = "DarkMatterKeyLog" },
  { key = "ALT-M", action = "TOGGLEWORLDMAP" },
  { key = "ALT-L", action = "TOGGLEQUESTLOG" },
}

local owner, regen
local function InCombat() return type(InCombatLockdown) == "function" and InCombatLockdown() == true end
function K.Wanted() return not (NS.db and NS.db.mlKeys == false) end

-- M / L: toggle Dark Matter on the Map tab with the Quest Log panel (L shows the panel's quest list)
function K.Press(which)
  local f = _G.DarkMatterFrame
  local onMap = f and f:IsShown() and NS.db and NS.db.tab == "map"
  local P = NS.QuestPanel
  if onMap and P and P.IsShown() then
    NS.ToggleWindow(false)
    return "closed"
  end
  NS.OpenOnMap(nil, which ~= "log") -- L shows the quest list; M keeps what the panel showed
  return "opened"
end

local function Build()
  if owner then return end
  owner = CreateFrame("Frame", "DarkMatterKeyOwner", UIParent)
  for _, b in ipairs(K.BINDS) do
    if b.click then
      local btn = CreateFrame("Button", b.click, UIParent)
      btn:Hide()
      btn:RegisterForClicks("AnyUp", "AnyDown")
      local which = b.key == "L" and "log" or "map"
      -- a key click can come as a press and a release: act once (on whichever comes first)
      btn:SetScript("OnClick", function(_, _, down)
        local now = (type(GetTime) == "function" and GetTime()) or 0
        if down == false and K.downAt and now - K.downAt < 1 then K.downAt = nil return end
        K.downAt = down and now or nil
        K.Press(which)
      end)
      K[which .. "Button"] = btn
    end
  end
  K.owner = owner
end

-- set (or clear) our override bindings; out of combat only, else queued until PLAYER_REGEN_ENABLED
function K.Apply()
  Build()
  if InCombat() then
    K.pending = true
    if not regen then
      regen = CreateFrame("Frame") -- private
      regen:SetScript("OnEvent", function(self)
        pcall(self.UnregisterEvent, self, "PLAYER_REGEN_ENABLED")
        if K.pending then K.pending = nil K.Apply() end
      end)
    end
    pcall(regen.RegisterEvent, regen, "PLAYER_REGEN_ENABLED")
    return "queued"
  end
  K.pending = nil
  if type(_G.ClearOverrideBindings) ~= "function" or type(_G.SetOverrideBinding) ~= "function" then return "noapi" end
  _G.ClearOverrideBindings(owner)
  K.applied = false
  if not K.Wanted() then return "off" end
  for _, b in ipairs(K.BINDS) do
    if b.click then
      if type(_G.SetOverrideBindingClick) == "function" then _G.SetOverrideBindingClick(owner, false, b.key, b.click, "LeftButton") end
    else
      _G.SetOverrideBinding(owner, false, b.key, b.action)
    end
  end
  K.applied = true
  return "on"
end
function K.Set(on)
  if NS.db then NS.db.mlKeys = on and true or false end
  return K.Apply()
end
function K.Start() return K.Apply() end
