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
local top_n = safe_num("lithium_hook_profiler_topn", 15)

local function top_from_map(map, mapfn, sorter, limit)
    local out = {}
    for k, v in pairs(map or {}) do
        out[#out + 1] = mapfn(k, v)
    end
    table.sort(out, sorter)
    local capped = {}
    for i = 1, math.min(limit, #out) do
        capped[#capped + 1] = out[i]
    end
    return capped
end

local function get_dispatcher_stats()
    return lithium.hook_dispatcher and lithium.hook_dispatcher.get_stats and lithium.hook_dispatcher.get_stats() or nil
end

local function get_compat_stats()
    return lithium.compatibility_registry and lithium.compatibility_registry.get_stats and lithium.compatibility_registry.get_stats() or nil
end

local function build_report(limit)
    local diag = hook.GetLithiumDiagnostics and hook.GetLithiumDiagnostics() or {}
    local disp = get_dispatcher_stats() or {}
    local compat = get_compat_stats() or {}
    local modules = lithium.module_summary or {}

    local top_events = top_from_map(diag.by_event or {}, function(event, item)
        return { event = event, calls = item.calls or 0, time = item.time or 0 }
    end, function(a, b) return a.time > b.time end, limit)

    local top_hooks = top_from_map(diag.by_hook or {}, function(key, item)
        return { key = key, calls = item.calls or 0, time = item.time or 0, source = item.source or "unknown" }
    end, function(a, b) return a.time > b.time end, limit)

    local top_sources = top_from_map(diag.by_source or {}, function(source, item)
        return { source = source, calls = item.calls or 0, time = item.time or 0, hooks = item.hooks or 0 }
    end, function(a, b) return a.time > b.time end, limit)

    local compat_rule_hits = top_from_map(compat.source_match_rules or {}, function(rule_id, hits)
        return { rule_id = rule_id, hits = hits }
    end, function(a, b) return a.hits > b.hits end, 50)

    local fallback_by_source = {}
    for _, item in ipairs((disp and disp.fallback_events) or {}) do
        local src = item.context and item.context.source or "unknown"
        fallback_by_source[src] = (fallback_by_source[src] or 0) + 1
    end
    local top_fallback_sources = top_from_map(fallback_by_source, function(source, hits)
        return { source = source, hits = hits }
    end, function(a, b) return a.hits > b.hits end, limit)

    return {
        generated_at = os and os.date and os.date("!%Y-%m-%dT%H:%M:%SZ") or "unknown",
        backend = {
            mode = disp.active_mode or "unknown",
            fallback_count = disp.fallback_count or 0,
            fallback_suppressed = disp.fallback_suppressed or 0,
            migration_count = disp.migration_count or 0,
            fallback_events = disp.fallback_events or {},
            top_fallback_sources = top_fallback_sources
        },
        modules = {
            loaded = modules.loaded or {},
            skipped = modules.skipped or {},
            failed = modules.failed or {}
        },
        profiler = {
            enabled = enabled.GetBool and enabled:GetBool() or false,
            total_events = diag.total_events or 0,
            total_calls = diag.total_calls or 0,
            profiler_samples = diag.profiler_samples or 0,
            compatibility_fallbacks = diag.compatibility_fallbacks or 0,
            top_events = top_events,
            top_hooks = top_hooks,
            top_sources = top_sources
        },
        compatibility = {
            addon_matches = compat.addon_matches or 0,
            source_matches = compat.source_matches or 0,
            source_match_builtin = compat.source_match_builtin or 0,
            source_match_custom = compat.source_match_custom or 0,
            force_legacy_matches = compat.force_legacy_matches or 0,
            feature_hint_matches = compat.feature_hint_matches or 0,
            observe_matches = compat.observe_matches or 0,
            unique_sources = compat.unique_sources or 0,
            last_source_match = compat.last_source_match,
            last_addon_match = compat.last_addon_match,
            reasons = compat.reasons or {},
            source_rule_hits = compat_rule_hits
        }
    }
end

local function log_report(report)
    lithium.info("[LITHIUM][REPORT] === Session report ===")
    lithium.info("[LITHIUM][REPORT] backend mode=" .. tostring(report.backend.mode) .. " fallback_count=" .. tostring(report.backend.fallback_count) .. " migrations=" .. tostring(report.backend.migration_count or 0) .. " suppressed=" .. tostring(report.backend.fallback_suppressed))
    lithium.info("[LITHIUM][REPORT] modules loaded=" .. tostring(#report.modules.loaded) .. " skipped=" .. tostring(#report.modules.skipped) .. " failed=" .. tostring(#report.modules.failed))
    lithium.info("[LITHIUM][REPORT] profiler enabled=" .. tostring(report.profiler.enabled) .. " samples=" .. tostring(report.profiler.profiler_samples) .. " events=" .. tostring(report.profiler.total_events) .. " calls=" .. tostring(report.profiler.total_calls))
    lithium.info("[LITHIUM][REPORT] compatibility addon_matches=" .. tostring(report.compatibility.addon_matches) .. " source_matches=" .. tostring(report.compatibility.source_matches) .. " unique_sources=" .. tostring(report.compatibility.unique_sources))

    for i, e in ipairs(report.profiler.top_events) do
        lithium.info(string.format("[LITHIUM][REPORT] TOP_EVENT #%d %s calls=%d time=%.6f", i, e.event, e.calls, e.time))
    end
    for i, h in ipairs(report.profiler.top_hooks) do
        lithium.info(string.format("[LITHIUM][REPORT] TOP_HOOK #%d %s calls=%d time=%.6f source=%s", i, h.key, h.calls, h.time, h.source))
    end
    for i, s in ipairs(report.profiler.top_sources) do
        lithium.info(string.format("[LITHIUM][REPORT] TOP_SOURCE #%d %s calls=%d hooks=%d time=%.6f", i, s.source, s.calls, s.hooks, s.time))
    end
    for i = 1, math.min(10, #report.backend.fallback_events) do
        local item = report.backend.fallback_events[#report.backend.fallback_events - i + 1]
        lithium.info("[LITHIUM][REPORT] FALLBACK[" .. i .. "] reason=" .. tostring(item.reason) .. " when=" .. tostring(item.when))
    end
    for i, item in ipairs(report.backend.top_fallback_sources or {}) do
        lithium.info("[LITHIUM][REPORT] FALLBACK_SOURCE[" .. i .. "] source=" .. tostring(item.source) .. " hits=" .. tostring(item.hits))
    end
    for i = 1, math.min(10, #report.compatibility.source_rule_hits) do
        local r = report.compatibility.source_rule_hits[i]
        lithium.info("[LITHIUM][REPORT] RULE_HIT[" .. i .. "] id=" .. tostring(r.rule_id) .. " hits=" .. tostring(r.hits))
    end
end

local function export_report(report)
    if not (file and file.Write and util and util.TableToJSON) then
        lithium.warn("[LITHIUM][REPORT] Export unavailable (file/util globals missing)")
        return nil
    end

    local stamp = os and os.date and os.date("%Y%m%d_%H%M%S") or tostring(math.floor((RealTime and RealTime() or 0) * 1000))
    local path = "lithium/reports/report_" .. stamp .. ".json"
    file.Write(path, util.TableToJSON(report, true))
    return path
end

local function dump_backend_only()
    local disp = get_dispatcher_stats()
    if not disp then
        lithium.warn("[HOOK][DIAG] Dispatcher stats unavailable")
        return
    end
    lithium.info("[HOOK][DIAG] backend=" .. tostring(disp.active_mode) .. " fallback_count=" .. tostring(disp.fallback_count) .. " suppressed=" .. tostring(disp.fallback_suppressed or 0))
end

local function dump_compat_only()
    local compat = get_compat_stats()
    if not compat then
        lithium.warn("[HOOK][DIAG] Compatibility stats unavailable")
        return
    end
    lithium.info("[HOOK][DIAG] compat addon_matches=" .. tostring(compat.addon_matches) .. " source_matches=" .. tostring(compat.source_matches) .. " builtin=" .. tostring(compat.source_match_builtin or 0) .. " custom=" .. tostring(compat.source_match_custom or 0) .. " unique_sources=" .. tostring(compat.unique_sources or 0))
    lithium.info("[HOOK][DIAG] compat actions force_legacy=" .. tostring(compat.force_legacy_matches or 0) .. " feature_hint=" .. tostring(compat.feature_hint_matches or 0) .. " observe=" .. tostring(compat.observe_matches or 0))

    if compat.last_source_match then
        local m = compat.last_source_match
        lithium.info("[HOOK][DIAG] compat last_source id=" .. tostring(m.id) .. " origin=" .. tostring(m.origin) .. " action=" .. tostring(m.action) .. " source=" .. tostring(m.source))
    end

    local top_rules = top_from_map(compat.source_match_rules or {}, function(id, hits)
        return { id = id, hits = hits }
    end, function(a, b) return a.hits > b.hits end, 10)
    for i, r in ipairs(top_rules) do
        lithium.info("[HOOK][DIAG] compat top_rule[" .. i .. "] id=" .. tostring(r.id) .. " hits=" .. tostring(r.hits))
    end
end

local function dump_modules_only()
    local ms = lithium.module_summary
    if not ms then
        lithium.warn("[HOOK][DIAG] Module summary unavailable")
        return
    end
    lithium.info("[HOOK][DIAG] modules loaded=" .. tostring(#(ms.loaded or {})) .. " failed=" .. tostring(#(ms.failed or {})) .. " skipped=" .. tostring(#(ms.skipped or {})))
end

if type(concommand_add) == "function" then
    concommand_add("lithium_hook_profiler_dump", function(_, _, args)
        local limit = tonumber(args and args[1]) or (top_n.GetInt and top_n:GetInt()) or 15
        log_report(build_report(limit))
    end)

    concommand_add("lithium_report_dump", function(_, _, args)
        local limit = tonumber(args and args[1]) or (top_n.GetInt and top_n:GetInt()) or 15
        log_report(build_report(limit))
    end)

    concommand_add("lithium_report_export", function(_, _, args)
        local limit = tonumber(args and args[1]) or (top_n.GetInt and top_n:GetInt()) or 15
        local report = build_report(limit)
        local path = export_report(report)
        if path then
            lithium.info("[LITHIUM][REPORT] Exported: data/" .. path)
        end
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
        dump_backend_only()
    end)

    concommand_add("lithium_compat_dump", function()
        dump_compat_only()
    end)

    concommand_add("lithium_module_dump", function()
        dump_modules_only()
    end)

    concommand_add("lithium_compat_rules_list", function()
        local registry = lithium.compatibility_registry
        local rules = registry and registry.get_source_rules and registry.get_source_rules() or nil
        if not rules then
            lithium.warn("[COMPAT][RULE] Source rule list unavailable")
            return
        end

        local rows = {}
        for id, rule in pairs(rules) do
            rows[#rows + 1] = {
                id = id,
                origin = rule.origin or "builtin",
                source_pattern = rule.source_pattern or "",
                action = rule.use_legacy_hook and "force_legacy" or ((rule.disable_features and #rule.disable_features > 0) and "feature_hint" or "observe")
            }
        end
        table.sort(rows, function(a, b) return a.id < b.id end)
        for _, row in ipairs(rows) do
            lithium.info("[COMPAT][RULE] id=" .. row.id .. " origin=" .. row.origin .. " action=" .. row.action .. " source_pattern=" .. row.source_pattern)
        end
    end)

    concommand_add("lithium_compat_add_custom_rule", function(_, _, args)
        local id = tostring(args[1] or "")
        local source_pattern = tostring(args[2] or "")
        local action = tostring(args[3] or "observe")
        local reason = tostring(args[4] or "custom rule from console")

        if id == "" or source_pattern == "" then
            lithium.warn("[COMPAT][RULE] Usage: lithium_compat_add_custom_rule <id> <source_pattern> [observe|feature_hint|force_legacy] [reason]")
            return
        end
        if not (lithium.compatibility_registry and lithium.compatibility_registry.register_custom_source_rule) then
            lithium.warn("[COMPAT][RULE] Compatibility registry unavailable")
            return
        end

        local rule = { source_pattern = source_pattern, reason = reason }
        if action == "force_legacy" then
            rule.use_legacy_hook = true
        elseif action == "feature_hint" then
            rule.disable_features = { "compat_hint" }
        else
            rule.observe_only = true
        end

        lithium.compatibility_registry.register_custom_source_rule(id, rule)
        if lithium.compatibility_registry.save_custom_rules then
            lithium.compatibility_registry.save_custom_rules()
        end
        lithium.info("[COMPAT][RULE] Added custom rule id=" .. id .. " action=" .. action .. " source_pattern=" .. source_pattern)
    end)
else
    lithium.warn("[HOOK][DIAG] concommand.Add unavailable; diagnostics commands not registered")
end

return M
