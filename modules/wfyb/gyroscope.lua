-- "modules/wfyb/gyroscope.lua",
do
    return function(UI)
        -- [1] LOAD DEPENDENCIES
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv = (getgenv and getgenv()) or _G
        local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        -- [2] MODULE STATE
        local ModuleName = "Gyroscope"
        local Variables = {
            Maids = { [ModuleName] = Maid.new() },
            RunFlag = false, -- Corresponds to GyroEnabled
            GyroCharacter = nil,
            GyroRoot = nil,
            GyroSeat = nil,
            GyroVehicle = nil,
            GyroBaseRot = nil,
            GyroXAxis = 0,
            GyroYAxis = 0,
            GyroZAxis = 0,
        }

        -- [3] CORE LOGIC (Verbatim from prompt.lua)
        local function GyroCharacterAdded(c)
            local LocalPlayer = RbxService.Players.LocalPlayer
            if not LocalPlayer then return end
            Variables.GyroCharacter = c or LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
            Variables.GyroRoot = Variables.GyroCharacter:WaitForChild("HumanoidRootPart")
        end

        local function getSeat()
            local SeatedHumanoid = Variables.GyroCharacter and Variables.GyroCharacter:FindFirstChildOfClass("Humanoid")
            return SeatedHumanoid and SeatedHumanoid.SeatPart or nil
        end

        local function getTopModel(inst)
            if not inst then return nil end
            local GyroModel = inst:FindFirstAncestorOfClass("Model")
            if not GyroModel then return nil end
            while GyroModel.Parent and GyroModel.Parent:IsA("Model") do
                GyroModel = GyroModel.Parent
            end
            return GyroModel
        end

        local function refreshSeatVehicle()
            local VehicleSeat = getSeat()
            if VehicleSeat ~= Variables.GyroSeat then
                Variables.GyroSeat = VehicleSeat
                Variables.GyroVehicle = getTopModel(VehicleSeat)
                if Variables.GyroVehicle then
                    local pv = Variables.GyroVehicle:GetPivot()
                    Variables.GyroBaseRot = pv.Rotation
                else
                    Variables.GyroBaseRot = nil
                end
            end
        end

        local function quellSpin()
            local s = Variables.GyroSeat
            if s and s:IsA("BasePart") then
                pcall(function() s.RotVelocity = Vector3.zero end) -- pcall is from original
            end
        end

        local function applyVehicleRotation()
            local GyroRotationModel = Variables.GyroVehicle
            if not GyroRotationModel then return end
            -- pcall is NOT in original logic here, so it is removed.
            local pv = GyroRotationModel:GetPivot()
            local pos = pv.Position
            local base = Variables.GyroBaseRot or pv.Rotation
            local rx = math.rad(Variables.GyroXAxis or 0)
            local ry = math.rad(Variables.GyroYAxis or 0)
            local rz = math.rad(Variables.GyroZAxis or 0)
            local targetRot = base * CFrame.Angles(rx, ry, rz)
            GyroRotationModel:PivotTo(CFrame.new(pos) * targetRot)
            quellSpin()
        end
        
        local function onStepped()
            if not Variables.RunFlag then return end -- Flag check is verbatim
            local char = Variables.GyroCharacter
            local root = Variables.GyroRoot
            if not (char and root) then return end
            local SeatedHumanoid = char:FindFirstChildOfClass("Humanoid")
            if not (SeatedHumanoid and SeatedHumanoid.Sit) then return end
            refreshSeatVehicle()
            if not Variables.GyroVehicle then return end
            applyVehicleRotation()
        end

        -- [4] UI CREATION
        local BuildModifiersGroupBox = UI.Tabs.Main:AddRightGroupbox("Modifiers", "package-plus")
        local GyroToggle = BuildModifiersGroupBox:AddToggle("GyroToggle", {
			Text = "Custom Gyro",
			Tooltip = "Turns the custom gyroscope [ON]/[OFF].", 
			Default = false, 
		})
		UI.Toggles.GyroToggle:AddKeyPicker("GyroKeybind", {
			Text = "Gyroscope",
			SyncToggleState = true,
			Mode = "Toggle", 
		})
		BuildModifiersGroupBox:AddSlider("XAxisAngle", {
			Text = "X-Axis Angle",
			Default = 180,
			Min = 0,
			Max = 360,
			Rounding = 1,
			Compact = true,
			Tooltip = "Changes the gyro [X] axis angle.", 
		})
		BuildModifiersGroupBox:AddSlider("YAxisAngle", {
			Text = "Y-Axis Angle",
			Default = 180,
			Min = 0,
			Max = 360,
			Rounding = 1,
			Compact = true,
			Tooltip = "Changes the gyro [Y] axis angle.", 
		})
		BuildModifiersGroupBox:AddSlider("ZAxisAngle", {
			Text = "Z-Axis Angle",
			Default = 180,
			Min = 0,
			Max = 360,
			Rounding = 1,
			Compact = true,
			Tooltip = "Changes the gyro [Z] axis angle.", 
		})

        -- [5] UI WIRING & GLOBAL LOGIC (Verbatim)
        
        -- Initial setup (verbatim)
        local LocalPlayer = RbxService.Players.LocalPlayer
        if LocalPlayer then
             GyroCharacterAdded(LocalPlayer.Character)
             Variables.Maids[ModuleName]:GiveTask(LocalPlayer.CharacterAdded:Connect(GyroCharacterAdded))
        end
        
        -- Global Stepped connection (verbatim)
        Variables.Maids[ModuleName]:GiveTask(RbxService.RunService.Stepped:Connect(onStepped))

        -- UI Wiring (verbatim)
	    local function bindOnChanged(opt, cb)
	        if not opt then return end
	        if typeof(opt) == "table" then
	            if opt.OnChanged then opt:OnChanged(cb)
	            elseif opt.Onchanged then opt:Onchanged(cb) end
	        end
	    end
	    
	    bindOnChanged(UI.Toggles.GyroToggle, function(v)
	        Variables.RunFlag = v and true or false
	        if Variables.RunFlag then refreshSeatVehicle() end
	    end)
	    Variables.RunFlag = UI.Toggles.GyroToggle.Value and true or false -- Seed flag
	
	    if UI.Options.XAxisAngle then
	        Variables.GyroXAxis = tonumber(UI.Options.XAxisAngle.Value) or 0
	        bindOnChanged(UI.Options.XAxisAngle, function(v) Variables.GyroXAxis = tonumber(v) or Variables.GyroXAxis end) -- Verbatim
	    end
	    if UI.Options.YAxisAngle then
	        Variables.GyroYAxis = tonumber(UI.Options.YAxisAngle.Value) or 0
	        bindOnChanged(UI.Options.YAxisAngle, function(v) Variables.GyroYAxis = tonumber(v) or Variables.GyroYAxis end) -- Verbatim
	    end
	    if UI.Options.ZAxisAngle then
	        Variables.GyroZAxis = tonumber(UI.Options.ZAxisAngle.Value) or 0
	        bindOnChanged(UI.Options.ZAxisAngle, function(v) Variables.GyroZAxis = tonumber(v) or Variables.GyroZAxis end) -- Verbatim
	    end
	    
        -- [6] RETURN MODULE
        local function Stop()
            Variables.Maids[ModuleName]:DoCleaning()
        end
        return { Name = ModuleName, Stop = Stop }
    end
end
