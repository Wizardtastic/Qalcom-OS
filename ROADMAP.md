# Qalcom OS Modernization Roadmap

Qalcom OS will evolve into a cohesive, modern character-cell operating environment for ComputerCraft: Tweaked. The goal is not to decorate each application independently; it is to establish one visual and interaction system that makes every current and future application feel like part of Qalcom.

## Product direction

**Modern command console:** Windows-style desktop familiarity, operations-console density, retro character-cell clarity, contemporary information hierarchy, semantic status colors, calm motion, and explicit safety affordances.

The modernization must preserve Qalcom's operational boundaries: capability gates, explicit confirmations, audit records, safe-state behavior, graceful degradation, recovery access, CC:T compatibility, and region-based repaint performance.

## Design principles

- Hierarchy before decoration: primary state and actions must be obvious before secondary detail.
- Consistent rhythm: shared margins, row heights, section gaps, control sizes, and footer treatment.
- Semantic color: accent for interaction, green for healthy, amber for attention, red for danger/failure, gray for inactive/unknown.
- Progressive disclosure: show the most important information first; move dense detail into panes, tabs, or focused views.
- Mouse and keyboard parity: visible controls are required; shortcuts remain useful but never hidden-only.
- Responsive character-cell layouts: compact terminals remain usable, while larger terminals gain breathing room and detail.
- Accessibility: do not rely on color alone; include labels, symbols, strong contrast, visible focus, and reduced-motion support.
- Performance: app-local updates and shell changes must retain targeted repaint behavior; full-terminal clears remain exceptional.

## Milestone 1 — Design-system foundation

**Status:** Complete (source-level; target CC:T visual validation pending)

**Goal:** Build the shared visual language and app-shell primitives before redesigning individual applications.

### Theme tokens

Expand the shared theme model beyond desktop/accent colors. Every theme will provide semantic tokens for:

- Desktop and elevated desktop surfaces
- Base, raised, inset, selected, hover, and disabled surfaces
- Primary, muted, subtle, and inverse text
- Borders, strong borders, dividers, and focus indicators
- Accent, soft accent, and strong accent
- Success, warning, danger, and informational states
- Shadows and status treatments

Existing `UI.colors` fields remain supported as compatibility aliases. Applications should migrate from raw `colors.*` values to semantic `UI.colors.*` tokens over time.

### Shared metrics and layout

Provide centralized character-cell metrics and safe layout helpers:

- Standard outer/content padding
- Header, footer, row, and section-gap sizes
- Padded rectangles
- Horizontal and vertical splits
- Content bounds
- Column fitting and clamping
- Text measurement/truncation through the shared UI primitives

Layout helpers must clamp dimensions before calling strict CC:T terminal APIs.

### Reusable components

Establish shared components for:

- Application shells, headers, toolbars, tabs, and footers
- Primary, secondary, ghost, destructive, compact, disabled, and focused buttons
- Inputs, toggles, checkboxes, and segmented controls
- Cards, panels, tables, key/value rows, badges, meters, and status indicators
- Empty, loading, error, warning, and confirmation states
- Tooltips, focus treatments, and command hints

The first implementation remains backward-compatible with the existing `UI.button`, `UI.card`, `UI.input`, `UI.listRow`, `UI.sectionHeader`, `UI.badge`, `UI.meter`, `UI.status`, `Screen.begin`, and `Screen.card` APIs.

### App-shell contract

Add a reusable shell that can provide:

- Standard surface clearing and app header hierarchy
- Optional subtitle/context line
- Optional tabs and toolbar actions
- Usable content bounds
- Status/feedback area
- Keyboard/mouse command hints
- Compact-terminal fallback

Existing apps may continue using `Screen.begin` while they are migrated.

### Milestone 1 exit criteria

- All semantic tokens and metrics are available from the shared UI layer.
- Existing applications load without changing their current call sites.
- New applications can use the app shell and common state components without reimplementing layout plumbing.
- Light, dark, and terminal themes provide the same token names.
- Helpers clamp layout dimensions safely for CC:T.
- Pure helper tests and structural checks pass where a Lua 5.1-compatible runtime is available; this checkout has no Lua interpreter.
- No full repaint or region-repaint regressions are introduced by the foundation changes; target CC:T repaint validation remains required.

## Milestone 2 — Shell redesign

**Goal:** Make the desktop itself feel like a unified modern operating environment.

- Modernize active/inactive window chrome, title controls, borders, focus states, and compact layouts.
- Refine the taskbar with app health indicators, minimized state, notifications, intentional overflow, and clearer hover/focus behavior.
- Upgrade the Start menu into a searchable command palette with recent apps, categories, availability state, and Safe Mode explanation.
- Upgrade notifications with severity, grouping, titles, detail, persistent critical state, and consistent timing.
- Polish login, logout, recovery, and crash surfaces.
- Preserve targeted repainting and the corrected reposition-before-restore window movement invariant.

## Milestone 3 — Reference applications

Redesign these first to validate the design system across different interaction patterns:

- **Settings:** navigation, themes, toggles, forms, status feedback, and sections.
- **Calculator:** display hierarchy, keypad states, mouse/keyboard parity, and compact layout.
- **Control Center:** dashboard cards, process health, resource meters, and confirmed actions.

These become the visual benchmarks for later application migrations.

## Milestone 4 — Everyday applications

Migrate:

- Terminal
- File Explorer
- Text Viewer/Editor
- System Log
- Recovery
- Diagnostics
- Account

Each receives standard headers, state surfaces, empty/error handling, visible actions, compact layouts, and consistent interaction feedback.

## Milestone 5 — Operations applications

Migrate:

- System Monitor
- Peripheral Manager
- Operations Telemetry
- Network Operations
- Capabilities

Emphasize health, freshness, trust, availability, degraded state, read-only boundaries, and information density.

## Milestone 6 — High-impact applications

Migrate with additional safety review:

- Infrastructure Controls
- Automation Jobs
- Incident Response
- CBC Fire Control
- Related confirmation/dialog workflows

Visual design must make action scope, current state, confirmation requirements, dry-run boundaries, and safety limitations impossible to miss.

## Milestone 7 — Future-app SDK and quality gate

- Add an application manifest contract with title, category, icon, minimum size, input support, and capabilities.
- Provide a new-app template based on the shared shell.
- Add UI contribution rules forbidding raw theme colors and direct ad-hoc clearing in normal app flows.
- Add a mock terminal/snapshot layer for deterministic layout checks without a CC:T runtime.
- Add theme, compact-layout, keyboard, mouse, reduced-motion, and repaint validation matrices.

## Performance and validation policy

Qalcom has no local CC:T runtime, so every milestone requires both offline structural/pure checks and in-game validation on the target terminal. Visual work must be validated at the minimum supported terminal size and at a larger operational size.

Required visual regression scenarios include:

- Window focus, drag, minimize, maximize, restore, and close
- Dragging across windows, notifications, launcher panels, and terminal edges
- Taskbar hover and tooltip repainting
- Theme changes and reduced motion
- Compact layouts and text truncation
- Empty, loading, degraded, denied, failed, and confirmation states

## Definition of success

The modernization is successful when:

- Every app clearly looks like part of Qalcom.
- No app invents its own header, footer, selection, status, or button conventions.
- Themes affect the complete UI, not only the desktop.
- All apps work with mouse and keyboard and show visible focus.
- Every app handles compact sizes and relevant empty/error/loading states.
- High-density operations screens become easier to understand rather than merely more colorful.
- Sensitive actions become more visibly deliberate and safer to operate.
- New apps can start from a template and look polished immediately.
- Region repaint performance and window movement correctness remain intact.
- Visual behavior can be regression-tested without a live modpack.
