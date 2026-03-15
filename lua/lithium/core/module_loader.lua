require("lithium")

local Loader = {}
Loader.__index = Loader

function Loader.new()
    return setmetatable({ modules = {}, loaded = {}, failed = {}, skipped = {} }, Loader)
end

function Loader:register(name, def)
    def.name = name
    self.modules[name] = def
end

local function describe_module(def)
    local realm = def.realm or "shared"
    local deps = (#(def.depends_on or {}) > 0) and table.concat(def.depends_on, ",") or "none"
    local cv = def.convar and def.convar:GetName() or "none"
    return string.format("realm=%s deps=%s convar=%s", realm, deps, cv)
end

function Loader:is_enabled(def)
    if def.realm == "client" and SERVER then
        return false, "wrong realm (client-only module)"
    end
    if def.realm == "server" and CLIENT then
        return false, "wrong realm (server-only module)"
    end

    if def.convar and not def.convar:GetBool() then
        return false, "disabled by convar " .. def.convar:GetName()
    end
    if def.panic_file and file and file.Read and file.Read(def.panic_file, "DATA") == "1" then
        return false, "panic disabled by data/" .. def.panic_file
    end
    return true
end

function Loader:load_module(name, visiting)
    if self.loaded[name] then return true end
    if self.failed[name] then return false end

    local def = self.modules[name]
    if not def then
        self.failed[name] = "unknown module"
        lithium.warn("Unknown module dependency: " .. tostring(name))
        return false
    end

    visiting = visiting or {}
    if visiting[name] then
        self.failed[name] = "cyclic dependency"
        lithium.warn("Cycle while loading module: " .. tostring(name))
        return false
    end
    visiting[name] = true

    for _, dep in ipairs(def.depends_on or {}) do
        if not self:load_module(dep, visiting) then
            self.failed[name] = "dependency failed: " .. dep
            visiting[name] = nil
            return false
        end
    end

    local enabled, reason = self:is_enabled(def)
    if not enabled then
        local text = "Skipping module '" .. name .. "' (" .. reason .. "; " .. describe_module(def) .. ")"
        lithium.info(text)
        self.skipped[name] = text
        visiting[name] = nil
        return true
    end

    lithium.info("Loading module '" .. name .. "' (" .. describe_module(def) .. ")")
    local traceback = debug and debug.traceback or function(e) return tostring(e) end
    local ok, err = xpcall(def.load, traceback)
    if not ok then
        self.failed[name] = err
        lithium.warn("Module '" .. name .. "' failed (" .. describe_module(def) .. "): " .. tostring(err))
        if def.panic_file and file and file.Write then
            file.Write(def.panic_file, "1")
            lithium.warn("Panic flag written for '" .. name .. "' at data/" .. def.panic_file)
        elseif def.panic_file then
            lithium.warn("Panic flag not written for '" .. name .. "' (file.Write unavailable)")
        end
        visiting[name] = nil
        return false
    end

    self.loaded[name] = true
    visiting[name] = nil
    return true
end

function Loader:load_all(order)
    local list = order or {}
    if #list == 0 then
        for name in pairs(self.modules) do
            list[#list + 1] = name
        end
    end

    for _, name in ipairs(list) do
        self:load_module(name)
    end

    local results = { loaded = {}, failed = {}, skipped = {} }
    for name in pairs(self.loaded) do table.insert(results.loaded, name) end
    for name, reason in pairs(self.failed) do table.insert(results.failed, name .. ": " .. tostring(reason)) end
    for name, detail in pairs(self.skipped) do table.insert(results.skipped, name .. ": " .. detail) end
    table.sort(results.loaded)
    table.sort(results.failed)
    table.sort(results.skipped)
    return results
end

return Loader
