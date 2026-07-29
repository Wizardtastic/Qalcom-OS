--[[
  /QalcomOS/Apps/Login/main.lua - Centered login dialog (v0.7)

  v0.7 (this revision) adds a first-launch Create Profile flow:
    * On spawn, the app picks its mode from profile.hasAnyUser():
      no users at all -> "create" mode (CreateProfile), otherwise
      "login" mode. This is what makes a fresh install bootable.
    * "create" mode renders the same 36x13 dialog with an extra
      "Confirm Password" row, a different title strip ("Create your
      Qalcom account"), and a "[ CREATE ]" button instead of "[ LOGIN ]".
    * Validation in create mode: isSafeUsername, username not already
      taken, password >= profile.MIN_PASSWORD_LEN, confirm matches.
      Each failure has its own error code so the UI can spell out
      what to fix.
    * On successful create, the chunk switches to "login" mode with
      the username pre-filled, the password cleared, and a transient
      green "Profile created. Please sign in." hint.
    * Both modes have a "< Sign in instead >" / "< Create an account >"
      link on the last row of the dialog so an existing user can
      add another account from the Login screen.
    * Password storage happens in profile.create() (sha1 if available,
      plaintext otherwise), matching profile.authenticate().

  v0.6 features (preserved):
    * Real authentication against /QalcomOS/Users/<name>/.profile via
      QalcomOS/System/profile.lua. Wrong / missing profiles are
      rejected with mode-specific error hints.
    * The .theme file is read at spawn via themes.load(); an explicit
      theme_idx option (qos.options.theme_idx) overrides it.
    * Profile's theme_idx, when present at submit, overrides the
      boot-time default so a user who picks Dark in Settings sees
      Dark immediately on their first successful login.
    * Two-line Login button widget with disabled-state styling.
    * Real password input echoed as '*'.
    * Roller-shade transition: after submit, Login shrinks from the
      BOTTOM upward so the desktop underneath is progressively exposed.

  v0.6 migration (preserved):
    * The full THEMES table, swatchHit(), swatch-rendering block,
      and swatch-click handler were removed when the theme picker
      moved to QalcomOS/Apps/System/. Login no longer offers theme
      selection; that's System's job.
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

-- Pick the initial mode. First-launch (no users yet) drops into the
-- CreateProfile flow so the user can register themselves before any
-- auth can possibly succeed. Once at least one profile exists, fall
-- back to Login mode.
local function bootstrapMode()
  if profile.hasAnyUser() then return "login" end
  return "create"
end

-- ----------------------------------------------------------------------------
-- State
-- ----------------------------------------------------------------------------

local state = {
  mode             = bootstrapMode(),  -- "login" | "create"
  username         = "",
  password         = "",
  confirmPassword  = "",               -- create mode only
  themeIdx         = bootstrapThemeIdx(),
  activeField      = "user",           -- "user" | "pass" | "confirm"
  loginError       = "",               -- "" | "no_profile" | "wrong_password" | "create_succeeded"
  createError      = "",               -- "" | "invalid_username" | "username_taken"
                                        --    | "password_too_short" | "passwords_dont_match"
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

local function getTheme() return themes.themes[state.themeIdx] end

-- ----------------------------------------------------------------------------
-- Layout
-- ----------------------------------------------------------------------------
-- Dialog is 36 columns x 13 rows, centred. Both modes share the same
-- box dimensions so a mode switch doesn't cause a jarring redraw.
-- Coords are body-relative. When the body is smaller than the box
-- we clamp to row 1+ / col 2+ and let the bottom of the dialog crop.

local function layout()
  local w, h = term.getSize()
  local boxW, boxH = 36, 13
  local boxX = math.max(2, math.floor((w - boxW) / 2) + 1)
  -- Anchor the dialog at the TOP of the body. Centering was tried in
  -- earlier versions and left a 1-row 'ramp' of empty T.bg between the
  -- WM title bar and the dialog title strip on typical 51x19 screens.
  -- The brand/sub rows that used to live in that ramp were broken
  -- (their Y math collapsed into the dialog rows for body_h < 20),
  -- so we anchor at row 1 and let body's clear() paint the rest.
  local boxY = 1
  local out = {
    w = w, h = h,
    boxX = boxX, boxY = boxY,
    boxW = boxW, boxH = boxH,
    avatarX = boxX + 2, avatarY = boxY + 2,
    userX   = boxX + 13, userY   = boxY + 3,
    passX   = boxX + 13, passY   = boxY + 5,
    btnX1   = boxX + 12, btnX2   = boxX + 23,
    linkY   = boxY + 12,
  }
  if state.mode == "create" then
    out.confirmX = boxX + 13
    out.confirmY = boxY + 7
    out.btnY1 = boxY + 9
    out.btnY2 = boxY + 10
    out.linkLabel = "< Sign in instead >"
  else
    out.btnY1 = boxY + 8
    out.btnY2 = boxY + 9
    out.linkLabel = "< Create an account >"
  end
  out.linkX1 = boxX + math.floor((boxW - #out.linkLabel) / 2) + 1
  out.linkX2 = out.linkX1 + #out.linkLabel - 1
  return out
end

-- ----------------------------------------------------------------------------
-- Hit-tests
-- ----------------------------------------------------------------------------

local function buttonHit(mx, my, L)
  return (mx >= L.btnX1 and mx <= L.btnX2)
     and (my == L.btnY1 or my == L.btnY2)
end

local function fieldAt(mx, my, L)
  local right = L.boxX + L.boxW - 1
  if my == L.userY and mx >= L.userX and mx < right then
    return "user"
  elseif my == L.passY and mx >= L.passX and mx < right then
    return "pass"
  elseif state.mode == "create"
     and my == L.confirmY and mx >= L.confirmX and mx < right then
    return "confirm"
  end
  return nil
end

local function linkHit(mx, my, L)
  return my == L.linkY and mx >= L.linkX1 and mx <= L.linkX2
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

  if state.mode == "login" then
    if state.loginError == "no_profile" then
      term.setTextColor(T.accent)
      term.write("No profile for '" .. state.username .. "'.")
    elseif state.loginError == "wrong_password" then
      term.setTextColor(T.accent)
      term.write("Invalid username or password.")
    elseif state.loginError == "type_password" then
      term.setTextColor(T.accent)
      term.write("Please type your password to sign in.")
    elseif state.loginError == "create_succeeded" then
      term.setTextColor(T.okText)
      term.write("Profile created. Please sign in.")
    else
      term.setTextColor(T.textDim)
      term.write("Tab=switch field | Enter=submit | Backspace=delete | Esc=cancel")
    end
  else -- create
    if state.createError == "invalid_username" then
      term.setTextColor(T.accent)
      term.write("Username must be 1-16 chars: letters, digits, _ or -.")
    elseif state.createError == "username_taken" then
      term.setTextColor(T.accent)
      term.write("That username is already taken.")
    elseif state.createError == "password_too_short" then
      term.setTextColor(T.accent)
      term.write("Password must be at least "
                 .. tostring(profile.MIN_PASSWORD_LEN) .. " characters.")
    elseif state.createError == "passwords_dont_match" then
      term.setTextColor(T.accent)
      term.write("Passwords do not match.")
    elseif state.createError == "storage_error" then
      term.setTextColor(T.accent)
      term.write("Could not save profile (disk error).")
    else
      term.setTextColor(T.textDim)
      term.write("Tab=switch field | Enter=create | Backspace=delete | Esc=cancel")
    end
  end
end

local function draw()
  local L = layout()
  local T = getTheme()

  -- Backdrop.
  term.setBackgroundColor(T.bg)
  term.setTextColor(T.text)
  term.clear()

  -- Dialog backdrop.
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
  -- Codename is folded into the title strip (we removed the
  -- decorative brand/sub rows above the dialog because their Y
  -- math collided with the dialog on body_h < 20; the strip is
  -- where orientation info lives now).
  local codename = _QOS_CODENAME or "Qalcom OS"
  local title = state.mode == "create"
                and (" " .. codename .. " -- Create account ")
                or  (" " .. codename .. " -- Sign in ")
  term.setCursorPos(L.boxX + math.max(1, math.floor((L.boxW - #title) / 2)),
                    L.boxY)
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

  -- Confirm row (create mode only).
  if state.mode == "create" then
    term.setBackgroundColor(T.panelX)
    term.setTextColor(T.text)
    term.setCursorPos(L.boxX + 9, L.boxY + 7)
    term.write("Confirm:")
    term.setBackgroundColor(T.field)
    term.setTextColor(T.fieldText)
    term.setCursorPos(L.confirmX, L.confirmY)
    term.write(string.rep(" ", L.boxW - 14))
    term.setCursorPos(L.confirmX, L.confirmY)
    if #state.confirmPassword > 0 then
      term.write(string.rep("*", #state.confirmPassword))
    end
  end

  -- Button widget with disabled-state styling.
  local canSubmit
  if state.mode == "create" then
    canSubmit = (#state.username > 0)
                and (#state.password >= profile.MIN_PASSWORD_LEN)
                and (state.password == state.confirmPassword)
  else
    canSubmit = (#state.username > 0)
  end
  local btnBg = canSubmit and T.button_ok_bg  or T.button_dis_bg
  local btnFg = canSubmit and T.button_ok_fg  or T.button_dis_fg

  term.setBackgroundColor(btnBg)
  term.setTextColor(btnFg)
  term.setCursorPos(L.btnX1, L.btnY1)
  term.write(string.rep("-", L.btnX2 - L.btnX1 + 1))

  local labelW = L.btnX2 - L.btnX1 + 1
  local label
  if state.mode == "create" then
    label = canSubmit and "[ CREATE ]" or "[ ---- ]"
  else
    label = canSubmit and "[ LOGIN ]"  or "[ ---- ]"
  end
  local pad = math.max(0, math.floor((labelW - #label) / 2))
  term.setCursorPos(L.btnX1, L.btnY2)
  term.write(string.rep(" ", pad))
  term.write(label)
  local tail = math.max(0, labelW - pad - #label)
  term.write(string.rep(" ", tail))

  -- Mode-switch link on the last row of the box.
  term.setBackgroundColor(T.panelX)
  term.setTextColor(T.accent)
  term.setCursorPos(L.linkX1, L.linkY)
  term.write(L.linkLabel)

  -- Hint / error message below the dialog.
  drawHint(L, T)

  -- Drop the caret in the active input field.
  term.setCursorBlink(false)
  if state.activeField == "confirm" and state.mode == "create" then
    term.setCursorPos(L.confirmX + #state.confirmPassword, L.confirmY)
  elseif state.activeField == "pass" then
    term.setCursorPos(L.passX + #state.password, L.passY)
  else
    term.setCursorPos(L.userX + #state.username, L.userY)
  end
  term.setBackgroundColor(T.field)
  term.setTextColor(T.fieldText)
end

-- ----------------------------------------------------------------------------
-- Submit / create / curtain transition
-- ----------------------------------------------------------------------------

local function curtainUp()
  -- The original expression used the FIRST multi-value of
  -- qos.child.getSize() (window WIDTH, e.g. 51 on a 51x19 screen)
  -- as if it were the body height, producing cur_h = 52 and making
  -- resizeSelf GROW the window to 51 rows off-screen before the
  -- curtain could shrink it. Unpack both returns properly.
  --
  -- Guard against the child having been torn down (test runs,
  -- post-destroy race) -- without the guard, missing qos.child
  -- would crash the chunk and leave the user in Recovery.
  if not (qos.child and qos.child.getSize) then return end
  local _, body_h = qos.child.getSize()
  local cur_h      = math.max(2, body_h + 1)
  if cur_h <= 2 then return end
  for tick = 1, cur_h - 2 do
    local new_h = math.max(2, cur_h - tick)
    qos.resizeSelf(new_h)
    os.sleep(0.04)
  end
end

-- Login mode: validate the profile, then spawn Desktop and curtain up.
local function submitLogin()
  if #state.password == 0 then
    state.loginError = "type_password"
    draw()
    return
  end
  local userProfile = cachedProfile(state.username)
  if not userProfile or not userProfile.passwd or userProfile.passwd == "" then
    state.loginError = "no_profile"
    draw()
    return
  end
  if not profile.authenticate(state.password, userProfile.passwd) then
    state.loginError = "wrong_password"
    draw()
    return
  end

  -- Authenticated. Resolve the profile's theme_idx (clamped) and
  -- persist the active user so future revs of System/Desktop can
  -- look it up without prompting.
  state.themeIdx = profile.themeIdx(userProfile, state.themeIdx)
  state.loginError = ""
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
  -- Tell the main loop to bail out so the chunk ends cleanly.
  -- reapAndRefocus then destroys the (2-row) Login window.
  submitted = true
end

-- Create mode: validate inputs, write the .profile file, then drop
-- into Login mode with the username pre-filled. The user must still
-- type their password to sign in (verifies they actually know the
-- string they just typed).
local function submitCreate()
  if not profile.isSafeUsername(state.username) then
    state.createError = "invalid_username"
    draw(); return
  end
  if #state.password < profile.MIN_PASSWORD_LEN then
    state.createError = "password_too_short"
    draw(); return
  end
  if state.password ~= state.confirmPassword then
    state.createError = "passwords_dont_match"
    draw(); return
  end

  local ok, reason = profile.create(state.username, state.password, {
    theme_idx = state.themeIdx,
  })
  if not ok then
    -- Map create() failure reasons to UI error codes. Storage failures
    -- (fs_unavailable / fs_open_failed) get their own code so the
    -- hint tells the user what's actually wrong, instead of blaming
    -- their username.
    if reason == "username_taken" then
      state.createError = "username_taken"
    elseif reason == "password_too_short"
        or reason == "invalid_username" then
      state.createError = reason
    else
      state.createError = "storage_error"
    end
    draw(); return
  end

  -- Profile written. Flip to Login mode. Drop the cached profile so
  -- the next submit re-reads from disk. The submit will succeed
  -- once the user types the same password.
  state.mode             = "login"
  state.password         = ""
  state.confirmPassword  = ""
  state.activeField      = "pass"
  state.loginError       = "create_succeeded"
  state.createError      = ""
  state.cachedProfileName = nil
  state.cachedProfile     = nil
  draw()
end

local function submit()
  if state.mode == "create" then return submitCreate() end
  return submitLogin()
end

-- Cycle through the input fields in the current mode. Login mode
-- toggles user/pass; create mode cycles user/pass/confirm.
local function cycleField()
  if state.mode == "create" then
    if state.activeField == "user"   then state.activeField = "pass"
    elseif state.activeField == "pass"   then state.activeField = "confirm"
    else                                  state.activeField = "user"
    end
  else
    state.activeField = (state.activeField == "user") and "pass" or "user"
  end
end

-- Switch modes via the link click. Drops error states so the new
-- mode renders fresh.
local function switchMode(target)
  if state.mode == target then return end
  state.mode             = target
  state.password         = ""
  state.confirmPassword  = ""
  state.loginError       = ""
  state.createError      = ""
  state.activeField      = "user"
  state.cachedProfileName = nil
  state.cachedProfile     = nil
  draw()
end

-- Test escape hatch (offline harness only). When the harness flips
-- qos.options._test_expose_layout = true, hoist  onto the
-- qos table and skip everything after this point so dofile returns
-- without entering the event loop. Boot.lua never sets this flag;
-- test_login_layout.lua is the only caller. The hook sits AFTER
-- layout()/buttonHit()/fieldAt()/linkHit()/draw() etc. are defined
-- so the references resolve; it sits BEFORE the main loop so the
-- chunk does not block on os.pullEvent.
if qos.options and qos.options._test_expose_layout then
  qos.options._exposed_layout = layout
  return
end

-- ----------------------------------------------------------------------------
-- Main event loop
-- ----------------------------------------------------------------------------

-- Set true at the end of submitLogin() so the main loop bails out
-- cleanly. Without this, the chunk keeps os.pullEvent()-ing forever
-- and the (now 2-row) Login window sits on top of the Desktop.
local submitted = false

draw()
local loginHover = false

while not submitted do
  local ev, a, b, c = os.pullEvent()

  if ev == "char" then
    if type(a) == "string" and #a == 1 then
      -- Any new keystroke clears a stale error so the user can
      -- immediately retry without re-focusing the field.
      if state.loginError ~= "" then state.loginError = "" end
      if state.createError ~= "" then state.createError = "" end

      if state.activeField == "confirm" and state.mode == "create" then
        state.confirmPassword = state.confirmPassword .. a
      elseif state.activeField == "pass" then
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
      submit()
    elseif a == keys.backspace then
      if state.loginError ~= "" then state.loginError = "" end
      if state.createError ~= "" then state.createError = "" end
      if state.activeField == "confirm" and state.mode == "create" then
        if #state.confirmPassword > 0 then
          state.confirmPassword = state.confirmPassword:sub(1, #state.confirmPassword - 1)
          draw()
        end
      elseif state.activeField == "pass" then
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
      cycleField()
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
      submit()
    elseif linkHit(b, c, L) then
      switchMode(state.mode == "login" and "create" or "login")
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
