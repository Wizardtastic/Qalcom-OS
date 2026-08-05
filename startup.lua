-- Qalcom OS bootloader
-- Install this file as /startup.lua on a CC:T computer.

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
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.red)
    term.clear()
    term.setCursorPos(1, 1)
    print("Qalcom OS recovery")
    print(string.rep("-", 32))
    printError(tostring(err))
    print("")
    print("The Qalcom supervisor stopped safely.")
    print("Type reboot to try again, or shell to enter CraftOS.")
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
