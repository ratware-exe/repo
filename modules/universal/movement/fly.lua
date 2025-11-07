-- modules/universal/movement/fly.lua
do
    return function(UI)
        -- [1] LOAD DEPENDENCIES
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv = (getgenv and getgenv()) or _G
        local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        -- [2] MODULE STATE
        local ModuleName = "Fly"
        local Variables = {
            Maids = { [ModuleName] = Maid.new() },
            RunFlag = false, -- Corresponds to FlightEnabled
            FlightSpeed = 250,
            FlightBodyVelocity = nil,
            FlightBodyGyro = nil,
            FlightBasePart = nil,
            FlightSeatPart = nil,
            FlightNoCollideOriginalByPart = nil,
        }

        -- [3] CORE LOGIC
        
        -- === Movers ===
        local function FlightEnsureBodyVelocity()
            local flightBodyVelocityInstance = Variables.FlightBodyVelocity
            if not flightBodyVelocityInstance or flightBodyVelocityInstance.Parent == nil then
                flightBodyVelocityInstance = Instance.new("BodyVelocity")
                flightBodyVelocityInstance.Name = "WFYBVehicleFlyBodyVelocity"
                flightBodyVelocityInstance.MaxForce = Vector3.new(1e9, 1e9, 1e9)
                flightBodyVelocityInstance.Velocity = Vector3.new(0, 0, 0)
                Variables.FlightBodyVelocity = flightBodyVelocityInstance
            end
            return flightBodyVelocityInstance
        end

        local function FlightEnsureBodyGyro()
            local flightBodyGyroInstance = Variables.FlightBodyGyro
            if not flightBodyGyroInstance or flightBodyGyroInstance.Parent == nil then
                flightBodyGyroInstance = Instance.new("BodyGyro")
                flightBodyGyroInstance.Name = "WFYBVehicleFlyBodyGyro"
                flightBodyGyroInstance.D = 600
                flightBodyGyroInstance.P = 9000
                flightBodyGyroInstance.MaxTorque = Vector3.new(0, 1e9, 0) -- yaw only
                Variables.FlightBodyGyro = flightBodyGyroInstance
            end
            return flightBodyGyroInstance
        end

        -- === Target Part (seat if seated, else HRP) ===
        local function FlightGetBasePart()
            local LocalPlayer = RbxService.Players.LocalPlayer
            if not LocalPlayer then return nil end
            
            local flightCharacterInstance = LocalPlayer.Character
            if not flightCharacterInstance then
                Variables.FlightSeatPart = nil
                Variables.FlightBasePart = nil
                return nil
            end
            local flightHumanoidInstance = flightCharacterInstance:FindFirstChildOfClass("Humanoid")
            local flightSeatPartInstance = flightHumanoidInstance and flightHumanoidInstance.SeatPart
            if flightSeatPartInstance and flightSeatPartInstance:IsA("BasePart") then
                Variables.FlightSeatPart = flightSeatPartInstance
                Variables.FlightBasePart = flightSeatPartInstance
                return flightSeatPartInstance
            end
            local flightHumanoidRootPartInstance = flightCharacterInstance:FindFirstChild("HumanoidRootPart")
            Variables.FlightSeatPart = nil
            Variables.FlightBasePart = flightHumanoidRootPartInstance
            return flightHumanoidRootPartInstance
        end

        -- === Input → direction (world-space, camera-relative) ===
        local function FlightComputeDirectionVector()
            local flightCameraInstance = RbxService.Workspace.CurrentCamera
            if not flightCameraInstance then return Vector3.new(0, 0, 0) end
            local flightDirectionVector = Vector3.new(0, 0, 0)
            if RbxService.UserInputService:IsKeyDown(Enum.KeyCode.W) then
                flightDirectionVector += flightCameraInstance.CFrame.LookVector
            end
            if RbxService.UserInputService:IsKeyDown(Enum.KeyCode.S) then
                flightDirectionVector -= flightCameraInstance.CFrame.LookVector
            end
            if RbxService.UserInputService:IsKeyDown(Enum.KeyCode.A) then
                flightDirectionVector -= flightCameraInstance.CFrame.RightVector
            end
            if RbxService.UserInputService:IsKeyDown(Enum.KeyCode.D) then
                flightDirectionVector += flightCameraInstance.CFrame.RightVector
            end
            if RbxService.UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                flightDirectionVector += Vector3.new(0, 1, 0)
            end
            if flightDirectionVector.Magnitude > 0 then
                return flightDirectionVector.Unit
            end
            return Vector3.new(0, 0, 0)
        end

        -- === Seat yaw: face INTO the screen (180° from camera-facing-you) ===
        local function FlightApplyYawWhenSeated(flightBasePart)
            if not Variables.FlightSeatPart then
                if Variables.FlightBodyGyro then Variables.FlightBodyGyro.Parent = nil end
                return
            end
            local flightCameraInstance = RbxService.Workspace.CurrentCamera
            if not flightCameraInstance then return end

            local flatLookVector = Vector3.new(flightCameraInstance.CFrame.LookVector.X, 0, flightCameraInstance.CFrame.LookVector.Z)
            if flatLookVector.Magnitude < 1e-6 then flatLookVector = Vector3.new(0, 0, -1) end
            local flightYawRadians = math.atan2(flatLookVector.X, flatLookVector.Z) + math.pi
            local flightFacingCFrame = CFrame.new(flightBasePart.Position) * CFrame.Angles(0, flightYawRadians, 0)

            local flightBodyGyroInstance = FlightEnsureBodyGyro()
            if flightBodyGyroInstance.Parent ~= flightBasePart then
                local setParentSucceeded = pcall(function() flightBodyGyroInstance.Parent = flightBasePart end)
                if not setParentSucceeded then
                    pcall(function() flightBodyGyroInstance:Destroy() end)
                    Variables.FlightBodyGyro = nil
                    flightBodyGyroInstance = FlightEnsureBodyGyro()
                    pcall(function() flightBodyGyroInstance.Parent = flightBasePart end)
                end
            end
            flightBodyGyroInstance.CFrame = flightFacingCFrame
        end

        -- === No-collision only while BodyVelocity is moving ===
        local function FlightGetAffectedParts(flightBasePart)
            local LocalPlayer = RbxService.Players.LocalPlayer
            if not LocalPlayer then return {} end
            
            local flightAffectedPartsList = {}
            if Variables.FlightSeatPart then
                local getConnectedSucceeded, flightConnectedPartsList = pcall(function()
                    return Variables.FlightSeatPart:GetConnectedParts(true)
                end)
                if getConnectedSucceeded and flightConnectedPartsList then
                    for flightIndex, flightPartInstance in ipairs(flightConnectedPartsList) do
                        if flightPartInstance:IsA("BasePart") then
                            table.insert(flightAffectedPartsList, flightPartInstance)
                        end
                    end
                end
            else
                local flightCharacterInstance = LocalPlayer.Character
                if flightCharacterInstance then
                    for flightIndex, flightDescendantInstance in ipairs(flightCharacterInstance:GetDescendants()) do
                        if flightDescendantInstance:IsA("BasePart") then
                            table.insert(flightAffectedPartsList, flightDescendantInstance)
                        end
                    end
                end
            end
            return flightAffectedPartsList
        end

        local function FlightUpdateNoCollision(flightBasePart, flightIsMoving)
            Variables.FlightNoCollideOriginalByPart = Variables.FlightNoCollideOriginalByPart or {}
            local flightOriginalCollideStateByPart = Variables.FlightNoCollideOriginalByPart

            if not flightIsMoving or not flightBasePart then
                for flightPartInstance, flightOriginalState in pairs(flightOriginalCollideStateByPart) do
                    if flightPartInstance and flightPartInstance.Parent and flightOriginalState ~= nil then
                        pcall(function() flightPartInstance.CanCollide = flightOriginalState end)
                    end
                    flightOriginalCollideStateByPart[flightPartInstance] = nil
                end
                return
            end

            local flightSeenPartMap = {}
            local flightAffectedPartsList = FlightGetAffectedParts(flightBasePart)
            for flightIndex, flightPartInstance in ipairs(flightAffectedPartsList) do
                flightSeenPartMap[flightPartInstance] = true
                if flightOriginalCollideStateByPart[flightPartInstance] == nil then
                    flightOriginalCollideStateByPart[flightPartInstance] = flightPartInstance.CanCollide
                end
                if flightPartInstance.CanCollide then
                    pcall(function() flightPartInstance.CanCollide = false end)
                end
            end

            for flightPartInstance, flightOriginalState in pairs(flightOriginalCollideStateByPart) do
                if not flightSeenPartMap[flightPartInstance] then
                    if flightPartInstance and flightPartInstance.Parent and flightOriginalState ~= nil then
                        pcall(function() flightPartInstance.CanCollide = flightOriginalState end)
                    end
                    flightOriginalCollideStateByPart[flightPartInstance] = nil
                end
            end
        end

        local function FlightCleanup()
            FlightUpdateNoCollision(nil, false)
            if Variables.FlightBodyVelocity then Variables.FlightBodyVelocity.Parent = nil end
            if Variables.FlightBodyGyro then Variables.FlightBodyGyro.Parent = nil end
        end

        -- Function to enable the module
        local function Start()
            if Variables.RunFlag then return end
            Variables.RunFlag = true
            
            local LocalPlayer = RbxService.Players.LocalPlayer
            if not LocalPlayer then
                Variables.RunFlag = false
                return
            end

            local maid = Variables.Maids[ModuleName]

            local flightRenderConn = RbxService.RunService.RenderStepped:Connect(function()
                if not Variables.RunFlag then return end -- Use RunFlag

                local flightBasePart = FlightGetBasePart()
                local flightSpeedPerSecond = tonumber(Variables.FlightSpeed) or 0

                if not flightBasePart or flightSpeedPerSecond <= 0 then
                    FlightCleanup()
                    return
                end

                local flightDirectionVector = FlightComputeDirectionVector()
                local flightBodyVelocityInstance = FlightEnsureBodyVelocity()
                if flightBodyVelocityInstance.Parent ~= flightBasePart then
                    local setParentSucceeded = pcall(function() flightBodyVelocityInstance.Parent = flightBasePart end)
                    if not setParentSucceeded then
                        pcall(function() flightBodyVelocityInstance:Destroy() end)
                        Variables.FlightBodyVelocity = nil
                        flightBodyVelocityInstance = FlightEnsureBodyVelocity()
                        pcall(function() flightBodyVelocityInstance.Parent = flightBasePart end)
                    end
                end

                flightBodyVelocityInstance.Velocity = flightDirectionVector * flightSpeedPerSecond
                FlightApplyYawWhenSeated(flightBasePart)
                FlightUpdateNoCollision(flightBasePart, flightDirectionVector.Magnitude > 0)
            end)
            maid:GiveTask(flightRenderConn)

            local charAddedConn = LocalPlayer.CharacterAdded:Connect(function()
                FlightCleanup()
            end)
            maid:GiveTask(charAddedConn)

            local charRemovingConn = LocalPlayer.CharacterRemoving:Connect(function()
                FlightCleanup()
            end)
            maid:GiveTask(charRemovingConn)

            maid:GiveTask(function() Variables.RunFlag = false end)
        end

        -- Function to disable the module
        local function Stop()
            if not Variables.RunFlag then return end
            Variables.RunFlag = false
            
            Variables.Maids[ModuleName]:DoCleaning()
            FlightCleanup() -- Run one last time
        end

        -- [4] UI CREATION
        local MovementGroupBox = UI.Tabs.Main:AddLeftGroupbox("Movement", "person-standing")
        MovementGroupBox:AddDivider()
		local FlightToggle = MovementGroupBox:AddToggle("FlightToggle", {
			Text = "Fly",
			Tooltip = "Makes you fly.", 
			Default = false, 
		})
		UI.Toggles.FlightToggle:AddKeyPicker("FlightKeybind", {
			Text = "Fly",
			SyncToggleState = true,
			Mode = "Toggle", 
		})
		MovementGroupBox:AddSlider("FlightSlider", {
			Text = "Flight Speed",
			Default = 250,
			Min = 0,
			Max = 500,
			Rounding = 1,
			Compact = true,
			Tooltip = "Changes flight speed.", 
		})
        
        -- [5] UI WIRING (CORRECTED)
        UI.Toggles.FlightToggle:OnChanged(function(enabledState)
            if enabledState then Start() else Stop() end
        end)
        
        UI.Options.FlightSlider:OnChanged(function(newFlightSpeed)
            Variables.FlightSpeed = tonumber(newFlightSpeed)
        end)
        
        -- Seed default values from UI
        Variables.FlightSpeed = tonumber(UI.Options.FlightSlider.Value) or 250
        
        -- Start if already enabled
        if UI.Toggles.FlightToggle.Value then
            Start()
        end

        -- [6] RETURN MODULE
        return { Name = ModuleName, Stop = Stop }
    end
end
