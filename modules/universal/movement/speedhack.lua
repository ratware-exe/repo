-- "modules/universal/movement/speedhack.lua",
do
    return function(UI)
        -- [1] LOAD DEPENDENCIES
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv = (getgenv and getgenv()) or _G
        local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        -- [2] MODULE STATE
        local ModuleName = "Speedhack"
        local Variables = {
            Maids = { [ModuleName] = Maid.new() },
            RunFlag = false, -- Corresponds to 'Enabled' in old script
            
            -- Speedhack Vars (from original)
            DefaultDt = 0.016,
            TweenDtMultiplier = 1.5,
            TweenMin = 0.005,
            EasingStyle = Enum.EasingStyle.Linear,
            EasingDirection = Enum.EasingDirection.Out,
            DefaultSpeed = 250,
            currentTween = nil,
        }

        -- [3] CORE LOGIC
        local function secureCall(fn, ...)
            return pcall(fn, ...)
        end

        local function cancelTween()
            if Variables.currentTween then
                Variables.currentTween:Cancel()
                Variables.currentTween = nil
            end
        end

        local function getMovementInput()
            local ok, result = secureCall(function()
                local v = Vector3.zero
                if RbxService.UserInputService:IsKeyDown(Enum.KeyCode.W) then v += Vector3.new(0, 0, -1) end
                if RbxService.UserInputService:IsKeyDown(Enum.KeyCode.S) then v += Vector3.new(0, 0, 1) end
                if RbxService.UserInputService:IsKeyDown(Enum.KeyCode.A) then v += Vector3.new(-1, 0, 0) end
                if RbxService.UserInputService:IsKeyDown(Enum.KeyCode.D) then v += Vector3.new(1, 0, 0) end

                local Camera = RbxService.Workspace.CurrentCamera
                if Camera and v.Magnitude > 0 then
                    v = Camera.CFrame:VectorToWorldSpace(v)
                    v = Vector3.new(v.X, 0, v.Z).Unit
                end
                return v
            end)
            return (ok and typeof(result) == "Vector3") and result or Vector3.zero
        end

        local function onRenderStepped(dt)
            if not Variables.RunFlag then return end -- This logic is now correct

            secureCall(function()
                local LocalPlayer = RbxService.Players.LocalPlayer
                if not LocalPlayer then return end

                local char = LocalPlayer.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                if not hrp then
                    cancelTween()
                    return
                end

                local moveDir = getMovementInput()
                if moveDir.Magnitude <= 0 then
                    cancelTween()
                    return
                end

                local speed = tonumber(Variables.DefaultSpeed) or 0
                if speed <= 0 then
                    cancelTween()
                    return
                end

                local _dt = dt or Variables.DefaultDt
                local step = speed * _dt
                local delta = moveDir * step

                cancelTween()
                Variables.currentTween = RbxService.TweenService:Create(
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
        end

        local function Start()
            if Variables.RunFlag then return end
            Variables.RunFlag = true
            
            local LocalPlayer = RbxService.Players.LocalPlayer
            if not LocalPlayer then
                Variables.RunFlag = false
                return
            end

            -- Give connections to the Maid
            local maid = Variables.Maids[ModuleName]
            maid:GiveTask(RbxService.RunService.RenderStepped:Connect(onRenderStepped))

            maid:GiveTask(LocalPlayer.CharacterRemoving:Connect(function()
                secureCall(cancelTween)
            end))

            maid:GiveTask(LocalPlayer.CharacterAdded:Connect(function()
                secureCall(function()
                    if not Variables.RunFlag then
                        cancelTween()
                    end
                end)
            end))

            maid:GiveTask(function()
                Variables.RunFlag = false
                secureCall(cancelTween)
            end)
        end

        local function Stop()
            if not Variables.RunFlag then return end
            Variables.RunFlag = false -- This is handled by the maid task, but set explicitly
            
            -- DoCleaning will set RunFlag to false, disconnect RenderStepped, and call cancelTween
            Variables.Maids[ModuleName]:DoCleaning()
        end

        -- [4] UI CREATION
        local MovementGroupBox = UI.Tabs.Main:AddLeftGroupbox("Movement", "person-standing")
        local SpeedhackToggle = MovementGroupBox:AddToggle("SpeedhackToggle", {
			Text = "Speedhack",
			Tooltip = "Makes your extremely fast.", 
			Default = false, 
		})
		UI.Toggles.SpeedhackToggle:AddKeyPicker("SpeedhackKeybind", {
			Text = "Speedhack",
			SyncToggleState = true,
			Mode = "Toggle", 
		})
		MovementGroupBox:AddSlider("SpeedhackSlider", {
			Text = "Speed",
			Default = 250,
			Min = 0,
			Max = 500,
			Rounding = 1,
			Compact = true,
			Tooltip = "Changes speedhack speed.", 
		})
		MovementGroupBox:AddDivider()
        
        -- [5] UI WIRING (CORRECTED)
        UI.Toggles.SpeedhackToggle:OnChanged(function(enabledState)
            -- This is now correct. Start/Stop handle the RunFlag.
            if enabledState then 
                Start() 
            else 
                Stop() 
            end
        end)

        UI.Options.SpeedhackSlider:OnChanged(function(v)
            local n = tonumber(v)
            if n then
                Variables.DefaultSpeed = n
                if Variables.RunFlag then
                    cancelTween()
                end
            end
        end)
        
        -- Seed default values from UI
        Variables.DefaultSpeed = tonumber(UI.Options.SpeedhackSlider.Value) or 250
        
        -- Start if already enabled
        if UI.Toggles.SpeedhackToggle.Value then
            Start()
        end

        -- [6] RETURN MODULE
        return { Name = ModuleName, Stop = Stop }
    end
end
