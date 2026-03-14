if SERVER then return end
require("lithium")

local registry = include("lithium/client/render/performant_render_registry.lua")
local visibility = include("lithium/client/render/performant_render_visibility.lua")
local rv_compat = include("lithium/client/render/performant_render_renderview_compat.lua")

local state = { last_restore_mismatch = 0, rollback_until = 0 }

hook.Add("RenderScene", "LITHIUM_PerformantRenderLite_ViewState", function(origin, angles, fov)
    rv_compat.current_view = { origin = origin, angles = angles, fov = fov, soft_cull_distance_sqr = 225000000 }
end)

hook.Add("PreRender", "LITHIUM_PerformantRenderLite_SoftCull", function()
    if RealTime() < state.rollback_until then return end
    local view = rv_compat.current_view
    if not view then return end

    local changes = 0
    for _, ent in ipairs(ents.GetAll()) do
        if changes > 100 then break end
        if registry.is_allowed(ent:GetClass()) and visibility.should_soft_cull(ent, view) then
            ent.LithiumSoftCull = true
            changes = changes + 1
        end
    end
end)

hook.Add("PostRender", "LITHIUM_PerformantRenderLite_RestoreAudit", function()
    if state.last_restore_mismatch > 5 then
        state.rollback_until = RealTime() + 30
        lithium.warn("[RENDER] Restore mismatch detected; disabling PerformantRender-lite for 30 seconds")
    end
end)
