-- os/sound.lua — simple audio: PC-speaker beeps + a tiny synth.
-- Beep tones for clicks, alerts and a startup chime.

local M = {}

-- speakers: list of speaker peripherals; we just play on the first available.
local function speaker()
    if not (peripheral and peripheral.find) then return nil end
    local s = peripheral.find("speaker")
    return s
end

-- Play a tone with the speaker peripheral.
-- frequency in Hz; duration in seconds.
local function tone(freq, duration, volume)
    volume = volume or 0.6
    local s = speaker()
    if not s then return false end
    if s.playNote then
        local ok = pcall(s.playNote, math.floor(volume * 100), freq, duration)
        return ok
    end
    return false
end

function M.beep()         return tone(880,  0.05, 0.6) end  -- short click
function M.error()        return tone(440,  0.15, 0.8) end  -- descending low
function M.warn()         return tone(660,  0.12, 0.6) end
function M.alert()        return tone(220,  0.30, 1.0) end  -- big notice
function M.chime()        -- pleasant startup (C major arpeggio)
    tone(523, 0.10, 0.5)
    sleep(0.08)
    tone(659, 0.10, 0.5)
    sleep(0.08)
    tone(784, 0.18, 0.6)
end
function M.notify()       return tone(990, 0.05, 0.5) end

-- (M.click removed — the prior implementation used
--  `parallel and parallel.waitForAny(...)` which CC:T's parser rejects
--  with "syntax error near 'and'". Nothing in the OS calls M.click, so
--  deleting it is safe. The other functions above cover all UI sounds.)

return M
