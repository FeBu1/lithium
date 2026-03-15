local M = {}

function M.enable(migrate_from)
    require("hook")

    if migrate_from and migrate_from.ordered then
        for event, list in pairs(migrate_from.ordered) do
            for _, item in ipairs(list) do
                hook.Add(event, item.name, item.func)
            end
        end
        return true
    end

    if migrate_from and migrate_from.get_table then
        for event, event_table in pairs(migrate_from.get_table) do
            for name, fn in pairs(event_table) do
                hook.Add(event, name, fn)
            end
        end
    end

    return true
end

return M
