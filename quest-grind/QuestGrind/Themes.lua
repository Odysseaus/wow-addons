local _, NS = ...

-- Theme identity is colors / materials / motifs only.
-- Do NOT bake class names into art textures. Picker labels may use class names.
-- Art polish (TGA/wood/gold) is P4; P0 uses SetColorTexture layers.

local function C(r, g, b, a)
  return { r = r, g = g, b = b, a = a or 1 }
end

NS.THEME_ORDER = {
  "default",
  "warrior",
  "paladin",
  "hunter",
  "rogue",
  "priest",
  "shaman",
  "mage",
  "warlock",
  "druid",
}

NS.THEMES = {
  default = {
    id = "default",
    label = "Default",
    chrome = C(0.72, 0.55, 0.22, 1),
    chromeHi = C(0.90, 0.78, 0.40, 1),
    panel = C(0.18, 0.12, 0.07, 0.96),
    title = C(0.92, 0.78, 0.35),
    text = C(0.95, 0.93, 0.88),
    muted = C(0.70, 0.65, 0.55),
    accent = C(0.85, 0.65, 0.20),
    statusOk = C(0.35, 0.85, 0.40),
    statusXp = C(0.40, 0.70, 1.0),
    motif = "questbang",
  },
  warrior = {
    id = "warrior",
    label = "Warrior",
    chrome = C(0.45, 0.42, 0.38, 1),
    chromeHi = C(0.72, 0.48, 0.28, 1),
    panel = C(0.12, 0.12, 0.12, 0.97),
    title = C(0.90, 0.75, 0.40),
    text = C(0.92, 0.90, 0.86),
    muted = C(0.60, 0.58, 0.54),
    accent = C(0.55, 0.14, 0.16),
    statusOk = C(0.40, 0.80, 0.40),
    statusXp = C(0.45, 0.70, 1.0),
    motif = "swords",
  },
  paladin = {
    id = "paladin",
    label = "Paladin",
    chrome = C(0.88, 0.75, 0.35, 1),
    chromeHi = C(1.0, 0.92, 0.65, 1),
    panel = C(0.22, 0.20, 0.16, 0.96),
    title = C(1.0, 0.90, 0.55),
    text = C(0.98, 0.96, 0.90),
    muted = C(0.75, 0.70, 0.55),
    accent = C(0.96, 0.70, 0.35),
    statusOk = C(0.45, 0.88, 0.50),
    statusXp = C(0.55, 0.75, 1.0),
    motif = "holy",
  },
  hunter = {
    id = "hunter",
    label = "Hunter",
    chrome = C(0.45, 0.55, 0.28, 1),
    chromeHi = C(0.70, 0.78, 0.40, 1),
    panel = C(0.14, 0.12, 0.08, 0.97),
    title = C(0.78, 0.88, 0.45),
    text = C(0.92, 0.93, 0.85),
    muted = C(0.60, 0.62, 0.48),
    accent = C(0.55, 0.70, 0.30),
    statusOk = C(0.45, 0.85, 0.40),
    statusXp = C(0.45, 0.72, 1.0),
    motif = "feather",
  },
  rogue = {
    id = "rogue",
    label = "Rogue",
    chrome = C(0.35, 0.35, 0.32, 1),
    chromeHi = C(0.75, 0.70, 0.35, 1),
    panel = C(0.10, 0.10, 0.11, 0.97),
    title = C(0.95, 0.90, 0.40),
    text = C(0.92, 0.92, 0.88),
    muted = C(0.55, 0.55, 0.50),
    accent = C(0.70, 0.65, 0.25),
    statusOk = C(0.50, 0.85, 0.40),
    statusXp = C(0.45, 0.70, 1.0),
    motif = "dagger",
  },
  priest = {
    id = "priest",
    label = "Priest",
    chrome = C(0.75, 0.75, 0.82, 1),
    chromeHi = C(0.95, 0.95, 1.0, 1),
    panel = C(0.16, 0.14, 0.20, 0.96),
    title = C(0.95, 0.95, 1.0),
    text = C(0.95, 0.94, 0.98),
    muted = C(0.70, 0.68, 0.78),
    accent = C(0.80, 0.75, 0.95),
    statusOk = C(0.50, 0.88, 0.55),
    statusXp = C(0.55, 0.75, 1.0),
    motif = "holy",
  },
  shaman = {
    id = "shaman",
    label = "Shaman",
    chrome = C(0.20, 0.45, 0.70, 1),
    chromeHi = C(0.35, 0.70, 0.90, 1),
    panel = C(0.14, 0.12, 0.08, 0.97),
    title = C(0.45, 0.75, 1.0),
    text = C(0.92, 0.93, 0.90),
    muted = C(0.55, 0.60, 0.55),
    accent = C(0.15, 0.55, 0.85),
    statusOk = C(0.40, 0.85, 0.45),
    statusXp = C(0.40, 0.75, 1.0),
    motif = "totem",
  },
  mage = {
    id = "mage",
    label = "Mage",
    chrome = C(0.35, 0.45, 0.85, 1),
    chromeHi = C(0.55, 0.70, 1.0, 1),
    panel = C(0.08, 0.08, 0.18, 0.97),
    title = C(0.55, 0.80, 1.0),
    text = C(0.92, 0.94, 0.98),
    muted = C(0.55, 0.58, 0.75),
    accent = C(0.40, 0.55, 0.95),
    statusOk = C(0.45, 0.85, 0.55),
    statusXp = C(0.50, 0.70, 1.0),
    motif = "arcane",
  },
  warlock = {
    id = "warlock",
    label = "Warlock",
    chrome = C(0.45, 0.30, 0.65, 1),
    chromeHi = C(0.55, 0.85, 0.35, 1),
    panel = C(0.06, 0.05, 0.08, 0.97),
    title = C(0.70, 0.55, 0.95),
    text = C(0.90, 0.88, 0.95),
    muted = C(0.55, 0.50, 0.60),
    accent = C(0.50, 0.75, 0.25),
    statusOk = C(0.45, 0.85, 0.40),
    statusXp = C(0.55, 0.65, 1.0),
    motif = "fel",
  },
  druid = {
    id = "druid",
    label = "Druid",
    chrome = C(0.55, 0.40, 0.22, 1),
    chromeHi = C(0.45, 0.70, 0.30, 1),
    panel = C(0.10, 0.14, 0.08, 0.97),
    title = C(0.85, 0.70, 0.35),
    text = C(0.92, 0.93, 0.85),
    muted = C(0.55, 0.60, 0.45),
    accent = C(0.40, 0.65, 0.25),
    statusOk = C(0.45, 0.88, 0.40),
    statusXp = C(0.45, 0.72, 1.0),
    motif = "paw",
  },
}

function NS.GetTheme(id)
  if id and NS.THEMES[id] then
    return NS.THEMES[id]
  end
  if NS.db and NS.db.theme and NS.THEMES[NS.db.theme] then
    return NS.THEMES[NS.db.theme]
  end
  return NS.THEMES.default
end

function NS.ApplyThemeColors(id)
  return NS.GetTheme(id)
end

function NS.SetVertexColor(obj, c, a)
  if not obj or not c then return end
  local alpha = a
  if alpha == nil then alpha = c.a end
  if alpha == nil then alpha = 1 end
  if obj.SetTextColor then
    obj:SetTextColor(c.r, c.g, c.b, alpha)
  elseif obj.SetColorTexture then
    obj:SetColorTexture(c.r, c.g, c.b, alpha)
  elseif obj.SetVertexColor then
    obj:SetVertexColor(c.r, c.g, c.b, alpha)
  end
end
