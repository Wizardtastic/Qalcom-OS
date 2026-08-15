local Display = dofile("/qalcom/lib/ui/display.lua")
local Canvas = {}
function Canvas.available()
return Display.supportsGraphics()
end
function Canvas.isColour()
local function check(name)
if type(term) == "table" and type(term[name]) == "function" then
local ok, colour = pcall(term[name])
if ok and colour == false then return false end
end
return true
end
return check("isColour") and check("isColor")
end
function Canvas.enter()
if not Canvas.available() then return false end
if not Canvas.isColour() then return false end
if not pcall(term.setGraphicsMode, 2) then return false end
local ok, mode = pcall(term.getGraphicsMode)
if not ok or mode ~= 2 then
pcall(term.setGraphicsMode, 0)
return false
end
return true
end
function Canvas.exit()
if type(term) == "table" and type(term.setGraphicsMode) == "function" then
pcall(term.setGraphicsMode, 0)
end
end
function Canvas.size()
if not Canvas.available() then return nil end
local tw, th = term.getSize()
local ok, gw, gh = pcall(term.getSize, 2)
if ok and type(gw) == "number" and type(gh) == "number" and gw >= (tw or 0) * 2 then
return gw, gh
end
if type(tw) == "number" and type(th) == "number" then
return tw * 6, th * 9
end
return nil
end
function Canvas.freeze()
if type(term.setFrozen) == "function" then pcall(term.setFrozen, true) end
end
function Canvas.unfreeze()
if type(term.setFrozen) == "function" then pcall(term.setFrozen, false) end
end
function Canvas.clear(color)
local w, h = Canvas.size()
if not w then return end
pcall(term.drawPixels, 0, 0, color or 15, w, h)
end
function Canvas.rect(x, y, width, height, color)
width = math.floor(width or 0)
height = math.floor(height or 0)
if width < 1 or height < 1 then return end
pcall(term.drawPixels, math.floor(x), math.floor(y), color, width, height)
end
function Canvas.pixel(x, y, color)
pcall(term.setPixel, math.floor(x), math.floor(y), color)
end
function Canvas.gradientV(x, y, width, height, ramp)
x = math.floor(x); y = math.floor(y)
width = math.floor(width or 0); height = math.floor(height or 0)
if width < 1 or height < 1 or type(ramp) ~= "table" or #ramp == 0 then return end
local steps = #ramp
for row = 0, height - 1 do
local index = math.floor(row / math.max(1, height - 1) * (steps - 1) + 0.5) + 1
if index < 1 then index = 1 elseif index > steps then index = steps end
pcall(term.drawPixels, x, y + row, ramp[index], width, 1)
end
end
function Canvas.cornerInsets(radius)
radius = math.max(0, math.floor(tonumber(radius) or 0))
local insets = {}
for row = 0, radius - 1 do
local dy = radius - 1 - row
local span = math.floor(math.sqrt(math.max(0, radius * radius - dy * dy)))
insets[row + 1] = radius - span
end
return insets
end
function Canvas.roundedRect(x, y, width, height, color, radius)
x = math.floor(x); y = math.floor(y)
width = math.floor(width or 0); height = math.floor(height or 0)
if width < 1 or height < 1 then return end
radius = math.max(0, math.min(math.floor(tonumber(radius) or 0), math.floor(math.min(width, height) / 2)))
if radius < 1 then return Canvas.rect(x, y, width, height, color) end
local insets = Canvas.cornerInsets(radius)
for row = 0, height - 1 do
local inset = 0
if row < radius then inset = insets[row + 1]
elseif row >= height - radius then inset = insets[height - row] end
Canvas.rect(x + inset, y + row, width - inset * 2, 1, color)
end
end
function Canvas.shadow(x, y, width, height, radius, ramp)
if type(ramp) ~= "table" or #ramp == 0 then return end
local depth = #ramp
for step = depth, 1, -1 do
local grow = step
Canvas.roundedRect(x - grow + depth, y - grow + depth + 1, width + grow * 2, height + grow * 2, ramp[step], radius + grow)
end
end
return Canvas