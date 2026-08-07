local Crypto = {}

-- CC:Tweaked does not expose a native cryptographic API. This module uses
-- SHA-256/HMAC as a conservative, dependency-free compatibility layer. It is
-- intended for authenticated datagrams, not protection from a compromised host.
local MOD = 4294967296
local bit = bit32
local unpack = table.unpack or unpack

local function u32(value)
    -- Short-circuit the common case (already a 32-bit word) and keep the
    -- modulo path for larger sums: bit32.band semantics on values >= 2^32 are
    -- not guaranteed across every CC:T/Cobalt runtime.
    if value >= 0 and value < MOD then return value end
    value = value % MOD
    if value < 0 then value = value + MOD end
    return value
end

local function bitOp(operation, left, right)
    if bit and bit[operation] then return bit[operation](left, right) end
    local result, place = 0, 1
    left, right = u32(left), u32(right)
    for _ = 1, 32 do
        local a, b = left % 2, right % 2
        local enabled = operation == "band" and a == 1 and b == 1
            or operation == "bor" and (a == 1 or b == 1)
            or operation == "bxor" and a ~= b
        if enabled then result = result + place end
        left = math.floor(left / 2)
        right = math.floor(right / 2)
        place = place * 2
    end
    return u32(result)
end

local function band(a, b) return bitOp("band", a, b) end
local function bor(a, b) return bitOp("bor", a, b) end
local function bxor(a, b, ...)
    local result = bitOp("bxor", a, b)
    for index = 1, select("#", ...) do result = bitOp("bxor", result, select(index, ...)) end
    return result
end
local function bnot(value) return u32(MOD - 1 - u32(value)) end
local function lshift(value, amount)
    if bit and bit.lshift then return bit.lshift(value, amount) end
    return u32(u32(value) * (2 ^ amount))
end
local function rshift(value, amount)
    if bit and bit.rshift then return bit.rshift(value, amount) end
    return math.floor(u32(value) / (2 ^ amount))
end
local function rrotate(value, amount)
    if bit and bit.rrotate then return bit.rrotate(value, amount) end
    amount = amount % 32
    if amount == 0 then return u32(value) end
    return bor(rshift(value, amount), lshift(value, 32 - amount))
end

-- Fixed-arity additions for the SHA-256 inner loop. Each operand is already
-- a 32-bit word, so a single modulo at the end is equivalent to the previous
-- per-step reduction and avoids variadic select() overhead in the hot path.
local function add2(a, b) return u32(a + b) end
local function add4(a, b, c, d) return u32(a + b + c + d) end
local function add5(a, b, c, d, e) return u32(a + b + c + d + e) end

local function wordFromBytes(text, index)
    local a = string.byte(text, index) or 0
    local b = string.byte(text, index + 1) or 0
    local c = string.byte(text, index + 2) or 0
    local d = string.byte(text, index + 3) or 0
    return u32(a * 16777216 + b * 65536 + c * 256 + d)
end

local function wordToBytes(value)
    value = u32(value)
    local a = math.floor(value / 16777216) % 256
    local b = math.floor(value / 65536) % 256
    local c = math.floor(value / 256) % 256
    local d = value % 256
    return string.char(a, b, c, d)
end

local INITIAL = {
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
}
local ROUND = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b,
    0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01,
    0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7,
    0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152,
    0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
    0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819,
    0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116, 0x1e376c08,
    0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f,
    0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

function Crypto.sha256(message)
    message = tostring(message or "")
    local bitLength = #message * 8
    -- Append 0x80, enough zero padding so the total is 64 mod 64, then the
    -- 64-bit length. Computing the padding once avoids char-by-char string
    -- growth that would otherwise be quadratic on larger messages.
    local zeros = (64 - ((#message + 9) % 64)) % 64
    local padded = message .. string.char(128) .. string.rep(string.char(0), zeros)
    local high = math.floor(bitLength / 4294967296)
    local low = bitLength % 4294967296
    padded = padded .. wordToBytes(high) .. wordToBytes(low)
    local state = {}
    for index, value in ipairs(INITIAL) do state[index] = value end

    for offset = 1, #padded, 64 do
        local schedule = {}
        for index = 0, 15 do schedule[index] = wordFromBytes(padded, offset + index * 4) end
        for index = 16, 63 do
            local value = schedule[index - 15]
            local small0 = bxor(rrotate(value, 7), rrotate(value, 18), rshift(value, 3))
            value = schedule[index - 2]
            local small1 = bxor(rrotate(value, 17), rrotate(value, 19), rshift(value, 10))
            schedule[index] = add4(schedule[index - 16], small0, schedule[index - 7], small1)
        end
        local a, b, c, d = state[1], state[2], state[3], state[4]
        local e, f, g, h = state[5], state[6], state[7], state[8]
        for index = 0, 63 do
            local choice = bxor(band(e, f), band(bnot(e), g))
            local majority = bxor(band(a, b), band(a, c), band(b, c))
            local big0 = bxor(rrotate(a, 2), rrotate(a, 13), rrotate(a, 22))
            local big1 = bxor(rrotate(e, 6), rrotate(e, 11), rrotate(e, 25))
            local temp1 = add5(h, big1, choice, ROUND[index + 1], schedule[index])
            local temp2 = add2(big0, majority)
            h, g, f, e = g, f, e, add2(d, temp1)
            d, c, b, a = c, b, a, add2(temp1, temp2)
        end
        state[1] = add2(state[1], a)
        state[2] = add2(state[2], b)
        state[3] = add2(state[3], c)
        state[4] = add2(state[4], d)
        state[5] = add2(state[5], e)
        state[6] = add2(state[6], f)
        state[7] = add2(state[7], g)
        state[8] = add2(state[8], h)
    end
    local result = {}
    for index = 1, 8 do result[#result + 1] = wordToBytes(state[index]) end
    return table.concat(result)
end

function Crypto.hmac(key, message)
    key, message = tostring(key or ""), tostring(message or "")
    if #key > 64 then key = Crypto.sha256(key) end
    key = key .. string.rep(string.char(0), 64 - #key)
    local inner, outer = {}, {}
    for index = 1, 64 do
        local value = string.byte(key, index)
        inner[index] = bxor(value, 0x36)
        outer[index] = bxor(value, 0x5c)
    end
    return Crypto.sha256(string.char(unpack(outer)) .. Crypto.sha256(string.char(unpack(inner)) .. message))
end

function Crypto.hkdf(secret, salt, info, length)
    secret, salt, info = tostring(secret or ""), tostring(salt or ""), tostring(info or "")
    length = math.max(1, math.min(1024, math.floor(tonumber(length) or 32)))
    local prk = Crypto.hmac(salt ~= "" and salt or string.rep(string.char(0), 32), secret)
    local output, previous = {}, ""
    local blocks = math.ceil(length / 32)
    for index = 1, blocks do
        previous = Crypto.hmac(prk, previous .. info .. string.char(index))
        output[#output + 1] = previous
    end
    return table.concat(output):sub(1, length)
end

function Crypto.constantTimeEqual(left, right)
    left, right = tostring(left or ""), tostring(right or "")
    if #left ~= #right then return false end
    local difference = 0
    for index = 1, #left do difference = difference + math.abs(string.byte(left, index) - string.byte(right, index)) end
    return difference == 0
end

-- Precomputed hex/nibble tables replace per-byte string.format/tonumber
-- calls in the transport hot path.
local HEX = {}
for index = 0, 255 do HEX[index] = string.format("%02x", index) end
local HEXVAL = {}
for index = 48, 57 do HEXVAL[index] = index - 48 end
for index = 97, 102 do HEXVAL[index] = index - 87 end
for index = 65, 70 do HEXVAL[index] = index - 55 end

function Crypto.hex(value)
    local result = {}
    local text = tostring(value or "")
    for index = 1, #text do result[index] = HEX[string.byte(text, index)] end
    return table.concat(result)
end

function Crypto.unhex(value)
    value = tostring(value or "")
    if #value % 2 ~= 0 then return nil end
    local result = {}
    local count = 0
    for index = 1, #value, 2 do
        local high = HEXVAL[string.byte(value, index)]
        local low = HEXVAL[string.byte(value, index + 1)]
        if not high or not low then return nil end
        count = count + 1
        result[count] = string.char(high * 16 + low)
    end
    return table.concat(result)
end

local function xorBytes(left, right)
    -- XOR 64 bytes per string.char call instead of one tiny string per byte.
    local parts, index = {}, 1
    while index <= #left do
        local chunk = {}
        local count = 0
        for offset = 1, 64 do
            if index > #left then break end
            count = count + 1
            chunk[count] = bxor(string.byte(left, index), string.byte(right, index) or 0)
            index = index + 1
        end
        parts[#parts + 1] = string.char(unpack(chunk))
    end
    return table.concat(parts)
end

function Crypto.seal(key, nonce, plaintext, associatedData)
    key, nonce, plaintext, associatedData = tostring(key or ""), tostring(nonce or ""), tostring(plaintext or ""), tostring(associatedData or "")
    local encryptionKey = Crypto.hkdf(key, nonce, "qalcom encryption", 32)
    local macKey = Crypto.hkdf(key, nonce, "qalcom authentication", 32)
    -- Each keystream block is exactly 32 bytes, so track the running length
    -- instead of re-concatenating the whole stream on every iteration.
    local stream, counter, length = {}, 0, 0
    while length < #plaintext do
        stream[#stream + 1] = Crypto.hmac(encryptionKey, nonce .. string.char(math.floor(counter / 16777216) % 256, math.floor(counter / 65536) % 256, math.floor(counter / 256) % 256, counter % 256))
        counter = counter + 1
        length = length + 32
    end
    local ciphertext = xorBytes(plaintext, table.concat(stream):sub(1, #plaintext))
    local tag = Crypto.hmac(macKey, associatedData .. nonce .. ciphertext):sub(1, 16)
    return ciphertext, tag
end

function Crypto.open(key, nonce, ciphertext, tag, associatedData)
    key, nonce, ciphertext, tag, associatedData = tostring(key or ""), tostring(nonce or ""), tostring(ciphertext or ""), tostring(tag or ""), tostring(associatedData or "")
    local macKey = Crypto.hkdf(key, nonce, "qalcom authentication", 32)
    local expected = Crypto.hmac(macKey, associatedData .. nonce .. ciphertext):sub(1, 16)
    if not Crypto.constantTimeEqual(expected, tag) then return nil, "Authentication failed" end
    local encryptionKey = Crypto.hkdf(key, nonce, "qalcom encryption", 32)
    local stream, counter, length = {}, 0, 0
    while length < #ciphertext do
        stream[#stream + 1] = Crypto.hmac(encryptionKey, nonce .. string.char(math.floor(counter / 16777216) % 256, math.floor(counter / 65536) % 256, math.floor(counter / 256) % 256, counter % 256))
        counter = counter + 1
        length = length + 32
    end
    return xorBytes(ciphertext, table.concat(stream):sub(1, #ciphertext))
end

return Crypto
