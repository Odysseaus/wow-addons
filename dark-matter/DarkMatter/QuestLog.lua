-- 0.4.5 quest log reader for the Quests tab: quest text, objectives, rewards, the search haystack and /dm questprobe.
-- Every API is feature-detected and pcall'd; nothing is ever fabricated. The legacy quest-log reward functions read the
-- SELECTED log entry, so a read selects the entry briefly and puts Blizzard's previous selection back (the same pattern
-- quest addons use). Selecting can fire QUEST_LOG_UPDATE; NS.QL.reading is set meanwhile and static text/rewards are
-- cached per quest, so a read never loops into another read.
local _, NS = ...
local QL = {}
NS.QL = QL
QL.reading = false

local function G(name) local f = _G[name] if type(f) == "function" then return f end end
local function CQ(name) local t = _G.C_QuestLog if type(t) == "table" and type(t[name]) == "function" then return t[name] end end
local function Call(f, ...) if not f then return end local r = { pcall(f, ...) } if r[1] then return select(2, unpack(r)) end end

-- probe list: what the detail panel uses, in order of preference
QL.API = {
  { "C_QuestLog.GetInfo", "quest list (title, level, header, questID)" },
  { "C_QuestLog.GetQuestObjectives", "objective progress by questID" },
  { "GetNumQuestLeaderBoards", "objective fallback (by log index)" },
  { "GetQuestLogLeaderBoard", "objective fallback (by log index)" },
  { "C_QuestLog.GetLogIndexForQuestID", "log index by questID" },
  { "GetQuestLogIndexByID", "log index fallback" },
  { "GetQuestLogSelection", "remember the player's selection" },
  { "SelectQuestLogEntry", "select briefly for the readers below" },
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
  { "GetCoinTextureString", "money with coin icons" },
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

-- run fn with log entry `index` selected, then restore the player's selection
function QL.WithSelected(index, fn)
  local sel, get = G("SelectQuestLogEntry"), G("GetQuestLogSelection")
  if not (index and sel) then return false end
  local prev = NS.Num(Call(get))
  QL.reading = true
  pcall(sel, index)
  local ok = pcall(fn)
  if prev and prev ~= index then pcall(sel, prev) end
  QL.reading = false
  QL.lastSelect = (GetTime and NS.Num(GetTime())) or 0
  return ok
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
    local link = NS.Str(Call(G("GetQuestLogItemLink"), kind, i))
    local e = {
      kind = kind, index = i, name = NS.Str(name), icon = tex, count = NS.Num(count) or 1, quality = NS.Num(quality),
      usable = NS.Bool(usable), link = link, itemId = NS.Num(itemID) or ItemIdFrom(link),
    }
    if e.quality and e.quality < 0 then e.quality = nil end
    list[#list + 1] = e
  end
  return list, true
end

local cache = {}
function QL.Forget() cache = {} end

-- static quest data (text + rewards), read once per quest; nil fields = the client did not provide them
function QL.Details(q)
  local key = q.questID or q.title
  local d = cache[key]
  if d and not (d.partial and (d.tries or 0) < 3) then return d end
  local idx = LogIndex(q)
  d = { tries = (d and d.tries or 0) + 1, src = {} }
  local read = QL.WithSelected(idx, function()
    local desc, obj = Call(G("GetQuestLogQuestText"), idx)
    d.desc, d.objText = NS.Str(desc), NS.Str(obj)
    d.xp = NS.Num(Call(G("GetQuestLogRewardXP"), q.questID))
    d.money = NS.Num(Call(G("GetQuestLogRewardMoney"), q.questID))
    d.reqMoney = NS.Num(Call(G("GetQuestLogRequiredMoney"), q.questID))
    d.rewards, d.src.rewards = Items("reward", "GetNumQuestLogRewards", "GetQuestLogRewardInfo", q.questID)
    d.choices, d.src.choices = Items("choice", "GetNumQuestLogChoices", "GetQuestLogChoiceInfo", q.questID)
    local stex, sname = Call(G("GetQuestLogRewardSpell"))
    if NS.Str(sname) then d.spell = { name = sname, icon = stex } end
    d.honor = NS.Num(Call(G("GetQuestLogRewardHonor")))
    d.title = NS.Str(Call(G("GetQuestLogRewardTitle")))
    d.group = NS.Num(Call(G("GetQuestLogGroupNum")))
    d.rep = {}
    local nf = NS.Num(Call(G("GetNumQuestLogRewardFactions")))
    for i = 1, nf or 0 do
      local fid, amount = Call(G("GetQuestLogRewardFactionInfo"), i)
      fid, amount = NS.Num(fid), NS.Num(amount)
      local fname = fid and NS.Str(Call(G("GetFactionInfoByID"), fid))
      if amount and amount ~= 0 then d.rep[#d.rep + 1] = { name = fname or ("Faction " .. tostring(fid)), amount = amount } end
    end
  end)
  d.read = read
  d.partial = false
  for _, list in ipairs({ d.rewards or {}, d.choices or {} }) do
    for _, e in ipairs(list) do if not e.name then d.partial = true end end
  end
  cache[key] = d
  return d
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

-- money as gold/silver/copper with coin icons
function QL.Money(copper)
  copper = NS.Num(copper) or 0
  local s = NS.Str(Call(G("GetCoinTextureString"), copper))
  if s then return s end
  local g, si, c = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
  local out = {}
  local function coin(n, tex) out[#out + 1] = n .. "|TInterface\\MoneyFrame\\UI-" .. tex .. "Icon:0:0:2:0|t" end
  if g > 0 then coin(g, "Gold") end
  if si > 0 or (g > 0 and c > 0) then coin(si, "Silver") end
  if c > 0 or #out == 0 then coin(c, "Copper") end
  return table.concat(out, " ")
end

-- real item tooltip for a reward: SetQuestLogItem (entry selected briefly), else link, else item id
function QL.ShowRewardTooltip(owner, q, e)
  local tt = GameTooltip
  if not (tt and owner and e) then return end
  local idx = LogIndex(q)
  if tt.SetQuestLogItem and idx then
    tt:SetOwner(owner, "ANCHOR_RIGHT")
    local ok = false
    QL.WithSelected(idx, function() ok = pcall(tt.SetQuestLogItem, tt, e.kind, e.index) end)
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

-- /dm questprobe: which quest APIs exist, plus one sample read of the selected (or first) quest
function QL.ProbeReport()
  local lines, have, miss = {}, {}, {}
  for _, a in ipairs(QL.API) do
    if QL.Has(a[1]) then have[#have + 1] = a[1] else miss[#miss + 1] = a[1] .. " (" .. a[2] .. ")" end
  end
  lines[#lines + 1] = string.format("questprobe: %d of %d quest APIs present.", #have, #QL.API)
  lines[#lines + 1] = "present: " .. (#have > 0 and table.concat(have, ", ") or "none")
  lines[#lines + 1] = "missing: " .. (#miss > 0 and table.concat(miss, ", ") or "none")
  local q = NS.tabs and NS.tabs.quests and NS.tabs.quests.Selected and NS.tabs.quests.Selected()
  if q then
    local d = QL.Details(q)
    lines[#lines + 1] = string.format("sample \"%s\": text %s, xp %s, money %s, %d reward(s), %d choice(s)%s%s", q.title,
      d.desc and "yes" or "no", tostring(d.xp), tostring(d.money), #(d.rewards or {}), #(d.choices or {}),
      d.spell and ", spell" or "", #(d.rep or {}) > 0 and (", " .. #d.rep .. " reputation") or "")
  end
  if NS.db then NS.db.questprobe = { have = have, missing = miss, lines = lines } end
  return have, lines
end

---------------------------------------------------------------------------
-- 0.4.5 quest watch (the per-quest checkbox): two-way sync with the game's watch list
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

function QL.WatchCap()
  local cap = NS.Num(Call(CQ("GetMaxNumQuestsCanWatch")))
  if not cap and type(_G.MAX_WATCHABLE_QUESTS) == "number" then cap = _G.MAX_WATCHABLE_QUESTS end
  local n = NS.Num(Call(CQ("GetNumQuestWatches"))) or NS.Num(Call(G("GetNumQuestWatches")))
  return cap, n
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
  else
    local ok = false
    if q.questID and CQ("RemoveQuestWatch") then ok = pcall(CQ("RemoveQuestWatch"), q.questID) end
    if not ok and idx and G("RemoveQuestWatch") then ok = pcall(G("RemoveQuestWatch"), idx) end
    if not ok then return "noapi" end
  end
  QL.lastTracker = TrackerUpdate()
  return "ok"
end

QL.WATCH_EVENTS = { "QUEST_WATCH_LIST_CHANGED", "QUEST_WATCH_UPDATE", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN" }

function QL.WatchReport()
  local cap, n = QL.WatchCap()
  return string.format("watch: %s watched, cap %s; tracker refresh: %s", tostring(n), tostring(cap),
    G("QuestWatch_Update") and "QuestWatch_Update" or G("WatchFrame_Update") and "WatchFrame_Update" or "none (tracker updates from QUEST_WATCH_LIST_CHANGED)")
end
