
-- modules/pvp_mode.lua
do
    return function(UI)
        -- Dependencies
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv  = (getgenv and getgenv()) or _G
        GlobalEnv.Signal = GlobalEnv.Signal or loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()
        local Maid       = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()


        local Variables = {
            Maids = { PVPMode = Maid.new() },
            RunFlag = false,
            Nevermore = nil,
            BoatConstants = nil,
            GetRemoteFunction = nil,
            BoatRemote = nil,
        }
        local function EnsureNevermore()
            if not Variables.Nevermore then
                Variables.Nevermore = require(RbxService.ReplicatedStorage:WaitForChild("Nevermore"))
            end
            Variables.GetRemoteFunction = Variables.GetRemoteFunction or Variables.Nevermore("GetRemoteFunction")
            Variables.BoatConstants = Variables.BoatConstants or Variables.Nevermore("BoatConstants")
            Variables.BoatRemote = Variables.BoatRemote or Variables.GetRemoteFunction(Variables.BoatConstants.API_REMOTE_FUNCTION)
        end
        local Module = {}
        function Module.Start()
            if Variables.RunFlag then return end
            Variables.RunFlag = true
            EnsureNevermore()
            local hb = RbxService.RunService.Heartbeat:Connect(function()
                pcall(function() Variables.BoatRemote:InvokeServer("EnablePVPMode") end)
            end)
            Variables.Maids.PVPMode:GiveTask(hb)
            Variables.Maids.PVPMode:GiveTask(function() Variables.RunFlag = false end)
        end
        function Module.Stop()
            if not Variables.RunFlag then return end
            Variables.RunFlag = false
            Variables.Maids.PVPMode:DoCleaning()
        end

        local box = UI.Tabs.EXP:AddRightGroupbox("PVP Mode", "swords")
        box:AddToggle("PVPModeToggle", { Text = "PVP Mode", Default = false, Tooltip = "Re-enables PVP mode client action." })
        UI.Toggles.PVPModeToggle:OnChanged(function(b) if b then Module.Start() else Module.Stop() end end)

        local ModuleContract = { Name = "PVPMode", Stop = Module.Stop }

        return ModuleContract
    end
end
