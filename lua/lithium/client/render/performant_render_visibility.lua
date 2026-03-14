local M = {}

function M.should_soft_cull(entity, view)
    if not IsValid(entity) then return false end
    if not view or not view.origin then return false end
    return entity:GetPos():DistToSqr(view.origin) > (view.soft_cull_distance_sqr or 25000000)
end

return M
