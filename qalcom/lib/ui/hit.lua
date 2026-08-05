local Hit = {}

function Hit.inBounds(mouseX, mouseY, x, y, width, height)
    return tonumber(mouseX) and tonumber(mouseY) and tonumber(x) and tonumber(y)
        and mouseX >= x and mouseX < x + width
        and mouseY >= y and mouseY < y + (height or 1)
end

function Hit.button(buttons, mouseX, mouseY)
    for index, button in ipairs(buttons or {}) do
        if Hit.inBounds(mouseX, mouseY, button.x, button.y, button.width, button.height or 1) then
            return button, index
        end
    end
    return nil
end

return Hit
