local M = {}

function M.enable(migrate_from)
    require("hook")

    if migrate_from then
        for event, event_table in pairs(migrate_from) do
            for name, fn in pairs(event_table) do
                hook.Add(event, name, fn)
            end
        end
    end

    return true
end

return M
