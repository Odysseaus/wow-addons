-- WoWThreat 1.4.0 stock art. The 'wow' theme draws with the game's own built-in textures, referenced by path in game
-- (nothing from the game is copied into the addon). Each texture is checked at runtime first; anything this client
-- does not have falls back to WoWThreat's own look, piece by piece, so nothing is ever blank.
-- /wtm artprobe lists each texture with ok/MISSING and saves the list to WoWThreatDB.artprobe.
local _, NS = ...

local S = {}
NS.Stock = S

-- Everything the 'wow' theme asks the game for (key -> path). Shown by /wtm artprobe in this order.
S.PATHS = {
  { "edge", "Interface\\Tooltips\\UI-Tooltip-Border" },         -- tooltip-style frame border (edge file)
  { "bg", "Interface\\Tooltips\\UI-Tooltip-Background" },       -- tooltip background (tinted dark)
  { "header", "Interface\\DialogFrame\\UI-DialogBox-Header" },  -- dialog title plate
  { "bar", "Interface\\TargetingFrame\\UI-StatusBar" },         -- stock status bar (bar track + plain fill)
}
S.PATH = {}
for _, p in ipairs(S.PATHS) do S.PATH[p[1]] = p[2] end

local cache = {}
local probeTex

-- How presence is decided (shown by /wtm artprobe): the file-ID lookup when the client has it, otherwise a trial
-- load on a hidden texture.
function S.Method()
  if type(GetFileIDFromPath) == "function" then return "file-ID lookup" end
  return "trial texture load"
end

function S.TextureOK(path)
  if type(path) ~= "string" or path == "" then return false end
  local c = cache[path]
  if c ~= nil then return c end
  local ok = false
  if type(GetFileIDFromPath) == "function" then
    local s, id = pcall(GetFileIDFromPath, path)
    ok = s and type(id) == "number" and id > 0
  elseif type(CreateFrame) == "function" then
    if not probeTex then
      local okF, f = pcall(CreateFrame, "Frame")
      if okF and f then f:Hide() probeTex = f:CreateTexture(nil, "BACKGROUND") end
    end
    if probeTex then
      local s, r = pcall(probeTex.SetTexture, probeTex, path)
      ok = s and r ~= false
      if ok and type(probeTex.GetTextureFileID) == "function" then
        local s2, id = pcall(probeTex.GetTextureFileID, probeTex)
        if s2 and id ~= nil then ok = type(id) == "number" and id > 0 end
      end
    end
  end
  cache[path] = ok and true or false
  return cache[path]
end

-- Path for a key when the client has it, else nil (the caller draws its fallback).
function S.Get(key)
  local p = S.PATH[key]
  if p and S.TextureOK(p) then return p end
  return nil
end

function S.ClearCache() cache = {} end

-- /wtm artprobe: short lines, saved to WoWThreatDB.artprobe.
function S.Report()
  local lines, items, nOk, nMiss = {}, {}, 0, 0
  lines[1] = "artprobe " .. tostring(NS.VERSION) .. " (" .. S.Method() .. "):"
  for _, p in ipairs(S.PATHS) do
    local ok = S.TextureOK(p[2])
    local short = p[2]:gsub("^Interface\\", "")
    lines[#lines + 1] = (ok and "ok " or "MISSING ") .. short
    items[#items + 1] = { key = p[1], path = p[2], ok = ok }
    if ok then nOk = nOk + 1 else nMiss = nMiss + 1 end
  end
  lines[#lines + 1] = "artprobe: " .. nOk .. " ok, " .. nMiss .. " missing" .. (nMiss > 0 and " (missing pieces use WoWThreat's own art)" or "")
  if type(WoWThreatDB) == "table" then
    WoWThreatDB.artprobe = { version = NS.VERSION, method = S.Method(), ok = nOk, missing = nMiss, items = items,
      theme = NS.ThemeId and NS.ThemeId() or nil }
  end
  return lines
end
