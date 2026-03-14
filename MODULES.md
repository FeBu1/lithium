# Module catalog

## Core

- `core.gc` - periodic garbage collector.
- `hook.dispatch` - hybrid hook selector and fallback controller.
- `hook.diagnostics` - low-overhead profiler controls and dump/reset commands.
- `legacy.util` - existing utility helpers.
- `legacy.client_util` - client utility helpers.

## Legacy high-risk (default off)

- `legacy.cache_everything` - global function overrides.
- `legacy.clear_default_hooks` - default hook removals.
- `legacy.convar_spray` - broad convar mutation set.

## Client

- `client.gpu_saver` - out-of-focus rendering saver.
- `client.timeout_overlay` - timeout detection overlay.

## Experimental render

- `client.render.performant_lite`
  - Uses new files under `lua/lithium/client/render/`.
  - Starts with soft-cull markers + frame budget.
  - No aggressive `SetNoDraw` derender as default behavior.

## Panic disable files

Modules with panic files auto-disable themselves on startup failure by writing `1` to:

- `data/lithium/panic/core_gc.txt`
- `data/lithium/panic/hook_dispatch.txt`
- `data/lithium/panic/legacy_cache_everything.txt`
- `data/lithium/panic/legacy_clear_default_hooks.txt`
- `data/lithium/panic/legacy_convar_spray.txt`
- `data/lithium/panic/exp_render_performant_lite.txt`


## Diagnostics commands

- `lithium_hook_profiler_dump [topN]`
- `lithium_hook_profiler_reset`
- `lithium_hook_profiler_enabled` (ConVar)
