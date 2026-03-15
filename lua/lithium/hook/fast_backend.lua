require("lithium")

local _G = _G
local type = type
local tostring = tostring
local pcall = pcall
local next_fn = next or (_G and _G.next)
local debug_getinfo = debug and debug.getinfo

local function fallback_pairs(t)
    local function iter(tbl, k)
        return next_fn and next_fn(tbl, k) or nil
    end
    return iter, t, nil
end

local pairs_fn = pairs or (_G and _G.pairs) or fallback_pairs

local M = {}

function M.enable(opts)
    opts = opts or {}

    local old_hook_table = hook.GetTable and hook.GetTable() or {}
    require("hook_lithium")

    for event, event_table in pairs_fn(old_hook_table) do
        for name, fn in pairs_fn(event_table) do
            hook.Add(event, name, fn)
        end
    end

    local base_add = hook.Add
    hook.Add = function(event, name, func, priority)
        local info = debug_getinfo and debug_getinfo(2, "S") or {}
        local source = tostring(info.short_src or info.source or "unknown")

        if opts.compatibility and opts.on_policy_violation and opts.compatibility.evaluate_source then
            local policy = opts.compatibility.evaluate_source(source, event, name)
            if policy and policy.use_legacy_hook then
                opts.on_policy_violation({
                    source = source,
                    event = tostring(event),
                    name = tostring(name),
                    policy = policy
                })
            end
        end

        return base_add(event, name, func, priority)
    end

    return true
end

return M
