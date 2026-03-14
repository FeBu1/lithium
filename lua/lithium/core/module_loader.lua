require("lithium")

local Loader = {}
Loader.__index = Loader

function Loader.new()
    return setmetatable({ modules = {}, loaded = {}, failed = {} }, Loader)
end

function Loader:register(name, def)
    def.name = name
    self.modules[name] = def
end

function Loader:is_enabled(def)
    if def.realm == "client" and SERVER then
        return false, "wrong realm (client-only module)"
    end
    if def.realm == "server" and CLIENT then
        return false, "wrong realm (server-only module)"
    end

    if def.convar and not def.convar:GetBool() then
        return false, "disabled by convar"
    end
    if def.panic_file and file.Read(def.panic_file, "DATA") == "1" then
        return false, "panic disabled"
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
        lithium.info("Skipping module '" .. name .. "' (" .. reason .. ")")
        visiting[name] = nil
        return true
    end

    lithium.info("Loading module '" .. name .. "'")
    local ok, err = xpcall(def.load, debug.traceback)
    if not ok then
        self.failed[name] = err
        lithium.warn("Module '" .. name .. "' failed: " .. tostring(err))
        if def.panic_file then
            file.Write(def.panic_file, "1")
            lithium.warn("Panic flag written for '" .. name .. "' at data/" .. def.panic_file)
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

    local results = { loaded = {}, failed = {} }
    for name in pairs(self.loaded) do table.insert(results.loaded, name) end
    for name, reason in pairs(self.failed) do table.insert(results.failed, name .. ": " .. tostring(reason)) end
    table.sort(results.loaded)
    table.sort(results.failed)
    return results
end

return Loader
