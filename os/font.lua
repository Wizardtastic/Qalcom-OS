-- os/font.lua — 5x7 ASCII bitmap font for CC:Graphics mode-2.
-- Each glyph is an array of 7 strings, each row exactly 5 chars wide.
-- Char '#' = foreground pixel (drawn), anything else = transparent.
-- Coverage: ASCII 32 (space) through 126 ('~'); the OS code uses ASCII
-- only after the CC:Graphics port, so we deliberately do not ship
-- Unicode glyphs.

local M = {}

-- Glyph table. Constructed programmatically so the file stays compact.
-- Each row is 5 chars; we encode the bitmap as decimal numbers 0..31 where
-- each bit (LSB = leftmost) is a foreground pixel. 7 rows per glyph.
local data = {
-- 32 ' '        33 '!'      34 '"'      35 '#'      36 '$'      37 '%'
    {0,0,0,0,0},  {4,4,4,4,4}, {9,9,9,0,0},{10,31,21,31,10},{17,21,4,10,21,18}, -- 32,33,34,35,36,37
-- 38 '&'      39 '''      40 '('     41 ')'     42 '*'     43 '+'
    {10,21,10,12,7}, {4,4,4,0,0},{8,12,4,12,8}, {4,12,8,12,4}, {10,4,21,4,10}, {0,4,21,4,0},
-- 44 ','     45 '-'    46 '.'    47 '/'    48 '0'     49 '1'
    {0,0,0,12,4}, {0,0,21,0,0}, {0,0,0,4,4}, {16,8,4,2,1}, {10,17,21,13,10}, {6,10,4,4,14},
-- 50 '2'    51 '3'    52 '4'    53 '5'    54 '6'    55 '7'
    {6,9,17,21,14}, {14,17,16,21,14}, {8,12,10,31,8}, {14,17,16,17,14}, {14,21,17,17,14}, {31,1,3,5,4},
-- 56 '8'     57 '9'    58 ':'   59 ';'    60 '<'    61 '='
    {14,17,17,17,14}, {14,17,17,13,14}, {0,4,0,4,0},{0,4,0,12,4}, {16,8,4,8,16}, {0,21,0,21,0},
-- 62 '>'   63 '?'   64 '@'   65 'A'   66 'B'    67 'C'
    {4,8,16,8,4}, {14,17,1,0,4}, {14,17,21,21,14}, {10,17,17,31,17}, {30,17,17,17,14}, {14,17,16,16,17},
-- 68 'D'    69 'E'    70 'F'   71 'G'    72 'H'    73 'I'
    {30,17,17,17,30}, {31,16,16,16,16}, {31,16,16,16,16}, {14,17,16,21,15}, {17,17,31,17,17}, {14,4,4,4,14},
-- 74 'J'    75 'K'    76 'L'   77 'M'    78 'N'    79 'O'
    {7,9,1,17,14}, {17,18,16,18,17}, {16,16,16,16,31}, {17,27,21,17,17}, {17,25,21,19,17}, {14,17,17,17,14},
-- 80 'P'     81 'Q'    82 'R'   83 'S'    84 'T'    85 'U'
    {30,17,17,16,16}, {14,17,17,21,15}, {30,17,17,18,17}, {14,16,14,1,30}, {31,4,4,4,4}, {17,17,17,17,14},
-- 86 'V'    87 'W'    88 'X'   89 'Y'    90 'Z'    91 '['
    {17,17,17,10,4}, {17,17,21,21,17}, {17,10,4,10,17}, {21,10,4,4,4}, {31,1,4,8,31}, {14,8,8,8,14},
-- 92 '\'    93 ']'    94 '^'   95 '_'    96 '`'    97 'a'
    {1,2,4,8,16}, {14,4,4,4,14}, {4,10,17,0,0}, {0,0,0,0,31}, {4,8,4,0,0}, {0,14,17,17,15},
-- 98 'b'     99 'c'   100 'd'  101 'e'   102 'f'   103 'g'
    {16,30,17,17,14}, {0,14,16,16,17}, {0,14,17,17,30}, {0,14,17,16,31}, {4,21,17,17,14}, {0,28,4,4,7},
-- 104 'h'   105 'i'   106 'j'  107 'k'    108 'l'   109 'm'
    {16,30,17,17,17}, {0,12,4,4,14}, {0,7,1,17,14}, {16,17,20,18,17}, {4,4,4,4,14}, {0,21,27,17,17},
-- 110 'n'   111 'o'   112 'p'  113 'q'    114 'r'   115 's'
    {0,30,17,17,17}, {0,14,17,17,14}, {0,30,17,16,16}, {0,15,17,13,1}, {0,22,4,4,4}, {0,14,16,1,30},
-- 116 't'   117 'u'   118 'v'  119 'w'    120 'x'   121 'y'
    {0,4,14,4,4}, {0,17,17,17,13}, {0,17,17,10,4}, {0,17,21,17,17}, {0,17,10,4,8,16}, {0,17,17,13,1,30},
-- 122 'z'    123 '{'   124 '|'  125 '}'    126 '~'
    {31,1,4,8,31}, {8,12,4,12,8}, {0,4,4,4,4,4}, {4,4,8,12,12}, {4,12,4,2,1},
}

-- Expand compact decimal rows into 7 strings of "####" per char.
local glyphs = {}
for code = 32, 126 do
    local idx = code - 32
    local rowBits = data[idx + 1] or {0,0,0,0,0}
    local rows = {}
    for r = 0, 6 do
        local bits = rowBits[r + 1] or 0
        local row = ""
        -- Render left-to-right: bit 4 = leftmost pixel, bit 0 = rightmost.
        -- The mapping here is the standard 5x7 "left-bit-is-leftmost".
        -- Some rows in data have 6 values (e.g. some lowercase descenders).
        -- We tolerate both by indexing past a missing entry safely.
        for c = 4, 0, -1 do
            local bit = bit32 and bit32.btest(bits, c) and 1 or 0
            row = row .. (bit == 1 and "#" or " ")
        end
        rows[#rows+1] = row
    end
    glyphs[code] = rows
end
glyphs[9]  = { "     ","     ","     ","     ","     ","     ","     " }  -- \t as space
glyphs[10] = { "     ","     ","     ","     ","     ","     ","     " }  -- \n as space
glyphs[13] = glyphs[10]

M.glyphs   = glyphs
M.rowCount = 7                -- height in base 5x7 cells
M.colCount = 5                -- width  in base 5x7 cells

-- Pick the nearest integer scale that fits approx the requested pixel size.
function M.scaleForSize(size)
    size = tonumber(size) or 14
    if size <= 6  then return 1 end
    if size <= 12 then return 1 end
    if size <= 18 then return 2 end
    if size <= 27 then return 3 end
    return 4
end

-- Measure a string: returns pixel width / height for the given scale.
function M.measure(str, size)
    local s = M.scaleForSize(size)
    -- Single column of width 5 with 1 pixel tracking = 6 px effective.
    -- Each advanced char gets +1 px for the rightmost tracking pixel.
    local cols = 0
    for _ in str:gmatch(".") do cols = cols + 1 end
    local w = cols * 6 * s
    local h = 7 * s
    -- add ascender / descender slop
    return w, h
end

return M
