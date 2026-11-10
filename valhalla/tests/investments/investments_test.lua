-- Box tests for Valhalla/Investments (Lua 5.1). Run: lua valhalla/tests/investments/investments_test.lua [path to Valhalla/]
local here = (arg[0] or ""):match("^(.*[/\\])") or "./"
local root = arg[1] or (here .. "../../Valhalla/")
dofile(here .. "stubs.lua")

local ns = { modules = {}, version = "v0.3.3", Media = { path = "Interface\\AddOns\\Valhalla\\Media\\" } }
ns.L = setmetatable({}, { __index = function(_, k) return k end })
ns.Safe = { Value = function(v) return v end }
ns.Look = { Font = function(_, fs, size) fs._size = size return fs end }
ns.printed = {}
function ns:Print(fmt, ...) ns.printed[#ns.printed + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end
function ns:NewModule(key, spec) local m = spec or {} m.key = key m.defaults = m.defaults or {} if m.defaults.enabled == nil then m.defaults.enabled = true end self.modules[key] = m return m end
function ns:GetModule(key) return self.modules[key] end
ns.modules.worldmap = { key = "worldmap", enabled = true }
assert(loadfile(root .. "Links.lua"))("Valhalla", ns)
for _, f in ipairs({ "Invest", "Tabs", "Views", "Merchant", "AHPanel" }) do
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
ok(#T.Buttons() == 4, "four tabs")
local labels = {}
for i, b in ipairs(T.Buttons()) do labels[i] = b.label._text end
ok(table.concat(labels, "|") == "Map & Quest Log|Investments|Talents|Professions", "in order", table.concat(labels, "|"))
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
ok(Printed("tab map|invest|talents|professions"), "a wrong tab: says which there are")
WorldMapFrame:Hide()
W.combat = true W.calls.toggleMap = 0
Slash("tab", "invest")
ok(W.calls.toggleMap == 0 and Printed("can't be opened in combat"), "in combat: the map isn't opened")
W.combat = false
WorldMapFrame:Show()
Slash("invest", "settings")
ok(T.Current() == "invest" and T.Views().invest.page.current == "settings", "/valhalla invest settings: that page")
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
ok(d.toc == 16001 and d.version == "v0.3.3", "client and version")
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
local sp2 = root.pages.settings
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
for _, k in ipairs({ "vendor", "list", "market", "settings" }) do
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

print("== 21. the diagnostic's buttons (Investments > Settings)")
root2:ShowPage("settings")
local sp3 = root2.pages.settings
ok(sp3.run.text._text == "Run diagnostic" and sp3.runAH.text._text == "Run AH check" and sp3.last._text, "Run diagnostic, Run AH check, last run")
ValhallaInvestDB.diag = {}
ns.printed = {}
W.Click(sp3.run)
local d2 = ValhallaInvestDB.diag[1]
ok(d2 and d2.bankInfo.read.items == 17 and d2.list and d2.list.merchants == 1 and d2.list.lists == 6 and d2.list.active == "Mail", "saved: the bank as last read, the lists, merchants")
ok(#ns.printed == 3 and Printed("Diagnostic saved") and Printed("/reload writes it to disk") and Printed("Bank: last read Nov 09 16:50: 17 items in 3 tabs") and Printed("Lists: 6 saved, active 'Mail'"), "three lines in chat", table.concat(ns.printed, " || "))
ok(sp3.last._text == "Last run: Nov 09 16:50", "last run shown", sp3.last._text)
ns.printed = {}
W.Click(sp3.runAH)
ok(#ValhallaInvestDB.diag == 1 and Printed("open the Auction House first"), "Run AH check away from the AH: says where")
W.Fire("AUCTION_HOUSE_SHOW")
ns.printed = {}
W.Click(sp3.runAH)
local d3 = ValhallaInvestDB.diag[2]
ok(d3 and d3.kind == "ah" and d3.ah.search.button and Printed("ready for one%-click Search"), "Run AH check at the AH: its Search button checked")
ok(sp3.last._text:find("%(AH check%)"), "last run: the AH check")
W.Fire("AUCTION_HOUSE_CLOSED")
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

print(("\n%d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
