require("lithium")

local M = {}

local function bool(cvar_name, default)
    local cv = GetConVar(cvar_name)
    if cv then return cv end
    return CreateConVar(cvar_name, default and "1" or "0", { FCVAR_ARCHIVE }, "Lithium hook diagnostics toggle", 0, 1)
end

local function num(cvar_name, default)
    local cv = GetConVar(cvar_name)
    if cv then return cv end
    return CreateConVar(cvar_name, tostring(default), { FCVAR_ARCHIVE }, "Lithium hook diagnostics value")
end

local enabled = bool("lithium_hook_profiler_enabled", false)
local top_n = num("lithium_hook_profiler_topn", 10)

concommand.Add("lithium_hook_profiler_dump", function(_, _, args)
    if not hook.GetLithiumDiagnostics then
        lithium.warn("[HOOK][PROF] Diagnostics are unavailable in current hook backend")
        return
    end

    local diag = hook.GetLithiumDiagnostics()
    local limit = tonumber(args[1]) or top_n:GetInt()

    lithium.info("[HOOK][PROF] enabled=" .. tostring(enabled:GetBool()) .. " events=" .. tostring(diag.total_events) .. " calls=" .. tostring(diag.total_calls) .. " fallback_count=" .. tostring(diag.compatibility_fallbacks or 0))

    local disp = lithium.hook_dispatcher and lithium.hook_dispatcher.get_stats and lithium.hook_dispatcher.get_stats() or nil
    if disp then
        lithium.info("[HOOK][PROF] dispatcher mode=" .. tostring(disp.active_mode) .. " fallback_count=" .. tostring(disp.fallback_count))
    end

    local compat_stats = lithium.compatibility_registry and lithium.compatibility_registry.get_stats and lithium.compatibility_registry.get_stats() or nil
    if compat_stats then
        lithium.info("[HOOK][PROF] compatibility addon_matches=" .. tostring(compat_stats.addon_matches) .. " source_matches=" .. tostring(compat_stats.source_matches))
    end

    local events = {}
    for event, item in pairs(diag.by_event or {}) do
        events[#events + 1] = { event = event, calls = item.calls, time = item.time }
    end
    table.sort(events, function(a, b) return a.time > b.time end)

    for i = 1, math.min(limit, #events) do
        local e = events[i]
        lithium.info(string.format("[HOOK][PROF] EVENT #%d %s calls=%d time=%.6f", i, e.event, e.calls, e.time))
    end

    local hooks = {}
    for key, item in pairs(diag.by_hook or {}) do
        hooks[#hooks + 1] = { key = key, calls = item.calls, time = item.time, source = item.source }
    end
    table.sort(hooks, function(a, b) return a.time > b.time end)

    for i = 1, math.min(limit, #hooks) do
        local h = hooks[i]
        lithium.info(string.format("[HOOK][PROF] HOOK #%d %s calls=%d time=%.6f source=%s", i, h.key, h.calls, h.time, tostring(h.source)))
    end
end)

concommand.Add("lithium_hook_profiler_reset", function()
    if not hook.ResetLithiumDiagnostics then
        lithium.warn("[HOOK][PROF] Reset unavailable in current hook backend")
        return
    end

    hook.ResetLithiumDiagnostics()
    lithium.info("[HOOK][PROF] Diagnostics reset")
end)

return M
