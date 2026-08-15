local Display = {}
local function hasFunction(name)
return type(term) == "table" and type(term[name]) == "function"
end
function Display.supportsPalette()
return hasFunction("setPaletteColor")
end
function Display.supportsNativePalette()
return hasFunction("nativePaletteColor")
end
function Display.supportsGraphics()
if not hasFunction("setGraphicsMode") or not hasFunction("getGraphicsMode") then
return false
end
local ok = pcall(term.getGraphicsMode)
return ok == true
end
function Display.mode()
if Display.supportsGraphics() then return "graphics256" end
if Display.supportsPalette() then return "text-fluent" end
return "text"
end
function Display.textSize()
if type(term) ~= "table" or type(term.getSize) ~= "function" then return nil end
return term.getSize()
end
function Display.pixelSize()
if not Display.supportsGraphics() then return nil end
local ok, w, h = pcall(term.getSize, 2)
if ok and w and h then return w, h end
return nil
end
return Display