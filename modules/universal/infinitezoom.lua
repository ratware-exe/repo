-- modules/infinitezoom.lua
do
    return function(UI)
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv = (getgenv and getgenv()) or _G
        GlobalEnv.Signal = GlobalEnv.Signal or loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()
        local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local Variables = {
            Maids = { InfiniteZoom = Maid.new() },
            RunFlag = false,
            Backup = nil,
            HugeZoomDistance = 1e8
        }

        local function Start()
            if Variables.RunFlag then return end
            Variables.RunFlag = true

            local LocalPlayer = RbxService.Players.LocalPlayer
            if not LocalPlayer then
                Variables.RunFlag = false
                return
            end

            if not Variables.Backup then
                pcall(function()
                    Variables.Backup = {
                        Max = LocalPlayer.CameraMaxZoomDistance,
                        Min = LocalPlayer.CameraMinZoomDistance,
                    }
                end)
            end

            pcall(function()
                LocalPlayer.CameraMaxZoomDistance = Variables.HugeZoomDistance
                LocalPlayer.CameraMinZoomDistance = 0
            end)

            local enforceConnection = RbxService.RunService.RenderStepped:Connect(function()
                if not Variables.RunFlag then return end
                local CurrentLocalPlayer = RbxService.Players.LocalPlayer
                if CurrentLocalPlayer then
                    pcall(function()
                        CurrentLocalPlayer.CameraMaxZoomDistance = Variables.HugeZoomDistance
                        CurrentLocalPlayer.CameraMinZoomDistance = 0
                    end)
                end
            end)

            Variables.Maids.InfiniteZoom:GiveTask(enforceConnection)
            Variables.Maids.InfiniteZoom:GiveTask(function() Variables.RunFlag = false end)
        end

        local function Stop()
            if not Variables.RunFlag then return end
            Variables.RunFlag = false
            Variables.Maids.InfiniteZoom:DoCleaning() 

            local LocalPlayer = RbxService.Players.LocalPlayer
            if LocalPlayer and Variables.Backup then
                pcall(function()
                    LocalPlayer.CameraMaxZoomDistance = Variables.Backup.Max or 400
                    LocalPlayer.CameraMinZoomDistance = Variables.Backup.Min or 0.5
                end)
                Variables.Backup = nil
            end
        end

        -- UI
        local CameraGroupBox = UI.Tabs.Misc:AddLeftGroupbox("Infinite Zoom", "mouse-pointer-2")
        CameraGroupBox:AddToggle("InfiniteZoomToggle", { 
            Text = "Infinite Zoom",
            Tooltip = "Allows you to zoom out infinitely.",
            Default = false,
        })
        UI.Toggles.InfiniteZoomToggle:OnChanged(function(enabledState)
            if enabledState then Start() else Stop() end
        end)

        return { Name = "InfiniteZoom", Stop = Stop }
    end
end
