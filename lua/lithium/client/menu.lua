require("lithium")

local M = {}

local _G = _G
local string = string
local table = table
local math = math
local hook = hook
local concommand = concommand
local spawnmenu = spawnmenu
local vgui = vgui
local Derma = Derma

local tostring = tostring
local tonumber = tonumber
local next_fn = next or (_G and _G.next)
local RunConsoleCommandFn = RunConsoleCommand

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
        if v ~= nil then return i, v end
    end
    return iter, t, 0
end

local pairs_fn = pairs or (_G and _G.pairs) or fallback_pairs
local ipairs_fn = ipairs or (_G and _G.ipairs) or fallback_ipairs
local table_sort = table.sort
local math_min = math.min

local function top_from_map(map, mapfn, sorter, limit)
    local out = {}
    for k, v in pairs_fn(map or {}) do
        out[#out + 1] = mapfn(k, v)
    end
    table_sort(out, sorter)

    local clipped = {}
    for i = 1, math_min(limit or #out, #out) do
        clipped[#clipped + 1] = out[i]
    end
    return clipped
end

local function build_snapshot()
    local disp = lithium.hook_dispatcher and lithium.hook_dispatcher.get_stats and lithium.hook_dispatcher.get_stats() or {}
    local diag = hook.GetLithiumDiagnostics and hook.GetLithiumDiagnostics() or {}
    local net_report = lithium.net_diagnostics and lithium.net_diagnostics.get_report and lithium.net_diagnostics.get_report(10) or nil
    local compat = lithium.compatibility_registry and lithium.compatibility_registry.get_stats and lithium.compatibility_registry.get_stats() or {}
    local modules = lithium.module_summary or { loaded = {}, failed = {}, skipped = {} }
    local patches = lithium.addon_patch_summary or { total = 0, applied = 0, failed = 0, failed_detail = {} }

    local top_event = top_from_map(diag.by_event or {}, function(event, item)
        return { event = event, calls = item.calls or 0, time = item.time or 0 }
    end, function(a, b) return a.time > b.time end, 1)[1]

    local top_source = top_from_map(diag.by_source or {}, function(source, item)
        return { source = source, calls = item.calls or 0, time = item.time or 0 }
    end, function(a, b) return a.time > b.time end, 1)[1]

    local top_net = net_report and net_report.top_messages_by_bytes and net_report.top_messages_by_bytes[1] or nil

    return {
        dispatcher = disp,
        diagnostics = diag,
        net = net_report,
        compatibility = compat,
        modules = modules,
        patches = patches,
        top_event = top_event,
        top_source = top_source,
        top_net = top_net
    }
end

local function row(list, key, value)
    list:AddLine(tostring(key), tostring(value))
end

local function make_list(parent, cols)
    local lv = vgui.Create("DListView", parent)
    lv:Dock(FILL)
    for _, c in ipairs_fn(cols) do lv:AddColumn(c) end
    return lv
end

local function build_overview_tab(sheet)
    local panel = vgui.Create("DPanel", sheet)
    panel:DockPadding(8, 8, 8, 8)

    local list = make_list(panel, { "Metric", "Value" })
    local snap = build_snapshot()

    local loaded = #(snap.modules.loaded or {})
    local skipped = #(snap.modules.skipped or {})
    local failed = #(snap.modules.failed or {})

    row(list, "Hook backend mode", snap.dispatcher.active_mode or "unknown")
    row(list, "Fallback count", snap.dispatcher.fallback_count or 0)
    row(list, "Migration count", snap.dispatcher.migration_count or 0)
    row(list, "Loaded modules", loaded)
    row(list, "Skipped modules", skipped)
    row(list, "Failed modules", failed)
    row(list, "Profiler enabled", (GetConVar and GetConVar("lithium_hook_profiler_enabled") and GetConVar("lithium_hook_profiler_enabled"):GetBool()) and "yes" or "no")
    row(list, "Net diagnostics module", snap.net and "enabled" or "disabled")
    row(list, "Top hook event", snap.top_event and (snap.top_event.event .. " (" .. string.format("%.6f", snap.top_event.time) .. "s)") or "n/a")
    row(list, "Top hook source", snap.top_source and (snap.top_source.source .. " (" .. string.format("%.6f", snap.top_source.time) .. "s)") or "n/a")
    row(list, "Top net message", snap.top_net and (snap.top_net.name .. " (" .. tostring(snap.top_net.bytes) .. "B)") or "n/a")

    local warn = vgui.Create("DLabel", panel)
    warn:Dock(BOTTOM)
    warn:SetWrap(true)
    warn:SetTall(56)
    warn:SetText("Read-mostly dashboard. Experimental/dangerous modules remain controlled by existing convars. Missing telemetry modules show n/a instead of hard-failing.")

    sheet:AddSheet("Overview", panel, "icon16/monitor.png")
end

local function build_modules_tab(sheet)
    local panel = vgui.Create("DPanel", sheet)
    panel:DockPadding(8, 8, 8, 8)

    local list = make_list(panel, { "State", "Entry" })
    local ms = lithium.module_summary or { loaded = {}, skipped = {}, failed = {} }

    for _, name in ipairs_fn(ms.loaded or {}) do list:AddLine("loaded", name) end
    for _, detail in ipairs_fn(ms.skipped or {}) do list:AddLine("skipped", detail) end
    for _, detail in ipairs_fn(ms.failed or {}) do list:AddLine("failed", detail) end

    sheet:AddSheet("Modules", panel, "icon16/bricks.png")
end

local function build_hooks_tab(sheet)
    local panel = vgui.Create("DPanel", sheet)
    panel:DockPadding(8, 8, 8, 8)

    local list = make_list(panel, { "Type", "Name", "Calls", "Time" })
    local diag = hook.GetLithiumDiagnostics and hook.GetLithiumDiagnostics() or {}

    for _, e in ipairs_fn(top_from_map(diag.by_event or {}, function(event, item)
        return { kind = "event", name = event, calls = item.calls or 0, time = item.time or 0 }
    end, function(a, b) return a.time > b.time end, 15)) do
        list:AddLine(e.kind, e.name, e.calls, string.format("%.6f", e.time))
    end

    for _, s in ipairs_fn(top_from_map(diag.by_source or {}, function(source, item)
        return { kind = "source", name = source, calls = item.calls or 0, time = item.time or 0 }
    end, function(a, b) return a.time > b.time end, 15)) do
        list:AddLine(s.kind, s.name, s.calls, string.format("%.6f", s.time))
    end

    sheet:AddSheet("Hooks", panel, "icon16/lightning.png")
end

local function build_network_tab(sheet)
    local panel = vgui.Create("DPanel", sheet)
    panel:DockPadding(8, 8, 8, 8)

    local list = make_list(panel, { "Type", "Name", "Sends", "Bytes" })
    local net_report = lithium.net_diagnostics and lithium.net_diagnostics.get_report and lithium.net_diagnostics.get_report(15) or nil

    if not net_report then
        list:AddLine("info", "net.diagnostics disabled", 0, 0)
    else
        for _, m in ipairs_fn(net_report.top_messages_by_bytes or {}) do
            list:AddLine("message", m.name, m.sends, m.bytes)
        end
        for _, s in ipairs_fn(net_report.top_sources_by_bytes or {}) do
            list:AddLine("source", s.source, s.sends, s.bytes)
        end
    end

    sheet:AddSheet("Networking", panel, "icon16/transmit.png")
end

local function build_compat_tab(sheet)
    local panel = vgui.Create("DPanel", sheet)
    panel:DockPadding(8, 8, 8, 8)

    local list = make_list(panel, { "Metric", "Value" })
    local compat = lithium.compatibility_registry and lithium.compatibility_registry.get_stats and lithium.compatibility_registry.get_stats() or nil

    if not compat then
        list:AddLine("status", "compatibility registry unavailable")
    else
        row(list, "source matches", compat.source_matches or 0)
        row(list, "addon matches", compat.addon_matches or 0)
        row(list, "force legacy matches", compat.force_legacy_matches or 0)
        row(list, "feature hint matches", compat.feature_hint_matches or 0)
        row(list, "observe matches", compat.observe_matches or 0)
        row(list, "unique sources", compat.unique_sources or 0)

        for _, item in ipairs_fn(top_from_map(compat.source_match_rules or {}, function(rule_id, hits)
            local meta = compat.source_rule_meta and compat.source_rule_meta[rule_id] or {}
            return {
                key = rule_id,
                hits = hits,
                action = meta.action or "unknown",
                origin = meta.origin or "unknown"
            }
        end, function(a, b) return a.hits > b.hits end, 10)) do
            list:AddLine("rule " .. item.key, item.action .. " / " .. item.origin .. " / hits=" .. tostring(item.hits))
        end
    end

    sheet:AddSheet("Compatibility", panel, "icon16/shield.png")
end

local function build_patches_tab(sheet)
    local panel = vgui.Create("DPanel", sheet)
    panel:DockPadding(8, 8, 8, 8)

    local list = make_list(panel, { "Metric", "Value" })
    local ps = lithium.addon_patch_summary or nil
    if not ps then
        list:AddLine("status", "patch summary unavailable")
    else
        row(list, "total", ps.total or 0)
        row(list, "applied", ps.applied or 0)
        row(list, "failed", ps.failed or 0)
        for _, fail in ipairs_fn(ps.failed_detail or {}) do
            list:AddLine("failed detail", tostring(fail))
        end
    end

    sheet:AddSheet("Patches", panel, "icon16/wrench.png")
end

local function run_cmd(cmd, ...)
    if type(RunConsoleCommandFn) ~= "function" then
        if type(Derma) == "table" and Derma.Message then
            Derma.Message("RunConsoleCommand unavailable in this context.", "Lithium", "OK")
        end
        return
    end
    RunConsoleCommandFn(cmd, ...)
end

local function build_reports_tab(sheet)
    local panel = vgui.Create("DPanel", sheet)
    panel:DockPadding(8, 8, 8, 8)

    local controls = vgui.Create("DPanel", panel)
    controls:Dock(TOP)
    controls:SetTall(160)

    local dump_btn = vgui.Create("DButton", controls)
    dump_btn:SetText("Run report dump")
    dump_btn:SetPos(0, 0)
    dump_btn:SetSize(180, 28)
    dump_btn.DoClick = function() run_cmd("lithium_report_dump", "15") end

    local export_btn = vgui.Create("DButton", controls)
    export_btn:SetText("Export report")
    export_btn:SetPos(190, 0)
    export_btn:SetSize(180, 28)
    export_btn.DoClick = function() run_cmd("lithium_report_export", "15") end

    local prof_reset_btn = vgui.Create("DButton", controls)
    prof_reset_btn:SetText("Reset hook profiler")
    prof_reset_btn:SetPos(0, 36)
    prof_reset_btn:SetSize(180, 28)
    prof_reset_btn.DoClick = function() run_cmd("lithium_hook_profiler_reset") end

    local net_reset_btn = vgui.Create("DButton", controls)
    net_reset_btn:SetText("Reset net telemetry")
    net_reset_btn:SetPos(190, 36)
    net_reset_btn:SetSize(180, 28)
    net_reset_btn.DoClick = function() run_cmd("lithium_net_reset") end

    local compare_a = vgui.Create("DTextEntry", controls)
    compare_a:SetPos(0, 76)
    compare_a:SetSize(280, 24)
    compare_a:SetPlaceholderText("report A path (e.g. lithium/reports/report_YYYYMMDD_HHMMSS.json)")

    local compare_b = vgui.Create("DTextEntry", controls)
    compare_b:SetPos(0, 106)
    compare_b:SetSize(280, 24)
    compare_b:SetPlaceholderText("report B path")

    local compare_btn = vgui.Create("DButton", controls)
    compare_btn:SetText("Compare reports")
    compare_btn:SetPos(290, 90)
    compare_btn:SetSize(130, 28)
    compare_btn.DoClick = function()
        run_cmd("lithium_report_compare", compare_a:GetValue(), compare_b:GetValue(), "15")
    end

    local info = vgui.Create("DLabel", panel)
    info:Dock(TOP)
    info:SetTall(36)
    info:SetWrap(true)
    info:SetText("Reports tab is intentionally read-mostly: buttons trigger existing safe diagnostics commands and comparison workflow.")

    sheet:AddSheet("Reports", panel, "icon16/page_white_text.png")
end

function M.open()
    if not (vgui and vgui.Create) then
        lithium.warn("[MENU] vgui unavailable; lithium_menu cannot open")
        return
    end

    local frame = vgui.Create("DFrame")
    frame:SetTitle("Lithium Diagnostics Dashboard (First Pass)")
    frame:SetSize(980, 650)
    frame:Center()
    frame:MakePopup()

    local sheet = vgui.Create("DPropertySheet", frame)
    sheet:Dock(FILL)

    build_overview_tab(sheet)
    build_modules_tab(sheet)
    build_hooks_tab(sheet)
    build_network_tab(sheet)
    build_compat_tab(sheet)
    build_patches_tab(sheet)
    build_reports_tab(sheet)
end

if concommand and concommand.Add then
    concommand.Add("lithium_menu", function()
        M.open()
    end)
end

if hook and hook.Add then
    hook.Add("PopulateToolMenu", "LithiumMenuPopulate", function()
        if not (spawnmenu and spawnmenu.AddToolMenuOption) then return end
        spawnmenu.AddToolMenuOption("Utilities", "Lithium", "LithiumMenuOpen", "Open Lithium Menu", "", "", function(panel)
            panel:ClearControls()
            panel:Button("Open Lithium Diagnostics Menu", "lithium_menu")
            panel:Help("First-pass read-only diagnostics dashboard for Lithium triage.")
        end)
    end)
end

lithium.menu = M
return M
