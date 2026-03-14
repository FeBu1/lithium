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
- per-addon feature disable flags.

Initial rules:

- DLib-like addons are marked compatibility-sensitive and can force legacy hook backend.
- ULib is treated as known-compatible baseline.

## Hook mode policy

ConVar: `lithium_hook_mode`

- `auto` (recommended): fast backend unless compatibility rules force legacy.
- `fast`: force optimized backend.
- `legacy`: force stock hook backend.

## Risk notes

- Anything mutating hook internals is treated as sensitive, not "bad".
- Rendering state mutation is experimental-only and must support rollback.
- "ConVar spray" optimizers are retained only as opt-in legacy module.
