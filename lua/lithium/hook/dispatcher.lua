require("lithium")

local selftests = include("lithium/hook/selftests.lua")
local fast = include("lithium/hook/fast_backend.lua")
local legacy = include("lithium/hook/legacy_backend.lua")

local Dispatcher = {
    active_mode = "legacy",
    last_error = nil,
    fallback_count = 0,
    fallback_events = {}
}

local function record_fallback(reason, context)
    Dispatcher.fallback_count = Dispatcher.fallback_count + 1
    Dispatcher.fallback_events[#Dispatcher.fallback_events + 1] = {
        reason = reason,
        context = context,
        when = os.time()
    }

    lithium.warn("[HOOK][FALLBACK] " .. tostring(reason))
    if context then
        local ctx = util and util.TableToJSON and util.TableToJSON(context) or tostring(context)
        lithium.warn("[HOOK][FALLBACK] context: " .. tostring(ctx))
    end
end

function Dispatcher.select_mode(compatibility_state, mode_cvar)
    local mode = mode_cvar and mode_cvar:GetString() or "auto"
    if mode == "legacy" then return "legacy" end
    if compatibility_state and compatibility_state.force_legacy then return "legacy" end
    return "fast"
end

function Dispatcher.fallback_to_legacy(reason, context)
    if Dispatcher.active_mode == "legacy" then
        return false
    end

    local migrate_table = hook.GetTable and hook.GetTable() or nil
    if hook.AddCompatibilityFallbackCount then
        hook.AddCompatibilityFallbackCount()
    end
    record_fallback(reason, context)
    legacy.enable(migrate_table)
    Dispatcher.active_mode = "legacy"
    return true
end

function Dispatcher.enable(mode, opts)
    opts = opts or {}

    if mode == "legacy" then
        legacy.enable()
        Dispatcher.active_mode = "legacy"
        lithium.info("[HOOK] Legacy backend active")
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

    if not selftests.run() then
        record_fallback("self-tests failed", nil)
        legacy.enable(hook.GetTable and hook.GetTable() or nil)
        Dispatcher.active_mode = "legacy"
        return false
    end

    Dispatcher.active_mode = "fast"
    lithium.info("[HOOK] Fast backend active")
    return true
end

function Dispatcher.get_stats()
    return {
        active_mode = Dispatcher.active_mode,
        fallback_count = Dispatcher.fallback_count,
        fallback_events = Dispatcher.fallback_events,
        last_error = Dispatcher.last_error
    }
end

return Dispatcher
