local M = {
    classes_blacklist = { ["gmod_hands"] = true, ["viewmodel"] = true },
    classes_whitelist = {}
}

function M.is_allowed(class)
    if M.classes_whitelist[class] ~= nil then return M.classes_whitelist[class] end
    return not M.classes_blacklist[class]
end

return M
