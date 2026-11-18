-- Box tests for Valhalla/CombatQueue.lua (1.2.23: in combat, Valhalla's calls into the game's quest tracker,
-- quest log and windows wait until combat ends). Lua 5.1.
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

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
