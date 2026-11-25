--------------------------------------------------------------------------------
-- Parts (1.2.26): pieces two parts of the map used to build each their own way.
--
--   Parts.Sender(prefix, gap)        addon messages sent one every `gap` seconds. .Send(key, text, channel,
--                                    target, bn): a message with a key replaces the one waiting with that key (in
--                                    its place); no key, always queued. bn: a Battle.net friend's game account.
--   Parts.MapCatcher(sc, on)         the frame over the map's canvas a drawing tool takes the mouse with: left
--                                    button on.down / on.up, right-drag pans the map (Blizzard's own drag), the
--                                    wheel zooms, on.update each frame, on.key(key) -> a function for a key that's
--                                    the tool's (run out of combat, the key not passed on), else the key goes to
--                                    the game (Style.KeysThrough: never set in combat).
--   Parts.TwoClick(label, fn)        a button's OnClick for "click twice": the first shows "Sure?" for 3 s.
--   Parts.QuestPoi(parent)           (1.2.45) Valhalla's own instance of the quest POI button the game's Objectives
--                                    tracker uses (ObjectiveTrackerPOIButtonTemplate, else POIButtonTemplate); nil when
--                                    this client has neither. Its click and hover are the caller's.
--   Parts.PaintQuestPoi(b, q, style, selected)  that button styled as the tracker styles it (SetQuestID, SetStyle,
--                                    SetSelected, UpdateButtonStyle): the in-progress, complete, campaign... look and
--                                    the super-tracked glow are the game's own. Restyled only when one of them changed.
--------------------------------------------------------------------------------

local _, ns = ...
local L = ns.L
local Parts = {}
ns.Parts = Parts

function Parts.Sender(prefix, gap)
	local s = { order = {}, byKey = {} }
	local frame = CreateFrame("Frame")
	frame:Hide()
	local wait = 0
	frame:SetScript("OnUpdate", function(self, elapsed)
		wait = wait - elapsed
		if wait > 0 then return end
		local m = tremove(s.order, 1)
		if not m then self:Hide() return end
		if m.key ~= nil then s.byKey[m.key] = nil end
		wait = gap
		if m.bn then
			if BNSendGameData then pcall(BNSendGameData, m.bn, prefix, m.text) end
		elseif C_ChatInfo and C_ChatInfo.SendAddonMessage then
			pcall(C_ChatInfo.SendAddonMessage, prefix, m.text, m.channel, m.target)
		end
	end)
	s.frame = frame
	function s.Send(key, text, channel, target, bn)
		local m = key ~= nil and s.byKey[key]
		if not m then
			m = { key = key }
			s.order[#s.order + 1] = m
			if key ~= nil then s.byKey[key] = m end
		end
		m.text, m.channel, m.target, m.bn = text, channel, target, bn
		frame:Show()
	end
	return s
end

function Parts.MapCatcher(sc, on)
	local catcher = CreateFrame("Frame", nil, sc)
	catcher:SetAllPoints(sc)
	catcher:SetFrameLevel(math.min(sc:GetFrameLevel() + 9200, 9940))
	catcher:EnableMouse(true)
	catcher:EnableMouseWheel(true)
	catcher:Hide()
	local panning = false
	catcher:SetScript("OnMouseDown", function(_, button)
		if button == "LeftButton" then
			on.down()
		elseif button == "RightButton" then
			panning = true
			sc:OnMouseDown("LeftButton")   -- Blizzard's own drag-to-pan
		end
	end)
	catcher:SetScript("OnMouseUp", function(_, button)
		if button == "LeftButton" then
			on.up()
		elseif panning then
			panning = false
			sc.mouseButtonInfo.LeftButton.down = false
		end
	end)
	catcher:SetScript("OnMouseWheel", function(_, delta) on.wheel(delta) end)
	catcher:SetScript("OnUpdate", on.update)
	catcher:EnableKeyboard(true)
	ns.Style.KeysThrough(catcher)   -- (1.2.26: never in combat; put back after it)
	catcher:SetScript("OnKeyDown", function(self, key)
		local act = on.key(key)
		if act and not InCombatLockdown() then
			ns.Style.KeysThrough(self, false)
			act()
			C_Timer.After(0, function() ns.Style.KeysThrough(self) end)
		end
	end)
	return catcher
end

function Parts.TwoClick(label, fn)
	return function(self)
		if self.armed then
			fn()
			self.armed = nil
			self:SetText(label)
		else
			self.armed = true
			self:SetText(L["Sure?"])
			C_Timer.After(3, function() self.armed = nil self:SetText(label) end)
		end
	end
end

-- (1.2.45) the quest log's and Objectives tracker's own quest button. A mixin's methods sit on the frame
-- itself: SetQuestID there means the template took.
local POI_TEMPLATES = { "ObjectiveTrackerPOIButtonTemplate", "POIButtonTemplate" }
function Parts.QuestPoi(parent)
	if not CreateFrame then return end
	for _, t in ipairs(POI_TEMPLATES) do
		local ok, b = pcall(CreateFrame, "Button", nil, parent, t)
		if ok and type(b) == "table" and type(rawget(b, "SetQuestID")) == "function" then
			b.native, b.template = true, t
			return b
		end
	end
end

function Parts.PaintQuestPoi(b, q, style, selected)
	if not (b and q) then return end
	selected = selected and true or false
	local quest = b.painted ~= q
	if quest then pcall(b.SetQuestID, b, q) end
	if quest or b.paintedStyle ~= style or b.sel ~= selected then
		pcall(b.SetStyle, b, style)
		pcall(b.SetSelected, b, selected)
		pcall(b.UpdateButtonStyle, b)
	end
	b.painted, b.paintedStyle, b.sel = q, style, selected
end
