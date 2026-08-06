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
- [ ] Managed context wrappers cover filesystem, peripheral, redstone, label, and power actions used by built-in apps.
- [ ] Peripheral Manager discovery, adapter health, normalized contacts, aliases, blocklists, and trusted markers remain read-only and bounded.
- [ ] Infrastructure profiles, role/capability checks, confirmations, pulse limits, safe-state behavior, offline failures, and audit entries are bounded and allowlisted.
- [ ] Automation import/export accepts only validated structured definitions, and Recovery can pause all jobs without deleting their definitions.
- [ ] Structured jobs validate triggers/actions, enforce cooldowns and capability checks, bound history, persist bounded runtime status, use backoff retries, and never execute arbitrary Lua.
- [ ] Network envelopes use the documented HMAC-SHA256 authenticated encryption suite, associated-data binding, expiry/destination checks, persistent counter replay rejection, payload bounds, rate limits, and no arbitrary remote execution.
- [ ] The release explicitly states that cryptography cannot prevent RF/game-level jamming, copied secrets, compromised hosts, or clock/service outages.
- [ ] Receive replay state and transmit counters survive reboot and malformed state fails closed.
- [ ] Incident records are bounded; playbooks have dry-run previews and no autonomous offensive actions.
- [ ] Mod telemetry adapters are read-only, runtime-discovered, bounded, and visibly degraded when bridge APIs are absent or uncertain.
- [ ] Safe Mode blocks sensitive managed actions while preserving permitted read-only inspection.
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
- [ ] Managed action approvals and denials, including Safe Mode denials, were checked in the UI and audit log.
- [ ] Known limitations are recorded in the README and release notes.

## Version and documentation

- [ ] `/qalcom/version.lua` has the new version.
- [ ] `/qalcom/lib/managed.lua`, `/qalcom/lib/peripherals.lua`, `/qalcom/lib/infrastructure.lua`, `/qalcom/lib/jobs.lua`, `/qalcom/lib/network.lua`, `/qalcom/lib/telemetry.lua`, `/qalcom/apps/peripherals.lua`, `/qalcom/apps/infrastructure.lua`, `/qalcom/apps/jobs.lua`, `/qalcom/apps/jobs_service.lua`, `/qalcom/apps/network.lua`, and `/qalcom/apps/telemetry.lua` are included in installation and upgrade instructions.
- [ ] 0.2.6 persistent files `/qalcom/data/jobs.status` and `/qalcom/data/jobs.export` are documented, bounded, and optional.
- [ ] Persistent network and incident files `/qalcom/data/network.meta`, `/qalcom/data/nodes.meta`, `/qalcom/data/network.state`, `/qalcom/data/network.audit`, and `/qalcom/data/incidents.meta` are documented, bounded, and optional.
- [ ] Role schema/version migration is documented in the README and roadmap.
- [ ] User-facing version text is current.
- [ ] `ROADMAP.md` marks the milestone complete and preserves future work.
- [ ] Network and mod research limitations are recorded; actual CC:T/modpack method names are verified in-game before control work.
- [ ] `README.md` documents controls, installation changes, recovery, and limitations.
- [ ] The final response states what was tested and what could not be tested locally.
