-- Box tests for the 1.2.26 review's fixes in files no other suite loads (Map/Pins, Friends, News, Stitch, Close,
-- Nav, Paint, Sketch; API.lua; Objectives' tracker pins). Lua 5.1.
-- Run: lua valhalla/tests/review/fixes_test.lua [path to Valhalla/]
-- Functions are taken from the source as written (Chunk) and run with small stubs; what can't run here is checked
-- in the source.
local here = (arg[0] or ""):match("^(.*[/\\])") or "./"
local root = arg[1] or (here .. "../../Valhalla/")

local pass, fail = 0, 0
local function ok(cond, name, detail)
  if cond then pass = pass + 1 print("PASS  " .. name)
  else fail = fail + 1 print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end
local function Source(file) local f = assert(io.open(root .. file)) local s = f:read("*a") f:close() return s end
local function Lines(src) local t = {} for l in (src .. "\n"):gmatch("([^\n]*)\n") do t[#t + 1] = l end return t end
-- a top-level function (or one-line local) from the source: from the line starting with `head` to its closing
-- "end" at the start of a line
local function Chunk(src, head)
  local L = Lines(src)
  for i, l in ipairs(L) do
    if l:sub(1, #head) == head then
      if l:match("end%s*$") and not l:match("^%s*local function [%w_.]+%b()%s*$") and select(2, l:gsub("function", "")) >= 1
        and (l:match("%) return .- end%s*$") or l:match("%)%s.-%send%s*$")) and i < #L and not L[i + 1]:match("^\t") then
        return l
      end
      local out = { l }
      for j = i + 1, #L do
        out[#out + 1] = L[j]
        if L[j] == "end" then return table.concat(out, "\n") end
      end
    end
  end
  error("no chunk " .. head)
end
local function Run(code, env)
  setmetatable(env, { __index = _G })
  local fn = assert(loadstring(code))
  setfenv(fn, env)
  fn()
  return env
end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function strsplit(sep, s, n)
  local out, start = {}, 1
  while true do
    if n and #out == n - 1 then out[#out + 1] = s:sub(start) break end
    local a, b = s:find(sep, start, true)
    if not a then out[#out + 1] = s:sub(start) break end
    out[#out + 1] = s:sub(start, a - 1)
    start = b + 1
  end
  return unpack(out)
end

-- (1.2.26) the shared helpers, as the game loads them after Core.lua
local uns = { L = setmetatable({}, { __index = function(_, k) return k end }) }
assert(loadfile(root .. "Util.lua"))("Valhalla", uns)
local U = uns.Util

---------------------------------------------------------------------------
print("== B2. a pin code with spaces in a note: every pin and the whole note")
do
  local src = Source("Map/Pins.lua")
  local code = table.concat({
    "CODE = " .. src:match("local CODE = (\"[^\"]+\")"),
    "NOTE_MAX, SHARE_MAX = 160, 20",
    "COLORS = { 1, 2, 3, 4, 5, 6 }",
    "S = { Rect = function(m) return m == 1429 or m == 1453 end }",
    "local Round = _U.Round", Chunk(src, "local function Clean("),
    Chunk(src, "local function Escape("), Chunk(src, "local function Unescape("),
    Chunk(src, "local function CodeOf("), Chunk(src, "local function Valid("), Chunk(src, "local function FromCode("),
    "_CodeOf, _FromCode, _Escape = CodeOf, FromCode, Escape",
  }, "\n")
  local env = Run(code, { _U = U })
  local pins = { { map = 1429, x = 0.5, y = 0.25, color = 2, note = "big chest here" }, { map = 1453, x = 0.1, y = 0.9, color = 1, note = "mailbox, 50% off; ok" } }
  local c = env._CodeOf(pins)
  ok(not c:find(" ", 1, true), "the code has no spaces (they're escaped)", c)
  local back = env._FromCode("look: " .. c .. "\n")
  ok(back and #back == 2 and back[1].note == "big chest here" and back[2].note == "mailbox, 50% off; ok", "read back: both pins, the notes whole", back and #back)
  local old = "VHPINS1:1429,0.5000,0.2500,2,big chest here;1453,0.1000,0.9000,1,mail"
  local b2 = env._FromCode(old)
  ok(b2 and #b2 == 2 and b2[1].note == "big chest here" and b2[2].note == "mail", "a 1.2.25 code (spaces as they were): both pins, the note whole", b2 and #b2)
end

print("== B8. every way a pin goes ends its drawing and its editor")
do
  local drop = Chunk(Source("Map/Pins.lua"), "local function Drop(")
  ok(drop:find("editor.pin == p", 1, true) and drop:find("ToggleSketch(false)", 1, true), "Drop closes the editor and the quill for that pin")
  local env = Run("local editor = { pin = nil, Hide = function(self) self.hidden = true end }\n_E = editor\n"
    .. "local function Followed() return false end local function Remove(p) _removed = p end\n" .. drop .. "\n_Drop = Drop",
    { mod = { SketchPin = function() return _G.__sk end, ToggleSketch = function(self, on) _sketchOff = on == false end, DropSketches = function(id) _dropped = id end } })
  local p = { id = 7 }
  env._E.pin = p
  _G.__sk = p
  env._Drop(p)
  ok(env._E.pin == nil and env._E.hidden and env._sketchOff and env._removed == p and env._dropped == 7, "Delete / Alt-click / Clear All: editor closed, quill off, pin and strokes gone")
  _G.__sk = nil
end

print("== B5. the other-realm mark: only on another realm's names")
do
  local src = Source("Map/Friends.lua")
  local env = Run(table.concat({ "local function Realm() return 'Forever' end", Chunk(src, "local function Plain("),
    Chunk(src, "local function Short("), Chunk(src, "local function Shown("), "_Shown = Shown" }, "\n"), { FOREIGN_SERVER_LABEL = " (*)" })
  ok(env._Shown("Thor-Forever") == "Thor", "your own realm: no mark", env._Shown("Thor-Forever"))
  ok(env._Shown("Loki-Asgard") == "Loki (*)", "another realm: marked", env._Shown("Loki-Asgard"))
  ok(env._Shown("Odin") == "Odin", "no realm given: no mark")
end

print("== B4. What's new: the versions scroll")
do
  local src = Source("Map/News.lua")
  ok(src:find("local listScroll = ns.Style.UIScroll(list)", 1, true) and src:find('CreateFrame("Button", nil, rowsChild)', 1, true)
    and not src:find('CreateFrame("Button", nil, list)', 1, true), "the rows in a scroll frame, not straight on the list")
  local env = Run(Chunk(src, "local function ScrollListTo(") .. "\n_To = ScrollListTo", { ROW_H = 26 })
  local sf = { h = 300, v = 0, range = 1400 }
  function sf:GetHeight() return self.h end function sf:GetVerticalScroll() return self.v end
  function sf:GetVerticalScrollRange() return self.range end function sf:SetVerticalScroll(v) self.v = v end
  env._To(sf, 40)
  ok(sf.v > 0 and 39 * 28 >= sf.v and 39 * 28 + 26 <= sf.v + 300 + 8, "an old version picked (Older): scrolled into view", sf.v)
  env._To(sf, 1)
  ok(sf.v == 0, "the newest: back at the top")
end

print("== B3. unexplored covers: one frame per zone, its textures reused")
do
  local src = Source("Map/Stitch.lua")
  local a = src:find("Shade.Hide.frames = {}", 1, true)
  local b = src:find("function Shade.Hide.Build(", 1, true)
  ok(a and b and a < b, "the cover helpers sit before Build")
  local made, frames = 0, 0
  local function Tex()
    made = made + 1
    local t = { masks = {}, shown = true }
    function t:AddMaskTexture(m) self.masks[m] = true end function t:RemoveMaskTexture(m) self.masks[m] = nil end
    function t:Hide() self.shown = false end function t:Show() self.shown = true end function t:ClearAllPoints() self.cleared = true end
    function t:SetDrawLayer() end function t:SetVertexColor() end
    return t
  end
  local env = Run("local NONE = {}\n" .. src:sub(a, b - 1), {
    Shade = { Hide = { root = {} } }, root = {}, tremove = table.remove,
    CreateFrame = function() frames = frames + 1 return { SetAllPoints = function() end, CreateTexture = function() return Tex() end } end })
  local H = env.Shade.Hide
  local f = H.CoverFrame(1429)
  ok(H.CoverFrame(1429) == f and frames == 1, "one frame per zone, made once")
  local t1 = H.CoverTex(f, "art", 0) H.CoverMask(t1, "band")
  local t2 = H.CoverTex(f, "art", 1)
  H.Release(f)
  ok(not t1.shown and t1.cleared and not t1.masks.band and #f.used == 0, "made again: the old textures hidden, unanchored, masks off")
  local r1, r2 = H.CoverTex(f, "art", 0), H.CoverTex(f, "art", 0)
  ok(made == 2 and (r1 == t1 or r1 == t2) and (r2 == t1 or r2 == t2) and r1.shown, "and reused: no new textures", made)
  local tint = H.CoverTex(f, "tint")
  ok(made == 3 and tint.coverKind == "tint", "a tinted one kept apart from the art (never recoloured as art)")
  local n = 0
  local mk = function() n = n + 1 return "mask" end
  H.CoverZoneMask(f, "band", mk) H.CoverZoneMask(f, "band", mk)
  ok(n == 1, "a zone's masks made once")
  local rec = Chunk(src, "local function Record(")
  ok(rec:find("region.omRec", 1, true) and rec:find("PlaceRecord(old)", 1, true), "a region placed again: its record moved, not a second one")
  ok(Chunk(src, "function Shade.Tint("):find("omTinted", 1, true), "a reused shade tinted once in the list")
end

print("== B9. keyboard catchers: never SetPropagateKeyboardInput straight (combat)")
for _, file in ipairs({ "Map/Paint.lua", "Map/Sketch.lua" }) do
  local src = Source(file)
  ok(not src:find(":SetPropagateKeyboardInput(", 1, true) and src:find("ns.Style.KeysThrough(catcher)", 1, true), file .. ": through Style.KeysThrough")
end

print("== B15. other addons' menu toggles under their own section's heading")
do
  local mod = {}
  local ns = { MapStitch = {}, L = setmetatable({}, { __index = function(_, k) return k end }) }
  function ns:GetModule() return mod end
  local savedLibStub = LibStub
  LibStub = nil
  assert(loadfile(root .. "API.lua"))("Valhalla", ns)
  LibStub = savedLibStub
  local function T(id, section) ValhallaAPI.RegisterMenuToggle("Addon", { id = id, label = id, get = function() return true end, set = function() end, section = section }) end
  T("a", "Alpha") T("b", "Beta") T("c", "Alpha")
  local rows = mod.ExtraMenuRows(function(label) return { label } end)
  local seq = {}
  for _, r in ipairs(rows) do seq[#seq + 1] = r[1] end
  ok(table.concat(seq, " ") == "Alpha a c Beta b", "Alpha's toggles together (c no longer under Beta)", table.concat(seq, " "))
  ValhallaAPI = nil
end

print("== B17. the gap minimap: a tile off the yard box skipped, not an error")
do
  local src = Source("Map/Close.lua")
  local i = src:find("local u1, v1 = S.FromYards(cont, (31 - ty) * TILE, (31 - tx) * TILE)", 1, true)
  ok(i and src:sub(i, i + 300):find("if u0 and u1 then", 1, true), "both corners checked before the arithmetic")
end

print("== B18. idle work")
do
  local fr = Source("Map/Friends.lua")
  ok(fr:find("if tickHandle then tickHandle:Cancel() tickHandle = nil end", 1, true) and not fr:find("\n\tC_Timer.NewTicker(TICK, Tick)\n", 1, true),
    "Friends: the 2 s look only while sharing")
  ok(Chunk(fr, "local function QueueScan("):find("mod.db.friends or mod.db.friendsShare", 1, true), "Friends: no roster scans with both off")
  local nav = Chunk(Source("Map/Nav.lua"), "local function RefreshGroup(")
  ok(nav:find("if not on and not groupShown then return end", 1, true), "Nav: group off and none up: the refresh does nothing")
  local lp = Chunk(Source("Objectives/Objectives.lua"), "function O.LayoutPins(")
  ok(not lp:find("tostring(b)", 1, true) and lp:find("S.blankSpare", 1, true) and lp:find("p.keyStrata ~= strata", 1, true),
    "tracker pins: no key strings or new tables a pass; strata and level set on a change")
end

print("== D1-D4, D6. the shared helpers (Util.lua) do what each copy did")
do
  ok(U.Round(0.123456, 1e4) == 0.1235 and U.Round(0.1234567, 1e5) == 0.12346 and U.Round(2.5) == 3 and U.Round(-0.4) == 0,
    "Round: Pins (1e4), Sketch/Paint (1e5), Flights (whole)")
  ok(U.Smooth(5, { 0, 10 }) == 0.5 and U.Smooth(5, 0, 10) == 0.5 and U.Smooth(-1, { 0, 10 }) == 0 and U.Smooth(20, 0, 10) == 1,
    "Smooth: Routes/Close (x, { from, to }) and Stitch (from, to)")
  ok(U.Trim("  a b \n") == "a b" and U.Trim(nil) == "" and U.Trim(12) == "12" and select("#", U.Trim(" x ")) == 1, "Trim: text, nil, a number; one result")
  local a, b, c, d = U.Call(function() return 1, 2, 3, 4, 5 end)
  ok(a == 1 and b == 2 and c == 3 and d == 4 and U.Call(error) == nil and U.Call(nil) == nil, "Call: four results, nil on an error")
  ok(select("#", U.CallAll(function() return 1, nil, 3, nil, 5, 6 end)) == 6, "CallAll: every result (Craft's GetProfessionInfo)")
  uns.Safe = { Value = function(v) if v == "SECRET" then return nil end return v end }
  local x, y = U.Call(function() return "SECRET", 2 end)
  ok(x == nil and y == 2 and U.Value("SECRET") == nil and U.Value(false) == false, "a secret result: nil (Objectives' Plain let it through)")
  local core = Source("Core.lua")
  local xy = core:match("(function Safe%.XY%(vec%).-\nend)")
  local env = Run("local Safe = _S\n" .. xy:gsub("^function Safe%.XY", "function _S.XY"), { _S = uns.Safe })
  local px, py = uns.Safe.XY({ GetXY = function() return "SECRET", 0.5 end })
  local qx, qy = uns.Safe.XY({ x = 0.25, y = 0.75 })
  ok(px == nil and py == 0.5 and qx == 0.25 and qy == 0.75 and uns.Safe.XY(nil) == nil, "Safe.XY: plain values, a secret one nil (D6)")
  uns.Safe = nil
  uns.Combat = nil
  local ran = 0
  _G.InCombatLockdown = function() return true end
  ok(U.Defer("k", function() ran = ran + 1 end) == false and ran == 0, "Defer without CombatQueue: held in combat")
  _G.InCombatLockdown = function() return false end
  ok(U.Defer("k", function() ran = ran + 1 end) == true and ran == 1, "and run out of it")
  local seen
  uns.Combat = { Run = function(k, fn, note) seen = { k, note } return false end, Blocked = function() return true end }
  ok(U.Defer("w", function() end, "Note") == false and seen[1] == "w" and seen[2] == "Note" and U.InCombat() == true, "Defer and InCombat through CombatQueue")
  _G.InCombatLockdown = nil
end

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
