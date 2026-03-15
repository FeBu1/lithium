require("lithium")

local Registry = {
    addons = {},
    features = {},
    sources = {},
    stats = {
        addon_matches = 0,
        source_matches = 0,
        source_match_rules = {},
        source_match_builtin = 0,
        source_match_custom = 0,
        force_legacy_matches = 0,
        feature_hint_matches = 0,
        observe_matches = 0,
        unique_source_set = {},
        unique_sources = 0,
        last_source_match = nil,
        last_addon_match = nil,
        reasons = {}
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
    if rule.source_pattern and not match_pattern(source, rule.source_pattern) then return false end
    if rule.event_pattern and not match_pattern(event, rule.event_pattern) then return false end
    if rule.hook_id_pattern and not match_pattern(tostring(name), rule.hook_id_pattern) then return false end
    return true
end

local function rule_action(rule)
    if rule.observe_only then return "observe" end
    if rule.use_legacy_hook then return "force_legacy" end
    if rule.disable_features and #rule.disable_features > 0 then return "feature_hint" end
    return "observe"
end

local function bump_reason(reason)
    Registry.stats.reasons[reason] = (Registry.stats.reasons[reason] or 0) + 1
end

local function bump_action(action)
    if action == "force_legacy" then
        Registry.stats.force_legacy_matches = Registry.stats.force_legacy_matches + 1
    elseif action == "feature_hint" then
        Registry.stats.feature_hint_matches = Registry.stats.feature_hint_matches + 1
    else
        Registry.stats.observe_matches = Registry.stats.observe_matches + 1
    end
end

local function mark_unique_source(source)
    source = tostring(source or "unknown")
    if Registry.stats.unique_source_set[source] then return end
    Registry.stats.unique_source_set[source] = true
    Registry.stats.unique_sources = Registry.stats.unique_sources + 1
end

local function register_source_rule_internal(id, rule, origin)
    rule.id = id
    rule.origin = origin or rule.origin or "builtin"
    Registry.sources[id] = rule
end

function Registry.register_addon_rule(id, rule)
    rule.id = id
    rule.origin = rule.origin or "builtin"
    Registry.addons[id] = rule
end

function Registry.register_feature_rule(feature, id, rule)
    Registry.features[feature] = Registry.features[feature] or {}
    rule.id = id
    rule.origin = rule.origin or "builtin"
    Registry.features[feature][id] = rule
end

function Registry.register_source_rule(id, rule)
    register_source_rule_internal(id, rule, rule.origin or "builtin")
end

function Registry.register_builtin_source_rule(id, rule)
    register_source_rule_internal(id, rule, "builtin")
end

function Registry.register_custom_source_rule(id, rule)
    register_source_rule_internal(id, rule, "custom")
end

function Registry.get_source_rules()
    return Registry.sources
end

function Registry.evaluate_addon(addon_name, addon_file)
    local result = { use_legacy_hook = false, disabled_features = {}, notes = {} }
    for id, rule in pairs(Registry.addons) do
        if rule_matches(rule, addon_name, addon_file) then
            local reason = rule.reason or "matched addon rule"
            local action = rule_action(rule)

            if action == "force_legacy" then
                result.use_legacy_hook = true
            end
            for _, feature in ipairs(rule.disable_features or {}) do
                result.disabled_features[feature] = true
            end

            result.notes[#result.notes + 1] = { id = id, reason = reason, action = action, origin = rule.origin or "builtin" }
            Registry.stats.addon_matches = Registry.stats.addon_matches + 1
            Registry.stats.last_addon_match = {
                id = id,
                addon_name = addon_name,
                addon_file = addon_file,
                reason = reason,
                action = action,
                origin = rule.origin or "builtin"
            }
            bump_reason(reason)
            bump_action(action)
        end
    end
    return result
end

function Registry.evaluate_source(source, event, name)
    local result = { use_legacy_hook = false, matched_rules = {} }

    for id, rule in pairs(Registry.sources) do
        if source_rule_matches(rule, source, event, name) then
            local reason = rule.reason or "matched source rule"
            local action = rule_action(rule)

            if action == "force_legacy" then
                result.use_legacy_hook = true
            end

            result.matched_rules[#result.matched_rules + 1] = { id = id, reason = reason, action = action, origin = rule.origin or "builtin" }
            Registry.stats.source_matches = Registry.stats.source_matches + 1
            Registry.stats.source_match_rules[id] = (Registry.stats.source_match_rules[id] or 0) + 1
            Registry.stats.last_source_match = {
                id = id,
                source = source,
                event = event,
                hook_id = tostring(name),
                reason = reason,
                action = action,
                origin = rule.origin or "builtin"
            }
            if (rule.origin or "builtin") == "custom" then
                Registry.stats.source_match_custom = Registry.stats.source_match_custom + 1
            else
                Registry.stats.source_match_builtin = Registry.stats.source_match_builtin + 1
            end
            bump_reason(reason)
            bump_action(action)
            mark_unique_source(source)
        end
    end

    return result
end

local CUSTOM_RULE_PATH = "lithium/custom_compat_rules.json"

function Registry.load_custom_rules()
    if not (file and file.Read) then return 0 end
    local raw = file.Read(CUSTOM_RULE_PATH, "DATA")
    if not raw or raw == "" then return 0 end
    if not (util and util.JSONToTable) then return 0 end

    local parsed = util.JSONToTable(raw)
    if type(parsed) ~= "table" then return 0 end

    local loaded = 0
    for _, item in ipairs(parsed) do
        if type(item) == "table" and item.id and item.source_pattern then
            Registry.register_custom_source_rule(tostring(item.id), {
                source_pattern = item.source_pattern,
                event_pattern = item.event_pattern,
                hook_id_pattern = item.hook_id_pattern,
                use_legacy_hook = item.use_legacy_hook == true,
                observe_only = item.observe_only == true,
                disable_features = item.disable_features,
                reason = item.reason or "custom source rule"
            })
            loaded = loaded + 1
        end
    end

    return loaded
end

function Registry.save_custom_rules()
    if not (file and file.Write and util and util.TableToJSON) then return false end
    local out = {}
    for id, rule in pairs(Registry.sources) do
        if rule.origin == "custom" then
            out[#out + 1] = {
                id = id,
                source_pattern = rule.source_pattern,
                event_pattern = rule.event_pattern,
                hook_id_pattern = rule.hook_id_pattern,
                use_legacy_hook = rule.use_legacy_hook == true,
                observe_only = rule.observe_only == true,
                disable_features = rule.disable_features,
                reason = rule.reason
            }
        end
    end
    file.Write(CUSTOM_RULE_PATH, util.TableToJSON(out, true))
    return true
end

function Registry.get_stats()
    return Registry.stats
end

return Registry
