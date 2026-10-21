-- /dm            toggle the window
-- /dm probe      print + save API/version probe to DarkMatterDB.probe
-- /dm reset      reset window position (and minimap button angle with "all")
local _, NS = ...

SLASH_DARKMATTER1 = "/dm"
SLASH_DARKMATTER2 = "/darkmatter"

local function Help()
  NS.Print("v" .. NS.version .. " commands:")
  print("  /dm  toggle the window")
  print("  /dm probe  check this client's APIs (saved to DarkMatterDB.probe)")
  print("  /dm raw  show/hide the raw call list in the probe window")
  print("  /dm blocked  last blocked function (with context and stack); /dm blocked clear")
  print("  /dm reset  reset window position   (/dm reset all: also minimap button)")
  print("  /dm minimap  show/hide the minimap button")
  print("  /dm icon  switch between the Dark Matter icon and a stock icon")
  print("  /dm options  open the Settings page")
  print("  /dm theme  list themes   /dm theme <name>  apply one   /dm theme next  cycle (saved, applies live)")
  print("  /dm fishcheck  compare fishing catalog names with the client's item names")
  print("  /dm tipdebug  log fishing tooltip placement (points/rects) to DarkMatterDB.tipdebug")
  print("  /dm agscan  Adventure Guide: LFG rows kept/rejected -> DarkMatterDB.agscan")
  print("  /dm questprobe  Quests: which quest log, reward and watch APIs this client has -> DarkMatterDB.questprobe")
  print("  /dm achprobe  Achievements: mode, game API counts + 3 samples, Dark Matter counts -> DarkMatterDB.achprobe")
end

SlashCmdList["DARKMATTER"] = function(msg)
  if not NS.db then NS.Print("not ready yet.") return end
  local cmd, rest = strmatch(strlower(strtrim(msg or "")), "^(%S*)%s*(.-)$")
  if cmd == "" or cmd == "toggle" then
    NS.ToggleWindow()
  elseif cmd == "show" then
    NS.ToggleWindow(true)
  elseif cmd == "hide" then
    NS.ToggleWindow(false)
  elseif cmd == "probe" then
    NS.RunProbe(false)
  elseif cmd == "blocked" then
    if rest == "clear" then
      NS.db.blockedLog = {}
      if type(NS.db.probe) == "table" then NS.db.probe.blocked = NS.db.blockedLog end
      NS.Print("blocked-action log cleared.")
    else
      local lines = NS.BlockedLines(4)
      NS.Print(lines[1])
      for i = 2, #lines do print(lines[i]) end
    end
  elseif cmd == "raw" then
    NS.showRaw = not NS.showRaw
    NS.Print("raw call list in the probe window: " .. (NS.showRaw and "on" or "off"))
    if NS.RefreshProbeWindow then NS.RefreshProbeWindow() end
  elseif cmd == "reset" then
    NS.ResetWindowPosition()
    if rest == "all" then NS.ResetMinimapButton() NS.Print("minimap button reset.") end
  elseif cmd == "minimap" then
    NS.SetMinimapButtonShown(NS.db.minimap.hide)
  elseif cmd == "icon" then
    NS.db.stockIcon = not NS.db.stockIcon
    NS.SetMinimapIcon()
    NS.Print(NS.db.stockIcon and "using the stock icon." or "using the Dark Matter icon.")
  elseif cmd == "theme" then
    if rest == "" or rest == "list" then
      local names = {}
      for _, id in ipairs(NS.themeOrder) do names[#names + 1] = (id == NS.theme.id) and ("[" .. id .. "]") or id end
      NS.Print("themes: " .. table.concat(names, ", ") .. "   (/dm theme <name> or /dm theme next)")
    else
      local id = (rest == "next") and NS.NextThemeId() or rest
      if NS.SetTheme(id) then NS.Print("theme: " .. NS.theme.name) else NS.Print("unknown theme \"" .. rest .. "\"; /dm theme lists them.") end
    end
  elseif cmd == "options" then
    NS.OpenOptions()
  elseif cmd == "agscan" then
    if NS.AG and NS.AG.ScanReport then
      local _, lines = NS.AG.ScanReport()
      for _, l in ipairs(lines or {}) do NS.Print(l) end
    end
  elseif cmd == "questprobe" then
    if NS.QL and NS.QL.ProbeReport then
      local _, lines = NS.QL.ProbeReport()
      for _, x in ipairs(lines or {}) do NS.Print(x) end
      NS.Print(NS.QL.WatchReport())
    end
  elseif cmd == "achprobe" then
    if NS.Ach and NS.Ach.ProbeReport then
      local _, lines = NS.Ach.ProbeReport()
      for _, l in ipairs(lines or {}) do NS.Print(l) end
    end
  elseif cmd == "tipdebug" then
    local on = NS.FishingToggleTipDebug()
    local td = NS.db.tipdebug or {}
    NS.Print("tipdebug " .. (on and "on: hover a fish row; placements are saved to DarkMatterDB.tipdebug (last + log) and summarized here." or
      ("off (" .. tostring(td.count or 0) .. " placement(s) logged; /reload to write SavedVariables).")))
  elseif cmd == "fishcheck" then
    local res = NS.FishingCheckCatalog()
    NS.Print(string.format("fishcheck: %d items checked, %d name mismatch(es), %d not cached yet (saved to DarkMatterDB.fishcheck).",
      res.checked, #res.mismatches, res.uncached))
    for i = 1, math.min(#res.mismatches, 15) do
      local m = res.mismatches[i]
      print(string.format("  %d: catalog \"%s\" / client \"%s\"", m.itemId, m.catalog, m.client))
    end
    if res.uncached > 0 then print("  run /dm fishcheck again in a few seconds to check the items still loading.") end
  else
    Help()
  end
end
