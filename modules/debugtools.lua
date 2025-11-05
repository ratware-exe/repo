
-- modules/debug_tools.lua
do
    return function(UI)
        -- Dependencies
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv  = (getgenv and getgenv()) or _G
        GlobalEnv.Signal = GlobalEnv.Signal or loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()
        local Maid       = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()


        local Variables = {
            Maids = { DebugTools = Maid.new() },
            Map = {
                InfiniteYield = { primary = "https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source" },
                DexExplorer   = { primary = "https://raw.githubusercontent.com/Babyhamsta/RBLX_Scripts/main/Universal/BypassedDarkDexV3.lua" },
                Decompiler    = { primary = "https://raw.githubusercontent.com/depthso/Sigma-Spy/refs/heads/main/Main.lua" },
                SimpleSpy     = { primary = "https://github.com/exxtremestuffs/SimpleSpySource/raw/master/SimpleSpy.lua" },
                OctoSpy       = { primary = "https://raw.githubusercontent.com/InfernusScripts/Octo-Spy/refs/heads/main/Main.lua" },
                ShitSpy       = { primary = "https://gist.githubusercontent.com/WFYBGG/868c9485c3d1912a49e78bb7a3c8efe1/raw/124f52040b7aedfd339ac078ca105ab7f7e1db75/XenoSolaraSpy.lua" },
            },
        }
        local function tryLoad(url)
            local ok,src = pcall(function() return game:HttpGet(url) end)
            if not ok or type(src)~="string" or #src<3 then return false,"http" end
            local ok2,err = pcall(function() loadstring(src)() end)
            return ok2,err
        end

        local box = UI.Tabs.Debug:AddLeftGroupbox("Debug Tools", "bug-off")
        box:AddButton({ Text = "InfiniteYield", Func=function() tryLoad(Variables.Map.InfiniteYield.primary) end })
        box:AddButton({ Text = "Dex Explorer",  Func=function() tryLoad(Variables.Map.DexExplorer.primary)  end })
        box:AddButton({ Text = "Decompiler",    Func=function() tryLoad(Variables.Map.Decompiler.primary)   end })
        box:AddButton({ Text = "SimpleSpy",     Func=function() tryLoad(Variables.Map.SimpleSpy.primary)    end })
        box:AddButton({ Text = "Octo Spy",      Func=function() tryLoad(Variables.Map.OctoSpy.primary)      end })
        box:AddButton({ Text = "HTTPS Spy",     Func=function() tryLoad(Variables.Map.ShitSpy.primary)       end })

        local ModuleContract = { Name = "DebugTools", Stop = function() end }

        return ModuleContract
    end
end
