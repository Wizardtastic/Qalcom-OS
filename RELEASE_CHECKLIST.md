# Qalcom Release Checklist

Use this checklist before calling a milestone complete.

## Scope

- [ ] The implementation matches the milestone goal in `ROADMAP.md`.
- [ ] The change is limited to the milestone; deferred work is documented instead of silently included.
- [ ] CC:T-only APIs are used unless a dependency is explicitly documented.

## Code and compatibility

- [ ] New files are included in `README.md` installation instructions.
- [ ] Exported functions and references were searched after changes.
- [ ] CC:T API calls are defensive where peripherals, memory, files, or optional APIs may be absent.
- [ ] Every built-in application has a versioned capability manifest.
- [ ] Role policy and approval behavior are documented; trusted Lua is not treated as sandboxed.
- [ ] Capability policy limitations are documented; no sandbox claim is made.
- [ ] Compact terminal behavior is checked at 30 x 14 and at a normal terminal size.
- [ ] Native UI shadows and animations are checked for bounds, responsiveness, and memory impact.
- [ ] Recovery and CraftOS escape paths remain available.

## Persistence and migration

- [ ] Existing account data remains readable.
- [ ] Legacy accounts migrate to versioned roles without data loss.
- [ ] Existing settings remain readable.
- [ ] Schema migration runs before settings are applied.
- [ ] Legacy setting names are tested and current defaults do not hide them.
- [ ] Restore defaults does not delete account data.
- [ ] Any persistent-data migration has a documented procedure.
- [ ] Logs are bounded and do not grow without limit.
- [ ] Capability audit logs are bounded and tolerate unavailable storage.

## Validation

- [ ] `git diff --check` passes.
- [ ] Offline pure-helper tests pass when a Lua interpreter is available.
- [ ] Manual CC:T checklist in `TESTING.md` is complete.
- [ ] Boot, login, logout, recovery, resize, app-failure, task cleanup, and power-confirmation paths were tested.
- [ ] Manual restart limits and recovery diagnostics were checked.
- [ ] Capability inspector, role decisions, account-role approvals/denials, and power approval events were checked.
- [ ] Known limitations are recorded in the README and release notes.

## Version and documentation

- [ ] `/qalcom/version.lua` has the new version.
- [ ] Role schema/version migration is documented in the README and roadmap.
- [ ] User-facing version text is current.
- [ ] `ROADMAP.md` marks the milestone complete and preserves future work.
- [ ] `README.md` documents controls, installation changes, recovery, and limitations.
- [ ] The final response states what was tested and what could not be tested locally.
