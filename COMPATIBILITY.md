# Compatibility strategy

## Objectives

- Preserve default Garry's Mod hook semantics (ordering + first non-nil return).
- Avoid globally forcing risky behavior in unknown addon ecosystems.
- Keep rollback paths available at runtime or next restart.

## Compatibility registry

File: `lua/lithium/core/compatibility_registry.lua`

The registry supports:

- addon name/file pattern matching,
- per-addon legacy hook mode forcing,
- per-addon feature disable hints,
- source-path policy matching for `hook.Add` call sites,
- built-in and custom rule origins.

## Rule actions

Rules are classified by action:

- `force_legacy`: compatibility-sensitive; can force legacy backend/fallback.
- `feature_hint`: advisory feature disable hint for risky subsystems.
- `observe`: telemetry-only; records matches without forcing fallback.

## Built-in vs custom rule workflow

- Built-in rules are registered by bootstrap at startup.
- Custom rules are loaded from `data/lithium/custom_compat_rules.json`.
- Add custom rules at runtime with:
  - `lithium_compat_add_custom_rule <id> <source_pattern> [observe|feature_hint|force_legacy] [reason]`
- Custom rules are persisted via registry save path when file/util APIs are available.

## Telemetry for pack triage

The registry tracks:

- total addon and source matches,
- built-in vs custom source match counts,
- action counters (`force_legacy`, `feature_hint`, `observe`),
- unique matched source count,
- last addon/source match context,
- reason hit counters,
- per-rule hit counters.

Use commands:

- `lithium_compat_dump`
- `lithium_report_dump`
- `lithium_report_export`

## Hook mode policy

ConVar: `lithium_hook_mode`

- `auto` (recommended): fast backend unless compatibility rules force legacy.
- `fast`: force optimized backend.
- `legacy`: force stock hook backend.

## Risk notes

- Anything mutating hook internals is treated as sensitive, not "bad".
- Rendering state mutation is experimental-only and must support rollback.
- "ConVar spray" optimizers are retained only as opt-in legacy module.


## Tuning workflow from telemetry

Use:

- `lithium_report_dump` for readable session telemetry
- `lithium_tuning_summary` for heuristic suggestions
- `lithium_report_export` for structured JSON snapshots

The tuning summary is heuristic-only and intentionally conservative:
- flags potentially overbroad `force_legacy` rules,
- highlights hot sources without compatibility actions,
- highlights frequent `observe` sources that may need escalation,
- highlights possible downgrade candidates where `force_legacy` appears costly but low-risk by telemetry.
