local Pure = dofile("/qalcom/lib/pure.lua")
local Palette = {}
Palette.slots = {
colors.white, colors.orange, colors.magenta, colors.lightBlue,
colors.yellow, colors.lime, colors.pink, colors.gray,
colors.lightGray, colors.cyan, colors.purple, colors.blue,
colors.brown, colors.green, colors.red, colors.black,
}
local function supported()
return type(term) == "table" and type(term.setPaletteColor) == "function"
end
Palette.supported = supported
function Palette.channels(hex)
return Pure.colorChannels(hex)
end
function Palette.snapshot()
if not supported() or type(term.getPaletteColor) ~= "function" then return nil end
local snap = {}
for _, slot in ipairs(Palette.slots) do
local ok, r, g, b = pcall(term.getPaletteColor, slot)
if ok and r then snap[slot] = { r, g, b } end
end
return snap
end
function Palette.resetDefaults()
if not supported() or type(term.nativePaletteColor) ~= "function" then return false end
for _, slot in ipairs(Palette.slots) do
local ok, r, g, b = pcall(term.nativePaletteColor, slot)
if ok and r then pcall(term.setPaletteColor, slot, r, g, b) end
end
return true
end
function Palette.restore(snap)
if not supported() then return false end
if type(snap) == "table" then
for slot, rgb in pairs(snap) do
pcall(term.setPaletteColor, slot, rgb[1], rgb[2], rgb[3])
end
return true
end
return Palette.resetDefaults()
end
function Palette.apply(palette)
if not supported() or type(palette) ~= "table" then return false end
for slot, hex in pairs(palette) do
local r, g, b = Pure.colorChannels(hex)
pcall(term.setPaletteColor, slot, r, g, b)
end
return true
end
return Palette