-- 0.5.1 stock art layer. The WoW theme draws with the game's own built-in textures and templates, referenced by path
-- (nothing from the game is copied into the addon). Every texture and template is checked at runtime first; anything
-- the client does not have falls back to Dark Matter's own art, so no piece is ever left blank. /dm artprobe lists
-- each one with ok/missing and saves the list to DarkMatterDB.artprobe.
local _, NS = ...

local S = {}
NS.Stock = S
S.used = {}       -- path or template name -> kind ("texture" / "template"), everything the stock look asked for
S.order = {}
local texCache, tmplCache = {}, {}
local probeTex

local function Note(name, kind)
  if not S.used[name] then S.used[name] = kind S.order[#S.order + 1] = name end
end

-- How a texture's presence was decided (shown by /dm artprobe): the file-ID lookup when the client has it, otherwise a
-- trial load on a hidden texture.
function S.Method()
  if type(GetFileIDFromPath) == "function" then return "file-ID lookup" end
  return "trial texture load"
end

function S.TextureOK(path)
  if type(path) ~= "string" or path == "" then return false end
  Note(path, "texture")
  local c = texCache[path]
  if c ~= nil then return c end
  local ok = false
  if type(GetFileIDFromPath) == "function" then
    local s, id = pcall(GetFileIDFromPath, path)
    ok = s and type(id) == "number" and id > 0
  else
    if not probeTex and UIParent and UIParent.CreateTexture then probeTex = UIParent:CreateTexture(nil, "BACKGROUND") if probeTex.Hide then probeTex:Hide() end end
    if probeTex then
      local s, r = pcall(probeTex.SetTexture, probeTex, path)
      ok = s and r ~= false
      if ok and type(probeTex.GetTextureFileID) == "function" then
        local s2, id = pcall(probeTex.GetTextureFileID, probeTex)
        if s2 and id ~= nil then ok = type(id) == "number" and id > 0 end
      end
    end
  end
  texCache[path] = ok and true or false
  return texCache[path]
end

local tmplParent
function S.TemplateOK(name, ftype)
  Note(name, "template")
  local c = tmplCache[name]
  if c ~= nil then return c end
  local ok
  if C_XMLUtil and type(C_XMLUtil.GetTemplateInfo) == "function" then
    local s, info = pcall(C_XMLUtil.GetTemplateInfo, name)
    ok = s and info ~= nil
  else
    if not tmplParent then tmplParent = CreateFrame("Frame", nil, UIParent) tmplParent:Hide() end
    local s, fr = pcall(CreateFrame, ftype or "Frame", nil, tmplParent, name)
    ok = s and fr ~= nil
    if fr and fr.Hide then fr:Hide() end
  end
  tmplCache[name] = ok and true or false
  return tmplCache[name]
end

-- Forget what was checked (the next look-up asks the client again).
function S.ClearCache()
  for k in pairs(texCache) do texCache[k] = nil end
  for k in pairs(tmplCache) do tmplCache[k] = nil end
end

-- Create a frame from a stock template when the client has it (nil otherwise; the caller then builds its own).
function S.FromTemplate(ftype, parent, name)
  if not S.TemplateOK(name, ftype) then return nil end
  local s, fr = pcall(CreateFrame, ftype, nil, parent, name)
  if s then return fr end
  tmplCache[name] = false
  return nil
end

-- Stock spec for an atlas piece key in the current theme, only when its file loads.
function S.Spec(key)
  local st = NS.theme and NS.theme.stock
  local sp = st and st[key]
  if sp and S.TextureOK(sp.file) then return sp end
  return nil
end

local blended = setmetatable({}, { __mode = "k" })
-- Draw a stock spec on a texture: file, texcoords (4 or 8 numbers), optional blend mode and vertex colour.
function S.Apply(tex, sp)
  NS.Unflat(tex)
  if sp.wrap then tex:SetTexture(sp.file, sp.wrap, sp.wrap) else tex:SetTexture(sp.file) end
  local tc = sp.tc or { 0, 1, 0, 1 }
  tex:SetTexCoord(unpack(tc))
  if sp.blend then tex:SetBlendMode(sp.blend) blended[tex] = true
  elseif blended[tex] then tex:SetBlendMode("BLEND") blended[tex] = nil end
  local vc = sp.vc
  if vc then tex:SetVertexColor(vc[1], vc[2], vc[3], vc[4] or 1) else tex:SetVertexColor(1, 1, 1, 1) end
end
-- Undo a stock blend mode before Dark Matter's own art is drawn on the same texture.
function S.Reset(tex)
  if blended[tex] then tex:SetBlendMode("BLEND") blended[tex] = nil end
end

-- 0.5.1.1: the crop of a "crop" surface (QuestBG): the theme's texcoords, or the player's /dm parchment override
-- (DarkMatterDB.parchTC, four numbers 0..1 with left < right and top < bottom).
function S.CropTC(sp)
  local o = NS.db and NS.db.parchTC
  if sp.crop and type(o) == "table" then
    local l, r, t, b = NS.Num(o[1]), NS.Num(o[2]), NS.Num(o[3]), NS.Num(o[4])
    if l and r and t and b and l >= 0 and r <= 1 and t >= 0 and b <= 1 and l < r and t < b then return { l, r, t, b } end
  end
  return sp.tc or { 0, 1, 0, 1 }
end

-- Big surfaces: the theme's stock media for an area ("shell", "rail", "list", "page", "detail") when it loads, else
-- Dark Matter's own file (media.slate / media.parchment) shaded as before. Returns true when stock art was used.
-- The caller anchors tex to BOTH corners of its panel (SetAllPoints), so the art always fills the panel: a tiled
-- surface repeats every sp.tile pixels; any other surface stretches sp.tc (the clean part of the file) over the whole
-- panel. 0.5.1.1: never the whole file of a sheet that only fills part of it (QuestBG: torn edges mid-panel).
function S.Media(tex, area, fallbackKind, shade)
  local sm = NS.theme and NS.theme.stockMedia
  local sp = sm and sm[area]
  if sp and S.TextureOK(sp.file) then
    NS.Unflat(tex)
    S.Reset(tex)
    if sp.tile then tex:SetTexture(sp.file, "REPEAT", "REPEAT") else tex:SetTexture(sp.file) end
    local w, h = NS.Num(tex:GetWidth()) or 0, NS.Num(tex:GetHeight()) or 0
    if (w <= 1 or h <= 1) and tex.GetParent then
      local par = tex:GetParent()
      if par and par.GetWidth then w, h = NS.Num(par:GetWidth()) or 0, NS.Num(par:GetHeight()) or 0 end
    end
    if sp.tile and w > 1 and h > 1 then tex:SetTexCoord(0, w / sp.tile, 0, h / sp.tile)
    elseif sp.tile then tex:SetTexCoord(0, 1, 0, 1)
    else tex:SetTexCoord(unpack(S.CropTC(sp))) end
    local c, k = sp.vc or { 1, 1, 1, 1 }, sp.shade or 1
    tex:SetVertexColor(c[1] * k, c[2] * k, c[3] * k, c[4] or 1)
    return true
  end
  S.Reset(tex)
  shade = shade or 1
  tex:SetTexture(NS.theme.media[fallbackKind])
  tex:SetTexCoord(0, 1, 0, 1)
  tex:SetVertexColor(shade, shade, shade, 1)
  return false
end

-- 0.5.1.1 scroll buttons: the stock button states of a piece (sb_up / sb_dn) when the client has all four files.
function S.ButtonStates(key)
  local sp = S.KitSpec(key) -- 0.5.1.3: the class themes borrow the WoW theme's scroll buttons too
  if not (sp and sp.down and sp.disabled and sp.highlight) then return nil end
  if not (S.TextureOK(sp.down) and S.TextureOK(sp.disabled) and S.TextureOK(sp.highlight)) then return nil end
  return sp
end


-- 0.5.1.2 stock button feel: the theme's UIPanelButtonTemplate files (stockButtons) when the client has all four.
-- 0.5.1.3: every theme. The WoW theme draws them as they are; a class theme (theme.stockTint) borrows the WoW theme's
-- files and draws them desaturated and recoloured in its own palette (S.Tint).
local function Wow() return NS.themes and NS.themes.wow end
local function KitOn()
  local th = NS.theme
  return th and (th.stockButtons or th.stockTint) and true or false
end
function S.PanelButton()
  if not KitOn() then return nil end
  local sb = NS.theme.stockButtons or (Wow() and Wow().stockButtons)
  if not sb then return nil end
  for _, k in ipairs({ "up", "down", "disabled", "highlight" }) do
    if not S.TextureOK(sb[k]) then return nil end
  end
  return sb
end
-- a stock piece spec for the current theme: its own (WoW) or, for a class theme with a stock tint, the WoW theme's
function S.KitSpec(key)
  local th = NS.theme
  local sp = th and th.stock and th.stock[key]
  if not sp and th and th.stockTint then local w = Wow() sp = w and w.stock and w.stock[key] end
  if sp and S.TextureOK(sp.file) then return sp end
  return nil
end
-- the character-frame tab look (both tab files + the tab highlight), for the section tabs. 0.5.1.3: built from the
-- UI-Character-ActiveTab / InActiveTab textures alone; the CharacterFrameTabButtonTemplate template itself is never
-- needed (the 1.60.1 client does not have it).
function S.TabButton()
  local sb = S.PanelButton()
  if not (sb and sb.tabHighlight) then return nil end
  for _, k in ipairs({ "ptab_a_l", "ptab_a_m", "ptab_a_r", "ptab_i_l", "ptab_i_m", "ptab_i_r" }) do
    if not S.KitSpec(k) then return nil end
  end
  if not S.TextureOK(sb.tabHighlight) then return nil end
  return { highlight = sb.tabHighlight, highlightTC = sb.tabHighlightTC or { 0, 1, 0, 1 } }
end
-- the recolour for one kind of stock piece in a class theme ({ r, g, b }); nil in the WoW theme (drawn as is)
function S.Tint(kind)
  local t = NS.theme and NS.theme.stockTint
  if not t then return nil end
  return t[kind] or t.face
end
-- desaturate + recolour a stock texture (class theme), or undo both (WoW theme)
function S.Recolor(tex, tint, alpha)
  if tex.SetDesaturated then tex:SetDesaturated(tint and true or false) end
  if tint then tex:SetVertexColor(tint[1], tint[2], tint[3], alpha or 1) else tex:SetVertexColor(1, 1, 1, alpha or 1) end
end

-- /dm artprobe: one short line per stock texture/template the WoW theme uses, ok or missing.
function S.Report()
  -- ask for everything the WoW theme lists, even pieces not drawn yet
  local wow = NS.themes and NS.themes.wow
  if wow then
    for _, sp in pairs(wow.stock or {}) do
      S.TextureOK(sp.file)
      if sp.down then S.TextureOK(sp.down) S.TextureOK(sp.disabled) S.TextureOK(sp.highlight) end
    end
    for _, sp in pairs(wow.stockMedia or {}) do S.TextureOK(sp.file) end
    for _, k in ipairs({ "up", "down", "disabled", "highlight", "tabHighlight" }) do
      if wow.stockButtons and wow.stockButtons[k] then S.TextureOK(wow.stockButtons[k]) end
    end
    for _, t in ipairs(wow.stockTemplates or {}) do S.TemplateOK(t[1], t[2]) end
  end
  local names = {}
  for _, n in ipairs(S.order) do names[#names + 1] = n end
  table.sort(names, function(a, b)
    if S.used[a] ~= S.used[b] then return S.used[a] == "texture" end
    return a < b
  end)
  local lines, okN, missN, saved = {}, 0, 0, {}
  -- 0.5.1.3: what stands in for a missing piece (said on its line and in the one-line summary)
  local fb = wow and wow.stockFallback or {}
  local missing = {}
  lines[1] = "artprobe " .. tostring(NS.version) .. " (" .. S.Method() .. "):"
  for _, n in ipairs(names) do
    local ok = (S.used[n] == "texture") and texCache[n] or tmplCache[n]
    if ok then okN = okN + 1 else missN = missN + 1 end
    local short = n:gsub("^Interface\\", "")
    local kind = S.used[n] == "template" and " (template)" or ""
    local instead = fb[n] or "Dark Matter's own art"
    lines[#lines + 1] = string.format("%s %s%s%s", ok and "ok" or "MISSING", short, kind, ok and "" or (" -> " .. instead))
    if not ok then missing[#missing + 1] = short .. kind .. " -> " .. instead end
    saved[#saved + 1] = { name = n, kind = S.used[n], ok = ok and true or false, instead = (not ok) and instead or nil }
  end
  -- the summary names a missing piece (up to 3) on the one line with its stand-in (the list above can scroll out of the
  -- chat frame); with more missing, the client has no stock art at all and Dark Matter's own art is drawn
  local tail = ""
  if missN > 3 then
    tail = " (missing pieces use Dark Matter's own art)"
  elseif missN > 0 then
    tail = ": " .. table.concat(missing, "; ")
  end
  lines[#lines + 1] = string.format("artprobe: %d ok, %d missing%s", okN, missN, tail)
  if NS.db then
    NS.db.artprobe = { version = NS.version, method = S.Method(), ok = okN, missing = missN, items = saved, theme = NS.theme and NS.theme.id,
      missingNames = missing }
  end
  return lines
end
