# Migration roadmap

## Phase 1 - Stabilize Lithium core

- [x] Replace monolithic bootstrap with modular loader.
- [x] Add per-module convar gating.
- [x] Add panic-disable files for invasive modules.
- [x] Shift risky modules to default-off.
- [ ] Split scheduler/profiler/logging into richer APIs.

## Phase 2 - Hybrid hook redesign

- [x] Add hook dispatcher scaffold (`auto`/`fast`/`legacy`).
- [x] Keep hook self-tests as fast-backend gate.
- [x] Add compatibility-based legacy forcing.
- [ ] Add runtime suspicious behavior detectors (mutating hook internals).
- [ ] Add manual compatibility presets for major addon frameworks.

## Phase 3 - Profiler + diagnostics

- [ ] Hook execution timing by event/hook ID.
- [ ] Per-module health diagnostics (fail count, rollback count).
- [ ] Structured logging levels + remote dump support.
- [ ] Rollback tests and compatibility self-tests in dedicated `tests/` tree.

## Phase 4 - PerformantRender-lite integration (optional)

- [x] Create experimental module boundary (`client.render.performant_lite`).
- [x] Split responsibilities:
  - registry,
  - visibility,
  - render-view compatibility,
  - point-camera compatibility,
  - apply,
  - debug.
- [ ] Add class blacklist/whitelist configuration convars.
- [ ] Soft-cull production hardening (default experimental mode).
- [ ] Full derender mode as explicit opt-in.
- [ ] Adaptive per-frame budget based on frametime.
- [ ] Restore mismatch auditing with automatic rollback + telemetry.

## First files to continue editing

1. `lua/lithium/core/bootstrap.lua`
2. `lua/lithium/hook/dispatcher.lua`
3. `lua/lithium/core/compatibility_registry.lua`
4. `lua/lithium/client/render/performant_render_apply.lua`
5. `lua/lithium/tests/hook.lua` (expand semantics tests for hybrid mode)
