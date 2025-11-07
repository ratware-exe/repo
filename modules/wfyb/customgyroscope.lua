-- modules/universal/gyroscope.lua
do
    return function(UI)
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local Variables = {
            Maids = { Gyro = Maid.new() },
            GyroEnabled = false,
            GyroCharacter = nil,
            GyroRoot = nil,
            GyroSeat = nil,
            GyroVehicle = nil,
            GyroBaseRot = nil,
            GyroXAxis = 0,
            GyroYAxis = 0,
            GyroZAxis = 0,
        }

        local function GyroCharacterAdded(c)
            local lp = services.Players.LocalPlayer
            Variables.GyroCharacter = c or (lp and lp.Character) or (lp and lp.CharacterAdded:Wait())
            Variables.GyroRoot = Variables.GyroCharacter and Variables.GyroCharacter:WaitForChild("HumanoidRootPart")
        end

        local lp = services.Players.LocalPlayer
        GyroCharacterAdded(lp and lp.Character)
        if lp then
            Variables.Maids.Gyro:GiveTask(lp.CharacterAdded:Connect(GyroCharacterAdded))
        end

        local function getSeat()
            local hum = Variables.GyroCharacter and Variables.GyroCharacter:FindFirstChildOfClass("Humanoid")
            return hum and hum.SeatPart
        end

        local function refreshSeatVehicle()
            Variables.GyroSeat = getSeat()
            Variables.GyroVehicle = Variables.GyroSeat and Variables.GyroSeat:FindFirstAncestorOfClass("Model")
            local cf = Variables.GyroVehicle and Variables.GyroVehicle:GetPivot()
            Variables.GyroBaseRot = cf or CFrame.new()
        end

        local hb = services.RunService.Heartbeat:Connect(function()
            if not Variables.GyroEnabled then return end
            refreshSeatVehicle()
            local veh = Variables.GyroVehicle
            if veh then
                local base = veh:GetPivot().Position
                local rx = math.rad(Variables.GyroXAxis or 0)
                local ry = math.rad(Variables.GyroYAxis or 0)
                local rz = math.rad(Variables.GyroZAxis or 0)
                veh:PivotTo(CFrame.new(base) * CFrame.Angles(rx, ry, rz))
            end
        end)
        Variables.Maids.Gyro:GiveTask(hb)

        -- UI (verbatim IDs)
        do
            local tab = UI.Tabs.Main or UI.Tabs.Misc
            local group = tab:AddRightGroupbox("Modifiers", "package-plus")
            group:AddToggle("GyroToggle", {
                Text = "Custom Gyro",
                Tooltip = "Turns the custom gyroscope [ON]/[OFF].",
                DisabledTooltip = "Feature Disabled!",
                Default = false,
                Disabled = false,
                Visible = true,
                Risky = false,
            })
            UI.Toggles.GyroToggle:AddKeyPicker("GyroKeybind", {
                Text = "Gyroscope",
                SyncToggleState = true,
                Mode = "Toggle",
                NoUI = false,
            })
            group:AddSlider("XAxisAngle", {
                Text = "X-Axis Angle",
                Default = 180, Min = 0, Max = 360, Rounding = 1, Compact = true,
                Tooltip = "Changes the gyro [X] axis angle.",
                DisabledTooltip = "Feature Disabled!", Disabled = false, Visible = true,
            })
            group:AddSlider("YAxisAngle", {
                Text = "Y-Axis Angle",
                Default = 180, Min = 0, Max = 360, Rounding = 1, Compact = true,
                Tooltip = "Changes the gyro [Y] axis angle.",
                DisabledTooltip = "Feature Disabled!", Disabled = false, Visible = true,
            })
            group:AddSlider("ZAxisAngle", {
                Text = "Z-Axis Angle",
                Default = 180, Min = 0, Max = 360, Rounding = 1, Compact = true,
                Tooltip = "Changes the gyro [Z] axis angle.",
                DisabledTooltip = "Feature Disabled!", Disabled = false, Visible = true,
            })
        end

        -- OnChanged (verbatim mapping)
        local function bindOnChanged(opt, cb)
            if not opt then return end
            if typeof(opt) == "table" then
                if opt.OnChanged then opt:OnChanged(cb)
                elseif opt.Onchanged then opt:Onchanged(cb) end
            end
        end

        if UI.Toggles and UI.Toggles.GyroToggle then
            bindOnChanged(UI.Toggles.GyroToggle, function(v)
                Variables.GyroEnabled = v and true or false
                if Variables.GyroEnabled then refreshSeatVehicle() end
            end)
            Variables.GyroEnabled = UI.Toggles.GyroToggle.Value and true or false
        end
        if UI.Options then
            if UI.Options.XAxisAngle then
                Variables.GyroXAxis = tonumber(UI.Options.XAxisAngle.Value) or 0
                bindOnChanged(UI.Options.XAxisAngle, function(v) Variables.GyroXAxis = tonumber(v) or Variables.GyroXAxis end)
            end
            if UI.Options.YAxisAngle then
                Variables.GyroYAxis = tonumber(UI.Options.YAxisAngle.Value) or 0
                bindOnChanged(UI.Options.YAxisAngle, function(v) Variables.GyroYAxis = tonumber(v) or Variables.GyroYAxis end)
            end
            if UI.Options.ZAxisAngle then
                Variables.GyroZAxis = tonumber(UI.Options.ZAxisAngle.Value) or 0
                bindOnChanged(UI.Options.ZAxisAngle, function(v) Variables.GyroZAxis = tonumber(v) or Variables.GyroZAxis end)
            end
        end

        local function Stop()
            Variables.GyroEnabled = false
            Variables.Maids.Gyro:DoCleaning()
        end

        return { Name = "Gyroscope", Stop = Stop }
    end
end
