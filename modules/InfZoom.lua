-- modules/InfZoom.lua
do
    return function(UI)
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv = (getgenv and getgenv()) or _G
        GlobalEnv.Signal = GlobalEnv.Signal or loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()
        local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local Variables = {
            Maids = { InfZoom = Maid.new() },
            RunFlag = false,
            Backup = nil,
        }

        local HugeZoomDistance = 1e8

        local function Start()
            if Variables.RunFlag then return end
            Variables.RunFlag = true

            local localPlayer = RbxService.Players.LocalPlayer
            if not localPlayer then
                Variables.RunFlag = false
                return
            end

            if not Variables.Backup then
                pcall(function()
                    Variables.Backup = {
                        Max = localPlayer.CameraMaxZoomDistance,
                        Min = localPlayer.CameraMinZoomDistance,
                    }
                end)
            end

            pcall(function()
                localPlayer.CameraMaxZoomDistance = HugeZoomDistance
                localPlayer.CameraMinZoomDistance = 0
            end)

            local enforceConnection = RbxService.RunService.RenderStepped:Connect(function()
                if not Variables.RunFlag then return end
                local currentLocalPlayer = RbxService.Players.LocalPlayer
                if currentLocalPlayer then
                    pcall(function()
                        currentLocalPlayer.CameraMaxZoomDistance = HugeZoomDistance
                        currentLocalPlayer.CameraMinZoomDistance = 0
                    end)
                end
            end)

            Variables.Maids.InfZoom:GiveTask(enforceConnection)
            Variables.Maids.InfZoom:GiveTask(function() Variables.RunFlag = false end)
        end

        local function Stop()
            if not Variables.RunFlag then return end
            Variables.RunFlag = false
            Variables.Maids.InfZoom:DoCleaning()

            local localPlayer = RbxService.Players.LocalPlayer
            if localPlayer and Variables.Backup then
                pcall(function()
                    localPlayer.CameraMaxZoomDistance = Variables.Backup.Max or 400
                    localPlayer.CameraMinZoomDistance = Variables.Backup.Min or 0.5
                end)
                Variables.Backup = nil
            end
        end

        -- UI
        local groupbox = UI.Tabs.Misc:AddLeftGroupbox("Inf Zoom", "mouse-pointer-2")
        groupbox:AddToggle("InfZoomToggle", {
            Text = "Infinite Zoom",
            Tooltip = "Allows you to zoom out infinitely.",
            Default = false,
        })
        UI.Toggles.InfZoomToggle:OnChanged(function(enabledState)
            if enabledState then Start() else Stop() end
        end)

        return { Name = "InfZoom", Stop = Stop }
    end
end
