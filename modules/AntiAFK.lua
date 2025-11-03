-- modules/AntiAFK.lua
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
            local hasGetConnections, connectionsOrError = pcall(getconnections, RbxService.Players.LocalPlayer.Idled)
            if not hasGetConnections or type(connectionsOrError) ~= "table" then
                return false
            end
            for connectionIndex = 1, #connectionsOrError do
                local connectionObject = connectionsOrError[connectionIndex]
                local disabledOk = false
                if connectionObject and connectionObject.Disable then
                    disabledOk = pcall(function() connectionObject:Disable() end)
                end
                if (not disabledOk) and connectionObject and connectionObject.Disconnect then
                    pcall(function() connectionObject:Disconnect() end)
                end
            end
            return true
        end

        local function BindVirtualUserFallback()
            if Variables.State.IdledConn then return end
            local virtualUser = RbxService.VirtualUser
            if not virtualUser then return end
            Variables.State.IdledConn = RbxService.Players.LocalPlayer.Idled:Connect(function()
                pcall(function()
                    virtualUser:CaptureController()
                    virtualUser:ClickButton2(Vector2.new(0, 0), RbxService.Workspace.CurrentCamera and RbxService.Workspace.CurrentCamera.CFrame or CFrame.new())
                end)
            end)
            Variables.Maids.AntiAFK:GiveTask(Variables.State.IdledConn)
        end

        local function StartPeriodicNudge()
            if Variables.State.NudgeLoop then return end
            local virtualInput = RbxService.VirtualInputManager
            if not virtualInput then return end
            local lastNudge = 0
            Variables.State.NudgeLoop = RbxService.RunService.Heartbeat:Connect(function()
                if not Variables.Config.PeriodicNudge then return end
                local now = os.clock()
                if now - lastNudge >= Variables.Config.NudgeIntervalSeconds then
                    lastNudge = now
                    pcall(function()
                        local mousePos = RbxService.UserInputService:GetMouseLocation()
                        virtualInput:SendMouseMoveEvent(mousePos.X, mousePos.Y, true)
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

            -- 1) Disable Roblox's default Idle kick listeners (if exploiter supports it)
            if Variables.Config.DisableIdledConnections then
                DisableExistingIdledConnections()
            end

            -- 2) VirtualUser fallback (robust + executor-agnostic)
            if Variables.Config.VirtualUserFallback then
                BindVirtualUserFallback()
            end

            -- 3) Optional periodic nudge
            if Variables.Config.PeriodicNudge then
                StartPeriodicNudge()
            end
        end

        -- === UI ===
        local clientTweaksGroup = UI.Tabs.Misc:AddLeftGroupbox("Anti Idle", "user-x")
        clientTweaksGroup:AddToggle("AntiIdleEnabled", {
            Text = "Enable Anti Idle",
            Tooltip = "Prevents kick for idling. Disables existing Idled listeners, plus VirtualUser fallback.",
            Default = false,
        })
        UI.Toggles.AntiIdleEnabled:OnChanged(function(state)
            if state then StartAll() else StopAll() end
        end)

        clientTweaksGroup:AddToggle("AntiIdleDisableIdled", {
            Text = "Disable Idled Connections",
            Default = Variables.Config.DisableIdledConnections,
        }):OnChanged(function(state)
            Variables.Config.DisableIdledConnections = state
            if Variables.Config.Enabled and state then
                DisableExistingIdledConnections()
            end
        end)

        clientTweaksGroup:AddToggle("AntiIdleVirtualUser", {
            Text = "VirtualUser Fallback",
            Default = Variables.Config.VirtualUserFallback,
        }):OnChanged(function(state)
            Variables.Config.VirtualUserFallback = state
            if Variables.Config.Enabled then
                if state and not Variables.State.IdledConn then
                    BindVirtualUserFallback()
                elseif (not state) and Variables.State.IdledConn then
                    Variables.State.IdledConn:Disconnect()
                    Variables.State.IdledConn = nil
                end
            end
        end)

        clientTweaksGroup:AddToggle("AntiIdlePeriodicNudge", {
            Text = "Periodic Mouse Nudge",
            Default = Variables.Config.PeriodicNudge,
            Tooltip = "Uses VirtualInputManager to nudge the mouse every N seconds.",
        }):OnChanged(function(state)
            Variables.Config.PeriodicNudge = state
            if Variables.Config.Enabled then
                if state then StartPeriodicNudge() end
            end
        end)

        clientTweaksGroup:AddSlider("AntiIdleNudgeInterval", {
            Label = "Nudge Interval",
            Min = 10, Max = 180, Default = 60, Suffix = "sec",
        }):OnChanged(function(value)
            Variables.Config.NudgeIntervalSeconds = math.floor(value)
        end)

        local function ModuleStop()
            if UI.Toggles.AntiIdleEnabled then UI.Toggles.AntiIdleEnabled:SetValue(false) end
            StopAll()
        end

        return { Name = "AntiIdle", Stop = ModuleStop }
    end
end
