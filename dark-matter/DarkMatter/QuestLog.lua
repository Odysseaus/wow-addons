-- 0.4.6 quest log reader for the Quests tab: quest text, objectives, rewards, the search haystack and /dm questprobe.
-- Every API is feature-detected and pcall'd; nothing is ever fabricated.
-- 0.4.6 fix: WoW Forever has no SelectQuestLogEntry/GetQuestLogSelection. 0.4.5 then skipped the readers entirely, so every
-- quest showed "Not available". The readers now ALWAYS run, under the first selection method that yields quest text:
--   1. SelectQuestLogEntry(logIndex)          (classic; GetQuestLogSelection restored)
--   2. C_QuestLog.SetSelectedQuest(questID)   (modern client; C_QuestLog.GetSelectedQuest restored)
--   3. direct                                  (no selection; readers get explicit questID / log index arguments;
--                                                 used only when the client has no selection API at all)
-- The method that works is remembered. Selecting can fire QUEST_LOG_UPDATE; NS.QL.reading is set meanwhile and static
-- text/rewards are cached per quest, so a read never loops into another read.
local _, NS = ...
local QL = {}
NS.QL = QL
QL.reading = false

local function G(name) local f = _G[name] if type(f) == "function" then return f end end
local function CQ(name) local t = _G.C_QuestLog if type(t) == "table" and type(t[name]) == "function" then return t[name] end end
local function Call(f, ...) if not f then return end local r = { pcall(f, ...) } if r[1] then return select(2, unpack(r)) end end
local function Text(s) s = NS.Str(s) if s and s:match("%S") then return s end end
local function Str1(...) local v = ... return tostring(v) end -- tostring of a call that may return nothing

-- probe list: what the detail panel uses, in order of preference
QL.API = {
  { "C_QuestLog.GetInfo", "quest list (title, level, header, questID)" },
  { "C_QuestLog.GetQuestObjectives", "objective progress by questID" },
  { "GetNumQuestLeaderBoards", "objective fallback (by log index)" },
  { "GetQuestLogLeaderBoard", "objective fallback (by log index)" },
  { "C_QuestLog.GetLogIndexForQuestID", "log index by questID" },
  { "GetQuestLogIndexByID", "log index fallback" },
  { "GetQuestLogSelection", "remember the player's selection (classic)" },
  { "SelectQuestLogEntry", "select by log index (classic)" },
  { "C_QuestLog.GetSelectedQuest", "remember the player's selection (questID)" },
  { "C_QuestLog.SetSelectedQuest", "select by questID" },
  { "C_QuestLog.RequestLoadQuestByID", "ask the client to load quest data" },
  { "HaveQuestData", "quest data loaded?" },
  { "GetQuestLogTitle", "classic quest title by log index (probe only)" },
  { "GetQuestObjectiveInfo", "objective by questID (probe only)" },
  { "GetQuestLogQuestText", "description + objectives summary" },
  { "GetQuestLogRewardXP", "experience" },
  { "GetQuestLogRewardMoney", "money" },
  { "GetQuestLogRequiredMoney", "required money" },
  { "GetNumQuestLogRewards", "'You will receive' items" },
  { "GetQuestLogRewardInfo", "reward item name/icon/count/quality" },
  { "GetNumQuestLogChoices", "'choose one of these' items" },
  { "GetQuestLogChoiceInfo", "choice item name/icon/count/quality" },
  { "GetQuestLogItemLink", "item links (tooltip fallback, item id)" },
  { "GetQuestLogRewardSpell", "spell reward" },
  { "GetQuestLogRewardHonor", "honor reward" },
  { "GetQuestLogRewardTitle", "title reward" },
  { "GetNumQuestLogRewardFactions", "reputation rewards" },
  { "GetQuestLogRewardFactionInfo", "reputation reward faction/amount" },
  { "GetQuestLogGroupNum", "suggested group size" },
  { "GameTooltip.SetQuestLogItem", "real item tooltip (primary)" },
  { "GameTooltip.SetHyperlink", "item tooltip by link (fallback 1)" },
  { "GameTooltip.SetItemByID", "item tooltip by id (fallback 2)" },
  { "GetCoinTextureString", "money with coin icons (own coin icons used when missing)" },
}

function QL.Has(name)
  local ns, fn = name:match("^(.-)%.(.+)$")
  if ns == "C_QuestLog" then return CQ(fn) ~= nil end
  if ns == "GameTooltip" then return type(GameTooltip) == "table" and type(GameTooltip[fn]) == "function" end
  return G(name) ~= nil
end

local function LogIndex(q)
  if q.questID then
    local i = NS.Num(Call(CQ("GetLogIndexForQuestID"), q.questID)) or NS.Num(Call(G("GetQuestLogIndexByID"), q.questID))
    if i and i > 0 then return i end
  end
  return q.logIndex
end
QL.LogIndex = LogIndex

-- selection methods this client offers, best first; "direct" (no selection) always works as a last resort
function QL.Methods()
  local m = {}
  if G("SelectQuestLogEntry") then m[#m + 1] = "SelectQuestLogEntry" end
  if CQ("SetSelectedQuest") then m[#m + 1] = "C_QuestLog.SetSelectedQuest" end
  m[#m + 1] = "direct"
  return m
end

-- run fn(logIndex) with the quest selected by `method`, then put the player's selection back.
-- Returns true when fn ran. The readers always run (0.4.5 skipped them when SelectQuestLogEntry was missing).
function QL.WithSelected(q, fn, method, idx)
  idx = idx or LogIndex(q)
  method = method or QL.method or QL.Methods()[1]
  local ran = false
  QL.reading = true
  if method == "SelectQuestLogEntry" then
    local sel = G("SelectQuestLogEntry")
    if sel and idx then
      local prev = NS.Num(Call(G("GetQuestLogSelection")))
      pcall(sel, idx)
      ran = pcall(fn, idx)
      if prev and prev ~= idx then pcall(sel, prev) end
    end
  elseif method == "C_QuestLog.SetSelectedQuest" then
    local set = CQ("SetSelectedQuest")
    if set and q.questID then
      local prev = NS.Num(Call(CQ("GetSelectedQuest")))
      pcall(set, q.questID)
      ran = pcall(fn, idx)
      if prev ~= q.questID then pcall(set, prev or 0) end
    end
  else
    ran = pcall(fn, idx)
  end
  QL.reading = false
  QL.lastSelect = (GetTime and NS.Num(GetTime())) or 0
  return ran
end

function QL.Objectives(q)
  local out = {}
  local raw = q.questID and NS.Tbl(Call(CQ("GetQuestObjectives"), q.questID))
  if raw then
    for _, o in ipairs(raw) do
      local ob = NS.Tbl(o)
      if ob and NS.Str(ob.text) and ob.text ~= "" then out[#out + 1] = { text = ob.text, done = NS.Bool(ob.finished) == true } end
    end
    return out, "C_QuestLog.GetQuestObjectives"
  end
  local idx = LogIndex(q)
  local n = idx and NS.Num(Call(G("GetNumQuestLeaderBoards"), idx))
  if n and G("GetQuestLogLeaderBoard") then
    for i = 1, n do
      local text, _, done = Call(G("GetQuestLogLeaderBoard"), i, idx)
      text = NS.Str(text)
      if text and text ~= "" then out[#out + 1] = { text = text, done = NS.Bool(done) == true or done == 1 } end
    end
    return out, "GetQuestLogLeaderBoard"
  end
  return out, nil
end

local function ItemIdFrom(link) local id = NS.Str(link) and link:match("item:(%d+)") return id and tonumber(id) end

local function Items(kind, numFn, infoFn, questID)
  local list = {}
  local n = NS.Num(Call(G(numFn), questID))
  if not n or not G(infoFn) then return list, false end
  for i = 1, n do
    local name, tex, count, quality, usable, itemID = Call(G(infoFn), i, questID)
    local link = NS.Str(Call(G("GetQuestLogItemLink"), kind, i, questID))
    local e = {
      kind = kind, index = i, name = NS.Str(name), icon = tex, count = NS.Num(count) or 1, quality = NS.Num(quality),
      usable = NS.Bool(usable), link = link, itemId = NS.Num(itemID) or ItemIdFrom(link),
    }
    if e.quality and e.quality < 0 then e.quality = nil end
    list[#list + 1] = e
  end
  return list, true
end

-- every reader, with explicit arguments so the modern signatures (questID / log index) also work without a selection;
-- the classic versions ignore the extra arguments and read the selected entry
local function ReadAll(d, q, idx)
  local qid = q.questID
  local desc, obj = Call(G("GetQuestLogQuestText"), idx)
  d.desc, d.objText = Text(desc), Text(obj)
  d.xp = NS.Num(Call(G("GetQuestLogRewardXP"), qid))
  d.money = NS.Num(Call(G("GetQuestLogRewardMoney"), qid))
  d.reqMoney = NS.Num(Call(G("GetQuestLogRequiredMoney"), qid))
  d.rewards, d.src.rewards = Items("reward", "GetNumQuestLogRewards", "GetQuestLogRewardInfo", qid)
  d.choices, d.src.choices = Items("choice", "GetNumQuestLogChoices", "GetQuestLogChoiceInfo", qid)
  local stex, sname = Call(G("GetQuestLogRewardSpell"), qid)
  if NS.Str(sname) then d.spell = { name = sname, icon = stex } end
  d.honor = NS.Num(Call(G("GetQuestLogRewardHonor"), qid))
  d.title = Text(Call(G("GetQuestLogRewardTitle"), qid))
  d.group = NS.Num(Call(G("GetQuestLogGroupNum"), idx))
  d.rep = {}
  local nf = NS.Num(Call(G("GetNumQuestLogRewardFactions"), qid))
  for i = 1, nf or 0 do
    local fid, amount = Call(G("GetQuestLogRewardFactionInfo"), i, qid)
    fid, amount = NS.Num(fid), NS.Num(amount)
    local fname = fid and NS.Str(Call(G("GetFactionInfoByID"), fid))
    if amount and amount ~= 0 then d.rep[#d.rep + 1] = { name = fname or ("Faction " .. tostring(fid)), amount = amount } end
  end
end
QL.ReadAll = ReadAll

local function Score(d)
  return (d.desc and 8 or 0) + (d.objText and 4 or 0) + ((d.xp or 0) > 0 and 2 or 0) + ((d.money or 0) > 0 and 1 or 0)
    + #(d.rewards or {}) + #(d.choices or {}) + #(d.rep or {})
end

local cache, requested = {}, {}
function QL.Forget(questID)
  if questID then cache[questID] = nil requested[questID] = nil else cache = {} end
end

-- static quest data (text + rewards), read once per quest; nil fields = the client did not provide them
function QL.Details(q)
  local key = q.questID or q.title
  local d = cache[key]
  if d and not (d.partial and (d.tries or 0) < 3) then return d end
  local tries = (d and d.tries or 0) + 1
  local idx = LogIndex(q)
  local order, seen, tried, best = {}, {}, {}, nil
  if QL.method then order[1] = QL.method end
  -- "direct" only when the client has no selection API: with one, a selection-free read answers for the PLAYER's selected
  -- quest and could show another quest's text (the probe still tries it, for diagnosis only)
  local ms = QL.Methods()
  for _, m in ipairs(ms) do if m ~= "direct" or #ms == 1 then order[#order + 1] = m end end
  for _, m in ipairs(order) do
    if not seen[m] then
      seen[m] = true
      local t = { tries = tries, src = {}, method = m, rewards = {}, choices = {}, rep = {} }
      local ran = QL.WithSelected(q, function(i) ReadAll(t, q, i) end, m, idx)
      t.read = ran
      tried[#tried + 1] = m .. (ran and (t.desc and " (text)" or " (no text)") or " (unavailable)")
      if ran and (not best or Score(t) > Score(best)) then best = t end
      if ran and t.desc then QL.method = m break end
    end
  end
  d = best or { tries = tries, src = {}, read = false, rewards = {}, choices = {}, rep = {} }
  d.tried, d.index = table.concat(tried, ", "), idx
  d.partial = false
  for _, list in ipairs({ d.rewards or {}, d.choices or {} }) do
    for _, e in ipairs(list) do if not e.name then d.partial = true end end
  end
  -- no text yet: ask the client to load this quest once; QUEST_DATA_LOAD_RESULT then triggers a fresh read
  if not d.desc and q.questID then
    local req = CQ("RequestLoadQuestByID")
    if req and not requested[q.questID] then
      requested[q.questID] = true
      d.requested = pcall(req, q.questID)
      d.partial = true
    end
  end
  cache[key] = d
  return d
end

-- one-line diagnosis when a clicked quest's panel came back empty (printed once per quest by the Quests tab)
function QL.DebugLine(q, d)
  d = d or QL.Details(q)
  return string.format("detail debug \"%s\": questID %s, list index %s, C_QuestLog.GetLogIndexForQuestID %s, GetQuestLogIndexByID %s; tried %s; text %s, xp %s, money %s, %d reward(s), %d choice(s); HaveQuestData %s; load requested %s",
    tostring(q.title), tostring(q.questID), tostring(q.logIndex),
    tostring(q.questID and Call(CQ("GetLogIndexForQuestID"), q.questID)), tostring(q.questID and Call(G("GetQuestLogIndexByID"), q.questID)),
    tostring(d.tried), d.desc and "yes" or "no", tostring(d.xp), tostring(d.money), #(d.rewards or {}), #(d.choices or {}),
    G("HaveQuestData") and Str1(Call(G("HaveQuestData"), q.questID)) or "n/a", d.requested and "yes" or "no")
end

local function Norm(s) return (tostring(s or ""):lower():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[%p%c]", ""):gsub("%s+", " ")) end
QL.Norm = Norm

-- everything a search can match for one quest (title, zone, objectives, quest text, reward names)
function QL.Haystack(q)
  local parts = { q.title, q.group }
  for _, o in ipairs((QL.Objectives(q))) do parts[#parts + 1] = o.text end
  local d = QL.Details(q)
  parts[#parts + 1] = d.objText
  parts[#parts + 1] = d.desc
  for _, list in ipairs({ d.rewards or {}, d.choices or {} }) do
    for _, e in ipairs(list) do parts[#parts + 1] = e.name end
  end
  if d.spell then parts[#parts + 1] = d.spell.name end
  if d.title then parts[#parts + 1] = d.title end
  for _, r in ipairs(d.rep or {}) do parts[#parts + 1] = r.name end
  local s = {}
  for _, p in ipairs(parts) do if NS.Str(p) then s[#s + 1] = p end end
  return Norm(table.concat(s, " "))
end

-- money as gold/silver/copper with coin icons (GetCoinTextureString when the client has it, else our own coin string)
function QL.Money(copper)
  copper = NS.Num(copper) or 0
  local s = Text(Call(G("GetCoinTextureString"), copper))
  if s then return s end
  local g, si, c = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
  local out = {}
  local function coin(n, tex) out[#out + 1] = n .. "|TInterface\\MoneyFrame\\UI-" .. tex .. "Icon:0:0:2:0|t" end
  if g > 0 then coin(g, "Gold") end
  if si > 0 or (g > 0 and c > 0) then coin(si, "Silver") end
  if c > 0 or #out == 0 then coin(c, "Copper") end
  return table.concat(out, " ")
end

-- real item tooltip for a reward: SetQuestLogItem (quest selected the same way as the detail read), else link, else item id
function QL.ShowRewardTooltip(owner, q, e)
  local tt = GameTooltip
  if not (tt and owner and e) then return end
  local d = cache[q.questID or q.title]
  if tt.SetQuestLogItem then
    tt:SetOwner(owner, "ANCHOR_RIGHT")
    local ok = false
    QL.WithSelected(q, function() ok = pcall(tt.SetQuestLogItem, tt, e.kind, e.index, q.questID) end, (d and d.method) or QL.method)
    if ok and tt.NumLines and NS.Num(Call(tt.NumLines, tt)) == 0 then ok = false end
    if ok then tt:Show() return "questlog" end
  end
  if NS.ShowItemTooltip then
    return NS.ShowItemTooltip(owner, { itemId = e.itemId, link = e.link, name = e.name or "Item", quality = e.quality })
  end
end
function QL.HideRewardTooltip(owner)
  if NS.HideItemTooltip then pcall(NS.HideItemTooltip, owner) end
  if GameTooltip and GameTooltip.IsOwned and select(2, pcall(GameTooltip.IsOwned, GameTooltip, owner)) then GameTooltip:Hide() end
end

-- quest-reader functions this client really has (names only; listed by the probe so nothing has to be guessed)
local function Scan()
  local cq, gl = {}, {}
  if type(_G.C_QuestLog) == "table" then
    for k, v in pairs(_G.C_QuestLog) do
      if type(v) == "function" and type(k) == "string" and (k:find("Reward") or k:find("Select") or k:find("Text") or k:find("Money")
        or k:find("Experience") or k:find("XP") or k:find("Load") or k:find("Detail") or k:find("Description")) then cq[#cq + 1] = k end
    end
  end
  for k, v in pairs(_G) do
    if type(v) == "function" and type(k) == "string" and (k:find("^GetQuestLog") or k:find("^GetNumQuestLog") or k:find("^HaveQuest")
      or k:find("^SelectQuestLog") or k:find("QuestReward")) then gl[#gl + 1] = k end
  end
  table.sort(cq) table.sort(gl)
  return cq, gl
end

-- /dm questprobe: which quest APIs exist, which selection method makes the readers return text, the index values,
-- plus one normal detail read of the selected quest
function QL.ProbeReport()
  local lines, have, miss = {}, {}, {}
  for _, a in ipairs(QL.API) do
    if QL.Has(a[1]) then have[#have + 1] = a[1] else miss[#miss + 1] = a[1] .. " (" .. a[2] .. ")" end
  end
  lines[#lines + 1] = string.format("questprobe 0.4.6: %d of %d quest APIs present.", #have, #QL.API)
  lines[#lines + 1] = "present: " .. (#have > 0 and table.concat(have, ", ") or "none")
  lines[#lines + 1] = "missing: " .. (#miss > 0 and table.concat(miss, ", ") or "none")
  local cq, gl = Scan()
  lines[#lines + 1] = "client C_QuestLog reader functions: " .. (#cq > 0 and table.concat(cq, ", ") or "none")
  lines[#lines + 1] = "client quest-log globals: " .. (#gl > 0 and table.concat(gl, ", ") or "none")
  lines[#lines + 1] = "selection methods: " .. table.concat(QL.Methods(), ", ")
  local q = NS.tabs and NS.tabs.quests and NS.tabs.quests.Selected and NS.tabs.quests.Selected()
  if q then
    local byId = q.questID and NS.Num(Call(CQ("GetLogIndexForQuestID"), q.questID))
    lines[#lines + 1] = string.format("index \"%s\": questID %s, list index (C_QuestLog.GetInfo) %s, C_QuestLog.GetLogIndexForQuestID %s, GetQuestLogIndexByID %s; selection now: GetQuestLogSelection %s, C_QuestLog.GetSelectedQuest %s; HaveQuestData %s",
      tostring(q.title), tostring(q.questID), tostring(q.logIndex), tostring(byId), tostring(q.questID and Call(G("GetQuestLogIndexByID"), q.questID)),
      Str1(Call(G("GetQuestLogSelection"))), Str1(Call(CQ("GetSelectedQuest"))), G("HaveQuestData") and Str1(Call(G("HaveQuestData"), q.questID)) or "n/a")
    local tries = {}
    for _, m in ipairs(QL.Methods()) do
      tries[#tries + 1] = { m, nil }
      if m == "SelectQuestLogEntry" and q.logIndex and byId and q.logIndex ~= byId then tries[#tries + 1] = { m, q.logIndex } end
    end
    for _, tr in ipairs(tries) do
      local t = { src = {}, rewards = {}, choices = {}, rep = {} }
      local ran = QL.WithSelected(q, function(i) ReadAll(t, q, i) end, tr[1], tr[2])
      lines[#lines + 1] = string.format("try %s%s: %s", tr[1], tr[2] and (" (list index " .. tr[2] .. ")") or "",
        ran and string.format("GetQuestLogQuestText %s, objectives text %s, xp %s, money %s, %d reward(s), %d choice(s)",
          t.desc and ("text (" .. #t.desc .. " chars)") or "no text", t.objText and "yes" or "no", tostring(t.xp), tostring(t.money), #t.rewards, #t.choices)
        or "not available on this client")
    end
    QL.Forget(q.questID)
    if not q.questID then QL.Forget() end
    local d = QL.Details(q)
    lines[#lines + 1] = string.format("sample \"%s\": text %s, xp %s, money %s, %d reward(s), %d choice(s)%s%s; detail reads use %s",
      q.title, d.desc and "yes" or "no", tostring(d.xp), tostring(d.money), #(d.rewards or {}), #(d.choices or {}),
      d.spell and ", spell" or "", #(d.rep or {}) > 0 and (", " .. #d.rep .. " reputation") or "", tostring(QL.method or d.method or "none"))
  else
    lines[#lines + 1] = "sample: open the Quests tab and click a quest, then run /dm questprobe again."
  end
  if NS.db then NS.db.questprobe = { have = have, missing = miss, lines = lines } end
  return have, lines
end

---------------------------------------------------------------------------
-- 0.4.5/0.4.6 quest watch (the per-quest checkbox): two-way sync with the game's watch list
---------------------------------------------------------------------------
local WATCH_API = {
  { "C_QuestLog.GetQuestWatchType", "is watched (questID)" },
  { "C_QuestLog.IsQuestWatched", "is watched (questID)" },
  { "IsQuestWatched", "is watched (log index, classic)" },
  { "C_QuestLog.AddQuestWatch", "watch (questID)" },
  { "AddQuestWatch", "watch (log index, classic)" },
  { "C_QuestLog.RemoveQuestWatch", "unwatch (questID)" },
  { "RemoveQuestWatch", "unwatch (log index, classic)" },
  { "C_QuestLog.GetNumQuestWatches", "watch count" },
  { "GetNumQuestWatches", "watch count (classic)" },
  { "C_QuestLog.GetMaxNumQuestsCanWatch", "watch cap" },
  { "QuestWatch_Update", "classic tracker refresh (called after a change)" },
  { "WatchFrame_Update", "wrath tracker refresh (called after a change)" },
}
for _, a in ipairs(WATCH_API) do QL.API[#QL.API + 1] = a end

function QL.IsWatched(q)
  if q.questID then
    local wt = CQ("GetQuestWatchType")
    if wt then local ok, v = pcall(wt, q.questID) if ok then return v ~= nil end end
    local iw = CQ("IsQuestWatched")
    if iw then local ok, v = pcall(iw, q.questID) if ok then return v == true or v == 1 end end
  end
  local idx = LogIndex(q)
  if idx and G("IsQuestWatched") then local v = Call(G("IsQuestWatched"), idx) return v == true or v == 1 end
  return nil -- no watch API: no checkbox
end

function QL.CanWatch() return CQ("GetQuestWatchType") or CQ("IsQuestWatched") or G("IsQuestWatched") end

-- the watch cap: what the client reports, else its constants, else 25 (assumed; the game still refuses past its own limit)
QL.DEFAULT_WATCH_CAP = 25
function QL.WatchCap()
  local cap, src = NS.Num(Call(CQ("GetMaxNumQuestsCanWatch"))), "C_QuestLog.GetMaxNumQuestsCanWatch"
  if not cap then
    local k = type(_G.Constants) == "table" and type(_G.Constants.QuestWatchConsts) == "table" and NS.Num(_G.Constants.QuestWatchConsts.MAX_QUEST_WATCHES)
    if k then cap, src = k, "Constants.QuestWatchConsts.MAX_QUEST_WATCHES" end
  end
  if not cap and type(_G.MAX_WATCHABLE_QUESTS) == "number" then cap, src = _G.MAX_WATCHABLE_QUESTS, "MAX_WATCHABLE_QUESTS" end
  if not cap then cap, src = QL.DEFAULT_WATCH_CAP, "assumed default (the client reports no cap)" end
  local n = NS.Num(Call(CQ("GetNumQuestWatches"))) or NS.Num(Call(G("GetNumQuestWatches")))
  return cap, n, src
end

local function TrackerUpdate()
  -- the classic/wrath stock quest log calls these after a watch change; the retail ObjectiveTracker updates itself
  -- from QUEST_WATCH_LIST_CHANGED and holds secure item buttons, so it is never called from here (taint-safe)
  if G("QuestWatch_Update") then pcall(QuestWatch_Update) return "QuestWatch_Update" end
  if G("WatchFrame_Update") then pcall(WatchFrame_Update) return "WatchFrame_Update" end
end

local queued = {}
local regen
-- want = true (watch) / false (unwatch). Returns "ok", "queued", "cap" or "noapi".
function QL.SetWatched(q, want)
  if InCombatLockdown and InCombatLockdown() then
    queued[q.questID or q.title] = { q = q, want = want }
    if not regen then
      regen = CreateFrame("Frame") -- private frame
      regen:SetScript("OnEvent", function()
        local list = queued
        queued = {}
        for _, it in pairs(list) do QL.SetWatched(it.q, it.want) end
        if NS.tabs and NS.tabs.quests and NS.tabs.quests.Refresh then NS.tabs.quests.Refresh() end
      end)
    end
    pcall(regen.RegisterEvent, regen, "PLAYER_REGEN_ENABLED")
    return "queued"
  end
  if regen then pcall(regen.UnregisterEvent, regen, "PLAYER_REGEN_ENABLED") end
  local idx = LogIndex(q)
  if want then
    local cap, n = QL.WatchCap()
    if cap and n and n >= cap then
      local msg = type(_G.QUEST_WATCH_TOO_MANY) == "string" and _G.QUEST_WATCH_TOO_MANY:format(cap) or ("You can only track " .. cap .. " quests at a time.")
      if UIErrorsFrame and UIErrorsFrame.AddMessage then pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, msg, 1, 0.1, 0.1) end
      NS.Print(msg)
      return "cap"
    end
    local ok = false
    if q.questID and CQ("AddQuestWatch") then ok = pcall(CQ("AddQuestWatch"), q.questID) end
    if not ok and idx and G("AddQuestWatch") then ok = pcall(G("AddQuestWatch"), idx) end
    if not ok then return "noapi" end
    if QL.IsWatched(q) == false then
      -- the game did not take it (its own limit, or a quest it will not track): leave the box unticked, say so
      NS.Print("The game did not add \"" .. tostring(q.title) .. "\" to the watch list (it may be at its tracking limit).")
      QL.lastTracker = TrackerUpdate()
      return "refused"
    end
  else
    local ok = false
    if q.questID and CQ("RemoveQuestWatch") then ok = pcall(CQ("RemoveQuestWatch"), q.questID) end
    if not ok and idx and G("RemoveQuestWatch") then ok = pcall(G("RemoveQuestWatch"), idx) end
    if not ok then return "noapi" end
  end
  QL.lastTracker = TrackerUpdate()
  return "ok"
end

QL.WATCH_EVENTS = { "QUEST_WATCH_LIST_CHANGED", "QUEST_WATCH_UPDATE", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "QUEST_DATA_LOAD_RESULT" }

function QL.WatchReport()
  local cap, n, src = QL.WatchCap()
  return string.format("watch: %s watched, cap %s (%s); tracker refresh: %s", tostring(n), tostring(cap), tostring(src),
    G("QuestWatch_Update") and "QuestWatch_Update" or G("WatchFrame_Update") and "WatchFrame_Update" or "none (tracker updates from QUEST_WATCH_LIST_CHANGED)")
end
