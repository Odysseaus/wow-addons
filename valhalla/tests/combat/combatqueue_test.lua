-- Box tests for Valhalla/CombatQueue.lua (1.2.23: in combat, Valhalla's calls into the game's quest tracker,
-- quest log and windows wait until combat ends; 1.2.24: the gate widened, the settle after combat). Lua 5.1.
-- Run: lua valhalla/tests/combat/combatqueue_test.lua [path to Valhalla/]
local here = (arg[0] or ""):match("^(.*[/\\])") or "./"
local root = arg[1] or (here .. "../../Valhalla/")

local pass, fail = 0, 0
local function ok(cond, name, detail)
  if cond then pass = pass + 1 print("PASS  " .. name)
  else fail = fail + 1 print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

local combat = false
function InCombatLockdown() return combat end
local errors = {}
function geterrorhandler() return function(e) errors[#errors + 1] = tostring(e) end end
local ns = { printed = {}, handlers = {} }
function ns:Print(fmt) self.printed[#self.printed + 1] = fmt end
function ns.RegisterEvent(owner, event, fn) ns.handlers[event] = { owner = owner, fn = fn } return true end
assert(loadfile(root .. "Util.lua"))("Valhalla", ns)   -- (1.2.26: the shared helpers, after Core.lua)
assert(loadfile(root .. "CombatQueue.lua"))("Valhalla", ns)
local Q = ns.Combat

print("== 1. out of combat: straight away")
local log = {}
ok(Q.Run("a", function() log[#log + 1] = "a" end) == true and #log == 1 and not Q.Pending(), "run now, nothing queued")
ok(ns.handlers.PLAYER_REGEN_ENABLED ~= nil, "PLAYER_REGEN_ENABLED registered (the flush)")

print("== 2. in combat: queued, the last write kept (moved to the end), told once")
combat = true
log = {}
ok(Q.Run("watch:1", function() log[#log + 1] = "remove 1" end, "note") == false, "queued (false)")
Q.Run("supertrack", function() log[#log + 1] = "super 5" end, "note")
Q.Run("watch:1", function() log[#log + 1] = "add 1" end, "note")
Q.Run("map:pins", function() log[#log + 1] = "map" end, "map note")
ok(#log == 0 and Q.Pending("watch:1") and Q.Pending("supertrack") and Q.Pending(), "nothing run in combat")
ok(#Q.order == 3 and Q.order[1] == "supertrack" and Q.order[2] == "watch:1" and Q.order[3] == "map:pins", "de-duplicated: one per key, the replaced one moved to the end", table.concat(Q.order, ","))
ok(#ns.printed == 2 and ns.printed[1] == "note" and ns.printed[2] == "map note", "each note printed once per combat", table.concat(ns.printed, "|"))
ok(Q.Flush() == 0 and #log == 0, "a flush while still in combat: nothing run")
ok(Q.Run("x", "not a function") == false and not Q.Pending("x"), "not a function: ignored")

print("== 3. combat over (PLAYER_REGEN_ENABLED): run in order, once")
combat = false
local h = ns.handlers.PLAYER_REGEN_ENABLED
h.fn(h.owner, "PLAYER_REGEN_ENABLED")
ok(table.concat(log, ",") == "super 5,add 1,map", "run in order, the last write for watch:1 only", table.concat(log, ","))
ok(not Q.Pending() and Q.Flush() == 0, "nothing left; a second flush runs nothing")

print("== 4. an error in one: reported, the rest still run; notes again next combat")
combat = true
ns.printed = {}
log = {}
Q.Run("bad", function() error("boom") end, "note")
Q.Run("good", function() log[#log + 1] = "good" end, "note")
ok(#ns.printed == 1, "a new combat: told again (once)")
combat = false
ok(Q.Flush() == 2 and log[1] == "good" and #errors == 1 and errors[1]:find("boom", 1, true), "the error to the error handler, the next one run", errors[1])

print("== 5. the call sites: every map open / window call from Valhalla's code waits out combat (source scan)")
local addonRoot = root
local p = io.popen('find "' .. addonRoot .. '" -name "*.lua" -not -path "*/Libs/*" -not -path "*/Locales/*" -not -path "*/Data/*"')
local bad, seen = {}, 0
for path in p:lines() do
  local lines = {}
  for line in io.lines(path) do lines[#lines + 1] = line end
  for n, line in ipairs(lines) do
    local code = line:gsub("%-%-.*$", "")
    for _, pat in ipairs({ "ToggleWorldMap%(%)", "ShowUIPanel%(", "HideUIPanel%(", "pcall%(HideUIPanel" }) do
      if code:find(pat) then
        seen = seen + 1
        local guarded = false
        for k = math.max(1, n - 8), math.min(#lines, n + 8) do
          if lines[k]:find("InCombatLockdown", 1, true) or lines[k]:find("ns.Combat", 1, true) then guarded = true end
        end
        if not guarded then bad[#bad + 1] = path:match("[^/]+/[^/]+$") .. ":" .. n end
        break
      end
    end
  end
end
p:close()
ok(seen >= 9 and #bad == 0, "every ToggleWorldMap / ShowUIPanel / HideUIPanel call guarded by combat (" .. seen .. " calls)", table.concat(bad, ", "))

-- (1.2.24) the gate: the player in combat, secret auras (1.2.25), the settle after combat; timers
print("== 6. (1.2.24) secret auras (1.2.25: ShouldAurasBeSecret; out of combat): deferred, looked at again, run once clear")
local clock = 1000
function GetTime() return clock end
local timers = {}
C_Timer = { After = function(d, fn) timers[#timers + 1] = { at = clock + (d or 0), fn = fn } end }
local function Advance(sec)
  clock = clock + sec
  local again = true
  while again do
    again = false
    for i, t in ipairs(timers) do
      if t.at <= clock then table.remove(timers, i) t.fn() again = true break end
    end
  end
end
local secret, unitCombat = false, false
C_Secrets = { ShouldAurasBeSecret = function() return secret end }
function UnitAffectingCombat(u) return u == "player" and unitCombat end
combat, secret = false, true
ns.printed, log = {}, {}
ok(Q.Blocked() and Q.Why()[1] == "secret auras", "secret auras: the gate holds", table.concat(Q.Why(), ","))
ok(Q.Run("supertrack", function() log[#log + 1] = "super" end, "note") == false and #log == 0 and Q.Pending("supertrack"), "deferred, not run")
ok(#ns.printed == 1 and #timers == 1, "told once; a look scheduled (no PLAYER_REGEN_ENABLED comes)", #timers)
Advance(Q.SETTLE)
ok(#log == 0 and Q.Pending() and #timers == 1, "still restricted after the wait: re-deferred, looked at again")
ok(Q.Flush() == 0 and #log == 0, "a flush while restricted: nothing run")
secret = false
Advance(Q.SETTLE)
ok(#log == 1 and not Q.Pending() and #timers == 0, "clear: run once, nothing scheduled after")
ok(Q.Run("now", function() log[#log + 1] = "now" end) == true and log[2] == "now", "clear and nothing queued: straight away")

print("== 7. (1.2.24) the player in combat (UnitAffectingCombat) without lockdown, and a secret answer: held")
unitCombat, log = true, {}
ok(Q.Blocked() and Q.Run("watch:7", function() log[#log + 1] = "w7" end) == false and #log == 0, "UnitAffectingCombat: held")
unitCombat = false
local realSecret = rawget(_G, "issecretvalue")
local SECRET = {}
issecretvalue = function(v) return v == SECRET end
C_Secrets.ShouldAurasBeSecret = function() return SECRET end
ok(Q.Blocked(), "a secret answer from the game counts as blocked")
C_Secrets.ShouldAurasBeSecret = function() return secret end
issecretvalue = realSecret
Advance(Q.SETTLE)
ok(log[1] == "w7" and not Q.Pending(), "clear again: run")

print("== 8. (1.2.24) combat ends: nothing for SETTLE seconds, new changes queue behind, then run in order")
combat, log, ns.printed = true, {}, {}
Q.Run("watch:1", function() log[#log + 1] = "watch 1" end, "note")
Q.Run("supertrack", function() log[#log + 1] = "super A" end, "note")
ok(#timers == 0, "in lockdown: no timer (PLAYER_REGEN_ENABLED starts it)")
combat = false
h.fn(h.owner, "PLAYER_REGEN_ENABLED")
ok(#log == 0 and Q.Blocked() and Q.Why()[1] == "settling after combat", "PLAYER_REGEN_ENABLED: not run yet (settling)", table.concat(Q.Why(), ","))
Advance(1)
ok(Q.Run("supertrack", function() log[#log + 1] = "super B" end, "note") == false and #log == 0, "a change in the settle: queued (the last kept), not run")
Advance(1.5)
ok(#log == 0, "2.5 s after combat: still nothing")
Advance(0.6)
ok(table.concat(log, ",") == "watch 1,super B", "after SETTLE seconds, still clear: run in order, the last write only", table.concat(log, ","))
ok(not Q.Pending() and #timers == 0, "nothing left or scheduled")

print("== 9. (1.2.24) not clear when the settle ends: re-deferred; combat again in the settle: the next end starts over")
combat, log = true, {}
Q.Run("questlog:zones", function() log[#log + 1] = "zones" end)
combat = false
h.fn(h.owner, "PLAYER_REGEN_ENABLED")
secret = true
Advance(Q.SETTLE)
ok(#log == 0 and Q.Pending() and #timers == 1, "secret at the settle's end: re-deferred, looked at again")
secret = false
combat = true
Advance(Q.SETTLE)
ok(#log == 0 and #timers == 0, "combat again by then: held, no timer in lockdown")
combat = false
h.fn(h.owner, "PLAYER_REGEN_ENABLED")
Advance(Q.SETTLE - 0.5)
ok(#log == 0, "the new settle: still waiting")
Advance(0.5)
ok(log[1] == "zones" and not Q.Pending(), "then run, once")

print("== 10. (1.2.24) Cancel")
combat = true
Q.Run("waypoint", function() log[#log + 1] = "wp" end)
ok(Q.Cancel("waypoint") and not Q.Pending("waypoint") and not Q.Cancel("waypoint"), "a queued key dropped (once)")
combat = false

print("== 11. (1.2.24) every call that changes the game's watch, super-track, waypoint or quest details waits on the gate (source scan)")
do
  local pats = { "C_Map%.SetUserWaypoint", "C_Map%.ClearUserWaypoint", "SetSuperTrackedUserWaypoint", "SetSuperTrackedQuestID",
    "ClearAllSuperTracked", "C_QuestLog%.AddQuestWatch", "C_QuestLog%.RemoveQuestWatch", "C%.AddQuestWatch", "C%.RemoveQuestWatch",
    "\"ExpandQuestHeader\"", "\"QuestMapFrame_ShowQuestDetails\"%)", "\"QuestMapFrame_OpenToQuestDetails\"%)", "\"QuestMapQuestOptions_TrackQuest\"%)" }
  local guards = { "ns.Combat", "Defer(", "Gate(", "C.Run", "InCombat()", "Blocked()" }
  local p2 = io.popen('find "' .. root .. '" -name "*.lua" -not -path "*/Libs/*" -not -path "*/Locales/*" -not -path "*/Data/*"')
  local bad2, seen2 = {}, 0
  for path in p2:lines() do
    local lines = {}
    for line in io.lines(path) do lines[#lines + 1] = line end
    for n, line in ipairs(lines) do
      local code = line:gsub("%-%-.*$", "")
      for _, pat in ipairs(pats) do
        if code:find(pat) and not code:find("hooksecurefunc", 1, true) and not code:find("^%s*if ") and not code:find("^%s*and ") then
          seen2 = seen2 + 1
          local guarded = false
          for k = math.max(1, n - 12), math.min(#lines, n + 12) do
            for _, g in ipairs(guards) do if lines[k]:find(g, 1, true) then guarded = true end end
          end
          if not guarded then bad2[#bad2 + 1] = path:match("[^/]+/[^/]+$") .. ":" .. n end
          break
        end
      end
    end
  end
  p2:close()
  ok(seen2 >= 12 and #bad2 == 0, "every such call behind the gate (" .. seen2 .. " calls)", table.concat(bad2, ", "))
end

print("== 12. (1.2.25) HasSecretRestrictions always true (the client build has secrets): no hold out of combat")
combat, unitCombat, secret = false, false, false
C_Secrets = { HasSecretRestrictions = function() return true end, ShouldAurasBeSecret = function() return secret end }
clock = clock + 10   -- (well past any settle)
log, ns.printed = {}, {}
ok(not Q.Blocked() and #Q.Why() == 0, "the gate clear", table.concat(Q.Why(), ","))
ok(Q.Run("waypoint", function() log[#log + 1] = "wp" end, "note") == true and log[1] == "wp" and #ns.printed == 0, "a waypoint runs at once, no chat line")

print("== 13. (1.2.25) ShouldAurasBeSecret true out of combat: held, released at SAFETY seconds (one warning), held again next time")
secret, log, ns.printed, timers = true, {}, {}, {}
ok(Q.Blocked() and Q.Why()[1] == "secret auras", "secret auras: held", table.concat(Q.Why(), ","))
Q.Run("watch:9", function() log[#log + 1] = "w9" end, "note")
Advance(27)
ok(#log == 0 and Q.Pending("watch:9"), "27 s: still held")
Advance(3.5)
local warned = 0 for _, p in ipairs(ns.printed) do if p == Q.SAFETY_NOTE then warned = warned + 1 end end
ok(log[1] == "w9" and not Q.Pending(), "past " .. Q.SAFETY .. " s: run", table.concat(log, ","))
ok(warned == 1, "one chat warning", table.concat(ns.printed, " | "))
ok(Q.Run("watch:10", function() log[#log + 1] = "w10" end) == true and log[2] == "w10", "still secret, released: straight away")
secret = false
ok(not Q.Blocked(), "secret over: clear")
secret = true
ok(Q.Blocked(), "secret again: held again (a new " .. Q.SAFETY .. " s)")
Q.Run("watch:11", function() log[#log + 1] = "w11" end)
Advance(Q.SAFETY + 3)
warned = 0 for _, p in ipairs(ns.printed) do if p == Q.SAFETY_NOTE then warned = warned + 1 end end
ok(log[3] == "w11" and warned == 1, "released again; no second warning this session", warned)
combat = true
ok(Q.Blocked(), "in combat, secret auras: held (the safety net is out of combat only)")
Q.Run("watch:12", function() log[#log + 1] = "w12" end)
Advance(60)
ok(#log == 3 and Q.Pending("watch:12"), "in combat a minute: still held")
combat, secret = false, false
h.fn(h.owner, "PLAYER_REGEN_ENABLED")
Advance(Q.SETTLE + 0.1)
ok(log[4] == "w12" and not Q.Pending(), "combat over and settled: run")

print("== 14. (1.2.25) the record of calls run (time and key), /valhalla combat")
local hist = Q.History()
ok(#hist >= 5 and hist[#hist].key == "watch:12" and hist[#hist].how == "queued", "the last call run recorded, queued", hist[#hist] and hist[#hist].key)
local nowSeen = false for _, e in ipairs(hist) do if e.key == "watch:10" and e.how == "now" then nowSeen = true end end
ok(nowSeen and type(hist[1].at) == "number" and type(hist[1].clock) == "string", "straight-away runs too; time kept")
for i = 1, Q.HISTORY + 10 do Q.Run("k" .. i, function() end) end
ok(#Q.History() == Q.HISTORY and Q.History()[Q.HISTORY].key == "k" .. (Q.HISTORY + 10), "kept to the last " .. Q.HISTORY)
local rep = Q.Report()
ok(rep[1]:find("clear", 1, true) and rep[#rep]:find("k" .. (Q.HISTORY + 10), 1, true), "the report: the gate, the last run", rep[1])
secret = true
Q.Run("held", function() end)
rep = Q.Report()
ok(rep[1]:find("held (secret auras)", 1, true) and rep[2]:find("held", 1, true), "held: the reason and what waits", rep[1] .. " / " .. tostring(rep[2]))
secret = false
Advance(Q.SETTLE)
C_Secrets = nil

print("== 15. (1.2.26) a failing secret-auras check counts as secret (the safety net still opens it); a failing combat check doesn't hold")
do
  C_Secrets = { ShouldAurasBeSecret = function() error("broken") end }
  local ran = false
  ok(Q.Blocked() == true and Q.Why()[1] == "secret auras", "ShouldAurasBeSecret errors: held as secret auras", table.concat(Q.Why(), ","))
  Q.Run("broken", function() ran = true end)
  ok(not ran and Q.Pending("broken"), "a call waits")
  Advance(Q.SAFETY + Q.SETTLE + 1)
  ok(ran and not Q.Pending(), "after the safety net's " .. Q.SAFETY .. " s: run")
  C_Secrets = nil
  Advance(Q.SETTLE)
  local gameICL = InCombatLockdown
  InCombatLockdown = function() error("broken") end
  ran = false
  ok(Q.Run("icl", function() ran = true end) == true and ran, "InCombatLockdown errors: not held (never for good)")
  InCombatLockdown = gameICL
end

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
