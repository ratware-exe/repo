-- modules/wfyb/AntiAFK.lua
-- Keeps session alive using Idled + small inputs.

return function()
    local RbxService
    local Variables
    local Maid
    local Signal
    local Library

    local Module = {}

    local function ensureServiceOnRbx(name)
        if not RbxService[name] then
            RbxService[name] = game:GetService(name)
        end
        return RbxService[name]
    end

    function Module.Init(env)
        RbxService = env.RbxService
        Variables  = env.Variables
        Maid       = env.Maid
        Signal     = env.Signal
        Library    = env.Library
        if not Variables.Maids.AntiAFK then
            Variables.Maids.AntiAFK = Maid.new()
        end
        ensureServiceOnRbx("VirtualUser")
        ensureServiceOnRbx("UserInputService")
    end

    function Module.BuildUI(Tabs)
        local Group = Tabs.Misc:AddRightGroupbox("AFK", "coffee")
        Group:AddToggle("WFYB_AntiAFKToggle", {
            Text = "Anti-AFK (VirtualUser)",
            Default = true
        })
        Library.Toggles.WFYB_AntiAFKToggle:OnChanged(function(isOn)
            if isOn then Module.Start() else Module.Stop() end
        end)
    end

    function Module.Start()
        if Variables.AntiAFKRunFlag then return end
        Variables.AntiAFKRunFlag = true

        local LocalPlayer = RbxService.Players.LocalPlayer
        if not LocalPlayer then
            Variables.AntiAFKRunFlag = false
            return
        end

        -- Standard Roblox approach
        local Connection = LocalPlayer.Idled:Connect(function()
            if not Variables.AntiAFKRunFlag then return end
            pcall(function()
                RbxService.VirtualUser:CaptureController()
                RbxService.VirtualUser:ClickButton2(Vector2.new(0, 0))
            end)
        end)

        Variables.Maids.AntiAFK:GiveTask(Connection)
        Variables.Maids.AntiAFK:GiveTask(function()
            Variables.AntiAFKRunFlag = false
        end)
    end

    function Module.Stop()
        if not Variables.AntiAFKRunFlag then return end
        Variables.AntiAFKRunFlag = false
        Variables.Maids.AntiAFK:DoCleaning()
    end

    return Module
end
