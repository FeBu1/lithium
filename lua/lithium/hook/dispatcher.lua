require("lithium")

local _G = _G
local os = os
local util = util

local type = type
local tostring = tostring
local pcall = pcall
local next_fn = next or (_G and _G.next)

local function fallback_pairs(t)
    local function iter(tbl, k)
        return next_fn and next_fn(tbl, k) or nil
    end
    return iter, t, nil
end

local pairs_fn = pairs or (_G and _G.pairs) or fallback_pairs

local selftests = include("lithium/hook/selftests.lua")
local fast = include("lithium/hook/fast_backend.lua")
local legacy = include("lithium/hook/legacy_backend.lua")

local Dispatcher = {
    active_mode = "legacy",
    last_error = nil,
    fallback_count = 0,
    fallback_events = {},
    fallback_suppressed = 0,
    migration_count = 0,
    migration_failures = 0,
    _last_reason = nil,
    _last_reason_time = 0
}

local function now()
    if os and os.time then return os.time() end
    return 0
end

local function record_fallback(reason, context)
    local t = now()
    if Dispatcher._last_reason == reason and t - Dispatcher._last_reason_time <= 2 then
        Dispatcher.fallback_suppressed = Dispatcher.fallback_suppressed + 1
        return
    end

    Dispatcher._last_reason = reason
    Dispatcher._last_reason_time = t

    Dispatcher.fallback_count = Dispatcher.fallback_count + 1
    Dispatcher.fallback_events[#Dispatcher.fallback_events + 1] = {
        reason = reason,
        context = context,
        when = t
    }

    lithium.warn("[HOOK][DISPATCH][FALLBACK] reason=" .. tostring(reason))
    if context then
        local ctx = util and util.TableToJSON and util.TableToJSON(context) or tostring(context)
        lithium.warn("[HOOK][DISPATCH][FALLBACK] context=" .. tostring(ctx))
    end
end

local function safe_snapshot()
    local snap = { get_table = nil, ordered = nil, export_error = nil, get_table_error = nil }

    local ok_get, get_table = pcall(function()
        return hook.GetTable and hook.GetTable() or nil
    end)
    if ok_get then
        snap.get_table = get_table
    else
        snap.get_table_error = tostring(get_table)
    end

    local ok_export, ordered = pcall(function()
        return hook.ExportLithiumHooksInOrder and hook.ExportLithiumHooksInOrder() or nil
    end)
    if ok_export then
        snap.ordered = ordered
    else
        snap.export_error = tostring(ordered)
    end

    return snap
end

local function degrade_snapshot(snapshot)
    local fallback = { get_table = nil, ordered = nil }

    if snapshot and snapshot.get_table and type(snapshot.get_table) == "table" then
        fallback.get_table = snapshot.get_table
    end

    if snapshot and snapshot.ordered and type(snapshot.ordered) == "table" then
        fallback.ordered = snapshot.ordered
    end

    if not fallback.ordered and fallback.get_table then
        local ordered = {}
        for event, event_table in pairs_fn(fallback.get_table) do
            local row = {}
            for name, fn in pairs_fn(event_table) do
                row[#row + 1] = { name = name, func = fn }
            end
            ordered[event] = row
        end
        fallback.ordered = ordered
    end

    return fallback
end

local function migrate_to_legacy(snapshot, reason)
    local migrate_data = degrade_snapshot(snapshot)

    local ok, err = pcall(function()
        legacy.enable(migrate_data)
    end)

    if not ok then
        Dispatcher.migration_failures = Dispatcher.migration_failures + 1
        Dispatcher.last_error = tostring(err)
        lithium.warn("[HOOK][DISPATCH][FALLBACK] migration failed, forcing empty legacy enable: " .. tostring(err))
        pcall(function() legacy.enable(nil) end)
    end

    Dispatcher.active_mode = "legacy"
    Dispatcher.migration_count = Dispatcher.migration_count + 1

    if snapshot and (snapshot.export_error or snapshot.get_table_error) then
        lithium.warn("[HOOK][DISPATCH][FALLBACK] snapshot degraded reason=" .. tostring(reason) .. " export_error=" .. tostring(snapshot.export_error) .. " get_table_error=" .. tostring(snapshot.get_table_error))
    end
end

function Dispatcher.select_mode(compatibility_state, mode_cvar)
    local mode = mode_cvar and mode_cvar.GetString and mode_cvar:GetString() or "auto"
    if mode == "legacy" then return "legacy" end
    if compatibility_state and compatibility_state.force_legacy then return "legacy" end
    return "fast"
end

function Dispatcher.fallback_to_legacy(reason, context)
    if Dispatcher.active_mode == "legacy" then
        return false
    end

    local snapshot = safe_snapshot()
    if hook.AddCompatibilityFallbackCount then
        hook.AddCompatibilityFallbackCount()
    end
    record_fallback(reason, context)
    migrate_to_legacy(snapshot, reason)
    return true
end

function Dispatcher.enable(mode, opts)
    opts = opts or {}

    if mode == "legacy" then
        legacy.enable()
        Dispatcher.active_mode = "legacy"
        lithium.info("[HOOK][DISPATCH] Legacy backend active")
        return true
    end

    local ok, err = pcall(function()
        fast.enable({
            compatibility = opts.compatibility,
            on_policy_violation = function(context)
                local matched = (context.policy and context.policy.matched_rules and context.policy.matched_rules[1])
                local reason = matched and matched.reason or "source policy violation"
                Dispatcher.fallback_to_legacy(reason, context)
            end
        })
    end)
    if not ok then
        Dispatcher.last_error = err
        record_fallback("fast backend load failed", { error = tostring(err) })
        legacy.enable()
        Dispatcher.active_mode = "legacy"
        return false
    end

    Dispatcher.active_mode = "fast"

    if not selftests.run() then
        record_fallback("self-tests failed", nil)
        local snapshot = safe_snapshot()
        migrate_to_legacy(snapshot, "self-tests failed")
        return false
    end

    if Dispatcher.active_mode ~= "fast" then
        lithium.warn("[HOOK][DISPATCH] self-tests changed backend mode to " .. tostring(Dispatcher.active_mode))
        return false
    end

    lithium.info("[HOOK][DISPATCH] Fast backend active")
    return true
end

function Dispatcher.get_stats()
    return {
        active_mode = Dispatcher.active_mode,
        fallback_count = Dispatcher.fallback_count,
        fallback_events = Dispatcher.fallback_events,
        fallback_suppressed = Dispatcher.fallback_suppressed,
        migration_count = Dispatcher.migration_count,
        migration_failures = Dispatcher.migration_failures,
        last_error = Dispatcher.last_error
    }
end

return Dispatcher
