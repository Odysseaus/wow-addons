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
  print("  /dm mapprobe  Map: which map, waypoint and drawing APIs this client has (read-only) -> DarkMatterDB.mapprobe")
  print("  /dm mapsweep  Map: check the map layers over every continent and zone (read-only; saved with the probes): a masks line, then OK or FLAGGED per continent")
  print("  /dm questmap  Quests on the map: status, waypoint and arrow APIs, GetQuestsOnMap, the game icons, the objective tracker (read-only) -> DarkMatterDB.questmap")
  print("  /dm autotrack on|off  zone auto-track: this zone's quests and kept ones tracked, the rest untracked (on by default)")
  print("  /dm trackorder on|off  keep the objective tracker in quest-log order (on by default)")
  print("  /dm keys on|off  M and L open Dark Matter (ALT-M / ALT-L the game's own map and quest log)")
  print("  /dm keepicon [pin|lock|star|auto]  the keep-tracked icon on the objective tracker")
  print("  /dm trackerprobe  the objective tracker, keep icons, pin counts and log vs tracker order (read-only) -> DarkMatterDB.trackerprobe")
  print("  /dm artprobe  WoW theme: which of the game's own textures/templates this client has (ok/missing) -> DarkMatterDB.artprobe")
  print("  /dm frameprobe  the game's map window: its size and the border, title and close textures it is drawn with -> DarkMatterDB.frameprobe")
  print("  /dm achprobe  Achievements: mode, game API counts + 3 samples, Dark Matter counts -> DarkMatterDB.achprobe")
  print("  every probe also keeps its last run, with the time, in DarkMatterDB.probeLog (read it after /reload)")
  print("  /dm testtoast  show a sample achievement toast (nothing is recorded)")
  print("  /dm parchment l r t b  WoW theme: crop of the parchment (QuestBG) inside its torn edge, 0..1   /dm parchment reset")
end

-- 0.5.2a.1: every /dm probe also keeps its last run, with a timestamp, in DarkMatterDB.probeLog[name] =
-- { time = "YYYY-MM-DD HH:MM:SS", version, lines = { ... } }. One run per probe (a new run replaces it); capped in size.
NS.PROBE_LOG_LINES, NS.PROBE_LOG_CHARS, NS.PROBE_LOG_MAX = 400, 400, 16
function NS.LogProbe(name, lines)
  if not (NS.db and type(name) == "string" and type(lines) == "table") then return end
  local log = type(NS.db.probeLog) == "table" and NS.db.probeLog or {}
  NS.db.probeLog = log
  local copy, n = {}, #lines
  for i = 1, math.min(n, NS.PROBE_LOG_LINES) do
    local s = tostring(lines[i])
    if #s > NS.PROBE_LOG_CHARS then s = s:sub(1, NS.PROBE_LOG_CHARS) .. "..." end
    copy[i] = s
  end
  if n > NS.PROBE_LOG_LINES then copy[#copy + 1] = "... " .. (n - NS.PROBE_LOG_LINES) .. " more lines not kept" end
  local at = 0 -- run order (kept across sessions): one past the newest entry
  for _, v in pairs(log) do if type(v) == "table" and type(v.at) == "number" and v.at > at then at = v.at end end
  at = at + 1
  log[name] = { time = date("%Y-%m-%d %H:%M:%S"), at = at, version = NS.version, lines = copy }
  -- at most PROBE_LOG_MAX probes: the oldest runs go first
  local names = {}
  for k, v in pairs(log) do if type(v) == "table" then names[#names + 1] = k else log[k] = nil end end
  if #names > NS.PROBE_LOG_MAX then
    table.sort(names, function(a, b) return (log[a].at or 0) < (log[b].at or 0) end)
    for i = 1, #names - NS.PROBE_LOG_MAX do log[names[i]] = nil end
  end
end
-- print a probe's lines and keep them in the probe log
local function Say(name, lines)
  for _, l in ipairs(lines or {}) do NS.Print(l) end
  NS.LogProbe(name, lines or {})
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
    local out = NS.RunProbe(false)
    if type(out) == "table" and type(out.summary) == "table" then NS.LogProbe("probe", out.summary) end
  elseif cmd == "blocked" then
    if rest == "clear" then
      NS.db.blockedLog = {}
      if type(NS.db.probe) == "table" then NS.db.probe.blocked = NS.db.blockedLog end
      NS.Print("blocked-action log cleared.")
    else
      local lines = NS.BlockedLines(4)
      NS.Print(lines[1])
      for i = 2, #lines do print(lines[i]) end
      NS.LogProbe("blocked", lines)
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
      Say("agscan", lines)
    end
  elseif cmd == "questprobe" then
    if NS.QL and NS.QL.ProbeReport then
      local _, lines = NS.QL.ProbeReport()
      local all = {}
      for _, x in ipairs(lines or {}) do all[#all + 1] = x end
      all[#all + 1] = NS.QL.WatchReport()
      Say("questprobe", all)
    end
  elseif cmd == "questmap" then
    if NS.QS and NS.QS.ProbeReport then
      Say("questmap", NS.QS.ProbeReport())
    end
  elseif cmd == "autotrack" then
    -- 0.5.2b: zone auto-track (on by default since 0.5.2b.1)
    if NS.Tracker then
      local on = rest == "on" or (rest ~= "off" and not (NS.db and NS.db.autoTrack))
      NS.Tracker.SetAuto(on)
      NS.Print("zone auto-track " .. (on and "on: this zone's quests and kept ones are tracked (after a flight lands)" or "off"))
    end
  elseif cmd == "trackorder" then
    -- 0.5.2b.1: the objective tracker in quest-log order (on by default)
    if NS.Tracker then
      local on = rest == "on" or (rest ~= "off" and NS.db and NS.db.trackOrder == false)
      NS.Tracker.SetOrder(on)
      NS.Print("tracker in quest-log order " .. (on and "on" or "off: the game's own order"))
    end
  elseif cmd == "keys" then
    if NS.Keys then
      local on = rest == "on" or (rest ~= "off" and NS.db and NS.db.mlKeys == false)
      local r = NS.Keys.Set(on)
      NS.Print("M / L keys " .. (on and "on" or "off") .. (r == "queued" and " (after combat)" or ""))
    end
  elseif cmd == "keepicon" then
    if NS.Tracker then
      local _, said = NS.Tracker.SetKeepIcon(rest)
      NS.Print(said)
    end
  elseif cmd == "trackerprobe" then
    if NS.Tracker then Say("trackerprobe", NS.Tracker.Report()) end
  elseif cmd == "mapprobe" then
    if NS.MapProbe and NS.MapProbe.Report then
      Say("mapprobe", NS.MapProbe.Report())
    end
  elseif cmd == "mapsweep" then
    -- 0.5.2b.3: the map layer check over every continent and zone at several zooms -> DarkMatterDB (read only)
    if NS.MapTab and NS.MapTab.Sweep then Say("mapsweep", NS.MapTab.Sweep()) end
  elseif cmd == "mapmask" then
    -- 0.5.2b.4: removed with the zone masks
    NS.Print("/dm mapmask was removed in 0.5.2b.4: no zone is cut with a mask any more (one feathered zone picture at a time)")
  elseif cmd == "artprobe" then
    Say("artprobe", NS.Stock.Report())
  elseif cmd == "frameprobe" then
    -- 0.5.1.4: what the game's map window is drawn with (read only) and the size Dark Matter took from it
    Say("frameprobe", NS.MapWindow.Report())
  elseif cmd == "achprobe" then
    if NS.Ach and NS.Ach.ProbeReport then
      local _, lines = NS.Ach.ProbeReport()
      Say("achprobe", lines)
    end
  elseif cmd == "testtoast" then
    if NS.Ach and NS.Ach.TestToast then
      local a = NS.Ach.TestToast()
      NS.Print("test toast: " .. tostring(a and a.name or "?") .. " (a preview; nothing was recorded).")
    end
  elseif cmd == "parchment" then
    local wow = NS.themes and NS.themes.wow
    local def = wow and wow.stockMedia and wow.stockMedia.detail and wow.stockMedia.detail.tc or { 0, 1, 0, 1 }
    if rest == "reset" then
      NS.db.parchTC = nil
    elseif rest ~= "" then
      local l, r, t, b = strmatch(rest, "^([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)$")
      l, r, t, b = tonumber(l), tonumber(r), tonumber(t), tonumber(b)
      if l and r and t and b and l >= 0 and r <= 1 and t >= 0 and b <= 1 and l < r and t < b then
        NS.db.parchTC = { l, r, t, b }
      else
        NS.Print("parchment: four numbers 0..1, left < right and top < bottom (e.g. /dm parchment 0.04 0.545 0.04 0.615).")
        return
      end
    end
    local c = NS.db.parchTC or def
    NS.Print(string.format("parchment crop: %.3f %.3f %.3f %.3f%s", c[1], c[2], c[3], c[4], NS.db.parchTC and " (yours)" or " (default)"))
    if NS.SetTheme and NS.theme then NS.SetTheme(NS.theme.id) end
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
