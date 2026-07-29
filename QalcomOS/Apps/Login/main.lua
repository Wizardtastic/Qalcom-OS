--[[
  /QalcomOS/Apps/Login/main.lua - Centered login dialog (v0.6 auth)

  v0.6 changes (real authentication):
    * Authentication is now real. submit() reads
      /QalcomOS/Users/<name>/.profile via QalcomOS/System/profile.lua,
      rejects empty / missing profiles, rejects wrong passwords, and
      on success writes /QalcomOS/.current_user so future System /
      Desktop revs know who is signed in.
    * The profile's stored theme_idx overrides the boot-time default
      at submit, so a user who picked Dark in Settings sees the Dark
      palette immediately on their first successful login.
    * The profile's `avatar=<name>` field is honored by loadAvatar
      (falls back to the deterministic synthetic avatar when absent).
    * Profile `passwd=` accepts either 40-hex SHA-1 (compared via
      `require("sha1").hash(s)` if available) or plaintext for
      simplicity. Empty profile is treated as no-auth and rejected.
    * Inline error messages replace the placeholder hint line on
      failed submits. The next char input clears the error.

  v0.6 migration (preserved):
    * The full THEMES table, swatchHit(), swatch-rendering block,
      and swatch-click handler were removed in the prior pass when
      the theme picker moved to QalcomOS/Apps/System/.

  v0.4 features (preserved):
    * Two-line Login button widget with disabled-state styling.
    * Real password input echoed as '*'.
    * Roller-shade transition: after submit, Login shrinks from the
      BOTTOM upward over ~10 frames so the desktop underneath is
      progressively exposed.
]]

local qos       = _QOS
local kernel    = qos.kernel
local wm        = qos.wm
local themes    = dofile("/QalcomOS/System/themes.lua")
local profile   = dofile("/QalcomOS/System/profile.lua")
local DESKTOP   = "/QalcomOS/Apps/Desktop/main.lua"

-- ----------------------------------------------------------------------------
-- Theme bootstrap (file-read + spawn-arg handoff)
-- ----------------------------------------------------------------------------

-- Pick the theme index to use for the rest of Login's lifetime:
-- an explicit boot handoff wins; otherwise the .theme file. We freeze
-- the choice at spawn -- the user can't switch on the Login screen
-- anymore; that's System's job now. The profile's theme_idx, if
-- present at submit time, overrides this later in submit().
local function bootstrapThemeIdx()
  local opt = qos.options and qos.options.theme_idx
  if type(opt) == "number" and opt >= 1 and opt <= #themes.themes then
    return themes.normalize(opt)
  end
  return themes.load()
end

-- ----------------------------------------------------------------------------
-- State
-- ----------------------------------------------------------------------------

local state = {
  username    = "",
  password    = "",
  themeIdx    = bootstrapThemeIdx(),
  activeField = "user",   -- "user" | "pass"
  authError   = "",       -- "" | "no_profile" | "wrong_password"
  cachedProfileName = nil,
  cachedProfile     = nil,
}

-- 5-line avatars deterministically picked by first letter of username
-- unless the profile overrides with `avatar=smiley|hat|wizard|cube`.
local AVATARS = {
  { "  o  ", " o.o ", "  T  ", " / \\ ", "/___\\" },        -- smiley
  { "/---\\", "| o |", " o.o ", "  T  ", " \\-/ " },        -- hat
  { "  *  ", " /\\  ", "|o.o|", " \\-/ ", "/___\\" },        -- wizard
  { " ___ ", "/   \\", "|o o|", "| ^ |", "|___|" },         -- cube
}

-- Cached profile lookup. Refreshed when the username field changes.
local function cachedProfile(name)
  if state.cachedProfileName == name then
    return state.cachedProfile
  end
  local p = profile.read(name)
  state.cachedProfileName = name
  state.cachedProfile     = p
  return p
end

local function loadAvatar(name)
  if name and #name > 0 then
    local p = cachedProfile(name)
    if p and p.avatar then
      local idx = profile.AVATAR_INDEX[p.avatar]
      if idx and AVATARS[idx] then return AVATARS[idx] end
    end
    -- Existing per-user avatar file override (legacy path).
    if profile.isSafeUsername(name) then
      local path = "/QalcomOS/Users/" .. name .. "/avatar"
      if fs and fs.exists and fs.exists(path) then
        local f = fs.open(path, "r")
        if f then
          local lines = {}
          for line in f.readLine do
            if #lines >= 5 then break end
            lines[#lines + 1] = line
          end
          f.close()
          if #lines == 5 then return lines end
        end
      end
    end
  end
  if not name or name == "" then return nil end
  local h = 0
  for i = 1, #name do h = h + string.byte(name, i) end
  return AVATARS[(h % #AVATARS) + 1]
end

local function getTheme()    return themes.themes[state.themeIdx] end
local function getName()     return (getTheme()).name end

-- ----------------------------------------------------------------------------
-- Layout
-- ----------------------------------------------------------------------------
-- Dialog is 36 columns x 13 rows, centred. All coords in this layout
-- helper are body-relative (a body of 51 wide x 18 tall on an Advanced
-- Computer gives us room). When the body is smaller we clamp to row 1+
-- or col 2+ and let the bottom of the dialog crop.

local function layout()
  local w, h = term.getSize()
  local boxW, boxH = 36, 13
  local boxX = math.max(2, math.floor((w - boxW) / 2) + 1)
  local boxY = math.max(2, math.floor((h - boxH) / 2))
  return {
    w = w, h = h,
    boxX = boxX, boxY = boxY,
    boxW = boxW, boxH = boxH,
    avatarX = boxX + 2, avatarY = boxY + 2,
    userX   = boxX + 13, userY = boxY + 3,
    passX   = boxX + 13, passY = boxY + 5,
    btnX1   = boxX + 12, btnX2 = boxX + 23,
    btnY1   = boxY + 8, btnY2 = boxY + 9,
  }
end

-- ----------------------------------------------------------------------------
-- Hit-tests
-- ----------------------------------------------------------------------------

local function buttonHit(mx, my, L)
  return (mx >= L.btnX1 and mx <= L.btnX2)
     and (my == L.btnY1 or my == L.btnY2)
end

local function fieldAt(mx, my, L)
  if my == L.userY and mx >= L.userX and mx < L.boxX + L.boxW - 1 then
    return "user"
  elseif my == L.passY and mx >= L.passX and mx < L.boxX + L.boxW - 1 then
    return "pass"
  end
  return nil
end

-- ----------------------------------------------------------------------------
-- Draw
-- ----------------------------------------------------------------------------

local function drawHint(L, T)
  local hintY = L.boxY + L.boxH + 1
  if hintY > L.h then hintY = L.h end
  if hintY < L.boxY + L.boxH then return end
  term.setBackgroundColor(T.bg)
  term.setCursorPos(L.boxX, hintY)
  if state.authError == "no_profile" then
    term.setTextColor(T.accent)
    term.write("No profile for '" .. state.username .. "'.")
  elseif state.authError == "wrong_password" then
    term.setTextColor(T.accent)
    term.write("Invalid username or password.")
  else
    term.setTextColor(T.textDim)
    term.write("Tab=switch field | Enter=submit | Backspace=delete | Esc=cancel")
  end
end

local function draw()
  local L = layout()
  local T = getTheme()

  -- Backdrop.
  term.setBackgroundColor(T.bg)
  term.setTextColor(T.text)
  term.clear()

  -- Brand above the dialog.
  local brand         = "QALCOM OS"
  local brandY        = math.max(2, L.boxY - 3)
  local sub           = "Genesis II -- sign in"
  local subY          = math.max(3, L.boxY - 1)
  if brandY > 0 then
    term.setTextColor(T.accent)
    term.setCursorPos(math.floor((L.w - #brand) / 2) + 1, brandY)
    term.write(brand)
    if subY > 0 then
      term.setTextColor(T.textDim)
      term.setCursorPos(math.floor((L.w - #sub) / 2) + 1, subY)
      term.write(sub)
    end
  end

  -- Dialog backdrop (entire rectangle).
  for row = L.boxY, L.boxY + L.boxH - 1 do
    term.setCursorPos(L.boxX, row)
    term.setBackgroundColor(T.panelX)
    term.setTextColor(T.text)
    term.write(string.rep(" ", L.boxW))
  end

  -- Dialog title strip.
  term.setCursorPos(L.boxX, L.boxY)
  term.setBackgroundColor(T.panel)
  term.setTextColor(T.accent)
  term.write(string.rep(" ", L.boxW))
  local title = " Login to Qalcom OS "
  term.setCursorPos(L.boxX + math.max(1, math.floor((L.boxW - #title) / 2)), L.boxY)
  term.write(title)

  -- Avatar to the left of the username field.
  local avatar = loadAvatar(state.username)
  if avatar then
    term.setBackgroundColor(T.panelX)
    term.setTextColor(T.accent)
    for i, line in ipairs(avatar) do
      local row = L.avatarY + i - 1
      if row >= L.boxY and row < L.boxY + L.boxH then
        term.setCursorPos(L.avatarX, row)
        term.write(line)
      end
    end
  end

  -- Username row.
  term.setBackgroundColor(T.panelX)
  term.setTextColor(T.text)
  term.setCursorPos(L.boxX + 9, L.boxY + 3)
  term.write("Username:")
  term.setBackgroundColor(T.field)
  term.setTextColor(T.fieldText)
  term.setCursorPos(L.userX, L.userY)
  term.write(string.rep(" ", L.boxW - 14))
  term.setCursorPos(L.userX, L.userY)
  if #state.username > 0 then term.write(state.username) end

  -- Password row (masked with '*').
  term.setBackgroundColor(T.panelX)
  term.setTextColor(T.text)
  term.setCursorPos(L.boxX + 9, L.boxY + 5)
  term.write("Password:")
  term.setBackgroundColor(T.field)
  term.setTextColor(T.fieldText)
  term.setCursorPos(L.passX, L.passY)
  term.write(string.rep(" ", L.boxW - 14))
  term.setCursorPos(L.passX, L.passY)
  if #state.password > 0 then
    term.write(string.rep("*", #state.password))
  end

  -- Two-line Login button widget with disabled-state styling.
  local canSubmit = (#state.username > 0)
  local btnBg     = canSubmit and T.button_ok_bg  or T.button_dis_bg
  local btnFg     = canSubmit and T.button_ok_fg  or T.button_dis_fg

  term.setBackgroundColor(btnBg)
  term.setTextColor(btnFg)
  term.setCursorPos(L.btnX1, L.btnY1)
  term.write(string.rep("-", L.btnX2 - L.btnX1 + 1))

  local labelW = L.btnX2 - L.btnX1 + 1
  local label  = "[ LOGIN ]"
  if not canSubmit then label = "[ ---- ]" end
  local pad    = math.max(0, math.floor((labelW - #label) / 2))
  term.setCursorPos(L.btnX1, L.btnY2)
  term.write(string.rep(" ", pad))
  term.write(label)
  local tail = math.max(0, labelW - pad - #label)
  term.write(string.rep(" ", tail))

  -- Hint line / auth-error message below the dialog.
  drawHint(L, T)

  -- Drop the caret in the active input field.
  term.setCursorBlink(false)
  if state.activeField == "pass" then
    term.setCursorPos(L.passX + #state.password, L.passY)
  else
    term.setCursorPos(L.userX + #state.username, L.userY)
  end
  term.setBackgroundColor(T.field)
  term.setTextColor(T.fieldText)
end

-- ----------------------------------------------------------------------------
-- Submit + curtain transition
-- ----------------------------------------------------------------------------

local function curtainUp()
  local sw, sh = term.getSize()
  local cur_h = math.max(2, (qos.child and qos.child.getSize
                            and qos.child.getSize()) and (qos.child.getSize() + 1) or sh)
  if cur_h <= 2 then return end
  for tick = 1, cur_h - 2 do
    local new_h = math.max(2, cur_h - tick)
    qos.resizeSelf(new_h)
    os.sleep(0.04)
  end
end

local function submit()
  local userProfile = cachedProfile(state.username)
  if not userProfile or not userProfile.passwd or userProfile.passwd == "" then
    state.authError = "no_profile"
    draw()
    return
  end
  if not profile.authenticate(state.password, userProfile.passwd) then
    state.authError = "wrong_password"
    draw()
    return
  end

  -- Authenticated. Resolve the profile's theme_idx (clamped) and
  -- persist the active user so future revs of System/Desktop can
  -- look it up without prompting.
  state.themeIdx = profile.themeIdx(userProfile, state.themeIdx)
  state.authError = ""
  profile.writeCurrentUser(state.username)

  -- Spawn Desktop as the system process. SYSTEM_PID slot is empty
  -- because Login is a regular process.
  local L = layout()
  kernel.spawn(DESKTOP, {
    title     = "Desktop",
    isSystem  = true,
    w         = L.w,
    h         = L.h,
    theme_idx = state.themeIdx,
  })
  os.sleep(0.10)  -- let Desktop's first paint complete

  curtainUp()
end

-- ----------------------------------------------------------------------------
-- Main event loop
-- ----------------------------------------------------------------------------

draw()
local loginHover = false

while true do
  local ev, a, b, c = os.pullEvent()

  if ev == "char" then
    if type(a) == "string" and #a == 1 then
      -- Any new keystroke clears a stale auth error so the user
      -- can immediately retry without re-focusing the field.
      if state.authError ~= "" then
        state.authError = ""
      end
      if state.activeField == "pass" then
        state.password = state.password .. a
      else
        state.username = state.username .. a
        -- Username changed: drop the cached profile so the next
        -- submit re-reads the per-user file.
        state.cachedProfileName = nil
        state.cachedProfile     = nil
      end
      draw()
    end

  elseif ev == "key" then
    if a == keys.enter then
      if #state.username > 0 then submit() end
    elseif a == keys.backspace then
      if state.authError ~= "" then
        state.authError = ""
      end
      if state.activeField == "pass" then
        if #state.password > 0 then
          state.password = state.password:sub(1, #state.password - 1)
          draw()
        end
      else
        if #state.username > 0 then
          state.username = state.username:sub(1, #state.username - 1)
          state.cachedProfileName = nil
          state.cachedProfile     = nil
          draw()
        end
      end
    elseif a == keys.tab then
      state.activeField = (state.activeField == "user") and "pass" or "user"
      draw()
    elseif a == keys.escape then
      term.setBackgroundColor(colors.black)
      term.setTextColor(colors.red)
      term.clear()
      term.setCursorPos(1, 1)
      print("Login cancelled.")
      return
    end

  elseif ev == "mouse_click" then
    local L = layout()
    if buttonHit(b, c, L) then
      if #state.username > 0 then submit() end
    else
      local f = fieldAt(b, c, L)
      if f then
        state.activeField = f
        draw()
      end
    end

  elseif ev == "mouse_move" then
    local L = layout()
    local h = buttonHit(b, c, L)
    if h ~= loginHover then loginHover = h; draw() end

  elseif ev == "terminate" then
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.red)
    term.clear()
    term.setCursorPos(1, 1)
    print("Login terminated.")
    return
  end
end
