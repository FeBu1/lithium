local _G = _G
local next_fn = next or (_G and _G.next)

local function fallback_pairs(t)
    local function iter(tbl, k)
        return next_fn and next_fn(tbl, k) or nil
    end
    return iter, t, nil
end

local function fallback_ipairs(t)
    local function iter(tbl, i)
        i = i + 1
        local v = tbl[i]
        if v ~= nil then
            return i, v
        end
    end
    return iter, t, 0
end

local pairs_fn = pairs or (_G and _G.pairs) or fallback_pairs
local ipairs_fn = ipairs or (_G and _G.ipairs) or fallback_ipairs

local M = {}

function M.enable(migrate_from)
    require("hook")

    if migrate_from and migrate_from.ordered then
        for event, list in pairs_fn(migrate_from.ordered) do
            for _, item in ipairs_fn(list) do
                hook.Add(event, item.name, item.func)
            end
        end
        return true
    end

    if migrate_from and migrate_from.get_table then
        for event, event_table in pairs_fn(migrate_from.get_table) do
            for name, fn in pairs_fn(event_table) do
                hook.Add(event, name, fn)
            end
        end
    end

    return true
end

return M
