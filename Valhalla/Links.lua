--------------------------------------------------------------------------------
-- Shift-click into Valhalla's boxes (v0.3.1). Shift-clicking an item while one of Valhalla's text boxes
-- has the cursor puts the item in that box, the way it goes into chat. The game's bags open their
-- "split the stack" box on a shift-click whenever nothing (no chat line) took the link
-- (HandleModifiedItemClick -> ChatFrameUtil.InsertLink returned false). So: when one of our boxes took
-- the link on this very click, that split box is closed again as it opens. Anywhere else (no Valhalla
-- box has the cursor, or it didn't take the link) shift-click is the game's own, split box and all.
--
-- Boxes sign up with ns.LinkBox(box[, take]): take(box, link) puts the item in and returns true. The
-- default puts in the item's name as plain text (for notes). Nothing is written on the game's frames:
-- the chat's link function is post-hooked (hooksecurefunc) and the split box's OnShow hooked (HookScript).
--------------------------------------------------------------------------------

local _, ns = ...
local K = { boxes = setmetatable({}, { __mode = "k" }), order = {}, suppressed = 0 }
ns.Links = K

-- the item's name, as plain text where the cursor is
function K.InsertName(box, link)
	local name = type(link) == "string" and link:match("|h%[(.-)%]|h")
	if not name or name == "" then return false end
	if box.Insert then box:Insert(name) else box:SetText((box:GetText() or "") .. name) end
	return true
end

function ns.LinkBox(box, take)
	if not box then return end
	if K.boxes[box] == nil then K.order[#K.order + 1] = box end
	K.boxes[box] = take or K.InsertName
	K.Install()
end

-- the Valhalla box with the cursor, if any
function K.Focused()
	for _, box in ipairs(K.order) do
		local take = K.boxes[box]
		if take and box.HasFocus and box:HasFocus() then return box, take end
	end
end

local function Now() return GetTime and GetTime() or 0 end

-- after the game's ChatFrameUtil.InsertLink (a shift-clicked item, anywhere)
function K.OnInsertLink(text)
	if type(text) ~= "string" or not text:find("|H", 1, true) then return end
	local box, take = K.Focused()
	if not box then return end
	local ok, took = pcall(take, box, text)
	if ok and took then K.took = Now() end
end

-- the split box opening on the same click our box took the link: closed again
function K.OnSplitShow(frame)
	if K.took and K.took == Now() then
		K.took = nil
		K.suppressed = K.suppressed + 1
		frame:Hide()
	end
end

function K.Install()
	if not K.linkHooked then
		if _G.ChatFrameUtil and _G.ChatFrameUtil.InsertLink then
			hooksecurefunc(_G.ChatFrameUtil, "InsertLink", K.OnInsertLink)
			K.linkHooked = true
		elseif _G.ChatEdit_InsertLink then
			hooksecurefunc("ChatEdit_InsertLink", K.OnInsertLink)
			K.linkHooked = true
		end
	end
	if not K.splitHooked and _G.StackSplitFrame and _G.StackSplitFrame.HookScript then
		_G.StackSplitFrame:HookScript("OnShow", K.OnSplitShow)
		K.splitHooked = true
	end
end
