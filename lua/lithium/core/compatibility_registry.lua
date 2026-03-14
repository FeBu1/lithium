require("lithium")

local Registry = {
    addons = {},
    features = {},
    sources = {},
    stats = {
        addon_matches = 0,
        source_matches = 0,
        source_match_rules = {}
    }
}

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

local function source_rule_matches(rule, source, event, name)
    if rule.source_pattern and not match_pattern(source, rule.source_pattern) then
        return false
    end
    if rule.event_pattern and not match_pattern(event, rule.event_pattern) then
        return false
    end
    if rule.hook_id_pattern and not match_pattern(tostring(name), rule.hook_id_pattern) then
        return false
    end
    return true
end

function Registry.register_addon_rule(id, rule)
    rule.id = id
    Registry.addons[id] = rule
end

function Registry.register_feature_rule(feature, id, rule)
    Registry.features[feature] = Registry.features[feature] or {}
    rule.id = id
    Registry.features[feature][id] = rule
end

function Registry.register_source_rule(id, rule)
    rule.id = id
    Registry.sources[id] = rule
end

function Registry.evaluate_addon(addon_name, addon_file)
    local result = { use_legacy_hook = false, disabled_features = {}, notes = {} }
    for id, rule in pairs(Registry.addons) do
        if rule_matches(rule, addon_name, addon_file) then
            if rule.use_legacy_hook then result.use_legacy_hook = true end
            for _, feature in ipairs(rule.disable_features or {}) do result.disabled_features[feature] = true end
            result.notes[#result.notes + 1] = {
                id = id,
                reason = rule.reason or "matched addon rule"
            }
            Registry.stats.addon_matches = Registry.stats.addon_matches + 1
        end
    end
    return result
end

function Registry.evaluate_source(source, event, name)
    local result = {
        use_legacy_hook = false,
        matched_rules = {}
    }

    for id, rule in pairs(Registry.sources) do
        if source_rule_matches(rule, source, event, name) then
            if rule.use_legacy_hook then
                result.use_legacy_hook = true
            end
            result.matched_rules[#result.matched_rules + 1] = {
                id = id,
                reason = rule.reason or "matched source rule"
            }
            Registry.stats.source_matches = Registry.stats.source_matches + 1
            Registry.stats.source_match_rules[id] = (Registry.stats.source_match_rules[id] or 0) + 1
        end
    end

    return result
end

function Registry.get_stats()
    return Registry.stats
end

return Registry
