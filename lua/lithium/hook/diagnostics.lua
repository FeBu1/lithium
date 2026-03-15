require("lithium")

local M = {}

local GetConVarFn = GetConVar
local CreateConVarFn = CreateConVar
local concommand_add = concommand and concommand.Add

local function safe_bool(cvar_name, default)
    if type(GetConVarFn) == "function" then
        local cv = GetConVarFn(cvar_name)
        if cv then return cv end
    end

    if type(CreateConVarFn) == "function" then
        return CreateConVarFn(cvar_name, default and "1" or "0", { FCVAR_ARCHIVE }, "Lithium hook diagnostics toggle", 0, 1)
    end

    return { GetBool = function() return default end, GetInt = function() return default and 1 or 0 end }
end

local function safe_num(cvar_name, default)
    if type(GetConVarFn) == "function" then
        local cv = GetConVarFn(cvar_name)
        if cv then return cv end
    end

    if type(CreateConVarFn) == "function" then
        return CreateConVarFn(cvar_name, tostring(default), { FCVAR_ARCHIVE }, "Lithium hook diagnostics value")
    end

    return { GetInt = function() return default end }
end

local enabled = safe_bool("lithium_hook_profiler_enabled", false)
local top_n = safe_num("lithium_hook_profiler_topn", 10)

local function dump_dispatcher()
    local disp = lithium.hook_dispatcher and lithium.hook_dispatcher.get_stats and lithium.hook_dispatcher.get_stats() or nil
    if not disp then
        lithium.warn("[HOOK][DIAG] Dispatcher stats unavailable")
        return
    end

    lithium.info("[HOOK][DIAG] backend=" .. tostring(disp.active_mode) .. " fallback_count=" .. tostring(disp.fallback_count) .. " suppressed=" .. tostring(disp.fallback_suppressed or 0))
    for i = 1, math.min(10, #(disp.fallback_events or {})) do
        local item = disp.fallback_events[#disp.fallback_events - i + 1]
        lithium.info("[HOOK][DIAG] fallback[" .. i .. "] reason=" .. tostring(item.reason) .. " when=" .. tostring(item.when))
    end
end

local function dump_compatibility()
    local compat_stats = lithium.compatibility_registry and lithium.compatibility_registry.get_stats and lithium.compatibility_registry.get_stats() or nil
    if not compat_stats then
        lithium.warn("[HOOK][DIAG] Compatibility stats unavailable")
        return
    end

    lithium.info("[HOOK][DIAG] compat addon_matches=" .. tostring(compat_stats.addon_matches) .. " source_matches=" .. tostring(compat_stats.source_matches))

    if compat_stats.last_source_match then
        local m = compat_stats.last_source_match
        lithium.info("[HOOK][DIAG] compat last_source_match id=" .. tostring(m.id) .. " action=" .. tostring(m.action) .. " source=" .. tostring(m.source) .. " event=" .. tostring(m.event) .. " hook_id=" .. tostring(m.hook_id))
    end

    if compat_stats.last_addon_match then
        local a = compat_stats.last_addon_match
        lithium.info("[HOOK][DIAG] compat last_addon_match id=" .. tostring(a.id) .. " action=" .. tostring(a.action) .. " addon=" .. tostring(a.addon_name) .. " file=" .. tostring(a.addon_file))
    end

    for id, hits in pairs(compat_stats.source_match_rules or {}) do
        lithium.info("[HOOK][DIAG] compat rule_hits id=" .. tostring(id) .. " hits=" .. tostring(hits))
    end
end

local function dump_modules()
    local ms = lithium.module_summary
    if not ms then
        lithium.warn("[HOOK][DIAG] Module summary unavailable")
        return
    end

    lithium.info("[HOOK][DIAG] modules loaded=" .. tostring(#(ms.loaded or {})) .. " failed=" .. tostring(#(ms.failed or {})) .. " skipped=" .. tostring(#(ms.skipped or {})))
end

local function dump_profiler(args)
    if not hook.GetLithiumDiagnostics then
        lithium.warn("[HOOK][PROF] Diagnostics unavailable in current hook backend")
        return
    end

    local diag = hook.GetLithiumDiagnostics()
    local limit = tonumber(args[1]) or (top_n.GetInt and top_n:GetInt()) or 10

    lithium.info("[HOOK][PROF] enabled=" .. tostring(enabled.GetBool and enabled:GetBool() or false) .. " events=" .. tostring(diag.total_events) .. " calls=" .. tostring(diag.total_calls) .. " fallback_count=" .. tostring(diag.compatibility_fallbacks or 0))

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
end

if type(concommand_add) == "function" then
    concommand_add("lithium_hook_profiler_dump", function(_, _, args)
        dump_profiler(args or {})
        dump_dispatcher()
        dump_compatibility()
        dump_modules()
    end)

    concommand_add("lithium_hook_profiler_reset", function()
        if not hook.ResetLithiumDiagnostics then
            lithium.warn("[HOOK][PROF] Reset unavailable in current hook backend")
            return
        end

        hook.ResetLithiumDiagnostics()
        lithium.info("[HOOK][PROF] Diagnostics reset")
    end)

    concommand_add("lithium_hook_backend_status", function()
        dump_dispatcher()
    end)

    concommand_add("lithium_compat_dump", function()
        dump_compatibility()
    end)

    concommand_add("lithium_module_dump", function()
        dump_modules()
    end)
else
    lithium.warn("[HOOK][DIAG] concommand.Add unavailable; diagnostics commands not registered")
end

return M
