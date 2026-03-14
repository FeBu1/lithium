require("lithium")

local M = {}

function M.run()
    lithium.info("[HOOK] Running hook self-tests")
    local ok, passed = pcall(include, "lithium/tests/hook.lua")
    if not ok then
        lithium.warn("[HOOK] Self-test execution failed: " .. tostring(passed))
        return false
    end
    if not passed then
        lithium.warn("[HOOK] Self-tests reported failure")
        return false
    end
    lithium.info("[HOOK] Hook self-tests completed")
    return true
end

return M
