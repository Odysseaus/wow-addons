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

-- Big surfaces: the theme's stock media for an area ("shell", "rail", "list", "page") when it loads, else Dark
-- Matter's own file (media.slate / media.parchment) shaded as before. Returns true when stock art was used.
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
    else tex:SetTexCoord(unpack(sp.tc or { 0, 1, 0, 1 })) end
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

-- /dm artprobe: one short line per stock texture/template the WoW theme uses, ok or missing.
function S.Report()
  -- ask for everything the WoW theme lists, even pieces not drawn yet
  local wow = NS.themes and NS.themes.wow
  if wow then
    for _, sp in pairs(wow.stock or {}) do S.TextureOK(sp.file) end
    for _, sp in pairs(wow.stockMedia or {}) do S.TextureOK(sp.file) end
    for _, t in ipairs(wow.stockTemplates or {}) do S.TemplateOK(t[1], t[2]) end
  end
  local names = {}
  for _, n in ipairs(S.order) do names[#names + 1] = n end
  table.sort(names, function(a, b)
    if S.used[a] ~= S.used[b] then return S.used[a] == "texture" end
    return a < b
  end)
  local lines, okN, missN, saved = {}, 0, 0, {}
  lines[1] = "artprobe 0.5.1 (" .. S.Method() .. "):"
  for _, n in ipairs(names) do
    local ok = (S.used[n] == "texture") and texCache[n] or tmplCache[n]
    if ok then okN = okN + 1 else missN = missN + 1 end
    local short = n:gsub("^Interface\\", "")
    lines[#lines + 1] = string.format("%s %s%s", ok and "ok" or "MISSING", short, S.used[n] == "template" and " (template)" or "")
    saved[#saved + 1] = { name = n, kind = S.used[n], ok = ok and true or false }
  end
  lines[#lines + 1] = string.format("artprobe: %d ok, %d missing%s", okN, missN,
    missN > 0 and " (missing pieces use Dark Matter's own art)" or "")
  if NS.db then
    NS.db.artprobe = { version = NS.version, method = S.Method(), ok = okN, missing = missN, items = saved, theme = NS.theme and NS.theme.id }
  end
  return lines
end
