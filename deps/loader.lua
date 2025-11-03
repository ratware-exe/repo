-- loader.lua
-- Simple, cached importer for remote (or raw string) modules.
-- - Caches per name in a global table so multiple load points share results
-- - Safe against concurrent double-loads (cooperative lock + wait)
-- - Helpful debug helpers (IsCached / SourceOf / Purge / Set)

local Loader = {}
Loader.ClassName = "WFYB_Loader"

local function getGlobalTables()
    local globalTable = (getgenv and getgenv()) or _G
    globalTable._WFYB_IMPORTS = globalTable._WFYB_IMPORTS or {}
    globalTable._WFYB_SOURCES = globalTable._WFYB_SOURCES or {}
    globalTable._WFYB_LOCKS   = globalTable._WFYB_LOCKS   or {}
    return globalTable._WFYB_IMPORTS, globalTable._WFYB_SOURCES, globalTable._WFYB_LOCKS
end

local function isHttpUrl(text)
    return type(text) == "string" and (text:sub(1, 7) == "http://" or text:sub(1, 8) == "https://")
end

-- Import(name, urlOrSourceString)
-- urlOrSourceString:
--   - "https://..." or "http://..." → fetched via HttpGet
--   - otherwise treated as raw Lua source to loadstring
function Loader.Import(name, urlOrSourceString)
    assert(type(name) == "string" and #name > 0, "Import requires a non-empty module name")
    local importCache, sourceMap, lockMap = getGlobalTables()

    if importCache[name] ~= nil then
        return importCache[name]
    end

    -- Wait if another thread is currently importing the same name
    while lockMap[name] == true do
        task.wait()
        if importCache[name] ~= nil then
            return importCache[name]
        end
    end

    lockMap[name] = true

    local sourceCode
    if isHttpUrl(urlOrSourceString) then
        sourceCode = game:HttpGet(urlOrSourceString)
        sourceMap[name] = urlOrSourceString
    elseif type(urlOrSourceString) == "string" then
        sourceCode = urlOrSourceString
        sourceMap[name] = "[string]"
    else
        lockMap[name] = nil
        error("Import('" .. name .. "') requires a URL or source string", 2)
    end

    local chunkFunction, loadError = loadstring(sourceCode, "@" .. name)
    if not chunkFunction then
        lockMap[name] = nil
        error("Import('" .. name .. "') load failed: " .. tostring(loadError), 2)
    end

    local ok, resultOrError = pcall(chunkFunction)
    if not ok then
        lockMap[name] = nil
        error("Import('" .. name .. "') execution failed: " .. tostring(resultOrError), 2)
    end

    importCache[name] = resultOrError
    lockMap[name] = nil
    return resultOrError
end

-- Helpers

function Loader.IsCached(name)
    local importCache = getGlobalTables()
    return importCache[name] ~= nil
end

function Loader.SourceOf(name)
    local _, sourceMap = getGlobalTables()
    return sourceMap[name]
end

function Loader.Purge(name)
    local importCache, sourceMap, lockMap = getGlobalTables()
    importCache[name] = nil
    sourceMap[name] = nil
    lockMap[name] = nil
end

function Loader.Set(name, value)
    local importCache = getGlobalTables()
    importCache[name] = value
    return value
end

return Loader
