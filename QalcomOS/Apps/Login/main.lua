--[[
  /QalcomOS/Apps/Login/main.lua - Centered login dialog (v1.0 CC: Graphics)

  GPU-accelerated login with pixel art avatars, shadow effects,
  gradient panels, and smooth curtain transition.

  Core architecture unchanged from v0.7:
    * profile.hasAnyUser() determines create vs login mode
    * Authentication against /QalcomOS/Users/<name>/.profile
    * Same create/login flow for first-time users
    * Curtain-up transition on successful login

  New in v1.0:
    * Uses GPUFramebuffer for all rendering
    * Richer pixel-art avatars with colour
    * Gradient panel backgrounds
    * Drop shadows on dialog
    * 24-bit palette colours
]]--

local qos       = _QOS
local kernel    = qos.kernel
local themes    = dofile("/QalcomOS/System/themes.lua")
local profile   = dofile("/QalcomOS/System/profile.lua")
local api       = dofile("/QalcomOS/System/api.lua")
local gpu       = api.gpu
local DESKTOP   = "/QalcomOS/Apps/Desktop/main.lua"

-- Fallback if GPU not available.
if not gpu then
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(2, 2)
  term.write("GPU unavailable. Press any key.")
  os.pullEvent("key")
  return
end

local w, h = term.getSize()
local loginFB = gpu.createFramebuffer(w, h, {
  doubleBuffer = true, dirtyAlways = false,
  clearChar = " ", clearBg = 15, clearFg = 0,
})

-- Theme bootstrap ---
local function bootstrapThemeIdx()
  local opt = qos.options and qos.options.theme_idx
  if type(opt) == "number" and opt >= 1 and opt <= #themes.themes then
    return themes.normalize(opt)
  end
  return themes.load()
end

local function bootstrapMode()
  if profile.hasAnyUser() then return "login" end
  return "create"
end

-- State ---
local state = {
  mode             = bootstrapMode(),
  username         = "",
  password         = "",
  confirmPassword  = "",
  themeIdx         = bootstrapThemeIdx(),
  activeField      = "user",
  loginError       = "",
  createError      = "",
  cachedProfileName = nil,
  cachedProfile     = nil,
}

-- Pixel art avatars (rich 5-line art).
local AVATARS = {
  { "  ╭───╮  ", "  │ o o│ ", "  │ T │ ", "  ╰─┬─╯  ", "   / \\   " },  -- smiley
  { "  ╔═══╗  ", "  ║ o ║  ", "  ║ o ║  ", "  ║ T ║  ", "  ╚═╤═╝  " },  -- hat
  { "   *     ", "  / \\   ", " | o.o |", "  \\_/_  ", "  /___\\  " },    -- wizard
  { "  ┌───┐  ", "  │ o o│ ", "  │ ^ │ ", "  │___│ ", "  ───── " },      -- cube
}

local function cachedProfile(name)
  if state.cachedProfileName == name then return state.cachedProfile end
  local p = profile.read(name)
  state.cachedProfileName = name
  state.cachedProfile = p
  return p
end

local function loadAvatar(name)
  if name and #name > 0 then
    local p = cachedProfile(name)
    if p and p.avatar then
      local idx = profile.AVATAR_INDEX[p.avatar]
      if idx and AVATARS[idx] then return AVATARS[idx] end
    end
  end
  if not name or name == "" then return nil end
  local h = 0
  for i = 1, #name do h = h + string.byte(name, i) end
  return AVATARS[(h % #AVATARS) + 1]
end

local function getTheme() return themes.themes[state.themeIdx] end

-- Layout ---
local function layout()
  local boxW, boxH = 38, 14
  local boxX = math.max(2, math.floor((w - boxW) / 2) + 1)
  local boxY = math.max(1, math.floor((h - boxH) / 2))
  local T = getTheme()
  local out = {
    w = w, h = h, boxX = boxX, boxY = boxY, boxW = boxW, boxH = boxH,
    avatarX = boxX + 2, avatarY = boxY + 2,
    userX = boxX + 14, userY = boxY + 3,
    passX = boxX + 14, passY = boxY + 5,
    titleBg = (T and T.panel) or 3,
    bodyBg  = (T and T.panelX) or 7,
    accent  = (T and T.accent) or 4,
    fg      = (T and T.text) or 15,
    fieldBg = (T and T.field) or 0,
    fieldFg = (T and T.fieldText) or 15,
    btnBg   = (T and T.button_ok_bg) or 5,
    btnFg   = (T and T.button_ok_fg) or 15,
    linkBg  = (T and T.panelX) or 7,
    linkFg  = (T and T.accent) or 4,
  }
  if state.mode == "create" then
    out.confirmX = boxX + 14; out.confirmY = boxY + 7
    out.btnY1 = boxY + 9; out.btnY2 = boxY + 10
    out.linkLabel = "< Sign in instead >"
  else
    out.btnY1 = boxY + 8; out.btnY2 = boxY + 9
    out.linkLabel = "< Create an account >"
  end
  out.linkX = boxX + math.floor((boxW - #out.linkLabel) / 2) + 1
  out.linkY = math.min(boxY + boxH - 1, boxY + 13)
  -- Adjust linkY if box is too small.
  if out.linkY > h then out.linkY = h end
  return out
end

-- Drawing ---
local function drawDialog(T)
  local L = T  -- layout and theme combined

  -- Clear.
  loginFB:clear(" ", L.fg, L.bodyBg)

  -- Shadow behind dialog.
  loginFB:drawShadow(L.boxX, L.boxY, L.boxX + L.boxW - 1,
                      L.boxY + L.boxH - 1, 2, 1, 15)

  -- Dialog body with gradient.
  loginFB:gradientFill(L.boxX, L.boxY,
                        L.boxX + L.boxW - 1,
                        L.boxY + L.boxH - 1,
                        L.bodyBg, L.bodyBg, L.fg)

  -- Title bar.
  loginFB:fillRect(L.boxX, L.boxY,
                    L.boxX + L.boxW - 1, L.boxY,
                    " ", L.fg, L.titleBg)

  local codename = _QOS_CODENAME or "Qalcom OS"
  local title = state.mode == "create"
                and (" " .. codename .. " -- Create account ")
                or  (" " .. codename .. " -- Sign in ")
  loginFB:drawTextCentered(L.boxY, title, L.accent, L.titleBg)

  -- Bottom border.
  loginFB:drawHLine(L.boxX, L.boxX + L.boxW - 1,
                     L.boxY + L.boxH - 1, " ", L.fg, L.titleBg)

  -- Avatar.
  local avatar = loadAvatar(state.username)
  if avatar then
    for i, line in ipairs(avatar) do
      local row = L.avatarY + i - 1
      if row >= L.boxY and row < L.boxY + L.boxH then
        loginFB:drawText(L.avatarX, row, line, L.accent, L.bodyBg)
      end
    end
  end

  -- Username field.
  loginFB:drawText(L.boxX + 9, L.userY, "Username:", L.fg, L.bodyBg)
  loginFB:fillRect(L.userX, L.userY,
                    L.boxX + L.boxW - 2, L.userY,
                    " ", L.fieldFg, L.fieldBg)
  local uname = state.username or ""
  if #uname > L.boxW - 16 then uname = uname:sub(1, L.boxW - 18) end
  loginFB:drawText(L.userX, L.userY, uname, L.fieldFg, L.fieldBg)

  -- Password field.
  loginFB:drawText(L.boxX + 9, L.passY, "Password:", L.fg, L.bodyBg)
  loginFB:fillRect(L.passX, L.passY,
                    L.boxX + L.boxW - 2, L.passY,
                    " ", L.fieldFg, L.fieldBg)
  if #state.password > 0 then
    loginFB:drawText(L.passX, L.passY,
                      string.rep("*", #state.password),
                      L.fieldFg, L.fieldBg)
  end

  -- Confirm field (create mode).
  if state.mode == "create" then
    loginFB:drawText(L.boxX + 9, L.confirmY, "Confirm:", L.fg, L.bodyBg)
    loginFB:fillRect(L.confirmX, L.confirmY,
                      L.boxX + L.boxW - 2, L.confirmY,
                      " ", L.fieldFg, L.fieldBg)
    if #state.confirmPassword > 0 then
      loginFB:drawText(L.confirmX, L.confirmY,
                        string.rep("*", #state.confirmPassword),
                        L.fieldFg, L.fieldBg)
    end
  end

  -- Button.
  local canSubmit
  if state.mode == "create" then
    canSubmit = (#state.username > 0) and (#state.password >= profile.MIN_PASSWORD_LEN)
                and (state.password == state.confirmPassword)
  else
    canSubmit = (#state.username > 0)
  end
  local btnBg = canSubmit and L.btnBg or 7
  local btnFg = canSubmit and L.btnFg or 0
  local labelW = math.min(L.boxW - 2, L.boxX + L.boxW - 2 - L.boxX + 1)
  -- Button top border.
  loginFB:drawHLine(L.boxX + 10, L.boxX + L.boxW - 11,
                     L.btnY1, " ", L.btnFg, btnBg)
  -- Button label.
  local label = (state.mode == "create")
                and (canSubmit and "[ CREATE ]" or "[ ------ ]")
                or  (canSubmit and "[ LOGIN ]" or "[ ------ ]")
  local bx = L.boxX + math.floor((L.boxW - #label) / 2) + 1
  loginFB:drawText(bx, L.btnY2, label, btnFg, btnBg)

  -- Mode switch link.
  loginFB:drawText(L.linkX, L.linkY, L.linkLabel, L.linkFg, L.linkBg)

  -- Error/hint line.
  local hintY = L.boxY + L.boxH + 1
  if hintY <= h then
    local hintText = ""
    if state.mode == "login" then
      if state.loginError == "no_profile" then
        hintText = "No profile for '" .. state.username .. "'."
      elseif state.loginError == "wrong_password" then
        hintText = "Invalid username or password."
      elseif state.loginError == "create_succeeded" then
        hintText = "Profile created. Please sign in."
      else
        hintText = "Tab=switch field | Enter=submit | Esc=cancel"
      end
    else
      if state.createError == "invalid_username" then
        hintText = "Username: 1-16 chars, letters, digits, _ or -."
      elseif state.createError == "username_taken" then
        hintText = "That username is already taken."
      elseif state.createError == "password_too_short" then
        hintText = "Password must be >= " .. tostring(profile.MIN_PASSWORD_LEN) .. " chars."
      elseif state.createError == "passwords_dont_match" then
        hintText = "Passwords do not match."
      else
        hintText = "Tab=switch field | Enter=create | Esc=cancel"
      end
    end
    if #hintText > 0 and hintY <= h then
      loginFB:drawText(math.floor((w - #hintText) / 2) + 1, hintY, hintText, L.accent, L.bodyBg)
    end
  end

  loginFB:present()
end

-- Draw ---
local function draw()
  local L = layout()
  local T = getTheme()
  L.titleBg = T and T.panel or 3
  L.bodyBg  = T and T.panelX or 7
  L.accent  = T and T.accent or 4
  L.fg      = T and T.text or 15
  L.fieldBg = T and T.field or 0
  L.fieldFg = T and T.fieldText or 15
  L.btnBg   = T and T.button_ok_bg or 5
  L.btnFg   = T and T.button_ok_fg or 15
  L.linkBg  = T and T.panelX or 7
  L.linkFg  = T and T.accent or 4

  loginFB:beginDraw()
  drawDialog(L)
  loginFB:endDraw()
end

-- Hit tests ---
local function buttonHit(mx, my, L)
  return (mx >= L.boxX + 10 and mx <= L.boxX + L.boxW - 11)
     and (my == L.btnY1 or my == L.btnY2)
end

local function fieldAt(mx, my, L)
  if my == L.userY and mx >= L.userX and mx < L.boxX + L.boxW - 2 then return "user" end
  if my == L.passY and mx >= L.passX and mx < L.boxX + L.boxW - 2 then return "pass" end
  if state.mode == "create" and my == L.confirmY and mx >= L.confirmX and mx < L.boxX + L.boxW - 2 then return "confirm" end
  return nil
end

local function linkHit(mx, my, L)
  return my == L.linkY and mx >= L.linkX and mx < L.linkX + #L.linkLabel
end

-- Submit / transition ---
local function curtainUp()
  if not (qos.child and qos.child.getSize) then return end
  local _, body_h = qos.child.getSize()
  local cur_h = math.max(2, body_h + 1)
  if cur_h <= 2 then return end
  for tick = 1, cur_h - 2 do
    local new_h = math.max(2, cur_h - tick)
    qos.resizeSelf(new_h)
    os.sleep(0.04)
  end
end

local function submitLogin()
  if #state.password == 0 then state.loginError = "wrong_password"; draw(); return end
  local userProfile = cachedProfile(state.username)
  if not userProfile or not userProfile.passwd or userProfile.passwd == "" then
    state.loginError = "no_profile"; draw(); return
  end
  if not profile.authenticate(state.password, userProfile.passwd) then
    state.loginError = "wrong_password"; draw(); return
  end
  state.themeIdx = profile.themeIdx(userProfile, state.themeIdx)
  state.loginError = ""
  profile.writeCurrentUser(state.username)
  local L = layout()
  kernel.spawn(DESKTOP, {
    title = "Desktop", isSystem = true, w = L.w, h = L.h,
    theme_idx = state.themeIdx,
  })
  os.sleep(0.10)
  curtainUp()
  submitted = true
end

local function submitCreate()
  if not profile.isSafeUsername(state.username) then
    state.createError = "invalid_username"; draw(); return
  end
  if #state.password < profile.MIN_PASSWORD_LEN then
    state.createError = "password_too_short"; draw(); return
  end
  if state.password ~= state.confirmPassword then
    state.createError = "passwords_dont_match"; draw(); return
  end
  local ok, reason = profile.create(state.username, state.password, { theme_idx = state.themeIdx })
  if not ok then
    state.createError = reason == "username_taken" and "username_taken" or "storage_error"
    draw(); return
  end
  state.mode = "login"; state.password = ""; state.confirmPassword = ""
  state.activeField = "pass"; state.loginError = "create_succeeded"; state.createError = ""
  state.cachedProfileName = nil; state.cachedProfile = nil
  draw()
end

local function submit()
  if state.mode == "create" then return submitCreate() end
  return submitLogin()
end

local function cycleField()
  if state.mode == "create" then
    if state.activeField == "user" then state.activeField = "pass"
    elseif state.activeField == "pass" then state.activeField = "confirm"
    else state.activeField = "user" end
  else
    state.activeField = (state.activeField == "user") and "pass" or "user"
  end
end

local function switchMode(target)
  if state.mode == target then return end
  state.mode = target; state.password = ""; state.confirmPassword = ""
  state.loginError = ""; state.createError = ""; state.activeField = "user"
  state.cachedProfileName = nil; state.cachedProfile = nil
  draw()
end

-- Expose for tests ---
if qos.options and qos.options._test_expose_layout then
  qos.options._exposed_layout = layout
  return
end

-- Main event loop ---
local submitted = false
local loginHover = false

draw()

while not submitted do
  local ev, a, b, c = os.pullEvent()

  if ev == "char" then
    if type(a) == "string" and #a == 1 then
      if state.loginError ~= "" then state.loginError = "" end
      if state.createError ~= "" then state.createError = "" end
      if state.activeField == "confirm" and state.mode == "create" then
        state.confirmPassword = state.confirmPassword .. a
      elseif state.activeField == "pass" then
        state.password = state.password .. a
      else
        state.username = state.username .. a
        state.cachedProfileName = nil; state.cachedProfile = nil
      end
      draw()
    end

  elseif ev == "key" then
    if a == keys.enter then submit()
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
          state.cachedProfileName = nil; state.cachedProfile = nil
          draw()
        end
      end
    elseif a == keys.tab then cycleField(); draw()
    elseif a == keys.escape then
      term.setBackgroundColor(colors.black); term.setTextColor(colors.red); term.clear()
      term.setCursorPos(1, 1); print("Login cancelled.")
      return
    end

  elseif ev == "mouse_click" then
    local L = layout()
    if buttonHit(b, c, L) then submit()
    elseif linkHit(b, c, L) then switchMode(state.mode == "login" and "create" or "login")
    else
      local f = fieldAt(b, c, L)
      if f then state.activeField = f; draw() end
    end

  elseif ev == "terminate" then
    term.setBackgroundColor(colors.black); term.setTextColor(colors.red); term.clear()
    term.setCursorPos(1, 1); print("Login terminated.")
    return
  end
end
