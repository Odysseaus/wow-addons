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

-- 0.5.2b.10: M toggles the Map tab, L the Quests tab: the same key on its own tab closes the window, else that tab opens
function K.Press(which)
  local f = _G.DarkMatterFrame
  local tab = which == "log" and "quests" or "map"
  if f and f:IsShown() and NS.db and NS.db.tab == tab then
    NS.ToggleWindow(false)
    return "closed"
  end
  if tab == "map" then
    NS.OpenOnMap(nil, true) -- shows the window on the Map tab (opens at your map, like the game's)
  else
    NS.ToggleWindow(true)
    NS.ShowTab("quests")
  end
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
local busy
local Apply0 = K.Apply
function K.Apply(...)
  if busy then return "busy" end
  busy = true
  local ok, r = pcall(Apply0, ...)
  busy = false
  if not ok then error(r, 0) end
  return r
end
local watch
function K.Start()
  if not watch then
    watch = CreateFrame("Frame") -- private
    watch:SetScript("OnEvent", function() K.Apply() end)
    pcall(watch.RegisterEvent, watch, "UPDATE_BINDINGS")
  end
  return K.Apply()
end
