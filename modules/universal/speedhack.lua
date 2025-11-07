-- modules/universal/speedhack.lua
do
    return function(UI)
        -- deps
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        -- local aliases (match original names for verbatim logic)
        local Variables = {
            Maids = { Speedhack = Maid.new() },

            -- Speedhack constants/state (verbatim)
            WaitRandomMin     = 1,
            WaitRandomMax     = 3,
            DefaultDt         = 0.016,
            TweenDtMultiplier = 1.5,
            TweenMin          = 0.005,
            EasingStyle       = Enum.EasingStyle.Linear,
            EasingDirection   = Enum.EasingDirection.Out,

            Enabled      = false,   -- toggled state
            DefaultSpeed = nil,     -- read from slider
            currentTween = nil,     -- active tween
            cancelTween  = nil,
        }

        -- verbatim helper
        local function secureCall(fn, ...)
            return pcall(fn, ...)
        end

        -- cancel tween verbatim
        local function cancelTween()
            if Variables.currentTween then
                Variables.currentTween:Cancel()
                Variables.currentTween = nil
            end
        end
        Variables.cancelTween = cancelTween

        -- movement input verbatim (camera-relative WASD)
        local function getMovementInput()
            local ok, result = secureCall(function()
                local v = Vector3.zero
                if services.UserInputService:IsKeyDown(Enum.KeyCode.W) then v += Vector3.new(0, 0, -1) end
                if services.UserInputService:IsKeyDown(Enum.KeyCode.S) then v += Vector3.new(0, 0,  1) end
                if services.UserInputService:IsKeyDown(Enum.KeyCode.A) then v += Vector3.new(-1, 0, 0) end
                if services.UserInputService:IsKeyDown(Enum.KeyCode.D) then v += Vector3.new( 1, 0, 0) end

                local camera = services.Workspace.CurrentCamera
                if camera and v.Magnitude > 0 then
                    v = camera.CFrame:VectorToWorldSpace(v)
                    v = Vector3.new(v.X, 0, v.Z).Unit
                end
                return v
            end)
            return (ok and typeof(result) == "Vector3") and result or Vector3.zero
        end

        -- initial random wait (verbatim)
        task.wait(math.random(Variables.WaitRandomMin, Variables.WaitRandomMax))

        -- main loop verbatim (RenderStepped)
        local steppedConn = services.RunService.RenderStepped:Connect(function(dt)
            secureCall(function()
                if not Variables.Enabled then
                    cancelTween()
                    return
                end

                local localPlayer = services.Players.LocalPlayer
                local character   = localPlayer and localPlayer.Character
                local hrp         = character and character:FindFirstChild("HumanoidRootPart")
                if not hrp then
                    cancelTween()
                    return
                end

                local moveDir = getMovementInput()
                if moveDir.Magnitude <= 0 then
                    cancelTween()
                    return
                end

                local speed =
                    (UI.Options and UI.Options.SpeedhackSlider and tonumber(UI.Options.SpeedhackSlider.Value))
                    or tonumber(Variables.DefaultSpeed)
                    or 0

                if speed <= 0 then
                    cancelTween()
                    return
                end

                local _dt  = dt or Variables.DefaultDt
                local step = speed * _dt
                local delta = moveDir * step

                cancelTween()
                Variables.currentTween = services.TweenService:Create(
                    hrp,
                    TweenInfo.new(
                        math.max(Variables.TweenMin, _dt * Variables.TweenDtMultiplier),
                        Variables.EasingStyle,
                        Variables.EasingDirection
                    ),
                    { CFrame = hrp.CFrame + delta }
                )
                Variables.currentTween:Play()
            end)
        end)
        Variables.Maids.Speedhack:GiveTask(steppedConn)

        -- clean tween on character changes (verbatim)
        local lp = services.Players.LocalPlayer
        if lp then
            Variables.Maids.Speedhack:GiveTask(lp.CharacterRemoving:Connect(function()
                secureCall(cancelTween)
            end))
            Variables.Maids.Speedhack:GiveTask(lp.CharacterAdded:Connect(function()
                secureCall(function()
                    if not Variables.Enabled then
                        cancelTween()
                    end
                end)
            end))
        end

        -- === UI (keeps exact IDs/labels/limits from prompt.lua) ===
        do
            local tab = UI.Tabs.Main or UI.Tabs.Misc or UI.Tabs.Visual or UI.Tabs.Debug or UI.Tabs["UI Settings"]
            local group = tab:AddLeftGroupbox("Movement", "person-standing")

            group:AddToggle("SpeedhackToggle", {
                Text = "Speedhack",
                Tooltip = "Makes your extremely fast.",
                DisabledTooltip = "Feature Disabled!",
                Default = false,
                Disabled = false,
                Visible = true,
                Risky = false,
            })
            UI.Toggles.SpeedhackToggle:AddKeyPicker("SpeedhackKeybind", {
                Text = "Speedhack",
                SyncToggleState = true,
                Mode = "Toggle",
                NoUI = false,
            })
            group:AddSlider("SpeedhackSlider", {
                Text = "Speed",
                Default = 250,
                Min = 0,
                Max = 500,
                Rounding = 1,
                Compact = true,
                Tooltip = "Changes speedhack speed.",
                DisabledTooltip = "Feature Disabled!",
                Disabled = false,
                Visible = true,
            })

            -- OnChanged (verbatim)
            if UI.Toggles and UI.Toggles.SpeedhackToggle then
                UI.Toggles.SpeedhackToggle:OnChanged(function(value)
                    Variables.Enabled = value and true or false
                    if not Variables.Enabled then
                        if Variables.cancelTween then Variables.cancelTween() end
                    end
                end)
                Variables.Enabled = UI.Toggles.SpeedhackToggle.Value and true or false
            end

            if UI.Options and UI.Options.SpeedhackSlider and UI.Options.SpeedhackSlider.OnChanged then
                UI.Options.SpeedhackSlider:OnChanged(function(v)
                    local n = tonumber(v)
                    if n then
                        Variables.DefaultSpeed = n
                        if Variables.cancelTween then
                            Variables.cancelTween()
                        end
                    end
                end)
                if UI.Options.SpeedhackSlider.Value ~= nil then
                    Variables.DefaultSpeed = tonumber(UI.Options.SpeedhackSlider.Value) or Variables.DefaultSpeed
                end
            end
        end

        -- stop
        local function Stop()
            Variables.Enabled = false
            Variables.Maids.Speedhack:DoCleaning()
            cancelTween()
        end

        return { Name = "Speedhack", Stop = Stop }
    end
end
