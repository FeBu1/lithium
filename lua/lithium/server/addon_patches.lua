require("lithium")

local M = {
    patches = {},
    applied = {},
    failed = {}
}

local CreateConVarFn = CreateConVar

local function mk_patch_convar(id, default_enabled)
    if type(CreateConVarFn) ~= "function" then
        return { GetBool = function() return default_enabled == true end }
    end

    return CreateConVar(
        "lithium_patch_" .. id,
        default_enabled and "1" or "0",
        { FCVAR_ARCHIVE },
        "Enable Lithium targeted addon patch: " .. id,
        0,
        1
    )
end

function M.register_patch(def)
    if not def or not def.id or type(def.apply) ~= "function" then
        return false
    end

    def.description = def.description or "No description"
    def.default_enabled = def.default_enabled == true
    def.convar = mk_patch_convar(def.id, def.default_enabled)
    M.patches[def.id] = def
    return true
end

local function should_apply(def)
    if def.realm == "server" and not SERVER then return false, "wrong realm" end
    if def.realm == "client" and not CLIENT then return false, "wrong realm" end
    if def.convar and def.convar.GetBool and not def.convar:GetBool() then
        return false, "disabled by convar"
    end
    return true
end

function M.apply_all()
    for id, def in pairs(M.patches) do
        local ok_enabled, why = should_apply(def)
        if not ok_enabled then
            lithium.debug("[PATCH][" .. id .. "] skipped: " .. tostring(why))
        else
            local ok, err = xpcall(def.apply, debug and debug.traceback or function(e) return tostring(e) end)
            if ok then
                M.applied[id] = true
                lithium.info("[PATCH][" .. id .. "] applied")
            else
                M.failed[id] = tostring(err)
                lithium.warn("[PATCH][" .. id .. "] failed: " .. tostring(err))
            end
        end
    end
end

function M.get_summary()
    local applied, failed, total = 0, 0, 0
    for _ in pairs(M.patches) do total = total + 1 end
    for _ in pairs(M.applied) do applied = applied + 1 end
    for _ in pairs(M.failed) do failed = failed + 1 end

    return {
        total = total,
        applied = applied,
        failed = failed,
        failed_detail = M.failed
    }
end

-- Example patch stub kept explicit and disabled by default.
M.register_patch({
    id = "example_safe_stub",
    realm = "shared",
    default_enabled = false,
    description = "Template patch stub; does not modify behavior.",
    apply = function()
        -- Intentional no-op.
    end
})

if concommand and concommand.Add then
    concommand.Add("lithium_patch_dump", function()
        local summary = M.get_summary()
        lithium.info("[PATCH] total=" .. summary.total .. " applied=" .. summary.applied .. " failed=" .. summary.failed)
        for id, err in pairs(summary.failed_detail or {}) do
            lithium.warn("[PATCH] failed id=" .. tostring(id) .. " err=" .. tostring(err))
        end
    end)
end

return M
