local kernel = "/qalcom/kernel/init.lua"
if not fs.exists(kernel) then
term.clear()
term.setCursorPos(1, 1)
printError("Qalcom OS is not installed.")
print("Missing: " .. kernel)
print("Restore the /qalcom directory, then reboot.")
return
end
local ok, err = pcall(function()
dofile(kernel)
end)
if not ok then
if term.nativePaletteColor and term.setPaletteColor then
for _, slot in ipairs({
colors.white, colors.orange, colors.magenta, colors.lightBlue,
colors.yellow, colors.lime, colors.pink, colors.gray,
colors.lightGray, colors.cyan, colors.purple, colors.blue,
colors.brown, colors.green, colors.red, colors.black,
}) do
local restored, r, g, b = pcall(term.nativePaletteColor, slot)
if restored and r then pcall(term.setPaletteColor, slot, r, g, b) end
end
end
local width = select(1, term.getSize())
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(2, 2)
term.setTextColor(colors.red)
term.write("Qalcom OS  -  Recovery")
term.setCursorPos(2, 3)
term.setTextColor(colors.gray)
term.write(string.rep("-", math.min(math.max(1, width - 2), 40)))
term.setCursorPos(2, 5)
term.setTextColor(colors.lightGray)
term.write("The Qalcom supervisor stopped safely.")
term.setCursorPos(2, 6)
term.setTextColor(colors.gray)
term.write("Details:")
term.setCursorPos(2, 7)
term.setTextColor(colors.red)
term.write(tostring(err):sub(1, math.max(1, width - 2)))
term.setCursorPos(2, 9)
term.setTextColor(colors.white)
term.write("Type 'reboot' to try again, or 'shell' for CraftOS.")
term.setCursorPos(1, 11)
term.setTextColor(colors.white)
while true do
write("> ")
local command = read()
if command == "reboot" then
os.reboot()
elseif command == "shell" then
shell.run("/rom/programs/shell.lua")
break
else
print("Use reboot or shell.")
end
end
end