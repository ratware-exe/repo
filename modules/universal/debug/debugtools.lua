-- modules/debugtools.lua
do
    return function(ui)
        local rbxservice = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local maid       = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
        local tasks      = maid.new()

        -- local helpers (no globals; respects executor env)
        local function notify(text)
            local lib = ui and ui.Library
            if lib and lib.Notify then
                pcall(lib.Notify, lib, tostring(text), 6)
            else
                print("[Notify]", text)
            end
        end

        local function try_load(url)
            if type(url) ~= "string" or url == "" then
                return false, "empty url"
            end
            return pcall(function()
                local src = game:HttpGet(url)
                local chunk = loadstring(src)
                local result = chunk()
                return (result == nil) and true or result
            end)
        end

        -- mirrors the source map used in your main-2.lua
        local source_map = {
            infiniteyield = {
                primary  = "https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source",
                fallback = "https://gist.githubusercontent.com/WFYBGG/f2fc85f38dac87ee5cb1c95b1c3c4e50/raw/46cad0d7f207a6cbc85a3c75d7fec5d49e622ba4/InfiniteYieldSource.lua",
            },
            dexexplorer = {
                primary  = "https://raw.githubusercontent.com/Babyhamsta/RBLX_Scripts/main/Universal/BypassedDarkDexV3.lua",
                fallback = "https://gist.githubusercontent.com/WFYBGG/3c75ac87b1ccf48e425e1cb2526d9ecf/raw/7ad05fe46a5ff0a39dc867cf3d949cc081b9b674/Dex.lua",
            },
            decompiler = {
                primary  = "https://raw.githubusercontent.com/depthso/Sigma-Spy/refs/heads/main/Main.lua",
                fallback = "https://raw.githubusercontent.com/depthso/Sigma-Spy/refs/heads/main/Main.lua",
            },
            simplespy = {
                primary  = "https://github.com/exxtremestuffs/SimpleSpySource/raw/master/SimpleSpy.lua",
                fallback = "https://raw.githubusercontent.com/78n/SimpleSpy/main/SimpleSpyBeta.lua",
            },
            octospy = {
                primary  = "https://raw.githubusercontent.com/InfernusScripts/Octo-Spy/refs/heads/main/Main.lua",
                fallback = "https://raw.githubusercontent.com/InfernusScripts/Octo-Spy/refs/heads/main/Main.lua",
            },
            httpspy = {
                primary  = "https://gist.githubusercontent.com/WFYBGG/868c9485c3d1912a49e78bb7a3c8efe1/raw/124f52040b7aedfd339ac078ca105ab7f7e1db75/XenoSolaraSpy.lua",
                fallback = "https://gist.githubusercontent.com/WFYBGG/0f5aea79182fd8c9151ff4c2648d5681/raw/19d774c848872118575d63fb54e0604bf47d5797/gistfile1.txt",
            },
        } -- matches your previous setup. :contentReference[oaicite:1]{index=1}

        local function make_ensure(global_key, pair, label)
            label = label or global_key
            return function(force_reload)
                local genv = (getgenv and getgenv()) or _G
                if not force_reload and genv[global_key] ~= nil then
                    return genv[global_key], true
                end
                local ok1, res1 = try_load(pair.primary)
                local final, ok = res1, ok1
                if not ok1 then
                    warn(("[%s] primary failed: %s"):format(label, tostring(res1)))
                    local ok2, res2 = try_load(pair.fallback)
                    final, ok = res2, ok2
                    if not ok2 then
                        return nil, false, ("primary failed: %s | fallback failed: %s"):format(tostring(res1), tostring(res2))
                    end
                end
                genv[global_key] = (final == nil) and true or final
                return genv[global_key], true
            end
        end

        local ensure_infiniteyield = make_ensure("InfiniteYield",      source_map.infiniteyield, "Infinite Yield")
        local ensure_dex          = make_ensure("DexExplorer",         source_map.dexexplorer,   "Dex Explorer")
        local ensure_decompiler   = make_ensure("Decompiler",          source_map.decompiler,    "Decompiler")
        local ensure_simplespy    = make_ensure("SimpleSpy",           source_map.simplespy,     "SimpleSpy")
        local ensure_octospy      = make_ensure("OctoSpy",             source_map.octospy,       "OctoSpy")
        local ensure_httpspy      = make_ensure("ShitsploitHttpsSpy",  source_map.httpspy,       "HTTPS Spy")

        -- UI (uses existing Debug tab)
        local tab = ui.Tabs.Debug or ui.Tabs["Debug"]
        if not tab then
            -- fall back: create under Misc if user renamed Debug
            tab = ui.Tabs.Misc or ui.Tabs["Misc"]
        end

        local tools_group = tab:AddLeftGroupbox("Client Modifiers", "pocket-knife")
        tools_group:AddButton({
            Text = "Load Infinite Yield",
            Func = function()
                local _, ok, err = ensure_infiniteyield(false)
                if ok then notify("Infinite Yield loaded.") else notify("Failed to load Infinite Yield.\n" .. tostring(err)) end
            end,
            DoubleClick = true,
            Tooltip = "Double click to load infinite yield.",
            DisabledTooltip = "Feature Disabled",
            Disabled = false,
        })
        tools_group:AddButton({
            Text = "Load Dex Explorer",
            Func = function()
                local _, ok, err = ensure_dex(false)
                if ok then notify("Dex Explorer loaded.") else notify("Failed to load Dex Explorer.\n" .. tostring(err)) end
            end,
            DoubleClick = true,
            Tooltip = "Double click to load dex explorer.",
            DisabledTooltip = "Feature Disabled",
            Disabled = false,
        })
        tools_group:AddButton({
            Text = "Load Decompiler",
            Func = function()
                local _, ok, err = ensure_decompiler(false)
                if ok then notify("Decompiler loaded.") else notify("Failed to load Decompiler.\n" .. tostring(err)) end
            end,
            DoubleClick = true,
            Tooltip = "Double click to load decompiler.",
            DisabledTooltip = "Feature Disabled",
            Disabled = false,
        })

        local spies_group = tab:AddLeftGroupbox("Remote Spys", "hat-glasses")
        spies_group:AddButton({
            Text = "Load Simple Spy",
            Func = function()
                local _, ok, err = ensure_simplespy(false)
                if ok then notify("SimpleSpy loaded.") else notify("Failed to load SimpleSpy.\n" .. tostring(err)) end
            end,
            DoubleClick = true,
            Tooltip = "Double click to load simple spy.",
            DisabledTooltip = "Feature Disabled",
            Disabled = false,
        })
        spies_group:AddButton({
            Text = "Load OctoSpy",
            Func = function()
                local _, ok, err = ensure_octospy(false)
                if ok then notify("OctoSpy loaded.") else notify("Failed to load OctoSpy.\n" .. tostring(err)) end
            end,
            DoubleClick = true,
            Tooltip = "Double click to load octospy.",
            DisabledTooltip = "Feature Disabled",
            Disabled = false,
        })
        spies_group:AddButton({
            Text = "Load Https Spy",
            Func = function()
                local _, ok, err = ensure_httpspy(false)
                if ok then notify("HTTPS Spy loaded.") else notify("Failed to load HTTPS Spy.\n" .. tostring(err)) end
            end,
            DoubleClick = true,
            Tooltip = "Double click to load https spy.",
            DisabledTooltip = "Feature Disabled",
            Disabled = false,
        })

        local function stop()
            tasks:DoCleaning()
        end

        return { Name = "debugtools", Stop = stop }
    end
end
