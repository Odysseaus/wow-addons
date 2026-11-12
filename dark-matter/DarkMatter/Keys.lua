-- Dark Matter 0.5.2b: M and L open Dark Matter (0.5.2b.10: M the Map tab, L the Quests tab); ALT-M and ALT-L open the game's
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

-- 0.5.2b.28: M and L both toggle Map & Quest Logs. Either key closes it when it is open.
-- Opening centres on you. ALT-M and ALT-L are unchanged (the stock map and stock quest log).
function K.Press(which)
  local f = _G.DarkMatterFrame
  local shown = f and f.IsShown and f:IsShown()
  if shown then
    NS.ToggleWindow(false)
    return "closed"
  end
  NS.OpenOnMap(nil, true)
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
      -- a key click can come as a press and a release: act once. M and L keep separate timers,
      -- so alternating the two keys is not swallowed.
      btn:SetScript("OnClick", function(_, _, down)
        local now = (type(GetTime) == "function" and GetTime()) or 0
        K.downAtBy = K.downAtBy or {}
        local prev = K.downAtBy[which]
        if down == false and prev and now - prev < 1 then K.downAtBy[which] = nil return end
        K.downAtBy[which] = (down ~= false) and now or nil
        local f = _G.DarkMatterFrame
        local before = f and f.IsShown and f:IsShown()
        local result = K.Press(which)
        if K.probeArmed then
          K.probeArmed = nil
          local after = f and f.IsShown and f:IsShown()
          local line = string.format("keyprobe hit key=%s down=%s press=%s shownBefore=%s shownAfter=%s ownerShown=%s",
            which == "log" and "L" or "M", tostring(down), tostring(result), tostring(before and true or false), tostring(after and true or false),
            tostring(K.owner and K.owner.IsShown and K.owner:IsShown() and true or false))
          K.lastHit = line
          if NS.Print then NS.Print(line) end
          if NS.LogProbe then NS.LogProbe("keyprobe", { line }) end
        end
      end)
      K[which .. "Button"] = btn
    end
  end
  K.owner = owner
end

-- true when this key still runs our button. GetBindingAction's second argument asks for the override.
function K.Bound(key, click)
  if type(_G.GetBindingAction) ~= "function" then return true end
  local ok, act = pcall(_G.GetBindingAction, key, true)
  if not ok or type(act) ~= "string" or act == "" then return false end
  return act:find(click, 1, true) ~= nil
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
  local done = {}
  for _, b in ipairs(K.BINDS) do
    done[b.key] = true
    if b.click then
      if type(_G.SetOverrideBindingClick) == "function" then _G.SetOverrideBindingClick(owner, false, b.key, b.click, "LeftButton") end
    else
      _G.SetOverrideBinding(owner, false, b.key, b.action)
    end
  end
  -- 0.5.2b.10: any other key bound to the game's map / quest log opens Dark Matter too (ALT-M / ALT-L stay the game's)
  if type(_G.GetBindingKey) == "function" and type(_G.SetOverrideBindingClick) == "function" then
    for action, click in pairs({ TOGGLEWORLDMAP = "DarkMatterKeyMap", TOGGLEQUESTLOG = "DarkMatterKeyLog" }) do
      local keys = { pcall(_G.GetBindingKey, action) }
      if table.remove(keys, 1) then
        for _, key in ipairs(keys) do
          if type(key) == "string" and not done[key] then
            done[key] = true
            _G.SetOverrideBindingClick(owner, false, key, click, "LeftButton")
          end
        end
      end
    end
  end
  K.applied = true
  return "on"
end
function K.Set(on)
  if NS.db then NS.db.mlKeys = on and true or false end
  return K.Apply()
end
-- 0.5.2b.10: re-apply when the player rebinds (UPDATE_BINDINGS); our own override changes can fire it too, so ignore
-- the ones that come while we are applying
local busy, again
local Apply0 = K.Apply
function K.Apply(...)
  if busy then again = true return "busy" end
  busy = true
  local ok, r = pcall(Apply0, ...)
  busy = false
  if not ok then error(r, 0) end
  return r
end
-- 0.5.2b.27: bindings are session overrides. A loading screen, a rebind, or a combat boundary can clear them,
-- and an UPDATE_BINDINGS that arrives while we are applying used to be ignored. Put them back out of combat.
-- 0.5.2b.29: one read of the bindings. Does not change M or L. The next real click, if it arrives, prints what it did.
function K.ProbeArm()
  K.probeArmed = true
  K.lastHit = nil
  local function act(key)
    if type(_G.GetBindingAction) ~= "function" then return "noapi" end
    local ok, a = pcall(_G.GetBindingAction, key, true)
    if not ok or type(a) ~= "string" then return "" end
    return a
  end
  local function shown(f) return type(f) == "table" and f.IsShown and f:IsShown() and true or false end
  return {
    string.format("keyprobe armed bindM=%s bindL=%s ownerShown=%s btnMShown=%s btnLShown=%s",
      act("M"), act("L"), tostring(shown(K.owner)), tostring(shown(K.mapButton)), tostring(shown(K.logButton))),
  }
end
function K.Ensure()
  if not K.Wanted() then return K.Apply() end
  if K.applied and K.Bound("M", "DarkMatterKeyMap") and K.Bound("L", "DarkMatterKeyLog") then return "on" end
  return K.Apply()
end
local watch
function K.Start()
  if not watch then
    watch = CreateFrame("Frame") -- private
    local acc = 0
    watch:SetScript("OnEvent", function(_, ev)
      if busy then again = true return end
      if ev == "PLAYER_REGEN_ENABLED" and K.pending then K.pending = nil end
      K.Apply()
    end)
    watch:SetScript("OnUpdate", function(_, dt)
      acc = acc + (dt or 0)
      if again and not busy then again = nil K.Apply() end
      if acc < 2 then return end
      acc = 0
      if K.Wanted() and not InCombat() then K.Ensure() end
    end)
    pcall(watch.RegisterEvent, watch, "UPDATE_BINDINGS")
    pcall(watch.RegisterEvent, watch, "PLAYER_ENTERING_WORLD")
    pcall(watch.RegisterEvent, watch, "PLAYER_REGEN_ENABLED")
    pcall(watch.RegisterEvent, watch, "ZONE_CHANGED_NEW_AREA")
  end
  return K.Apply()
end
