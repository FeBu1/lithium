AddCSLuaFile()

_G.LITHIUM_LastAutoReload = _G.LITHIUM_LastAutoReload or -1
if SysTime() - _G.LITHIUM_LastAutoReload < 0.1 then return end
_G.LITHIUM_LastAutoReload = SysTime()

require("lithium")

concommand.Add("lithium_samplefps_" .. (SERVER and "sv" or CLIENT and "cl" or "unk"), function(ply, _, args)
    if SERVER and not IsValid(ply) then
        lithium.log("Running on dedicated server. Measurements may be more accurate.")
    end

    local timings = {}
    hook.Add("Tick", "LITHIUM_SampleFPS", function()
        timings[#timings + 1] = FrameTime()
    end)

    local sample_time = tonumber(args[1]) or 10
    lithium.log("Sampling FPS for " .. sample_time .. " seconds...")

    timer.Simple(sample_time, function()
        hook.Remove("Tick", "LITHIUM_SampleFPS")
        if #timings == 0 then
            lithium.warn("No frame timings captured.")
            return
        end

        local max_t, min_t, avg_t = 0, math.huge, 0
        for _, ft in ipairs(timings) do
            max_t = math.max(max_t, ft)
            min_t = math.min(min_t, ft)
            avg_t = avg_t + ft
        end
        avg_t = avg_t / #timings

        lithium.log("Sampling complete:")
        lithium.log("    Min FPS: " .. math.Round(1 / max_t, 2))
        lithium.log("    Max FPS: " .. math.Round(1 / min_t, 2))
        lithium.log("    Avg FPS: " .. math.Round(1 / avg_t, 2))
    end)
end)

local function send_dir(dir)
    dir = dir .. "/"
    local files, directories = file.Find(dir .. "*", "LUA")

    for _, filename in ipairs(files) do
        if string.EndsWith(filename, ".lua") then
            AddCSLuaFile(dir .. filename)
        end
    end

    for _, nested in ipairs(directories) do
        send_dir(dir .. nested)
    end
end

if SERVER then
    send_dir("lithium")
    AddCSLuaFile("includes/modules/hook_lithium.lua")
    AddCSLuaFile("includes/modules/lithium.lua")
    AddCSLuaFile("autorun/client/cl_lithium_controls.lua")
end

include("lithium/core/bootstrap.lua").run()
