require("lithium")

local M = {}

function M.enable()
    local old_hook_table = hook.GetTable()
    require("hook_lithium")

    for event, event_table in pairs(old_hook_table) do
        for name, fn in pairs(event_table) do
            hook.Add(event, name, fn)
        end
    end

    return true
end

return M
