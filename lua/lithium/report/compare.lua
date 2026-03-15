require("lithium")

local M = {}

local _G = _G
local file = file
local util = util
local string = string
local table = table
local math = math

local type = type
local tostring = tostring
local tonumber = tonumber
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
local table_sort = table.sort
local math_abs = math.abs
local math_min = math.min

local function top_from_map(map, mapfn, sorter, limit)
    local out = {}
    for k, v in pairs_fn(map or {}) do
        out[#out + 1] = mapfn(k, v)
    end
    table_sort(out, sorter)

    local capped = {}
    for i = 1, math_min(limit or #out, #out) do
        capped[#capped + 1] = out[i]
    end
    return capped
end

local function path_normalize(path)
    path = tostring(path or "")
    path = string.gsub(path, "^data/", "")
    if string.find(path, "lithium/reports/", 1, true) then
        return path
    end
    if string.find(path, "report_", 1, true) then
        return "lithium/reports/" .. path
    end
    return path
end

local function load_report(path)
    if not (file and file.Read and util and util.JSONToTable) then
        return false, "file/util globals unavailable"
    end

    local normalized = path_normalize(path)
    local raw = file.Read(normalized, "DATA")
    if not raw or raw == "" then
        return false, "report not found in data/: " .. tostring(normalized)
    end

    local parsed = util.JSONToTable(raw)
    if type(parsed) ~= "table" then
        return false, "invalid JSON report: " .. tostring(normalized)
    end

    return true, parsed, normalized
end

local function index_by(list, key_name)
    local out = {}
    for _, item in ipairs_fn(list or {}) do
        local key = tostring(item[key_name] or "")
        if key ~= "" then
            out[key] = item
        end
    end
    return out
end

local function numeric(v)
    return tonumber(v) or 0
end

local function compute_delta_rows(list_a, list_b, key_name, value_name, limit)
    local idx_a = index_by(list_a, key_name)
    local idx_b = index_by(list_b, key_name)
    local keys = {}
    for key, _ in pairs_fn(idx_a) do keys[key] = true end
    for key, _ in pairs_fn(idx_b) do keys[key] = true end

    local rows = {}
    for key, _ in pairs_fn(keys) do
        local a = idx_a[key]
        local b = idx_b[key]
        local av = numeric(a and a[value_name] or 0)
        local bv = numeric(b and b[value_name] or 0)
        rows[#rows + 1] = {
            key = key,
            before = av,
            after = bv,
            delta = bv - av,
            abs_delta = math_abs(bv - av),
            appeared = (not a) and (b ~= nil)
        }
    end

    table_sort(rows, function(x, y)
        if x.abs_delta == y.abs_delta then
            return x.key < y.key
        end
        return x.abs_delta > y.abs_delta
    end)

    local trimmed = {}
    for i = 1, math_min(limit or #rows, #rows) do
        trimmed[#trimmed + 1] = rows[i]
    end
    return trimmed
end

local function appeared_items(list_a, list_b, key_name, limit)
    local idx_a = index_by(list_a, key_name)
    local out = {}
    for _, item in ipairs_fn(list_b or {}) do
        local key = tostring(item[key_name] or "")
        if key ~= "" and not idx_a[key] then
            out[#out + 1] = item
        end
    end

    if #out > (limit or #out) then
        local trimmed = {}
        for i = 1, limit do trimmed[#trimmed + 1] = out[i] end
        return trimmed
    end
    return out
end

function M.compare_reports(a, b, limit)
    limit = tonumber(limit) or 15

    local summary = {
        heuristic = true,
        header = {
            before = a.header or {},
            after = b.header or {}
        },
        deltas = {
            fallback_count = numeric((b.backend or {}).fallback_count) - numeric((a.backend or {}).fallback_count),
            migration_count = numeric((b.backend or {}).migration_count) - numeric((a.backend or {}).migration_count),
            compat_source_matches = numeric((b.compatibility or {}).source_matches) - numeric((a.compatibility or {}).source_matches),
            compat_force_legacy_matches = numeric((b.compatibility or {}).force_legacy_matches) - numeric((a.compatibility or {}).force_legacy_matches)
        },
        top_event_time_deltas = compute_delta_rows((a.profiler or {}).top_events, (b.profiler or {}).top_events, "event", "time", limit),
        top_hook_time_deltas = compute_delta_rows((a.profiler or {}).top_hooks, (b.profiler or {}).top_hooks, "key", "time", limit),
        top_source_time_deltas = compute_delta_rows((a.profiler or {}).top_sources, (b.profiler or {}).top_sources, "source", "time", limit),
        top_source_group_time_deltas = compute_delta_rows((a.profiler or {}).top_source_groups, (b.profiler or {}).top_source_groups, "bucket", "time", limit),
        top_net_message_byte_deltas = compute_delta_rows((a.net or {}).top_messages_by_bytes, (b.net or {}).top_messages_by_bytes, "name", "bytes", limit),
        top_net_message_send_deltas = compute_delta_rows((a.net or {}).top_messages_by_count, (b.net or {}).top_messages_by_count, "name", "sends", limit),
        top_net_source_byte_deltas = compute_delta_rows((a.net or {}).top_sources_by_bytes, (b.net or {}).top_sources_by_bytes, "source", "bytes", limit),
        top_net_group_byte_deltas = compute_delta_rows((a.net or {}).top_source_groups, (b.net or {}).top_source_groups, "bucket", "bytes", limit),
        source_rule_hit_deltas = compute_delta_rows((a.compatibility or {}).source_rule_hits, (b.compatibility or {}).source_rule_hits, "rule_id", "hits", limit),
        fallback_source_deltas = compute_delta_rows((a.backend or {}).top_fallback_sources, (b.backend or {}).top_fallback_sources, "source", "hits", limit),
        new_hot_sources = appeared_items((a.profiler or {}).top_sources, (b.profiler or {}).top_sources, "source", limit),
        new_compat_matches = appeared_items((a.compatibility or {}).source_rule_hits, (b.compatibility or {}).source_rule_hits, "rule_id", limit),
        new_patch_candidates = appeared_items((a.tuning_suggestions or {}).addon_patch_candidates, (b.tuning_suggestions or {}).addon_patch_candidates, "source", limit)
    }

    return summary
end

function M.compare_from_paths(path_a, path_b, limit)
    local ok_a, rep_a, norm_a = load_report(path_a)
    if not ok_a then return false, rep_a end

    local ok_b, rep_b, norm_b = load_report(path_b)
    if not ok_b then return false, rep_b end

    local summary = M.compare_reports(rep_a, rep_b, limit)
    summary.paths = { before = norm_a, after = norm_b }
    return true, summary
end

function M.log_summary(summary)
    lithium.info("[LITHIUM][COMPARE] === Session compare summary ===")
    lithium.info("[LITHIUM][COMPARE] before=" .. tostring(summary.paths and summary.paths.before or "unknown") .. " after=" .. tostring(summary.paths and summary.paths.after or "unknown"))
    lithium.info("[LITHIUM][COMPARE] labels before='" .. tostring(summary.header.before.session_label or "") .. "' after='" .. tostring(summary.header.after.session_label or "") .. "'")
    lithium.info("[LITHIUM][COMPARE] map before=" .. tostring(summary.header.before.map or "unknown") .. " after=" .. tostring(summary.header.after.map or "unknown"))
    lithium.info("[LITHIUM][COMPARE] fallback_delta=" .. tostring(summary.deltas.fallback_count) .. " migration_delta=" .. tostring(summary.deltas.migration_count) .. " compat_delta=" .. tostring(summary.deltas.compat_source_matches) .. " force_legacy_delta=" .. tostring(summary.deltas.compat_force_legacy_matches))

    for i, row in ipairs_fn(summary.top_event_time_deltas or {}) do
        lithium.info(string.format("[LITHIUM][COMPARE] EVENT_DELTA #%d %s before=%.6f after=%.6f delta=%+.6f", i, row.key, row.before, row.after, row.delta))
    end
    for i, row in ipairs_fn(summary.top_source_time_deltas or {}) do
        lithium.info(string.format("[LITHIUM][COMPARE] SOURCE_DELTA #%d %s before=%.6f after=%.6f delta=%+.6f", i, row.key, row.before, row.after, row.delta))
    end
    for i, row in ipairs_fn(summary.top_net_message_byte_deltas or {}) do
        lithium.info(string.format("[LITHIUM][COMPARE] NET_BYTES_DELTA #%d %s before=%.0f after=%.0f delta=%+.0f", i, row.key, row.before, row.after, row.delta))
    end
    for i, row in ipairs_fn(summary.source_rule_hit_deltas or {}) do
        lithium.info(string.format("[LITHIUM][COMPARE] RULE_DELTA #%d %s before=%.0f after=%.0f delta=%+.0f", i, row.key, row.before, row.after, row.delta))
    end

    for i, item in ipairs_fn(summary.new_hot_sources or {}) do
        lithium.info("[LITHIUM][COMPARE] NEW_HOT_SOURCE[" .. i .. "] " .. tostring(item.source) .. " bucket=" .. tostring(item.bucket) .. " time=" .. tostring(item.time))
    end
    for i, item in ipairs_fn(summary.new_compat_matches or {}) do
        lithium.info("[LITHIUM][COMPARE] NEW_RULE_MATCH[" .. i .. "] rule=" .. tostring(item.rule_id) .. " action=" .. tostring(item.action) .. " hits=" .. tostring(item.hits))
    end
    for i, item in ipairs_fn(summary.new_patch_candidates or {}) do
        lithium.info("[LITHIUM][COMPARE] NEW_PATCH_CANDIDATE[" .. i .. "] source=" .. tostring(item.source) .. " bucket=" .. tostring(item.bucket))
    end

    lithium.info("[LITHIUM][COMPARE] suggestions are heuristic; verify with in-session evidence before policy changes")
end

return M
