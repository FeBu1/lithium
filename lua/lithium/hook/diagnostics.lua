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

local function source_bucket(path)
    path = tostring(path or "unknown")
    local low = string.lower(path)
    if string.find(low, "workshop/content", 1, true) then return "workshop_content" end
    if string.find(low, "addons/", 1, true) then return "addons" end
    if string.find(low, "gamemodes/", 1, true) then return "gamemodes" end
    if string.find(low, "lua/includes/", 1, true) then return "engine_includes" end
    if string.find(low, "lua/", 1, true) then return "base_lua" end
    return "other"
end

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

local function get_net_report(limit)
    return lithium.net_diagnostics and lithium.net_diagnostics.get_report and lithium.net_diagnostics.get_report(limit) or nil
end

local function build_header(disp, compat, diag)
    local map = game and game.GetMap and game.GetMap() or "unknown"
    local players = player and player.GetCount and player.GetCount() or -1
    return {
        generated_at = os and os.date and os.date("!%Y-%m-%dT%H:%M:%SZ") or "unknown",
        map = map,
        player_count = players,
        backend_mode = disp.active_mode or "unknown",
        fallback_occurred = (disp.fallback_count or 0) > 0,
        fallback_count = disp.fallback_count or 0,
        migration_count = disp.migration_count or 0,
        compat_matches = compat.source_matches or 0,
        profiler_samples = diag.profiler_samples or 0,
        total_calls = diag.total_calls or 0,
        total_events = diag.total_events or 0
    }
end

local function build_tuning_suggestions(diag, disp, compat, limit)
    local suggestions = {
        heuristic = true,
        likely_overbroad_legacy_rules = {},
        hot_sources_no_compat_action = {},
        observe_sources_maybe_escalate = {},
        force_legacy_sources_maybe_downgrade = {},
        addon_patch_candidates = {}
    }

    local source_actions = compat.source_actions_by_source or {}
    local source_rule_hits = compat.source_match_rules or {}
    local source_rule_meta = compat.source_rule_meta or {}

    for rule_id, hits in pairs(source_rule_hits) do
        local meta = source_rule_meta[rule_id]
        if meta and meta.action == "force_legacy" and hits >= 25 and (disp.migration_count or 0) == 0 then
            suggestions.likely_overbroad_legacy_rules[#suggestions.likely_overbroad_legacy_rules + 1] = {
                rule_id = rule_id,
                hits = hits,
                reason = "high force_legacy hits with no runtime migration observed",
                origin = meta.origin,
                source_pattern = meta.source_pattern
            }
        end
    end

    local top_sources = top_from_map(diag.by_source or {}, function(source, item)
        return { source = source, time = item.time or 0, calls = item.calls or 0, hooks = item.hooks or 0 }
    end, function(a, b) return a.time > b.time end, limit)

    local fallback_by_source = {}
    for _, item in ipairs(disp.fallback_events or {}) do
        local src = item.context and item.context.source or "unknown"
        fallback_by_source[src] = (fallback_by_source[src] or 0) + 1
    end

    for _, s in ipairs(top_sources) do
        local actions = source_actions[s.source]
        if not actions then
            suggestions.hot_sources_no_compat_action[#suggestions.hot_sources_no_compat_action + 1] = {
                source = s.source,
                time = s.time,
                calls = s.calls,
                reason = "hot source with no compatibility action observed"
            }
            suggestions.addon_patch_candidates[#suggestions.addon_patch_candidates + 1] = {
                source = s.source,
                bucket = source_bucket(s.source),
                time = s.time,
                reason = "high-cost source candidate for targeted patch"
            }
        else
            if (actions.observe or 0) >= 10 and s.time > 0.001 then
                suggestions.observe_sources_maybe_escalate[#suggestions.observe_sources_maybe_escalate + 1] = {
                    source = s.source,
                    observe_hits = actions.observe,
                    time = s.time,
                    reason = "frequent observe hits with measurable cost"
                }
            end
            if (actions.force_legacy or 0) >= 10 and (fallback_by_source[s.source] or 0) == 0 and s.time < 0.0005 then
                suggestions.force_legacy_sources_maybe_downgrade[#suggestions.force_legacy_sources_maybe_downgrade + 1] = {
                    source = s.source,
                    force_legacy_hits = actions.force_legacy,
                    time = s.time,
                    reason = "many force_legacy matches but very low cost/no fallback evidence"
                }
            end
        end
    end

    return suggestions
end

local function merge_net_tuning_suggestions(suggestions, net_report)
    if not net_report or not net_report.suggestions then
        return
    end

    suggestions.network_candidates = {
        heuristic = true,
        broadcast_heavy_messages = net_report.suggestions.broadcast_heavy_messages or {},
        candidate_event_spam_messages = net_report.suggestions.candidate_event_spam_messages or {},
        candidate_large_payload_messages = net_report.suggestions.candidate_large_payload_messages or {}
    }
end

local function build_report(limit)
    local diag = hook.GetLithiumDiagnostics and hook.GetLithiumDiagnostics() or {}
    local disp = get_dispatcher_stats() or {}
    local compat = get_compat_stats() or {}
    local net_report = get_net_report(limit)
    local modules = lithium.module_summary or {}
    local patches = lithium.addon_patch_summary or {}

    local top_events = top_from_map(diag.by_event or {}, function(event, item)
        return { event = event, calls = item.calls or 0, time = item.time or 0 }
    end, function(a, b) return a.time > b.time end, limit)

    local top_hooks = top_from_map(diag.by_hook or {}, function(key, item)
        return { key = key, calls = item.calls or 0, time = item.time or 0, source = item.source or "unknown" }
    end, function(a, b) return a.time > b.time end, limit)

    local top_sources = top_from_map(diag.by_source or {}, function(source, item)
        return { source = source, calls = item.calls or 0, time = item.time or 0, hooks = item.hooks or 0, bucket = source_bucket(source) }
    end, function(a, b) return a.time > b.time end, limit)

    local source_groups = {}
    for source, item in pairs(diag.by_source or {}) do
        local bucket = source_bucket(source)
        local g = source_groups[bucket] or { time = 0, calls = 0, hooks = 0 }
        g.time = g.time + (item.time or 0)
        g.calls = g.calls + (item.calls or 0)
        g.hooks = g.hooks + (item.hooks or 0)
        source_groups[bucket] = g
    end
    local top_source_groups = top_from_map(source_groups, function(bucket, item)
        return { bucket = bucket, time = item.time, calls = item.calls, hooks = item.hooks }
    end, function(a, b) return a.time > b.time end, 16)

    local compat_rule_hits = top_from_map(compat.source_match_rules or {}, function(rule_id, hits)
        local meta = compat.source_rule_meta and compat.source_rule_meta[rule_id] or nil
        return {
            rule_id = rule_id,
            hits = hits,
            action = meta and meta.action or "unknown",
            origin = meta and meta.origin or "unknown",
            source_pattern = meta and meta.source_pattern or ""
        }
    end, function(a, b) return a.hits > b.hits end, 64)

    local fallback_by_source = {}
    for _, item in ipairs((disp and disp.fallback_events) or {}) do
        local src = item.context and item.context.source or "unknown"
        fallback_by_source[src] = (fallback_by_source[src] or 0) + 1
    end
    local top_fallback_sources = top_from_map(fallback_by_source, function(source, hits)
        return { source = source, hits = hits, bucket = source_bucket(source) }
    end, function(a, b) return a.hits > b.hits end, limit)

    local report = {
        header = build_header(disp, compat, diag),
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
        patches = {
            total = patches.total or 0,
            applied = patches.applied or 0,
            failed = patches.failed or 0,
            failed_detail = patches.failed_detail or {}
        },
        profiler = {
            enabled = enabled.GetBool and enabled:GetBool() or false,
            total_events = diag.total_events or 0,
            total_calls = diag.total_calls or 0,
            profiler_samples = diag.profiler_samples or 0,
            compatibility_fallbacks = diag.compatibility_fallbacks or 0,
            top_events = top_events,
            top_hooks = top_hooks,
            top_sources = top_sources,
            top_source_groups = top_source_groups
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
            source_rule_hits = compat_rule_hits,
            source_rule_meta = compat.source_rule_meta or {}
        },
        tuning_suggestions = build_tuning_suggestions(diag, disp, compat, limit)
    }

    report.net = net_report
    merge_net_tuning_suggestions(report.tuning_suggestions, net_report)
    return report
end

local function log_report(report)
    lithium.info("[LITHIUM][REPORT] === Session report ===")
    lithium.info("[LITHIUM][REPORT] header map=" .. tostring(report.header.map) .. " players=" .. tostring(report.header.player_count) .. " backend=" .. tostring(report.header.backend_mode))
    lithium.info("[LITHIUM][REPORT] backend mode=" .. tostring(report.backend.mode) .. " fallback_count=" .. tostring(report.backend.fallback_count) .. " migrations=" .. tostring(report.backend.migration_count or 0) .. " suppressed=" .. tostring(report.backend.fallback_suppressed))
    lithium.info("[LITHIUM][REPORT] modules loaded=" .. tostring(#report.modules.loaded) .. " skipped=" .. tostring(#report.modules.skipped) .. " failed=" .. tostring(#report.modules.failed))
    lithium.info("[LITHIUM][REPORT] patches total=" .. tostring(report.patches.total) .. " applied=" .. tostring(report.patches.applied) .. " failed=" .. tostring(report.patches.failed))
    lithium.info("[LITHIUM][REPORT] profiler enabled=" .. tostring(report.profiler.enabled) .. " samples=" .. tostring(report.profiler.profiler_samples) .. " events=" .. tostring(report.profiler.total_events) .. " calls=" .. tostring(report.profiler.total_calls))
    lithium.info("[LITHIUM][REPORT] compatibility addon_matches=" .. tostring(report.compatibility.addon_matches) .. " source_matches=" .. tostring(report.compatibility.source_matches) .. " unique_sources=" .. tostring(report.compatibility.unique_sources))
    if report.net then
        lithium.info("[LITHIUM][REPORT] net enabled=" .. tostring(report.net.enabled) .. " sends=" .. tostring(report.net.total_sends) .. " bytes=" .. tostring(report.net.total_bytes))
    end

    for i, e in ipairs(report.profiler.top_events) do
        lithium.info(string.format("[LITHIUM][REPORT] TOP_EVENT #%d %s calls=%d time=%.6f", i, e.event, e.calls, e.time))
    end
    for i, h in ipairs(report.profiler.top_hooks) do
        lithium.info(string.format("[LITHIUM][REPORT] TOP_HOOK #%d %s calls=%d time=%.6f source=%s", i, h.key, h.calls, h.time, h.source))
    end
    for i, s in ipairs(report.profiler.top_sources) do
        lithium.info(string.format("[LITHIUM][REPORT] TOP_SOURCE #%d %s bucket=%s calls=%d hooks=%d time=%.6f", i, s.source, s.bucket, s.calls, s.hooks, s.time))
    end
    for i, g in ipairs(report.profiler.top_source_groups or {}) do
        lithium.info(string.format("[LITHIUM][REPORT] TOP_GROUP #%d %s calls=%d hooks=%d time=%.6f", i, g.bucket, g.calls, g.hooks, g.time))
    end
    for i = 1, math.min(10, #report.backend.fallback_events) do
        local item = report.backend.fallback_events[#report.backend.fallback_events - i + 1]
        lithium.info("[LITHIUM][REPORT] FALLBACK[" .. i .. "] reason=" .. tostring(item.reason) .. " when=" .. tostring(item.when))
    end
    for i, item in ipairs(report.backend.top_fallback_sources or {}) do
        lithium.info("[LITHIUM][REPORT] FALLBACK_SOURCE[" .. i .. "] source=" .. tostring(item.source) .. " bucket=" .. tostring(item.bucket) .. " hits=" .. tostring(item.hits))
    end

    if report.net then
        for i, item in ipairs(report.net.top_messages_by_bytes or {}) do
            lithium.info(string.format("[LITHIUM][REPORT] NET_TOP_BYTES #%d %s sends=%d bytes=%d avg=%.1f max=%d", i, item.name, item.sends, item.bytes, item.avg_bytes, item.max_bytes))
        end
        for i, item in ipairs(report.net.top_sources_by_bytes or {}) do
            lithium.info(string.format("[LITHIUM][REPORT] NET_TOP_SOURCE #%d %s bucket=%s sends=%d bytes=%d", i, item.source, item.bucket, item.sends, item.bytes))
        end
        for i, item in ipairs(report.net.top_source_groups or {}) do
            lithium.info(string.format("[LITHIUM][REPORT] NET_TOP_GROUP #%d %s sends=%d bytes=%d", i, item.bucket, item.sends, item.bytes))
        end
    end
end

local function log_tuning_summary(report)
    local t = report.tuning_suggestions
    lithium.info("[LITHIUM][TUNING] heuristic summary (suggestions, not truth)")

    for i, item in ipairs(t.likely_overbroad_legacy_rules) do
        lithium.info("[LITHIUM][TUNING] overbroad_rule[" .. i .. "] id=" .. tostring(item.rule_id) .. " hits=" .. tostring(item.hits) .. " reason=" .. tostring(item.reason))
    end
    for i, item in ipairs(t.hot_sources_no_compat_action) do
        lithium.info("[LITHIUM][TUNING] hot_no_action[" .. i .. "] source=" .. tostring(item.source) .. " time=" .. tostring(item.time))
    end
    for i, item in ipairs(t.observe_sources_maybe_escalate) do
        lithium.info("[LITHIUM][TUNING] observe_escalate[" .. i .. "] source=" .. tostring(item.source) .. " observe_hits=" .. tostring(item.observe_hits) .. " time=" .. tostring(item.time))
    end
    for i, item in ipairs(t.force_legacy_sources_maybe_downgrade) do
        lithium.info("[LITHIUM][TUNING] legacy_downgrade[" .. i .. "] source=" .. tostring(item.source) .. " force_hits=" .. tostring(item.force_legacy_hits) .. " time=" .. tostring(item.time))
    end
    for i, item in ipairs(t.addon_patch_candidates) do
        lithium.info("[LITHIUM][TUNING] patch_candidate[" .. i .. "] source=" .. tostring(item.source) .. " bucket=" .. tostring(item.bucket) .. " time=" .. tostring(item.time))
    end

    local n = t.network_candidates
    if n then
        for i, item in ipairs(n.broadcast_heavy_messages or {}) do
            lithium.info("[LITHIUM][TUNING] net_broadcast_heavy[" .. i .. "] msg=" .. tostring(item.name) .. " avg_recipients=" .. tostring(item.avg_recipients) .. " sends=" .. tostring(item.sends))
        end
        for i, item in ipairs(n.candidate_event_spam_messages or {}) do
            lithium.info("[LITHIUM][TUNING] net_event_spam_candidate[" .. i .. "] msg=" .. tostring(item.name) .. " sends=" .. tostring(item.sends) .. " avg_bytes=" .. tostring(item.avg_bytes))
        end
        for i, item in ipairs(n.candidate_large_payload_messages or {}) do
            lithium.info("[LITHIUM][TUNING] net_large_payload_candidate[" .. i .. "] msg=" .. tostring(item.name) .. " max_bytes=" .. tostring(item.max_bytes) .. " avg_bytes=" .. tostring(item.avg_bytes))
        end
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
    lithium.info("[HOOK][DIAG] backend=" .. tostring(disp.active_mode) .. " fallback_count=" .. tostring(disp.fallback_count) .. " suppressed=" .. tostring(disp.fallback_suppressed or 0) .. " migrations=" .. tostring(disp.migration_count or 0))
end

local function dump_compat_only()
    local compat = get_compat_stats()
    if not compat then
        lithium.warn("[HOOK][DIAG] Compatibility stats unavailable")
        return
    end
    lithium.info("[HOOK][DIAG] compat addon_matches=" .. tostring(compat.addon_matches) .. " source_matches=" .. tostring(compat.source_matches) .. " builtin=" .. tostring(compat.source_match_builtin or 0) .. " custom=" .. tostring(compat.source_match_custom or 0) .. " unique_sources=" .. tostring(compat.unique_sources or 0))
    lithium.info("[HOOK][DIAG] compat actions force_legacy=" .. tostring(compat.force_legacy_matches or 0) .. " feature_hint=" .. tostring(compat.feature_hint_matches or 0) .. " observe=" .. tostring(compat.observe_matches or 0))
end

local function dump_modules_only()
    local ms = lithium.module_summary
    if not ms then
        lithium.warn("[HOOK][DIAG] Module summary unavailable")
        return
    end
    lithium.info("[HOOK][DIAG] modules loaded=" .. tostring(#(ms.loaded or {})) .. " failed=" .. tostring(#(ms.failed or {})) .. " skipped=" .. tostring(#(ms.skipped or {})))

    local ps = lithium.addon_patch_summary
    if ps then
        lithium.info("[HOOK][DIAG] patches total=" .. tostring(ps.total or 0) .. " applied=" .. tostring(ps.applied or 0) .. " failed=" .. tostring(ps.failed or 0))
    end
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

    concommand_add("lithium_tuning_summary", function(_, _, args)
        local limit = tonumber(args and args[1]) or (top_n.GetInt and top_n:GetInt()) or 15
        log_tuning_summary(build_report(limit))
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

    concommand_add("lithium_hook_backend_status", function() dump_backend_only() end)
    concommand_add("lithium_compat_dump", function() dump_compat_only() end)
    concommand_add("lithium_module_dump", function() dump_modules_only() end)

    concommand_add("lithium_net_dump", function(_, _, args)
        if not (lithium.net_diagnostics and lithium.net_diagnostics.get_report) then
            lithium.warn("[NET][DIAG] net.diagnostics module is not loaded (enable lithium_net_diagnostics_*)")
            return
        end
        local limit = tonumber(args and args[1]) or (top_n.GetInt and top_n:GetInt()) or 15
        local net_report = lithium.net_diagnostics.get_report(limit)
        lithium.info("[NET][DIAG] enabled=" .. tostring(net_report.enabled) .. " sends=" .. tostring(net_report.total_sends) .. " bytes=" .. tostring(net_report.total_bytes))
        for i, item in ipairs(net_report.top_messages_by_bytes or {}) do
            lithium.info(string.format("[NET][DIAG] TOP_BYTES #%d %s sends=%d bytes=%d avg=%.1f max=%d", i, item.name, item.sends, item.bytes, item.avg_bytes, item.max_bytes))
        end
    end)

    concommand_add("lithium_net_reset", function()
        if not (lithium.net_diagnostics and lithium.net_diagnostics.reset) then
            lithium.warn("[NET][DIAG] net.diagnostics module is not loaded")
            return
        end
        lithium.net_diagnostics.reset()
        lithium.info("[NET][DIAG] reset")
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
