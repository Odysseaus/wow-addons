-- Box tests for Valhalla/Investments (Lua 5.1). Run: lua valhalla/tests/investments/investments_test.lua [path to Valhalla/]
local here = (arg[0] or ""):match("^(.*[/\\])") or "./"
local root = arg[1] or (here .. "../../Valhalla/")
dofile(here .. "stubs.lua")

local ns = { modules = {}, version = "v0.4.0", Media = { path = "Interface\\AddOns\\Valhalla\\Media\\" } }
ns.L = setmetatable({}, { __index = function(_, k) return k end })
ns.Safe = { Value = function(v) return v end }
ns.Look = { Font = function(_, fs, size) fs._size = size return fs end }
ns.printed = {}
function ns:Print(fmt, ...) ns.printed[#ns.printed + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end
function ns:NewModule(key, spec) local m = spec or {} m.key = key m.defaults = m.defaults or {} if m.defaults.enabled == nil then m.defaults.enabled = true end self.modules[key] = m return m end
function ns:GetModule(key) return self.modules[key] end
ns.modules.worldmap = { key = "worldmap", enabled = true }
function ns.modules.worldmap.TabAway(away) ns.modules.worldmap.away = away end   -- (Map/Panel.lua: its menu put away on the other tabs)
assert(loadfile(root .. "Links.lua"))("Valhalla", ns)
for _, f in ipairs({ "Invest", "Scan", "Tabs", "Views", "Market", "Craft", "Merchant", "AHPanel" }) do
  assert(loadfile(root .. "Investments/" .. f .. ".lua"))("Valhalla", ns)
end
local mod = ns:GetModule("invest")
local I = mod.I
local T, M, A = I.Tabs, I.Merchant, I.AH

local pass, fail = 0, 0
local function ok(cond, name, detail)
  if cond then pass = pass + 1 print("PASS  " .. name)
  else fail = fail + 1 print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end
local function Keys(f) local t = {} for k in pairs(f) do t[#t + 1] = tostring(k) end table.sort(t) return table.concat(t, ",") end
local function Printed(pat) for _, s in ipairs(ns.printed) do if tostring(s):find(pat) then return true end end return false end
local function Find(parentPred) local out = {} for _, f in ipairs(W.frames) do if parentPred(f) then out[#out + 1] = f end end return out end
local function Slash(word, arg) mod:Slash(word, arg) end

-- the game's frames as Blizzard made them, to check Valhalla writes nothing on them
local mapKeys = Keys(WorldMapFrame)
local slotKeys = {}
for i = 1, 10 do slotKeys[i] = Keys(_G["MerchantItem" .. i]) end
local merchantKeys = Keys(MerchantFrame)

-- start as the game does: saved variables, then login
ValhallaInvestDB = nil
mod.db, mod.char, mod.enabled = { enabled = true }, {}, true
W.bags[0] = { { 2589, 12 }, { 2589, 8 }, { 2770, 30 }, size = 16 }
W.bags[5] = { { 2447, 4 }, size = 20 }      -- (the reagent bag)
W.bags[6] = { { 2589, 8 }, { 2447, 6 }, { 765, 2 } }   -- (bank tab 1: unreadable until the bank is open)
W.bags[15] = { { 2447, 1 } }                -- (the warband bank)
mod:OnEnable()

print("== 1. saved data: ValhallaInvestDB, its settings (graph style kept for Phase D), this character")
ok(type(ValhallaInvestDB) == "table" and ValhallaInvestDB.v == 1, "ValhallaInvestDB made")
ok(I.S.tabPos == "bottom" and I.S.graphStyle == "lines" and I.S.greyAlpha == 0.6 and I.S.countBank == true, "defaults: bottom tabs, lines, 60% grey, bank counted")
ok(ValhallaInvestDB.realms.Forever.chars.Odysseaus ~= nil, "this character's data under its realm")
ok(I.char.bags[2589] == 20 and I.char.bags[2447] == 4 and I.char.bags[2770] == 30, "bags counted (backpack and reagent bag)", I.char.bags[2589])
ok(next(I.char.bank) == nil and I.char.bankSeen == nil, "bank: not seen yet (only readable while open)")

print("== 2. the tabs on the map window")
ok(T.Attached(), "attached to WorldMapFrame")
ok(#T.Buttons() == 5, "five tabs")
local labels = {}
for i, b in ipairs(T.Buttons()) do labels[i] = b.label._text end
ok(table.concat(labels, "|") == "Map & Quest Log|Investments|Talents|Professions|Settings", "in order", table.concat(labels, "|"))
ok(T.Buttons()[3].tag and T.Buttons()[3].tag._text == "soon" and T.Buttons()[4].tag._text == "soon" and not T.Buttons()[2].tag, "Talents and Professions marked soon")
ok(T.Current() == "map" and not T.Host():IsShown(), "starts on Map & Quest Log, the view host hidden")
ok(T.Host()._strata == "HIGH" and T.Host()._level == 9920 and T.Host()._mouse == true, "host: HIGH strata over the map and quest log, takes the mouse")
local hp = T.Host()._points
ok(hp[1][2] == WorldMapFrame.ScrollContainer and hp[2][2] == WorldMapFrame, "host from the map's content top to its bottom edge (title strip left visible)")
local b1 = T.Buttons()[1]._points[1]
ok(b1[1] == "TOPLEFT" and b1[2] == WorldMapFrame and b1[3] == "BOTTOMLEFT" and b1[4] == 30, "bottom: hanging below the window, clear of the corner grips")

print("== 3. switching tabs")
WorldMapFrame:Show()
W.Click(T.Buttons()[2])
ok(T.Current() == "invest" and T.Host():IsShown() and T.Views().invest:IsShown(), "Investments: the host and its view")
ok(T.Views().invest.page.current == "list" and T.Views().invest.page.pages.list:IsShown(), "opens on the Shopping List (Smart Vendor is under construction)")
W.Click(T.Buttons()[3])
local tal = T.Views().talents
ok(tal:IsShown() and not T.Views().invest:IsShown() and tal.page.text._text == "Under construction: coming soon", "Talents: under construction, coming soon")
W.Click(T.Buttons()[4])
ok(T.Views().professions.page.text._text == "Under construction: coming soon" and T.Views().professions.page.title._text == "Professions", "Professions: under construction")
W.Click(T.Buttons()[1])
ok(T.Current() == "map" and not T.Host():IsShown(), "back to Map & Quest Log: the host hidden, the map as it was")
ok(Keys(WorldMapFrame) == mapKeys, "nothing written on WorldMapFrame", Keys(WorldMapFrame))
ok(T.Buttons()[1]._edge[1] == 1 and T.Buttons()[2]._edge[1] ~= 1, "the current tab edged gold")

print("== 4. full screen: no tabs, the map")
W.Click(T.Buttons()[2])
WorldMapFrame:Maximize()
ok(not T.Strip():IsShown() and not T.Host():IsShown() and T.Current() == "map", "maximized: tabs hidden, back on the map")
ok(not T.Select("invest") or T.Current() == "map", "no switching while maximized")
WorldMapFrame:Minimize()
ok(T.Strip():IsShown(), "windowed again: the tabs back")

print("== 5. opening the map: always Map & Quest Log, the other tabs truly hidden; L (and M) close it from any tab")
local function Tick() W.now = W.now + 1 end
local function OnMapTab() return WorldMapFrame:IsShown() and T.Current() == "map" and not T.Host():IsShown() and not T.Host():IsVisible() end
W.Click(T.Buttons()[2])
ok(T.Host():IsShown() and T.Views().invest:IsVisible(), "on Investments")
WorldMapFrame:Hide() Tick() WorldMapFrame:Show()
ok(T.Current() == "map" and not T.Host():IsShown() and not T.Views().invest:IsVisible(), "reopened: Map & Quest Log, the Investments panel hidden (v0.3.0 left it shown over the map)")
ok(T.Buttons()[1]._edge[1] == 1 and T.Buttons()[2]._edge[1] ~= 1, "and the Map & Quest Log tab lit")
W.Click(T.Buttons()[3]) WorldMapFrame:Hide() Tick()
ToggleWorldMap()
ok(OnMapTab() and not T.Views().talents:IsVisible(), "M (left on Talents): opens on Map & Quest Log, Talents hidden")
W.Click(T.Buttons()[2]) WorldMapFrame:Hide() WorldMapFrame.QuestLog:Hide() Tick()
ToggleQuestLog()
ok(OnMapTab() and not T.Views().invest:IsVisible(), "L (left on Investments): opens on Map & Quest Log, Investments hidden")
Tick() W.Click(T.Buttons()[2]) WorldMapFrame.QuestLog:Hide()
ToggleQuestLog()
ok(not WorldMapFrame:IsShown(), "L, open on Investments (the log hidden underneath): closes the window")
WorldMapFrame:Show() Tick() WorldMapFrame.QuestLog:Hide()
ToggleQuestLog()
ok(not WorldMapFrame:IsShown(), "L, open on Map & Quest Log with its log folded away: closes too (any tab)")
WorldMapFrame:Show() Tick() W.Click(T.Buttons()[4]) WorldMapFrame.QuestLog:Show()
ToggleQuestLog()
ok(not WorldMapFrame:IsShown(), "L, open on Professions: closed")
WorldMapFrame:Show() Tick() W.Click(T.Buttons()[2])
ToggleWorldMap()
ok(not WorldMapFrame:IsShown(), "M, open on Investments: closed")
WorldMapFrame:Show() Tick() W.Click(T.Buttons()[2]) WorldMapFrame.QuestLog:Hide()
W.combat = true W.calls.HideUIPanel = 0
ToggleQuestLog()
ok(W.calls.HideUIPanel == 0 and OnMapTab(), "L in combat: Valhalla doesn't close it, back on Map & Quest Log")
W.combat = false
Tick() W.Click(T.Buttons()[2])
OpenQuestLog()
ok(OnMapTab(), "the quest log opened from elsewhere (a quest clicked): Map & Quest Log")
ok(I.S.rememberTab == nil and I.S.tab == nil, "no 'last tab' setting any more")
ok(Keys(WorldMapFrame) == mapKeys, "nothing written on WorldMapFrame (the keys' global functions hooked)")
W.Click(T.Buttons()[1])
WorldMapFrame:Hide()
W.calls.toggleMap = 0
Slash("tab", "invest")
ok(W.calls.toggleMap == 1 and WorldMapFrame:IsShown() and T.Current() == "invest", "/valhalla tab invest opens the map on Investments")
Slash("tab", "talents")
ok(T.Current() == "talents", "/valhalla tab talents")
Slash("tab", "bogus")
ok(Printed("tab map|invest|talents|professions|settings"), "a wrong tab: says which there are")
WorldMapFrame:Hide()
W.combat = true W.calls.toggleMap = 0
Slash("tab", "invest")
ok(W.calls.toggleMap == 0 and Printed("can't be opened in combat"), "in combat: the map isn't opened")
W.combat = false
WorldMapFrame:Show()
Slash("invest", "settings")
ok(T.Current() == "settings" and T.Views().settings:IsShown() and T.Views().settings.page.key == "settings", "/valhalla invest settings: the Settings tab")
local act = ns.InvestAction(function(n) return { texture = n } end)
W.Click(T.Buttons()[1])
act.run()
ok(act[1] == "Investments" and T.Current() == "invest" and act.lit(), "the map menu's Investments opens the tab")

print("== 6. tab placement: bottom, top, side")
local function SetPos(p) I.S.tabPos = p T.Layout() end
SetPos("top")
local tp = T.Buttons()[1]._points[1]
ok(tp[2] == T.Host() and tp[1] == "TOPLEFT" and tp[5] == -3, "top: a row at the top of the content")
local vp = T.Views().invest._points[1]
ok(vp[1] == "TOPLEFT" and vp[3] == -(T.TAB_H + 6), "top: the views start under it")
SetPos("side")
local sp = T.Buttons()[2]._points[1]
ok(sp[2] == WorldMapFrame and sp[3] == "TOPRIGHT" and T.Buttons()[2]._w == 40 and T.Buttons()[2].icon._shown and not T.Buttons()[2].label._shown, "side: icons down the right edge")
SetPos("bottom")
ok(T.Buttons()[1]._points[1][3] == "BOTTOMLEFT" and T.Buttons()[1].label._shown, "bottom again")
WorldMapFrame._w = 480
T.Layout()
ok(T.Buttons()[1]._w < 132 and T.Buttons()[1]._w >= 80, "a narrow window: narrower tabs", T.Buttons()[1]._w)
WorldMapFrame._w = nil T.Layout()

local function MakeList(name, items)
  I.DraftClear()
  I.DraftName(name)
  for _, it in ipairs(items) do I.DraftAdd(it[1], it[2]) if it[3] then I.DraftKeep(it[1], true) end end
  return I.BuildList()
end

print("== 7. the builder (a draft) and a saved list: haves and needs")
ok(type(I.char.lists) == "table" and #I.Lists() == 0 and I.ActiveList() == nil, "no lists yet (no old wants to bring over)")
ns.printed = {}
ok(I.BuildList() == nil and Printed("Add an item first"), "an empty builder: nothing built")
I.DraftAdd(2589)
ok(I.Draft().items[1].id == 2589 and I.Draft().items[1].n == 0, "added: how many starts at 0")
ns.printed = {}
ok(I.BuildList() == nil and Printed("Set how many") and #I.Lists() == 0, "all 0: nothing built, says why")
I.DraftSet(2589, 40) I.DraftAdd(2447, 20) I.DraftAdd(765, 20) I.DraftAdd(4470, 10) I.DraftAdd(2770, 30) I.DraftAdd(2324)
ok(not I.DraftAdd(2589) and #I.Draft().items == 6, "the same item twice: once")
ns.printed = {}
local L1 = I.BuildList()
ok(L1 and L1.name == "List 1" and #L1.items == 5 and Printed("'List 1' saved %(5 items%)") and Printed("1 with 0 left out"), "Build: no name: 'List 1'; the 0 left out, said", ns.printed[1])
ok(#I.Draft().items == 0 and I.Draft().name == "" and #I.Lists() == 1, "the builder cleared, the list saved")
ok(I.ActiveList() == L1 and I.char.activeList == L1.id, "the only list: active")
local function Row(id) for _, r in ipairs(I.ListRows(I.ActiveList())) do if r.id == id then return r end end end
ok(Row(2589).need == 20 and Row(2589).bags == 20 and Row(2589).bank == 0, "Linen Cloth: 20 in bags, bank unseen: need 20")
ok(Row(2770).need == 0, "Copper Ore: 30 of 30: done")
W.Fire("BANKFRAME_OPENED")
ok(I.char.bank[2589] == 8 and I.char.bank[2447] == 6 and I.char.bankSeen == W.now, "bank opened: its tabs read, time noted")
ok(ValhallaInvestDB.account.bank[2447] == 1, "the warband bank too")
ok(Row(2589).need == 12 and Row(2447).need == 9 and Row(765).need == 18, "needs count the bank (20+8 of 40; 4+6+1 of 20; 2 of 20)", Row(2447).need)
W.Fire("BANKFRAME_CLOSED")
W.bags[6] = {}
W.now = W.now + 3600
W.Fire("BAG_UPDATE_DELAYED")
ok(I.char.bank[2589] == 8 and I.char.bankSeen == W.now - 3600, "bank closed: the snapshot kept (not re-read)")
I.S.countBank = false
ok(Row(2589).need == 20, "Count bank off: bags only")
I.S.countBank = true
W.bags[0][1] = { 2589, 20 }
W.Fire("BAG_UPDATE_DELAYED")
ok(Row(2589).bags == 28 and Row(2589).need == 4, "bags counted live as they change")
ValhallaInvestDB.realms.Forever.chars.Alt = { bags = { [765] = 10 }, bank = { [765] = 5 }, want = {} }
ok(Row(765).need == 18, "alts not counted by default")
I.S.countAlts = true
ok(Row(765).need == 3 and Row(765).alts == 15, "Count my other characters: 2 + 15 of 20")
I.S.countAlts = false

print("== 8. typing items; Edit; /valhalla want and unwant (the builder); the search")
ok(I.ParseItem("|cffffffff|Hitem:2320::::::::|h[Coarse Thread]|h|r") == 2320, "a link")
ok(I.ParseItem("item:3371") == 3371 and I.ParseItem("2321") == 2321, "item:ID and an ID")
ok(I.ParseItem("Silverleaf") == 765, "a name the game knows")
ok(I.EditList(L1.id) and I.Draft().editing == L1.id and I.Draft().name == "List 1" and #I.Draft().items == 5, "Edit: the list back in the builder")
ns.printed = {}
Slash("want", "|cffffffff|Hitem:2320::::::::|h[Coarse Thread]|h|r 15 reagent")
ok(I.LineOf(I.Draft(), 2320) and I.LineOf(I.Draft(), 2320).n == 15 and Printed("In the builder: Coarse Thread x15"), "/valhalla want <link> 15 (an old category word ignored): into the builder")
Slash("want", "Simple Wood 12 mat")
ok(I.LineOf(I.Draft(), 4470).n == 12, "/valhalla want Simple Wood 12: its count set")
Slash("want", "3026 gear")
ok(I.LineOf(I.Draft(), 3026) and I.LineOf(I.Draft(), 3026).n == 0, "/valhalla want 3026: added with 0")
Slash("unwant", "3026")
ok(I.LineOf(I.Draft(), 3026) == nil and Printed("Out of the builder: Hunting Bow"), "/valhalla unwant")
Slash("want", "Nonexistent Thing 3")
ok(Printed("Which item%?"), "an unknown name: asks for a link or ID")
W.uncached[2321] = true
I.DraftAdd(2321, 5)
ok(I.ItemName(2321) == "item:2321" and (W.calls.requestLoad or 0) > 0, "an item not loaded yet: asked for, shown by ID")
W.uncached[2321] = nil
W.Fire("GET_ITEM_INFO_RECEIVED", 2321)
ok(I.LineOf(I.Draft(), 2321).name == "Fine Thread", "named once the game sends it")
I.DraftRemove(2321)
local found = I.SearchItems("thread")
ok(#found == 1 and found[1] == 2320, "search 'thread': what Valhalla has seen with that in its name", table.concat(found, ","))
ok(I.SearchItems("silver")[1] == 765 and I.SearchItems("item:2678")[1] == 2678 and #I.SearchItems("") == 0, "search: part of a name, a link or an ID; nothing typed: nothing")
ns.printed = {}
local L1b = I.BuildList()
ok(L1b == L1 and #I.Lists() == 1 and L1.name == "List 1" and #L1.items == 6 and L1.items[4].n == 12 and L1.items[6].id == 2320 and I.Draft().editing == nil, "saved in place (Edit): the same list, now 6 items")
ok(ValhallaInvestDB.realms.Forever.chars.Odysseaus.want and next(ValhallaInvestDB.realms.Forever.chars.Odysseaus.want) == nil, "the old want list: not written")

print("== 9. the active list: by where to buy")
local list = I.ShoppingList()
ok(#list.vendor == 0 and #list.ah == 5 and list.done == 1 and list.total == 6 and list.name == "List 1", "no vendor seen yet: all from the AH", #list.ah)
W.npc, W.npcName = 1250, "Trade Supplies"
W.merchant = { 4470, 2604, 6256, 2320, 2324, 2678, 3371, 2321, 2604, 2604, 2320 }
W.prices[4470] = 38
MerchantFrame:Show()
W.Fire("MERCHANT_SHOW")
local m = ValhallaInvestDB.realms.Forever.merchants[1250]
ok(m and m.name == "Trade Supplies" and m.items[4470] == 38, "the merchant's wares saved (by NPC)")
list = I.ShoppingList()
local vendorNames = {}
for _, r in ipairs(list.vendor) do vendorNames[#vendorNames + 1] = r.name end
ok(table.concat(vendorNames, ",") == "Simple Wood,Coarse Thread" and #list.ah == 3, "Simple Wood and Coarse Thread: vendor; the rest: AH", table.concat(vendorNames, ","))
ok(list.vendor[1].vendor == "Trade Supplies", "and which vendor")
Slash("list", "")
ok(Printed("Shopping list 'List 1' %(1 of 6 done%)") and Printed("Vendor: Simple Wood x12"), "/valhalla list: the active list")

print("== 10. the merchant: the active list's items glow, the rest greyed (still buyable); its picker")
MerchantFrame_UpdateMerchantInfo()
local ov = M.Overlays()
ok(ov[1] and ov[1]:IsShown() and ov[1].glow._shown and ov[1].tag._shown and ov[1].tag._text == "need 12" and not ov[1].wash._shown, "Simple Wood: gold glow, 'need 12'")
ok(ov[4].glow._shown and ov[4].tag._text == "need 15", "Coarse Thread: 'need 15'")
ok(ov[2]:IsShown() and ov[2].wash._shown and not ov[2].glow._shown and ov[2].wash._color[4] == 0.6, "Red Dye: greyed (60%)")
local mouse = false
for _, o in pairs(ov) do if o._mouse ~= nil then mouse = true end end
ok(not mouse, "the overlays take no mouse: every click is the game's")
local written = false
for i = 1, 10 do if Keys(_G["MerchantItem" .. i]) ~= slotKeys[i] then written = true end end
ok(not written and Keys(MerchantFrame) == merchantKeys, "nothing written on the merchant's frames")
ok((W.calls.BuyMerchantItem or 0) == 0, "nothing bought")
MerchantFrame.page = 2
MerchantFrame_UpdateMerchantInfo()
ok(ov[1]:IsShown() and ov[1].tag._text == "need 15" and not ov[2]:IsShown(), "page 2: item 11 (Coarse Thread) on slot 1; empty slots clear")
MerchantFrame.page = 1
I.S.showNeed = false MerchantFrame_UpdateMerchantInfo()
ok(ov[1].glow._shown and not ov[1].tag._shown, "'need N' off: the glow alone")
I.S.showNeed = true
I.S.greyAlpha = 0.8 MerchantFrame_UpdateMerchantInfo()
ok(ov[2].wash._color[4] == 0.8, "grey-out strength follows the setting")
I.S.greyAlpha = 0.6
MerchantFrame.selectedTab = 2
MerchantFrame_UpdateBuybackInfo()
ok(not ov[1]:IsShown() and not ov[2]:IsShown() and not M.Picker():IsShown(), "buyback tab: nothing drawn")
MerchantFrame.selectedTab = 1 MerchantFrame_UpdateMerchantInfo()
I.S.hiVendor = false MerchantFrame_UpdateMerchantInfo()
ok(not ov[1]:IsShown() and not M.Picker():IsShown(), "highlighting off: nothing drawn, no picker")
I.S.hiVendor = true MerchantFrame_UpdateMerchantInfo()
local L2 = MakeList("Other", { { 4470, 3 } })
ok(#I.Lists() == 2 and I.ActiveList() == L1, "a second list: the active one stays")
local pk = M.Picker()
local ppt = pk._points[1]
ok(pk:IsShown() and pk.text._text == "List: List 1  v" and pk._parent == MerchantFrame and ppt[1] == "BOTTOMRIGHT" and ppt[3] == "TOPRIGHT", "above the merchant window's top right: which list", pk.text._text)
-- bought: the bags fill; the lists stay as they are (v0.3.3), the glow too, now "Done"
W.bags[1] = { { 4470, 12 }, { 2320, 15 } }
ns.printed, I.undo = {}, {}
W.Fire("BAG_UPDATE_DELAYED")
ok(#L1.items == 6 and I.LineOf(L1, 4470).n == 12 and I.LineOf(L1, 2320).n == 15 and #L2.items == 1 and L2.items[1].n == 3, "bought enough: no list changes (nothing taken off, no counts changed)")
ok(#ns.printed == 0 and I.LastUndo() == nil, "nothing said in chat, nothing to undo")
ok(ov[1]:IsShown() and ov[1].glow._shown and ov[1].tag._text == "Done" and ov[4].glow._shown and ov[4].tag._text == "Done" and not ov[1].wash._shown, "still glowing, tagged Done")
ok(ov[2]:IsShown() and ov[2].wash._shown, "the rest still greyed")
W.bags[1] = { { 4470, 2 } }
W.Fire("BAG_UPDATE_DELAYED")
ok(ov[1].tag._text == "need 10" and I.LineOf(L1, 2320), "need updates as you use them (and they stay listed)")
W.Click(pk)
ok(pk.menu:IsShown() and pk.menu.items[1].text._text == "None" and pk.menu.items[2].text._text == "> List 1" and pk.menu.items[3].text._text == "Other" and not pk.menu.items[4]:IsShown(), "its menu: None, then your lists, the active one marked")
W.Click(pk.menu.items[3])
ok(I.ActiveList() == L2 and I.char.activeList == L2.id and not pk.menu:IsShown() and pk.text._text == "List: Other  v", "Other chosen: active (remembered)")
ok(ov[1].tag._text == "need 1" and ov[4]:IsShown() and ov[4].wash._shown and not ov[4].glow._shown, "the highlights follow at once: Simple Wood need 1; Coarse Thread (not on Other) greyed")
W.Click(pk) W.Click(pk.menu.items[2])
ok(I.ActiveList() == L1 and ov[1].tag._text == "need 10", "back to List 1")
W.combat = true MerchantFrame_UpdateMerchantInfo() W.combat = false
ok(W.blockedSetters == 0, "no mouse pass-through setters, ever")
W.Fire("MERCHANT_CLOSED") MerchantFrame:Hide()
ok(not ov[1]:IsShown() and not pk:IsShown(), "merchant closed: gone")

print("== 11. the Auction House's list: the active list, one-click Search (the AH's own Search button), minimize")
W.NewAH()
W.combat = true
W.Fire("AUCTION_HOUSE_SHOW")
ok(A.Panel() == nil and A.waiting, "opened in combat: the list waits (secure buttons aren't made in combat)")
W.combat = false
W.Fire("PLAYER_REGEN_ENABLED")
local p = A.Panel()
ok(p and p:IsShown() and p._parent == AuctionHouseFrame, "beside the AH")
ok(p.picker and p.picker.text._text == "List: List 1  v", "under its title: which list")
local function Shown() local t = {} for _, r in ipairs(p.rows) do if r:IsShown() then t[#t + 1] = r.name._text end end return table.concat(t, ",") end
ok(Shown() == "Linen Cloth,Peacebloom,Silverleaf,Copper Ore", "the list's AH items, Copper Ore (enough) too", Shown())
ok(p.rows[1].need._text == "x4" and p.rows[4].need._text == "Done", "still needed, or Done")
W.Click(p.picker) W.Click(p.picker.menu.items[3])
ok(Shown() == "" and p.empty:IsShown() and p.empty._text == "Nothing on this list from the Auction House.", "Other chosen here: its list at once (nothing from the AH)")
W.Click(p.picker) W.Click(p.picker.menu.items[2])
ok(Shown() == "Linen Cloth,Peacebloom,Silverleaf,Copper Ore" and I.ActiveList() == L1, "List 1 again")
local sb = p.rows[1].search
ok(sb._template:find("SecureActionButtonTemplate", 1, true) and sb:GetAttribute("type") == "click" and sb:GetAttribute("clickbutton") == AuctionHouseFrame.SearchBar.SearchButton,
	"Search: a secure click whose target is the AH's own Search button")
W.calls.StartSearch, W.secureClicks = 0, 0
W.Click(sb)
ok(W.searchText == "Linen Cloth" and W.calls.StartSearch == 1 and W.secureClicks == 1, "one click: the name in, the AH's own Search button pressed (its own search runs)")
ok(sb:GetAttribute("type") == "click" and A.pending and A.last == "clicked", "set for the next click; waiting for the AH's answer")
W.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
W.RunTimers()
ok(A.last == "searched" and A.pending == nil, "the AH answered: no fallback")
ns.printed = {}
W.Click(p.rows[3].search)
W.RunTimers()
ok(W.searchText == "Silverleaf" and A.last == "no answer" and W.focus == AuctionHouseFrame.SearchBar.SearchBox and Printed("press Enter"), "no answer from the AH: the name's in its box, focused: press Enter")
W.ahConstrained = true
W.calls.StartSearch, ns.printed = 0, {}
W.Click(p.rows[2].search)
ok(W.searchText == "Peacebloom" and W.calls.StartSearch == 0 and W.focus == AuctionHouseFrame.SearchBar.SearchBox and Printed("press Enter") and A.last == "fallback:blocked",
	"the game won't let the button be clicked: no click, the name in the box, focused: press Enter")
ok(sb:GetAttribute("type") == "click", "and the button set again for next time")
W.ahConstrained = false
AuctionHouseFrame.displayMode = "Sell"
W.calls.StartSearch = 0
W.Click(p.rows[3].search)
ok(Printed("Browse tab") and W.searchText == "Peacebloom" and W.calls.StartSearch == 0, "not on Browse: says so, no search")
AuctionHouseFrame.displayMode = "Buy"
ok((W.calls.PlaceBid or 0) + (W.calls.StartCommoditiesPurchase or 0) + (W.calls.ConfirmCommoditiesPurchase or 0) + (W.calls.PostItem or 0) == 0, "never buys, bids or posts")
I.S.ahPanel = false A.Refresh()
ok(not p:IsShown() and not A.Mini():IsShown(), "AH list off: hidden, its button too")
I.S.ahPanel = true A.Refresh()
ok(p.minimize.text._text == "-" and #Find(function(f) return f._parent == p and f.text and f.text._text == "x" end) == 0, "no close X: a minimize -")
W.Click(p.minimize)
ok(not p:IsShown() and A.Mini():IsShown() and A.Mini().count._text == "3" and I.S.ahPanelMin == true, "-: minimized to a small button with how many are needed")
local mpt = A.Mini()._points[1]
ok(A.Mini()._parent == AuctionHouseFrame and mpt[1] == "TOPLEFT" and mpt[2] == AuctionHouseFrame and mpt[3] == "TOPRIGHT", "at the AH's top right")
I.Changed()
ok(not p:IsShown() and A.Mini():IsShown(), "stays minimized as things change")
W.Fire("AUCTION_HOUSE_CLOSED")
ok(not A.Mini():IsShown(), "AH closed: gone")
W.Fire("AUCTION_HOUSE_SHOW")
ok(not p:IsShown() and A.Mini():IsShown(), "next visit: still minimized (remembered)")
W.Click(A.Mini())
ok(p:IsShown() and not A.Mini():IsShown() and I.S.ahPanelMin == false, "its button: the list back")
W.Fire("AUCTION_HOUSE_CLOSED") W.Fire("AUCTION_HOUSE_SHOW")
ok(p:IsShown() and not A.Mini():IsShown(), "next visit: shown (remembered)")

print("== 12. /valhalla invest diag: saved to the saved log")
ValhallaInvestDB.diag = {}
I.bankOpen = false
Slash("invest", "diag replicate")
local d = ValhallaInvestDB.diag[1]
ok(d and d.apis["C_AuctionHouse.ReplicateItems"] == true and d.apis["QueryAuctionItems"] == false, "which APIs this client has (no QueryAuctionItems)")
ok(d.toc == 16001 and d.version == "v0.4.0", "client and version")
ok(d.bankInfo and d.bankInfo.seen and d.bankInfo.read.tabs == 2 and d.bankInfo.events.BANKFRAME_OPENED == 1, "the bank: last read, its tabs, which event said it opened")
ok(d.ah.search and d.ah.search.button == true and d.ah.search.blocked == false, "the AH's Search button: there, and clickable for one-click Search")
ok(d.counts.linen.id == 2589 and d.counts.linen.bagsSeen == 28, "counts for Linen Cloth, Copper Ore, Peacebloom")
ok(d.list.lists == 2 and d.list.active == "List 1" and d.list.wanted == 6 and d.list.oldWants == 0, "the lists: how many, which is active, its lines")
ok(d.open.ah == true and W.calls.ReplicateItems == 1 and d.ah.replicateCalled, "at the AH: replicate asked for")
W.Fire("REPLICATE_ITEM_LIST_UPDATE")
ok(d.ah.replicateCount == 31337 and type(d.ah.replicateSeconds) == "number", "its answer saved")
ok(Printed("Saved in ValhallaInvestDB.diag"), "says it's saved (/reload to write it)")
for _ = 1, 12 do I.Diag() end
ok(#ValhallaInvestDB.diag == 10, "keeps the last 10")
W.Fire("AUCTION_HOUSE_CLOSED")

print("== 13. Smart Vendor (under construction); the Shopping List page's builder")
WorldMapFrame:Show()
Slash("invest", "vendor")
local root = T.Views().invest.page
ok(root.current == "vendor" and root.pages.vendor.title._text == "Under construction: coming soon", "Smart Vendor: under construction, coming soon")
root:ShowPage("list")
local lp = root.pages.list
ok(lp:IsShown() and lp.build.text._text == "Build Shopping List" and lp.builderHead._text == "New list" and lp.nameHint._text == "Empty: it's named List 2", "the builder: New list, Build Shopping List; an empty name will be List 2", lp.nameHint._text)
lp.search:SetText("vial")
ok(lp.results:IsShown() and lp.results.rows[1].name._text == "Empty Vial" and lp.results.rows[1].act.text._text == "Add" and not lp.results.rows[2]:IsShown(), "part of a name: what matches (from the vendor's wares), with Add")
W.Click(lp.results.rows[1].act)
ok(I.LineOf(I.Draft(), 3371) and I.LineOf(I.Draft(), 3371).n == 0 and lp.results.rows[1].act.text._text == "Remove", "Add: into the list (0); the match now says Remove")
W.Click(lp.results.rows[1].act)
ok(not I.LineOf(I.Draft(), 3371) and lp.results.rows[1].act.text._text == "Add", "Remove: out again")
W.Click(lp.results.rows[1].act)
lp.search:SetText("red d")
lp.AddTop()
ok(I.LineOf(I.Draft(), 2604) and lp.search._text == "" and not lp.results:IsShown(), "Enter: the top match added, the box cleared")
W.cursor = 2321
lp.Drop()
ok(I.LineOf(I.Draft(), 2321) and W.cursor == nil, "an item dropped on the box: added")
lp.search:SetFocus()
W.now = W.now + 1
W.ShiftClickBag("|cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r", 20)
ok(I.LineOf(I.Draft(), 2589) and not StackSplitFrame:IsShown() and ns.Links.suppressed == 1, "shift-click a stack while the search box has the cursor: added, no stack-split box")
local function DRow(id) for _, r in ipairs(lp.drows) do if r:IsShown() and r.id == id then return r end end end
lp.search:ClearFocus() DRow(3371).qty:SetFocus() W.now = W.now + 1
W.ShiftClickBag("|cffffffff|Hitem:2678::::::::|h[Mild Spices]|h|r", 5)
ok(I.LineOf(I.Draft(), 2678) and not StackSplitFrame:IsShown(), "a how-many box has the cursor: that item into the list, no split box")
DRow(3371).qty:ClearFocus() W.now = W.now + 1
W.ShiftClickBag("|cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r", 20)
ok(StackSplitFrame:IsShown() and ns.Links.suppressed == 2, "no Valhalla box has the cursor: the game's own split box, as always")
StackSplitFrame:Hide()
lp.search:SetFocus() W.now = W.now + 1
W.ShiftClickBag("|cff71d5ff|Hspell:133::::::::|h[Fireball]|h|r", 1)
StackSplitFrame:OpenStackSplitFrame(20, {})
ok(StackSplitFrame:IsShown() and #I.Draft().items == 5, "a link the box doesn't take: nothing taken, the split box untouched")
StackSplitFrame:Hide() lp.search:ClearFocus()
local note = CreateFrame("EditBox")
ns.LinkBox(note)
note:SetFocus() W.now = W.now + 1
W.ShiftClickBag("|cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r", 20)
ok(note._text == "Linen Cloth" and not StackSplitFrame:IsShown(), "a Valhalla note box (map pin): the item's name, no split box")
note:ClearFocus()
local r1 = DRow(2589)
ok(r1.bags._text == "28" and r1.bank._text == "8" and r1.qty._text == "0", "a row: Bags, Bank, how many (0)", r1.bags._text .. "/" .. r1.bank._text)
W.Click(r1.plus) W.Click(r1.plus)
ok(I.LineOf(I.Draft(), 2589).n == 2 and DRow(2589).qty._text == "2", "+ raises it")
W.Click(DRow(2589).minus)
ok(I.LineOf(I.Draft(), 2589).n == 1, "- lowers it")
W.Click(DRow(2589).minus) W.Click(DRow(2589).minus)
ok(I.LineOf(I.Draft(), 2589).n == 0, "never below 0")
local q = DRow(3371).qty
q:SetFocus() q:SetText("7") W.Run(q, "OnEnterPressed")
ok(I.LineOf(I.Draft(), 3371).n == 7 and not q:HasFocus(), "typed: 7")
ok(DRow(2604).keep == nil and #Find(function(f) return f._parent == DRow(2604) and f.tick end) == 0, "no Keep tick any more")
W.Click(DRow(2604).plus) W.Click(DRow(2604).plus) W.Click(DRow(2604).plus)
W.Click(DRow(2321).plus) W.Click(DRow(2321).plus)
W.Click(DRow(2678).remove)
ok(not I.LineOf(I.Draft(), 2678), "x removes it")
lp.name:SetText("Alchemy")
ok(I.Draft().name == "Alchemy", "the name box")
ns.printed = {}
W.Click(lp.build)
local L3 = I.Lists()[3]
ok(L3 and L3.name == "Alchemy" and #L3.items == 3 and L3.items[2].keep == nil and Printed("1 with 0 left out") and #I.Draft().items == 0 and lp.name._text == "", "Build Shopping List: 'Alchemy' saved below (Linen at 0 left out), the builder cleared")
ok(I.ActiveList() == L1, "the active list stays List 1")

print("== 14. the saved lists below (live); Edit, Delete (Undo); AH Market, Settings")
lp:Refresh()
local function Lines() local t = {} for _, ln in ipairs(lp.lines) do if ln:IsShown() then t[#t + 1] = ln end end return t end
local ls = Lines()
ok(ls[1].name._text == "List 1  (active)" and ls[1].edit:IsShown() and ls[1].delete:IsShown() and ls[1].where._text == "6 items", "each list: its name (active marked), Edit, Delete", ls[1].name._text)
ok(ls[2].name._text == "Linen Cloth" and ls[2].count._text == "x4" and ls[2].where._text == "Auction House" and not ls[2].edit:IsShown(), "its items beneath: still needed (bags and bank), where", ls[2].count._text)
ok(ls[5].name._text == "Simple Wood" and ls[5].count._text == "x10" and ls[5].where._text == "at Trade Supplies", "a vendor's item: at that vendor")
ok(ls[6].name._text == "Copper Ore" and ls[6].count._text == "Done", "had enough: Done")
ok(ls[8].name._text == "Other" and ls[9].name._text == "Simple Wood" and ls[9].count._text == "x1" and ls[10].name._text == "Alchemy", "the next lists, each with its items")
W.Run(lp, "OnMouseWheel", -1)
ok(lp.offset == 1 and Lines()[12].name._text == "Fine Thread", "the wheel scrolls the lists")
W.Run(lp, "OnMouseWheel", 1)
ns.printed = {}
W.Click(Lines()[8].delete)
ok(#I.Lists() == 2 and not I.ListByID(L2.id) and Printed("'Other' deleted") and lp.undo:IsShown() and lp.undo.text._text == "Undo: the list 'Other'", "Delete: gone, said, with Undo")
W.Click(lp.undo)
ok(#I.Lists() == 3 and I.Lists()[2] == L2, "Undo: back, where it was")
W.Click(Lines()[8].edit)
ok(lp.builderHead._text == "Editing 'Other'" and lp.build.text._text == "Save List" and lp.name._text == "Other" and DRow(4470) and DRow(4470).qty._text == "3", "Edit: in the builder, Save List", lp.builderHead._text)
lp.name:SetText("Other things")
W.Click(lp.build)
ok(I.Lists()[2] == L2 and L2.name == "Other things" and lp.builderHead._text == "New list" and #I.Lists() == 3 and Printed("Undo puts back what it was"), "Save List: saved in its place, renamed")
ok(lp.undo:IsShown() and lp.undo.text._text == "Undo: the edit of 'Other'", "Undo for the edit", lp.undo.text._text)
W.Click(lp.undo)
ok(L2.name == "Other" and #L2.items == 1 and L2.items[1].n == 3 and I.Lists()[2] == L2, "Undo: the list as it was before the edit")
root:ShowPage("market")
ok(root.pages.market:IsShown(), "AH Market: Phase C placeholder")
root:ShowPage("settings")
ok(T.Current() == "settings" and not root.pages.settings, "Investments' old Settings page: now the Settings tab")
local sp2 = T.Views().settings.page
W.Click(sp2.tabPos.boxes[3])
ok(I.S.tabPos == "side" and T.Buttons()[1]._w == 40, "Settings: tabs to the side, at once")
W.Click(sp2.tabPos.boxes[1])
ok(I.S.tabPos == "bottom", "and back to the bottom")
W.Click(sp2.graph.boxes[2])
ok(I.S.graphStyle == "bars" and ValhallaInvestDB.settings.graphStyle == "bars", "graph style saved (for Phase D)")
W.Click(sp2.grey.plus)
ok(math.abs(I.S.greyAlpha - 0.7) < 1e-9 and sp2.grey.label._text == "Grey-out strength: 70%", "grey-out strength stepper")

print("== 15. /valhalla invest off: the map as before")
WorldMapFrame:Show()
Slash("tab", "invest")
Slash("invest", "off")
ok(not mod.enabled and mod.db.enabled == false, "off, and saved")
ok(not T.Host():IsShown() and not T.Strip():IsShown() and T.Current() == "map", "tabs and views gone")
W.Fire("MERCHANT_SHOW") MerchantFrame:Show() MerchantFrame_UpdateMerchantInfo()
local any = false for _, o in pairs(M.Overlays()) do if o:IsShown() then any = true end end
ok(not any, "no merchant highlights")
ok(not A.Panel():IsShown(), "no AH list")
ns.printed = {}
Slash("tab", "invest")
ok(Printed("Investments is off") and T.Current() == "map", "/valhalla tab: says it's off")
WorldMapFrame:Hide() WorldMapFrame:Show()
ok(not T.Strip():IsShown(), "the map opens without tabs")
Slash("invest", "on")
ok(mod.enabled and T.Strip():IsShown(), "on again: the tabs back")
ok(Keys(WorldMapFrame) == mapKeys, "still nothing written on WorldMapFrame")

print("== 16. without Valhalla's map (off, or the Gamepad UI): no tabs")
Slash("invest", "off")
ns.modules.worldmap.enabled = false
Slash("invest", "on")
ok(not T.Attached(), "not attached")
ns.printed = {}
Slash("tab", "invest")
ok(Printed("need Valhalla's map"), "says why")
ns.modules.worldmap.enabled = true
Slash("invest", "off") Slash("invest", "on")
ok(T.Attached(), "attached with the map on")
ok(W.blockedSetters == 0, "no blocked setters anywhere")

print("== 17. the bank: either event, said once per visit with counts; its own first tab read")
local function Said(pat) local n = 0 for _, s in ipairs(ns.printed) do if tostring(s):find(pat) then n = n + 1 end end return n end
W.RunTimers()
ns.printed, I.bankEvents = {}, {}
W.bags[6] = { { 2589, 8 }, { 2447, 6 } }
W.bags[8] = { { 765, 3 } }
W.bankTabs[0] = { 7 }                        -- (the tab data leaves out the bank's own first tab, and tab 3)
W.Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 8)
ok(I.bankOpen and I.bankVia == "interaction" and I.char.bank[2589] == 8 and I.char.bank[765] == 3, "the banker (interaction event): the bank read, its own first tab and every tab with slots")
W.Fire("BANKFRAME_OPENED")
ok(I.bankEvents.BANKFRAME_OPENED == 1 and I.bankEvents.interaction == 1 and Said("Bank counted") == 0, "the other event: the same visit (nothing said twice)")
W.RunTimers()
ok(Said("Bank counted: 17 items %(3 kinds%) in 3 tabs%.") == 1 and Printed("Warband bank: 1 items"), "said once, a moment after opening: items, kinds, tabs (and the warband bank)", ns.printed[1])
W.Fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 8) W.Fire("BANKFRAME_CLOSED")
ok(not I.bankOpen and Said("Bank counted") == 1, "closed: not said again")
ok(I.char.bankInfo.tabs == 3 and I.char.bankInfo.items == 17 and I.char.bankInfo.via == "interaction", "what the read found, saved (for the diagnostic)")
W.Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 5)
ok(not I.bankOpen, "a merchant's interaction isn't the bank")
ns.printed = {}
W.Fire("BANKFRAME_OPENED") W.Fire("BANKFRAME_CLOSED")
ok(Said("Bank counted") == 1 and I.bankVia == "BANKFRAME_OPENED", "next visit (closed before the moment passed): said at closing")
W.RunTimers()
ok(Said("Bank counted") == 1, "and only once")
local b6, b8 = W.bags[6], W.bags[8]
W.bankTabs[0], W.bags[6], W.bags[8] = {}, nil, nil
ns.printed = {}
W.Fire("BANKFRAME_OPENED") W.Fire("BANKFRAME_CLOSED")
ok(Printed("none of its tabs could be read") and Printed("Run diagnostic"), "no tabs read: says so, and asks for the diagnostic")
W.bankTabs[0], W.bags[6], W.bags[8] = { 6, 7 }, b6, b8
W.Fire("BANKFRAME_OPENED") W.Fire("BANKFRAME_CLOSED") W.RunTimers()
WorldMapFrame:Show()
Slash("invest", "vendor")
local root2 = T.Views().invest.page
local every = true
for _, k in ipairs({ "vendor", "list", "market" }) do
	root2:ShowPage(k)
	if not (root2.bankLine:IsVisible() and root2.bankLine._text:find("Bank last seen: Nov 09 16:50 %(17 items%)")) then every = false end
end
ok(every, "every Investments page: 'Bank last seen' (with the count) under the page menu", root2.bankLine._text)
I.DraftClear()
root2:ShowPage("list")
local ve = root2.pages.list.dempty
ok(ve:IsShown() and ve._text:find("Bags") and ve._text:find("Bank") and ve._text:find("last visit") and ve._text:find("never changes a list"), "an empty builder: the page explains its columns and the bank")
I.char.bankSeen = nil
I.Changed()
ok(root2.bankLine._text:find("Bank not seen yet"), "never seen: says to open the bank once")
W.Fire("BANKFRAME_OPENED") W.Fire("BANKFRAME_CLOSED") W.RunTimers()

print("== 18. buying never changes a list: still needed, Done, used up; Undo is for Delete and Edit only")
W.bags[2] = {}
W.Fire("BAG_UPDATE_DELAYED")
local SL = MakeList("Stock", { { 3371, 5 }, { 2604, 3 } })
I.SetActive(SL.id)
local function Listed(id) local l = I.ShoppingList() for _, src in ipairs({ "vendor", "ah", "mail" }) do for _, r in ipairs(l[src]) do if r.id == id then return src end end end end
ok(Listed(3371) and Listed(2604), "both to buy")
local l1n = #L1.items
I.undo = {}
ns.printed = {}
W.bags[2] = { { 3371, 5 }, { 2604, 3 } }
W.Fire("BAG_UPDATE_DELAYED")
ok(#SL.items == 2 and SL.items[1].id == 3371 and SL.items[1].n == 5 and SL.items[2].n == 3 and not Listed(3371) and not Listed(2604), "bought both: both lines still there, as they were, nothing left to buy")
ok(not Printed("bought") and I.LastUndo() == nil, "no chat line, no Undo for a purchase")
ok(#L1.items == l1n and I.LineOf(L3, 3371).n == 7, "the other lists untouched")
root2:ShowPage("list")
local lp2 = root2.pages.list
lp2.offset = 99 lp2:Refresh()
local last = lp2.lines[12]
ok(last.name._text == "Red Dye" and last.count._text == "Done" and lp2.lines[11].count._text == "Done", "on the page: Done", last.name._text .. "=" .. tostring(last.count._text))
W.bags[2] = { { 2604, 1 } }
W.Fire("BAG_UPDATE_DELAYED")
ok(Listed(2604) and last.count._text == "x2" and lp2.lines[11].count._text == "x5", "used up: still needed again (x2, x5)", last.count._text)
ok(not lp2.undo:IsShown(), "no Undo button for purchases")
local HL = MakeList("Have", { { 2770, 30 } })
I.SetActive(HL.id)
ns.printed = {}
I.DeleteList(HL.id)
ok(I.ActiveList() == nil and I.char.activeList == nil, "the active list deleted (others left): none active")
ok(I.Undo() == "the list 'Have'" and I.ListByID(HL.id) and I.ActiveList() == HL, "Undo: back, and active again")
I.DeleteList(HL.id)
I.undo = {}
I.SetActive(SL.id)
ns.printed = {}
Slash("undo", "")
ok(Printed("Nothing to undo"), "/valhalla undo with nothing to undo: says so")

print("== 19. bought at the Auction House: 'in the mail' until looted")
local ML = MakeList("Mail", { { 2321, 10 } })
I.SetActive(ML.id)
W.Fire("COMMODITY_PURCHASED", 2321, 6)
local fr = I.LineRow(I.LineOf(ML, 2321))
ok(I.MailOf(2321) == 6 and fr.mail == 6 and fr.need == 4 and fr.short == 10, "6 bought: 6 in the mail, need 4 more (not bought twice)")
W.Fire("COMMODITY_PURCHASED", 2321, 4)
ok(Listed(2321) == "mail" and I.LineRow(I.LineOf(ML, 2321)).need == 0, "all 10 bought: 'In the mail', not to buy")
ok(I.LineOf(ML, 2321), "still on the list until it reaches your bags")
lp2.offset = 99 lp2:Refresh()
local ml = lp2.lines[12]
ok(ml.name._text == "Fine Thread" and ml.count._text == "In the mail" and ml.where._text == "10 in the mail (bought, not yet looted)", "Shopping List: 'In the mail'", ml.name._text .. "=" .. tostring(ml.count._text))
W.Fire("AUCTION_HOUSE_SHOW")
ok(A.Panel().mail._text:find("In the mail: Fine Thread x10"), "the AH's list: what's in the mail", A.Panel().mail._text)
W.Fire("AUCTION_HOUSE_CLOSED")
W.Fire("ITEM_PURCHASED", 6256)
ok(I.MailOf(6256) == 0, "something not on a list: not tracked")
ns.printed = {}
W.bags[3] = { { 2321, 10 } }
W.Fire("BAG_UPDATE_DELAYED")
ok(I.MailOf(2321) == 0 and I.LineOf(ML, 2321) and I.LineOf(ML, 2321).n == 10 and not Printed("bought") and I.LineRow(I.LineOf(ML, 2321)).need == 0, "looted: out of the mail; the line stays (Done)")
lp2:Refresh()
ok(lp2.lines[12].name._text == "Fine Thread" and lp2.lines[12].count._text == "Done", "on the page: Done")
MakeList("Bleach", { { 2324, 5 } })
W.Fire("ITEM_PURCHASED", 2324)
ok(I.MailOf(2324) == 1, "an item auction bought (on a list): 1 in the mail")
W.now = W.now + 600
W.inbox = { { { 2324, 3 }, { 6256, 1 } } }
W.Fire("MAIL_SHOW")
ok(I.MailOf(2324) == 3 and I.MailOf(6256) == 0, "the mailbox open: what's really in it (listed items only)")
W.inbox = {}
W.Fire("MAIL_INBOX_UPDATE")
ok(I.MailOf(2324) == 0, "taken out of the mailbox: none in the mail")
W.Fire("MAIL_CLOSED")
W.Fire("COMMODITY_PURCHASED", 2324, 2)
W.now = W.now + 31 * 86400
W.Fire("BAG_UPDATE_DELAYED")
ok(I.MailOf(2324) == 0, "mail older than 30 days: dropped (the game returns it)")

print("== 20. settings v0.3.1 took out: cleared from the save")
ValhallaInvestDB.settings.rememberTab, ValhallaInvestDB.settings.tab, ValhallaInvestDB.settings.ahOneClick = true, "invest", true
I.InitDB()
ok(ValhallaInvestDB.settings.rememberTab == nil and ValhallaInvestDB.settings.tab == nil and ValhallaInvestDB.settings.ahOneClick == nil and ValhallaInvestDB.settings.ahPanelMin == false,
	"rememberTab, tab and ahOneClick gone; ahPanelMin added")
ok(#I.Lists() == 6 and I.ActiveList() == ML, "the lists and the active one kept")

print("== 21. the diagnostic's buttons (the Settings tab)")
Slash("tab", "settings")
local sp3 = T.Views().settings.page
ok(sp3.run.text._text == "Run diagnostic" and sp3.runAH == nil and sp3.last._text, "Run diagnostic, last run (the AH check: /valhalla invest diag ah only, v0.4.0)")
ValhallaInvestDB.diag = {}
ns.printed = {}
W.Click(sp3.run)
local d2 = ValhallaInvestDB.diag[1]
ok(d2 and d2.bankInfo.read.items == 17 and d2.list and d2.list.merchants == 1 and d2.list.lists == 6 and d2.list.active == "Mail", "saved: the bank as last read, the lists, merchants")
ok(#ns.printed == 3 and Printed("Diagnostic saved") and Printed("/reload writes it to disk") and Printed("Bank: last read Nov 09 16:50: 17 items in 3 tabs") and Printed("Lists: 6 saved, active 'Mail'"), "three lines in chat", table.concat(ns.printed, " || "))
ok(sp3.last._text == "Last run: Nov 09 16:50", "last run shown", sp3.last._text)
ns.printed = {}
Slash("invest", "diag ah")
ok(#ValhallaInvestDB.diag == 1 and Printed("open the Auction House first"), "Run AH check away from the AH: says where")
W.Fire("AUCTION_HOUSE_SHOW")
ns.printed = {}
Slash("invest", "diag ah")
local d3 = ValhallaInvestDB.diag[2]
ok(d3 and d3.kind == "ah" and d3.ah.search.button and Printed("ready for one%-click Search"), "Run AH check at the AH: its Search button checked")
ok(I.AHCheck.Running() and Printed("AH check started") and sp3.last._text:find("AH check running"), "the AH check started; Settings shows it running", sp3.last._text)
W.Fire("AUCTION_HOUSE_CLOSED")
I.AHCheck.Tick() I.AHCheck.Tick()
ok(not I.AHCheck.Running() and d3.ahcheck.state:find("Auction House closed") and sp3.last._text:find("%(AH check: stopped"), "closing the AH stops it (saved as stopped)", sp3.last._text)
local seen0 = I.char.bankSeen
I.char.bankSeen = nil
I.bankEvents = {}
local lines2 = I.DiagSummary(I.Diag(""))
ok(lines2[2]:find("never read on this character %(bank events this session: none%)"), "never read: says so, and which bank events came", lines2[2])
I.char.bankSeen = seen0

print("== 22. v0.3.1's want list: made 'My List' once, the wants left as they were")
local old = { [250342] = { want = 20, cat = "mat", short = true, added = 1794331383, name = "Lesser Arcane Elixir" }, [3371] = { want = 5, keep = true }, [2589] = { want = 0 } }
local c = { want = old }
ok(I.MigrateLists(c) and #c.lists == 1 and c.lists[1].name == "My List" and c.activeList == c.lists[1].id, "My List made, active")
local my = c.lists[1]
ok(#my.items == 2 and my.items[1].id == 3371 and my.items[1].n == 5 and my.items[1].keep == nil and my.items[2].id == 250342 and my.items[2].n == 20 and my.items[2].name == "Lesser Arcane Elixir", "its items: each want and how many (Keep isn't carried: v0.3.3 has none)")
ok(c.want == old and old[250342].want == 20 and old[250342].short == true and old[250342].added == 1794331383 and old[3371].keep == true and old[2589].want == 0, "the old wants untouched")
ok(not I.MigrateLists(c) and #c.lists == 1, "only once")
local c2 = { want = {} }
ok(not I.MigrateLists(c2) and type(c2.lists) == "table" and #c2.lists == 0, "no old wants: no list")
local me = ValhallaInvestDB.realms.Forever.chars.Odysseaus
local keepLists, keepActive = me.lists, me.activeList
me.lists, me.activeList = nil, nil
me.want = { [2589] = { want = 40, name = "Linen Cloth" } }
I.InitDB()
ok(I.char == me and I.char.lists[1].name == "My List" and I.char.lists[1].items[1].n == 40 and I.char.want[2589].want == 40 and I.ActiveList() == I.char.lists[1], "at login: the same, from this character's saved wants")
me.lists, me.activeList = keepLists, keepActive

print("== 23. no lists, one list, none chosen: the vendor's and the AH's picker")
I.char.lists, I.char.activeList = {}, nil
W.Fire("AUCTION_HOUSE_SHOW")
local p2 = A.Panel()
ok(p2.picker.text._text == "No shopping list: build one" and p2.empty:IsShown() and p2.empty._text:find("No shopping list yet"), "no lists: the AH's picker says build one", p2.empty._text)
WorldMapFrame:Hide()
ns.printed = {}
W.Click(p2.picker)
ok(WorldMapFrame:IsShown() and T.Current() == "invest" and T.Views().invest.page.current == "list" and Printed("build one in Investments > Shopping List") and not p2.picker.menu:IsShown(), "its click: opens Investments > Shopping List")
W.Fire("AUCTION_HOUSE_CLOSED")
local only = MakeList("Only", { { 4470, 50 } })
ok(I.ActiveList() == only, "one list: chosen for you")
I.char.lists[2] = { id = 99, name = "Two", items = {} }
I.char.activeList = nil
ok(I.ActiveList() == nil, "two lists, none chosen: none")
MerchantFrame:Show() W.Fire("MERCHANT_SHOW") MerchantFrame_UpdateMerchantInfo()
ok(M.Picker():IsShown() and M.Picker().text._text == "Choose a shopping list  v", "the vendor's picker: choose one", M.Picker().text._text)
local anyGlow = false for _, o in pairs(M.Overlays()) do if o:IsShown() and o.glow._shown then anyGlow = true end end
ok(not anyGlow, "none chosen: nothing glows")
W.Click(M.Picker()) W.Click(M.Picker().menu.items[2])
ok(I.ActiveList() == only and M.Overlays()[1]:IsShown() and M.Overlays()[1].glow._shown and M.Overlays()[1].tag._text == "need 48", "Only chosen: Simple Wood glows at once (need 48)", M.Overlays()[1].tag._text)
W.Fire("MERCHANT_CLOSED") MerchantFrame:Hide()
ok(W.blockedSetters == 0 and Keys(WorldMapFrame) == mapKeys and Keys(MerchantFrame) == merchantKeys, "still no blocked setters, nothing written on the map or the merchant")

print("== 24. None: no list chosen, remembered; not the same as having no lists")
MerchantFrame:Show() W.Fire("MERCHANT_SHOW") MerchantFrame_UpdateMerchantInfo()
local pk2 = M.Picker()
W.Click(pk2)
ok(pk2.menu.items[1].text._text == "None" and pk2.menu.items[2].text._text == "> Only", "the menu: None first")
W.Click(pk2.menu.items[1])
ok(I.char.activeList == "none" and I.ActiveList() == nil and I.NoneChosen() and pk2.text._text == "List: None  v", "None chosen: no active list", pk2.text._text)
local lit = false for _, o in pairs(M.Overlays()) do if o:IsShown() then lit = true end end
ok(not lit, "None: no highlights, no grey")
W.Click(pk2)
ok(pk2.menu.items[1].text._text == "> None", "None marked in the menu")
pk2.menu:Hide()
W.Fire("MERCHANT_CLOSED") MerchantFrame:Hide()
table.remove(I.char.lists, 2)
ok(#I.Lists() == 1 and I.ActiveList() == nil and I.NoneChosen(), "one list left: None still chosen (not picked for you)")
W.Fire("AUCTION_HOUSE_SHOW")
ok(A.Panel().picker.text._text == "List: None  v" and A.Panel().empty:IsShown() and A.Panel().empty._text == "No list selected (None). Choose one above." and #A.Rows() == 0, "the AH: None, 'No list selected'")
W.Fire("AUCTION_HOUSE_CLOSED")
mod:OnDisable() mod:OnEnable()
ok(I.char.activeList == "none" and I.NoneChosen(), "remembered (saved as the choice)")
MakeList("Later", { { 2589, 5 } })
ok(I.NoneChosen() and I.ActiveList() == nil, "a new list built: None stays chosen")
ns.printed = {}
Slash("list", "")
ok(Printed("None chosen"), "/valhalla list: says None is chosen")
local d4 = I.Diag("")
ok(d4.list.none == true and I.DiagSummary(d4)[3]:find("active None %(chosen%)"), "the diagnostic: None (chosen)", I.DiagSummary(d4)[3])
I.char.lists = {}
W.Fire("AUCTION_HOUSE_SHOW")
ok(not I.NoneChosen() and A.Panel().picker.text._text == "No shopping list: build one" and A.Panel().empty._text:find("No shopping list yet"), "no lists at all: says build one (not None)")
W.Fire("AUCTION_HOUSE_CLOSED")
W.Fire("AUCTION_HOUSE_SHOW")
W.Click(A.Panel().picker)
W.Fire("AUCTION_HOUSE_CLOSED")
ok(W.blockedSetters == 0 and Keys(WorldMapFrame) == mapKeys, "still nothing written on the map")

print("== 25. v0.3.4: the AH check (Phase C0)")
local AC = I.AHCheck
W.clock = 0
function debugprofilestop() return W.clock end
function GetTimePreciseSec() return W.clock / 1000 end
W.pending = {}
local function Later(n, event, ...) W.pending[#W.pending + 1] = { n = n, event = event, args = { ... } } end
local function Tick(n)
  for _ = 1, n or 1 do
    W.clock = W.clock + 16
    local keep = {}
    for _, p in ipairs(W.pending) do p.n = p.n - 1 if p.n <= 0 then W.Fire(p.event, unpack(p.args)) else keep[#keep + 1] = p end end
    W.pending = keep
    AC.Tick()
  end
end
local function TickUntil(cond, max) for _ = 1, max or 3000 do if cond() then return true end Tick() end return cond() end
local rows = {}
local function Rows(n)
  rows = {}
  for i = 1, n do rows[i] = { id = (i % 3 == 0) and 2589 or (1000 + i % 50), count = (i % 3 == 0) and 20 or 1, buyout = (i % 97 == 0) and 0 or 100 * (1 + i % 7) * ((i % 3 == 0) and 20 or 1) } end
end
Rows(2500)
local CA = C_AuctionHouse
W.throttleReady = true
CA.IsThrottledMessageSystemReady = function() return W.throttleReady end
CA.MakeItemKey = function(id) return { itemID = id, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 } end
CA.SearchForItemKeys = function(keys) W.Count("SearchForItemKeys") W.lastKeys = #keys Later(3, "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED") end
CA.GetBrowseResults = function() local t = {} for i = 1, math.min(W.lastKeys, 40) do t[i] = { itemKey = { itemID = i }, totalQuantity = 5, minPrice = i <= 30 and 100 or 0 } end return t end
CA.HasFullBrowseResults = function() return true end
CA.SendSearchQuery = function(key) W.Count("SendSearchQuery") W.searched = key.itemID Later(2, "COMMODITY_SEARCH_RESULTS_UPDATED", key.itemID) end
CA.GetNumCommoditySearchResults = function() return 12 end
CA.HasFullCommoditySearchResults = function() return true end
CA.GetCommoditySearchResultsQuantity = function() return 16660 end
CA.GetCommoditySearchResultInfo = function(_, i) return i == 1 and { unitPrice = 21, quantity = 200 } or nil end
W.replicateThrottled = false
CA.ReplicateItems = function() W.Count("ReplicateItems") if not W.replicateThrottled then W.replicateThrottled = true Later(5, "REPLICATE_ITEM_LIST_UPDATE") end end
CA.GetNumReplicateItems = function() return #rows end
CA.GetReplicateItemInfo = function(i)
  local r = rows[i + 1]
  W.clock = W.clock + 0.01   -- (a row costs 10 us)
  return nil, nil, r.count, 1, true, 1, nil, 0, 0, r.buyout, 0, nil, nil, nil, nil, 0, r.id, false
end
CA.CalculateCommodityDeposit = function(id, dur, q) return 100 * dur end
CA.CalculateItemDeposit = function(loc, dur, q) return 50 * dur end
CA.GetItemCommodityStatus = function(loc) return (loc.bag == 0 and loc.slot == 1) and 2 or 1 end
ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
C_TradeSkillUI = {
  GetRecipeSchematic = function(id) if id == 2963 then return { recipeID = 2963, name = "Bolt of Linen Cloth", outputItemID = 2996, quantityMin = 1, quantityMax = 1,
    reagentSlotSchematics = { { quantityRequired = 2, reagents = { { itemID = 2589 } } } } } end end,
  GetRecipeInfo = function(id) if id == 2963 then return { recipeID = 2963, learned = true } end end,
  IsTradeSkillReady = function() return false end,
}
function GetSubZoneText() return "Booty Bay" end
function GetRealZoneText() return "Stranglethorn Vale" end
function UnitFactionGroup() return "Horde" end
W.calls.PostItem, W.calls.PlaceBid, W.calls.StartCommoditiesPurchase, W.calls.ConfirmCommoditiesPurchase = nil, nil, nil, nil
I.db.account.replicateAt = nil
ValhallaInvestDB.diag = {}
W.Fire("AUCTION_HOUSE_SHOW")
ns.printed = {}
Slash("invest", "diag ah")
local e = ValhallaInvestDB.diag[1]
ok(AC.Running() and e and e.ahcheck and e.ahcheck.state == "running" and Printed("AH check started") and Printed("nothing is posted, bid or bought"), "Run AH check at the AH: started, saved as running")
ok(e.recipeProbe and e.recipeProbe.window == false, "the plain diagnostic's part: recipes probed too (window closed)")
ns.printed = {}
I.RunDiag("ah")
ok(#ValhallaInvestDB.diag == 1 and Printed("already running"), "a second click while it runs: says so, starts nothing")
ok(TickUntil(function() return not AC.Running() end, 3000), "it ends by itself")
local o = e.ahcheck
ok(o.state == "done" and o.step == "7/7 done", "done, all 7 steps", tostring(o.state))
ok(o.house.neutral == true and o.house.house == "Neutral" and o.house.faction == "Horde" and o.house.sub == "Booty Bay", "the house: neutral (Booty Bay), faction saved")
ok(o.deposit.commodity and o.deposit.commodity[1] == 100 and o.deposit.commodity[3] == 300 and o.deposit.item and o.deposit.item[1] == 50 and o.deposit.item[3] == 150, "deposits: a commodity and an item, calculated only (12/24/48 h)")
ok(o.recipes.read == 1 and o.recipes.learned == 1 and o.recipes.tried == #I.PROBE_RECIPES and o.recipes.samples[1].r1 == 2589 and o.recipes.samples[1].r1n == 2, "recipes: what reads (Bolt of Linen Cloth: Linen x2), learned or not")
ok(#o.quick == 3 and o.quick[1].keys == 10 and o.quick[2].keys == 50 and o.quick[3].keys == 100 and o.quick[1].results == 10 and o.quick[3].results == 40 and o.quick[3].priced == 30 and o.quick[1].answer == "results" and o.quick[1].secs > 0, "quick scan: 10 / 50 / 100 keys, results, time")
ok(o.commodity.kind == "commodity" and o.commodity.min == 21 and o.commodity.units == 16660 and o.commodity.results == 12 and W.searched == 2589, "Linen Cloth: a commodity, its lowest and units")
local rp = o.replicate
local bid = 0 for i = 1, 2500 do if i % 97 == 0 then bid = bid + 1 end end
ok(rp.called and rp.answered and rp.readySecs > 0 and rp.count == 2500 and rp.items == 51 and rp.bidOnly == bid, "full scan: answered, 2,500 auctions of 51 items, bid-only counted", ("%s %s %s"):format(tostring(rp.count), tostring(rp.items), tostring(rp.bidOnly)))
ok(rp.watch[2589].units == 833 * 20 and rp.watch[2589].auctions == 833 and rp.watch[2589].min and rp.linenVsSearch == 1, "commodities in the full scan: Linen's units match its search")
ok(rp.frames >= 3 and o.maxFrameMs <= AC.BUDGET_MS + 1.5 and rp.cpuMs >= 25, "read over several frames, no frame past the budget", ("frames %s max %s cpu %s"):format(rp.frames, o.maxFrameMs, rp.cpuMs))
ok(rp.secondCalled and rp.secondEvents == 0 and rp.quietEvents == 0, "second call within the cooldown: no answer")
ok(I.db.account.replicateAt == W.now and #rp.top == 5 and rp.top[1].id == 2589, "the last full scan's time kept (account-wide); top items")
ok(Printed("AH check done") and Printed("Full scan: ready in") and Printed("2500 auctions of 51 items") and Printed("Linen Cloth search: commodity") and Printed("Quick scan: 10 keys") and Printed("Recipes %(profession window closed%): 1 of") and Printed("writes it to disk"), "its results in chat", table.concat(ns.printed, " || "))
ok(not W.calls.PostItem and not W.calls.PlaceBid and not W.calls.StartCommoditiesPurchase and not W.calls.ConfirmCommoditiesPurchase, "never posts, bids or buys")
sp3:Refresh()
ok(sp3.last._text:find("%(AH check: done%)"), "Settings: last run, the AH check done", sp3.last._text)
-- cooldown: a new check at once: no answer (saved as such, with the minutes since the last one)
W.Fire("AUCTION_HOUSE_CLOSED") W.Fire("AUCTION_HOUSE_SHOW")
local saveTimeout = AC.TIMEOUT.replicate
AC.TIMEOUT.replicate = 2
ns.printed = {}
I.RunDiag("ah")
TickUntil(function() return not AC.Running() end, 3000)
local o2 = ValhallaInvestDB.diag[#ValhallaInvestDB.diag].ahcheck
ok(o2.state == "done" and o2.replicate.called and o2.replicate.answered == false and o2.replicate.minutesSince == 0 and Printed("Full scan: no answer in"), "within the cooldown: no answer, said and saved")
AC.TIMEOUT.replicate = saveTimeout
-- the AH closed in the middle of the read
W.replicateThrottled = false
Rows(20000)
ns.printed = {}
I.RunDiag("ah")
TickUntil(function() return o and (ValhallaInvestDB.diag[#ValhallaInvestDB.diag].ahcheck.step or ""):find("^5/7") and ValhallaInvestDB.diag[#ValhallaInvestDB.diag].ahcheck.replicate.readAt end, 3000)
W.Fire("AUCTION_HOUSE_CLOSED")
Tick(2)
local o3 = ValhallaInvestDB.diag[#ValhallaInvestDB.diag].ahcheck
ok(not AC.Running() and o3.state:find("Auction House closed") and o3.replicate.aborted and o3.replicate.aborted > 0 and o3.replicate.aborted < 20000, "AH closed mid-read: stopped, where saved", tostring(o3.replicate.aborted))
ok(Printed("AH check stopped"), "said in chat")
-- /valhalla invest diag ah | stop
W.Fire("AUCTION_HOUSE_SHOW")
W.replicateThrottled = false
Rows(100)
ns.printed = {}
Slash("invest", "diag ah")
ok(AC.Running() and Printed("AH check started"), "/valhalla invest diag ah starts it")
Slash("invest", "diag stop")
ok(not AC.Running() and ValhallaInvestDB.diag[#ValhallaInvestDB.diag].ahcheck.state == "stopped", "/valhalla invest diag stop stops it")
ns.printed = {}
Slash("invest", "diag stop")
ok(Printed("isn't running"), "stop when not running: says so")
W.Fire("AUCTION_HOUSE_CLOSED")
ok(#ValhallaInvestDB.diag <= I.DIAG_KEEP and W.blockedSetters == 0 and Keys(WorldMapFrame) == mapKeys, "the log stays capped; still nothing written on the map")

print("== 26. v0.3.5: the Settings tab, the title, the strip covered, the AH check on the AH list")
WorldMapFrame:Show()
Slash("tab", "map")
local wmod = ns.modules.worldmap
ok(T.Buttons()[5].label._text == "Settings" and not T.Buttons()[5].tag, "Settings: the fifth tab, right of Professions (not 'soon')")
local navKeys = {}
for i, p in ipairs(I.Views.PAGES) do navKeys[i] = p.key end
ok(table.concat(navKeys, ",") == "vendor,list,market", "Investments' menu: Smart Vendor, Shopping List, AH Market", table.concat(navKeys, ","))
Slash("tab", "settings")
ok(T.Current() == "settings" and T.Views().settings:IsVisible() and not T.Views().invest:IsVisible(), "/valhalla tab settings")
Slash("tab", "invest")
Slash("invest", "settings")
ok(T.Current() == "settings", "/valhalla invest settings: the Settings tab")
Slash("tab", "invest")
T.Views().invest.page:ShowPage("settings")
ok(T.Current() == "settings", "Investments asked for its old Settings page: the Settings tab")
local placesOk = true
for _, pos in ipairs({ "bottom", "top", "side" }) do
  I.S.tabPos = pos
  T.Layout()
  local seen, n = {}, 0
  for _, b in ipairs(T.Buttons()) do
    local pt = b._points[1]
    local k = pt and (tostring(pt[4]) .. ":" .. tostring(pt[5])) or "none"
    if b:IsShown() and pt and not seen[k] then seen[k] = true n = n + 1 end
  end
  if n ~= 5 then placesOk = false end
end
I.S.tabPos = "bottom" T.Layout()
ok(placesOk, "five tabs, each in its own place, bottom, top and side")
-- the title: Valhalla, windowed and full screen
local BF = WorldMapFrame.BorderFrame
WorldMapFrame:Hide() WorldMapFrame:Show()
ok(BF._title == "Valhalla", "title: Valhalla (shown)", BF._title)
WorldMapFrame:Maximize()
ok(BF._title == "Valhalla", "title: Valhalla (maximized: after the game's own World Map)", BF._title)
WorldMapFrame:Minimize()
ok(BF._title == "Valhalla", "title: Valhalla (windowed again)", BF._title)
WorldMapFrame:SynchronizeDisplayState()
ok(BF._title == "Valhalla", "title: Valhalla after any of the game's title updates")
-- the strip over the map (breadcrumb, quest search, Quests count): covered on the other tabs
local band = T.Band()
local bp = band._points
ok(band._parent == T.Host() and band._strata == "HIGH" and band._level == T.LEVEL and band._mouse == true and band._wheel == true and band.bg and band.bg._tex == "Interface\\FrameGeneral\\UI-Background-Rock", "the band: ours, solid, over the strip, takes the clicks")
ok(bp[1][1] == "TOPLEFT" and bp[1][2] == WorldMapFrame and bp[1][4] == 64 and bp[1][5] == -23 and bp[2][1] == "BOTTOMRIGHT" and bp[2][2] == T.Host() and bp[2][3] == "TOPRIGHT",
  "from under the title bar (right of the portrait) down to the tab's panel, across the whole window")
Slash("tab", "settings")
ok(band:IsVisible() and wmod.away == true, "Settings: the strip covered, Valhalla's map menu put away")
Slash("tab", "talents")
ok(band:IsVisible() and wmod.away == true, "Talents: the same")
Slash("tab", "map")
ok(not band:IsVisible() and wmod.away == false, "Map & Quest Log: the strip and the map menu back")
-- Settings: nothing overlaps, at any width
Slash("tab", "settings")
local sp = T.Views().settings.page
I.ahOpen = false
sp:Refresh()
ok(sp.how._text:find("/valhalla invest diag ah", 1, true) and not sp.runAH, "the AH check: by slash command only (said in Settings)", sp.how._text)
ok(#sp.how._text < 260, "the diagnostic's description: short (the long one in its tooltip)", #sp.how._text)
local tipLines = {}
local addLine = GameTooltip.AddLine
GameTooltip.AddLine = function(_, t) tipLines[#tipLines + 1] = t end
W.Run(sp.run, "OnEnter")
GameTooltip.AddLine = addLine
ok(#tipLines >= 2 and tipLines[2]:find("/reload writes it to disk"), "Run diagnostic: its tooltip has the long description")
local function NoOverlap()
  local rows = sp.rows
  for i, r in ipairs(rows) do
    if r.note then
      local t = r.w._text or ""
      if t ~= "" and r.height < r.w:GetStringHeight() then return false, "note " .. i .. " too short" end
    end
    local nxt = rows[i + 1]
    if nxt and nxt.y > r.y - r.height + 0.001 then return false, "row " .. (i + 1) .. " over row " .. i end
  end
  return true
end
local heights = {}
for _, w in ipairs({ 760, 330 }) do
  sp.view:SetWidth(w)
  W.Run(sp.view, "OnSizeChanged")
  local good, why = NoOverlap()
  ok(good, ("Settings at %d px: nothing overlaps"):format(w), why)
  heights[w] = sp.body._h
end
ok(heights[330] > heights[760], "narrower: the notes measured again, the page longer", ("%s %s"):format(heights[330], heights[760]))
sp.view:SetWidth(760) W.Run(sp.view, "OnSizeChanged")
I.ahOpen = true
sp:Refresh()
ok(sp.hint._text == "" and NoOverlap(), "AH open: no hint, still nothing overlaps")
I.ahOpen = false
-- (v0.3.5's AH check button on the AH list: Scan since v0.4.0, tested in 27)
-- off: the game's own title back; on: Valhalla again
Slash("invest", "off")
ok(BF._title == "Map & Quest Log" and wmod.away == false, "off: the game's own title back, the map menu back")
Slash("invest", "on")
ok(BF._title == "Valhalla", "on: Valhalla")
ok(W.blockedSetters == 0 and Keys(WorldMapFrame) == mapKeys, "still nothing written on the map")

print("== 27. v0.4.0: the scanner, AH Market, item cells")
do
  local Sc, Mk, V = I.Scan, I.Market, I.Views
  local function STick(n) for _ = 1, n or 1 do Tick() Sc.Tick() end end
  local function SUntil(cond, max) for _ = 1, max or 6000 do if cond() then return true end STick() end return cond() end
  local function Events(f) local n, list = 0, {} for e in pairs(f and rawget(f, "_events") or {}) do n = n + 1 list[#list + 1] = e end table.sort(list) return n, table.concat(list, ",") end
  -- the auctions: { id, count, buyout } rows, read by GetReplicateItemInfo (10 us a row)
  local auctions = {}
  local function Market(n, price)
    auctions = {}
    for i = 1, n do
      local id = (i % 3 == 0) and 2589 or (1000 + i % 50)
      local count = (i % 3 == 0) and 20 or 1
      local unit = (price and price(id)) or 100 * (1 + i % 7)
      auctions[i] = { id = id, count = count, buyout = (i % 97 == 0) and 0 or unit * count }
    end
  end
  CA.GetNumReplicateItems = function() return #auctions end
  CA.GetReplicateItemInfo = function(i)
    local r = auctions[i + 1]
    W.clock = W.clock + 0.01
    return nil, nil, r.count, 1, true, 1, nil, 0, 0, r.buyout, 0, nil, nil, nil, nil, 0, r.id, false
  end
  local function Expect(id)
    local min, units, n = 0, 0, 0
    for _, r in ipairs(auctions) do
      if r.id == id then
        n, units = n + 1, units + r.count
        if r.buyout > 0 then local u = math.floor(r.buyout / r.count) if min == 0 or u < min then min = u end end
      end
    end
    return min, units, n
  end
  W.now = W.now - (W.now % 3600) + 3600 + 60        -- (just past an hour: two scans 15 minutes apart share it)
  function GetSubZoneText() return "The Commons" end
  function GetRealZoneText() return "Ironforge" end
  function UnitFactionGroup() return "Alliance" end
  I.realm.ah = nil
  I.db.account.replicateAt = nil
  W.replicateThrottled = false
  W.throttleReady = true
  Market(3000)
  I.S.ahPanelMin = false
  W.Fire("AUCTION_HOUSE_SHOW")
  A.Refresh()
  local ck = A.Panel().check
  ok(ck.button.text._text == "Scan" and ck.status._text:find("Full scan ready"), "the AH list: one Scan button, 'Full scan ready'", ck.status._text)
  ok(Sc.House() == "Alliance" and I.realm.ahLast == "Alliance", "this house: Alliance (remembered for AH Market)")
  ns.printed = {}
  W.Click(ck.button)
  local run = Sc.run
  STick(1)
  ok(Sc.Running() and run.kind == "full" and ck.button.text._text == "Stop" and Printed("Full scan started"), "Scan, the cooldown ready: a full scan; the button says Stop")
  local n1, ev1 = Events(Sc.Listener())
  ok(n1 == 1 and ev1 == "REPLICATE_ITEM_LIST_UPDATE" and W.calls.ReplicateItems, "one request, one listener: only the full scan's event", ev1)
  ok(I.AHCheck.Start and I.RunDiag("ah") == nil and Printed("A scan is running"), "the AH check waits for a scan (one at a time)")
  SUntil(function() return run.answered end)
  local n2 = Events(Sc.Listener())
  ok(n2 == 0 and I.db.account.replicateAt == W.now, "answered: the listener dropped at once (the 33 stray updates can't reach it); the 15 minutes start")
  for _ = 1, 33 do W.Fire("REPLICATE_ITEM_LIST_UPDATE") end
  local frames, reading = 0, false
  SUntil(function() if run.phase == "read" then frames = frames + 1 end return not Sc.Running() end)
  ok(run.state == "done" and frames >= 3, "read over several frames", frames)
  ok(run.maxMs <= 8 + 0.6, "no frame past the 8 ms budget (+ one 50-row chunk)", run.maxMs)
  local m = Sc.Market("Alliance")
  local c = Sc.Cur("Alliance", 2589)
  local emin, eunits, en = Expect(2589)
  ok(c and c.min == emin and c.units == eunits and c.auctions == en and not c.quick, "per item: lowest buyout per unit, units, auctions", ("%s %s %s"):format(c and c.min, c and c.units, c and c.auctions))
  local items = 0 for _ in pairs(m.cur) do items = items + 1 end
  ok(items == 51 and #m.scans == 1 and m.scans[1].kind == "full" and m.scans[1].n == 3000 and m.scans[1].items == 51, "51 items from 3,000 auctions, one full scan saved")
  ok(Printed("Full scan done: 3000 auctions of 51 items %(Alliance%)") and Printed("Next full scan in 15:00"), "said in chat, with the cooldown", table.concat(ns.printed, " || "))
  ok(Sc.CooldownText() == "Next full scan in 15:00." and ck.status._text:find("Next full scan in 15:00"), "the AH list: next full scan in mm:ss", ck.status._text)
  W.now = W.now + 61
  ok(Sc.CooldownText() == "Next full scan in 13:59.", "the timer counts down", Sc.CooldownText())
  -- quick scan (the cooldown runs): your items, 100 per search, paced by the AH's throttle
  local savedBags = I.char.bags
  local bags = {} for k, v in pairs(savedBags) do bags[k] = v end
  for id = 5000, 5249 do bags[id] = 1 end
  I.char.bags = bags
  local interest = Sc.Interest("Alliance")
  local sent = {}
  W.calls.SearchForItemKeys, W.calls.RequestMoreBrowseResults = 0, 0
  CA.SearchForItemKeys = function(keys) W.Count("SearchForItemKeys") sent = {} for _, k in ipairs(keys) do sent[#sent + 1] = k.itemID end W.lastKeys = #keys Later(3, "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED") end
  local fullOnce = false
  CA.HasFullBrowseResults = function() if not fullOnce then fullOnce = true return false end return true end
  CA.RequestMoreBrowseResults = function() W.Count("RequestMoreBrowseResults") Later(2, "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED") end
  CA.GetBrowseResults = function()
    local t = {}
    for _, id in ipairs(sent) do if id % 5 ~= 0 then t[#t + 1] = { itemKey = { itemID = id }, totalQuantity = 3, minPrice = 100 + id % 7 } end end
    return t
  end
  W.throttleReady = false
  ns.printed = {}
  W.Click(ck.button)
  local q = Sc.run
  ok(q and q.kind == "quick" and Printed("Quick scan started"), "Scan inside the 15 minutes: a quick scan of your items")
  STick(20)
  ok(W.calls.SearchForItemKeys == 0, "the AH busy: no search sent (waits for its throttle)")
  W.throttleReady = true
  STick(1)
  local nq, evq = Events(Sc.Listener())
  ok(W.calls.SearchForItemKeys == 1 and W.lastKeys == 100 and evq == "AUCTION_HOUSE_BROWSE_FAILURE,AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "ready: one search of 100 keys, only its events listened to", evq)
  SUntil(function() return not Sc.Running() end)
  local batches = math.ceil(#interest / 100)
  ok(q.state == "done" and W.calls.SearchForItemKeys == batches and batches == 3 and W.calls.RequestMoreBrowseResults == 1, "all of them in 3 searches; a partial answer asked for more", ("%d items, %d searches"):format(#interest, W.calls.SearchForItemKeys))
  local c5001, c5000 = Sc.Cur("Alliance", 5001), Sc.Cur("Alliance", 5000)
  ok(c5001 and c5001.quick and c5001.min == 100 + 5001 % 7 and c5001.units == 3 and c5000 and c5000.min == 0, "quick: lowest and units (marked quick); none listed kept as such")
  local p2589 = Sc.Points("Alliance", 2589)
  ok(#p2589 == 1 and p2589[1].quick, "the same hour: one point per item, the latest wins", #p2589)
  ok(Events(Sc.Listener()) == 0, "done: nothing listened to")
  I.char.bags = savedBags
  -- the AH closing mid-read: nothing saved
  W.now = W.now + 901
  W.replicateThrottled = false
  Market(20000)
  local before = m.cur[2589]
  local scansBefore = #m.scans
  ns.printed = {}
  Sc.Start()
  local pr = Sc.run
  SUntil(function() return pr.phase == "read" and (pr.readAt or 0) > 0 end)
  W.Fire("AUCTION_HOUSE_CLOSED")
  ok(not Sc.Running() and pr.state == "closed" and #m.scans == scansBefore and m.cur[2589] == before, "AH closed mid-read: nothing saved, the market as it was")
  ok(Printed("Full scan stopped: the Auction House closed. Nothing saved. Next full scan in 15:00"), "said, with the timer (the 15 minutes were spent)", table.concat(ns.printed, " || "))
  -- another house: Horde, its own market; four days of full scans: trending
  function UnitFactionGroup() return "Horde" end
  W.Fire("AUCTION_HOUSE_SHOW")
  ok(Sc.House() == "Horde", "a Horde Auction House: Horde")
  local factor = { 1, 1, 2, 2 }
  local start = W.now
  for k = 1, 4 do
    W.now = start + (k - 1) * 86400
    W.replicateThrottled = false
    Market(300, function(id) if id == 1001 then return 100 * factor[k] elseif id == 1002 then return 200 / factor[k] end end)
    Sc.Start("full")
    SUntil(function() return not Sc.Running() end)
    if k == 2 then
      local r2, f2, n2 = Sc.Trending("Horde")
      ok(n2 == 2 and #r2 == 0 and #f2 == 0, "two full scans: no Top 10 yet (needs 3)")
    end
  end
  local hm = Sc.Market("Horde")
  ok(hm ~= Sc.Market("Alliance") and #hm.scans == 4 and Sc.Cur("Alliance", 1001).min ~= Sc.Cur("Horde", 1001).min, "houses apart: Horde's market isn't Alliance's")
  local rising, falling, fulls = Sc.Trending("Horde")
  ok(fulls == 4 and rising[1] and rising[1].id == 1001 and math.abs(rising[1].change - 1) < 1e-9, "Top 10 rising: +100% (median of each half of the window)", rising[1] and rising[1].change)
  ok(falling[1] and falling[1].id == 1002 and math.abs(falling[1].change + 0.5) < 1e-9 and #rising <= 10 and #falling <= 10, "Top 10 falling: -50%", falling[1] and falling[1].change)
  -- a full scan 15 minutes later, in the same hour: its point replaces the last
  W.now = W.now + 901
  W.replicateThrottled = false
  Sc.Start("full")
  SUntil(function() return not Sc.Running() end)
  ok(#Sc.Points("Horde", 1001) == 4 and #hm.scans == 5, "a second scan in the same hour: still one point an hour (the scan logged)", #Sc.Points("Horde", 1001))
  -- neutral: Booty Bay is its own market, 15% cut
  function GetSubZoneText() return "Booty Bay" end
  function GetRealZoneText() return "Stranglethorn Vale" end
  W.Fire("AUCTION_HOUSE_SHOW")
  ok(Sc.House() == "Neutral" and Sc.Cut("Neutral") == 0.15 and Sc.Cut("Horde") == 0.05 and Sc.Market("Neutral") == nil, "Booty Bay: the neutral house, its own market, 15% cut")
  W.Fire("AUCTION_HOUSE_CLOSED")
  function GetSubZoneText() return "The Commons" end
  function GetRealZoneText() return "Ironforge" end
  I.realm.ahLast = "Horde"

  print("-- item cells")
  local loads = {}
  Item = { CreateFromItemID = function(_, id) return { ContinueOnItemLoad = function(_, fn) loads[#loads + 1] = { id = id, fn = fn } end } end }
  local tips = {}
  local GT = GameTooltip
  local gtKeys = {}
  for k in pairs(GT) do if not tostring(k):find("^_") then gtKeys[#gtKeys + 1] = tostring(k) end end
  table.sort(gtKeys)
  local gtBefore = table.concat(gtKeys, ",")
  GT.SetOwner = function(_, o) tips.owner = o end
  GT.SetHyperlink = function(_, l) tips.link = l tips.byID = nil end
  GT.SetItemByID = function(_, id) tips.byID = id tips.link = nil end
  GT.AddLine = function(_, t) tips.lines[#tips.lines + 1] = t end
  local compares = 0
  function GameTooltip_ShowCompareItem() compares = compares + 1 end
  function GameTooltip_HideShoppingTooltips() end
  function IsShiftKeyDown() return W.shift end
  function IsControlKeyDown() return W.ctrl end
  local dressed = 0
  function DressUpItemLink() dressed = dressed + 1 end
  W.uncached[2770] = true
  local cell = V.ItemCell(UIParent, 200)
  cell:SetItem(2770, Mk.Lines)
  ok(cell.icon._tex == 134566 and cell.name._text == "Item #2770" and #loads == 1 and V.loadingCount == 1, "not loaded yet: the icon at once, 'Item #id', its data asked for")
  local cell2 = V.ItemCell(UIParent, 200)
  cell2:SetItem(2770)
  ok(#loads == 1, "the same item twice: asked once")
  cell:SetItem(2447, Mk.Lines)
  W.uncached[2770] = nil
  loads[1].fn()
  ok(cell.name._text == "Peacebloom" and cell2.name._text == "Copper Ore" and V.loadingCount == 0, "the answer: the row that still shows it gets the name; a reused row keeps its new item")
  for id = 7000, 7040 do W.items[id] = { "Thing " .. id, 134400 } W.uncached[id] = true V.ItemCell(UIParent):SetItem(id) end
  ok(V.loadingCount == V.LOAD_MAX and V.LOAD_MAX == 30, "at most 30 items asked for at a time", V.loadingCount)
  tips.lines = {}
  W.shift = false
  W.Run(cell, "OnEnter")
  ok(tips.owner == cell and tips.link and tips.link:find("item:2447") and GT:IsShown(), "hover: the game's tooltip for the item (its link)")
  ok(tips.lines[1] and tips.lines[1]:find("Valhalla AH %(Horde%)"), "with what the AH said under it", tips.lines[1])
  W.Run(cell, "OnLeave")
  W.uncached[2770] = true
  cell2:SetItem(2770)
  tips.lines = {}
  W.Run(cell2, "OnEnter")
  ok(tips.byID == 2770, "not loaded: the tooltip by item ID (the game fills it in)")
  W.Run(cell2, "OnLeave")
  W.uncached[2770] = nil
  W.shift = true
  tips.lines = {}
  W.Run(cell, "OnEnter")
  ok(compares == 1 and V.comparing, "shift-hover: compared with what you wear")
  W.shift = false
  W.Fire("MODIFIER_STATE_CHANGED")
  ok(compares == 1 and not V.comparing and GT:IsShown(), "shift let go: the plain tooltip")
  W.Run(cell, "OnLeave")
  ok(not GT:IsShown() and Events(cell) == 0, "leave: hidden, nothing listened to")
  W.calls.insertLink = 0
  W.shift = true W.Click(cell) W.shift = false
  ok(W.calls.insertLink == 1, "shift-click: its link into chat")
  W.ctrl = true W.Click(cell) W.ctrl = false
  ok(dressed == 1, "ctrl-click: the dressing room")
  local clicked
  cell.onClick = function(id) clicked = id end
  W.Click(cell)
  ok(clicked == 2447, "click: its History")
  W.Click(cell, "RightButton")
  local inDraft = false for _, e in ipairs(I.Draft().items) do if e.id == 2447 then inDraft = true end end
  ok(inDraft, "right-click: into the Shopping List's builder")
  local gtKeys2 = {}
  for k in pairs(GT) do if not tostring(k):find("^_") then gtKeys2[#gtKeys2 + 1] = tostring(k) end end
  table.sort(gtKeys2)
  local set, want = {}, {}
  for _, k in ipairs(gtKeys) do set[k] = true end
  for _, k in ipairs({ "AddLine", "SetHyperlink", "SetItemByID", "SetOwner" }) do set[k] = true end   -- (the test's own spies)
  for k in pairs(set) do want[#want + 1] = k end
  table.sort(want)
  ok(table.concat(gtKeys2, ",") == table.concat(want, ","), "nothing of ours written on the game's tooltip", table.concat(gtKeys2, ","))

  print("-- AH Market's views")
  WorldMapFrame:Show()
  Slash("invest", "market")
  local root = T.Views().invest.page
  local mp = root.pages.market
  ok(mp and mp:IsShown() and #mp.subButtons == 5 and mp.subButtons[5].soon and mp.current == "top", "AH Market: Top 10, My items, History, Scan results, Craft (soon)")
  ok(mp.hint._text:find("Scan at the Auction House: the Scan button is on Valhalla's list beside it"), "the AH closed: where to scan")
  ok(mp.status._text:find("^Horde Auction House") and mp.houseButton:IsShown(), "the house last visited, a button to switch houses", mp.status._text)
  local top = mp.subs.top
  ok(top.cols[1].rows[1].cell.id == 1001 and top.cols[2].rows[1].cell.id == 1002 and top.cols[1].rows[1].change._text == "+100%" and not top.empty:IsShown(), "Top 10: rising and falling, each with its icon and tooltip", top.cols[1].rows[1].change._text)
  ok(top.cols[1].rows[1].cell.icon._tex ~= nil, "every row an item cell (icon)")
  W.Click(top.cols[1].rows[1].cell)
  local hf = mp.subs.history
  ok(mp.current == "history" and Mk.historyID == 1001 and hf.drawn == 4 and hf.cell.id == 1001, "a Top 10 item clicked: its History", hf.drawn)
  I.S.graphStyle = "bars" mp:Refresh()
  ok(hf.drawn == 4 and hf.marks[1]:IsShown() and hf.marks[1]._h > 1, "bars too (Settings' graph style)")
  I.S.graphStyle = "lines"
  mp:ShowSub("mine")
  local mf = mp.subs.mine
  local r1
  for _, r in ipairs(mf.rows) do if r.cell.id == 2589 then r1 = r end end
  local low = Sc.Lowest("Horde", 2589)
  ok(r1 and r1.vendor._text == Sc.Money(10) and r1.ah._text == Sc.Money(math.floor(low * 0.95)), "My items: vendor price vs the AH's lowest after the 5% cut", r1 and r1.ah._text)
  ok(mf.totals._text:find("after its 5%% cut"), "totals")
  mp:ShowSub("results")
  local rf = mp.subs.results
  local hitems = 0 for _ in pairs(hm.cur) do hitems = hitems + 1 end
  ok(#rf.list == hitems and rf.rows[1].cell.id ~= nil and rf.count._text:find(hitems .. " items"), "Scan results: every item of the last full scan", rf.count._text)
  rf.search:SetText("linen")
  ok(#rf.list == 1 and rf.rows[1].cell.id == 2589, "search by name")
  rf.search:SetText("")
  W.Click(rf.sortButtons[2])
  ok(rf.list[1].min <= rf.list[#rf.list].min, "sorted by lowest")
  mp:ShowSub("top")
  W.Click(mp.subButtons[5])
  ok(mp.current == "top", "Craft: coming in v0.4.1 (not opened)")
  Mk.house = "Alliance" mp:Refresh()
  ok(mp.status._text:find("^Alliance"), "another house chosen")
  Mk.house = nil

  -- 7 days: older points dropped
  W.now = start + 7 * 86400 + 30 * 3600
  Sc.PruneAll()
  local left = Sc.Points("Horde", 1001)
  ok(#left == 2 and left[1].t >= W.now - 7 * 86400, "past 7 days: dropped (the last two days kept)", #left)
  -- the size cap: the oldest scans go first
  I.S.histCapMB = 0.004
  Sc.Prune(hm)
  ok(Sc.TotalSize() <= 0.004 * 1048576 or #hm.scans == 1, "over the cap: the oldest scans dropped first", Sc.TotalSize())
  I.S.histCapMB = 3
  -- the dump filter (off by default)
  local nowMin = math.floor(W.now / 60) - hm.base
  hm.hist[2589] = ("%d:100:20:1;%d:120:20:1;%d:110:20:1"):format(nowMin - 300, nowMin - 200, nowMin - 100)
  local mid = Sc.Median7("Horde", 2589)
  hm.cur[2589] = ("%d,%d,%d,%d"):format(1, 20, 1, math.floor(W.now / 60) - hm.base)
  ok(Sc.Lowest("Horde", 2589) == 1, "the raw lowest buyout by default (no filter)")
  I.S.dumpFilter = true
  local low, _, dumped = Sc.Lowest("Horde", 2589)
  ok(mid == 110 and dumped and low == 110, "dump filter on: a 1c dump ignored (the 7-day median instead)", tostring(low))
  I.S.dumpFilter = false
  print("-- Settings > AH Market; the minimized button; /valhalla invest scan")
  Slash("tab", "settings")
  local sp4 = T.Views().settings.page
  sp4:Refresh()
  ok(sp4.speed and sp4.days and sp4.size._text:find("^History: %d+%.%d MB of 3 MB") and sp4.forgetAH and sp4.dump and sp4.compare, "Settings: scan speed, days, history size, dump filter, compare, forget", sp4.size._text)
  W.Click(sp4.speed.boxes[3])
  ok(I.S.scanSpeed == "fast", "scan speed: Fast")
  I.S.scanSpeed = "balanced"
  W.Fire("AUCTION_HOUSE_SHOW")
  A.SetMinimized(true)
  local mb = A.Mini()
  W.now = W.now + 901
  W.replicateThrottled = false
  W.Click(mb, "RightButton")
  ok(Sc.Running() and mb:IsShown(), "minimized: right-click scans")
  W.Click(mb, "RightButton")
  ok(not Sc.Running() and Printed("Nothing saved"), "right-click again: stopped, nothing saved")
  A.SetMinimized(false)
  Slash("invest", "scan")
  ok(Sc.Running(), "/valhalla invest scan")
  Slash("invest", "scan stop")
  ok(not Sc.Running(), "/valhalla invest scan stop")
  W.Fire("AUCTION_HOUSE_CLOSED")
  ns.printed = {}
  Slash("invest", "scan")
  ok(not Sc.Running() and Printed("open the Auction House first"), "away from the AH: says where")
  -- the size measured in Ironforge: 149,583 auctions of 5,016 items
  W.Fire("AUCTION_HOUSE_SHOW")
  W.now = W.now + 901
  W.replicateThrottled = false
  auctions = {}
  for i = 1, 149583 do local id = 10000 + i % 5016 auctions[i] = { id = id, count = 1 + i % 5, buyout = (1 + i % 5) * (50 + i % 13) } end
  Sc.Start("full")
  local big = Sc.run
  local bigFrames = 0
  SUntil(function() if big.phase == "read" then bigFrames = bigFrames + 1 end return not Sc.Running() end, 100000)
  ok(big.state == "done" and big.items == 5016 and big.maxMs <= 8 + 0.6 and bigFrames >= 150, "149,583 auctions of 5,016 items: done, no frame past the budget", ("%d frames, max %.2f ms"):format(bigFrames, big.maxMs))
  W.Fire("AUCTION_HOUSE_CLOSED")
  ok(W.blockedSetters == 0 and Keys(WorldMapFrame) == mapKeys, "still nothing written on the map")
end

print(("\n%d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
