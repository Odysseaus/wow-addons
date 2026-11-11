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
assert(loadfile(root .. "UI/Style.lua"))("Valhalla", ns)   -- (v0.4.2: the look, loaded after Core.lua)
assert(loadfile(root .. "Links.lua"))("Valhalla", ns)
for _, f in ipairs({ "Invest", "Scan", "Tabs", "Views", "Market", "Data/Forever/Recipes", "Data/Forever/TopSkills", "Craft", "Merchant", "AHPanel" }) do
  assert(loadfile(root .. (f:find("/") and f or ("Investments/" .. f)) .. ".lua"))("Valhalla", ns)   -- (the TOC's order)
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
ok(T.Buttons()[1].vh.selected and not T.Buttons()[2].vh.selected, "the current tab lit (the look's active tab)")

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
ok(T.Buttons()[1].vh.selected and not T.Buttons()[2].vh.selected, "and the Map & Quest Log tab lit")
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
ok(pk:IsShown() and pk.text._text == "List: List 1" and pk._parent == MerchantFrame and ppt[1] == "BOTTOMRIGHT" and ppt[3] == "TOPRIGHT", "above the merchant window's top right: which list", pk.text._text)
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
ok(I.ActiveList() == L2 and I.char.activeList == L2.id and not pk.menu:IsShown() and pk.text._text == "List: Other", "Other chosen: active (remembered)")
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
ok(p.picker and p.picker.text._text == "List: List 1", "under its title: which list")
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
ok(lp.lpager:IsShown() and lp.lpager.label._text == "1 of 2" and lp.lpager.first.off and not lp.lpager.next.off, "more lines than a page: the lists' pager, page 1 of 2", lp.lpager.label._text)
ok(not rawget(lp, "_wheel") and not rawget(lp, "_scripts").OnMouseWheel, "no wheel: the pager only")
W.Click(lp.lpager.next)
ok(lp.offset == 12 and Lines()[1].name._text == "Fine Thread" and lp.lpager.label._text == "2 of 2" and lp.lpager.last.off, "next: page 2, the lines after the first 12", Lines()[1] and Lines()[1].name._text)
W.Click(lp.lpager.first)
ok(lp.offset == 0, "first: back to page 1")
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
local function LastLines()
  lp2:Refresh() W.Click(lp2.lpager.last)
  local t = {} for _, ln in ipairs(lp2.lines) do if ln:IsShown() then t[#t + 1] = ln end end
  return t[#t], t[#t - 1]
end
local last, before = LastLines()
ok(last.name._text == "Red Dye" and last.count._text == "Done" and before.count._text == "Done", "on the page: Done", last.name._text .. "=" .. tostring(last.count._text))
W.bags[2] = { { 2604, 1 } }
W.Fire("BAG_UPDATE_DELAYED")
ok(Listed(2604) and last.count._text == "x2" and before.count._text == "x5", "used up: still needed again (x2, x5)", last.count._text)
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
local ml = LastLines()
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
local ml2 = LastLines()
ok(ml2.name._text == "Fine Thread" and ml2.count._text == "Done", "on the page: Done")
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
ok(M.Picker():IsShown() and M.Picker().text._text == "Choose a shopping list", "the vendor's picker: choose one", M.Picker().text._text)
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
ok(I.char.activeList == "none" and I.ActiveList() == nil and I.NoneChosen() and pk2.text._text == "List: None", "None chosen: no active list", pk2.text._text)
local lit = false for _, o in pairs(M.Overlays()) do if o:IsShown() then lit = true end end
ok(not lit, "None: no highlights, no grey")
W.Click(pk2)
ok(pk2.menu.items[1].text._text == "> None", "None marked in the menu")
pk2.menu:Hide()
W.Fire("MERCHANT_CLOSED") MerchantFrame:Hide()
table.remove(I.char.lists, 2)
ok(#I.Lists() == 1 and I.ActiveList() == nil and I.NoneChosen(), "one list left: None still chosen (not picked for you)")
W.Fire("AUCTION_HOUSE_SHOW")
ok(A.Panel().picker.text._text == "List: None" and A.Panel().empty:IsShown() and A.Panel().empty._text == "No list selected (None). Choose one above." and #A.Rows() == 0, "the AH: None, 'No list selected'")
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
  ok(mp and mp:IsShown() and #mp.subButtons == 5 and not mp.subButtons[5].soon and mp.current == "top", "AH Market: Top 10, My items, History, Scan results, Craft")
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
  ok(mp.current == "craft" and mp.subs.craft:IsShown(), "Craft: opens (v0.4.1)")
  mp:ShowSub("top")
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

  ;(function()   -- (its own function: the main chunk is at its 200 locals)
  print("-- 28. v0.4.0.1: My items and Scan results page; rows fit the window; History needs no minimum; round icon")
  ok(Mk.FitRows(400, 48) == 12 and Mk.FitRows(250, 48) == 6 and Mk.FitRows(100, 48) == 6 and Mk.FitRows(900, 48) == 20 and Mk.FitRows(600, 56) == 19,
    "rows that fit: 6 to 20 (12 at 400 px)")
  local keepBags, keepBank, keepScope = I.char.bags, I.char.bank, I.S.mineBank
  local function Bags(n) local b = {} for i = 1, n do b[2000 + i] = i end I.char.bags = b end
  Bags(70) I.char.bank = { [2001] = 5, [3001] = 2 } I.S.mineBank = false
  Slash("tab", "invest")
  mp:ShowSub("mine")
  local mf = mp.subs.mine
  mf:SetHeight(400) W.Run(mf, "OnSizeChanged")
  local pg = mf.pager
  local function Shown(f) local n = 0 for _, r in ipairs(f.rows) do if r:IsShown() then n = n + 1 end end return n end
  ok(mf.per == 12 and #mf.list == 70 and pg:IsShown() and pg.label._text == "Page 1 of 6 · items 1-12 of 70" and Shown(mf) == 12, "My items: 70 items, 12 a page: Page 1 of 6", pg.label._text)
  ok(pg.first.off and pg.prev.off and not pg.next.off and not pg.last.off, "on page 1: first and back are off")
  ok(mf.rows[1].cell.id == mf.list[1].id and mf.rows[12].cell.id == mf.list[12].id, "the first page's items")
  W.Click(pg.next)
  ok(mf.offset == 12 and pg.label._text == "Page 2 of 6 · items 13-24 of 70" and mf.rows[1].cell.id == mf.list[13].id, "next: items 13-24", pg.label._text)
  W.Click(pg.last)
  ok(pg.label._text == "Page 6 of 6 · items 61-70 of 70" and Shown(mf) == 10 and not mf.rows[11]:IsShown() and pg.next.off and pg.last.off, "last: items 61-70, the rest of the rows hidden", pg.label._text)
  W.Click(pg.next)
  ok(mf.offset == 60, "next on the last page: stays")
  W.Run(mf, "OnMouseWheel", 1)
  ok(pg.label._text:find("^Page 6 of 6") and not rawget(mf, "_scripts").OnMouseWheel, "v0.4.2.1: no wheel on a paged list (its buttons only)", pg.label._text)
  W.Click(pg.prev) W.Click(pg.first)
  ok(mf.offset == 0 and pg.label._text:find("^Page 1 of 6"), "back and first")
  local sv = 0 for _, e in ipairs(mf.list) do sv = sv + (e.vendor or 0) * e.n end
  ok(mf.sums.vendor == sv and mf.totals._text:find(Sc.Money(sv), 1, true), "the totals: all 70 items, not the page", mf.totals._text)
  W.Click(pg.last)
  W.Click(mf.scope.boxes[2])
  ok(I.S.mineBank == true and mf.offset == 0 and #mf.list == 71 and pg.label._text == "Page 1 of 6 · items 1-12 of 71", "Bags + bank: back to page 1 (the bank counted)", pg.label._text)
  W.Click(mf.scope.boxes[1])
  W.Click(pg.last)
  Bags(30) mp:Refresh()
  ok(pg.label._text == "Page 3 of 3 · items 25-30 of 30" and Shown(mf) == 6, "the bags emptied: onto the new last page", pg.label._text)
  Bags(10) mp:Refresh()
  ok(not pg:IsShown() and Shown(mf) == 10 and mf.offset == 0, "all on one page: no page buttons")
  Bags(70) mp:Refresh()
  W.Click(pg.next) W.Click(pg.next)
  ok(mf.offset == 24, "page 3 at 12 rows")
  mf:SetHeight(250) W.Run(mf, "OnSizeChanged")
  ok(mf.per == 6 and mf.offset == 24 and mf.rows[1].cell.id == mf.list[25].id and Shown(mf) == 6 and pg.label._text == "Page 5 of 12 · items 25-30 of 70",
    "the window smaller: 6 rows, the same first item kept", pg.label._text)
  mf:SetHeight(900) W.Run(mf, "OnSizeChanged")
  ok(mf.per == 20 and #mf.rows == 20 and mf.offset == 20 and Shown(mf) == 20 and pg.label._text == "Page 2 of 4 · items 21-40 of 70", "bigger: 20 rows (made as needed, no more)", pg.label._text)
  mf:SetHeight(400) W.Run(mf, "OnSizeChanged")
  ok(mf.per == 12 and Shown(mf) == 12, "back to 12 rows (the others hidden)")
  I.char.bags, I.char.bank, I.S.mineBank = keepBags, keepBank, keepScope
  -- Scan results: the 5,016 items of the big scan
  mp:ShowSub("results")
  local rf2 = mp.subs.results
  rf2:SetHeight(408) W.Run(rf2, "OnSizeChanged")
  local rp = rf2.pager
  ok(rf2.per == 12 and #rf2.list == 5016 and rp:IsShown() and rp.label._text == "Page 1 of 418 · items 1-12 of 5016", "Scan results: 5,016 items, Page 1 of 418", rp.label._text)
  W.Click(rp.last)
  ok(rp.label._text == "Page 418 of 418 · items 5005-5016 of 5016" and rf2.count._text:find("showing 5005-5016", 1, true) and rf2.rows[12].cell.id == rf2.list[5016].id, "last page: items 5005-5016 (the count line agrees)", rf2.count._text)
  W.Click(rp.prev)
  ok(rp.label._text:find("^Page 417 of 418"), "prev: a page")
  W.Click(rf2.sortButtons[3])
  ok(rf2.offset == 0 and rp.label._text:find("^Page 1 of 418"), "a new sort: page 1")
  W.Click(rp.next)
  rf2.search:SetText("Item")
  ok(rf2.offset == 0, "a search: page 1")
  rf2.search:SetText("")
  rf2:SetHeight(220) W.Run(rf2, "OnSizeChanged")
  ok(rf2.per == 6 and rp.label._text:find("^Page 1 of 836"), "Scan results fit too: 6 rows, 836 pages", rp.label._text)
  rf2:SetHeight(408) W.Run(rf2, "OnSizeChanged")
  -- History: no minimum number of scans; one point an hour
  local hh = Mk.House()
  local hmk = Sc.Market(hh)
  local nowM = math.floor(W.now / 60) - hmk.base
  hmk.hist[777001] = nil
  Mk.ShowHistory(mp, 777001)
  local hf2 = mp.subs.history
  ok(hf2.drawn == 0 and hf2.empty:IsShown() and hf2.empty._text:find("no minimum", 1, true), "History, no points: says one point a scan, no minimum", hf2.empty._text)
  local slot = math.floor((nowM - 60) / Sc.SLOT) * Sc.SLOT   -- (an hour's slot that has ended)
  Sc.AddPoint(hmk, 777001, slot + 5, 500, 3, 2)
  mp:Refresh()
  ok(hf2.drawn == 1 and hf2.note._text:find("^One point so far"), "one full scan: one point, drawn (no 3-scan minimum)", hf2.note._text)
  Sc.AddPoint(hmk, 777001, slot + 40, 450, 3, "q")
  mp:Refresh()
  local pts = Sc.Points(hh, 777001)
  ok(hf2.drawn == 1 and #pts == 1 and pts[1].min == 450, "a second scan in the same hour: still one point (the latest)")
  hmk.hist[777001] = ("%d:520:3:2;%d:450:3:q"):format(nowM - 130, nowM)
  mp:Refresh()
  ok(hf2.drawn == 2 and hf2.marks[1]._color[4] == 1 and hf2.marks[2]._color[4] == 0.4, "a full and a quick point in two hours: a line (quick faint)")
  hmk.hist[777001] = ("%d:520:3:2;%d:0:0:q"):format(nowM - 130, nowM)
  mp:Refresh()
  ok(hf2.drawn == 1, "a quick scan's 'none listed' isn't drawn")
  hmk.hist[777001] = nil
  -- the round icon (R2): an uncompressed 32-bit TGA, transparent corners, solid centre
  local fh = io.open("Valhalla/Media/Textures/ValhallaIconRound.tga", "rb")
  local tga = fh and fh:read("*a") if fh then fh:close() end
  local hdr = tga and { tga:byte(1, 18) } or {}
  ok(tga and #tga == 65554 and hdr[3] == 2 and hdr[13] == 128 and hdr[15] == 128 and hdr[17] == 32 and hdr[18] == 8, "round icon: 128x128 32-bit uncompressed TGA", tga and #tga)
  local function Alpha(x, y) return tga:byte(18 + (y * 128 + x) * 4 + 4) end
  ok(tga and Alpha(0, 0) == 0 and Alpha(127, 127) == 0 and Alpha(64, 64) == 255, "round icon: transparent corners, solid centre")
  ok(W.blockedSetters == 0 and Keys(WorldMapFrame) == mapKeys, "paging wrote nothing on the map")
  end)()

  ;(function()
  print("-- 29. v0.4.0.2: a view is built once; a resize redraws only its own list (the freeze of v0.4.0.1)")
  local errs0 = #W.sizeErrors
  W.sizeMaxDepth = 0
  local CF, made, views = CreateFrame, 0, {}
  local host = CreateFrame("Frame", nil, nil)
  CreateFrame = function(k, n, parent, ...)
    made = made + 1
    local fr = CF(k, n, parent, ...)
    if parent == host then views[#views + 1] = fr end
    return fr
  end
  local ok1, e1 = pcall(V.BuildMarket, host)
  local function Count(key) local n = 0 for _, v in ipairs(views) do if v.view == key then n = n + 1 end end return n end
  local function ShownLists() local n = 0 for _, v in ipairs(views) do if rawget(v, "pager") and v:IsShown() then n = n + 1 end end return n end
  made = 0
  local ok2, e2 = pcall(host.ShowSub, host, "mine")
  local mineMade = made
  ok(ok1 and ok2 and Count("mine") == 1 and host.subs.mine and host.subs.mine:IsShown(), "My items opened: one view built, not dozens", tostring(e1 or e2) .. " " .. Count("mine"))
  ok(W.sizeMaxDepth <= 1 and #W.sizeErrors == errs0, "its size asked as the game does: OnSizeChanged never nested, no error", W.sizeMaxDepth)
  ok(mineMade <= 80, "frames made for it: its rows, pager and header only", mineMade)
  made = 0
  host:ShowSub("results")
  ok(Count("results") == 1 and made <= 80 and W.sizeMaxDepth <= 1 and not host.subs.mine:IsShown() and host.subs.results:IsShown(), "Scan results: one view too, My items hidden", made)
  host:ShowSub("history")
  ok(ShownLists() == 0 and host.subs.history:IsShown(), "History: no list view left showing under it")
  host:ShowSub("mine") host:ShowSub("results") host:ShowSub("mine")
  ok(Count("mine") == 1 and Count("results") == 1 and #host.allSubs == 4 and ShownLists() == 1, "back and forth: each view built once (4 views made in all)", #host.allSubs)
  -- 10 resizes: rows made once (up to 20), one redraw of its own list when the rows change, never the page
  local mf = host.subs.mine
  local redraws, pageRefresh, subs = 0, 0, 0
  local R, PR, PS = mf.Refresh, host.Refresh, host.Sub
  mf.Refresh = function(...) redraws = redraws + 1 return R(...) end
  host.Refresh = function(...) pageRefresh = pageRefresh + 1 return PR(...) end
  host.Sub = function(...) subs = subs + 1 return PS(...) end
  made = 0
  local most, prev, bad = 0, mf.per, nil
  for _, h in ipairs({ 400, 900, 250, 900, 400, 400, 620, 250, 900, 400 }) do
    local before = redraws
    mf:SetHeight(h) W.Run(mf, "OnSizeChanged", 800, h)
    local want = (Mk.FitRows(h, 48) ~= prev) and 1 or 0
    if redraws - before ~= want then bad = ("%d px: %d redraws"):format(h, redraws - before) end
    prev = mf.per
    most = math.max(most, #mf.rows)
  end
  ok(not bad, "each resize: one redraw when the rows change, none when they don't", bad)
  ok(pageRefresh == 0 and subs == 0, "a resize never redraws the page or looks up a view", pageRefresh .. " " .. subs)
  ok(most == 20 and #mf.rows == 20 and made <= 8 * 3, "rows made only as needed, 20 at most, never again", made)
  host:ShowSub("history")
  pageRefresh, redraws = 0, 0
  local per = mf.per
  W.Run(mf, "OnSizeChanged", 800, 250)
  ok(mf.per == per and redraws == 0, "a resize while hidden: nothing")
  host:ShowSub("mine")
  redraws = 0
  mf.fitting = true W.Run(mf, "OnSizeChanged", 800, 900) mf.fitting = nil
  ok(redraws == 0, "a resize inside a resize: nothing")
  mf.Refresh, host.Refresh, host.Sub = R, PR, PS
  CreateFrame = CF
  ok(#W.sizeErrors == errs0, "no handler error anywhere", tostring(W.sizeErrors[#W.sizeErrors]))
  end)()

  ;(function()
  print("-- 30. v0.4.1: Craft: recipes from the game (and the bundle), the Top 10 by profit, owned reagents, the view")
  local Cr = I.Craft
  ok(Cr and Cr.ready and ns.Recipes and (","..ns.Recipes.professions[197].ids..","):find(",2963,", 1, true) and not (","..ns.Recipes.professions[197].ids..","):find(",2330,", 1, true),
    "the bundle: the probe's 2963 in it (2330, empty in the game, isn't a recipe in the client's tables either)")
  -- items, prices, a merchant
  local A, B, X = 920001, 920002, 920009
  for id, name in pairs({ [A] = "Test Thread", [B] = "Test Dye", [X] = "Test Unpriced", [910001] = "Test Shirt", [910002] = "Test Bolts",
    [910003] = "Test Missing", [910004] = "Test Unlisted", [910005] = "Test Soulbound" }) do W.items[id] = { name, 132912 } end
  for k = 1, 11 do W.items[910100 + k] = { "Test Craft " .. k, 132912 } end
  W.bind = { [910005] = 1 }
  I.realm.merchants.crafttest = { name = "Test Vendor", items = { [B] = 300 } }
  local function House(name, scans)
    local m = Sc.Market(name, true)
    local tm = math.floor(W.now / 60) - m.base
    m.scans = {}
    for i = 1, scans do m.scans[i] = { t = tm, kind = "full", n = 100, items = 10 } end
    local function Put(id, min) m.cur[id] = ("%d,%d,%d,%d"):format(min, 20, 2, tm) end
    Put(A, 100) Put(B, 500) Put(910001, 2000) Put(910002, 400) Put(910003, 5000) Put(910005, 9000)
    for k = 1, 11 do Put(910100 + k, 1000 + k * 10) end
    return m
  end
  local cm = House("CraftTest", 1)
  House("Neutral", 1)
  -- the game's recipes
  local R = {
    [901001] = { outputItemID = 910001, quantityMin = 1, quantityMax = 1, reagentSlotSchematics = { { quantityRequired = 2, reagents = { { itemID = A } } }, { quantityRequired = 1, reagents = { { itemID = B } } } } },
    [901002] = { outputItemID = 910002, quantityMin = 2, quantityMax = 4, reagentSlotSchematics = { { quantityRequired = 3, reagents = { { itemID = A } } } } },
    [901003] = { outputItemID = 910003, quantityMin = 1, quantityMax = 1, reagentSlotSchematics = { { quantityRequired = 1, reagents = { { itemID = X } } } } },
    [901004] = { outputItemID = 910004, quantityMin = 1, quantityMax = 1, reagentSlotSchematics = { { quantityRequired = 1, reagents = { { itemID = A } } } } },
    [901005] = { outputItemID = 910005, quantityMin = 1, quantityMax = 1, reagentSlotSchematics = { { quantityRequired = 1, reagents = { { itemID = A } } } } },
    [901006] = { outputItemID = 0, quantityMin = 0, quantityMax = 0, reagentSlotSchematics = {} },   -- (as the game answered 2330)
    [901007] = { outputItemID = 0, recipeType = 3, quantityMin = 1, quantityMax = 1, reagentSlotSchematics = {} },   -- (an enchant)
  }
  for k = 1, 11 do R[901100 + k] = { outputItemID = 910100 + k, quantityMin = 1, quantityMax = 1, reagentSlotSchematics = { { quantityRequired = 1, reagents = { { itemID = A } } },
    { quantityRequired = 1, required = false, reagents = { { itemID = X } } } } } end   -- (an optional reagent: not costed)
  local ids = {}
  for id in pairs(R) do ids[#ids + 1] = id end
  table.sort(ids)
  local TS = C_TradeSkillUI
  local reads = 0
  local cost = 0
  Enum.TradeskillRecipeType = { Item = 1, Enchant = 3 }
  C_TradeSkillUI = {
    GetBaseProfessionInfo = function() return { professionID = 2540, professionName = "Classic Tailoring", parentProfessionID = 197, parentProfessionName = "Tailoring" } end,
    GetAllRecipeIDs = function() return ids end,
    GetRecipeInfo = function(id) return { recipeID = id, learned = id == 901001 or id == 901002 } end,
    GetRecipeSchematic = function(id) reads = reads + 1 W.clock = W.clock + cost local r = R[id] if r then local c = {} for k, v in pairs(r) do c[k] = v end c.recipeID = id return c end return TS.GetRecipeSchematic(id) end,
  }
  Cr.schem, Cr.results = {}, {}
  W.Fire("TRADE_SKILL_SHOW")
  local store = I.db.account.recipes
  ok(store and store[197] and store[197].name == "Tailoring" and select(2, store[197].ids:gsub(",", "")) + 1 == #ids and I.char.known[197] == "901001,901002",
    "a profession window opens: its whole list kept for the account (keyed by its skill line), what this character knows", store and store[197] and store[197].ids)
  local p = Cr.Profession(197)
  ok(p and p.source == "live" and #p.ids == #ids and Cr.Profession(129) and Cr.Profession(129).source == "bundled", "the window's list replaces the bundled one; other professions keep theirs")
  ok(Cr.Key(nil, "Classic Tailoring") == 197 and Cr.Key(2540, "") == 2540 and Cr.Key(nil, "Basketry") == "Basketry", "a profession's key: its skill line by name, else the game's ID or name")
  local infos = 0
  local GRI = C_TradeSkillUI.GetRecipeInfo
  C_TradeSkillUI.GetRecipeInfo = function(id) infos = infos + 1 return GRI(id) end
  W.Fire("TRADE_SKILL_LIST_UPDATE")
  ok(infos == 0, "the same list again within 3 s: not read again")
  ids[#ids + 1] = 901008 R[901008] = R[901001]
  W.Fire("TRADE_SKILL_LIST_UPDATE")
  ok(infos == #ids and select(2, I.db.account.recipes[197].ids:gsub(",", "")) + 1 == #ids, "a longer list (the window was still loading): read at once", infos)
  ids[#ids] = nil R[901008] = nil
  W.Fire("TRADE_SKILL_SHOW")
  C_TradeSkillUI.GetRecipeInfo = GRI
  -- the math
  local opts = { owned = "market", bank = false, knownOnly = false }
  local res = Cr.Rank("CraftTest", 197, opts)
  local r1 = res.rows[1]
  ok(r1 and r1.id == 901001 and r1.cost == 500 and r1.sell == 2000 and math.abs(r1.net - 1900) < 0.01 and math.abs(r1.profit - 1400) < 0.01 and math.abs(r1.margin - 2.8) < 0.001,
    "sell at the lowest buyout (no undercut) less 5%; cost: 2 x 100 + the vendor's 300 (cheaper than the AH's 500)", r1 and r1.cost)
  ok(r1.parts[1].src == "ah" and r1.parts[2].src == "vendor", "each reagent's source: AH or vendor")
  local e2 = Cr.Price("CraftTest", Cr.Resolve(901002), opts, {})
  ok(e2.qty == 3 and e2.cost == 300 and math.abs(e2.net - 1140) < 0.01 and math.abs(e2.each - 280) < 0.01, "makes 2-4: sold as 3, profit per item", e2.each)
  ok(#res.rows == 10 and res.ranked == 13 and #res.list == 13 and res.rows[2].id == 901111 and res.rows[10].id == 901103, "the Top 10 by profit per craft (13 priced; 2 x 4 makes fall out)", res.rows[2] and res.rows[2].id)
  ok(#res.missing == 1 and res.missing[1].missing[1] == X and #res.unlisted == 1 and res.unlisted[1].out == 910004, "a reagent nobody prices, an output nobody lists: not ranked, listed apart")
  ok(res.skipped == 2 and res.unknown == 1, "an enchant and a bind-on-pickup output skipped; an empty answer counted unknown", res.skipped .. " " .. res.unknown)
  ok(#res.rows[2].parts == 1, "an optional reagent isn't costed")
  local en = Cr.Price("Neutral", Cr.Resolve(901001), opts, {})
  ok(math.abs(en.profit - (2000 * 0.85 - 500)) < 0.01, "at a neutral house: its 15% cut", en.profit)
  ok(Cr.Deposit({ out = 910001, qty = 1 }) == 100 and math.abs(r1.profit - 1400) < 0.01, "the deposit (est.): 100c at least, not taken off the profit")
  local lines = table.concat(Cr.Lines(r1, "CraftTest"), "\n")
  ok(lines:find("Test Thread", 1, true) and lines:find("vendor", 1, true) and lines:find("Deposit if unsold", 1, true) and lines:find("5% cut", 1, true), "its tooltip: each reagent, the cut, the deposit if unsold", lines)
  -- what you own
  local have = { [A] = 1, [B] = 1 }
  local f1 = Cr.Price("CraftTest", Cr.Resolve(901001), { owned = "free" }, have)
  local v1 = Cr.Price("CraftTest", Cr.Resolve(901001), { owned = "vendor" }, have)
  ok(f1.cost == 100 and f1.can == 0 and v1.cost == 120, "owned free: 1 thread bought, the dye yours; at vendor value: +10c each", f1.cost .. " " .. v1.cost)
  local keepBags, keepBank = I.char.bags, I.char.bank
  I.char.bags, I.char.bank = { [A] = 1, [B] = 1 }, { [A] = 5 }
  local rb = Cr.Rank("CraftTest", 197, { owned = "free", bank = true })
  local rn = Cr.Rank("CraftTest", 197, { owned = "free", bank = false })
  local function Find(rs, id) for _, e in ipairs(rs.rows) do if e.id == id then return e end end end
  ok(Find(rb, 901001).cost == 0 and Find(rb, 901001).can == 1 and Find(rn, 901001).cost == 100, "with the bank: all owned (free), can make 1; bags only: 1 bought")
  ok(#Cr.Rank("CraftTest", 197, { owned = "market", knownOnly = true }).rows == 2, "Known only: the 2 this character knows")
  -- the view
  Mk.house = "CraftTest"
  W.sizeMaxDepth = 0
  mp:ShowSub("craft")
  local cf = mp.subs.craft
  ok(cf:IsShown() and cf.drop:IsShown() and not cf.menu:IsShown() and W.sizeMaxDepth <= 1, "Craft: one view, the profession dropdown (closed)")
  W.Click(cf.drop)
  local tb
  for _, b in ipairs(cf.menu.items) do if b:IsShown() and b.prof == 197 then tb = b end end
  W.Click(tb)
  ok(not cf.menu:IsShown(), "a profession picked: the menu closes")
  ok(Mk.craftProf == 197 and cf.status._text:find("reading", 1, true) and not cf.rows[1]:IsShown(), "Tailoring: read a little each frame first", cf.status._text)
  for _ = 1, 200 do if not Cr.Running() then break end Cr.Tick() end
  mp:Refresh()
  local row = cf.rows[1]
  ok(row:IsShown() and row.cell.id == 910001 and row.cell.icon._tex ~= nil and row.cost._text == Sc.Money(500) and row.known._text:find("*", 1, true), "the Top 10: item cells (icon, name), cost, known", row.cost._text)
  ok(cf.missing._text:find("Can't price (1)", 1, true) and cf.missing._text:find("Test Unpriced", 1, true) and cf.unlisted._text:find("Test Unlisted", 1, true), "under it: can't price, not listed", cf.missing._text)
  local inShown = false for _, id in ipairs(Sc.shown or {}) do if id == X then inShown = true end end
  ok(inShown, "the unpriced reagent goes to the quick scan")
  ok(table.concat(row.Lines(), " "):find("Deposit if unsold", 1, true), "hover: the craft's lines under the game's tooltip")
  local jobs = Cr.job
  mp:Refresh()
  ok(not Cr.Running() and jobs == nil, "cached: drawn again without working it out again")
  table.insert(cm.scans, { t = cm.scans[1].t, kind = "full", n = 100, items = 10 })
  mp:Refresh()
  ok(Cr.Running(), "a new full scan: ranked again")
  for _ = 1, 200 do if not Cr.Running() then break end Cr.Tick() end
  W.Click(cf.owned.boxes[2])
  ok(I.S.craftOwned == "free" and Cr.Running(), "Owned free: ranked again")
  for _ = 1, 200 do if not Cr.Running() then break end Cr.Tick() end
  I.S.craftOwned = "market"
  local ns2 = Sc.Market("NoScanYet", true) ns2.cur[A] = "1,1,1,0"
  Mk.house = "NoScanYet" mp:Refresh()
  ok(cf.status._text:find("No full scan of NoScanYet", 1, true) and not cf.rows[1]:IsShown(), "a house without a full scan: says so")
  Sc.Houses().NoScanYet = nil
  local keepStore, keepB = I.db.account.recipes, ns.Recipes.professions
  I.db.account.recipes, ns.Recipes.professions = {}, {}
  Mk.house = "CraftTest" mp:Refresh()
  ok(cf.status._text:find("No recipes yet", 1, true), "no recipes at all: open a profession window once")
  I.db.account.recipes, ns.Recipes.professions = keepStore, keepB
  -- 3,000 recipes, 0.2 ms each to read: no frame past the budget
  local big = {}
  for k = 1, 3000 do local id = 950000 + k big[#big + 1] = id R[id] = R[901001] end
  I.db.account.recipes[999] = { name = "Test Big", ids = table.concat(big, ","), t = W.now }
  Cr.schem, Cr.results = {}, {}
  cost = 0.2
  local _, _, _ = Cr.Get("CraftTest", 999, opts)
  local frames = 0
  for _ = 1, 2000 do if not Cr.Running() then break end Cr.Tick() frames = frames + 1 end
  cost = 0
  ok(Cr.last and Cr.last.maxMs <= Cr.BUDGET + 1.2 and frames >= 70, "3,000 recipes: read and ranked over frames, none past the budget", ("%d frames, max %.2f ms"):format(frames, Cr.last and Cr.last.maxMs or -1))
  I.db.account.recipes[999] = nil
  I.char.bags, I.char.bank = keepBags, keepBank
  C_TradeSkillUI = TS
  Mk.house, Mk.craftProf = nil, nil
  ok(W.blockedSetters == 0 and Keys(WorldMapFrame) == mapKeys and #W.sizeErrors == 0, "Craft wrote nothing on the map; no handler error")
  end)()

  ;(function()
  print("-- 31. v0.4.1.1: every profession from the client's data, Known without a window, the dropdown, pages, Total, Harvest, Top 10's hours")
  local Cr = I.Craft
  local P, G = ns.Recipes.professions, ns.Recipes.gather
  local function Count(s) local n = 0 for _ in tostring(s):gmatch("%d+") do n = n + 1 end return n end
  local function Has(s, id) return (("," .. s .. ","):find("," .. id .. ",", 1, true)) ~= nil end
  local n, bad = 0, 0
  for k, e in pairs(P) do n = n + 1 if not Cr.SKILL[k] or e.name ~= Cr.SKILL[k] or tostring(e.ids):find("[^%d,]") then bad = bad + 1 end end
  ok(n == 12 and bad == 0 and not P[755] and not P[773] and Count(P[185].ids) == 132 and Count(P[129].ids) == 32 and Count(P[165].ids) == 605
    and P[185].secondary and P[129].secondary and P[356].secondary and not P[171].secondary and ns.Recipes.source:find("70888", 1, true),
    "the bundle: all 12 professions from the client's tables (Cooking's 132 = the game's own list), IDs only", n)
  ok(Has(G[182].ids, 2447) and Has(G[186].ids, 2770) and not Has(G[186].ids, 2840) and Has(G[393].ids, 783) and not Has(G[393].ids, 2318)
    and Has(G[356].ids, 6291) and not Has(G[356].ids, 6290) and not G[197],
    "Harvest lists: herbs, ores (no bars), hides (no crafted leather), raw fish (no cooked); none for Tailoring")
  -- no window opened anywhere: all 12, yours first (starred), then primary, then secondary
  local keepStore, keepKnown, keepBags, keepBank, keepScope = I.db.account.recipes, I.char.known, I.char.bags, I.char.bank, I.S.mineBank
  I.db.account.recipes, I.char.known = {}, {}
  GetProfessions = function() return 1, nil, nil, 4, 5, nil end
  GetProfessionInfo = function(i)
    if i == 1 then return "Alchemy", 0, 1, 300, 0, 0, 171 elseif i == 4 then return "Fishing", 0, 1, 300, 0, 0, 356
    elseif i == 5 then return "Cooking", 0, 1, 300, 0, 0, 185 end
  end
  Cr.Learned()
  local profs = Cr.Professions()
  ok(#profs == 12 and profs[1].name == "Alchemy" and profs[1].mine and profs[2].name == "Cooking" and profs[3].name == "Fishing" and profs[3].mine
    and profs[4].name == "Blacksmithing" and not profs[4].mine and profs[11].name == "Tailoring" and profs[12].name == "First Aid" and profs[12].secondary,
    "no window opened: all 12 professions; yours first, then primary, then secondary", profs[1].name .. "," .. profs[2].name .. "," .. profs[12].name)
  ok(Cr.Key(2939, "") == 185 and Cr.Key(2942, nil) == 129 and Cr.Key(2948, "Classic Tailoring") == 197, "a profession's child line (Classic Cooking 2939): its parent")
  -- Known, asked of the game per recipe: no window
  local TS = C_TradeSkillUI
  local learned, spells = { [3275] = true, [2538] = true }, { [3277] = true }
  local Linen, Wool, Wolf = 2589, 2592, 2672
  local SCH = {
    [3275] = { 1251, { { Linen, 1 } } }, [3276] = { 2581, { { Linen, 2 } } }, [3277] = { 3530, { { Wool, 1 } } }, [2538] = { 2679, { { Wolf, 1 } } },
  }
  for k = 1, 40 do SCH[960000 + k] = { 961000 + k, { { Linen, 1 } } } end
  SCH[960040] = { 961040, { { 929999, 1 } } }   -- (a reagent nobody prices)
  for id, name in pairs({ [1251] = "Linen Bandage", [2581] = "Heavy Linen Bandage", [3530] = "Wool Bandage", [2679] = "Charred Wolf Meat", [Wool] = "Wool Cloth",
    [Wolf] = "Stringy Wolf Meat", [765] = "Silverleaf", [785] = "Mageroyal", [2447] = "Peacebloom" }) do W.items[id] = W.items[id] or { name, 132912 } end
  for k = 1, 40 do W.items[961000 + k] = { "Test Paged " .. k, 132912 } end
  C_TradeSkillUI = {
    GetBaseProfessionInfo = function() return { professionID = 2942, professionName = "" } end,
    GetAllRecipeIDs = function() return { 3275, 3276 } end,
    GetRecipeInfo = function(id) if id == 3277 then return nil end return { recipeID = id, learned = learned[id] or false } end,
    GetRecipeSchematic = function(id)
      local r = SCH[id]
      if not r then return nil end
      local slots = {}
      for _, g in ipairs(r[2]) do slots[#slots + 1] = { quantityRequired = g[2], reagents = { { itemID = g[1] } } } end
      return { recipeID = id, outputItemID = r[1], quantityMin = 1, quantityMax = 1, reagentSlotSchematics = slots }
    end,
  }
  IsPlayerSpell = function(id) return spells[id] or false end
  local km = Sc.Market("KnownTest", true)
  local tm = math.floor(W.now / 60) - km.base
  km.scans = { { t = tm, kind = "full", n = 100, items = 10 } }
  local function Put(m, id, min) m.cur[id] = ("%d,%d,%d,%d"):format(min, 20, 2, tm) end
  Put(km, Linen, 10) Put(km, Wool, 20) Put(km, Wolf, 5) Put(km, 1251, 100) Put(km, 2581, 150) Put(km, 3530, 300) Put(km, 2679, 60)
  for k = 1, 40 do Put(km, 961000 + k, 100 + k * 10) end
  Cr.schem, Cr.results = {}, {}
  local ko = { owned = "market", bank = false, knownOnly = true }
  local fa = Cr.Rank("KnownTest", 129, ko)
  local got = {} for _, e in ipairs(fa.list) do got[#got + 1] = e.id .. (e.known and "*" or "") end
  table.sort(got)
  ok(#fa.list == 2 and table.concat(got, ",") == "3275*,3277*" and fa.unknown == 29,
    "Known only, First Aid, its tab never shown: the game asked per recipe (learned, else IsPlayerSpell)", table.concat(got, ","))
  local co = Cr.Rank("KnownTest", 185, ko)
  ok(#co.list == 1 and co.list[1].id == 2538 and co.list[1].known, "Known only, Cooking: the same, no window", #co.list)
  learned[3276] = true
  ok(#Cr.Rank("KnownTest", 129, ko).list == 2, "asked once (cached) until something is learned")
  W.Fire("LEARNED_SPELL_IN_TAB")
  ok(#Cr.Rank("KnownTest", 129, ko).list == 3 and Cr.gen > 0, "something learned: asked again (3 now)")
  W.Fire("TRADE_SKILL_SHOW")
  ok(I.db.account.recipes[129] and I.db.account.recipes[129].name == "First Aid" and not I.db.account.recipes[2942] and Cr.Profession(129).source == "live",
    "First Aid's tab shown (its child line 2942, no name): kept as First Aid")
  -- the view: the dropdown
  Mk.house, Mk.craftProf, Mk.craftMode = "KnownTest", nil, nil
  I.S.craftKnownOnly = false
  mp:ShowSub("craft")
  local cf = mp.subs.craft
  for _ = 1, 400 do if not Cr.Running() then break end Cr.Tick() end
  mp:Refresh()
  ok(Mk.craftProf == 171 and cf.drop.text._text:find("Alchemy", 1, true) and cf.drop.text._text:find("*", 1, true), "the dropdown: your first profession, starred", cf.drop.text._text)
  W.Click(cf.drop)
  local items = 0 for _, it in ipairs(cf.menu.items) do if it:IsShown() then items = items + 1 end end
  ok(cf.menu:IsShown() and items == 12 and cf.menu.items[1].text._text:find("*", 1, true) and cf.menu.items[1].text._text:find("Alchemy", 1, true) and cf.menu.items[12].text._text:find("First Aid", 1, true)
    and cf.menu.items[12].text._text:find("secondary", 1, true) and not cf.menu.items[4].text._text:find("*", 1, true),
    "open: all 12, yours starred and first, the secondary ones last", items)
  cf:Hide()
  ok(not cf.menu:IsShown(), "the view hidden: its menu closes too")
  cf:Show() W.Click(cf.drop)
  W.Click(cf.menu.items[12])
  for _ = 1, 400 do if not Cr.Running() then break end Cr.Tick() end
  I.S.craftKnownOnly = true mp:Refresh()
  for _ = 1, 400 do if not Cr.Running() then break end Cr.Tick() end
  mp:Refresh()
  ok(Mk.craftProf == 129 and not cf.menu:IsShown() and cf.rows[1]:IsShown() and cf.rows[1].known._text:find("*", 1, true), "First Aid picked, Known only: its known crafts listed", cf.status._text)
  I.S.craftKnownOnly = false
  -- pages: 40 priced crafts
  I.db.account.recipes[999] = { name = "Test Paged", ids = (function() local t = {} for k = 1, 40 do t[k] = 960000 + k end return table.concat(t, ",") end)(), t = W.now }
  I.char.bags, I.char.bank, I.S.mineBank = { [Linen] = 10 }, { [Linen] = 5 }, false
  Mk.craftProf = 999
  W.sizeMaxDepth = 0
  local errs0 = #W.sizeErrors
  cf:SetHeight(400) W.Run(cf, "OnSizeChanged")
  mp:Refresh()
  for _ = 1, 400 do if not Cr.Running() then break end Cr.Tick() end
  mp:Refresh()
  local pg = cf.pager
  ok(cf.per == 8 and #cf.list == 39 and pg:IsShown() and pg.label._text == "Page 1 of 5 · items 1-8 of 39" and cf.rows[1].cell.id == 961039,
    "all the priced crafts, 8 a page at 400 px (the one with an unpriced reagent's in the strip)", pg.label._text)
  ok(cf.missing._text:find("Can't price (1)", 1, true), "the rest under it: Can't price")
  W.Click(pg.next)
  local onPage2 = false for _, id in ipairs(Sc.shown or {}) do if id == 961031 then onPage2 = true end end
  local onPage1 = false for _, id in ipairs(Sc.shown or {}) do if id == 961039 then onPage1 = true end end
  ok(cf.offset == 8 and cf.rows[1].cell.id == cf.list[9].out and onPage2 and not onPage1, "next: crafts 9-16; the quick scan asks only about this page", pg.label._text)
  W.Click(pg.prev)
  ok(cf.offset == 0, "prev: a page back")
  -- Total = profit x can make (Count the bank)
  local e1 = cf.list[1]
  ok(e1.can == 10 and math.abs(e1.total - e1.profit * 10) < 0.01 and cf.rows[1].total._text == Sc.Money(e1.total), "Total: profit x can make (10 from the bags)", cf.rows[1].total._text)
  W.Click(cf.bank)
  for _ = 1, 400 do if not Cr.Running() then break end Cr.Tick() end
  mp:Refresh()
  ok(I.S.mineBank and cf.list[1].can == 15 and math.abs(cf.list[1].total - cf.list[1].profit * 15) < 0.01, "Count the bank: can make 15, Total follows")
  I.char.bags = {}
  Cr.results = {}
  mp:Refresh()
  for _ = 1, 400 do if not Cr.Running() then break end Cr.Tick() end
  mp:Refresh()
  ok(cf.list[1].can == 5 and cf.rows[1].total._text ~= "-", "bank only: 5")
  I.char.bank = {} Cr.results = {}
  mp:Refresh()
  for _ = 1, 400 do if not Cr.Running() then break end Cr.Tick() end
  mp:Refresh()
  ok(cf.list[1].can == 0 and cf.list[1].total == nil and cf.rows[1].total._text == "-", "none to make with: Total -")
  ok(W.sizeMaxDepth <= 1 and #W.sizeErrors == errs0, "no layout loop: OnSizeChanged never nested, no error")
  -- Harvest
  Put(km, 785, 80) Put(km, 2447, 50) Put(km, 765, 30)
  Mk.craftProf = 197 mp:Refresh()
  ok(not cf.modeHarvest:IsShown() and not cf.modeCrafts:IsShown(), "Tailoring: no Harvest switch")
  Mk.craftProf = 182 mp:Refresh()
  ok(cf.modeHarvest:IsShown() and cf.modeCrafts:IsShown(), "Herbalism: Crafts | Harvest")
  W.Click(cf.modeHarvest)
  ok(Mk.craftMode == "harvest" and cf.rows[1].cell.id == 785 and cf.rows[2].cell.id == 2447 and cf.rows[3].cell.id == 765 and cf.rows[4].low._text == "-"
    and cf.rows[1].low._text == Sc.Money(80) and cf.head.harvest[1]:IsShown() and not cf.head.craft[1]:IsShown() and not cf.owned:IsShown()
    and cf.status._text:find("herbs", 1, true) and #cf.list == Count(G[182].ids) and pg:IsShown(),
    "Harvest: every herb, dearest first, unlisted after; its own columns; paged", cf.status._text)
  Mk.craftProf = 186 mp:Refresh()
  local bar = false for _, e in ipairs(cf.list) do if e.id == 2840 then bar = true end end
  ok(Mk.craftMode == "harvest" and #cf.list == Count(G[186].ids) and not bar, "Mining's harvest: ores and stone, no bars")
  W.Click(cf.modeCrafts)
  ok(Mk.craftMode == "crafts" and cf.head.craft[1]:IsShown() and not cf.head.harvest[1]:IsShown(), "back to Crafts")
  -- Top 10: hours, not scans; the message alone (no overlap)
  local hm = Sc.Market("Hours", true)
  local now = math.floor(W.now / 60) - hm.base
  local s = math.floor(now / Sc.SLOT)
  local a, b = (s - 5) * Sc.SLOT, s * Sc.SLOT + 1
  hm.scans = { { t = a, kind = "full", n = 1, items = 1 }, { t = a + 16, kind = "full", n = 1, items = 1 }, { t = b, kind = "full", n = 1, items = 1 } }
  Sc.AddPoint(hm, 1001, a, 100, 1, 1) Sc.AddPoint(hm, 1001, a + 16, 100, 1, 1) Sc.AddPoint(hm, 1001, b, 100, 1, 1)
  hm.cur[1001] = ("%d,%d,%d,%d"):format(100, 1, 1, b)
  local r1, f1, fulls, nextAt = Sc.Trending("Hours")
  ok(fulls == 2 and #r1 == 0 and #f1 == 0 and nextAt == Sc.AbsTime(hm, (s + 1) * Sc.SLOT), "3 full scans, 2 of them in one hour: 2 hours (one point an hour); the next counts from the next hour", fulls)
  Mk.house = "Hours"
  mp:ShowSub("top")
  local top = mp.subs.top
  ok(top.empty:IsShown() and top.empty._text:find("3 different hours", 1, true) and top.empty._text:find("(you have 2)", 1, true) and top.empty._text:find("counts from", 1, true)
    and not top.cols[1]:IsShown() and not top.cols[2]:IsShown(), "Top 10: needs 3 different hours, says when the next scan counts; no headers under it", top.empty._text)
  hm.scans[#hm.scans + 1] = { t = (s - 2) * Sc.SLOT, kind = "full", n = 1, items = 1 }
  Sc.AddPoint(hm, 1001, (s - 2) * Sc.SLOT, 100, 1, 1)
  mp:Refresh()
  ok(top.empty:IsShown() and top.empty._text:find("No price moved", 1, true) and not top.cols[1]:IsShown() and not top.cols[2]:IsShown(),
    "3 hours, nothing moved: the message alone (Rising and Falling no longer drawn over it)", top.empty._text)
  -- as it was
  Sc.Houses().Hours, Sc.Houses().KnownTest = nil, nil
  I.db.account.recipes, I.char.known, I.char.bags, I.char.bank, I.S.mineBank = keepStore, keepKnown, keepBags, keepBank, keepScope
  C_TradeSkillUI, GetProfessions, GetProfessionInfo, IsPlayerSpell = TS, nil, nil, nil
  Cr.Learned()
  Mk.house, Mk.craftProf, Mk.craftMode = nil, nil, nil
  ok(W.blockedSetters == 0 and Keys(WorldMapFrame) == mapKeys and #W.sizeErrors == errs0, "v0.4.1.1 wrote nothing on the map; no handler error")
  end)()
end


print("== 32. v0.4.2: the look (UI/Style.lua): Profession by default, Norse from Settings; every widget through it")
;(function()
  local St, Mk = ns.Style, I.Market
  local errs0 = #W.sizeErrors
  -- the client's art: the looks' atlases (a few of the -c60 ones missing below, on purpose)
  local function Have(t) for _, v in pairs(t) do if type(v) == "string" and v:find("%-") and not v:find("\\", 1, true) then W.atlases[v] = { 64, 64 } elseif type(v) == "table" then Have(v) end end end
  Have(St.THEMES.profession) Have(St.THEMES.norse)
  for _, k in ipairs({ "tl", "tr", "bl", "br" }) do W.atlases["heavybronze-horz-cornerbracket-" .. k .. "-c60"] = { 32, 32 } end
  for _, n in ipairs({ "128-redbutton-left-pressed-c60", "_128-redbutton-center-pressed-c60", "128-redbutton-right-pressed-c60",
      "128-redbutton-left-disabled-c60", "_128-redbutton-center-disabled-c60", "128-redbutton-right-disabled-c60",
      "profession-button-arrow-left-pressed-c60", "profession-button-arrow-right-pressed-c60", "128-redbutton-minus-pressed-c60" }) do W.atlases[n] = { 64, 64 } end
  St.ForgetArt()
  ValhallaDB = nil
  ok(St.Look() == "profession" and St.Theme().key == "profession", "the default look: Profession (no ValhallaDB.ui yet)")
  local parent = CreateFrame("Frame", nil, UIParent)
  -- the red button: three pieces, its caps at their art's width for its height
  local b = I.Views.Button(parent, "Build", 170, 22)
  ok(b.vh and b.vh.kind == "button" and b.vh.as == "button" and b._backdrop == nil, "V.Button: the look's button (its flat backdrop cleared)")
  local L3, M3, R3 = b.vh.parts["3L"], b.vh.parts["3M"], b.vh.parts["3R"]
  ok(L3._atlas == "128-redbutton-left-c60" and M3._atlas == "_128-redbutton-center-c60" and R3._atlas == "128-redbutton-right-c60", "Profession: 128-redbutton left / center / right (-c60)")
  ok(math.abs(L3._w - 114 * 22 / 128) < 0.01 and math.abs(R3._w - 292 * 22 / 128) < 0.01 and M3:IsShown(), "caps at the art's width for 22 px, the center between", L3._w)
  ok(b.text._tc[1] == 1 and b.text._tc[2] == 0.82, "its text gold")
  W.Run(b, "OnEnter")
  ok(b.text._tc[2] == 1, "hover: white")
  W.Run(b, "OnMouseDown")
  ok(b.vh.parts["3L"]._atlas == "128-redbutton-left-pressed-c60", "pressed: the pressed art")
  W.Run(b, "OnMouseUp") W.Run(b, "OnLeave")
  ok(b.vh.parts["3L"]._atlas == "128-redbutton-left-c60" and b.text._tc[2] == 0.82, "back to normal")
  -- a new size, from the button's own OnSizeChanged (no size asked): squeezed caps, no center
  local fired0, depth0 = W.sizeFired, W.sizeMaxDepth
  W.Run(b, "OnSizeChanged", 50, 20)
  local lw, rw = b.vh.parts["3L"]._w, b.vh.parts["3R"]._w
  ok(b.vh.w == 50 and b.vh.h == 20 and math.abs(lw + rw - 50) < 0.01 and not b.vh.parts["3M"]:IsShown(), "OnSizeChanged: its own pieces again (narrow: the caps squeezed)", lw + rw)
  ok(W.sizeFired == fired0 and W.sizeMaxDepth == depth0, "and nothing laid out: no size asked, no OnSizeChanged nested")
  -- the kinds from the label
  local kinds = {}
  for _, l in ipairs({ "-", "+", "x", "<<", "<", ">", ">>", "OK" }) do kinds[#kinds + 1] = I.Views.Button(parent, l, 22, 20).vh.as end
  ok(table.concat(kinds, ",") == "minus,plus,delete,first,prev,next,last,button", "kinds: - + x square, << < > >> the pager's arrows", table.concat(kinds, ","))
  local mn = I.Views.Button(parent, "-", 20, 20)
  ok(mn.vh.parts.sq._atlas == "128-redbutton-minus-c60" and mn.text._alpha == 0, "the square minus: the game's art, its '-' hidden under it")
  local nx = I.Views.Button(parent, ">>", 30, 20)
  ok(nx.vh.parts.a1._atlas == "profession-button-arrow-right-c60" and not nx.vh.parts.a2 and nx.vh.parts.stop:IsShown() and nx.text._alpha == 0, "last page: one profession arrow box and its stop bar (v0.4.2.1)")
  -- art the client lacks: its standard name, else a colour
  W.atlases["128-redbutton-left-c60"] = nil W.atlases["128-redbutton-left"] = { 114, 128 }
  W.atlases["_128-redbutton-center-c60"] = nil
  St.ForgetArt()
  local fb = I.Views.Button(parent, "Fallback", 120, 22)
  ok(fb.vh.parts["3L"]._atlas == "128-redbutton-left" and St.missing["128-redbutton-left-c60"] == "128-redbutton-left", "a missing -c60: its standard art")
  ok(fb.vh.parts["3M"]._atlas == nil and fb.vh.parts["3M"]._color ~= nil and St.missing["_128-redbutton-center-c60"] == false, "missing both: a plain colour (nothing breaks)")
  local rep = table.concat(St.ArtReport(), "|")
  ok(rep:find("128-redbutton-left-c60 -> 128-redbutton-left", 1, true) and rep:find("_128-redbutton-center-c60 -> colour", 1, true), "ArtReport says which", rep)
  W.atlases["128-redbutton-left-c60"], W.atlases["_128-redbutton-center-c60"], W.atlases["128-redbutton-left"] = { 64, 64 }, { 64, 64 }, nil
  St.ForgetArt() St.Reskin()
  ok(fb.vh.parts["3L"]._atlas == "128-redbutton-left-c60", "the art back: the -c60 again")
  -- the window's tabs, the views
  WorldMapFrame:Show()
  Slash("invest", "market")
  local root = T.Views().invest.page
  local mp = root.pages.market
  local tb = T.Buttons()
  ok(tb[1].vh.as == "tab" and tb[1].vh.pos == "bottom" and not tb[1].vh.selected and tb[1].vh.parts["3L"]._atlas == "uiframe-tab-left-c60", "the window's tabs: the game's tabs (bottom)")
  ok(tb[2].vh.selected and tb[2].vh.parts["3L"]._atlas == "uiframe-activetab-left" and tb[2].label._tc[1] == 1 and tb[2].label._tc[3] == 1, "the current one: the active tab's art, its label white")
  I.S.tabPos = "top" T.Layout()
  local c = tb[1].vh.parts["3L"]._coord
  ok(tb[1].vh.pos == "top" and c and c[3] > c[4], "top: the tab's art upside down (its own coords)", c and table.concat(c, ","))
  I.S.tabPos = "side" T.Layout()
  ok(tb[1].vh.as == "side" and tb[1].vh.parts.side:IsShown(), "side icons: the square button")
  I.S.tabPos = "bottom" T.Layout()
  ok(tb[1].vh.as == "tab" and tb[1].vh.pos == "bottom", "bottom again")
  ok(T.Host().vh and T.Host().vh.kind == "content" and T.Host().vh.parts.bg._atlas == "profession-background-template2-c60", "the host: the profession window's background (F2)")
  ok(T.Band().vh.strip and T.Band().vh.parts.bg._coord and T.Band().vh.parts.bg._coord[4] - T.Band().vh.parts.bg._coord[3] < 0.02, "the band over the breadcrumb: the art's top edge (not all of it squashed)")
  ok(mp.subButtons[1].vh.as == "tab" and mp.subButtons[1].vh.pos == "top", "AH Market's views: top tabs")
  ok(root.navButtons[1].vh.as == "nav" and root.navButtons[1].vh.parts.nav._atlas == "profession-tab-c60", "the page menu: the profession list's bars")
  local navOn
  for _, nb in ipairs(root.navButtons) do if nb.key == "market" then navOn = nb end end
  ok(navOn.vh.selected and navOn.vh.parts.glow:IsShown(), "the page shown: lit (its glow)")
  -- Craft: dropdown, its menu, Crafts | Harvest, Known only, the pager
  mp:ShowSub("craft")
  local cf = mp.subs.craft
  ok(cf.drop.vh.as == "dropdown" and cf.drop.vh.parts.arrow._atlas == "common-dropdown-a-button-c60" and cf.menu.vh.kind == "menu", "Craft's profession: the look's dropdown and menu")
  ok(cf.menu.items[1].vh.as == "item", "its lines: menu lines")
  W.Click(cf.drop)
  ok(cf.menu:IsShown() and cf.drop.vh.parts.arrow._atlas == "common-dropdown-a-button-open-c60", "open: the arrow's open art")
  cf:Hide()
  ok(not cf.menu:IsShown() and cf.drop.vh.parts.arrow._atlas == "common-dropdown-a-button-c60", "the view hidden: the menu closes (still), the arrow back")
  cf:Show()
  ok(cf.known.vh.kind == "check" and cf.known.vh.parts.box._atlas == "profession-checkbox-c60" and cf.known.tick._atlas == "checkmark-minimal" and cf.known._w == 16, "Known only: the profession tick box, the same 16 px")
  ok(cf.owned.boxes[1].vh.kind == "check", "radios: the look's tick boxes")
  ok(cf.pager.first.vh.as == "first" and cf.pager.prev.vh.as == "prev" and cf.pager.next.vh.as == "next" and cf.pager.last.vh.as == "last", "the pager: arrows")
  ok(Mk.ROW_H == 25 and Mk.MIN_ROWS == 6 and Mk.MAX_ROWS == 20 and Mk.BELOW == 52 and Mk.FitRows(600, 134) == 16, "fit rows as before: 25 px rows, 6 to 20", Mk.FitRows(600, 134))
  ok(cf.pager.first._w == 30 and cf.drop._w == 230 and cf.modeCrafts._w == 70, "sizes unchanged")
  T.Skin(cf.modeHarvest, 0.9, T.GOLD) T.Skin(cf.modeCrafts, 0.9, T.BRONZE)
  local hv, cr = cf.modeHarvest.vh, cf.modeCrafts.vh
  ok(hv.selected and not cr.selected and hv.parts["3L"]._atlas == "128-redbutton-left-c60" and hv.parts.glow:IsShown() and hv.parts.glow._blend == "ADD" and hv.parts.eT:IsShown() and hv.parts.eT._color[1] == 1,
    "Harvest chosen: the bright red art, a gold glow and edge")
  ok(cf.modeHarvest.text._tc[1] == 1 and cf.modeHarvest.text._tc[2] == 1 and cf.modeHarvest.text._tc[3] == 1, "the chosen one's text: bright (white)")
  ok(cr.parts["3L"]._atlas == "128-redbutton-left-pressed-c60" and cr.parts["3L"]._vc[1] < 1 and not (cr.parts.glow and cr.parts.glow:IsShown()) and not (cr.parts.eT and cr.parts.eT:IsShown()), "Crafts (not chosen): the darker pressed art, dimmed, no glow or edge")
  ok(cf.modeCrafts.text._tc[1] == 0.72 and cf.modeCrafts.text._tc[3] == 0.45, "the one not chosen: grey-gold text")
  W.Run(cf.modeCrafts, "OnEnter")
  ok(cf.modeCrafts.text._tc[1] == 1 and cf.modeCrafts.text._tc[3] == 1, "hovered: bright text (still a button)")
  W.Run(cf.modeCrafts, "OnLeave")
  T.Skin(cf.modeCrafts, 0.9, T.GOLD) T.Skin(cf.modeHarvest, 0.9, T.BRONZE)
  ok(cr.selected and cr.parts["3L"]._atlas == "128-redbutton-left-c60" and cr.parts.glow:IsShown() and hv.parts["3L"]._atlas == "128-redbutton-left-pressed-c60" and not hv.parts.glow:IsShown() and not hv.parts.eT:IsShown(),
    "switched: Crafts bright with its glow, Harvest dimmed (no glow or edge left over)")
  local plain = I.Views.Button(UIParent, "Plain", 80, 22)
  ok(not plain.vh.toggle and plain.vh.parts["3L"]._atlas == "128-redbutton-left-c60" and plain.text._tc[1] == 1 and plain.text._tc[2] < 1, "a plain button (not a toggle): untouched (bright art, gold text, no glow)")
  T.Skin(cf.modeHarvest, 0.9, T.GOLD) T.Skin(cf.modeCrafts, 0.9, T.BRONZE)
  ok(not cf.drop.text._text:find("  v", 1, true), "the dropdown's text: no 'v' (its arrow says it)", cf.drop.text._text)
  mp:Refresh()
  -- the Shopping List's - [qty] +
  root:ShowPage("list")
  local lp = root.pages.list
  local r1 = lp.drows[1]
  ok(r1.minus.vh.as == "dec" and r1.plus.vh.as == "inc" and r1.qty.vh.kind == "input" and r1.remove.vh.as == "delete", "how many: the profession arrows round the page box; x the delete button")
  ok(r1.minus.vh.parts.a1._atlas == "profession-button-arrow-left-c60" and r1.qty.vh.parts.bL._coord ~= nil, "the arrows' art; the box cut in three")
  ok(lp.name.vh.kind == "input" and lp.drows[1]._backdrop.edgeSize == 1, "text boxes: the page box; the rows: the look's panel")
  -- Settings: the Look switch
  T.Select("settings")
  local sp = T.Views().settings.page
  ok(sp.look and #sp.look.boxes == 2 and sp.look.boxes[1].value == "profession" and sp.look.boxes[2].value == "norse" and sp.look.boxes[1].tick._shown and not sp.look.boxes[2].tick._shown,
    "Settings > Look: Profession (ticked) / Norse")
  ok(sp.grey.minus.vh.as == "dec" and sp.days.plus.vh.as == "inc", "Settings' steppers: arrows")
  local n0 = 0 for _ in pairs(St.all) do n0 = n0 + 1 end
  local laid0 = W.sizeFired
  W.Click(sp.look.boxes[2])
  ok(ValhallaDB.ui.look == "norse" and St.Look() == "norse" and sp.look.boxes[2].tick._shown and not sp.look.boxes[1].tick._shown, "Norse chosen: saved in ValhallaDB.ui.look")
  ok(b.vh.parts.iron:IsShown() and not b.vh.parts["3L"]:IsShown() and b.vh.parts.eT:IsShown(), "live: the buttons are iron with a bronze edge (the red pieces hidden)")
  ok(T.Host().vh.parts.bg._atlas == "heavybronze-frame-background-c60", "the host: heavy bronze's background")
  ok(sp.vh.framed and sp.vh.parts.ktl and sp.vh.parts.ktl:IsShown() and sp.vh.parts.ktl._atlas == "heavybronze-horz-cornerbracket-tl-c60" and sp.vh.parts.n1._coord ~= nil, "the pages and the menu: framed in heavy bronze, bracketed")
  ok(tb[1].vh.parts.iron:IsShown() and tb[1].vh.parts.point == nil, "the tabs: iron, no point under them")
  local tOn, tOff
  for _, x in ipairs(tb) do if x.vh.selected then tOn = x elseif not x.soon then tOff = x end end
  ok(tOn and tOn.vh.parts.glow:IsShown() and tOn.vh.parts.eT._color[1] == 1 and tOn.label._tc[1] == 1 and tOn.label._tc[3] > 0.7,
    "the current tab: a gold edge, its glow, bright text")
  ok(tOff and not (tOff.vh.parts.glow and tOff.vh.parts.glow:IsShown()) and tOff.vh.parts.eT._color[1] < 0.5 and tOff.label._tc[1] == 0.7, "the other tabs: a dimmer edge, grey-gold text")
  local mOn, mOff = cf.modeCrafts, cf.modeHarvest
  if mOff.vh.selected then mOn, mOff = mOff, mOn end
  ok(mOn.vh.selected and mOn.vh.parts.iron:IsShown() and mOn.vh.parts.glow:IsShown() and mOn.vh.parts.eT._color[1] == 1 and mOn.text._tc[3] == 0.72, "Norse: the chosen toggle lit (gold edge, glow, bright text)")
  ok(not (mOff.vh.parts.glow and mOff.vh.parts.glow:IsShown()) and mOff.vh.parts.eT._color[1] < 0.5 and mOff.text._tc[1] == 0.7, "Norse: the other one dimmer (edge, text)")
  ok(cf.known.vh.parts.fill:IsShown() and not cf.known.vh.parts.box:IsShown() and cf.known.tick._vc[3] == 0.4, "the tick box: iron, its tick gold")
  ok(r1.minus.vh.parts.a1._atlas == "common-icon-backarrow" and r1.minus.vh.parts.iron:IsShown(), "the stepper: gold arrows on iron")
  local hdr = lp.builderHead
  local titleFont
  for fs in pairs(St.all) do if fs.vh.kind == "title" then titleFont = fs break end end
  ok(titleFont and titleFont._font[1] == "Fonts\\MORPHEUS.TTF", "titles: Morpheus")
  ok(lp.name._font == nil and b.text._font == nil, "small print: the game's font still")
  ok(W.sizeFired == laid0, "switching laid nothing out (no size asked)")
  local n1 = 0 for _ in pairs(St.all) do n1 = n1 + 1 end
  ok(n1 == n0, "no widget made again (the same ones repainted)", n0 .. " " .. n1)
  W.Click(sp.look.boxes[1])
  ok(St.Look() == "profession" and b.vh.parts["3L"]:IsShown() and not b.vh.parts.iron:IsShown() and titleFont._font[1] ~= "Fonts\\MORPHEUS.TTF", "Profession again: the red pieces back, the iron hidden, the game's font")
  ok(not St.SetLook("bogus") and St.Look() == "profession", "an unknown look: refused")
  ok(not sp.vh.parts.ktl:IsShown() and not sp.vh.parts.n1:IsShown() and sp._edge ~= nil, "Profession: the pages' plain edge again (the bronze hidden)")
  -- the AH list: its secure Search buttons untouched
  local secure = Find(function(f) return type(f._template) == "string" and f._template:find("SecureActionButtonTemplate", 1, true) end)
  local untouched = #secure > 0
  for _, f in ipairs(secure) do if f.vh or not (f._backdrop and f._backdrop.edgeSize == 1 and f._edge and math.abs(f._edge[1] - 0.66) < 0.001) then untouched = false end end
  ok(untouched, "the secure Search buttons: never skinned (their flat look kept)", #secure)
  local ref0 = St.refused
  St.Button(secure[1], "button", 64, 20) St.Check(secure[1]) St.Panel(secure[1]) St.SetLook("norse") St.SetLook("profession")
  ok(secure[1].vh == nil and St.refused >= ref0 + 1 and secure[1]._edge[1] - 0.66 < 0.001, "and refused when asked", St.refused - ref0)
  local ah = _G.ValhallaAHList
  ok(ah and ah.vh and ah.vh.kind == "panel" and ah.minimize.vh.as == "minus" and ah.picker.vh.as == "dropdown", "the AH list: the look's panel, its - the square minus, its list a dropdown")
  -- a window's frame (Map windows, the map menu) on a client without the nine-slice layout: a plain frame, 0
  local win = CreateFrame("Frame", nil, UIParent)
  ok(St.Frame(win) == 0 and win.vh.kind == "frame" and win.vh.parts.bg._atlas == "profession-background-template2-c60", "Style.Frame: the profession background (no layout here: no title bar)")
  NineSliceUtil = { GetLayout = function() return {} end, ApplyLayoutByName = function() return true end }
  local win2 = CreateFrame("Frame", nil, UIParent)
  ok(St.Frame(win2) == 21 and win2.vh.nine and win2.vh.nine._template == "NineSlicePanelTemplate", "with it: the metal nine-slice, a 21 px title bar")
  St.SetLook("norse")
  ok(not win2.vh.nine._shown and win2.vh.parts.n1:IsShown() and win2.vh.parts.ktl._atlas == "heavybronze-horz-cornerbracket-tl-c60" and win2.vh.parts.n1._coord ~= nil, "Norse: heavy bronze, cut in nine, its corner brackets")
  St.SetLook("profession")
  ok(win2.vh.nine._shown and not win2.vh.parts.n1:IsShown(), "Profession: the metal again")
  NineSliceUtil = nil
  -- the game's template buttons and boxes (Map windows): theirs hidden, ours on
  local tbn = St.UIButton(parent)
  tbn.Left, tbn.Middle, tbn.Right = tbn:CreateTexture(), tbn:CreateTexture(), tbn:CreateTexture()
  St.Apply(tbn)
  ok(tbn._template == "UIPanelButtonTemplate" and tbn.vh.template and tbn.Left._alpha == 0 and tbn.vh.parts["3L"]:IsShown(), "UIPanelButtonTemplate: its own art hidden under the look's")
  local ib = St.UIInput(parent)
  ok(ib._template == "InputBoxTemplate" and ib.vh.kind == "input" and ib.vh.template, "InputBoxTemplate: the look's box")
  local sf = St.UIScroll(parent)
  ok(sf._template == "UIPanelScrollFrameTemplate" and sf.vh and sf.vh.kind == "scroll", "UIPanelScrollFrameTemplate: the look's bar")
  ok(W.blockedSetters == 0 and Keys(WorldMapFrame) == mapKeys and #W.sizeErrors == errs0, "v0.4.2 wrote nothing on the map; no handler error")
  ValhallaDB = nil
  T.Select("map")
end)()

print("== 33. v0.4.2.1: pages not scrolling, |< >| pager ends, Craft's grid and filter, the AH list framed and paged, dropdowns close outside, shift-click into search")
;(function()
  local St, Mk, V = ns.Style, I.Market, I.Views
  local errs0 = #W.sizeErrors
  ValhallaDB = nil
  WorldMapFrame:Show()
  Slash("invest", "market")
  local root = T.Views().invest.page
  local mp = root.pages.market
  for _, look in ipairs({ "profession", "norse" }) do
    St.SetLook(look)
    local tag = look == "norse" and "Norse: " or "Profession: "
    -- 1. the pager's ends: one arrow, a stop bar at its far side; the four the same size
    mp:ShowSub("mine")
    local pg = mp.subs.mine.pager
    local f1, l1 = pg.first.vh.parts, pg.last.vh.parts
    ok(f1.a1:IsShown() and not (f1.a2 and f1.a2:IsShown()) and f1.stop:IsShown() and l1.a1:IsShown() and l1.stop:IsShown(), tag .. "|< and >|: one arrow each and a stop bar (no second arrow over it)")
    local fp, lpnt = f1.stop._points[1], l1.stop._points[1]
    ok(fp and lpnt and fp[2] < 0 and lpnt[2] > 0 and f1.stop._w == 2, tag .. "the bar: left of |<'s arrow, right of >|'s, 2 px wide", fp and fp[2])
    ok(pg.first._w == pg.prev._w and pg.prev._w == pg.next._w and pg.next._w == pg.last._w and pg.first._h == pg.prev._h, tag .. "the four the same size")
    ok(f1.a1._atlas == pg.prev.vh.parts.a1._atlas, tag .. "|<'s arrow: < 's own art")
  end
  St.SetLook("profession")
  -- 2. no wheel on a paged list; Settings' page still scrolls
  for _, key in ipairs({ "mine", "results", "craft" }) do
    mp:ShowSub(key)
    local f = mp.subs[key]
    ok(not rawget(f, "_wheel") and not rawget(f, "_scripts").OnMouseWheel, "no wheel on " .. key .. ": its pager's buttons only")
  end
  -- 3. Craft: Reagents: and Show: in measured columns; a name filter
  mp:ShowSub("craft")
  local cf = mp.subs.craft
  ok(cf.showTitle._text == "Show:" and cf.known:GetParent() == cf.showRow and cf.bank:GetParent() == cf.showRow, "Craft's second row: Show: Known only, Count the bank")
  local rows = { cf.owned.boxes, { cf.known, cf.bank } }
  local clear = true
  for _, bx in ipairs(rows) do
    for k = 1, #bx - 1 do
      local a, b = bx[k], bx[k + 1]
      if not (a.col + 16 + 6 + a.labelW + 8 <= b.col - 3) then clear = false end
    end
  end
  ok(clear, "each label ends 8 px or more before the next box's art (3 px over its edge)")
  ok(cf.known.col == cf.owned.boxes[1].col and cf.bank.col == cf.owned.boxes[2].col, "Show:'s boxes in Reagents' columns")
  ok(cf.owned.boxes[1].col >= V.TextWidth(cf.owned.title) + 16 and cf.owned.boxes[1].col >= V.TextWidth(cf.showTitle) + 16, "the boxes start after the wider title", cf.owned.boxes[1].col)
  ok(cf.known._w == 16 and cf.known.labelW > 0, "the box still 16 px (its label measured)")
  ok(cf.filter and cf.filter.vh.kind == "input" and cf.filterHint:IsShown(), "a name filter box (the look's), its hint while empty")
  Mk.craftProf, Mk.craftMode = 182, "harvest" mp:Refresh()   -- (Herbalism's harvest: read at once)
  for _ = 1, 400 do if not I.Craft.Running() then break end I.Craft.Tick() end
  cf.filter:SetText("") W.Run(cf.filter, "OnTextChanged")
  local all = #(cf.list or {})
  local want
  for _, e in ipairs(cf.list or {}) do want = want or V.ItemData(e.out or e.id) end
  if want then
    cf.filter:SetText(want) W.Run(cf.filter, "OnTextChanged")
    local good = #cf.list >= 1 and #cf.list <= all
    for _, e in ipairs(cf.list) do if not (V.ItemData(e.out or e.id) or ""):lower():find(want:lower(), 1, true) then good = false end end
    ok(good and not cf.filterHint:IsShown() and cf.filterCount._text == ("%d of %d"):format(#cf.list, all) and cf.offset == 0, "filtered: only names with it, on page 1, 'n of all' beside it", cf.filterCount._text)
    cf.filter:SetText("zzzz no such") W.Run(cf.filter, "OnTextChanged")
    ok(#cf.list == 0 and not cf.pager:IsShown(), "nothing matches: an empty page")
  else
    ok(false, "Craft had a list to filter", tostring(all) .. " " .. tostring(cf.status._text))
  end
  -- shift-click an item while the filter has the cursor: its name
  cf.filter:SetFocus() W.now = W.now + 1
  W.ShiftClickBag("|cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r", 20)
  ok(cf.filter._text == "Linen Cloth" and not StackSplitFrame:IsShown(), "Craft's filter: a shift-clicked item's name (in place of what was typed), no stack-split box", cf.filter._text)
  cf.filter:ClearFocus() cf.filter:SetText("") W.Run(cf.filter, "OnTextChanged")
  ok(#cf.list == all, "cleared: the whole list again")
  Mk.craftMode = "crafts" mp:Refresh()
  -- 4. the dropdown closes on a click outside it
  W.Click(cf.drop)
  ok(cf.menu:IsShown() and St.openMenus[cf.menu] == cf.drop, "open: watched")
  cf.menu.IsMouseOver = function() return true end
  W.Fire("GLOBAL_MOUSE_DOWN", "LeftButton")
  ok(cf.menu:IsShown(), "a press on the menu: stays open (its line's click picks)")
  cf.menu.IsMouseOver = nil cf.drop.IsMouseOver = function() return true end
  W.Fire("GLOBAL_MOUSE_DOWN", "LeftButton")
  ok(cf.menu:IsShown(), "a press on its own button: left to the button (it toggles)")
  cf.drop.IsMouseOver = nil
  W.Fire("GLOBAL_MOUSE_DOWN", "LeftButton")
  ok(not cf.menu:IsShown() and next(St.openMenus) == nil, "a press anywhere else: closed, nothing watched")
  local closer
  for _, f in ipairs(W.frames) do if rawget(f, "_scripts") and f._scripts.OnEvent == St.CloseOutside then closer = f end end
  ok(closer and not closer._events.GLOBAL_MOUSE_DOWN, "no menu open: the listener off (GLOBAL_MOUSE_DOWN unregistered)")
  -- 5. Scan results' search: shift-click an item: its name
  mp:ShowSub("results")
  local rf = mp.subs.results
  rf.search:SetFocus() W.now = W.now + 1
  W.ShiftClickBag("|cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r", 20)
  ok(rf.search._text == "Linen Cloth" and not StackSplitFrame:IsShown() and rf.offset == 0, "Scan results' search: a shift-clicked item's name, page 1", rf.search._text)
  W.ShiftClickBag("|cffffffff|Hitem:2592::::::::|h[Wool Cloth]|h|r", 20)
  ok(rf.search._text == "Wool Cloth", "another: in place of the first (as the game's search boxes)")
  rf.search:ClearFocus() rf.search:SetText("") W.Run(rf.search, "OnTextChanged")
  W.ShiftClickBag("|cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r", 20)
  ok(rf.search._text == "", "no cursor in it: the game's own shift-click")
  -- 6. the Shopping List: its draft and its lists page (no wheel)
  root:ShowPage("list")
  local lp = root.pages.list
  I.DraftClear()
  for k = 1, 8 do I.DraftAdd(961000 + k) end
  lp:Refresh()
  local shown = 0 for _, r in ipairs(lp.drows) do if r:IsShown() then shown = shown + 1 end end
  ok(lp.dpager:IsShown() and shown == V.DRAFT_ROWS and lp.dpager.label._text == "1 of 2 · 8 items" and lp.dpager.first.off, "8 in the draft: 6 on page 1, its pager", lp.dpager.label._text)
  W.Click(lp.dpager.next)
  shown = 0 for _, r in ipairs(lp.drows) do if r:IsShown() then shown = shown + 1 end end
  ok(lp.doffset == 6 and shown == 2 and lp.drows[1].id == 961007 and lp.dpager.last.off, "next: the last 2")
  local wheel = false for _, r in ipairs(lp.drows) do if rawget(r, "_scripts").OnMouseWheel then wheel = true end end
  ok(not wheel, "the draft's rows: no wheel")
  I.DraftRemove(961007) I.DraftRemove(961008)
  ok(lp.doffset == 0 and not lp.dpager:IsShown(), "back to 6: one page, no pager")
  I.DraftClear()
  -- the saved lists: as many lines as the page has room for (from its own OnSizeChanged), the pager under the last
  local SL1 = MakeList("Fit A", { { 961001, 1 }, { 961002, 1 }, { 961003, 1 }, { 961004, 1 }, { 961005, 1 } })
  local SL2 = MakeList("Fit B", { { 961006, 1 }, { 961007, 1 }, { 961008, 1 }, { 961009, 1 }, { 961010, 1 } })
  local laid = W.sizeFired
  W.Run(lp, "OnSizeChanged", 760, 590)
  local vis = 0 for _, ln in ipairs(lp.lines) do if ln:IsShown() then vis = vis + 1 end end
  local pp = lp.lpager._points[1]
  local top = lp.lines[1]._points[1][3] + 20
  ok(top == -324 and lp.per == 10 and vis == 10 and pp[3] == top - 20 - 10 * 21 - 2 and lp.lpager:IsShown(), "590 px high: 10 lines, the pager under the 10th", lp.per .. " " .. vis)
  W.Run(lp, "OnSizeChanged", 760, 900)
  vis = 0 for _, ln in ipairs(lp.lines) do if ln:IsShown() then vis = vis + 1 end end
  ok(lp.per == 20 and #lp.lines == 20 and vis == math.min(20, #lp.entries), "taller: up to 20 (made when first needed)", lp.per)
  W.Run(lp, "OnSizeChanged", 760, 300)
  ok(lp.per == 3, "very short: 3 at least")
  ok(W.sizeFired == laid, "fitting asked no size")
  W.Run(lp, "OnSizeChanged", 760, 626)
  ok(lp.per == 12, "626 px: 12, as before")
  I.DeleteList(SL1.id) I.DeleteList(SL2.id) I.undo = {}
  -- 7. the AH list: framed in Norse (the bronze and its brackets), a page of 13, secure buttons untouched
  local items = {} for k = 1, 20 do items[k] = { 961000 + k, 1 } end
  local PL = MakeList("Paged AH", items)
  I.SetActive(PL.id)
  W.Fire("AUCTION_HOUSE_SHOW")
  local ap = A.Panel()
  local function Rows() local n = 0 for _, r in ipairs(ap.rows) do if r:IsShown() then n = n + 1 end end return n end
  ok(#A.Rows() == 20 and Rows() == 13 and ap.pager:IsShown() and ap.pager.label._text == "1 of 2", "20 to buy: 13 on page 1, its pager", ap.pager.label._text)
  local sb1 = ap.rows[1].search
  local attr = sb1:GetAttribute("clickbutton")
  W.Click(ap.pager.next)
  ok(Rows() == 7 and ap.rows[1].id == 961014 and sb1:GetAttribute("clickbutton") == attr and sb1.vh == nil, "next: the other 7 (the same secure buttons, nothing set on them)")
  ok(ap.vh.framed and not ap.vh.parts.n1:IsShown(), "Profession: framed, no bronze (its own edge)")
  St.SetLook("norse")
  ok(ap.vh.parts.n1:IsShown() and ap.vh.parts.ktl:IsShown() and ap.vh.parts.ktl._atlas == "heavybronze-horz-cornerbracket-tl-c60", "Norse: the AH list in heavy bronze, bracketed")
  ok(ap.picker.vh.parts.iron:IsShown() and sb1.vh == nil, "its controls iron; the secure Search buttons untouched")
  ok(not ap.picker.text._text:find("  v", 1, true) and ap.picker.text._text == "List: Paged AH", "its list picker: no trailing 'v'", ap.picker.text._text)
  -- painted again on each visit (a widget left in the other look: right again)
  ap.vh.look = "profession" ap.vh.parts.n1:Hide()
  W.Fire("AUCTION_HOUSE_CLOSED") W.Fire("AUCTION_HOUSE_SHOW")
  ok(ap.vh.look == "norse" and ap.vh.parts.n1:IsShown(), "the AH opened: the look applied again to its list")
  -- the picker's menu closes on a click outside too
  W.Click(ap.picker)
  ok(ap.picker.menu:IsShown(), "the AH list's picker: open")
  W.Fire("GLOBAL_MOUSE_DOWN", "LeftButton")
  ok(not ap.picker.menu:IsShown(), "a click outside: closed")
  -- /valhalla look check: printed lines, saved
  local d = St.CheckLook(A.LookInfo())
  ok(d.look == "norse" and d.widgets > 50 and d.ahBronze and d.ahFramed and d.ahLook == "norse" and ValhallaDB.ui.lookCheck == d and #d.lines >= 3, "look check: Norse, the AH list framed in bronze; saved in ValhallaDB.ui.lookCheck", d.lines[1])
  ok(d.lines[#d.lines]:find("AH side window: norse look, framed yes, bronze shown", 1, true), "its AH line", d.lines[#d.lines])
  local bad = CreateFrame("Frame", nil, UIParent)
  bad.vh = { kind = "button", parts = {}, state = {}, used = {} }
  St.all[bad] = true
  bad.CreateTexture = function() error("boom") end
  St.Reskin()
  St.all[bad] = nil
  local d2 = St.CheckLook()
  ok(#St.errors >= 1 and d2.errors[#d2.errors]:find("boom", 1, true), "a widget that fails to paint: recorded, the rest painted")
  St.errors = {}
  St.SetLook("profession")
  W.Fire("AUCTION_HOUSE_CLOSED")
  I.DeleteList(PL.id) I.undo = {}
  ok(Keys(WorldMapFrame) == mapKeys and #W.sizeErrors == errs0, "v0.4.2.1 wrote nothing on the map; no handler error")
  ValhallaDB = nil
  T.Select("map")
end)()

print("== 34. v0.4.2.3: Top 10 filtered: All | Crafted | Harvested, a profession, its level (Wowhead Forever's skills)")
;(function()
  local St, Mk, Sc, Cr = ns.Style, I.Market, I.Scan, I.Craft
  local errs0 = #W.sizeErrors
  ValhallaDB = nil
  -- the bundled levels: numbers or false (unknown, never a guess); Mining harvested only
  local TS = ns.TopSkills
  ok(TS and TS.craft and TS.harvest and TS.source:find("Wowhead Forever", 1, true), "Data/Forever/TopSkills.lua loaded, its source named")
  local bad, nums, unk = 0, 0, 0
  for _, kind in ipairs({ "craft", "harvest" }) do
    for p, t in pairs(Cr.TopMap(kind)) do
      for id, v in pairs(t) do
        if v == false then unk = unk + 1 elseif type(v) == "number" and v >= 1 and v <= 400 then nums = nums + 1 else bad = bad + 1 end
      end
    end
  end
  ok(bad == 0 and nums > 1000 and unk > 0, "every level a skill (1-400) or false (unknown)", ("%d known, %d unknown, %d bad"):format(nums, unk, bad))
  ok(Cr.TopMap("craft")[186] == nil and Cr.TopMap("harvest")[186] ~= nil, "Mining: Harvested only, not Crafted")
  local sk, fi = 0, 0
  for _, v in pairs(Cr.TopMap("harvest")[393]) do if v ~= false then sk = sk + 1 end end
  for _, v in pairs(Cr.TopMap("harvest")[356]) do if v ~= false then fi = fi + 1 end end
  ok(sk == 0 and fi == 0, "Skinning and Fishing: none read, so all unknown (none estimated)")
  ok(Mk.TopSkill("harvest", 182, 2447) == 1 and Mk.TopSkill("harvest", 182, 785) == 50 and Mk.TopSkill("harvest", 182, 13463) == 270 and Mk.TopSkill("harvest", 182, 19726) == false,
    "Herbalism: Peacebloom 1, Mageroyal 50, Dreamfoil 270 (node skills), Bloodvine unknown")
  ok(Mk.TopSkill("craft", 171, 2459) == 60 and Mk.TopSkill("craft", 171, 3387) == 250 and Mk.TopSkill("craft", 171, 2455) == false and Mk.TopSkill("craft", 171, 2447) == nil,
    "Alchemy: Swiftness Potion 60, Limited Invulnerability Potion 250, Minor Mana Potion unknown; a herb isn't Alchemy's")
  -- the defaults, saved with the settings
  ok(I.S.topKind == "all" and I.S.topProf == 0 and I.S.topBracket == "all" and ValhallaInvestDB.settings == I.S, "defaults: All, any profession, all levels (in ValhallaInvestDB's settings)")
  -- a house: 12 other items rising faster than any herb, then herbs, ore, a hide, potions
  local hm = Sc.Market("Filt", true)
  local now = math.floor(W.now / 60) - hm.base
  local s = math.floor(now / Sc.SLOT)
  local a, b, c = (s - 5) * Sc.SLOT, (s - 2) * Sc.SLOT, s * Sc.SLOT + 1
  hm.scans = { { t = a, kind = "full", n = 1, items = 1 }, { t = b, kind = "full", n = 1, items = 1 }, { t = c, kind = "full", n = 1, items = 1 } }
  local function Item(id, change)
    local x = math.floor(100 * (1 + change) + 0.5)
    Sc.AddPoint(hm, id, a, 100, 1, 1) Sc.AddPoint(hm, id, b, x, 1, 1) Sc.AddPoint(hm, id, c, x, 1, 1)
    hm.cur[id] = ("%d,%d,%d,%d"):format(x, 1, 1, c)
  end
  for k = 1, 12 do Item(900000 + k, 1 + k / 10) end
  Item(2447, 0.10) Item(785, 0.09) Item(13463, 0.08) Item(19726, 0.07) Item(2770, 0.04) Item(4232, 0.03)
  Item(2459, -0.20) Item(2455, -0.15) Item(3387, -0.10)
  local r10, f10 = Sc.Trending("Filt", 10)
  local rAll, fAll, fulls = Sc.TrendingAll("Filt")
  ok(fulls == 3 and #r10 == 10 and #rAll == 18 and #fAll == 3 and rAll[1].id == 900012, "Scan keeps the full sorted lists (18 rising); Trending gives the first 10", #rAll)
  ok(select(1, Sc.TrendingAll("Filt")) == rAll, "the full lists cached (one read per scan)")
  WorldMapFrame:Show()
  Slash("invest", "market")
  local mp = T.Views().invest.page.pages.market
  Mk.house = "Filt"
  mp:ShowSub("top")
  local top = mp.subs.top
  local function Ids(c2) local t = {} for _, r in ipairs(top.cols[c2].rows) do if r:IsShown() then t[#t + 1] = r.cell.id end end return t end
  for _, look in ipairs({ "profession", "norse" }) do
    St.SetLook(look)
    local tag = look == "norse" and "Norse: " or "Profession: "
    I.S.topKind, I.S.topProf, I.S.topBracket = "all", 0, "all"
    mp:Refresh()
    local r = Ids(1)
    ok(#r == 10 and r[1] == 900012 and top.kinds[1]:IsShown() and not top.prof:IsShown() and not top.level:IsShown() and not top.note:IsShown(),
      tag .. "All: the top 10 as before; no profession or level dropdown")
    W.Click(top.kinds[3])
    r = Ids(1)
    ok(I.S.topKind == "harvest" and top.prof:IsShown() and not top.level:IsShown() and #r == 6 and r[1] == 2447 and r[6] == 4232,
      tag .. "Harvested: filtered first, then the top 10 (herbs, ore, a hide; the 12 faster items aren't harvested)", table.concat(r, ","))
    W.Click(top.prof)
    local names, herb = {}, nil
    for _, it in ipairs(top.prof.menu.items) do if it:IsShown() then names[#names + 1] = it.text._text if it.value == 182 then herb = it end end end
    ok(top.prof.menu:IsShown() and #names == 5 and names[1]:find("Any profession", 1, true), tag .. "the profession dropdown: Any, then the four gathering professions", table.concat(names, "|"))
    W.Click(herb)
    r = Ids(1)
    ok(I.S.topProf == 182 and not top.prof.menu:IsShown() and top.level:IsShown() and top.levelTitle:IsShown() and #r == 4 and top.level.text._text == "All levels",
      tag .. "Herbalism picked: its herbs; the Level dropdown appears (All levels)", table.concat(r, ","))
    -- the level dropdown: right of the lists, its menu over no prices
    local lp = top.level._points[1]
    local colRight = 0
    for _, col in ipairs(top.cols) do local cp = col._points[1] colRight = math.max(colRight, cp[2] + col._w) end
    ok(lp and lp[2] >= colRight and top.level.menu._points[1][2] == top.level and top.level.menu._points[1][3] == "BOTTOMLEFT",
      tag .. "the Level dropdown sits right of Rising and Falling, its menu opens below it: no prices covered", ("%s >= %s"):format(lp and lp[2], colRight))
    W.Click(top.level)
    local lv = {}
    for _, it in ipairs(top.level.menu.items) do if it:IsShown() then lv[#lv + 1] = it.text._text end end
    ok(top.level.menu:IsShown() and table.concat(lv, "|") == "> All levels|1-150|151-225|226-300|301-375+", tag .. "Level: All levels, 1-150, 151-225, 226-300, 301-375+ (the chosen one marked)", table.concat(lv, "|"))
    W.Fire("GLOBAL_MOUSE_DOWN", "LeftButton")
    ok(not top.level.menu:IsShown(), tag .. "a click anywhere else: the Level menu closes")
    W.Click(top.level)
    W.Click(top.level.menu.items[2])
    r = Ids(1)
    ok(I.S.topBracket == "1" and #r == 2 and r[1] == 2447 and r[2] == 785 and top.note:IsShown() and top.note._text:find("^1 Herbalism items with no known skill level are hidden"),
      tag .. "1-150: Peacebloom and Mageroyal; Bloodvine (no known level) hidden and counted", top.note._text)
    W.Click(top.level) W.Click(top.level.menu.items[4])
    r = Ids(1)
    ok(I.S.topBracket == "226" and #r == 1 and r[1] == 13463 and top.level.text._text == "226-300", tag .. "226-300: Dreamfoil only (one bracket at a time)")
    W.Click(top.level) W.Click(top.level.menu.items[5])
    ok(#Ids(1) == 0 and top.empty:IsShown() and top.empty._text:find("No Herbalism (301-375+) item moved", 1, true) and top.note:IsShown() and not top.cols[1]:IsShown(),
      tag .. "301-375+: nothing; says so, and the hidden count still shown", top.empty._text)
    -- Crafted: Mining isn't offered; Alchemy 226-300
    W.Click(top.kinds[2])
    ok(I.S.topKind == "craft" and I.S.topProf == 0 and I.S.topBracket == "all" and not top.level:IsShown(), tag .. "Crafted: the profession and level start over")
    W.Click(top.prof)
    local alch, mining = nil, false
    for _, it in ipairs(top.prof.menu.items) do if it:IsShown() then if it.value == 171 then alch = it end if it.value == 186 then mining = true end end end
    ok(alch and not mining, tag .. "Crafted's professions: no Mining")
    W.Click(alch)
    W.Click(top.level) W.Click(top.level.menu.items[4])
    local f2 = Ids(2)
    ok(#f2 == 1 and f2[1] == 3387 and top.note._text:find("^1 Alchemy items", 1) and #Ids(1) == 0, tag .. "Alchemy 226-300: Limited Invulnerability Potion falling; Minor Mana Potion hidden, counted", table.concat(f2, ","))
  end
  St.SetLook("profession")
  -- kept between sessions (ValhallaInvestDB.settings), a saved value that no longer fits starts over
  ok(ValhallaInvestDB.settings.topKind == "craft" and ValhallaInvestDB.settings.topProf == 171 and ValhallaInvestDB.settings.topBracket == "226", "the filter saved (SavedVariables)")
  I.S.topProf = 186
  local k2, p2, b2 = Mk.TopState()
  ok(k2 == "craft" and p2 == nil and b2 == "all", "a saved Mining under Crafted: any profession, all levels")
  I.S.topKind, I.S.topProf, I.S.topBracket = "all", 0, "all"
  mp:Refresh()
  Sc.Houses().Filt = nil
  Mk.house = nil
  ok(Keys(WorldMapFrame) == mapKeys and #W.sizeErrors == errs0, "v0.4.2.3 wrote nothing on the map; no handler error")
  T.Select("map")
end)()

print(("\n%d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
