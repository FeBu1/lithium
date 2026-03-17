require("lithium")

local M = {}
local realm_suffix = SERVER and "sv" or CLIENT and "cl" or "unk"

function M.realm_name(base, per_realm)
    if per_realm then
        return "lithium_" .. base .. "_" .. realm_suffix
    end
    return "lithium_" .. base
end

function M.bool(base, default, description, opts)
    opts = opts or {}
    if opts.client == false and CLIENT then return nil end
    if opts.server == false and SERVER then return nil end

    local name = M.realm_name(base, opts.per_realm ~= false)
    local cvar = GetConVar(name)
    if cvar then return cvar end

    local flags = opts.flags or { FCVAR_ARCHIVE }
    return CreateConVar(name, default and "1" or "0", flags, description or "", 0, 1)
end

return M
