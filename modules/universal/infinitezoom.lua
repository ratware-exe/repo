-- modules/wfyb/InfZoom.lua
-- Infinite zoom with safe restore.

return function()
    local RbxService
    local Variables
    local Maid
    local Signal
    local Library

    local Module = {}
    local Backup = nil

    local function getLocalPlayer()
        return RbxService.Players.LocalPlayer
    end

    function Module.Init(env)
        RbxService = env.RbxService
        Variables  = env.Variables
        Maid       = env.Maid
        Signal     = env.Signal
        Library    = env.Library
        if not Variables.Maids.InfZoom then
            Variables.Maids.InfZoom = Maid.new()
        end
    end

    function Module.BuildUI(Tabs)
        local Group = Tabs.Misc:AddLeftGroupbox("Client Tweaks", "mouse-pointer-2")
        Group:AddToggle("WFYB_InfZoomToggle", {
            Text = "Infinite Zoom",
            Default = false
        })
        Library.Toggles.WFYB_InfZoomToggle:OnChanged(function(isOn)
            if isOn then Module.Start() else Module.Stop() end
        end)
    end

    function Module.Start()
        if Variables.InfZoomRunFlag then return end
        Variables.InfZoomRunFlag = true

        local LocalPlayer = getLocalPlayer()
        if not LocalPlayer then
            Variables.InfZoomRunFlag = false
            return
        end

        if not Backup then
            Backup = {
                Max = LocalPlayer.CameraMaxZoomDistance,
                Min = LocalPlayer.CameraMinZoomDistance
            }
        end

        pcall(function()
            LocalPlayer.CameraMaxZoomDistance = 1e8
            LocalPlayer.CameraMinZoomDistance = 0
        end)

        local Enforce = RbxService.RunService.RenderStepped:Connect(function()
            if not Variables.InfZoomRunFlag then return end
            local CurrentPlayer = getLocalPlayer()
            if CurrentPlayer then
                pcall(function()
                    CurrentPlayer.CameraMaxZoomDistance = 1e8
                    CurrentPlayer.CameraMinZoomDistance = 0
                end)
            end
        end)

        Variables.Maids.InfZoom:GiveTask(Enforce)
        Variables.Maids.InfZoom:GiveTask(function()
            Variables.InfZoomRunFlag = false
        end)
    end

    function Module.Stop()
        if not Variables.InfZoomRunFlag then return end
        Variables.InfZoomRunFlag = false

        Variables.Maids.InfZoom:DoCleaning()

        local LocalPlayer = RbxService.Players.LocalPlayer
        if LocalPlayer and Backup then
            pcall(function()
                LocalPlayer.CameraMaxZoomDistance = Backup.Max or 400
                LocalPlayer.CameraMinZoomDistance = Backup.Min or 0.5
            end)
        end
        Backup = nil
    end

    return Module
end
