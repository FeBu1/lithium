# Module catalog

## Safety classification (conservative)

### Safe default-on (current evidence)

- `core.gc` - periodic garbage collector scheduler.
- `hook.dispatch` - hybrid backend selector + guarded fallback.
- `hook.diagnostics` - telemetry/report commands (low-overhead when profiler disabled).
- `legacy.util` - utility helpers with broad compatibility history.
- `legacy.client_util` - client helper utilities.
- `client.gpu_saver` - optional QoL saver (enabled by default, user-facing behavior).
- `client.timeout_overlay` - timeout diagnostics overlay.

### Safe but optional

- `hook` profiler sampling via `lithium_hook_profiler_enabled` (off by default).

### Experimental (keep disabled unless explicitly testing)

- `client.render.performant_lite`
  - Uses files under `lua/lithium/client/render/`.
  - Soft-cull bookkeeping only in current stage.
  - Not considered production-safe default behavior yet.

### Dangerous / keep disabled

- `legacy.cache_everything` - global function overrides.
- `legacy.clear_default_hooks` - default hook removals.
- `legacy.convar_spray` - broad convar mutation set.

## Panic disable files

Modules with panic files auto-disable themselves on startup failure by writing `1` to:

- `data/lithium/panic/core_gc.txt`
- `data/lithium/panic/hook_dispatch.txt`
- `data/lithium/panic/legacy_cache_everything.txt`
- `data/lithium/panic/legacy_clear_default_hooks.txt`
- `data/lithium/panic/legacy_convar_spray.txt`
- `data/lithium/panic/exp_render_performant_lite.txt`

## Diagnostics commands

- `lithium_report_dump [topN]` (combined end-of-session report)
- `lithium_report_export [topN]` (exports `data/lithium/reports/report_*.json`)
- `lithium_hook_profiler_dump [topN]`
- `lithium_hook_profiler_reset`
- `lithium_hook_profiler_enabled` (ConVar)
- `lithium_hook_backend_status`
- `lithium_compat_dump`
- `lithium_compat_rules_list`
- `lithium_module_dump`
- `lithium_compat_add_custom_rule <id> <source_pattern> [observe|feature_hint|force_legacy] [reason]`
