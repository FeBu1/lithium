# Lithium-Safe (WIP)

Lithium-Safe is a production-oriented fork of Lithium for large Garry's Mod addon packs (300-400 addons). This fork keeps Lithium's modular mindset, but shifts defaults toward safety, rollback behavior, observability, and compatibility.

## Current direction

- Hybrid hook architecture: fast path + legacy fallback.
- Compatibility registry for per-addon behavior control.
- High-risk systems moved to explicit opt-in modules.
- Experimental rendering optimizations isolated and disabled by default.

## Safety-first defaults

These systems are now **default-off** because they are too invasive for mixed addon environments:

- `legacy.cache_everything`
- `legacy.clear_default_hooks`
- `legacy.convar_spray`
- `client.render.performant_lite`

## Boot flow

`lua/autorun/!!!!!_lithium.lua` now delegates startup to `lua/lithium/core/bootstrap.lua`.

Each module has:

- an enable convar,
- logging on load/skip/fail,
- optional panic-disable file in `data/lithium/panic/...`,
- dependency declarations.

## Quick commands

- `lithium_enabled_sv` / `lithium_enabled_cl`: global enable toggle.
- `lithium_hook_mode`: `auto`, `fast`, or `legacy`.
- `lithium_samplefps_sv` / `lithium_samplefps_cl`: frame-time sampler.
- `lithium_report_dump` / `lithium_report_export`: session telemetry report (console/export).

## Status

This is a starter migration patch (Phase 1/2 scaffolding). See:

- `MODULES.md`
- `COMPATIBILITY.md`
- `ROADMAP.md`
