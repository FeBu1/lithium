if hook.GetULibTable then return end

require("lithium")

local _G = _G
local table = table or {}
local math = math or {}

local type = type
local tostring = tostring
local tonumber = tonumber
local error = error
local pcall = pcall
local xpcall = xpcall
local setmetatable = setmetatable
local getmetatable = getmetatable
local rawget = rawget
local rawset = rawset
local isnumber = isnumber
local isstring = isstring
local isbool = isbool
local isfunction = isfunction
local gmod = gmod
local SysTime = SysTime
local RealTime = RealTime
local GetConVarFn = GetConVar
local ErrorNoHaltWithStack = ErrorNoHaltWithStack

local table_insert = table.insert
local table_remove = table.remove
local table_unpack = table.unpack or unpack
local math_min = math.min
local math_max = math.max
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
local debug_getinfo = debug and debug.getinfo

local hooks = {}
local hooks_backward = {}
local hooks_table = {}
local hook_meta = {}
local add_epoch = 0

local diagnostics = {
    enabled_cache = false,
    next_cv_check = 0,
    total_calls = 0,
    total_events = 0,
    profiler_samples = 0,
    compatibility_fallbacks = 0,
    by_event = {},
    by_hook = {},
    by_source = {}
}

HOOK_MONITOR_HIGH = -2
HOOK_HIGH = -1
HOOK_NORMAL = 0
HOOK_LOW = 1
HOOK_MONITOR_LOW = 2

module("hook")

function GetTable() return hooks_backward end
function GetULibTable() return hooks end
function GetLithiumTable() return hooks_table end

local function profile_enabled()
    if type(RealTime) ~= "function" then return false end
    if RealTime() < diagnostics.next_cv_check then
        return diagnostics.enabled_cache
    end

    diagnostics.next_cv_check = RealTime() + 1
    if type(GetConVarFn) ~= "function" then
        diagnostics.enabled_cache = false
        return false
    end

    local cv = GetConVarFn("lithium_hook_profiler_enabled")
    diagnostics.enabled_cache = cv and cv.GetBool and cv:GetBool() or false
    return diagnostics.enabled_cache
end

function GetLithiumDiagnostics()
    return diagnostics
end

function ResetLithiumDiagnostics()
    diagnostics.total_calls = 0
    diagnostics.total_events = 0
    diagnostics.profiler_samples = 0
    diagnostics.compatibility_fallbacks = 0
    diagnostics.by_event = {}
    diagnostics.by_hook = {}
    diagnostics.by_source = {}
end

function AddCompatibilityFallbackCount()
    diagnostics.compatibility_fallbacks = diagnostics.compatibility_fallbacks + 1
end

function ExportLithiumHooksInOrder()
    local exported = {}
    for event, event_table in pairs_fn(hooks_table) do
        local list = {}
        for i = 6, #event_table, 3 do
            list[#list + 1] = {
                name = event_table[i + 2],
                func = event_table[i],
                is_string = event_table[i + 1]
            }
        end
        exported[event] = list
    end
    return exported
end

local function track_call(event, name, elapsed)
    if not profile_enabled() then return end

    diagnostics.total_calls = diagnostics.total_calls + 1

    local e = diagnostics.by_event[event]
    if not e then
        e = { calls = 0, time = 0 }
        diagnostics.by_event[event] = e
    end
    e.calls = e.calls + 1
    e.time = e.time + elapsed

    local key = event .. "|" .. tostring(name)
    local h = diagnostics.by_hook[key]
    if not h then
        local meta = hook_meta[event] and hook_meta[event][name] or nil
        h = {
            calls = 0,
            time = 0,
            event = event,
            name = tostring(name),
            source = meta and meta.source or "unknown"
        }
        diagnostics.by_hook[key] = h

        local source_key = h.source or "unknown"
        local src = diagnostics.by_source[source_key]
        if not src then
            src = { calls = 0, time = 0, hooks = 0 }
            diagnostics.by_source[source_key] = src
        end
        src.hooks = src.hooks + 1
    end
    h.calls = h.calls + 1
    h.time = h.time + elapsed

    local source_key = h.source or "unknown"
    local src = diagnostics.by_source[source_key]
    if not src then
        src = { calls = 0, time = 0, hooks = 0 }
        diagnostics.by_source[source_key] = src
    end
    src.calls = src.calls + 1
    src.time = src.time + elapsed
    diagnostics.profiler_samples = diagnostics.profiler_samples + 1
end

local function mark_event_call()
    if not profile_enabled() then return end
    diagnostics.total_events = diagnostics.total_events + 1
end

local function FindInsertIndex(event, priority)
    if not hooks_table[event] then return 1 end
    local amount = 0
    for i = 1, priority + 3, 1 do
        amount = amount + (hooks_table[event][i] or 0)
    end
    local went = 0
    for i = 5, #hooks_table[event], 3 do
        if went == amount then
            return i
        end
        went = went + 1
    end
    return #hooks_table[event] + 1
end

local function remove_entry_from_compact(event, name)
    local pr_n2 = FindInsertIndex(event, -2) + 1
    local pr_n1 = FindInsertIndex(event, -1) + 1
    local pr_z0 = FindInsertIndex(event, 0) + 1
    local pr_p1 = FindInsertIndex(event, 1) + 1

    local hook_table = hooks_table[event]
    if not hook_table then return end

    local did_remove = true
    while did_remove do
        did_remove = false
        for i = 6, #hook_table, 3 do
            if hook_table[i + 2] == name then
                table_remove(hook_table, i)
                table_remove(hook_table, i)
                table_remove(hook_table, i)
                if i >= pr_p1 then hook_table[5] = hook_table[5] - 1
                elseif i >= pr_z0 then hook_table[4] = hook_table[4] - 1
                elseif i >= pr_n1 then hook_table[3] = hook_table[3] - 1
                elseif i >= pr_n2 then hook_table[2] = hook_table[2] - 1
                else hook_table[1] = hook_table[1] - 1 end
                did_remove = true
                break
            end
        end
    end
end

function Add(event, name, func, priority)
    if not priority or not isnumber(priority) then priority = 0 end
    if not isstring(event) then
        return ErrorNoHaltWithStack("bad argument #1 to 'Add' (string expected, got " .. type(event) .. ")")
    end
    if not isfunction(func) then
        return ErrorNoHaltWithStack("bad argument #3 to 'Add' (function expected, got " .. type(func) .. ")")
    end
    local notValid = name == nil or isnumber(name) or isbool(name) or isfunction(name) or not name.IsValid or not name:IsValid()
    if not isstring(name) and notValid then
        return ErrorNoHaltWithStack("bad argument #2 to 'Add' (string expected, got " .. type(name) .. ")")
    end

    RemoveForce(event, name)

    local hook_table = hooks[event] or { [-2] = {}, [-1] = {}, [0] = {}, [1] = {}, [2] = {} }
    hooks[event] = hook_table
    hook_table = hook_table[priority]
    hooks[event][priority] = hook_table

    hooks_backward[event] = hooks_backward[event] or {}
    hook_meta[event] = hook_meta[event] or {}

    hook_table[name] = { fn = func, isstring = isstring(name) }
    hooks_backward[event][name] = func
    hooks_table[event] = hooks_table[event] or { 0, 0, 0, 0, 0 }

    local info = debug_getinfo and debug_getinfo(2, "S") or {}
    add_epoch = add_epoch + 1
    hook_meta[event][name] = {
        source = tostring(info.short_src or info.source or "unknown"),
        epoch = add_epoch
    }

    local insert_pos = FindInsertIndex(event, priority) + 1
    table_insert(hooks_table[event], insert_pos, func)
    table_insert(hooks_table[event], insert_pos + 1, isstring(name))
    table_insert(hooks_table[event], insert_pos + 2, name)
    hooks_table[event][priority + 3] = hooks_table[event][priority + 3] + 1
end

function Remove(event, name)
    if not isstring(event) then
        return ErrorNoHaltWithStack("bad argument #1 to 'Remove' (string expected, got " .. type(event) .. ")")
    end
    local notValid = name == nil or isnumber(name) or isbool(name) or isfunction(name) or not name.IsValid or not name:IsValid()
    if not isstring(name) and notValid then
        return ErrorNoHaltWithStack("bad argument #2 to 'Remove' (string expected, got " .. type(name) .. ")")
    end
    return RemoveForce(event, name)
end

function RemoveForce(event, name)
    if not hooks_backward[event] then return end
    for i = -2, 2, 1 do
        if hooks[event] and hooks[event][i] then
            hooks[event][i][name] = nil
        end
    end
    hooks_backward[event][name] = nil
    if hook_meta[event] then
        hook_meta[event][name] = nil
    end

    remove_entry_from_compact(event, name)
end

local current_name
local function should_run_entry(event, hook_name, hook_func, call_epoch)
    if not hooks_backward[event] then return false end

    local active = hooks_backward[event][hook_name]
    if active ~= hook_func then
        return false
    end

    local meta = hook_meta[event] and hook_meta[event][hook_name] or nil
    if meta and meta.epoch and meta.epoch > call_epoch then
        return false
    end

    return true
end

local function call_entry(hook_table, event, i, is_return, call_epoch, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
    local hook_name = hook_table[i + 2]
    local hook_func = hook_table[i]
    if not should_run_entry(event, hook_name, hook_func, call_epoch) then
        return
    end

    local started = (profile_enabled() and type(SysTime) == "function") and SysTime() or nil

    local a, b, c, d, e, f
    if hook_table[i + 1] then
        if is_return then
            a, b, c, d, e, f = hook_func(arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
        else
            hook_func(arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
        end
    else
        current_name = hook_name
        if not current_name then return end
        if not current_name:IsValid() then
            return RemoveForce(event, current_name)
        end
        if is_return then
            a, b, c, d, e, f = hook_func(current_name, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
        else
            hook_func(current_name, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
        end
    end

    if started then
        track_call(event, hook_name, SysTime() - started)
    end

    return a, b, c, d, e, f
end

function Call(event, gm, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
    mark_event_call()

    local hook_table = hooks_table[event]
    if hook_table then
        local call_epoch = add_epoch
        local n1, p2 = FindInsertIndex(event, -2), FindInsertIndex(event, 1)
        local maxn = #hook_table

        local a, b, c, d, e, f
        for i = 6, n1, 3 do
            call_entry(hook_table, event, i, false, call_epoch, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
        end
        for i = n1 + 1, p2, 3 do
            if i <= maxn then
                a, b, c, d, e, f = call_entry(hook_table, event, i, true, call_epoch, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
                if a ~= nil then return a, b, c, d, e, f end
            end
        end
        for i = p2 + 1, maxn, 3 do
            call_entry(hook_table, event, i, false, call_epoch, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
        end
    end

    if gm and gm[event] then
        return gm[event](gm, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
    end
end

local gm = nil
function Run(event, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
    if not gm then gm = gmod and gmod.GetGamemode() or nil end
    return Call(event, gm, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
end
