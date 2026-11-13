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
for _, f in ipairs({ "Invest", "Scan", "Tabs", "Views", "Market", "Tooltip", "Data/Forever/Recipes", "Data/Forever/TopSkills", "Craft", "Trainer", "Merchant", "AHPanel" }) do
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
  ok(#p2589 == 1 and not p2589[1].quick, "the same hour: one point per item; a quick scan keeps the full scan's point (v0.4.2.8)", #p2589)
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
  ok(Mk.House() == "Alliance", "(v0.4.2.7) AH Market's house: Alliance until one is picked, whatever AH was visited last")
  I.S.marketHouse = "Horde"   -- (picked with the Horde button: kept in the settings)

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
  ok(mp.status._text:find("^Horde Auction House") and #mp.houseButtons == 3 and mp.houseButtons[2].house == "Horde" and mp.houseButtons[2].vh.selected
    and not mp.houseButtons[1].vh.selected and not mp.houseButtons[3].vh.selected, "the house picked, lit among Alliance | Horde | Neutral", mp.status._text)
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
  W.Click(mp.houseButtons[1])
  ok(mp.status._text:find("^Alliance") and I.S.marketHouse == "Alliance" and mp.houseButtons[1].vh.selected, "another house chosen: kept in the settings")
  ok(mp.houseButtons[3]:GetAlpha() < 1 and mp.houseButtons[1]:GetAlpha() == 1, "Neutral: dimmer (no scan of it yet)")
  W.Click(mp.houseButtons[3])
  ok(mp.status._text:find("^Neutral") and mp.houseButtons[3].vh.selected and I.S.marketHouse == "Neutral", "Neutral picked: its own market")
  W.Click(mp.houseButtons[2])

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
  Sc.AddPoint(hmk, 777001, slot + 30, 470, 3, "q")
  ok(#Sc.Points(hh, 777001) == 1 and Sc.Points(hh, 777001)[1].min == 500 and not Sc.Points(hh, 777001)[1].quick, "(v0.4.2.8) a quick scan in the hour of a full scan: the full point kept")
  Sc.AddPoint(hmk, 777001, slot + 40, 450, 3, 2)
  mp:Refresh()
  local pts = Sc.Points(hh, 777001)
  ok(hf2.drawn == 1 and #pts == 1 and pts[1].min == 450, "a second full scan in the same hour: still one point (the latest)")
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
  ok(f1.cost == 100 and f1.can == 0 and v1.cost == 100, "Owned: 1 thread bought, the dye yours (1.0.1: no vendor value; an old \"vendor\" prices as Owned here, Market after the migration)", f1.cost .. " " .. v1.cost)
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
  ok(row:IsShown() and row.cell.id == 910001 and row.cell.icon._tex ~= nil and row.cost._text == Sc.Money(500) and row.known == nil, "the Top 10: item cells (icon, name), cost (1.0.1: no Known column)", row.cost._text)
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
  ok(Mk.craftProf == 129 and not cf.menu:IsShown() and cf.rows[1]:IsShown() and cf.list[1].known, "First Aid picked, Known only: its known crafts listed", cf.status._text)
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
  I.S.craftOwned = "free"   -- (v0.4.2.9: Count works with the Owned modes; Market: greyed, None)
  mp:Refresh()
  W.Click(cf.countDrop) W.Click(cf.countDrop.menu.items[2])   -- (v0.4.2.8: Count: Bags only, Craft's own dropdown)
  for _ = 1, 400 do if not Cr.Running() then break end Cr.Tick() end
  mp:Refresh()
  local e1 = cf.list[1]
  ok(e1.can == 10 and math.abs(e1.total - e1.profit * 10) < 0.01 and cf.rows[1].total._text == Sc.Money(e1.total), "Total: profit x can make (10 from the bags)", cf.rows[1].total._text)
  W.Click(cf.countDrop) W.Click(cf.countDrop.menu.items[3])   -- (v0.4.2.8: Count: Bags + bank)
  for _ = 1, 400 do if not Cr.Running() then break end Cr.Tick() end
  mp:Refresh()
  ok(I.S.craftCount == "bank" and cf.list[1].can == 15 and math.abs(cf.list[1].total - cf.list[1].profit * 15) < 0.01, "Count the bank: can make 15, Total follows")
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
  I.S.craftOwned = "market"
  ok(W.sizeMaxDepth <= 1 and #W.sizeErrors == errs0, "no layout loop: OnSizeChanged never nested, no error")
  -- Harvest
  Put(km, 785, 80) Put(km, 2447, 50) Put(km, 765, 30)
  Mk.craftProf = 197 mp:Refresh()
  ok(not cf.modeHarvest:IsShown() and not cf.modeCrafts:IsShown(), "Tailoring: no Harvest switch")
  Mk.craftProf = 182 mp:Refresh()
  ok(cf.modeHarvest:IsShown() and cf.modeCrafts:IsShown(), "Herbalism: Crafts | Harvest")
  W.Click(cf.modeHarvest)
  ok(Mk.craftMode == "harvest" and cf.rows[1].cell.id == 785 and cf.rows[2].cell.id == 2447 and cf.rows[3].cell.id == 765 and cf.rows[4].harvest.sell._text == "-"
    and cf.rows[1].harvest.sell._text == Sc.Money(80) and cf.head.harvestStrip:IsShown() and not cf.head.craftStrip:IsShown() and cf.owned:IsShown()
    and cf.status._text:find("herbs", 1, true) and #cf.list == Count(G[182].ids) and pg:IsShown(),
    "Harvest: every herb, dearest first, unlisted after; Crafts' columns (no Cost); paged", cf.status._text)
  Mk.craftProf = 186 mp:Refresh()
  local bar = false for _, e in ipairs(cf.list) do if e.id == 2840 then bar = true end end
  ok(Mk.craftMode == "harvest" and #cf.list == Count(G[186].ids) and not bar, "Mining's harvest: ores and stone, no bars")
  W.Click(cf.modeCrafts)
  ok(Mk.craftMode == "crafts" and cf.head.craftStrip:IsShown() and not cf.head.harvestStrip:IsShown() and cf.owned:GetAlpha() == 1 and not cf.ownedNote:IsShown(), "back to Crafts")
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
  ok(cf.showTitle._text == "Show:" and cf.known:GetParent() == cf.showRow and cf.countDrop:IsShown() and cf.countDrop.text._text:find("^Count: "),
    "Craft's second row: Show: Known only | the Count dropdown (v0.4.2.8)", cf.countDrop.text._text)
  local rows = { cf.owned.boxes }
  local clear = true
  for _, bx in ipairs(rows) do
    for k = 1, #bx - 1 do
      local a, b = bx[k], bx[k + 1]
      if not (a.col + 16 + 6 + a.labelW + 8 <= b.col - 3) then clear = false end
    end
  end
  ok(clear, "each label ends 8 px or more before the next box's art (3 px over its edge)")
  ok(cf.known.col == cf.owned.boxes[1].col, "Show:'s box in Reagents' first column")
  local dp = cf.countDrop._points
  ok(dp[1][2] == cf.owned.boxes[2] and dp[1][1] == "LEFT" and dp[2][2] == cf.showRow, "the Count dropdown under Owned free (Reagents' 2nd column), on the Show row")
  local mf0 = mp:Sub("mine")
  ok(mf0.scope.boxes[1].col == cf.owned.boxes[1].col, "My items' Count boxes start where Craft's do", mf0.scope.boxes[1].col .. " " .. cf.owned.boxes[1].col)
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
  ok(Mk.TopSkill("craft", 171, 2459) == 60 and Mk.TopSkill("craft", 171, 3387) == 250 and Mk.TopSkill("craft", 171, 2455) == 25 and Mk.TopSkill("craft", 171, 7076) == false and Mk.TopSkill("craft", 171, 2447) == nil,
    "Alchemy: Swiftness Potion 60, Limited Invulnerability Potion 250, Minor Mana Potion 25, Essence of Earth unknown; a herb isn't Alchemy's")
  -- (1.2.4) a fixture, not the bundled data: these items as the bundled data had them before 1.2.4 (no level known),
  -- so what's tested (a level found later) doesn't hang on which levels Data/Forever/TopSkills.lua has read
  local m171, was = I.Craft.TopMap("craft")[171], {}
  for _, id in ipairs({ 2455 }) do was[id] = m171[id] m171[id] = false end
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
    -- (1.2.0) an unknown level: shown at every level, marked "?" (was hidden and counted)
    local function Both() local t = {} for c2 = 1, 2 do for _, id in ipairs(Ids(c2)) do t[id] = true end end return t end
    local function Mark(id) for c2 = 1, 2 do for _, rr in ipairs(top.cols[c2].rows) do if rr:IsShown() and rr.cell.id == id then return rr.cell.suffix end end end end
    local b = Both()
    ok(I.S.topBracket == "1" and b[2447] and b[785] and b[19726] and not b[13463] and Mark(19726) == Mk.UNKNOWN_MARK and Mark(2447) == nil and Mark(785) == nil
      and top.cols[1].rows[1].cell.name._text:sub(-#Mk.UNKNOWN_MARK) ~= Mk.UNKNOWN_MARK
      and top.note:IsShown() and top.note._text:find("^%? 1 shown with no known Herbalism skill level yet: they show at every level%. Open a Herbalism trainer"),
      tag .. "1-150: Peacebloom and Mageroyal; Bloodvine (no known level) shown too, marked ?, the note says why", top.note._text)
    W.Click(top.level) W.Click(top.level.menu.items[4])
    b = Both()
    ok(I.S.topBracket == "226" and b[13463] and b[19726] and not b[2447] and not b[785] and top.level.text._text == "226-300", tag .. "226-300: Dreamfoil, and Bloodvine marked ? (one bracket at a time)")
    W.Click(top.level) W.Click(top.level.menu.items[5])
    b = Both()
    local n = 0 for _ in pairs(b) do n = n + 1 end
    ok(n == 1 and b[19726] and Mark(19726) == Mk.UNKNOWN_MARK and not top.empty:IsShown() and top.note:IsShown(),
      tag .. "301-375+: only Bloodvine (unknown: every level), marked ?", top.note._text)
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
    local has = {} for _, id in ipairs(f2) do has[id] = true end
    ok(#f2 == 2 and has[3387] and has[2455] and Mark(2455) == Mk.UNKNOWN_MARK and Mark(3387) == nil and top.note._text:find("^%? 1 shown with no known Alchemy skill level") and #Ids(1) == 0,
      tag .. "Alchemy 226-300: Limited Invulnerability Potion falling; Minor Mana Potion too, marked ?", table.concat(f2, ","))
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
  for id, v in pairs(was) do m171[id] = v end
end)()

print("== 35. v0.4.2.6: columns under their headers, every header sorts (kept), Craft's Count, Harvest like Crafts, Top 10's numbers fit")
;(function()
  local St, Mk, Sc, Cr = ns.Style, I.Market, I.Scan, I.Craft
  local errs0 = #W.sizeErrors
  St.SetLook("profession")
  for _, k in ipairs({ "sortResults", "sortMine", "sortCraft", "sortHarvest" }) do I.S[k] = nil end
  ok(Mk.SortTag("results") == "name:asc" and Mk.SortTag("mine") == "total:desc" and Mk.SortTag("craft") == "each:desc" and Mk.SortTag("harvest") == "sell:desc",
    "defaults: today's orders (Name; Total; Profit/item; Sell at)")
  local hm = Sc.Market("Cols", true)
  local tm = math.floor(W.now / 60) - hm.base
  hm.scans = { { t = tm, kind = "full", n = 12, items = 5 } }
  local function Put(id, min, units, auctions) hm.cur[id] = ("%d,%d,%d,%d"):format(min, units, auctions, tm) end
  Put(2589, 120, 40, 4) Put(2447, 300, 10, 2) Put(2770, 0, 5, 1) Put(765, 900, 25, 5) Put(13463, 5000, 3, 1)
  Mk.house = "Cols"
  WorldMapFrame:Show()
  Slash("invest", "market")
  local mp = T.Views().invest.page.pages.market
  -- one spec: each header over its own column (the same x and width as the rows' cells)
  local function Aligned(head, row, cells)
    local hx, rx = head._points[1][2], row._points[1][2]
    for _, b in ipairs(head.buttons) do
      local c = b.col
      local cell = c.item and row.cell or cells[c.key]
      if not cell then return false, c.key .. ": no cell" end
      if hx + b._points[1][2] ~= rx + cell._points[1][2] then return false, c.key .. ": x" end
      if b._w ~= c.w or cell._w ~= c.w then return false, c.key .. ": width" end
    end
    return true, ""
  end
  -- Scan results
  mp:ShowSub("results")
  local rf = mp.subs.results
  rf.search:SetText("")
  mp:Refresh()
  local al, why = Aligned(rf.head, rf.rows[1], rf.rows[1].cells)
  ok(al, "Scan results: every header over its own column (was off by up to 120 px)", why)
  local labels = {} for _, b in ipairs(rf.head.buttons) do labels[#labels + 1] = b.text._text end
  ok(table.concat(labels, "|") == "Name|Lowest|Quantity|Auctions|7-day change", "headers: Name, Lowest, Quantity (was Units), Auctions, 7-day change", table.concat(labels, "|"))
  ok(rf.head.buttons[1].arrow:IsShown() and rf.head.buttons[1].arrow.dir == "up" and not rf.head.buttons[2].arrow:IsShown(), "Name sorted A-Z: its arrow up, the others none")
  local function Mins() local t = {} for _, e in ipairs(rf.list) do t[#t + 1] = e.min end return table.concat(t, ",") end
  W.Click(rf.head.buttons[2])
  ok(Mins() == "120,300,900,5000,0" and rf.head.buttons[2].text._text == "Lowest" and rf.head.buttons[2].arrow.dir == "up", "Lowest: low to high, bid only (0) last", Mins())
  W.Click(rf.head.buttons[2])
  ok(Mins() == "5000,900,300,120,0" and rf.head.buttons[2].text._text == "Highest" and rf.head.buttons[2].arrow.dir == "down", "again: Highest (high to low), bid only still last", Mins())
  ok(I.S.sortResults == "min:desc", "kept in the settings (SavedVariables)", I.S.sortResults)
  W.Click(rf.head.buttons[3])
  ok(rf.list[1].units == 40 and rf.list[#rf.list].units == 3 and rf.head.buttons[2].text._text == "Lowest", "Quantity: most first; the price header back to Lowest")
  W.Click(rf.head.buttons[5])
  ok(I.S.sortResults == "change:desc" and #rf.list == 5 and rf.offset == 0, "7-day change: no change worked out goes last (here all: by name)")
  rf.list = nil mp:Refresh()
  ok(rf.head.buttons[5].arrow:IsShown(), "a rebuilt list keeps its sort")
  -- My items
  local keepBags, keepBank, keepScope = I.char.bags, I.char.bank, I.S.mineBank
  I.char.bags, I.char.bank, I.S.mineBank = { [2589] = 5, [2447] = 3, [2770] = 2 }, {}, false
  mp:ShowSub("mine")
  local mf = mp.subs.mine
  al, why = Aligned(mf.head, mf.rows[1], mf.rows[1].cells)
  ok(al, "My items: every header over its own column", why)
  ok(#mf.head.buttons == 6 and mf.head.buttons[6].arrow:IsShown() and mf.head.buttons[6].arrow.dir == "down", "My items: Total, high to low, by default (as before)")
  local function Names(list, field) local t = {} for _, e in ipairs(list) do t[#t + 1] = I.Views.ItemData(e[field or "id"]) or "?" end return table.concat(t, ",") end
  W.Click(mf.head.buttons[1])
  ok(Names(mf.list) == "Copper Ore,Linen Cloth,Peacebloom" and I.S.sortMine == "name:asc", "Item: A-Z", Names(mf.list))
  W.Click(mf.head.buttons[1])
  ok(Names(mf.list) == "Peacebloom,Linen Cloth,Copper Ore", "again: Z-A", Names(mf.list))
  W.Click(mf.head.buttons[2])
  ok(mf.list[1].n == 5 and mf.list[3].n == 2 and mf.rows[1].n._text == "5", "Have: most first, drawn so")
  -- Craft: Cost to Make; Harvest: Crafts' columns, no Cost
  mp:ShowSub("craft")
  local cf = mp.subs.craft
  local cl = {} for _, b in ipairs(cf.head.craft) do cl[#cl + 1] = b.text._text end
  ok(table.concat(cl, "|") == "Craft (makes)|Cost to Make|Sell at|Profit/item|Margin|Listed|Can make|Total", "Crafts' headers: Cost to Make (1.0.1: no Known)", table.concat(cl, "|"))
  al, why = Aligned(cf.head.craftStrip, cf.rows[1], cf.rows[1].craft)
  ok(al, "Crafts: every header over its own column", why)
  local keepGP, keepGPI = GetProfessions, GetProfessionInfo
  GetProfessions = function() return 1, nil, nil, nil, nil, nil end
  GetProfessionInfo = function(i) if i == 1 then return "Herbalism", 0, 60, 300, 0, 0, 182 end end
  Cr.Learned()
  ok(Cr.SkillRank(182) == 60 and Cr.SkillRank(186) == 0, "your skill: Herbalism 60 (the game's); Mining not yours: 0")
  I.char.bags = { [2447] = 4, [765] = 2 }
  I.S.craftKnownOnly = false
  Mk.craftProf, Mk.craftMode = 182, "harvest" mp:Refresh()
  local hl = {} for _, b in ipairs(cf.head.harvest) do hl[#hl + 1] = b.text._text end
  ok(table.concat(hl, "|") == "Item|Sell at|Profit/item|Listed|Have|Total" and cf.head.harvestStrip:IsShown() and not cf.head.craftStrip:IsShown(),
    "Harvest's headers: Crafts' less Cost, Margin (v0.4.2.8) and Known (Have for Can make)", table.concat(hl, "|"))
  al, why = Aligned(cf.head.harvestStrip, cf.rows[1], cf.rows[1].harvest)
  ok(al, "Harvest: every header over its own column (the item wider: no Cost)", why)
  local cut = Sc.Cut("Cols")
  local pb, dr
  for _, e in ipairs(cf.list) do if e.id == 2447 then pb = e elseif e.id == 13463 then dr = e end end
  ok(pb and math.abs(pb.each - 300 * (1 - cut)) < 1e-6 and pb.have == 4 and math.abs(pb.total - 4 * pb.each) < 1e-6 and pb.known == true,
    "Peacebloom: profit = the AH's lowest less the cut; Have 4; Total = 4 x profit; Known (skill 1, yours 60)")
  ok(dr and dr.known == false and dr.total == nil, "Dreamfoil: not Known (270 over your 60); none had: Total -")
  local row1 = cf.rows[1]
  ok(cf.list[1].id == 13463 and row1.harvest.sell._text == Sc.Money(5000) and row1.harvest.margin == nil and row1.harvest.known == nil
    and row1.harvest.total._text == "-" and row1.harvest.listed._text == "3" and row1.harvest.sell:IsShown() and not row1.cost:IsShown(),
    "the dearest first (Sell at), drawn in Crafts' columns; no Cost")
  ok(cf.owned:IsShown() and cf.owned:GetAlpha() < 1 and cf.owned.boxes[1]._mouse == false and cf.ownedNote:IsShown() and cf.ownedNote._text == "(crafts only)"
    and cf.known:IsShown() and cf.count:IsShown(), "the same filters: Reagents greyed (crafts only); Known only and Count work")
  W.Click(cf.known)
  ok(I.S.craftKnownOnly == true, "Known only on")
  local hiddenDF = true for _, e in ipairs(cf.list) do if e.id == 13463 then hiddenDF = false end end
  ok(hiddenDF and cf.status._text:find("above your skill hidden", 1, true), "Known only: Dreamfoil (above your skill) hidden, said", cf.status._text)
  W.Click(cf.known)
  local mb0 = I.S.mineBank
  W.Click(cf.countDrop) W.Click(cf.countDrop.menu.items[3])
  ok(I.S.craftCount == "bank" and I.S.mineBank == mb0, "Count: Bags + bank (Craft's own; My items' unchanged)")
  W.Click(cf.head.harvest[5])
  ok(I.S.sortHarvest == "have:desc" and cf.list[1].id == 2447 and cf.list[2].id == 765 and cf.offset == 0, "Have: most first; page 1")
  W.Click(cf.modeCrafts)
  ok(cf.owned:GetAlpha() == 1 and cf.owned.boxes[1]._mouse == true and not cf.ownedNote:IsShown() and cf.rows[1].cell._w == Mk.COLS.craft[1].w, "back to Crafts: Reagents live again; the item column its own width")
  GetProfessions, GetProfessionInfo = keepGP, keepGPI
  Cr.Learned()
  -- a stale saved column: the default
  I.S.sortMine = "bogus:up"
  ok(Mk.SortTag("mine") == "total:desc", "a saved sort that no longer fits: the default")
  -- empty last; equal values: the item ID's order, never another column (v0.4.2.7)
  local rows = { { id = 3, total = 5 }, { id = 1 }, { id = 2, total = 5 }, { id = 4, total = 9 } }
  I.S.sortMine = "total:asc"
  Mk.SortList(rows, "mine")
  ok(rows[1].id == 2 and rows[2].id == 3 and rows[3].id == 4 and rows[4].id == 1, "low to high: empty last, a tie by id")
  I.S.sortMine = "total:desc"
  Mk.SortList(rows, "mine")
  ok(rows[1].id == 4 and rows[2].id == 2 and rows[3].id == 3 and rows[4].id == 1, "high to low: empty still last")
  local tie = { { id = 7, n = 2, total = 1 }, { id = 3, n = 2, total = 9 }, { id = 5, n = 2, total = 5 } }
  I.S.sortMine = "n:desc"
  Mk.SortList(tie, "mine")
  ok(tie[1].id == 3 and tie[2].id == 5 and tie[3].id == 7, "a tie (Have 2 each): by item ID, not by Total (the default column)", tie[1].id .. tie[2].id .. tie[3].id)
  I.S.sortMine = "n:asc"
  Mk.SortList(tie, "mine")
  ok(tie[1].id == 3 and tie[2].id == 5 and tie[3].id == 7, "the other way: the tie's order unchanged (it isn't a second sort)")
  local cr = { { id = 20, out = 9, each = 4 }, { id = 10, out = 9, each = 4 }, { id = 30, out = 2, each = 4 } }
  I.S.sortCraft = "each:desc"
  Mk.SortList(cr, "craft")
  ok(cr[1].id == 30 and cr[2].id == 10 and cr[3].id == 20, "Craft: by the item made, then the recipe")
  I.S.sortCraft = nil
  -- Top 10: the widest change and price fit, one line each, measured with the game's font (FRIZQT, 11 px) drawn 1.3x
  -- wider (as the owner's client did: "+207%" didn't fit 46 px)
  mp:ShowSub("top")
  local top = mp.subs.top
  local col = top.cols[1]
  local ADV = { ["0"] = 7.047, ["1"] = 7.047, ["2"] = 7.047, ["3"] = 7.047, ["4"] = 7.047, ["5"] = 7.047, ["6"] = 7.047, ["7"] = 7.047, ["8"] = 7.047,
    ["9"] = 7.047, ["g"] = 6.812, ["s"] = 5.141, ["c"] = 5.734, [" "] = 2.875, ["+"] = 7.047, ["-"] = 4.328, ["%"] = 8.125 }
  local function Wd(s) local w = 0 for ch in tostring(s):gmatch(".") do w = w + (ADV[ch] or 8) end return w * 1.3 end
  for _, r in ipairs(col.rows) do
    r.change.GetStringWidth = function(self) return Wd(self._text or "") end
    r.price.GetStringWidth = function(self) return Wd(self._text or "") end
    r:Hide()
  end
  local function Row(i, ch, pr) local r = col.rows[i] r.change:SetText(ch) r.price:SetText(pr) r:Show() end
  Row(1, "+207%", "4g 33s 00c") Row(2, "+12%", "1g 30s 00c")
  local fit = Mk.FitTop(col)
  ok(fit.change >= Wd("+207%") and fit.price >= Wd("4g 33s 00c") and fit.name >= 130, "the owner's rows: +207% and 4g 33s 00c whole, the name roomy", ("%d %d %d"):format(fit.change, fit.price, fit.name))
  Row(3, "+1234%", "9999g 99s 99c") Row(4, "-100%", "1234g 56s 78c")
  fit = Mk.FitTop(col)
  local r1 = col.rows[1]
  ok(fit.change >= Wd("+1234%") and fit.price >= Wd("9999g 99s 99c") and r1.change._w == fit.change and r1.price._w == fit.price,
    "the widest: +1234% and 9999g 99s 99c fit their columns", ("%d >= %.1f, %d >= %.1f"):format(fit.change, Wd("+1234%"), fit.price, Wd("9999g 99s 99c")))
  ok(fit.changeX + fit.change + Mk.TOP_GAP <= fit.priceX and fit.priceX + fit.price + Mk.TOP_GAP <= fit.sparkX and fit.sparkX + Mk.SPARK * Mk.SPARK_STEP <= Mk.TOP_ROW_W
    and r1.cell._w + 2 + Mk.TOP_GAP <= fit.changeX and fit.name >= 100,
    "no overlap: name, change, price, sparkline, all in the row; the name keeps 100 px or more", fit.name)
  ok(r1.change._wrap == false and r1.price._wrap == false, "one line each: no wrapping")
  -- both lists line up alike: a narrower list takes the other's widths
  local wide = Mk.FitTop(col, { change = fit.change + 10, price = fit.price + 10 })
  ok(wide.change == fit.change + 10 and wide.price == fit.price + 10, "a column takes the other column's wider numbers")
  Mk.FitTop(col)
  for _, r in ipairs(col.rows) do r.change.GetStringWidth, r.price.GetStringWidth = nil, nil end
  I.char.bags, I.char.bank, I.S.mineBank = keepBags, keepBank, keepScope
  for _, k in ipairs({ "sortResults", "sortMine", "sortCraft", "sortHarvest" }) do I.S[k] = nil end
  Mk.house = nil
  mp:Refresh()
  ok(#W.sizeErrors == errs0, "no handler error")
end)()

print("== 36. v0.4.2.7: Harvest's Known only, titles that fit, one lit header, one sort, data for a sort, tooltips, houses")
;(function()
  local St, Mk, Sc, Cr, V = ns.Style, I.Market, I.Scan, I.Craft, I.Views
  local Frame = getmetatable(UIParent)   -- (the stubs' widget methods)
  local errs0 = #W.sizeErrors
  St.SetLook("profession")
  for _, k in ipairs({ "sortResults", "sortMine", "sortCraft", "sortHarvest" }) do I.S[k] = nil end
  local hm = Sc.Market("Fit", true)
  local tm = math.floor(W.now / 60) - hm.base
  hm.scans = { { t = tm, kind = "full", n = 12, items = 6 } }
  local function Put(id, min, units, auctions) hm.cur[id] = ("%d,%d,%d,%d"):format(min, units, auctions, tm) end
  Put(2589, 120, 40, 4) Put(2447, 300, 10, 2) Put(2770, 0, 5, 1) Put(765, 900, 25, 5) Put(13463, 5000, 3, 1)
  W.items[13463] = W.items[13463] or { "Dreamfoil", 134400 }
  Mk.house = "Fit"
  WorldMapFrame:Show()
  Slash("invest", "market")
  local mp = T.Views().invest.page.pages.market
  -- 1. Known only, every gathering profession: above your skill hidden; no level known: kept
  local keepGP, keepGPI, keepMine = GetProfessions, GetProfessionInfo, Cr.Mine
  GetProfessions = function() return 1, nil, nil, nil, nil, nil end
  GetProfessionInfo = function(i) if i == 1 then return "Herbalism", 0, 150, 300, 0, 0, 182 end end
  Cr.Mine = function() return { [182] = true } end
  local function Count(h, what) local n = 0 for _, e in ipairs(h.list) do if what(e) then n = n + 1 end end return n end
  for _, key in ipairs({ 182, 186, 393, 356 }) do
    local all, on = Cr.Harvest("Fit", key, false, false), Cr.Harvest("Fit", key, false, true)
    local above = Count(all, function(e) return e.known == false end)
    local unknown = Count(all, function(e) return e.known == nil end)
    ok(#on.list == #all.list - above and Count(on, function(e) return e.known == false end) == 0 and Count(on, function(e) return e.known == nil end) == unknown
      and on.above == above and on.unknown == unknown,
      ("Known only, skill line %d: %d of %d (%d above your skill hidden, %d with no level kept)"):format(key, #on.list, #all.list, above, unknown))
  end
  local herb = Cr.Harvest("Fit", 182, false, true)
  ok(herb.rank == 150 and herb.above > 0 and herb.unknown > 0, "Herbalism 150: some hidden, some with no level kept", herb.above .. " " .. herb.unknown)
  local skin = Cr.Harvest("Fit", 393, false, true)
  ok(#skin.list == #Cr.Harvest("Fit", 393, false, false).list and skin.unknown == #skin.list, "Skinning: no levels known: everything shown")
  local mine = Cr.Harvest("Fit", 186, false, true)
  ok(mine.rank == 0 and Count(mine, function(e) return e.known ~= nil end) == 0 and #mine.list == mine.unknown, "Mining not yours (rank 0): only the ones with no level")
  Cr.Mine = function() return { [182] = true, [186] = true } end
  GetProfessions = function() return nil end
  local keepNSL = GetNumSkillLines GetNumSkillLines = nil
  local blind = Cr.Harvest("Fit", 186, false, true)
  ok(blind.rank == nil and #blind.list == #Cr.Harvest("Fit", 186, false, false).list, "your skill unreadable: nothing hidden")
  GetNumSkillLines = keepNSL
  GetProfessions = function() return 1, nil, nil, nil, nil, nil end
  Cr.Mine = function() return { [182] = true } end
  -- the view: no Known column; Known only on; the status one short line
  mp:ShowSub("craft")
  local cf = mp.subs.craft
  I.S.craftKnownOnly, I.S.mineBank = true, false
  Mk.craftProf, Mk.craftMode = 182, "harvest" mp:Refresh()
  for _, b in ipairs(cf.head.harvest) do ok(b.key ~= "known", "Harvest: no Known column (" .. b.key .. ")") end
  ok(cf.rows[1].harvest.known == nil and cf.status._text:find("above your skill hidden", 1, true) and not cf.status._text:find("Sell at", 1, true),
    "Known only: said in a short status line", cf.status._text)
  -- 2. the status line fits one line at the game's width (FRIZQT 11 px, drawn 1.3x)
  local ADV = dofile("tests/investments/friz11.lua")
  local function Wd(t, size) local w = 0 for i = 1, #t do w = w + (ADV[t:byte(i)] or 7) end return w * 1.3 * (size or 11) / 11 end
  ok(Wd(cf.status._text) <= 760, "Harvest's status: one line (" .. math.floor(Wd(cf.status._text)) .. " px of 760)")
  -- (and Crafts' status, its longest: a long profession name, both notes)
  local craftLine = Mk.CraftStatus("Engineering", 999, false, 999, 0.15, "23 h ago", 999, 999)
  ok(Wd(craftLine) <= 760 and craftLine:find("not loaded", 1, true) and craftLine:find("skipped", 1, true),
    "Crafts' status: one line at its longest (" .. math.floor(Wd(craftLine)) .. " px of 760)")
  I.S.craftKnownOnly = false
  -- 3. titles that fit, at the game's width: every list
  local keepW = Frame.GetStringWidth
  Frame.GetStringWidth = function(self) return Wd(tostring(rawget(self, "_text") or ""), rawget(self, "_size") or 12) end
  for _, list in ipairs({ "results", "mine", "craft", "harvest" }) do
    local f = CreateFrame("Frame", nil, UIParent)
    Mk.FitCols(list, f)
    local cols = Mk.COLS[list]
    local good, why, prev = true, "", nil
    for _, c in ipairs(cols) do
      if not c.item then
        local lines = { c.label }
        if c.two then lines = {} for part in c.label:gmatch("%S+") do lines[#lines + 1] = part end end
        local need = 0
        if c.two then
          -- (the two lines: split where Halves splits; each word at most as wide as the line)
          for _, part in ipairs(lines) do need = math.max(need, Wd(part, Mk.HEAD_FONT)) end
        else need = Wd(c.label, Mk.HEAD_FONT) end
        if need + Mk.ARROW_W + Mk.HEAD_PAD > c.w + 0.5 then good, why = false, c.key .. ": title" end
        local sample = (Mk.SAMPLE_LIST[list] or {})[c.key] or Mk.SAMPLE[c.key] or "9999"
        if Wd(sample) + Mk.CELL_PAD > c.w + 0.5 then good, why = false, c.key .. ": value" end
      end
      if prev and c.x < prev.x + prev.w then good, why = false, c.key .. ": overlap" end
      prev = c
    end
    local last = cols[#cols]
    if last.x + last.w > Mk.ROW_W[list] then good, why = false, "past the row" end
    ok(good and cols[1].w >= 100, list .. ": every title and its widest value fit, nothing overlaps (1.3x widths)", why .. " name " .. cols[1].w)
  end
  -- a new list: laid out again from its own widest values; the header keeps its height
  local h0, n0 = cf.head.craftStrip.h, Mk.COLS.craft[1].w
  ok(Mk.Relayout(cf, cf.head.craftStrip, "craft", "craft", { cost = "1c", sell = "1c", each = "1c", total = "1c", margin = "1%", listed = "1", known = "*", can = "1" })
    and cf.head.craftStrip.h == h0 and Mk.COLS.craft[1].w > n0, "a list of small numbers: the columns narrower, the name wider, the header as high", Mk.COLS.craft[1].w)
  for _, list in ipairs({ "results", "mine", "craft", "harvest" }) do Mk.FitCols(list, CreateFrame("Frame", nil, UIParent)) end
  Frame.GetStringWidth = keepW
  -- 4. one lit header; hovering another doesn't light it
  mp:ShowSub("results")
  local rf = mp.subs.results
  W.Click(rf.head.buttons[3])
  local lit, arrows = 0, 0
  for _, b in ipairs(rf.head.buttons) do if b.vh.selected then lit = lit + 1 end if b.arrow:IsShown() then arrows = arrows + 1 end end
  ok(lit == 1 and arrows == 1 and rf.head.buttons[3].vh.selected, "one header lit, one arrow")
  local other = rf.head.buttons[4]
  local before = table.concat(other.text._tc, ",")
  W.Run(other, "OnEnter")
  ok(table.concat(other.text._tc, ",") == before and before ~= table.concat(rf.head.buttons[3].text._tc, ","), "hovered: its title keeps the unsorted colour", before)
  W.Run(other, "OnLeave")
  -- 5. colours: profit green, a loss red, Best plain, no gold on values
  mp:ShowSub("mine")
  local mf = mp.subs.mine
  I.char.bags = { [2589] = 5 }
  mp:Refresh()
  ok(table.concat(mf.rows[1].best._tc, ",") == "1,1,1", "My items' Best: plain (green is for profit)")
  -- 6. a sort that needs the game's data: all of the list's items asked for, sorted again when in
  local loads = {}
  local keepItem = Item
  Item = { CreateFromItemID = function(_, id) return { ContinueOnItemLoad = function(_, fn) loads[#loads + 1] = { id = id, fn = fn } end } end }
  V.loading, V.loadingCount = {}, 0   -- (the items earlier tests left unanswered)
  W.uncached[2589] = true W.uncached[765] = true
  mp:ShowSub("results")
  rf.cache = nil   -- (1.2.0: a scan's rows are read once; a cold game cache, as at login, read afresh)
  I.S.sortResults = "name:asc" rf.dirty = true mp:Refresh()
  local lastIds = {} for _, e in ipairs(rf.list) do lastIds[#lastIds + 1] = e.name or "?" end
  ok(#loads == 2 and rf.loadNote:IsShown() and rf.loadNote._text:find("2 items", 1, true) and rf.list[#rf.list].name == nil and rf.list[#rf.list - 1].name == nil,
    "sorted by name with 2 names missing: both asked for (not only the page's), sorted last meanwhile, said", table.concat(lastIds, ",") .. " loads " .. #loads .. " note " .. tostring(rf.loadNote and rf.loadNote._text) .. " lc " .. V.loadingCount)
  W.uncached[2589] = nil W.uncached[765] = nil
  for _, l in ipairs(loads) do l.fn() end
  local names = {} for _, e in ipairs(rf.list) do names[#names + 1] = e.name or "?" end
  local sorted = true
  for k = 2, #rf.list do if not rf.list[k - 1].name or not rf.list[k].name or rf.list[k - 1].name:lower() > rf.list[k].name:lower() then sorted = false end end
  ok(sorted and not rf.loadNote:IsShown(), "all in: sorted again, A-Z through the whole list", table.concat(names, ","))
  Item = keepItem
  -- 7. tooltips: 3 seconds, on every filter and every header
  local GT = GameTooltip
  local keep = { GT.SetOwner, GT.AddLine, GT.Show, GT.Hide, GT.GetOwner }
  local tip = {}
  GT.SetOwner = function(_, o) tip.owner, tip.lines = o, {} end
  GT.AddLine = function(_, t) tip.lines[#tip.lines + 1] = t end
  GT.Show = function() tip.shown = true end
  GT.Hide = function() tip.shown = false end
  GT.GetOwner = function() return tip.owner end
  local keepOver = Frame.IsMouseOver
  Frame.IsMouseOver = function() return true end
  local function Hover(w)
    tip.shown, tip.lines = false, {}
    W.Run(w, "OnEnter")
    local early = tip.shown
    W.RunTimers()
    return not early and tip.shown and tip.owner == w, tip.lines
  end
  local good, lines = Hover(rf.head.buttons[2])
  ok(good and lines[2] == Mk.HeadTip("results", "min") and lines[2]:find("lowest buyout per unit", 1, true) and not lines[2]:find("sort", 1, true),
    "a header: after the delay, what the column means (v0.4.2.8: no \"click to sort\")", lines[2])
  ok(V.TIP_DELAY == 1, "the delay: 1 second (v0.4.2.9)")
  W.Run(rf.head.buttons[2], "OnEnter") W.Run(rf.head.buttons[2], "OnLeave") tip.shown = false W.RunTimers()
  ok(not tip.shown, "moved off before 3 s: nothing")
  W.Run(rf.head.buttons[2], "OnEnter") W.Run(rf.head.buttons[2], "OnMouseDown") W.RunTimers()
  ok(not tip.shown, "clicked before 3 s: nothing")
  local function Has(w, key) local t = Mk.TIPS[key] return w.tip and w.tip.title == t[1] and w.tip.text == t[2] end
  local all = true
  for _, list in ipairs({ { rf, "results" }, { mf, "mine" } }) do for _, b in ipairs(list[1].head.buttons) do if not b.tip then all = false end end end
  for _, b in ipairs(cf.head.craft) do if not b.tip then all = false end end
  for _, b in ipairs(cf.head.harvest) do if not b.tip then all = false end end
  ok(all, "every header of every list: a tooltip")
  mp:ShowSub("top") mp:ShowSub("history")
  local top, hf = mp.subs.top, mp.subs.history
  ok(Has(top.kinds[1], "all") and Has(top.kinds[2], "crafted") and Has(top.kinds[3], "harvested") and Has(top.prof, "topProf") and Has(top.level, "topLevel"), "Top 10's filters")
  ok(Has(rf.search, "search") and Has(mf.scope.boxes[1], "bags") and Has(mf.scope.boxes[2], "bank") and Has(hf.range.boxes[1], "day") and Has(hf.range.boxes[2], "week"), "Scan results, My items, History")
  ok(Has(cf.drop, "craftProf") and Has(cf.modeCrafts, "crafts") and Has(cf.modeHarvest, "harvest") and Has(cf.filter, "filter")
    and Has(cf.owned.boxes[1], "market") and Has(cf.owned.boxes[2], "free") and cf.owned.boxes[3] == nil
    and Has(cf.countDrop, "craftCount") and Has(cf.invest, "invest"), "Craft's filters (v0.4.2.8: the Count dropdown, the Invest Amount)")
  mp:ShowSub("craft")
  Mk.craftMode = "crafts"
  local _, kl = Hover(cf.known)
  Mk.craftMode = "harvest"
  local _, kh = Hover(cf.known)
  ok(kl[2] == Mk.TIPS.knownCrafts[2] and kh[2] == Mk.TIPS.knownHarvest[2], "Known only: its text for Crafts, its own for Harvest", kh[2])
  -- 8. houses: Alliance | Horde | Neutral, Alliance by default, the pick kept
  Mk.house = nil
  local keepH = I.S.marketHouse
  I.S.marketHouse = nil
  ok(Mk.House() == "Alliance" and I.SETTINGS.marketHouse == "Alliance", "no house picked yet: Alliance")
  ok(Has(mp.houseButtons[1], "Alliance") and Has(mp.houseButtons[2], "Horde") and Has(mp.houseButtons[3], "Neutral")
    and Mk.TIPS.Neutral[2]:find("Booty Bay, Gadgetzan and Everlook", 1, true) and Mk.TIPS.Neutral[2]:find("15%", 1, true) and Sc.Cut("Neutral") == 0.15, "the houses' tooltips; Neutral's: the goblin AH, its 15% cut (as Scan's)")
  local g2, nl = Hover(mp.houseButtons[3])
  ok(g2 and nl[1] == "Neutral", "Neutral: its tooltip after 3 s")
  W.Click(mp.houseButtons[2])
  ok(I.S.marketHouse == "Horde" and Mk.House() == "Horde", "a pick kept in the settings (SavedVariables: kept after /reload)")
  I.S.marketHouse = keepH
  Frame.IsMouseOver = keepOver
  GT.SetOwner, GT.AddLine, GT.Show, GT.Hide, GT.GetOwner = keep[1], keep[2], keep[3], keep[4], keep[5]
  GetProfessions, GetProfessionInfo, Cr.Mine = keepGP, keepGPI, keepMine
  for _, k in ipairs({ "sortResults", "sortMine", "sortCraft", "sortHarvest" }) do I.S[k] = nil end
  Mk.house, Mk.craftProf, Mk.craftMode = nil, nil, nil
  mp:Refresh()
  ok(#W.sizeErrors == errs0, "no handler error")
end)()

print("== 37. v0.4.2.8: tooltips say what a column means (2 s), Harvest without Margin, Top 10's titles and Trending, the quick point, Invest Amount, Craft's Count, the I key")
;(function()
  local St, Mk, Sc, Cr, V = ns.Style, I.Market, I.Scan, I.Craft, I.Views
  local Frame = getmetatable(UIParent)
  local errs0 = #W.sizeErrors
  WorldMapFrame:Show()
  Slash("invest", "market")
  local mp = T.Views().invest.page.pages.market
  -- 1. every header: what its column means (no "click to sort"); the cut as the house's; the Reagents mode named
  local all, none = true, {}
  for _, list in ipairs({ "results", "mine", "craft", "harvest" }) do
    for _, c in ipairs(Mk.COLS[list]) do
      local t = Mk.HeadTip(list, c.key)
      if t == "" or t:lower():find("sort", 1, true) then all = false none[#none + 1] = list .. "." .. c.key end
    end
  end
  ok(all, "every column of every list: a tooltip saying what it means, none about sorting", table.concat(none, ","))
  Mk.house = "Neutral"
  ok(Mk.HeadTip("mine", "ah"):find("15%", 1, true) and Mk.HeadTip("craft", "each"):find("15%", 1, true) and Mk.HeadTip("harvest", "each"):find("15%", 1, true), "Neutral: its 15% cut in the tooltips")
  Mk.house = "Alliance"
  ok(Mk.HeadTip("craft", "total"):find("5%", 1, true) and Mk.HeadTip("craft", "total"):find("gold spent", 1, true), "Alliance: 5%; Total: less the gold spent with an Invest Amount")
  local keepOwned = I.S.craftOwned
  I.S.craftOwned = "free" local tf = Mk.HeadTip("craft", "cost")
  I.S.craftOwned = "market" local tm = Mk.HeadTip("craft", "cost")
  ok(tf:find("Owned:", 1, true) and not tf:find("vendor", 1, true) and tm:find("Market:", 1, true), "Cost to Make: the Reagents mode in use, named (1.0.1: Owned)")
  I.S.craftOwned = keepOwned
  ok(V.TIP_DELAY == 1, "every tooltip after 1 s (v0.4.2.9)")
  -- 2. Harvest: no Margin; a saved Margin sort: the default
  local hasMargin = false for _, c in ipairs(Mk.COLS.harvest) do if c.key == "margin" then hasMargin = true end end
  I.S.sortHarvest = "margin:desc"
  ok(not hasMargin and Mk.SortTag("harvest") == "sell:desc", "Harvest: no Margin column; a saved Margin sort falls back to Sell at", Mk.SortTag("harvest"))
  I.S.sortHarvest = nil
  -- 3. a quick scan never replaces the hour's full point
  local qm = Sc.Market("Quick8", true)
  local qt = math.floor(W.now / 60) - qm.base
  local slot = math.floor((qt - 60) / Sc.SLOT) * Sc.SLOT
  Sc.AddPoint(qm, 1, slot + 1, 100, 10, 2) Sc.AddPoint(qm, 1, slot + 20, 90, 4, "q")
  local qp = Sc.Points("Quick8", 1)
  ok(#qp == 1 and not qp[1].quick and qp[1].units == 10, "a quick scan in a full scan's hour: the full point kept")
  Sc.AddPoint(qm, 2, slot + 1, 100, 10, "q") Sc.AddPoint(qm, 2, slot + 20, 95, 12, 3)
  ok(#Sc.Points("Quick8", 2) == 1 and not Sc.Points("Quick8", 2)[1].quick, "a full scan after a quick one in the hour: the full point wins")
  -- 4. Trending: units gone between full scans (12 h apart at most), per day; gold the same
  local tmk = Sc.Market("Trend8", true)
  local base = math.floor(W.now / 60) - tmk.base
  local h = 60
  tmk.hist[501] = ("%d:100:100:5;%d:100:70:4;%d:100:90:5;%d:200:60:3"):format(base - 4 * h, base - 3 * h, base - 2 * h, base - h)   -- (30 + 30 gone in 3 h)
  tmk.hist[502] = ("%d:50:20:2;%d:50:10:1"):format(base - 30 * h, base - 15 * h)   -- (15 h apart: not counted)
  tmk.hist[503] = ("%d:10:40:2;%d:10:5:q;%d:10:30:2"):format(base - 3 * h, base - 2 * h, base - h)   -- (the quick point ignored: 10 gone in 2 h)
  tmk.cur[501] = ("%d,%d,%d,%d"):format(250, 60, 3, base - h)
  local u, g = Sc.SoldNow("Trend8")
  local by = {} for _, e in ipairs(u) do by[e.id] = e end
  ok(by[501] and math.abs(by[501].perDay - 480) < 0.01 and math.abs(by[501].goldDay - (30 * 100 + 30 * 100) * 8) < 0.01 and by[501].now == 250,
    "100 > 70 > 90 > 60 units in 3 h: 60 gone, 480 a day; gold: each drop x the price before it; Price: the last full scan's", by[501] and by[501].perDay)
  ok(not by[502] and by[503] and math.abs(by[503].perDay - 120) < 0.01, "pairs over 12 h apart skipped; quick points ignored", by[503] and by[503].perDay)
  ok(u[1].id == 501 and g[1].id == 501 and #u == 2, "ranked by units a day, and by gold a day")
  -- 5. Top 10: Price movers | Trending (kept), titles over the columns with what they mean; the Level clear of the toggle
  mp:ShowSub("top")
  local top = mp.subs.top
  I.S.topView = nil mp:Refresh()
  ok(top.views and #top.views == 2 and top.views[1].text._text == "Price movers" and top.views[2].text._text == "Trending" and Mk.TopView() == "movers"
    and top.cols[1].title._text == "Rising" and top.cols[2].title._text == "Falling" and top.cols[1].heads[2].text._text == "Change" and top.cols[1].heads[3].text._text == "Price"
    and top.cols[1].heads[4].text._text == "Last 8", "Price movers by default: Rising / Falling, Change, Price, Last 8")
  ok(top.cols[1].heads[2].tip.text:find("median", 1, true) and top.cols[1].titleHit.tip.text:find("went up", 1, true) and not top.cols[1].heads[2]._scripts.OnClick,
    "the titles' tooltips say what they mean; no sorting")
  Mk.house = "Trend8"
  W.Click(top.views[2])
  ok(I.S.topView == "sold" and top.cols[1].title._text == "Most units sold" and top.cols[2].title._text == "Most gold sold" and top.cols[1].heads[2].text._text == "Sold/day"
    and top.cols[2].heads[2].text._text == "Gold/day" and top.cols[1].heads[4].text._text == "Listed" and top.cols[1].heads[2].tip.text:find("12 h", 1, true),
    "Trending: Most units sold / Most gold sold, Sold/day / Gold/day, Price, Listed (saved)")
  ok(I.SETTINGS.topView == "movers", "the view kept in the settings (Price movers at first)")
  local lp, vp = top.level._points[1], top.views[1]._points[1]
  ok(lp[3] == -52 and top.levelTitle._points[1][3] == -35 and lp[2] == top.levelTitle._points[1][2] and vp[5] == -6 and top.views[2]._points[1][1] == "TOPRIGHT",
    "the toggle on the top row (to y -26), the Level title under it (y -35), its dropdown under the title (y -52): no overlap")
  W.Click(top.views[1])
  ok(I.S.topView == "movers", "back to Price movers")
  -- 6. Invest Amount: parsing; how many it makes; Total; live as you type; empty: as before
  local P = Mk.ParseMoney
  ok(P("50g") == 500000 and P("1g 20s") == 12000 and P("1.5") == 15000 and P("75s") == 7500 and P("33c") == 33 and P("2") == 20000 and P("") == nil and P("abc") == nil and P("0") == nil,
    "Invest Amount: 50g, 1g 20s, 1.5 (gold), 75s, 33c; junk and 0: none")
  local Sp = Sc.SellPrice
  Sc.SellPrice = function(id) return id == 1 and 5 or nil end
  local e = { parts = { { id = 1, n = 2, unit = 100 }, { id = 2, n = 1, unit = 300 } } }   -- (500 a craft at market)
  ok(Mk.Afford(e, 2600, {}, "market") == 5 and select(2, Mk.Afford(e, 2600, {}, "market")) == 2500, "Market: amount / Cost to Make (2600 / 500: 5, costing 2500)")
  ok(Mk.Afford(e, 2600, { [1] = 4, [2] = 1 }, "market") == 5, "Market: yours priced too (as Cost to Make)")
  local nf, cf2 = Mk.Afford(e, 1000, { [1] = 4, [2] = 1 }, "free")
  ok(nf == 3 and cf2 == 2 * 100 + 2 * 300, "Owned free: yours first (free), then bought: 3 for 800 (a 4th: 1300)", nf .. " " .. cf2)
  ok(Mk.Afford(e, 499, {}, "market") == 0 and Mk.Afford({ parts = {} }, 1, {}, "market") == Mk.INVEST_MAX, "less than one craft: 0; no reagents: capped")
  Sc.SellPrice = Sp
  -- in the view: 12 crafts of 2 reagents at house Inv8
  local keepTS, keepBags, keepBank = C_TradeSkillUI, I.char.bags, I.char.bank
  local SCH = {}
  for k = 1, 12 do SCH[970000 + k] = { 971000 + k, { { 972001, k % 3 + 1 }, { 972002, 1 } } } W.items[971000 + k] = { "Invest Test " .. k, 132912 } end
  W.items[972001] = { "Reagent A", 132912 } W.items[972002] = { "Reagent B", 132912 }
  C_TradeSkillUI = { GetRecipeSchematic = function(id)
    local r = SCH[id] if not r then return nil end
    local slots = {} for _, g in ipairs(r[2]) do slots[#slots + 1] = { quantityRequired = g[2], reagents = { { itemID = g[1] } } } end
    return { recipeID = id, outputItemID = r[1], quantityMin = 1, quantityMax = 1, reagentSlotSchematics = slots }
  end }
  local im = Sc.Market("Inv8", true)
  local itm = math.floor(W.now / 60) - im.base
  im.scans = { { t = itm, kind = "full", n = 100, items = 14 } }
  im.cur[972001] = ("%d,%d,%d,%d"):format(150, 50, 5, itm) im.cur[972002] = ("%d,%d,%d,%d"):format(400, 50, 5, itm)
  for k = 1, 12 do im.cur[971000 + k] = ("%d,%d,%d,%d"):format(1000 + k * 300, 10, 2, itm) end
  I.db.account.recipes[998] = { name = "Invest Test", ids = (function() local t = {} for k = 1, 12 do t[k] = 970000 + k end return table.concat(t, ",") end)(), t = W.now }
  I.char.bags, I.char.bank = { [972001] = 7, [972002] = 2 }, { [972002] = 5 }
  Mk.house, Mk.craftProf, Mk.craftMode = "Inv8", 998, "crafts"
  I.S.craftCount = "bags"
  mp:ShowSub("craft")
  local cf = mp.subs.craft
  for _ = 1, 400 do if not Cr.Running() then break end Cr.Tick() end
  mp:Refresh()
  ok(cf.invest and cf.invest:IsShown() and cf.investTitle._text == "Invest Amount:" and cf.investHint:IsShown() and cf.invest._points[1][2] == cf.countDrop and cf.invest._points[1][4] > 12 + (cf.investTitle:GetStringWidth() or 0)
    and cf.investTitle._points[1][2] == cf.countDrop, "one Invest Amount box above the table, after the Count dropdown, its hint while empty")
  local r1e = cf.list[1]
  local before = r1e and cf.rows[1].can._text
  cf.invest:SetText("50g") W.Run(cf.invest, "OnTextChanged")
  ok(Mk.investAmount == nil, "typing: not yet (a moment after the last key)")
  W.RunTimers()
  local e1 = cf.list[1]
  local n1 = e1 and Mk.Afford(e1, 500000, Cr.Have(false), I.S.craftOwned or "market")
  local cut = Sc.Cut("KnownTest")
  local want = e1 and n1 > 0 and (n1 * e1.sell * e1.qty * (1 - cut) - select(3, Mk.Afford(e1, 500000, Cr.Have(false), I.S.craftOwned or "market"))) or nil
  ok(Mk.investAmount == 500000 and e1 and cf.rows[1].can._text == tostring(n1) and (want == nil and cf.rows[1].total._text == "-" or cf.rows[1].total._text:find(Sc.Money(math.abs(want)), 1, true)),
    "50g typed: every row's Can make what it buys, Total the net return", e1 and (cf.rows[1].can._text .. " " .. cf.rows[1].total._text))
  local allRows = true
  for i, r in ipairs(cf.rows) do local x = cf.list[cf.offset + i] if x and r:IsShown() and r.can._text ~= tostring((Mk.Shown(x))) then allRows = false end end
  ok(allRows, "the amount on every row shown")
  -- (owner, 5:57 PM) the amount changes Can make and Total only: Cost to Make, Sell at, Profit/item, Margin as without it, in every Reagents mode
  local function Snap()
    local t = {}
    for i, r in ipairs(cf.rows) do local x = cf.list[cf.offset + i] if x and r:IsShown() then
      t[#t + 1] = table.concat({ x.out, r.cost._text, r.sell._text, r.each._text, r.margin._text, tostring(x.cost), tostring(x.each), tostring(x.margin), tostring(x.can), tostring(x.total) }, "|")
    end end
    table.sort(t) return table.concat(t, "\n")
  end
  local keepMode = I.S.craftOwned
  local same, n0 = true, 0
  for _, mode in ipairs({ "market", "free" }) do
    I.S.craftOwned = mode
    for _ = 1, 400 do mp:Refresh() if not Cr.Running() then break end Cr.Tick() end
    cf.invest:SetText("") W.Run(cf.invest, "OnTextChanged") W.RunTimers()
    local without = Snap()
    cf.invest:SetText("50g") W.Run(cf.invest, "OnTextChanged") W.RunTimers()
    local with = Snap()
    n0 = n0 + #without
    if with ~= without or without == "" then same = false end
  end
  I.S.craftOwned = keepMode mp:Refresh()
  ok(same and n0 > 0, "Profit/item, Margin, Cost to Make (and Sell at) identical with and without an amount: Market, Owned")
  I.S.sortCraft = "can:desc" mp:Refresh()
  local sorted = true for i = 2, #cf.list do if (Mk.Shown(cf.list[i - 1])) < (Mk.Shown(cf.list[i])) then sorted = false end end
  ok(sorted, "Can make sorts by what it shows (with the amount)")
  I.S.sortCraft = nil
  cf.invest:SetText("") W.Run(cf.invest, "OnTextChanged") W.RunTimers()
  ok(Mk.investAmount == nil and cf.list[1] and cf.rows[1].can._text == tostring(cf.list[1].can) and cf.investHint:IsShown(), "emptied: as before (your reagents)")
  ok(I.SETTINGS.craftInvest == nil and I.S.craftInvest == nil and I.S.investAmount == nil, "the amount isn't saved (this session only)")
  -- 7. Craft's Count: None | Bags only | Bags + bank, its own (first from My items'); None: nothing counted
  local keepMB = I.S.mineBank
  local keepOwned7 = I.S.craftOwned
  I.S.craftOwned = "free" mp:Refresh()   -- (v0.4.2.9: Count is live with the Owned modes)
  I.S.craftCount, I.S.mineBank = nil, true
  ok(Mk.CraftCount() == "bank" and I.S.craftCount == "bank", "first: from My items' (Bags + bank)")
  I.S.craftCount, I.S.mineBank = nil, false
  ok(Mk.CraftCount() == "bags", "first: from My items' (Bags only)")
  W.Click(cf.countDrop)
  local labels = {} for _, it in ipairs(cf.countDrop.menu.items) do if it:IsShown() then labels[#labels + 1] = it.text._text end end
  ok(table.concat(labels, "|") == "None|> Bags only|Bags + bank", "the dropdown: None | Bags only | Bags + bank (the current marked)", table.concat(labels, "|"))
  W.Click(cf.countDrop.menu.items[1])
  for _ = 1, 400 do if not Cr.Running() then break end Cr.Tick() end
  mp:Refresh()
  local zero = true for _, x in ipairs(cf.list) do if x.can ~= 0 or x.total ~= nil then zero = false end end
  ok(I.S.craftCount == "none" and I.S.mineBank == false and zero and cf.countDrop.text._text == "Count: None", "None: Can make 0, Total - everywhere; My items' setting untouched")
  cf.invest:SetText("10g") W.Run(cf.invest, "OnTextChanged") W.RunTimers()
  local e2 = cf.list[1]
  ok(e2 and (Mk.Shown(e2)) == e2.can and cf.invest.off, "Owned (1.0.1): an amount typed is ignored (the box greyed): what yours make", e2 and ((Mk.Shown(e2)) .. " " .. e2.can))
  cf.invest:SetText("") W.Run(cf.invest, "OnTextChanged") W.RunTimers()
  local hv = Cr.Harvest("Fit", 182, "none", false)
  local hz = true for _, x in ipairs(hv.list) do if x.have ~= 0 or x.total ~= nil then hz = false end end
  ok(hz, "Harvest under None: Have 0, Total -")
  I.S.craftCount, I.S.mineBank = "bags", keepMB
  I.S.craftOwned = keepOwned7
  -- 8. the I key: Key Bindings > Valhalla > Valhalla: Investments; I by default only if free
  C_TradeSkillUI, I.char.bags, I.char.bank = keepTS, keepBags, keepBank
  local xml = io.open("Valhalla/Bindings.xml"):read("*a")
  ok(xml:find('<Binding name="VALHALLA_INVEST" category="Valhalla">Valhalla_ToggleInvest()</Binding>', 1, true) and BINDING_NAME_VALHALLA_INVEST == "Valhalla: Investments",
    "the binding in Valhalla's section: \"Valhalla: Investments\"")
  local binds, saved = {}, nil
  local kb = { GetBindingKey, GetBindingAction, SetBinding, SaveBindings, GetCurrentBindingSet }
  GetBindingKey = function(a) for k, v in pairs(binds) do if v == a then return k end end end
  GetBindingAction = function(k) return binds[k] or "" end
  SetBinding = function(k, a) binds[k] = a return true end
  SaveBindings = function(set) saved = set end
  GetCurrentBindingSet = function() return 2 end
  ns.printed = {}
  I.db.account.investKey = nil
  ok(I.ClaimKey() == "set" and binds.I == "VALHALLA_INVEST" and saved == 2 and Printed("I now opens Investments"), "I free: taken for Investments, saved, said")
  ok(I.ClaimKey() == nil, "once per account")
  binds, saved = { I = "TOGGLEGROUPFINDER" }, nil
  BINDING_NAME_TOGGLEGROUPFINDER = "Toggle Group Finder"
  I.db.account.investKey = nil ns.printed = {}
  ok(I.ClaimKey() == "taken" and binds.I == "TOGGLEGROUPFINDER" and saved == nil and Printed("Toggle Group Finder") and Printed("/valhalla invest key"),
    "I already used (the game's or yours): left alone, said once with how to change it")
  binds = { ["CTRL-I"] = "VALHALLA_INVEST" } I.db.account.investKey = nil
  ok(I.ClaimKey() == "kept" and binds.I == nil, "a key of your own for it: nothing changed")
  binds = { I = "TOGGLEGROUPFINDER" } ns.printed = {}
  Slash("invest", "key")
  ok(binds.I == "VALHALLA_INVEST" and saved == 2 and Printed("it did \"Toggle Group Finder\""), "/valhalla invest key: I for Investments (what it did, said)")
  local opened, closed = {}, 0
  local keepOpen, keepClose, keepCur, keepAtt = T.Open, T.Close, T.Current, T.Attached
  T.Open = function(k, p) opened[#opened + 1] = k return true end
  T.Close = function() closed = closed + 1 return true end
  T.Attached = function() return true end
  T.Current = function() return "map" end
  Valhalla_ToggleInvest()
  T.Current = function() return "invest" end
  Valhalla_ToggleInvest()
  ok(opened[1] == "invest" and #opened == 1 and closed == 1, "the key: opens Investments; pressed on it again: closes")
  T.Open, T.Close, T.Current, T.Attached = keepOpen, keepClose, keepCur, keepAtt
  GetBindingKey, GetBindingAction, SetBinding, SaveBindings, GetCurrentBindingSet = kb[1], kb[2], kb[3], kb[4], kb[5]
  Mk.house, Mk.craftProf, Mk.craftMode = nil, nil, nil
  mp:Refresh()
  ok(#W.sizeErrors == errs0, "no handler error")
end)()

print("== 38. v0.4.2.9: Invest Amount uses your reagents (Owned modes) first; Market greys Count (None); Invest greyed in Harvest; tooltips after 1 s")
;(function()
  local Mk, Sc, Cr = I.Market, I.Scan, I.Craft
  local errs0 = #W.sizeErrors
  WorldMapFrame:Show()
  Slash("invest", "market")
  local mp = T.Views().invest.page.pages.market
  local keep = { owned = I.S.craftOwned, count = I.S.craftCount, bags = I.char.bags, bank = I.char.bank, sp = Sc.SellPrice, house = Mk.house, mode = Mk.craftMode }
  -- 1. the worked example (v0429-plan.md): 2 A (1s; vendor 5c) + 1 B (3s; vendor 25c); sells 1g, 5% cut (95s); 10s to invest;
  --    bags A 4, B 1; bank A 6, B 4
  Mk.house, Mk.craftMode = "Alliance", "crafts"
  I.char.bags, I.char.bank = { [990001] = 4, [990002] = 1 }, { [990001] = 6, [990002] = 4 }
  Sc.SellPrice = function(id) return ({ [990001] = 5, [990002] = 25 })[id] or keep.sp(id) end
  local function E() return { id = 990100, out = 990101, qty = 1, sell = 10000, parts = { { id = 990001, n = 2, unit = 100 }, { id = 990002, n = 1, unit = 300 } } } end
  Mk.investAmount = 1000
  local bad = {}
  for _, cnt in ipairs({ "none", "bags", "bank" }) do
    I.S.craftOwned, I.S.craftCount = "market", cnt
    local n, total = Mk.Shown(E())
    if n ~= 2 or math.abs((total or 0) - 18000) > 0.01 then bad[#bad + 1] = cnt .. ": " .. tostring(n) .. " " .. tostring(total) end
  end
  ok(#bad == 0, "Market + 10s, every Count (None there): 2 bought, Total 1g 80s (sale after the cut x 2 - 10s)", table.concat(bad, "; "))
  ok(Mk.Afford(E(), 1000, { [990001] = 10, [990002] = 5 }, "market") == 2, "Market: yours never used")
  -- (1.0.1) Owned: the amount kept but not used: Can make and Total are what yours make (yours free)
  I.S.craftOwned, I.S.craftCount = "free", "bank"
  local eo = E() eo.can, eo.total = 5, 47500
  local on, ot = Mk.Shown(eo)
  ok(Mk.investAmount == 1000 and on == 5 and ot == 47500 and not Mk.InvestOn(), "Owned: the amount ignored (kept): Can make and Total from your reagents")
  ok(#Mk.OWNED == 2 and Mk.OWNED[1][2] == "Market" and Mk.OWNED[2][1] == "free" and Mk.OWNED[2][2] == "Owned", "Reagents: Market | Owned (no Owned: vendor)")
  Mk.investAmount = nil
  -- 2. the view: Market greys Count and makes it None; the Owned modes bring the choice back
  local SCH = {}
  local keepTS = C_TradeSkillUI
  for k = 1, 6 do SCH[980000 + k] = { 981000 + k, { { 990001, 2 }, { 990002, 1 } } } W.items[981000 + k] = { "Count Test " .. k, 132912 } end
  W.items[990001] = { "Reagent A", 132912 } W.items[990002] = { "Reagent B", 132912 }
  C_TradeSkillUI = { GetRecipeSchematic = function(id)
    local r = SCH[id] if not r then return nil end
    local slots = {} for _, g in ipairs(r[2]) do slots[#slots + 1] = { quantityRequired = g[2], reagents = { { itemID = g[1] } } } end
    return { recipeID = id, outputItemID = r[1], quantityMin = 1, quantityMax = 1, reagentSlotSchematics = slots }
  end }
  local im = Sc.Market("Inv9", true)
  local itm = math.floor(W.now / 60) - im.base
  im.scans = { { t = itm, kind = "full", n = 100, items = 8 } }
  im.cur[990001] = ("%d,%d,%d,%d"):format(100, 50, 5, itm) im.cur[990002] = ("%d,%d,%d,%d"):format(300, 50, 5, itm)
  for k = 1, 6 do im.cur[981000 + k] = ("%d,%d,%d,%d"):format(10000, 10, 2, itm) end
  I.db.account.recipes[997] = { name = "Count Test", ids = "980001,980002,980003,980004,980005,980006", t = W.now }
  Mk.house, Mk.craftProf, Mk.craftMode = "Inv9", 997, "crafts"
  local function Settle() for _ = 1, 400 do mp:Refresh() if not Cr.Running() then break end Cr.Tick() end mp:Refresh() end
  I.S.craftOwned, I.S.craftCount = "free", "bank"
  mp:ShowSub("craft")
  local cf = mp.subs.craft
  Settle()
  ok(not cf.countDrop.locked and cf.countDrop._alpha ~= 0.45 and cf.countDrop.text._text == "Count: Bags + bank" and cf.list[1] and cf.list[1].can == 5,
    "Owned free: Count live (Bags + bank: 5 from yours)", cf.list[1] and cf.list[1].can)
  W.Click(cf.owned.boxes[1])   -- (Reagents: Market)
  Settle()
  local zero = true for _, x in ipairs(cf.list) do if x.can ~= 0 then zero = false end end
  ok(I.S.craftOwned == "market" and cf.countDrop.locked and cf.countDrop._alpha == 0.45 and cf.countDrop.text._text == "Count: None" and zero and I.S.craftCount == "bank",
    "Market: Count greyed and None, Can make 0 (no amount); your choice kept")
  W.Click(cf.countDrop)
  ok(not cf.countDrop.menu:IsShown(), "greyed: its menu doesn't open")
  cf.invest:SetText("10s") W.Run(cf.invest, "OnTextChanged") W.RunTimers()
  ok(cf.list[1] and cf.rows[1].can._text == "2", "Market + 10s: only what the gold buys (2)", cf.rows[1].can._text)
  W.Click(cf.owned.boxes[2])   -- (Owned free)
  Settle()
  ok(I.S.craftOwned == "free" and not cf.countDrop.locked and cf.countDrop.text._text == "Count: Bags + bank" and cf.rows[1].can._text == "5"
    and cf.invest.off and cf.invest._alpha == 0.45 and cf.investTitle._alpha == 0.45 and cf.invest._mouse == false and cf.invest:GetText() == "10s",
    "Owned again: Bags + bank back; Invest greyed and off (10s kept, ignored): 5 from yours", cf.rows[1].can._text)
  local r1 = cf.list[1]
  ok(r1 and r1.cost == 0 and math.abs(r1.total - 5 * r1.net) < 0.01 and cf.rows[1].total._text == Sc.Money(r1.total), "Owned: yours free: Total = 5 x the sale after the cut", r1 and r1.total)
  W.Click(cf.countDrop) W.Click(cf.countDrop.menu.items[2])
  Settle()
  ok(I.S.craftCount == "bags" and cf.rows[1].can._text == "1", "Owned, Bags only: 1 (A 4, B 1)", cf.rows[1].can._text)
  W.Click(cf.owned.boxes[1]) Settle()
  ok(I.S.craftOwned == "market" and not cf.invest.off and cf.invest._alpha == 1 and cf.rows[1].can._text == "2", "Market again: the box on, 10s buys 2", cf.rows[1].can._text)
  -- 3. Harvest: the Invest Amount greyed and off; Count works (no reagents there)
  I.S.craftOwned = "market"
  Mk.craftProf, Mk.craftMode = 182, "harvest"
  mp:Refresh()
  ok(cf.invest._alpha == 0.45 and cf.investTitle._alpha == 0.45 and cf.invest.off and cf.invest._mouse == false and not cf.countDrop.locked,
    "Harvest: Invest Amount greyed and off; Count live (even with Market)")
  Mk.craftProf, Mk.craftMode = 997, "crafts"
  mp:Refresh()
  ok(cf.invest._alpha == 1 and not cf.invest.off and cf.invest:GetText() == "10s", "back to Crafts: the box on again, the amount kept")
  cf.invest:SetText("") W.Run(cf.invest, "OnTextChanged") W.RunTimers()
  ok(Mk.HeadTip("craft", "can"):find("Market", 1, true) and I.Views.TIP_DELAY == 1, "the tooltips: Market's Count named; 1 s")
  C_TradeSkillUI = keepTS
  I.S.craftOwned, I.S.craftCount, I.char.bags, I.char.bank, Sc.SellPrice, Mk.house, Mk.craftMode = keep.owned, keep.count, keep.bags, keep.bank, keep.sp, keep.house, keep.mode
  Mk.craftProf = nil
  mp:Refresh()
  ok(#W.sizeErrors == errs0, "no handler error")
end)()

print("== 39. 1.0.1: Reagents Market | Owned (Owned: vendor moved to Market), Craft without Known, Owned greys the Invest Amount")
;(function()
  local Mk = I.Market
  local errs0 = #W.sizeErrors
  -- 1. saved settings: Owned: vendor -> Market; a Known sort -> the default; Owned (free) and Market kept
  local keepOwned, keepSort = I.S.craftOwned, I.S.sortCraft
  for _, c in ipairs({ { "vendor", "market" }, { "free", "free" }, { "market", "market" }, { "bogus", "market" } }) do
    ValhallaInvestDB.settings.craftOwned = c[1]
    I.InitDB()
    ok(I.S.craftOwned == c[2], ("a saved Reagents %q: %q"):format(c[1], c[2]), I.S.craftOwned)
  end
  ValhallaInvestDB.settings.sortCraft = "known:desc" I.InitDB()
  ok(I.S.sortCraft == "each:desc", "a saved sort by Known: Profit/item (the default)", I.S.sortCraft)
  ValhallaInvestDB.settings.sortCraft = "can:asc" I.InitDB()
  ok(I.S.sortCraft == "can:asc", "another sort: kept")
  I.S.craftOwned, I.S.sortCraft = keepOwned, keepSort
  -- 2. Craft's columns: no Known (its tooltip gone too); the Known only box still there
  local keys = {} for _, c in ipairs(Mk.COLS.craft) do keys[#keys + 1] = c.key end
  ok(table.concat(keys, ",") == "name,cost,sell,each,margin,listed,can,total" and Mk.HEAD_TIPS.craft.known == nil, "Craft: no Known column", table.concat(keys, ","))
  I.S.sortCraft = "known:asc"
  ok(Mk.SortTag("craft") == "each:desc", "a Known sort set at run time: the default too", Mk.SortTag("craft"))
  I.S.sortCraft = keepSort
  WorldMapFrame:Show()
  Slash("invest", "market")
  local mp = T.Views().invest.page.pages.market
  mp:ShowSub("craft")
  local cf = mp.subs.craft
  ok(cf.known and cf.known:IsShown() and #cf.owned.boxes == 2 and cf.owned.boxes[2].label._text == "Owned", "the Known only box kept; Reagents: Market | Owned", cf.owned.boxes[2].label and cf.owned.boxes[2].label._text)
  ok(Mk.TIPS.free[1] == "Owned" and Mk.TIPS.free[2]:find("Invest Amount is off", 1, true) and Mk.TIPS.vendor == nil and Mk.TIPS.invest[2]:find("Greyed with Owned", 1, true)
    and Mk.TIPS.craftCount[2]:find("Owned brings", 1, true), "tooltips: Owned, the Invest Amount (Market only), Count")
  -- (1.0.1) a relayout that sends a title to two lines (or back) wraps it to match (was: two lines wide, one line drawn)
  local head = cf.head.craftStrip
  local cost
  for _, b in ipairs(head.buttons) do if b.key == "cost" then cost = b end end
  local keepH = head.h
  head.h, head.sig = Mk.HEAD_H2, nil
  local wide = {} for _, c in ipairs(Mk.COLS.craft) do wide[c.key] = "1" end
  wide.total = ("9"):rep(70)   -- (narrow values, one very wide column: the titles must give room)
  Mk.Relayout(cf, head, "craft", "craft", wide)
  local twoOk = true for _, b in ipairs(head.buttons) do if (b.text._wrap and true or false) ~= (b.col.two and true or false) then twoOk = false end end
  ok(twoOk and cost.col.two and cost.text._wrap == true, "a relayout to two lines: the title wraps (Cost to / Make)")
  head.h, head.sig = Mk.HEAD_H, nil
  Mk.Relayout(cf, head, "craft", "craft", wide)
  local one = true for _, b in ipairs(head.buttons) do if b.col.two or b.text._wrap then one = false end end
  ok(one, "a strip one line high: its titles stay on one line (the name gives way)")
  head.h, head.sig = keepH, nil
  mp:Refresh()
  ok(#W.sizeErrors == errs0, "no handler error")
end)()

print("== 40. 1.2.0: AH price on item tooltips, Scan results' caches, Top 10's bars and trainers, the History graph's hover")
;(function()
  local Mk, Sc, V, P, R = I.Market, I.Scan, I.Views, I.Tooltip, I.Trainer
  -- (1.2.4) a fixture, not the bundled data: these items as the bundled data had them before 1.2.4 (no level known),
  -- so what's tested (a level found later) doesn't hang on which levels Data/Forever/TopSkills.lua has read
  local m171, was = I.Craft.TopMap("craft")[171], {}
  for _, id in ipairs({ 2455, 3383 }) do was[id] = m171[id] m171[id] = false end
  local errs0 = #W.sizeErrors
  local GT = GameTooltip
  local keepGT = { GT.SetOwner, GT.AddLine, GT.Show, GT.Hide, GT.GetOwner, GT.SetHyperlink }
  local tip = { lines = {} }
  GT.SetOwner = function(self, o) tip.owner = o tip.lines = {} tip.shown = false end
  GT.GetOwner = function() return tip.owner end
  GT.AddLine = function(self, t, r, g, b) tip.lines[#tip.lines + 1] = { t, r, g, b } end
  GT.Show = function() tip.shown = true end
  GT.Hide = function() tip.shown = false tip.owner = nil end
  GT.SetHyperlink = function() end
  local function Has(pat) for _, l in ipairs(tip.lines) do if tostring(l[1]):find(pat) then return true end end return false end

  print("-- item tooltips")
  ok(I.SETTINGS.ahTooltip == true and I.S.ahTooltip == true, "setting 'AH price on item tooltips': on by default")
  Slash("tab", "settings")
  local sp = T.Views().settings.page
  ok(sp.ahTooltip and sp.ahTooltip.label._text == "AH price on item tooltips" and sp.ahTooltip.tick:IsShown(), "Settings > AH Market: the box, ticked")
  -- the hook: TooltipDataProcessor's post-call for items (once)
  local posted = {}
  TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) posted[#posted + 1] = { kind, fn } end }
  Enum.TooltipDataType = { Item = 0 }
  P.hooked = nil
  ok(P.Hook() == "processor" and #posted == 1 and posted[1][1] == 0 and posted[1][2] == P.OnItem, "hooked through TooltipDataProcessor (items)")
  P.Hook()
  ok(#posted == 1, "hooked once")
  local hm = Sc.Market("Tip", true)
  local tm = math.floor(W.now / 60) - hm.base
  hm.scans = { { t = tm, kind = "full", n = 3, items = 3 } }
  hm.cur[2589] = ("%d,%d,%d,%d"):format(1234, 40, 4, tm)
  hm.cur[2770] = ("%d,%d,%d,%d"):format(0, 5, 1, tm)
  Mk.house = "Tip"
  local keepBags, keepBank, keepSeen, keepAcc, keepAccSeen = I.char.bags, I.char.bank, I.char.bankSeen, I.db.account.bank, I.db.account.bankSeen
  I.char.bags, I.char.bank, I.char.bankSeen, I.db.account.bank, I.db.account.bankSeen = { [2589] = 5 }, {}, nil, {}, nil
  local l = P.Lines(2589)
  ok(#l == 2 and l[1] == "AH lowest: 12s 34c each (just now)" and l[2] == "You have 5: 61s 70c", "bags only (bank never seen): lowest each and 5 x lowest", table.concat(l, " | "))
  I.char.bankSeen, I.char.bank[2589] = W.now, 3
  l = P.Lines(2589)
  ok(#l == 2 and l[2] == "You have 8 (bags 5, bank 3): 98s 72c", "the bank seen: bags + bank, split shown", l[2])
  I.char.bags[2589], I.char.bank[2589] = 1, nil
  l = P.Lines(2589)
  ok(#l == 1 and l[1]:find("^AH lowest"), "holding 1: the price only")
  I.char.bags[2589] = 5
  ok(#P.Lines(2320) == 0, "an item not in your scans: no line")
  ok(#P.Lines(2770) == 0, "none listed in the last scan: no line")
  Mk.house = "NoSuchHouse"
  ok(#P.Lines(2589) == 0, "no scan data for the house: no line")
  Mk.house = "Tip"
  W.bind = { [2589] = 1 }
  ok(#P.Lines(2589) == 0, "bind on pickup: no line")
  W.bind = nil
  ITEM_SOULBOUND = "Soulbound"
  ok(#P.Lines(2589, { id = 2589, lines = { { leftText = "Linen Cloth" }, { leftText = "Soulbound" } } }) == 0, "a soulbound one (its tooltip says so): no line")
  W.Click(sp.ahTooltip)
  ok(I.S.ahTooltip == false and #P.Lines(2589) == 0, "setting off: no line")
  W.Click(sp.ahTooltip)
  ok(I.S.ahTooltip == true, "setting on again")
  -- the post-call on the game's tooltips
  tip.lines = {}
  P.OnItem(GT, { id = 2589 })
  ok(#tip.lines == 2 and tip.lines[1][1]:find("^AH lowest") and tip.lines[1][2] == P.R, "GameTooltip: two lines added (Valhalla's gold)")
  ItemRefTooltip = W.NewFrame("GameTooltip")
  local ref = {}
  ItemRefTooltip.AddLine = function(self, t) ref[#ref + 1] = t end
  P.OnItem(ItemRefTooltip, { id = 2589 })
  ok(#ref == 2, "ItemRefTooltip (a clicked link): the same two lines")
  local other, n = W.NewFrame("GameTooltip"), 0
  other.AddLine = function() n = n + 1 end
  P.OnItem(other, { id = 2589 })
  ok(n == 0, "other tooltips (compare, addons'): nothing")
  -- Valhalla's own rows: the post-call's lines, not AH Market's again
  V.ItemTooltip(UIParent, 2589, Mk.Lines)
  ok(not Has("^Valhalla AH"), "a Valhalla row's tooltip: AH Market's own lines not added (the tooltip already has them)")
  I.S.ahTooltip = false
  V.ItemTooltip(UIParent, 2589, Mk.Lines)
  ok(Has("^Valhalla AH %(Tip%): lowest 12s 34c each"), "setting off: a Valhalla row keeps AH Market's lines")
  I.S.ahTooltip = true
  I.char.bags, I.char.bank, I.char.bankSeen, I.db.account.bank, I.db.account.bankSeen = keepBags, keepBank, keepSeen, keepAcc, keepAccSeen

  print("-- Scan results: a scan read once, each column sorted once, the other way flipped, arrivals one by one")
  local pm = Sc.Market("Perf", true)
  local ptm = math.floor(W.now / 60) - pm.base
  pm.scans = { { t = ptm, kind = "full", n = 300, items = 120 } }
  for i = 1, 120 do
    local id = 810000 + i
    W.items[id] = { ("Perf Item %03d"):format(121 - i), 134400 }
    -- (ties on purpose: 6 prices; every 10th none listed)
    pm.cur[id] = ("%d,%d,%d,%d"):format(i % 10 == 0 and 0 or 100 * (i % 6 + 1), i % 7 + 1, i % 3 + 1, ptm)
  end
  Mk.house = "Perf"
  WorldMapFrame:Show()
  Slash("invest", "market")
  local mp = T.Views().invest.page.pages.market
  mp:ShowSub("results")
  local rf = mp.subs.results
  rf.cache = nil
  I.S.sortResults = "min:asc" rf.dirty = true mp:Refresh()
  local C = rf.cache
  local builds, sorts = rf.cacheBuilds, C.sorts
  ok(C and #C.all == 120 and #rf.list == 120 and C.orders.min, "the scan read once into the cache; Lowest sorted", #rf.list)
  -- the cached orders are exactly M.SortBy's, both ways, every column
  local same = true
  for _, c in ipairs(Mk.COLS.results) do
    for _, d in ipairs({ false, true }) do
      local want = {} for i, e in ipairs(C.all) do want[i] = e end
      Mk.SortBy(want, "results", c.key, d)
      local got = Mk.ResultsOrder(C, c.key, d)
      for i = 1, #want do if want[i] ~= got[i] then same = false end end
    end
  end
  ok(same, "every column, both directions: the cached / flipped order is the same as a full sort (ties by id, empty last)")
  sorts = C.sorts
  W.Click(rf.head.buttons[2])   -- (Lowest again: Highest)
  ok(I.S.sortResults == "min:desc" and C.sorts == sorts and rf.cacheBuilds == builds and rf.list == C.desc.min, "the other direction: flipped from the cached sort (no sort, no re-read)")
  local firstPage = rf.list[1]
  rf.Page(2)
  local e = rf.list[rf.per + 1]
  ok(rf.rows[1].cell.id == e.id and rf.list[1] == firstPage and rf.cacheBuilds == builds and C.sorts == sorts, "page 2: the next rows of the same sort (nothing read or sorted again)")
  ok(rf.list[1].min >= rf.list[2].min and rf.list[#rf.list].min == 0, "Highest first, none listed last")
  rf.search:SetText("perf item 00")
  ok(#rf.list == 9 and rf.cacheBuilds == builds and C.sorts == sorts and rf.offset == 0, "a search filters the cached order (page 1)", #rf.list)
  rf.search:SetText("")
  -- names arriving: only that item checked, the list redrawn at most once a second, at once when the last is in
  local loads = {}
  local keepItem = Item
  Item = { CreateFromItemID = function(_, id) return { ContinueOnItemLoad = function(_, fn) loads[#loads + 1] = { id = id, fn = fn } end } end }
  V.loading, V.loadingCount = {}, 0
  for i = 1, 5 do W.uncached[810000 + i] = true end
  rf.cache = nil
  I.S.sortResults = "name:asc" rf.dirty = true mp:Refresh()
  C = rf.cache
  local r0, ck0 = rf.redraws or 0, rf.checked or 0
  W.timers = {}
  ok(#loads == 5 and rf.wantN == 5 and rf.loadNote:IsShown(), "5 names missing: 5 asked for, said")
  W.uncached[810001] = nil loads[1].fn()
  ok(rf.checked == ck0 + 1 and rf.wantN == 4 and (rf.redraws or 0) == r0 and #W.timers == 1, "one in: only it checked, the redraw waits (one timer)")
  W.uncached[810002] = nil loads[2].fn()
  ok(rf.checked == ck0 + 2 and (rf.redraws or 0) == r0 and #W.timers == 1, "another: still the one timer (at most once a second)")
  W.RunTimers()
  ok(rf.redraws == r0 + 1 and C.byId[810001].name and C.byId[810002].name, "a second later: one redraw, the new names in the cache")
  for k = 3, 5 do W.uncached[810000 + k] = nil loads[k].fn() end
  ok(rf.redraws == r0 + 2 and rf.wantN == 0 and not rf.loadNote:IsShown(), "the last in: redrawn at once")
  local az = true
  for k = 2, #rf.list do if not rf.list[k - 1].name or rf.list[k - 1].name:lower() > rf.list[k].name:lower() then az = false end end
  ok(az and rf.cacheBuilds == builds + 1, "A-Z through the whole list (the scan read once more only for the cold start)")
  Item = keepItem
  W.timers = {}
  -- a new scan: read again
  pm.scans[#pm.scans + 1] = { t = ptm + 61, kind = "full", n = 1, items = 120 }
  mp:Refresh()
  ok(rf.cacheBuilds == builds + 2 and rf.cache ~= C, "a new scan: the cache read again")
  I.S.sortResults = nil

  print("-- Top 10: Listed bars, trainers' skill levels")
  local top = mp.subs.top
  local sp1 = top.cols[1].rows[1].spark
  local vals = { 1000, 900, 800, 700, 10, 20, 30, 40, 50, 60, 70, 80 }
  sp1.Set(vals)
  local shown = 0 for _, b in ipairs(sp1.bars) do if b:IsShown() then shown = shown + 1 end end
  ok(#sp1.bars == 8 and shown == 8 and sp1.max == 80 and sp1.bars[8]._h == 16 and sp1.bars[1]._h == 2, "the last 8 scans, scaled to those 8 (an older high doesn't flatten them)", sp1.max)
  sp1.Set({ 5, 10 })
  shown = 0 for _, b in ipairs(sp1.bars) do if b:IsShown() then shown = shown + 1 end end
  ok(shown == 2 and sp1.bars[8]._h == 16 and sp1.bars[7]._h == 8, "fewer than 8: only those, right-aligned")
  -- a trainer: its services through the window's filters
  W.items[3383] = { "Elixir of Wisdom", 134711 } W.items[2455] = { "Minor Mana Potion", 134851 } W.items[118] = { "Minor Healing Potion", 134829 }
  local services = {
    { "Alchemy", "header" },
    { "Journeyman Alchemy", "available", skill = { "Alchemy", 50 } },
    { "Minor Healing Potion", "used", skill = { "Alchemy", 1 }, link = "|Hitem:118|h[Minor Healing Potion]|h" },
    { "Elixir of Wisdom", "unavailable", skill = { "Alchemy", 90 }, link = "|Hitem:3383|h[Elixir of Wisdom]|h" },
    { "Minor Mana Potion", "available", skill = { "Alchemy", 25 } },   -- (no item link: by name)
  }
  local filters, setLog = { available = true, unavailable = false, used = false }, {}
  local function Visible() local t = {} for _, s in ipairs(services) do if s[2] == "header" or filters[s[2]] then t[#t + 1] = s end end return t end
  GetTrainerServiceTypeFilter = function(t) return filters[t] end
  SetTrainerServiceTypeFilter = function(t, v) setLog[#setLog + 1] = t .. "=" .. tostring(v) filters[t] = v and true or false end
  GetNumTrainerServices = function() return #Visible() end
  GetTrainerServiceInfo = function(i) local s = Visible()[i] if s then return s[1], s[2] end end
  GetTrainerServiceSkillReq = function(i) local s = Visible()[i] if s and s.skill then return s.skill[1], s.skill[2], true end end
  GetTrainerServiceItemLink = function(i) local s = Visible()[i] return s and s.link end
  W.tradeskill = true
  IsTradeskillTrainer = function() return W.tradeskill end
  ok(Mk.TopSkill("craft", 171, 2455) == false and Mk.TopSkill("craft", 171, 3383) ~= 90, "before: Minor Mana Potion and Elixir of Wisdom unknown")
  I.db.trainer = nil
  ns.printed = {}
  W.Fire("TRAINER_SHOW")
  local tr = I.db.trainer and I.db.trainer[171]
  ok(tr and tr.items[118] == 1 and tr.items[3383] == 90 and tr.items[2455] == 25 and tr.n == 3, "TRAINER_SHOW: every recipe's skill recorded, used and unavailable ones too (all filters on); the rank itself skipped")
  ok(filters.available == true and filters.unavailable == false and filters.used == false and table.concat(setLog, ",") == "unavailable=true,used=true,unavailable=false,used=false",
    "the player's filters put back as they were", table.concat(setLog, ","))
  ok(ValhallaInvestDB.trainer == I.db.trainer and Printed("recorded 3 skill levels from this Alchemy trainer"), "saved (ValhallaInvestDB.trainer, account-wide) and said once")
  ok(Mk.TopSkill("craft", 171, 2455) == 25 and Mk.TopSkill("craft", 171, 3383) == 90 and Mk.TopSkill("harvest", 182, 2447) == 1, "Top 10 takes a recorded level over the bundled one (crafts)")
  local list = { { id = 3383 }, { id = 2455 }, { id = 3387 } }
  local o1, n1, u1 = Mk.TopFilter(list, "craft", 171, "1")
  local o2 = Mk.TopFilter(list, "craft", 171, "151")
  ok(#o1 == 2 and o1[1].id == 3383 and n1 == 0 and not u1[3383] and #o2 == 0, "Elixir of Wisdom (90) and Minor Mana Potion (25) in 1-150, not in 151-225")
  ns.printed = {} setLog = {}
  W.Fire("TRAINER_SHOW")
  ok(#ns.printed == 0 and I.db.trainer[171].n == 3, "the same trainer again: nothing new, nothing said")
  W.tradeskill = false
  setLog = {}
  ok(R.Read() == nil and #setLog == 0, "a class trainer: not read, its filters untouched")
  W.tradeskill = true
  local keepInfo = GetTrainerServiceInfo
  GetTrainerServiceInfo = function() error("broken") end
  setLog = {}
  ok(R.Read() == nil and filters.unavailable == false and filters.used == false and #setLog == 4, "a read that fails: the filters still put back")
  GetTrainerServiceInfo = keepInfo

  print("-- History: hover a point")
  ok(Mk.Nearest({ { 4, 1 }, { 100, 1 }, { 300, 1 } }, 180) == 2 and Mk.Nearest({ { 4, 1 }, { 100, 1 }, { 300, 1 } }, 250) == 3 and Mk.Nearest({}, 5) == nil, "the nearest point by x")
  local hh = Sc.Market("Perf")
  local id = 810007
  hh.hist[id] = ("%d:%d:%d:%d;%d:%d:%d:%d;%d:%d:%d:q"):format(ptm - 600, 150, 30, 3, ptm - 300, 200, 25, 2, ptm - 60, 180, 22)
  Mk.historyID = id
  mp:ShowSub("history")
  local hf = mp.subs.history
  for _, style in ipairs({ "lines", "bars" }) do
    I.S.graphStyle = style
    hf.Refresh()
    ok(#hf.xy == 3 and hf.hover and hf.hover._mouse == true and not hf.dot:IsShown(), style .. ": one overlay over the plot, no dot yet")
    hf.plot.GetLeft = function() return 1000 end
    hf.plot.GetEffectiveScale = function() return 1 end
    GetCursorPosition = function() return 1000 + hf.xy[3][1] - 1, 50 end
    W.Run(hf.hover, "OnEnter")
    hf.hover._scripts.OnUpdate(hf.hover)
    local dp = hf.dot._points[1]
    ok(hf.hovered == 3 and hf.dot:IsShown() and dp[4] == hf.xy[3][1] and dp[5] == hf.xy[3][2] and tip.owner == hf.hover and tip.shown,
      style .. ": the nearest point (the last), a dot on it, the tooltip")
    ok(tip.lines[1][1] == "1s 80c" and Has("22 units listed") and Has("Quick scan") and Has("%(") , style .. ": its price, time, units, quick scan", tip.lines[2] and tip.lines[2][1])
    GetCursorPosition = function() return 1000 + hf.xy[2][1] + 2, 50 end
    hf.hover._scripts.OnUpdate(hf.hover)
    ok(hf.hovered == 2 and tip.lines[1][1] == "2s 00c" and Has("25 units in 2 auctions") and Has("Full scan"), style .. ": moved: the middle point (a full scan)")
    W.Run(hf.hover, "OnLeave")
    ok(not hf.dot:IsShown() and not tip.shown and hf.hover._scripts.OnUpdate == nil, style .. ": left: dot and tooltip gone, no OnUpdate")
  end
  I.S.graphStyle = "lines"
  Mk.historyID = nil
  Mk.house = nil
  GT.SetOwner, GT.AddLine, GT.Show, GT.Hide, GT.GetOwner, GT.SetHyperlink = unpack(keepGT)
  ok(#W.sizeErrors == errs0, "no handler error")
  for id, v in pairs(was) do m171[id] = v end
end)()

print("== 41. 1.2.1: trainer reads as the list fills in, more ways to the item, what the read saw, the ? note")
;(function()
  local Mk, R = I.Market, I.Trainer
  -- (1.2.4) a fixture, not the bundled data: these items as the bundled data had them before 1.2.4 (no level known),
  -- so what's tested (a level found later) doesn't hang on which levels Data/Forever/TopSkills.lua has read
  local m171, was = I.Craft.TopMap("craft")[171], {}
  for _, id in ipairs({ 3383, 6371 }) do was[id] = m171[id] m171[id] = false end
  W.items[3383] = { "Elixir of Wisdom", 134711 } W.items[3385] = { "Lesser Mana Potion", 134851 } W.items[3389] = { "Elixir of Defense", 134846 }
  W.items[8949] = { "Elixir of Agility", 134873 }
  local services, filters, setLog = {}, { available = true, unavailable = false, used = false }, {}
  local ready, fireOnSet = false, false
  local function Visible() local t = {} if not ready then return t end for _, s in ipairs(services) do if s[2] == "header" or filters[s[2]] then t[#t + 1] = s end end return t end
  GetTrainerServiceTypeFilter = function(t) return filters[t] end
  SetTrainerServiceTypeFilter = function(t, v) setLog[#setLog + 1] = t .. "=" .. tostring(v) filters[t] = v and true or false if fireOnSet then W.Fire("TRAINER_UPDATE") end end
  GetNumTrainerServices = function() return #Visible() end
  GetTrainerServiceInfo = function(i) local s = Visible()[i] if s then if s.hideName then return nil, s[2] end return s[1], s[2] end end
  GetTrainerServiceSkillReq = function(i) local s = Visible()[i] if s and s.skill then return s.skill[1], s.skill[2], true end end
  GetTrainerServiceItemLink = function(i) local s = Visible()[i] return s and s.link end
  IsTradeskillTrainer = function() return true end
  local schem = { [3171] = 3389 }
  C_TradeSkillUI = C_TradeSkillUI or {}
  local keepSchem = C_TradeSkillUI.GetRecipeSchematic
  C_TradeSkillUI.GetRecipeSchematic = function(id) return schem[id] and { outputItemID = schem[id] } or nil end
  services = {
    { "Alchemy", "header" },
    { "Elixir of Wisdom", "unavailable", skill = { "Alchemy", 90 }, hideName = true },               -- (its name comes later)
    { "Elixir of Defense", "available", skill = { "Alchemy", 130 }, link = "|Hspell:3171|h[Elixir of Defense]|h" },   -- (a spell link)
    { "Lesser Mana Potion", "used", skill = { "Alchemy", 120 } },                                  -- (by name)
    { "Elixir of Agility", "unavailable", skill = { "Alchemy", 185 } },                              -- (its item not loaded yet)
  }
  W.uncached[8949] = true
  I.db.trainer = nil
  W.timers = {}
  ns.printed = {}
  W.now = W.now + 100
  W.Fire("TRAINER_SHOW")
  ok(R.open and (I.db.trainer == nil or next(I.db.trainer) == nil) and table.concat(setLog, ",") == "unavailable=true,used=true,unavailable=false,used=false" and #ns.printed == 0,
    "the window opens with its list still empty: nothing recorded, the filters put back")
  -- the list fills in
  ready = true
  W.Fire("TRAINER_UPDATE")
  ok(#W.timers == 0, "an update within a second of our own read: taken as our filter switching (no read)")
  W.now = W.now + 5
  W.Fire("TRAINER_UPDATE") W.Fire("TRAINER_UPDATE")
  ok(#W.timers == 2, "the list updates: a read waits half a second (each update restarts the wait)")
  setLog = {}
  W.RunTimers()
  local tr = I.db.trainer and I.db.trainer[171]
  ok(tr and tr.items[3389] == 130 and tr.items[3385] == 120 and tr.items[3383] == nil and tr.items[8949] == nil and #setLog == 4 and filters.unavailable == false and filters.used == false,
    "read once when it filled in: a spell link (what the recipe makes) and a name matched; filters put back", tostring(tr and tr.n))
  ok(tr.last and tr.last.services == 4 and tr.last.matched == 2 and table.concat(tr.last.unmatched, ",") == "#2,Elixir of Agility" and tr.last.link:find("spell:3171", 1, true),
    "what the read saw saved: 4 recipes, 2 matched, the unmatched (a missing name, an unloaded item), a sample link", tr.last and table.concat(tr.last.unmatched or {}, ","))
  ok(Printed("recorded 2 skill levels from this Alchemy trainer %(2 not matched to an item; /valhalla invest trainer%)"), "chat: recorded and not matched", ns.printed[#ns.printed])
  ok(R.wait and R.wait[8949] and W.calls.requestLoad and W.calls.requestLoad > 0, "the item not loaded yet: asked for")
  -- names arrive
  W.now = W.now + 5
  services[2].hideName = nil
  W.Fire("TRAINER_SERVICE_INFO_NAME_UPDATE")
  W.RunTimers()
  ok(tr.items[3383] == 90 and tr.items[8949] == nil and tr.last.matched == 3, "a recipe name arrives: read again, Elixir of Wisdom 90")
  W.now = W.now + 5
  W.uncached[8949] = nil
  W.Fire("GET_ITEM_INFO_RECEIVED", 8949)
  W.RunTimers()
  ok(tr.items[8949] == 185 and tr.last.matched == 4 and #tr.last.unmatched == 0 and tr.n == 4, "the item's name arrives: read again, Elixir of Agility 185; all matched")
  -- our own filter switching firing updates (as the game does, at once): no second read
  W.now = W.now + 5
  fireOnSet = true
  local reads = R.reads
  W.Fire("TRAINER_UPDATE") W.RunTimers()
  ok(R.reads == reads + 1 and #W.timers == 0, "the updates our own filter switching makes: no read of their own")
  fireOnSet = false
  -- at most MAX_READS for one opening
  for _ = 1, 10 do W.now = W.now + 5 W.Fire("TRAINER_UPDATE") W.RunTimers() end
  ok(R.openReads == R.MAX_READS, "at most " .. R.MAX_READS .. " reads for one opening of the window", R.openReads)
  W.Fire("TRAINER_CLOSED")
  W.now = W.now + 5
  W.Fire("TRAINER_UPDATE")
  ok(not R.open and #W.timers == 0, "closed: no more reads")
  -- /valhalla invest trainer
  ns.printed = {}
  Slash("invest", "trainer")
  ok(Printed("^Alchemy: 4 skill levels recorded%. Last read: 4 recipes, 4 matched to an item%.$"), "/valhalla invest trainer: recorded and the last read", ns.printed[1])
  -- Top 10 at once (no reload): Alchemy 151-225
  local list = { { id = 3383 }, { id = 3385 }, { id = 8949 }, { id = 6371 } }
  local out, n, unk = Mk.TopFilter(list, "craft", 171, "151")
  local ids = {} for _, e in ipairs(out) do ids[#ids + 1] = e.id .. (unk[e.id] and "?" or "") end
  ok(table.concat(ids, ",") == "8949,6371?" and Mk.TopSkill("craft", 171, 6371) == false,
    "Top 10 at once: Elixir of Wisdom and Lesser Mana Potion gone from 151-225, Elixir of Agility (185) unmarked; Fire Oil (a recipe item) still ?", table.concat(ids, ","))
  ok(Mk.UNKNOWN_NOTE:find("a recipe you find or buy %(not taught by trainers%) stays %? until its level is in Valhalla's data"), "the note: why a found or bought recipe stays ?")
  -- a class trainer: never read
  IsTradeskillTrainer = function() return false end
  setLog = {}
  W.Fire("TRAINER_SHOW")
  ok(#setLog == 0, "a class trainer: not read, its filters untouched")
  W.Fire("TRAINER_CLOSED")
  C_TradeSkillUI.GetRecipeSchematic = keepSchem
  for id, v in pairs(was) do m171[id] = v end
end)()

print(("\n%d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
