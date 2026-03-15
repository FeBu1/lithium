require("lithium")

local M = {
    wrapped = false,
    originals = {},
    pending = nil,
    stats = {
        total_sends = 0,
        total_bytes = 0,
        direction_counts = { sv_to_cl = 0, cl_to_sv = 0, other = 0 },
        by_message = {},
        by_source = {},
        by_mode = {}
    }
}

local GetConVarFn = GetConVar
local CreateConVarFn = CreateConVar
local debug_getinfo = debug and debug.getinfo

local function source_bucket(path)
    path = tostring(path or "unknown")
    local low = string.lower(path)
    if string.find(low, "workshop/content", 1, true) then return "workshop_content" end
    if string.find(low, "addons/", 1, true) then return "addons" end
    if string.find(low, "gamemodes/", 1, true) then return "gamemodes" end
    if string.find(low, "lua/includes/", 1, true) then return "engine_includes" end
    if string.find(low, "lua/", 1, true) then return "base_lua" end
    return "other"
end

local enabled_cv = nil
local enabled_cache = false
local next_enabled_check = 0
local RealTimeFn = RealTime

local function ensure_cvar()
    if enabled_cv then return end
    if type(GetConVarFn) == "function" then
        enabled_cv = GetConVarFn("lithium_net_diagnostics_enabled")
    end
    if not enabled_cv and type(CreateConVarFn) == "function" then
        enabled_cv = CreateConVarFn("lithium_net_diagnostics_enabled", "1", { FCVAR_ARCHIVE }, "Enable Lithium network diagnostics runtime capture", 0, 1)
    end
end

local function is_enabled()
    if type(RealTimeFn) ~= "function" then return false end
    if RealTimeFn() < next_enabled_check then return enabled_cache end
    next_enabled_check = RealTimeFn() + 1

    ensure_cvar()
    enabled_cache = enabled_cv and enabled_cv.GetBool and enabled_cv:GetBool() or false
    return enabled_cache
end

local function top_from_map(map, mapfn, sorter, limit)
    local out = {}
    for k, v in pairs(map or {}) do
        out[#out + 1] = mapfn(k, v)
    end
    table.sort(out, sorter)
    local capped = {}
    for i = 1, math.min(limit, #out) do
        capped[#capped + 1] = out[i]
    end
    return capped
end

local function count_recipients(target)
    if target == nil then return -1 end
    if type(target) == "table" then
        local c = 0
        for _, _ in pairs(target) do c = c + 1 end
        return c
    end
    return 1
end

local function bytes_written()
    if not net or type(net.BytesWritten) ~= "function" then return 0 end
    local bits = net.BytesWritten()
    if type(bits) ~= "number" then return 0 end
    return math.ceil(bits / 8)
end

local function mark_send(mode, recipients)
    if not is_enabled() then return end

    local p = M.pending or { name = "unknown", source = "unknown" }
    local name = tostring(p.name or "unknown")
    local source = tostring(p.source or "unknown")
    local bytes = bytes_written()

    local direction = "other"
    if SERVER then
        direction = "sv_to_cl"
    elseif CLIENT then
        direction = "cl_to_sv"
    end

    M.stats.total_sends = M.stats.total_sends + 1
    M.stats.total_bytes = M.stats.total_bytes + bytes
    M.stats.direction_counts[direction] = (M.stats.direction_counts[direction] or 0) + 1

    local msg = M.stats.by_message[name]
    if not msg then
        msg = {
            sends = 0,
            bytes = 0,
            max_bytes = 0,
            recipients_total = 0,
            recipients_samples = 0,
            source_top = {},
            modes = {}
        }
        M.stats.by_message[name] = msg
    end
    msg.sends = msg.sends + 1
    msg.bytes = msg.bytes + bytes
    msg.max_bytes = math.max(msg.max_bytes, bytes)
    msg.modes[mode] = (msg.modes[mode] or 0) + 1
    if recipients and recipients >= 0 then
        msg.recipients_total = msg.recipients_total + recipients
        msg.recipients_samples = msg.recipients_samples + 1
    end
    msg.source_top[source] = (msg.source_top[source] or 0) + bytes

    local src = M.stats.by_source[source]
    if not src then
        src = { sends = 0, bytes = 0, bucket = source_bucket(source), messages = {} }
        M.stats.by_source[source] = src
    end
    src.sends = src.sends + 1
    src.bytes = src.bytes + bytes
    src.messages[name] = (src.messages[name] or 0) + bytes

    local m = M.stats.by_mode[mode]
    if not m then
        m = { sends = 0, bytes = 0 }
        M.stats.by_mode[mode] = m
    end
    m.sends = m.sends + 1
    m.bytes = m.bytes + bytes

    M.pending = nil
end

local function wrap_net()
    if M.wrapped or not net then return end

    M.originals.Start = net.Start
    M.originals.Send = net.Send
    M.originals.Broadcast = net.Broadcast
    M.originals.SendOmit = net.SendOmit
    M.originals.SendPAS = net.SendPAS
    M.originals.SendPVS = net.SendPVS
    M.originals.SendToServer = net.SendToServer

    if type(M.originals.Start) == "function" then
        net.Start = function(name, ...)
            if is_enabled() then
                local info = debug_getinfo and debug_getinfo(2, "S") or {}
                local source = tostring(info.short_src or info.source or "unknown")
                M.pending = { name = tostring(name or "unknown"), source = source }
            end
            return M.originals.Start(name, ...)
        end
    end

    if type(M.originals.Send) == "function" then
        net.Send = function(target, ...)
            mark_send("send", count_recipients(target))
            return M.originals.Send(target, ...)
        end
    end

    if type(M.originals.Broadcast) == "function" then
        net.Broadcast = function(...)
            local recipients = player and player.GetCount and player.GetCount() or -1
            mark_send("broadcast", recipients)
            return M.originals.Broadcast(...)
        end
    end

    if type(M.originals.SendOmit) == "function" then
        net.SendOmit = function(target, ...)
            local total = player and player.GetCount and player.GetCount() or -1
            local omitted = count_recipients(target)
            local recipients = (total >= 0 and omitted >= 0) and math.max(0, total - omitted) or -1
            mark_send("send_omit", recipients)
            return M.originals.SendOmit(target, ...)
        end
    end

    if type(M.originals.SendPAS) == "function" then
        net.SendPAS = function(...)
            mark_send("send_pas", -1)
            return M.originals.SendPAS(...)
        end
    end

    if type(M.originals.SendPVS) == "function" then
        net.SendPVS = function(...)
            mark_send("send_pvs", -1)
            return M.originals.SendPVS(...)
        end
    end

    if type(M.originals.SendToServer) == "function" then
        net.SendToServer = function(...)
            mark_send("send_to_server", 1)
            return M.originals.SendToServer(...)
        end
    end

    M.wrapped = true
end

function M.reset()
    M.stats = {
        total_sends = 0,
        total_bytes = 0,
        direction_counts = { sv_to_cl = 0, cl_to_sv = 0, other = 0 },
        by_message = {},
        by_source = {},
        by_mode = {}
    }
end

function M.get_report(limit)
    limit = tonumber(limit) or 20

    local top_by_bytes = top_from_map(M.stats.by_message, function(name, item)
        local avg = item.sends > 0 and (item.bytes / item.sends) or 0
        local avg_recipients = item.recipients_samples > 0 and (item.recipients_total / item.recipients_samples) or -1
        return {
            name = name,
            sends = item.sends,
            bytes = item.bytes,
            avg_bytes = avg,
            max_bytes = item.max_bytes,
            avg_recipients = avg_recipients
        }
    end, function(a, b) return a.bytes > b.bytes end, limit)

    local top_by_count = top_from_map(M.stats.by_message, function(name, item)
        local avg = item.sends > 0 and (item.bytes / item.sends) or 0
        return { name = name, sends = item.sends, bytes = item.bytes, avg_bytes = avg }
    end, function(a, b) return a.sends > b.sends end, limit)

    local top_sources = top_from_map(M.stats.by_source, function(source, item)
        return {
            source = source,
            bucket = item.bucket,
            sends = item.sends,
            bytes = item.bytes
        }
    end, function(a, b) return a.bytes > b.bytes end, limit)

    local source_groups = {}
    for _, item in pairs(M.stats.by_source) do
        local g = source_groups[item.bucket] or { bytes = 0, sends = 0 }
        g.bytes = g.bytes + item.bytes
        g.sends = g.sends + item.sends
        source_groups[item.bucket] = g
    end

    local top_source_groups = top_from_map(source_groups, function(bucket, item)
        return { bucket = bucket, bytes = item.bytes, sends = item.sends }
    end, function(a, b) return a.bytes > b.bytes end, 16)

    local broadcast_heavy = {}
    local too_frequent = {}
    local too_large = {}
    for _, item in ipairs(top_by_bytes) do
        if item.avg_recipients >= 8 or item.avg_recipients == -1 then
            broadcast_heavy[#broadcast_heavy + 1] = item
        end
        if item.sends >= 100 and item.avg_bytes < 96 then
            too_frequent[#too_frequent + 1] = item
        end
        if item.max_bytes >= 2048 or item.avg_bytes >= 768 then
            too_large[#too_large + 1] = item
        end
    end

    return {
        enabled = is_enabled(),
        total_sends = M.stats.total_sends,
        total_bytes = M.stats.total_bytes,
        direction_counts = M.stats.direction_counts,
        top_messages_by_bytes = top_by_bytes,
        top_messages_by_count = top_by_count,
        top_sources_by_bytes = top_sources,
        top_source_groups = top_source_groups,
        mode_summary = M.stats.by_mode,
        suggestions = {
            heuristic = true,
            broadcast_heavy_messages = broadcast_heavy,
            candidate_event_spam_messages = too_frequent,
            candidate_large_payload_messages = too_large
        },
        limitations = {
            recipient_count = "approximate for SendPAS/SendPVS and any custom recipient filter userdata",
            payload_size = "estimated from net.BytesWritten() at send-time; includes serialized payload estimate only",
            source_capture = "best-effort from debug.getinfo at net.Start; may be unknown when debug is unavailable"
        }
    }
end

wrap_net()
lithium.net_diagnostics = M

-- Commands are registered in lithium/hook/diagnostics.lua so they remain discoverable
-- even when this module is disabled.

return M
