require("lithium")

local selftests = include("lithium/hook/selftests.lua")
local fast = include("lithium/hook/fast_backend.lua")
local legacy = include("lithium/hook/legacy_backend.lua")

local Dispatcher = { active_mode = "legacy", last_error = nil }

function Dispatcher.select_mode(compatibility_state, mode_cvar)
    local mode = mode_cvar and mode_cvar:GetString() or "auto"
    if mode == "legacy" then return "legacy" end
    if compatibility_state and compatibility_state.force_legacy then return "legacy" end
    return "fast"
end

function Dispatcher.enable(mode)
    if mode == "legacy" then
        legacy.enable()
        Dispatcher.active_mode = "legacy"
        lithium.info("[HOOK] Legacy backend active")
        return true
    end

    local ok, err = pcall(fast.enable)
    if not ok then
        Dispatcher.last_error = err
        lithium.warn("[HOOK] Fast backend load failed, falling back: " .. tostring(err))
        legacy.enable()
        Dispatcher.active_mode = "legacy"
        return false
    end

    if not selftests.run() then
        lithium.warn("[HOOK] Self-tests failed, falling back to legacy backend")
        legacy.enable()
        Dispatcher.active_mode = "legacy"
        return false
    end

    Dispatcher.active_mode = "fast"
    lithium.info("[HOOK] Fast backend active")
    return true
end

return Dispatcher
