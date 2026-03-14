require("lithium")

lithium._log_level = lithium._log_level or 1 -- 0=quiet,1=info,2=debug

local function prefix(level)
    return "[LITHIUM][" .. level .. "] "
end

function lithium.set_log_level(level)
    lithium._log_level = math.Clamp(tonumber(level) or 1, 0, 2)
end

function lithium.info(text)
    if lithium._log_level < 1 then return end
    print(prefix("INFO") .. tostring(text))
end

function lithium.debug(text)
    if lithium._log_level < 2 then return end
    print(prefix("DEBUG") .. tostring(text))
end

function lithium.warn(text)
    ErrorNoHalt(prefix("WARN") .. tostring(text) .. "\n")
end

lithium.log = lithium.info

return lithium
