-- os/text.lua — text measurement + word breaking helpers.
-- Provides the higher-level layout primitives apps will use on top of gfx.

local gfx = require("os.gfx")
local M = {}

-- Formats text so it wraps inside `maxWidth` pixels, returning a list of lines.
-- opts may include {font="Arial", size=14, style="bold"}.
function M.wrap(str, maxWidth, opts)
    local out = {}
    if type(str) ~= "string" or #str == 0 then return out end
    -- Split on whitespace, rebuild lines greedily.
    local cur, curW = "", 0
    local pen = 1
    while pen <= #str do
        local s, e = str:find("[ \t]+", pen)  -- find next whitespace
        local wordEnd = (s and s - 1) or #str
        local word = str:sub(pen, wordEnd)
        local w, _h = gfx.textSize(word, opts)
        if cur == "" then
            cur, curW = word, w
        elseif curW + 4 + w <= maxWidth then
            cur = cur .. " " .. word
            curW = curW + 4 + w
        else
            table.insert(out, cur)
            cur, curW = word, w
        end
        if not s then break end
        pen = e + 1
        -- Handle \n explicitly
        if str:sub(pen, pen) == "\n" then
            table.insert(out, cur)
            cur, curW = "", 0
            pen = pen + 1
        end
    end
    if #cur > 0 then table.insert(out, cur) end
    return out
end

-- Adapts wrap to a list of vertical offsets given a starting y.
function M.layoutLines(str, x, y, maxWidth, lineH, opts, col)
    local lines = M.wrap(str, maxWidth, opts)
    for i, line in ipairs(lines) do
        gfx.text(line, x, y + (i-1)*lineH, col, opts)
    end
    return #lines, y + #lines * lineH
end

-- Centers text horizontally within a rectangle. Returns the new x.
function M.centerX(text, rectX, rectW, opts)
    local w = gfx.textSize(text, opts)
    return rectX + math.floor((rectW - w) / 2 + 0.5)
end

-- Ellipsize long text to fit within `maxW`. Returns possibly-trimmed text
-- that will measure <= maxW + ellipsis overhead.
function M.ellipsize(text, maxW, opts)
    if maxW <= 0 then return "" end
    local w = gfx.textSize(text, opts)
    if w <= maxW then return text end
    local lo, hi = 1, #text
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        local candidate = text:sub(1, mid) .. "…"
        if gfx.textSize(candidate, opts) <= maxW then
            lo = mid
        else
            hi = mid - 1
        end
    end
    return text:sub(1, lo) .. "…"
end

return M
