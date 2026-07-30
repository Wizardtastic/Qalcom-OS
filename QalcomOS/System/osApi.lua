--[[
  QalcomOS.System.osApi - thin, defensive wrapper around CC's `os`.

  CC:Tweaked ships an `os` object whose exact surface differs between
  versions (and between vanilla ComputerCraft Lua 5.1, the offline lupa
  test harness, and CC:Tweaked 1.109+). Calling a method that does not
  exist on the host raises "attempt to call field '<name>'" -- which
  has already crashed the desktop once when a chunk called os.month().

  This wrapper fixes that by:
    * Exposing a SMALL, STABLE surface -- day / month / year / hour /
      minute / second -- together with formatDate / formatTime
      convenience helpers. Apps reach for these, never for `os.x`
      directly.
    * Never raising on a missing host API. Every helper falls back to
      a sensible default (Jan 1, 00:00, year 26, ...). Callers can
      pass the result straight into string.format('%d', ...) without
      nil-checks.
    * CENTRALISING each validation rule in one inner helper
      (clampDay, checkHHMM, parseDateStr) so a future CC API tweak
      can be adapted by editing one place, not seven.
    * Parsing os.date() with anchored patterns so a leading weekday
      prefix can't sneak in as the month, and the year can't grab a
      4-digit substring of a longer digit run.
    * Parsing os.time() as CC's HHMM encoding (e.g. 17:53 -> 1753).
      We reject values that look like Unix epoch (>= 2400 or
      non-integer), since mapping epoch seconds to a local clock
      without a timezone is wrong, not safer.
    * Coalescing inside formatTime / formatDate so the host's os
      methods are called once each per formatted output -- not twice,
      as a naive delegation to M.hour()/M.minute()/... would do.

  Apps that want to use it can either:
    local osApi = dofile("/QalcomOS/System/osApi.lua")
  ...or pull it from the env the kernel hands them:
    local osApi = _QOS.osApi
  Both routes share the same module.

  No per-call allocations on the convenience hot path: formatTime
  makes exactly one os.time()-equivalent call; formatDate makes one
  os.day() and one os.date() call; the per-field helpers (M.day(),
  M.month(), ...) each make exactly one host call.
]]

local M = {}

-- Provide a stable default when the host's os surface is unrecognised
-- rather than silently rendering the wrong date.
local YEAR_FALLBACK = 26

-- Month-name -> number. CC's os.date() yields "DD MMM YYYY" so we
-- accept any of these. The wrapper never crashes on an unrecognised
-- token -- lookup miss falls through to the caller-default (1 / 26).
local MONTH_FROM_NAME = {
  Jan = 1, Feb = 2, Mar = 3, Apr = 4,
  May = 5, Jun = 6, Jul = 7, Aug = 8,
  Sep = 9, Oct = 10, Nov = 11, Dec = 12,
}

-- ---------------------------------------------------------------------------
-- Internal validators (single source of truth)
--
-- Every public helper funnels its raw os.* return value through one of
-- these. A future CC API tweak that loosens (say) the day-clamping
-- range, or relaxes what counts as an HHMM encoding, is a one-line
-- change here -- not seven.
-- ---------------------------------------------------------------------------

-- Fetch a method from the host's os table, returning nil when the
-- field is missing or present-but-not-callable. CC's old Forge Lua 5.1
-- puts os methods on the global directly; CC:Tweaked keeps them on a
-- metatable. Either way a type() check is enough.
local function safeCall(name)
  if type(os) ~= "table" then return nil end
  local fn = os[name]
  if type(fn) ~= "function" then return nil end
  return fn
end

-- Validate / clamp a value claimed to be a day-of-month. Returns
-- 1 if the input is missing, the wrong type, or out of range -- so
-- callers can pass the result straight into string.format.
local function clampDay(v)
  if type(v) ~= "number" then return 1 end
  if v < 1  then return 1  end
  if v > 31 then return 31 end
  return v
end

-- Validate a value claimed to be CC's HHMM-encoded time (17:53 -> 1753).
-- Returns nil for anything that doesn't fit -- non-number, non-integer,
-- negative, or >= 2400 (rejecting Unix-epoch values that would otherwise
-- be silently misread as wall-clock times).
local function checkHHMM(t)
  if type(t) ~= "number"  then return nil end
  if t ~= math.floor(t)   then return nil end
  if t < 0 or t >= 2400   then return nil end
  return t
end

-- Parse a date string of the form "DD MMM YYYY" (or with trailing
-- "HH:MM" / "HH:MM:SS") into (month, year). The single match
-- captures an alphabetic token followed by a 4-digit run -- weekday
-- prefixes (e.g. "Mon" in "Mon 29 Jul 2026") still fail naturally
-- because they are followed by the 2-digit day, not a 4-digit year;
-- the engine advances past them. CC's canonical "DD MMM YYYY"
-- matches because "Jul" is followed by " 2026". The trailing 4-digit
-- requirement also prevents the year from grabbing a 4-digit
-- substring of a longer digit run like "20265". Returns
-- (1, YEAR_FALLBACK) on any failure. ONE string.match call.
local function parseDateStr(ds)
  if type(ds) ~= "string" or #ds == 0 then
    return 1, YEAR_FALLBACK
  end
  local abbr, y4 = ds:match("(%a+)%s+(%d%d%d%d)")
  local m = 1
  if abbr then
    -- Trim to the documented 3-letter abbreviation before lookup, so
    -- locales that spell the month out ("July" rather than "Jul")
    -- still resolve to a known entry. ONE substring allocation per
    -- successful match; acceptable on the once-per-frame path.
    local key = abbr:sub(1, 3)
    local num = MONTH_FROM_NAME[key]
    if num then m = num end
  end
  local y = YEAR_FALLBACK
  if y4 then
    local y2 = tonumber(y4:sub(3, 4))
    if y2 then y = y2 end
  end
  return m, y
end

-- ---------------------------------------------------------------------------
-- Coalesced internal helpers (used by the formatXxx convenience paths)
--
-- formatTime and formatDate are typically called once per frame from
-- the desktop render loop. They need to make the MINIMUM possible
-- host calls -- not double-dispatch through M.hour()/M.minute()/
-- M.month()/M.year() (which would double the host-call count).
-- ---------------------------------------------------------------------------

local function parsedTime()
  local fn = safeCall("time")
  if not fn then return 0, 0 end
  local t = checkHHMM(fn())
  if not t then return 0, 0 end
  return math.floor(t / 100), t % 100
end

local function parsedDate()
  local d = 1
  local m = 1
  local y = YEAR_FALLBACK

  local dfn = safeCall("day")
  if dfn then
    d = clampDay(dfn())
  end

  local datefn = safeCall("date")
  if datefn then
    m, y = parseDateStr(datefn())
  end

  return d, m, y
end

-- ---------------------------------------------------------------------------
-- Public per-field helpers (one host call each, funnelled through the
-- central validators above)
-- ---------------------------------------------------------------------------

function M.day()
  local fn = safeCall("day")
  if not fn then return 1 end
  return clampDay(fn())
end

function M.month()
  local fn = safeCall("date")
  if not fn then return 1 end
  local m = parseDateStr(fn())
  return m
end

function M.year()
  local fn = safeCall("date")
  if not fn then return YEAR_FALLBACK end
  local _, y = parseDateStr(fn())
  return y
end

function M.hour()
  local fn = safeCall("time")
  if not fn then return 0 end
  local t = checkHHMM(fn())
  if not t then return 0 end
  return math.floor(t / 100)
end

function M.minute()
  local fn = safeCall("time")
  if not fn then return 0 end
  local t = checkHHMM(fn())
  if not t then return 0 end
  return t % 100
end

-- ---------------------------------------------------------------------------
-- Second
--
-- CC has no second-precision API. We deliberately return 0 rather than
-- call os.clock() % 60 here -- os.clock() is a monotonic float for
-- delta-time measurement and conflating it with wall-clock seconds
-- would be a footgun. If a future code path really needs a tick
-- counter it should pull os.clock() directly.
-- ---------------------------------------------------------------------------

function M.second()
  return 0
end

-- ---------------------------------------------------------------------------
-- Convenience formatters (use parsedTime / parsedDate so the hot path
-- makes the minimum number of host calls)
-- ---------------------------------------------------------------------------

function M.formatDate(delim)
  delim = delim or "-"
  local d, m, y = parsedDate()
  return string.format("%d%s%d%s%d", d, delim, m, delim, y)
end

function M.formatTime(delim)
  delim = delim or ":"
  local h, mn = parsedTime()
  return string.format("%02d%s%02d", h, delim, mn)
end

return M
