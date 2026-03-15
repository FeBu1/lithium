require("lithium")

local cvars = include("lithium/core/convars.lua")
local Loader = include("lithium/core/module_loader.lua")
local compatibility = include("lithium/core/compatibility_registry.lua")
local dispatcher = include("lithium/hook/dispatcher.lua")

local function safe_include(path)
    return function()
        local ok, ret = pcall(include, path)
        if not ok then
            error(ret)
        end

        if ret == false then
            error("include failed for '" .. path .. "'")
        end
    end
end

local function setup_default_rules()
    compatibility.register_addon_rule("dlib_hook_mutation", {
        name_pattern = "dlib",
        use_legacy_hook = true,
        disable_features = { "experimental_render_derender" },
        reason = "DLib-style hook table mutation compatibility mode"
    })
    compatibility.register_addon_rule("ulib_safe_path", {
        name_pattern = "ulib",
        use_legacy_hook = false,
        reason = "ULib known compatibility baseline"
    })

    compatibility.register_builtin_source_rule("dlib_source_hook_fallback", {
        source_pattern = "dlib/",
        use_legacy_hook = true,
        reason = "hook.Add caller source matched DLib rule"
    })

    compatibility.register_builtin_source_rule("observe_glua_postprocess", {
        source_pattern = "lua/postprocess/",
        observe_only = true,
        reason = "Postprocess path observed for telemetry"
    })
end

local function detect_compatibility()
    local state = { force_legacy = false, matches = {} }
    if not engine.GetAddons then return state end

    for _, addon in ipairs(engine.GetAddons()) do
        if addon.mounted then
            local info = compatibility.evaluate_addon(addon.title or "", addon.file or "")
            if info.use_legacy_hook then
                state.force_legacy = true
                state.matches[#state.matches + 1] = (addon.title ~= "" and addon.title) or addon.file or "unknown"
            end
        end
    end

    if state.force_legacy then
        lithium.warn("[COMPAT] Legacy hook mode forced by: " .. table.concat(state.matches, ", "))
    end
    return state
end

local M = {}

function M.run()
    local enabled = cvars.bool("enabled", true, "Enable Lithium", { per_realm = true })
    if enabled and not enabled:GetBool() then
        print("[LITHIUM] Startup skipped: disabled by convar")
        return
    end
    if file and file.Read and file.Read("lithium_dontload.txt", "DATA") == "yes" then
        print("[LITHIUM] Startup skipped: data/lithium_dontload.txt")
        return
    end

    include("lithium/core/logging.lua")
    setup_default_rules()
    local loaded_custom_rules = compatibility.load_custom_rules and compatibility.load_custom_rules() or 0
    if loaded_custom_rules > 0 then
        lithium.info("[COMPAT] Loaded custom source rules: " .. tostring(loaded_custom_rules))
    end
    lithium.compatibility_registry = compatibility
    lithium.hook_dispatcher = dispatcher

    local loader = Loader.new()
    local create_cvar = CreateConVar
    local hook_mode
    if type(create_cvar) == "function" then
        hook_mode = create_cvar("lithium_hook_mode", "auto", { FCVAR_ARCHIVE }, "Hook backend mode: auto/fast/legacy")
        create_cvar("lithium_hook_selftest_allow_fallback", "0", { FCVAR_ARCHIVE }, "Allow invasive fallback migration self-tests")
    else
        lithium.warn("[CORE][BOOT] CreateConVar unavailable; using default hook mode 'auto'")
        hook_mode = { GetString = function() return "auto" end }
    end

    loader:register("core.gc", {
        convar = cvars.bool("core_gc", true, "Enable Lithium garbage collector", { per_realm = true }),
        panic_file = "lithium/panic/core_gc.txt",
        load = function()
            if timer and timer.Create then
                timer.Create("LITHIUM_garbage_collector", 300, 0, function()
                    collectgarbage("collect")
                    collectgarbage("step", 192)
                end)
            else
                lithium.warn("[CORE][GC] timer.Create unavailable; GC scheduler not started")
            end
        end
    })

    loader:register("hook.dispatch", {
        convar = cvars.bool("hook_dispatch", true, "Enable hybrid hook dispatcher", { per_realm = true }),
        panic_file = "lithium/panic/hook_dispatch.txt",
        load = function()
            local mode = dispatcher.select_mode(detect_compatibility(), hook_mode)
            dispatcher.enable(mode, { compatibility = compatibility })
        end
    })

    loader:register("hook.diagnostics", {
        convar = cvars.bool("hook_diagnostics", true, "Enable hook diagnostics commands", { per_realm = true }),
        load = safe_include("lithium/hook/diagnostics.lua")
    })

    loader:register("net.diagnostics", {
        convar = cvars.bool("net_diagnostics", false, "Enable network diagnostics instrumentation (diagnostics only)", { per_realm = true }),
        load = safe_include("lithium/net/diagnostics.lua")
    })

    loader:register("legacy.util", {
        convar = cvars.bool("legacy_util", true, "Enable legacy utility helpers", { per_realm = true }),
        load = safe_include("lithium/util.lua")
    })

    loader:register("legacy.client_util", {
        realm = "client",
        depends_on = { "legacy.util" },
        convar = cvars.bool("legacy_client_util", true, "Enable legacy client utility helpers", { server = false, per_realm = true }),
        load = safe_include("lithium/util/client.lua")
    })

    loader:register("legacy.cache_everything", {
        convar = cvars.bool("legacy_cache_everything", false, "Enable risky cache-everything overrides", { per_realm = true }),
        panic_file = "lithium/panic/legacy_cache_everything.txt",
        load = safe_include("lithium/extensions/caching.lua")
    })

    loader:register("legacy.clear_default_hooks", {
        convar = cvars.bool("legacy_clear_default_hooks", false, "Enable risky default hook removals", { per_realm = true }),
        panic_file = "lithium/panic/legacy_clear_default_hooks.txt",
        load = safe_include("lithium/killhooks.lua")
    })

    loader:register("legacy.convar_spray", {
        convar = cvars.bool("legacy_convar_spray", false, "Enable risky convar spray tuning", { per_realm = true }),
        panic_file = "lithium/panic/legacy_convar_spray.txt",
        load = safe_include("lithium/convars.lua")
    })

    loader:register("server.addon_patches", {
        convar = cvars.bool("server_addon_patches", true, "Enable targeted addon patch framework", { per_realm = true }),
        load = function()
            local mod = include("lithium/server/addon_patches.lua")
            if mod and mod.apply_all then
                mod.apply_all()
                lithium.addon_patch_summary = mod.get_summary and mod.get_summary() or nil
            end
        end
    })

    loader:register("client.gpu_saver", {
        realm = "client",
        convar = cvars.bool("client_gpu_saver", true, "Enable GPU saver", { server = false, per_realm = true }),
        load = safe_include("lithium/gpusaver.lua")
    })

    loader:register("client.timeout_overlay", {
        realm = "client",
        convar = cvars.bool("client_timeout_overlay", true, "Enable timeout overlay", { server = false, per_realm = true }),
        load = safe_include("lithium/timingout.lua")
    })

    loader:register("client.render.performant_lite", {
        realm = "client",
        convar = cvars.bool("exp_render_performant_lite", false, "Enable experimental PerformantRender-lite", { server = false, per_realm = true }),
        panic_file = "lithium/panic/exp_render_performant_lite.txt",
        load = safe_include("lithium/client/render/performant_render_apply.lua")
    })

    local result = loader:load_all({
        "core.gc", "hook.dispatch", "hook.diagnostics", "net.diagnostics", "legacy.util", "legacy.client_util", "legacy.cache_everything",
        "legacy.clear_default_hooks", "legacy.convar_spray", "server.addon_patches", "client.gpu_saver", "client.timeout_overlay",
        "client.render.performant_lite"
    })

    lithium.module_summary = result
    lithium.info("Startup complete. Loaded modules: " .. #result.loaded .. ", Failed modules: " .. #result.failed .. ", Skipped modules: " .. #result.skipped)
    if #result.failed > 0 then
        lithium.warn("Failed module list: " .. table.concat(result.failed, " | "))
    end
    if #result.skipped > 0 then
        lithium.info("Skipped module list: " .. table.concat(result.skipped, " | "))
    end

    local disp = dispatcher.get_stats and dispatcher.get_stats() or nil
    if disp then
        lithium.info("[HOOK] mode=" .. tostring(disp.active_mode) .. " fallbacks=" .. tostring(disp.fallback_count))
    end
end

return M
