-- MapShapes.lua (0.5.2b.5): the groundwork for zone shape masks.
--   /dm masktest   a visual proof that mask textures work on this client: four parchment squares side by side,
--                  1 no mask, 2 cut by the game's own round portrait mask, 3 cut by Dark Matter's shipped test mask
--                  (Media\masks\dm-masktest.tga, a soft five-point star), 4 cut by the game's zone highlight file
--                  at your position (diagnostic only). Toggles; lines saved with the probes.
--   /dm mapshapes  samples, for every zone of both continents, which zone the game says each point of the zone's
--                  rectangle belongs to (C_Map.GetMapInfoAtPosition on a 160-wide grid), a few milliseconds per
--                  frame, out of combat only. Saved to DarkMatterDB.mapshapes (written to disk at /reload or
--                  logout). tools/maskgen on the box turns that into the mask files that ship in 0.5.2b.6.
--   /dm mapshapes stop | status
-- Nothing here changes the map; it only reads the game's map data.
local _, NS = ...
local S = {}
NS.MapShapes = S

S.VERSION = 1
S.GRID = 160
S.BUDGET_MS = 4
S.STEP_NO_CLOCK = 200
S.ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
S.PARCH = "Interface\\AddOns\\DarkMatter\\Media\\wow-parchment"
S.ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
S.TEST = "Interface\\AddOns\\DarkMatter\\Media\\masks\\dm-masktest"

local function MD() return NS.MapData end
local function Out(msg) if NS.Print then NS.Print(msg) else print(msg) end end

---------------------------------------------------------------------------
-- /dm masktest
---------------------------------------------------------------------------
local function PlayerHighlight()
  local C = C_Map
  if not (C and type(C.GetMapHighlightInfoAtPosition) == "function" and type(C.GetBestMapForUnit) == "function") then
    return nil, "the game has no C_Map.GetMapHighlightInfoAtPosition"
  end
  local okm, here = pcall(C.GetBestMapForUnit, "player")
  local md = MD()
  local cont = okm and here and md and (md.Is(here, "continent") and here or (md.ZoneEntry(here) or {}).cont)
  if not cont then return nil, "no continent for your position" end
  local okp, pos = pcall(C.GetPlayerMapPosition, cont, "player")
  local x, y
  if okp and pos then
    if type(pos) == "table" and pos.GetXY then x, y = pos:GetXY() elseif type(pos) == "table" then x, y = pos.x, pos.y end
  end
  if not (x and y) then return nil, "no position on the continent" end
  local okh, fid = pcall(C.GetMapHighlightInfoAtPosition, cont, x, y)
  if okh and type(fid) == "number" and fid > 0 then return fid, string.format("file %d at %.3f, %.3f of map %d", fid, x, y, cont) end
  return nil, string.format("the game gave no highlight file at %.3f, %.3f of map %d", x, y, cont)
end

local function Panel(f, i, label)
  local p = CreateFrame("Frame", nil, f)
  p:SetSize(128, 128)
  p:SetPoint("TOPLEFT", f, "TOPLEFT", 16 + (i - 1) * 144, -40)
  local t = p:CreateTexture(nil, "ARTWORK")
  t:SetAllPoints(p)
  t:SetTexture(S.PARCH)
  t:SetVertexColor(1, 0.85, 0.55, 1)
  local fs = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetPoint("TOP", p, "BOTTOM", 0, -6)
  fs:SetWidth(136)
  fs:SetText(label)
  p.tex, p.label = t, fs
  return p
end

local function Mask(p, file)
  if not p.CreateMaskTexture then return false, "no CreateMaskTexture" end
  local ok, m = pcall(p.CreateMaskTexture, p)
  if not (ok and m) then return false, "CreateMaskTexture failed" end
  local ok2, r = pcall(m.SetTexture, m, file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  if not ok2 or r == false then return false, "the mask file did not load" end
  m:SetAllPoints(p)
  local ok3 = pcall(p.tex.AddMaskTexture, p.tex, m)
  if not ok3 then return false, "AddMaskTexture failed" end
  p.mask = m
  return true, "applied"
end

-- 0.5.2b.6.1: /dm masktest zone [name]: one zone's picture and its shape mask, drawn four ways side by side
S.ZW, S.ZH = 300, 200
local function MaskCount(t)
  if not (t and t.GetNumMaskTextures) then return nil end
  local ok, n = pcall(t.GetNumMaskTextures, t)
  return ok and n or nil
end
local function FindZone(name)
  local md = MD()
  if not md then return nil end
  name = (name or ""):lower():match("^%s*(.-)%s*$")
  if name == "" then
    local here = md.PlayerMap and md.PlayerMap()
    local z = here and md.ZoneOf(here)
    return z and md.ZoneEntry(z)
  end
  local starts
  for _, ct in ipairs(md.Continents()) do
    for _, z in ipairs(md.Zones(ct.id)) do
      local n = (z.name or ""):lower()
      if n == name then return z end
      if not starts and n:find(name, 1, true) == 1 then starts = z end
    end
  end
  return starts
end
-- the zone's tiles laid out in frame f at scale k (1 = the art's own px), order "last" (file, size, place, then the
-- mask, as /dm masktest) or "first" (the mask on the empty texture, as the map did in 0.5.2b.6)
local function ZoneTiles(f, art, k, m, order, filter)
  local list, carry = {}, 0
  for i, fid in ipairs(art.tex) do
    local col, row = (i - 1) % art.cols, math.floor((i - 1) / art.cols)
    local x, y = col * art.tw, row * art.th
    local w, h = math.min(art.tw, art.w - x), math.min(art.th, art.h - y)
    if w > 0 and h > 0 then
      local t = f:CreateTexture(nil, "ARTWORK")
      if m and order == "first" then pcall(t.AddMaskTexture, t, m) end
      t:SetSize(w * k, h * k)
      t:SetPoint("TOPLEFT", f, "TOPLEFT", x * k, -y * k)
      t:SetTexture(fid, nil, nil, filter)
      t:SetTexCoord(0, w / art.tw, 0, h / art.th)
      if m and order == "last" then pcall(t.AddMaskTexture, t, m) end
      list[#list + 1] = t
      if (MaskCount(t) or 0) >= 1 then carry = carry + 1 end
    end
  end
  return list, carry
end
local function ZoneMask(f, file)
  local ok, m = pcall(f.CreateMaskTexture, f)
  if not (ok and m) then return nil, "CreateMaskTexture failed" end
  local ok2, r = pcall(m.SetTexture, m, file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  if not ok2 or r == false then return nil, "the mask file did not load (" .. tostring(r) .. ")" end
  m:SetAllPoints(f)
  return m, "SetTexture " .. tostring(r)
end
function S.MaskTestZone(name)
  local md, M = MD(), NS.MapTab
  local z = FindZone(name)
  if not z then return { "masktest zone: no zone " .. (name ~= "" and ("'" .. name .. "'") or "for your position") .. " (try /dm masktest zone elwynn)" } end
  local art = md.Art(z.id)
  local file = M and M.MaskFile and M.MaskFile(z.id)
  if not art then return { "masktest zone: " .. z.name .. " has no picture" } end
  if not file then return { "masktest zone: " .. z.name .. " has no zone mask in Data_ZoneMasks.lua" } end
  if S.zoneFrame then S.zoneFrame:Hide() end
  local W, H = S.ZW, S.ZH
  local f = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  S.zoneFrame = f
  f:SetSize(16 + 4 * (W + 16), H + 90)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, -60)
  f:SetFrameStrata("DIALOG")
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
  end
  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", f, "TOP", 0, -12)
  title:SetText("Dark Matter zone mask test: " .. z.name .. " (/dm masktest zone again to close)")
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  local function Box(i, label)
    local p = CreateFrame("Frame", nil, f)
    p:SetSize(W, H)
    p:SetPoint("TOPLEFT", f, "TOPLEFT", 16 + (i - 1) * (W + 16), -36)
    local fs = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOP", p, "BOTTOM", 0, -6)
    fs:SetWidth(W + 12)
    fs:SetText(label)
    return p
  end
  local k = W / art.w
  local res = {}
  -- 1: the mask file alone over parchment (does the zone's mask load and cut?)
  local p1 = Box(1, "1 the zone mask on parchment")
  p1.tex = p1:CreateTexture(nil, "ARTWORK")
  p1.tex:SetAllPoints(p1)
  p1.tex:SetTexture(S.PARCH)
  p1.tex:SetVertexColor(1, 0.85, 0.55, 1)
  local ok1, why1 = Mask(p1, file)
  res[1] = (ok1 and "applied" or ("NOT applied: " .. tostring(why1))) .. ", carries " .. tostring(MaskCount(p1.tex))
  -- 2: the zone picture, mask added last (the /dm masktest way)
  local p2 = Box(2, "2 picture, mask last (masktest way)")
  local m2, w2 = ZoneMask(p2, file)
  local l2, c2 = ZoneTiles(p2, art, k, m2, "last")
  res[2] = string.format("%d/%d pieces carry the mask (%s)", c2, #l2, w2)
  -- 3: the map's 0.5.2b.6 way: a hidden frame at the art's size, mask first, trilinear, then scaled and shown
  local p3 = Box(3, "3 the 0.5.2b.6 map way (mask first)")
  local f3 = CreateFrame("Frame", nil, p3)
  f3:SetSize(art.w, art.h)
  f3:SetPoint("TOPLEFT", p3, "TOPLEFT", 0, 0)
  f3:Hide()
  local m3, w3 = ZoneMask(f3, file)
  local l3, c3 = ZoneTiles(f3, art, 1, m3, "first", "TRILINEAR")
  f3:SetScale(k)
  f3:Show()
  res[3] = string.format("%d/%d pieces carry the mask (%s)", c3, #l3, w3)
  -- 4: the 0.5.2b.6.1 map way: the same hidden scaled frame, the mask added last
  local p4 = Box(4, "4 the 0.5.2b.6.1 map way (mask last)")
  local f4 = CreateFrame("Frame", nil, p4)
  f4:SetSize(art.w, art.h)
  f4:SetPoint("TOPLEFT", p4, "TOPLEFT", 0, 0)
  f4:Hide()
  local m4, w4 = ZoneMask(f4, file)
  local l4, c4 = ZoneTiles(f4, art, 1, m4, "last", "TRILINEAR")
  f4:SetScale(k)
  f4:Show()
  res[4] = string.format("%d/%d pieces carry the mask (%s)", c4, #l4, w4)
  f:Show()
  local out = {
    string.format("masktest zone %s: %s (map %d, picture %dx%d, mask %s)", NS.version, z.name, z.id, art.w, art.h, file:match("[^\\]+$") or file),
    "masktest zone 1: " .. res[1] .. " -> the zone's outline cut from parchment",
    "masktest zone 2: " .. res[2] .. " -> the zone's own land only, no torn edge",
    "masktest zone 3: " .. res[3] .. " -> the same as 2 if the 0.5.2b.6 way worked",
    "masktest zone 4: " .. res[4] .. " -> the same as 2 (the map's way now)",
  }
  if M and M.MaskCheck then out[#out + 1] = "masktest zone map: " .. M.MaskCheck() end
  out[#out + 1] = "masktest zone: if 2 and 4 show the full rectangle too, masks do not cut zone pictures here: /dm mapmask off"
  return out
end

function S.MaskTest(arg)
  local word, rest = (arg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  if word and word:lower() == "zone" then
    if S.zoneFrame and S.zoneFrame:IsShown() and rest == "" then S.zoneFrame:Hide() return { "masktest zone: closed" } end
    return S.MaskTestZone(rest)
  end
  if S.testFrame and S.testFrame:IsShown() then
    S.testFrame:Hide()
    return { "masktest: closed" }
  end
  local f = S.testFrame
  if not f then
    f = CreateFrame("Frame", "DarkMatterMaskTest", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(16 + 4 * 144, 220)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    f:SetFrameStrata("DIALOG")
    if f.SetBackdrop then
      f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
      f:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
    end
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -12)
    title:SetText("Dark Matter mask test (/dm masktest again to close)")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    f.close = close
    f.p = {
      Panel(f, 1, "1 no mask: a square"),
      Panel(f, 2, "2 game round mask: a circle"),
      Panel(f, 3, "3 Dark Matter mask: a soft star"),
      Panel(f, 4, "4 zone highlight (diagnostic)"),
    }
    S.testFrame = f
    f.res = {}
    f.res[2] = { Mask(f.p[2], S.ROUND) }
    f.res[3] = { Mask(f.p[3], S.TEST) }
    local fid, why = PlayerHighlight()
    if fid then f.res[4] = { Mask(f.p[4], fid) } f.res[4][3] = why
    else f.res[4] = { false, why } f.p[4].tex:SetVertexColor(0.3, 0.3, 0.3, 1) end
  end
  f:Show()
  local r = f.res
  local function R(i)
    local x = r[i]
    if x[1] then return "applied" .. (x[3] and " (" .. x[3] .. ")" or "") end
    return "NOT applied: " .. tostring(x[2])
  end
  return {
    "masktest " .. NS.version .. ": four parchment squares in a window above the middle of the screen",
    "masktest 1: no mask -> you should see a plain square",
    "masktest 2: round game mask " .. R(2) .. " -> you should see a circle",
    "masktest 3: Dark Matter mask " .. R(3) .. " -> a five-point star with soft edges",
    "masktest 4: zone highlight " .. R(4) .. " -> your zone's outline (diagnostic only)",
    "masktest: if 3 is a full square or blank, masks from the addon do not load (tell me which)",
  }
end

---------------------------------------------------------------------------
-- /dm mapshapes
---------------------------------------------------------------------------
-- one row of zone ids -> run-length text: a letter per legend entry ('.' = no zone), a count after it when > 1
function S.Encode(row, legend, index)
  local out, prev, n = {}, nil, 0
  local function Flush()
    if prev == nil then return end
    out[#out + 1] = prev .. (n > 1 and tostring(n) or "")
  end
  for i = 1, #row do
    local id = row[i]
    local ch = "."
    if id then
      local k = index[id]
      if not k then
        legend[#legend + 1] = id
        k = #legend
        index[id] = k
      end
      ch = k <= #S.ALPHABET and S.ALPHABET:sub(k, k) or "?"
    end
    if ch == prev then n = n + 1 else Flush() prev, n = ch, 1 end
  end
  Flush()
  return table.concat(out)
end
function S.Decode(text, legend)
  local row = {}
  for ch, num in text:gmatch("([%a%.%?])(%d*)") do
    local k = S.ALPHABET:find(ch, 1, true)
    local id = k and legend[k] or false
    for _ = 1, (num ~= "" and tonumber(num) or 1) do row[#row + 1] = id end
  end
  return row
end

local function Clock() return type(debugprofilestop) == "function" and debugprofilestop() or nil end

-- the zone the game names at continent point x, y (cities as themselves, sub-maps folded into their zone)
local function ZoneAt(cont, zones, x, y)
  local ok, info = pcall(C_Map.GetMapInfoAtPosition, cont, x, y)
  local id = ok and type(info) == "table" and tonumber(info.mapID)
  if not id then return nil end
  if zones[id] then return id end
  local up = MD().ZoneOf(id)
  if up and zones[up] then return up end
  return nil
end

local function Jobs()
  local md = MD()
  local jobs = {}
  for _, ct in ipairs(md.Continents()) do
    local zones = {}
    for _, z in ipairs(md.Zones(ct.id)) do zones[z.id] = z end
    for _, z in ipairs(md.Zones(ct.id)) do
      if not md.IsCityID(z.id) then -- 0.5.2b.6: every zone but the six capitals (0.5.2b.5 skipped Redridge, Moonglade by size)
        local art = md.Art(z.id)
        local W = S.GRID
        local H = math.max(8, math.floor(W * ((art and art.w > 0) and art.h / art.w or 2 / 3) + 0.5))
        jobs[#jobs + 1] = { cont = ct.id, contName = ct.name, zones = zones, z = z, W = W, H = H }
      end
    end
  end
  return jobs
end

function S.Status()
  local run = S.run
  if run then
    return string.format("mapshapes: running, zone %d/%d (%s), %d points so far%s", run.j, #run.jobs,
      run.jobs[run.j] and run.jobs[run.j].z.name or "?", run.samples, run.paused and "; paused in combat" or "")
  end
  local d = NS.db and NS.db.mapshapes
  if type(d) == "table" then
    return string.format("mapshapes: %s %d zones, %d points (%s); /reload writes it to disk", d.done and "done:" or "unfinished:", d.zonesDone or 0, d.samples or 0, tostring(d.when))
  end
  return "mapshapes: not run yet (/dm mapshapes)"
end

function S.Stop()
  if not S.run then return "mapshapes: not running" end
  S.run = nil
  if S.driver then S.driver:SetScript("OnUpdate", nil) end
  return "mapshapes: stopped; what was sampled stays in DarkMatterDB.mapshapes (/dm mapshapes starts over)"
end

local function Finish(run)
  local d = run.data
  d.done = true
  d.seconds = math.floor((GetTime() - run.t0) * 10 + 0.5) / 10
  S.run = nil
  if S.driver then S.driver:SetScript("OnUpdate", nil) end
  local line = string.format("mapshapes done: %d zones, %d points in %.1f s -> DarkMatterDB.mapshapes; now /reload", d.zonesDone, d.samples, d.seconds)
  Out(line)
  if NS.LogProbe then NS.LogProbe("mapshapes", { "Dark Matter " .. NS.version .. " mapshapes", line }) end
end

-- sample until the time budget for this frame is spent (or `steps` points with no clock)
function S.Step(budgetMs)
  local run = S.run
  if not run then return end
  if InCombatLockdown and InCombatLockdown() then
    if not run.paused then run.paused = true Out("mapshapes: paused (combat); it goes on by itself after combat") end
    return
  end
  if run.paused then run.paused = false Out("mapshapes: going on") end
  local t0 = Clock()
  local left = S.STEP_NO_CLOCK
  local budget = budgetMs or S.BUDGET_MS
  while true do
    local job = run.jobs[run.j]
    if not job then Finish(run) return end
    local z = job.z
    if not job.rec then
      job.rec = { name = z.name, r = { z.r[1], z.r[2], z.r[3], z.r[4] }, w = job.W, h = job.H, legend = {}, rows = {}, own = 0 }
      job.index, job.row, job.i = {}, {}, 0
      local c = run.data.conts[job.cont] or { name = job.contName, zones = {} }
      run.data.conts[job.cont] = c
      c.zones[z.id] = job.rec
    end
    local rec = job.rec
    local y = #rec.rows
    local i = job.i
    local r = z.r
    local px = r[1] + (i + 0.5) / job.W * (r[2] - r[1])
    local py = r[3] + (y + 0.5) / job.H * (r[4] - r[3])
    local id = ZoneAt(job.cont, job.zones, px, py)
    job.row[i + 1] = id or false
    if id == z.id then job.own = (job.own or 0) + 1 end
    run.samples = run.samples + 1
    job.i = i + 1
    if job.i >= job.W then
      rec.rows[#rec.rows + 1] = S.Encode(job.row, rec.legend, job.index)
      job.row, job.i = {}, 0
      if #rec.rows >= job.H then
        rec.own = math.floor((job.own or 0) / (job.W * job.H) * 1000 + 0.5) / 1000
        run.data.zonesDone = run.data.zonesDone + 1
        run.data.samples = run.samples
        Out(string.format("mapshapes %d/%d: %s (%dx%d, %d%% its own land)", run.j, #run.jobs, z.name, job.W, job.H, math.floor(rec.own * 100 + 0.5)))
        job.index, job.row, job.zones = nil, nil, nil
        run.j = run.j + 1
      end
    end
    run.data.samples = run.samples
    if t0 then
      if Clock() - t0 >= budget then return end
    else
      left = left - 1
      if left <= 0 then return end
    end
  end
end

function S.Start(grid)
  if S.run then return { S.Status() } end
  if InCombatLockdown and InCombatLockdown() then return { "mapshapes: not in combat; try again after the fight" } end
  if not (C_Map and type(C_Map.GetMapInfoAtPosition) == "function") then return { "mapshapes: this client has no C_Map.GetMapInfoAtPosition; nothing to sample" } end
  if not (NS.db and MD()) then return { "mapshapes: Dark Matter is not loaded yet" } end
  S.GRID = grid or S.GRID
  local jobs = Jobs()
  local data = { version = S.VERSION, addon = NS.version, when = date("%Y-%m-%d %H:%M:%S"), grid = S.GRID, done = false, samples = 0, zonesDone = 0, zones = #jobs, conts = {} }
  NS.db.mapshapes = data
  local total = 0
  for _, j in ipairs(jobs) do total = total + j.W * j.H end
  S.run = { jobs = jobs, j = 1, samples = 0, data = data, t0 = GetTime() }
  local f = S.driver or CreateFrame("Frame")
  S.driver = f
  f:SetScript("OnUpdate", function() S.Step() end)
  return { string.format("mapshapes: sampling %d zones on %d points (grid %d wide), a few ms per frame; stay out of combat. Done line follows.", #jobs, total, S.GRID) }
end

function S.Slash(rest)
  rest = rest or ""
  if rest == "stop" then return { S.Stop() } end
  if rest == "status" then return { S.Status() } end
  local g = tonumber(rest)
  if rest ~= "" and not (g and g >= 16 and g <= 512) then return { "mapshapes: /dm mapshapes [stop | status]" } end
  return S.Start(g and math.floor(g))
end
