-- WoW API stubs for Valhalla's Investments module and the window's tabs (box tests only)
local W = {}
_G.W = W
W.now = 1762700000
function time() return W.now end
function GetTime() return W.now end
W.frames = {}
W.blockedSetters = 0
W.calls = {}
local function Count(k) W.calls[k] = (W.calls[k] or 0) + 1 end
W.Count = Count

local Frame = {}
Frame.__index = function(t, k)
  local m = rawget(Frame, k)
  if m then return m end
  if type(k) == "string" and k:find("^%u") then return function() return nil end end   -- (other widget methods: no-ops)
  return nil
end
local function NewFrame(kind, name, parent)
  local f = setmetatable({ _kind = kind, _name = name, _parent = parent, _scripts = {}, _hooks = {}, _shown = true, _points = {}, _level = 1 }, Frame)
  return f
end
W.NewFrame = NewFrame
function Frame.SetScript(self, k, fn) self._scripts[k] = fn end
function Frame.GetScript(self, k) return self._scripts[k] end
function Frame.HookScript(self, k, fn) local h = self._hooks[k] or {} self._hooks[k] = h h[#h + 1] = fn end
function Frame.Show(self) local was = self._shown self._shown = true if not was then W.Run(self, "OnShow") end end
function Frame.Hide(self) local was = self._shown self._shown = false if was then W.Run(self, "OnHide") end end
function Frame.SetShown(self, v) if v then self:Show() else self:Hide() end end
function Frame.IsShown(self) return self._shown end
function Frame.IsVisible(self)
  local f = self
  for _ = 1, 50 do
    if not f then return true end
    if not f._shown then return false end
    f = rawget(f, "_parent")
  end
  return true
end
function Frame.GetParent(self) return self._parent end
function Frame.SetParent(self, p) self._parent = p end
function Frame.SetPoint(self, ...) self._points[#self._points + 1] = { ... } end
function Frame.ClearAllPoints(self) self._points = {} end
function Frame.SetAllPoints(self, rel) self._points = { { "ALL", rel } } end
function Frame.GetPoint(self, i) local p = self._points[i or 1] if p then return unpack(p) end end
function Frame.SetSize(self, w, h) self._w, self._h = w, h end
function Frame.SetWidth(self, w) self._w = w end
function Frame.SetHeight(self, h) self._h = h end
-- (v0.4.0.2) as the game does: asking a frame anchored by two points its size the first time lays it out
-- there and then and fires its OnSizeChanged (a handler's error caught, as the game catches each script's)
W.sizeFired, W.sizeDepth, W.sizeMaxDepth, W.sizeErrors = 0, 0, 0, {}
local function LayOut(self)
  if rawget(self, "_laid") or #self._points < 2 then return end
  self._laid = true
  W.sizeFired = W.sizeFired + 1
  W.sizeDepth = W.sizeDepth + 1
  if W.sizeDepth > W.sizeMaxDepth then W.sizeMaxDepth = W.sizeDepth end
  if W.sizeDepth > 50 then W.sizeDepth = W.sizeDepth - 1 error("OnSizeChanged nested 50 deep (a runaway)") end
  local ok, e = pcall(W.Run, self, "OnSizeChanged", rawget(self, "_w") or 800, rawget(self, "_h") or 600)
  if not ok then W.sizeErrors[#W.sizeErrors + 1] = e end
  W.sizeDepth = W.sizeDepth - 1
end
function Frame.GetWidth(self) LayOut(self) return rawget(self, "_w") or 800 end
function Frame.GetHeight(self) LayOut(self) return rawget(self, "_h") or 600 end
function Frame.SetFrameLevel(self, l) self._level = l end
function Frame.GetFrameLevel(self) return self._level end
function Frame.SetFrameStrata(self, s) self._strata = s end
function Frame.GetFrameStrata(self) return self._strata or "MEDIUM" end
function Frame.EnableMouse(self, v) self._mouse = v end
function Frame.EnableMouseWheel(self, v) self._wheel = v end
function Frame.SetPassThroughButtons() W.blockedSetters = W.blockedSetters + 1 end
function Frame.SetPropagateMouseClicks() W.blockedSetters = W.blockedSetters + 1 end
function Frame.SetBackdrop(self, b) self._backdrop = b end
function Frame.SetBackdropColor(self, r, g, b, a) self._bg = { r, g, b, a } end
function Frame.SetBackdropBorderColor(self, r, g, b, a) self._edge = { r, g, b, a } end
function Frame.RegisterEvent(self, e) local t = rawget(self, "_events") or {} self._events = t t[e] = true return true end
function Frame.UnregisterEvent(self, e) if self._events then self._events[e] = nil end end
function Frame.UnregisterAllEvents(self) self._events = {} end
function Frame.CreateTexture(self, _, layer) local t = NewFrame("Texture", nil, self) t._layer = layer return t end
function Frame.CreateLine(self, _, layer) local l = NewFrame("Line", nil, self) l._layer = layer return l end   -- (SetStartPoint, SetEndPoint, SetThickness: no-ops)
function Frame.CreateFontString(self) local f = NewFrame("FontString", nil, self) f._text = "" return f end
function Frame.SetTexture(self, t) self._tex = t end
function Frame.SetColorTexture(self, r, g, b, a) self._color = { r, g, b, a } end
function Frame.SetText(self, s) self._text = s if self._kind == "EditBox" and self._scripts.OnTextChanged then self._scripts.OnTextChanged(self) end end
function Frame.GetText(self) return self._text end
-- a font string's height at its width: about 6 px a character, 13 px a line (enough to catch overlaps)
function Frame.GetStringHeight(self)
  local t = tostring(self._text or "")
  if t == "" then return 0 end
  local w = rawget(self, "_w") or 800
  return math.ceil(#t * 6 / math.max(1, w)) * 13
end
function Frame.SetTextColor(self, r, g, b) self._tc = { r, g, b } end
function Frame.SetFocus(self) W.focus = self end
function Frame.ClearFocus(self) if W.focus == self then W.focus = nil end end
function Frame.HasFocus(self) return W.focus == self end
function Frame.SetDesaturated(self, v) self._desat = v end
function W.Run(f, script, ...)
  if f._scripts[script] then f._scripts[script](f, ...) end
  for _, h in ipairs(f._hooks[script] or {}) do h(f, ...) end
end
function Frame.SetAttribute(self, k, v) local a = rawget(self, "_attr") or {} self._attr = a a[k] = v end
function Frame.GetAttribute(self, k) local a = rawget(self, "_attr") return a and a[k] end
function Frame.Insert(self, t) self._text = (self._text or "") .. t end
-- a click; on a secure action button as the game does a mouse press: down then up, acting on the up
function W.Click(f, button)
  button = button or "LeftButton"
  if type(f._template) == "string" and f._template:find("SecureActionButtonTemplate", 1, true) then
    W.Run(f, "PreClick", button, true) W.Run(f, "PostClick", button, true)
    W.Run(f, "PreClick", button, false)
    if f:GetAttribute("type") == "click" and f:GetAttribute("clickbutton") then
      W.secureClicks = (W.secureClicks or 0) + 1
      W.Click(f:GetAttribute("clickbutton"), button)
    end
    W.Run(f, "PostClick", button, false)
    return
  end
  W.Run(f, "OnClick", button)
end

function CreateFrame(kind, name, parent, template)
  local f = NewFrame(kind, name, parent)
  f._template = template
  if kind == "EditBox" then f._text = "" end
  W.frames[#W.frames + 1] = f
  if name then _G[name] = f end
  return f
end
UIParent = NewFrame("Frame", "UIParent")
GameTooltip = NewFrame("GameTooltip")
GameFontHighlight, GameFontNormal = {}, {}
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
-- C_Timer.After(0): at once; later ones wait for W.RunTimers()
W.timers = {}
C_Timer = { After = function(d, fn) if (d or 0) <= 0 then fn() else W.timers[#W.timers + 1] = fn end end, NewTicker = function() return { Cancel = function() end } end }
function W.RunTimers() local t = W.timers W.timers = {} for _, fn in ipairs(t) do fn() end end
function InCombatLockdown() return W.combat end
function geterrorhandler() return function(e) error(e) end end
function hooksecurefunc(a, b, c)
  if type(a) == "table" then
    local old = a[b]
    a[b] = function(...) local r = { old(...) } c(...) return unpack(r) end
  else
    local old = _G[a]
    _G[a] = function(...) local r = { old(...) } b(...) return unpack(r) end
  end
end
function date(fmt, t) return "Nov 09 16:50" end
function GetBuildInfo() return "1.60.1", "70790", "Nov 1 2026", 16001 end
function GetRealmName() return "Forever" end
function UnitName(u) if u == "player" then return W.me or "Odysseaus" end if u == "npc" then return W.npcName end end
function UnitGUID(u) if u == "npc" and W.npc then return "Creature-0-1-2-3-" .. W.npc .. "-0000ABCD" end end

-- items
W.items = {
  [2589] = { "Linen Cloth", 132889 }, [2770] = { "Copper Ore", 134566 }, [2447] = { "Peacebloom", 133939 },
  [765] = { "Silverleaf", 134190 }, [4470] = { "Simple Wood", 135435 }, [2320] = { "Coarse Thread", 132891 },
  [3371] = { "Empty Vial", 134712 }, [2324] = { "Bleach", 134743 }, [2604] = { "Red Dye", 134732 },
  [6256] = { "Fishing Pole", 132932 }, [2321] = { "Fine Thread", 132912 }, [2678] = { "Mild Spices", 134059 },
  [3026] = { "Hunting Bow", 135490 },
}
W.uncached = {}
C_Item = {
  GetItemInfo = function(x)
    local id = tonumber(x) or (type(x) == "string" and tonumber(x:match("item:(%d+)")))
    if not id and type(x) == "string" then for i, v in pairs(W.items) do if v[1] == x then id = i end end end
    local v = id and W.items[id]
    if not v or W.uncached[id] then return nil end
    return v[1], ("|cffffffff|Hitem:%d::::::::|h[%s]|h|r"):format(id, v[1]), 1, 1, 1, "Trade Goods", "Cloth", 20, "", v[2], 10, 7, 5, (W.bind or {})[id]   -- (classID, subclassID, bindType: W.bind[id], 1 = bind on pickup)
  end,
  GetItemIconByID = function(id) return W.items[id] and W.items[id][2] end,
  RequestLoadItemDataByID = function(id) Count("requestLoad") end,
  GetItemCount = function(id, bank) return 0 end,
}
-- bags: W.bags[bag] = { { id, count }, ... } (slot order); bank tabs likewise, by bag ID
W.bags = {}
C_Container = {
  GetContainerNumSlots = function(bag) local b = W.bags[bag] return b and (b.size or #b) or 0 end,
  GetContainerItemInfo = function(bag, slot) local b = W.bags[bag] local s = b and b[slot] if s and s[1] then return { itemID = s[1], stackCount = s[2] } end end,
}
Enum = { BankType = { Character = 0, Account = 2 }, BagIndex = { Backpack = 0, ReagentBag = 5, CharacterBankTab_1 = 6, CharacterBankTab_2 = 7, CharacterBankTab_3 = 8, AccountBankTab_1 = 15 },
  PlayerInteractionType = { Merchant = 5, Banker = 8, CharacterBanker = 67, AccountBanker = 68 }, ForbiddenAspect = { ScriptedInput = 32 } }
W.bankTabs = { [0] = { 6, 7 }, [2] = { 15 } }
W.canViewAccount = true
C_Bank = {
  FetchPurchasedBankTabData = function(t) local out = {} for _, id in ipairs(W.bankTabs[t] or {}) do out[#out + 1] = { ID = id } end return out end,
  CanViewBank = function(t) return t ~= 2 or W.canViewAccount end,
  ShouldUsePlayerBagsInBank = function() return false end,
}
-- the cursor
function GetCursorInfo() if W.cursor then return "item", W.cursor end end
function ClearCursor() W.cursor = nil end
ChatFrameUtil = { InsertLink = function(text) Count("insertLink") return false end }
-- the bags' stack-split box, and a shift-click on a bag item as ContainerFrame.lua does it
StackSplitFrame = CreateFrame("Frame", "StackSplitFrame", UIParent)
StackSplitFrame._shown = false
function StackSplitFrame.OpenStackSplitFrame(self, maxStack, parent) self.owner = parent self:Show() end
function W.ShiftClickBag(link, stack)
  if ChatFrameUtil.InsertLink(link) then return end
  if (stack or 1) > 1 then StackSplitFrame:OpenStackSplitFrame(stack, {}) end
end
-- the mailbox
W.inbox = {}
function GetInboxNumItems() return #W.inbox end
function GetInboxItem(i, j) local m = W.inbox[i] local a = m and m[j] if a then return W.items[a[1]][1], a[1], 1, a[2] end end

-- the world map window
WorldMapFrame = CreateFrame("Frame", "WorldMapFrame", UIParent)
WorldMapFrame._shown = false
WorldMapFrame.ScrollContainer = CreateFrame("ScrollFrame", nil, WorldMapFrame)
WorldMapFrame.BorderFrame = CreateFrame("Frame", nil, WorldMapFrame)
WorldMapFrame._max = false
function WorldMapFrame.IsMaximized(self) return self._max end
-- as Blizzard_WorldMap.lua: the title from SetupTitle / SynchronizeDisplayState (Maximize/Minimize call it)
WorldMapFrame.TitleCanvasSpacerFrame = CreateFrame("Frame", nil, WorldMapFrame)
function WorldMapFrame.BorderFrame.SetTitle(self, t) self._title = t end
function WorldMapFrame.BorderFrame.GetTitleText(self) return self._title end
function WorldMapFrame.SynchronizeDisplayState(self)
  self.BorderFrame:SetTitle(self._max and "World Map" or "Map & Quest Log")
end
function WorldMapFrame.Maximize(self) self._max = true self:SynchronizeDisplayState() end
function WorldMapFrame.Minimize(self) self._max = false self:SynchronizeDisplayState() end
WorldMapFrame.BorderFrame:SetTitle("Map & Quest Log")
WorldMapFrame.QuestLog = CreateFrame("Frame", nil, WorldMapFrame)
-- the game's M and L (QuestLogOwnerMixin): M toggles the map; L closes it if its quest log is showing, else opens it with the log
function ToggleWorldMap() Count("toggleMap") if WorldMapFrame:IsShown() then WorldMapFrame:Hide() else WorldMapFrame:Show() end end
function ToggleQuestLog()
  Count("toggleLog")
  if WorldMapFrame:IsShown() and WorldMapFrame.QuestLog:IsShown() then WorldMapFrame:Hide()
  else WorldMapFrame.QuestLog:Show() WorldMapFrame:Show() end
end
function OpenQuestLog() WorldMapFrame.QuestLog:Show() WorldMapFrame:Show() end
function OpenWorldMap() WorldMapFrame:Show() end
function HideUIPanel(f) Count("HideUIPanel") f:Hide() end

-- the merchant: W.merchant = { itemID, ... } (with prices W.prices)
MERCHANT_ITEMS_PER_PAGE = 10
W.merchant = {}
W.prices = {}
MerchantFrame = CreateFrame("Frame", "MerchantFrame", UIParent)
MerchantFrame._shown = false
MerchantFrame.page, MerchantFrame.selectedTab = 1, 1
for i = 1, 10 do
  local slot = CreateFrame("Frame", "MerchantItem" .. i, MerchantFrame)
  slot._level = 3
  CreateFrame("Button", "MerchantItem" .. i .. "ItemButton", slot)
end
function GetMerchantNumItems() return #W.merchant end
function GetMerchantItemID(i) return W.merchant[i] end
C_MerchantFrame = { GetItemInfo = function(i) local id = W.merchant[i] if id then return { name = W.items[id][1], price = W.prices[id] or 10 } end end }
function MerchantFrame_UpdateMerchantInfo() Count("merchantUpdate") end
function MerchantFrame_UpdateBuybackInfo() Count("buybackUpdate") end
function BuyMerchantItem() Count("BuyMerchantItem") end

-- the auction house
function W.NewAH()
  local ah = CreateFrame("Frame", "AuctionHouseFrame", UIParent)
  ah.displayMode = "Buy"
  ah.SearchBar = CreateFrame("Frame", nil, ah)
  ah.SearchBar.SearchBox = CreateFrame("EditBox", nil, ah.SearchBar)
  function ah.SetSearchText(self, text)
    if self.displayMode ~= "Buy" then return false end
    self.SearchBar.SearchBox:SetText(text)
    W.searchText = text
    return true
  end
  function ah.SearchBar.StartSearch() Count("StartSearch") end
  -- the AH's own Search button (its OnClick: StartSearch)
  ah.SearchBar.SearchButton = CreateFrame("Button", nil, ah.SearchBar)
  ah.SearchBar.SearchButton:SetScript("OnClick", function() ah.SearchBar.StartSearch() end)
  function ah.SearchBar.SearchButton.HasAccessConstraints() return W.ahConstrained or false end
  function ah.SearchBar.SearchButton.HasAnyForbiddenAspects() return false end
  return ah
end
C_AuctionHouse = {
  ReplicateItems = function() Count("ReplicateItems") end,
  GetNumReplicateItems = function() return 31337 end,
  IsThrottledMessageSystemReady = function() return true end,
  PlaceBid = function() Count("PlaceBid") end,
  StartCommoditiesPurchase = function() Count("StartCommoditiesPurchase") end,
  ConfirmCommoditiesPurchase = function() Count("ConfirmCommoditiesPurchase") end,
  PostItem = function() Count("PostItem") end,
}

-- events: to frames that registered them
function W.Fire(event, ...)
  for _, f in ipairs(W.frames) do
    if rawget(f, "_events") and f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
  end
end
