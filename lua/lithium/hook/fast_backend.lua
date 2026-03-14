require("lithium")

local M = {}

function M.enable(opts)
    opts = opts or {}

    local old_hook_table = hook.GetTable()
    require("hook_lithium")

    for event, event_table in pairs(old_hook_table) do
        for name, fn in pairs(event_table) do
            hook.Add(event, name, fn)
        end
    end

    local base_add = hook.Add
    hook.Add = function(event, name, func, priority)
        local info = debug.getinfo(2, "S") or {}
        local source = tostring(info.short_src or info.source or "unknown")

        if opts.compatibility and opts.on_policy_violation then
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
