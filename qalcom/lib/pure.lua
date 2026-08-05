local Pure = {}

function Pure.clampInteger(value, minimum, maximum, fallback)
    local number = tonumber(value)
    if not number then number = fallback end
    number = math.floor(number or minimum)
    if number < minimum then return minimum end
    if number > maximum then return maximum end
    return number
end

function Pure.normalizePath(path)
    local result = {}
    for part in tostring(path or ""):gmatch("[^/]+") do
        if part == ".." then
            if #result > 0 then table.remove(result) end
        elseif part ~= "." and part ~= "" then
            result[#result + 1] = part
        end
    end
    if #result == 0 then return "/" end
    return "/" .. table.concat(result, "/")
end

function Pure.absolutePath(base, path)
    path = tostring(path or "")
    if path:sub(1, 1) == "/" then return Pure.normalizePath(path) end
    return Pure.normalizePath(tostring(base or "/") .. "/" .. path)
end

function Pure.validateUsername(username, maximum)
    maximum = maximum or 24
    return type(username) == "string"
        and #username >= 2
        and #username <= maximum
        and username:match("^[%w_%-]+$") ~= nil
end

function Pure.validateAccountRecord(account)
    return type(account) == "table"
        and type(account.username) == "string"
        and type(account.salt) == "string"
        and type(account.digest) == "string"
end

function Pure.retainLines(lines, limit)
    local retained = {}
    limit = Pure.clampInteger(limit, 1, math.max(1, #lines), #lines)
    local first = math.max(1, #lines - limit + 1)
    for index = first, #lines do retained[#retained + 1] = lines[index] end
    return retained
end

function Pure.fitWindow(screenWidth, screenHeight, desiredWidth, desiredHeight, minimumWidth, minimumHeight, margin)
    margin = margin or 1
    local availableWidth = math.max(1, screenWidth - margin * 2)
    local availableHeight = math.max(1, screenHeight - margin * 2)
    local width = math.min(desiredWidth, math.max(1, math.min(minimumWidth, availableWidth)))
    local height = math.min(desiredHeight, math.max(1, math.min(minimumHeight, availableHeight)))
    local x = math.max(margin, math.floor((screenWidth - width) / 2) + 1)
    local y = math.max(margin, math.floor((screenHeight - height) / 2) + 1)
    return x, y, width, height
end

return Pure
