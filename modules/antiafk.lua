-- modules/antiafk.lua
do
    return function(UI)
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv = (getgenv and getgenv()) or _G
        GlobalEnv.Signal = GlobalEnv.Signal or loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()
        local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local Variables = {
            Maids = { AntiAFK = Maid.new() },
            Config = {
                Enabled = false,
                DisableIdledConnections = true,
                VirtualUserFallback = true,
                PeriodicNudge = false,
                NudgeIntervalSeconds = 60,
            },
            State = {
                NudgeLoop = nil,
                IdledConn = nil,
            },
        }

        local function DisableExistingIdledConnections()
            local ok, list = pcall(getconnections, RbxService.Players.LocalPlayer.Idled)
            if not ok or type(list) ~= "table" then return false end
            for index = 1, #list do
                local connection = list[index]
                if connection then
                    local done = false
                    if connection.Disable then done = pcall(function() connection:Disable() end) end
                    if not done and connection.Disconnect then pcall(function() connection:Disconnect() end) end
                end
            end
            return true
        end

        local function BindVirtualUserFallback()
            if Variables.State.IdledConn then return end
            if not RbxService.VirtualUser then return end
            Variables.State.IdledConn = RbxService.Players.LocalPlayer.Idled:Connect(function()
                pcall(function()
                    RbxService.VirtualUser:CaptureController()
                    RbxService.VirtualUser:ClickButton2(Vector2.new(0, 0),
                        RbxService.Workspace.CurrentCamera and RbxService.Workspace.CurrentCamera.CFrame or CFrame.new())
                end)
            end)
            Variables.Maids.AntiAFK:GiveTask(Variables.State.IdledConn)
        end

        local function StartPeriodicNudge()
            if Variables.State.NudgeLoop then return end
            if not RbxService.VirtualInputManager then return end
            local lastNudge = 0
            Variables.State.NudgeLoop = RbxService.RunService.Heartbeat:Connect(function()
                if not Variables.Config.PeriodicNudge then return end
                local now = os.clock()
                if now - lastNudge >= Variables.Config.NudgeIntervalSeconds then
                    lastNudge = now
                    pcall(function()
                        local pos = RbxService.UserInputService:GetMouseLocation()
                        RbxService.VirtualInputManager:SendMouseMoveEvent(pos.X, pos.Y, true)
                    end)
                end
            end)
            Variables.Maids.AntiAFK:GiveTask(Variables.State.NudgeLoop)
        end

        local function StopAll()
            Variables.Config.Enabled = false
            Variables.Maids.AntiAFK:DoCleaning()
            Variables.State.IdledConn = nil
            Variables.State.NudgeLoop = nil
        end

        local function StartAll()
            Variables.Config.Enabled = true
            if Variables.Config.DisableIdledConnections then
                DisableExistingIdledConnections()
            end
            if Variables.Config.VirtualUserFallback then
                BindVirtualUserFallback()
            end
            if Variables.Config.PeriodicNudge then
                StartPeriodicNudge()
            end
        end

        local group = UI.Tabs.Misc:AddLeftGroupbox("Anti Idle", "user-x")
        group:AddToggle("AntiIdleEnabled", {
            Text = "Enable Anti Idle",
            Tooltip = "Prevents kick for idling. Disables Idled listeners; VirtualUser fallback.",
            Default = false,
        }):OnChanged(function(state)
            if state then StartAll() else StopAll() end
        end)
        group:AddToggle("AntiIdleDisableIdled", { Text="Disable Idled Connections", Default=Variables.Config.DisableIdledConnections })
            :OnChanged(function(state)
                Variables.Config.DisableIdledConnections = state
                if Variables.Config.Enabled and state then DisableExistingIdledConnections() end
            end)
        group:AddToggle("AntiIdleVirtualUser", { Text="VirtualUser Fallback", Default=Variables.Config.VirtualUserFallback })
            :OnChanged(function(state)
                Variables.Config.VirtualUserFallback = state
                if Variables.Config.Enabled then
                    if state and not Variables.State.IdledConn then BindVirtualUserFallback()
                    elseif (not state) and Variables.State.IdledConn then
                        Variables.State.IdledConn:Disconnect()
                        Variables.State.IdledConn = nil
                    end
                end
            end)
        group:AddToggle("AntiIdlePeriodicNudge", { Text="Periodic Mouse Nudge", Default=Variables.Config.PeriodicNudge })
            :OnChanged(function(state)
                Variables.Config.PeriodicNudge = state
                if Variables.Config.Enabled then if state then StartPeriodicNudge() end end
            end)
        group:AddSlider("AntiIdleNudgeInterval", { Label="Nudge Interval", Min=10, Max=180, Default=60, Suffix="sec" })
            :OnChanged(function(value) Variables.Config.NudgeIntervalSeconds = math.floor(value) end)

        local function ModuleStop()
            if UI.Toggles.AntiIdleEnabled then UI.Toggles.AntiIdleEnabled:SetValue(false) end
            StopAll()
        end

        return { Name = "AntiIdle", Stop = ModuleStop }
    end
end
