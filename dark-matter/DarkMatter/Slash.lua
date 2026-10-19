-- /dm            toggle the window
-- /dm probe      print + save API/version probe to DarkMatterDB.probe
-- /dm reset      reset window position (and minimap button angle with "all")
local _, NS = ...

SLASH_DARKMATTER1 = "/dm"
SLASH_DARKMATTER2 = "/darkmatter"

local function Help()
  NS.Print("v" .. NS.version .. " commands:")
  print("  /dm  toggle the window")
  print("  /dm probe  check this client's APIs (saved to DarkMatterDB.probe)")
  print("  /dm reset  reset window position   (/dm reset all: also minimap button)")
  print("  /dm minimap  show/hide the minimap button")
  print("  /dm icon  switch between the Dark Matter icon and a stock icon")
  print("  /dm options  open the Settings page")
end

SlashCmdList["DARKMATTER"] = function(msg)
  if not NS.db then NS.Print("not ready yet.") return end
  local cmd, rest = strmatch(strlower(strtrim(msg or "")), "^(%S*)%s*(.-)$")
  if cmd == "" or cmd == "toggle" then
    NS.ToggleWindow()
  elseif cmd == "show" then
    NS.ToggleWindow(true)
  elseif cmd == "hide" then
    NS.ToggleWindow(false)
  elseif cmd == "probe" then
    NS.RunProbe(false)
  elseif cmd == "reset" then
    NS.ResetWindowPosition()
    if rest == "all" then NS.ResetMinimapButton() NS.Print("minimap button reset.") end
  elseif cmd == "minimap" then
    NS.SetMinimapButtonShown(NS.db.minimap.hide)
  elseif cmd == "icon" then
    NS.db.stockIcon = not NS.db.stockIcon
    NS.SetMinimapIcon()
    NS.Print(NS.db.stockIcon and "using the stock icon." or "using the Dark Matter icon.")
  elseif cmd == "options" then
    NS.OpenOptions()
  else
    Help()
  end
end
