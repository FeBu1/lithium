require("lithium")

local selftests = include("lithium/hook/selftests.lua")
local fast = include("lithium/hook/fast_backend.lua")
local legacy = include("lithium/hook/legacy_backend.lua")

local Dispatcher = {
    active_mode = "legacy",
    last_error = nil,
    fallback_count = 0,
    fallback_events = {},
    fallback_suppressed = 0,
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

local function migration_snapshot()
    local snap = {
        get_table = hook.GetTable and hook.GetTable() or nil,
        ordered = hook.ExportLithiumHooksInOrder and hook.ExportLithiumHooksInOrder() or nil
    }
    return snap
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

    local migrate_data = migration_snapshot()
    if hook.AddCompatibilityFallbackCount then
        hook.AddCompatibilityFallbackCount()
    end
    record_fallback(reason, context)
    legacy.enable(migrate_data)
    Dispatcher.active_mode = "legacy"
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
        legacy.enable(migration_snapshot())
        Dispatcher.active_mode = "legacy"
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
        last_error = Dispatcher.last_error
    }
end

return Dispatcher
