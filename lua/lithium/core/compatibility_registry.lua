require("lithium")

local Registry = { addons = {}, features = {} }

local function norm(str)
    return string.lower(tostring(str or ""))
end

local function match_pattern(value, pattern)
    if not pattern or pattern == "" then return false end
    return string.find(norm(value), norm(pattern), 1, true) ~= nil
end

local function rule_matches(rule, addon_name, addon_file)
    if rule.name_pattern and match_pattern(addon_name, rule.name_pattern) then return true end
    if rule.file_pattern and match_pattern(addon_file, rule.file_pattern) then return true end
    return false
end

function Registry.register_addon_rule(id, rule)
    Registry.addons[id] = rule
end

function Registry.register_feature_rule(feature, id, rule)
    Registry.features[feature] = Registry.features[feature] or {}
    Registry.features[feature][id] = rule
end

function Registry.evaluate_addon(addon_name, addon_file)
    local result = { use_legacy_hook = false, disabled_features = {}, notes = {} }
    for id, rule in pairs(Registry.addons) do
        if rule_matches(rule, addon_name, addon_file) then
            if rule.use_legacy_hook then result.use_legacy_hook = true end
            for _, feature in ipairs(rule.disable_features or {}) do result.disabled_features[feature] = true end
            result.notes[#result.notes + 1] = id
        end
    end
    return result
end

return Registry
