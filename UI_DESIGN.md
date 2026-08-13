# Qalcom OS Visual Design Specification

**Status:** Shared foundation and visible-app shell migration implemented; in-game visual QA remains  
**Source version:** 0.4.7  
**Primary design surface:** 204 x 76 terminal cells (width x height)  
**Supported floor:** 30 x 14 terminal cells

This document defines the visual system Qalcom should converge on after the visual overhaul. It is a design target, not a claim that every rule is already implemented. Runtime behavior, capability policy, event ownership, window restoration, palette cleanup, and the application contract remain unchanged unless a future implementation explicitly documents otherwise.

## 1. Design direction

Qalcom should look like a **cohesive command desktop**: a serious, pixel-native operating environment for an advanced ComputerCraft computer, not a collection of unrelated terminal programs.

The visual direction combines:

- the reference OS's hard-edged pixel geometry and clear navigation/content separation;
- a restrained dark shell with light or raised work surfaces;
- cobalt blue as the primary interaction accent;
- compact, readable information density at normal sizes;
- generous spacing and strong hierarchy on large terminals;
- a complete text-mode fallback that does not depend on graphics support.

The design must remain recognizable at 30 x 14 and become more useful, not merely more empty, at 204 x 76.

### Principles

1. **Hierarchy before decoration.** Background, window chrome, panels, content, and selection must be visually distinct before any ornament is added.
2. **One interaction accent.** Blue indicates focus, selection, primary actions, and active navigation. It must not be used as generic decoration.
3. **Surfaces carry structure.** Use tonal surfaces, one-cell borders, dividers, and spacing instead of excessive colored headers.
4. **Information is progressive.** Essential labels remain visible at every size; metadata, navigation rails, inspectors, and secondary actions appear only when space permits.
5. **Pixel-native clarity.** Use sharp rectangles, bitmap-friendly icons, fixed-cell alignment, and high-contrast state changes. Do not imitate browser UI with gradients, rounded corners, or tiny low-contrast text.
6. **Keyboard and mouse parity.** Every visible interactive control has a keyboard path and a visible focus state. Mouse hover is supplemental, never the only indication of state.
7. **The shell is shared.** Applications use the same title bars, panel rules, rows, buttons, spacing, and state language through `qalcom/lib/ui.lua` and `qalcom/lib/ui/screen.lua`.
8. **The kernel remains authoritative.** No app draws outside its known window or takes ownership of window/event/redraw behavior.

## 2. Resolution and responsive layout

All layout code must begin with the target surface's actual `getSize()` result. Do not use the 204 x 76 design surface as a fixed coordinate canvas and do not assume that a larger terminal should simply scale every cell-sized control proportionally.

Use **discrete responsive tiers**. A tier is selected only when both dimensions meet its threshold; otherwise the next smaller tier is used.

| Tier | Minimum size | Intended composition |
| --- | ---: | --- |
| Compact | 30 x 14 | Single content pane, no persistent navigation rail, essential controls only, one-line rows, collapsed metadata. |
| Standard | 56 x 21 | Optional navigation rail, one main pane, compact toolbar, selected-item details inline or in a modal. |
| Wide | 100 x 36 | Navigation rail plus main pane, optional inspector, breadcrumbs, visible secondary metadata, wider button groups. |
| Command | 160 x 60 | Full desktop composition, multi-pane operational views, dashboard cards, inspector/status regions, and expanded taskbar/tray. |

At the primary 204 x 76 surface, use the Command tier. A typical Explorer or operations window may contain a 28–32 cell navigation rail, a 2 cell pane gap, a flexible main region, and a 30–36 cell inspector when the selected item has useful detail. These are starting bounds, not fixed coordinates; the main region receives all remaining space.

### Responsive rules

- Compact layouts must never depend on horizontal scrolling for essential actions.
- At Compact tier, hide or collapse navigation rails and replace icon-plus-label toolbars with a short action row or menu.
- Telemetry and Peripheral Manager collapse their inspector into a selected-item summary below the list; they never squeeze two detail columns into a compact pane.
- At Standard tier, show a rail only if the remaining main pane is at least 24 cells wide.
- At Wide and Command tiers, use split panes only when every pane retains its minimum content width. If not, collapse the least important pane.
- Extra width expands content columns and breathing room; it does not create oversized buttons or stretch short labels across the screen.
- Extra height increases visible rows, detail area, and whitespace. It does not require taller one-line controls.
- Long titles, paths, names, and status messages use `UI.clampText` and the existing truncation convention. Never write past a calculated rectangle.
- Every layout has a deterministic compact fallback before drawing. A resize must not produce negative widths, overlapping controls, or inaccessible actions.

### Responsive metrics

Metrics are cell-based and should be calculated from the current terminal size. The following formulas are the target behavior; the implementation may expose them through `UI.metricsFor(width, height)` or equivalent helpers.

```text
short = min(width, height)
outerGutter  = clamp(1, floor(short / 32), 3)
paneGap      = clamp(1, floor(short / 28), 2)
panelPadding = clamp(1, floor(short / 30), 2)

navigationWidth = clamp(16, floor(width * 0.16), 32)
inspectorWidth  = clamp(24, floor(width * 0.18), 36)
```

`navigationWidth` and `inspectorWidth` are used only when their tier and remaining content width allow them. The formulas are intentionally capped so an ultra-wide terminal grows the work area rather than producing a comically wide navigation rail.

Target shell metrics by tier:

| Metric | Compact | Standard | Wide | Command |
| --- | ---: | ---: | ---: | ---: |
| Outer gutter | 1 | 1 | 2 | 2–3 |
| Pane gap | 1 | 1 | 1–2 | 2 |
| Panel padding | 1 | 1 | 1–2 | 2 |
| Window title bar | 1 row | 1 row | 1 row | 1 row |
| App header | 1 row | 1–2 rows | 2 rows | 2 rows |
| Taskbar | 1 row | 2 rows | 2 rows | up to 3 rows |
| Default list row | 1 row | 1 row | 1 row | 1 row, or 2 for detail rows |

The window title bar stays one row at every tier because it is part of the kernel's known frame and caption geometry. Larger applications gain a separate body header, breadcrumb, or toolbar rather than making window controls taller.

## 3. Palette token system

Applications must consume semantic tokens from `UI.colors`. They must not choose raw CC color constants for normal UI drawing and must not call `term.setPaletteColor` themselves. `Config.apply` and the palette helper remain the single theme/palette owners.

The existing names remain compatibility aliases during migration. The target canonical vocabulary is:

| Token | Meaning and usage |
| --- | --- |
| `desktop` | The lowest desktop/background surface. Use for the exposed desktop and login backdrop. |
| `desktopInset` | A quiet desktop variation for restrained texture, status areas, or recessed shell regions. |
| `surface` | Normal application content surface. |
| `surfaceRaised` | Floating cards, launcher panels, dialogs, and clearly elevated content. |
| `surfaceInset` | Recessed inputs, search fields, meter tracks, and secondary content wells. |
| `surfaceHover` | Pointer hover or pre-focus feedback. It must remain readable with normal text. |
| `surfaceSelected` | Keyboard/mouse selection background. Use with `textInverse` or a guaranteed-contrast text token. |
| `surfaceDisabled` | Disabled controls and unavailable content. Never use it for ordinary secondary content. |
| `border` | Neutral one-cell panel/window boundary. |
| `borderStrong` | Focused or important boundary; not a replacement for the focus state. |
| `divider` | Quiet separators inside a surface. |
| `shadow` | Optional one-cell offset for floating surfaces only. The shadow region must be included in the kernel's restore model. |
| `text` | Primary text and labels. |
| `textMuted` | Secondary metadata and supporting descriptions. |
| `textSubtle` | Non-essential hints and footer instructions. It must not carry required meaning. |
| `textInverse` | Text on a strong accent, danger, or dark surface. |
| `accent` | Default cobalt interaction accent. |
| `accentStrong` | Pressed state, selected marker, or high-priority primary action. |
| `accentSoft` | Low-intensity selection fill, active underline, or information highlight. |
| `focus` | High-contrast keyboard-focus marker. It may equal `accent` in a theme. |
| `info` | Informational status and service indicators. |
| `success` / `successSoft` | Positive state and low-intensity positive background. |
| `warning` / `warningSoft` | Caution state and low-intensity caution background. |
| `danger` / `dangerSoft` | Destructive/error state and low-intensity error background. |
| `button` / `buttonText` | Default secondary button surface and label color. |
| `buttonActive` | Pressed/active secondary button surface. |
| `titleActive` / `titleInactive` | Focused and unfocused window title-bar surfaces. |
| `titleControl` | Title-bar caption glyph color. |
| `statusText` | Text in taskbar/tray or other high-contrast status regions. |

Existing names such as `surfaceStrong`, `surfaceAlt`, `surfaceMuted`, `muted`, `hover`, `section`, and `sectionText` should remain available as aliases while applications migrate. New code should prefer the canonical names above. In particular, section headers should no longer use the warning-yellow token by default; yellow must communicate caution, not merely application structure.

### Reference-inspired theme targets

The values below describe the intended visual relationships. They are illustrative RGB targets for color-capable terminals, not permission for apps to bypass the 16-slot CC:T palette.

**Command Dark**

```text
desktop        deep blue-black      #101820
surface        charcoal slate       #222C36
surfaceRaised  lighter slate        #2E3945
surfaceInset   deep inset           #141B22
border         quiet blue-gray      #3E4A56
divider        dark blue-gray       #2D3944
text           cool off-white       #F0F4F7
textMuted      blue-gray            #AAB6C0
accent         cobalt               #3F7FDB
accentStrong   deep cobalt          #245AB0
accentSoft     muted cobalt         #2D527F
focus          bright blue          #7DB9FF
success        controlled green     #65C466
warning        amber                #E1B34F
danger         restrained red       #D86565
```

**Command Light**

```text
desktop        cool gray            #D8DEE4
surface        pale gray            #F4F6F8
surfaceRaised  white                #FFFFFF
surfaceInset   blue-gray inset      #E6EBEF
border         medium slate         #7B8792
divider        light slate          #C3CCD4
text           deep slate           #15202A
textMuted      slate                #5E6C78
accent         cobalt               #2F69C9
accentStrong   deep cobalt          #1E4F9D
accentSoft     pale blue            #C8DAF5
focus          clear blue           #155FC5
```

The login surface may use `accentStrong` or a dedicated cobalt backdrop with a raised light card. It should not make the whole desktop permanently blue. On a stock 16-color host, preserve luminance separation even if hue distinctions collapse.

### Contrast rules

- Required text must differ from its background by a strong luminance step; do not rely on blue versus purple or green versus cyan alone.
- Every semantic status has a text/icon/glyph treatment in addition to color.
- `textSubtle` is never used for credentials, errors, selected values, or action labels.
- Selected text must remain readable when the theme maps `surfaceSelected` to a bright terminal slot.
- Theme application must continue to snapshot and restore the host palette during logout, graphics exit, reboot, and failure cleanup.

## 4. Spacing and alignment

The base spacing unit is one terminal cell. Spacing is structural, not decorative.

| Token | Compact | Expanded use |
| --- | ---: | ---: |
| `space1` | 1 | Inline separation, row padding, divider offset |
| `space2` | 1 | Panel inner padding at small sizes; normal control gap |
| `space3` | 1–2 | Section separation and pane gap |
| `space4` | 2 | Card padding, toolbar-to-content separation |
| `space6` | 2–3 | Login card and large dashboard section separation |

Rules:

- Align labels, values, buttons, and status markers to a small set of column boundaries.
- Use one cell of breathing room around a compact panel; use two cells on Wide and Command surfaces.
- Do not create a divider and a full blank row for the same separation.
- Keep related controls in one group and separate destructive actions from normal actions by at least one cell or a distinct action group.
- Prefer a flexible content column over a hard-coded centered control when the available width changes.
- At 204 x 76, use two-cell gutters and two-cell pane gaps by default. Let the main content area expand rather than increasing every control's height.

## 5. Component specification

### 5.1 Window title bars

The title bar is the primary window identity and focus surface.

- Height: exactly one row at every resolution tier.
- Left: optional one-cell icon, one-cell separation, then a clamped title.
- Right: the shared `UI.captionButtons(x, y, width)` geometry for minimize, maximize/restore, and close.
- Active window: `titleActive`, primary title text, and an accent icon or marker.
- Inactive window: `titleInactive`, muted title text, and no high-saturation focus treatment.
- Hover: a quiet `surfaceHover` treatment for minimize/maximize; danger treatment for close.
- Narrow windows: use the existing collapse rule and expose close safely rather than overlapping controls.
- Titles must truncate inside the first caption boundary. Never duplicate caption coordinates in the kernel or an app.
- Window borders stay inside the kernel-known frame. A title bar must never draw a shadow or accent line outside that rectangle.

The title bar should feel like a consistent operating-system chrome element, not an app-specific banner.

### 5.2 Application headers and breadcrumbs

The body may have a second header below the window title bar.

- Compact: one-line title or context only; omit decorative subtitle text.
- Standard: title plus optional status or breadcrumb.
- Wide/Command: title, breadcrumb/path, and a right-aligned status or primary action where space permits.
- Use `surface` or `surfaceRaised`, not warning yellow, for structural headers.
- Breadcrumb segments use muted text with the current segment in primary text or accent.
- Headers must reserve their own rectangle before body layout begins.

### 5.3 Panels and cards

Panels establish grouping and elevation.

- Rectangular, sharp corners, one-cell border.
- Normal panel: `surface` with `border`.
- Raised panel: `surfaceRaised` with `borderStrong` only when it represents a dialog, launcher, inspector, or active region.
- Inset region: `surfaceInset` with either `divider` or no border when the parent surface already supplies enough contrast.
- Default padding: one cell Compact/Standard, two cells Wide/Command.
- Use a one-cell shadow only for floating surfaces and only when the full shadow region is covered by the relevant restore/redraw model.
- Do not stack more than three tonal levels in a small window; excessive nested cards make a terminal UI noisy.
- Cards with a title use a quiet structural header and a consistent title offset. A colored header is reserved for an active/primary card, not every section.

### 5.4 Rows and lists

Rows are the primary information surface for Explorer, Settings, Account, Network, Telemetry, and Control Center.

- Default height: one row. Use two rows only for a detail row with a meaningful secondary line and enough vertical space.
- Left region: optional icon/status marker, then the primary label.
- Middle region: flexible description or metadata.
- Right region: value, state badge, or affordance, aligned to a stable column.
- Use a divider or surface change between groups; do not zebra-stripe every row by default.
- Selected row: `surfaceSelected` or `accentSoft`, a visible accent marker, and guaranteed-contrast text.
- Focused row: retain selection treatment and add a one-cell focus marker or focus glyph; do not depend only on a color change.
- Disabled row: muted text and a disabled surface; it must not look actionable.
- Empty state: centered or padded title plus a muted explanation and an available next action when one exists.

At 204 x 76, Explorer should support icon + name + metadata + state columns and may show a detail inspector. At Compact tier it should reduce to icon + name and put secondary information in the footer or a modal.

### 5.5 Buttons and controls

Buttons must have a visible rectangle, a minimum readable label, and shared hit geometry.

Variants:

- **Primary/accent:** `accent` background, `textInverse` label; one per action group where possible.
- **Secondary:** `button` background, `buttonText` label; normal non-destructive actions.
- **Subtle/ghost:** `surface` or `surfaceInset` background with primary text; navigation and low-emphasis actions.
- **Danger:** `danger` treatment only for destructive confirmation or close-hover states.
- **Disabled:** `surfaceDisabled` and muted text; no hover or pressed response.

Geometry:

- Standard inline button height: one row.
- Minimum width: the label plus two cells of horizontal padding, bounded by the available layout rectangle; retain the existing seven-cell minimum where it fits.
- Primary login or emergency actions may use a two-row button at Standard tier or above; do not force two-row buttons into Compact layouts.
- Button groups have one cell between controls and at least two cells before an unrelated group.
- Labels are centered inside the button's own rectangle, never centered against the entire screen.
- Controls remain usable by keyboard when labels are clamped; the visible accelerator/help text must also be clamped.

### 5.6 Inputs, toggles, badges, and meters

- Inputs use `surfaceInset`, a strong active/focus treatment, and a visible cursor or insertion marker.
- Active input: use `focus` or `accent` without hiding the typed value.
- Toggles and checkboxes show an explicit on/off glyph in addition to color.
- Badges are short, bounded, and reserved for states such as `READY`, `STALE`, `DENIED`, or `SAFE MODE`; do not use them for ordinary labels.
- Meters use an inset track and an accent fill, with a text/value or semantic label when the reading matters.
- Unknown, stale, unavailable, and denied must remain different states even if a theme maps some colors similarly.

### 5.7 Dialogs and notifications

- Dialogs use a raised surface, one-cell border, clear title, short body, and grouped actions with the primary action last/rightmost where space allows.
- Destructive dialogs require explicit confirmation and a visible danger label; visual polish must never weaken Qalcom's safety workflow.
- Notifications use bounded cards or taskbar markers and severity glyphs. Danger persists longer than informational feedback.
- Dialogs and notifications must stay within the terminal and preserve the kernel's region restore rules.

### 5.8 Context menus

- Right-clicking anywhere in the desktop opens a kernel-owned menu above the taskbar or beside the pointer, clamped entirely inside the terminal.
- The menu is a raised surface with a compact location header, keyboard selection, hover feedback, and an explicit Cancel row.
- Creation actions use the current Explorer directory when the pointer is over Explorer; otherwise they use the root directory as the shell default.
- New folders, text files, and Lua files receive bounded collision-safe names and refresh Explorer after creation.
- When the current target is Explorer and an item is selected, offer Open with Editor for files, Rename, Delete, Copy, and Paste where applicable; the menu remains useful without a selection.
- Rename uses an editable name prompt, rejects traversal/path separators, control characters, empty names, and collisions, then requires explicit confirmation before moving the item.
- Delete requires explicit confirmation, warns about recursive folder removal, rechecks the target, and refreshes Explorer after success.
- Copy/paste uses one session clipboard shared with Explorer keyboard shortcuts and refuses missing sources, collisions, and folder self-pastes.
- All filesystem actions remain subject to the managed `fs.read`/`fs.write` capabilities and Safe Mode; denials are visible and audited.
- The menu captures its own clicks and keys so context actions never leak into the focused application.

## 6. Focus, hover, selection, and state language

State must be understandable without memorizing theme colors.

| State | Visual treatment | Meaning |
| --- | --- | --- |
| Normal | Base surface, primary text | Available but not active |
| Hover | `surfaceHover`, optional glyph change | Pointer is over the control |
| Keyboard focus | `focus` marker/border/underline | Keyboard action will affect this control |
| Selected | `surfaceSelected` or `accentSoft` plus marker | Current item in a list/navigation context |
| Pressed | `accentStrong` and pressed glyph/label | Action is being activated |
| Disabled | `surfaceDisabled`, muted text, no hover | Not available under current state/policy |
| Informational | `info` plus `i`/service glyph | Non-error system information |
| Success | `success` plus check/ready glyph | Completed or healthy |
| Warning | `warning` plus `!`/caution glyph | Needs attention |
| Danger | `danger` plus `!`/stop glyph | Failure, denial, or destructive action |

A focused selected row should not become a saturated full-row block if that makes its contents difficult to read. Prefer an accent strip, a soft fill, and a strong text/marker combination.

`reduced_motion` disables or shortens transitions but does not remove focus, hover, or selection feedback.

## 7. Shell and application composition

The desktop shell should follow this order:

1. Desktop background or solid wallpaper.
2. Kernel-managed windows with shared title bars and frames.
3. Bottom taskbar with a clearly separated launcher/start control, app icons, active marker, service health, and clock/tray.
4. Launcher/menus as raised surfaces anchored to their owner control.
5. Notifications in a bounded shell-owned region.

The login experience should be a distinct system surface:

- solid cobalt backdrop;
- centered light raised card;
- clear Qalcom identity;
- compact credential fields;
- one dominant sign-in/create-account action;
- help and shutdown hints in muted text;
- a compact fallback that keeps the same order and semantics.

At 204 x 76, the desktop should feel spacious and operational: windows may expose richer dashboards, but the taskbar and title bars remain compact. At 30 x 14, the same shell becomes a single-pane utility surface without losing the launcher, close path, focus state, or recovery access.

## 8. Visual overhaul plan

The overhaul is intentionally staged so visual changes do not destabilize the kernel, security policy, or app behavior.

### Phase 0: Freeze the visual contract — complete

- Treat this document as the target vocabulary and responsive contract.
- Inventory every `UI.colors` consumer and every raw drawing call in apps.
- Define canonical token aliases in the UI layer while preserving legacy names.
- Add pure layout helpers for tier selection, scaled metrics, split-pane fitting, and clamped control groups.

### Phase 1: Rebuild the UI primitives — implemented

- Update `UI.panel`, `UI.card`, `UI.sectionHeader`, `UI.listRow`, `UI.button`, `UI.input`, `UI.badge`, `UI.meter`, `UI.titleBar`, and `Screen.shell` to follow these rules.
- Make active/inactive/hover/focus/disabled states consistent across all variants.
- Keep `UI.captionButtons` as the only title-control geometry source.
- Remove structural dependence on yellow section headers; retain yellow for warnings.
- Add shared pixel-safe icon helpers with text-label fallbacks.

### Phase 2: Rework the shell and login — implemented

- Apply the dark-shell/light-surface hierarchy to the kernel desktop, taskbar, launcher, and notifications.
- Add the reference-inspired cobalt login surface and centered card without changing authentication flow.
- Make taskbar and launcher behavior tier-aware while preserving current mouse/keyboard routing.
- Validate shadows, tooltip bounds, restore regions, palette restoration, and resize behavior after every shell change.

### Phase 3: Migrate the highest-value applications — visible app shell migration complete

Prioritize applications where hierarchy provides the largest benefit:

1. File Explorer: navigation rail, path/breadcrumb strip, toolbar, icon-aware rows, selection, and optional inspector.
2. Settings: grouped sections, clear toggles, responsive forms, and a persistent status/footer.
3. Control Center and Diagnostics: status rows, health markers, failure/restart actions, and dashboard cards.
4. Telemetry, Network, and Peripheral Manager: split-pane layouts at Wide/Command tiers with compact list fallbacks.
5. Account, Recovery, Terminal, Editor, Calculator, and Capabilities: migrate to the same headers, panels, controls, and state language.
6. CBC Fire Control: preserve the safety workflow while improving mount rows, target planning hierarchy, confirmation dialogs, and danger-action grouping.

No migration may remove an existing policy denial, confirmation, audit entry, Safe Mode behavior, cleanup callback, or explicit unknown/stale state.

### Phase 4: Make Fluent and text mode visually equivalent — text shell migrated; graphics parity review pending

- Map the same semantic tokens to Canvas/256-color rendering and native terminal slots.
- Share geometry and state decisions between text and graphics paths where practical.
- Keep the text renderer authoritative when graphics mode is unavailable or the terminal is not color-capable.
- Preserve graphics cleanup and host palette restoration on every exit path.

### Phase 5: Validate at representative sizes

Every migrated screen must be reviewed at minimum:

- 30 x 14: compact recovery-safe layout;
- 40 x 18: narrow everyday layout;
- 80 x 24: standard desktop;
- 120 x 40: wide split-pane layout;
- 204 x 76: primary advanced-computer layout;
- one substantially larger and one unusually wide/short terminal to catch hard-coded assumptions.

Validation must cover keyboard, mouse, resize, focus, inactive windows, disabled/denied actions, Safe Mode, reduced motion, palette restoration, crash/restart, and logout. Pure layout helpers should be added to `tests/pure_test.lua`; runtime-dependent rendering remains a manual CC:T/CraftOS-PC check.

## 9. Implementation guardrails

- Keep `/qalcom` absolute paths and the app return-function contract intact.
- Do not move drawing/event/window ownership into applications.
- Do not draw beyond a task's known frame or add a shadow without updating the region-restore model.
- Do not introduce external dependencies or assume a desktop Lua runtime.
- Do not call raw palette mutation from an app; theme and palette restoration remain centralized.
- Do not use color as the only status or permission indicator.
- Do not imply that capability decisions form a secure sandbox.
- Do not use decorative wallpaper or texture that prevents deterministic partial restoration. Any wallpaper remains a pure function of absolute cell coordinates, and image wallpaper stays out of the native path unless its restore/performance implications are explicitly solved.
- Keep compact layouts fully usable; the 204 x 76 design target is an enhancement, not a new minimum requirement.
