-- Look must clear a mask before it sets tex coords (1.2.43). The Find Me button redraws a menu
-- icon that already has one, and Forever refuses SetTexCoord on a masked texture.
-- Run: lua5.1 valhalla/tests/worldmap/look_test.lua [path to Valhalla/]
local here = (arg[0] or ""):match("^(.*[/\\])") or "./"
local root = arg[1] or (here .. "../../Valhalla/")

local pass, fail = 0, 0
local function ok(cond, name, detail)
	if cond then pass = pass + 1 print("PASS  " .. name)
	else fail = fail + 1 print("FAIL  " .. name .. (detail and ("  -- " .. tostring(detail)) or "")) end
end

local ns = { Media = { tex = "T\\", path = "P\\" }, Client = "Forever" }
function ns:GetModule() return {} end
ns.L = setmetatable({}, { __index = function(_, k) return k end })
function CreateFrame()
	local f = {}
	return setmetatable(f, { __index = function() return function() return f end end })
end
pcall(function() assert(loadfile(root .. "Map/Stitch.lua"))("Valhalla", ns) end)
local Look = ns.MapStitch and ns.MapStitch.Look
ok(type(Look) == "function", "Look is available")

local order = {}
local tex = {
	masks = 1,
	GetNumMaskTextures = function(self) return self.masks end,
	GetMaskTexture = function() return {} end,
	RemoveMaskTexture = function(self)
		self.masks = 0
		order[#order + 1] = "clear"
	end,
	SetTexCoord = function() order[#order + 1] = "coord" end,
	SetVertexColor = function() end,
	SetTexture = function() return true end,
	SetRotation = function() end,
}
if Look then Look(tex, { texture = "Interface\\Icons\\Trade_Alchemy" }) end
local coordAt, clearAt
for i, step in ipairs(order) do
	if step == "clear" then clearAt = i end
	if step == "coord" and not coordAt then coordAt = i end
end
ok(clearAt and coordAt and clearAt < coordAt and tex.masks == 0,
	"a masked texture is cleared before its tex coords are set", table.concat(order, ","))

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
