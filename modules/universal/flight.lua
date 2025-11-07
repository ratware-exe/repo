-- modules/universal/flight.lua
do
    return function(UI)
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local Variables = {
            Maids = { Flight = Maid.new() },

            -- verbatim flight state
            FlightEnabled = false,
            FlightSpeed   = nil,
            FlightBodyVelocity = nil,
            FlightBodyGyro     = nil,
            FlightBasePart     = nil,
            FlightSeatPart     = nil,
            FlightNoCollideOriginalByPart = nil,
        }

        -- === Movers (verbatim) ===
        local function FlightEnsureBodyVelocity()
            local inst = Variables.FlightBodyVelocity
            if not inst or inst.Parent == nil then
                inst = Instance.new("BodyVelocity")
                inst.Name = "WFYBVehicleFlyBodyVelocity"
                inst.MaxForce = Vector3.new(1e9, 1e9, 1e9)
                inst.Velocity = Vector3.new(0, 0, 0)
                Variables.FlightBodyVelocity = inst
            end
            return inst
        end

        local function FlightEnsureBodyGyro()
            local inst = Variables.FlightBodyGyro
            if not inst or inst.Parent == nil then
                inst = Instance.new("BodyGyro")
                inst.Name = "WFYBVehicleFlyBodyGyro"
                inst.D = 600
                inst.P = 9000
                inst.MaxTorque = Vector3.new(0, 1e9, 0) -- yaw only
                Variables.FlightBodyGyro = inst
            end
            return inst
        end

        -- === Target part (verbatim: seat if seated, else HRP) ===
        local function FlightGetBasePart()
            local lp = services.Players.LocalPlayer
            local ch = lp and lp.Character
            if not ch then
                Variables.FlightSeatPart = nil
                Variables.FlightBasePart = nil
                return nil
            end
            local hum = ch:FindFirstChildOfClass("Humanoid")
            local seat = hum and hum.SeatPart
            if seat and seat:IsA("BasePart") then
                Variables.FlightSeatPart = seat
                Variables.FlightBasePart = seat
                return seat
            end
            local hrp = ch:FindFirstChild("HumanoidRootPart")
            Variables.FlightSeatPart = nil
            Variables.FlightBasePart = hrp
            return hrp
        end

        -- === Input → direction (world space, camera-relative) ===
        local function FlightComputeDirectionVector()
            local camera = services.Workspace.CurrentCamera
            local v = Vector3.zero
            if services.UserInputService:IsKeyDown(Enum.KeyCode.W) then v += Vector3.new(0, 0, -1) end
            if services.UserInputService:IsKeyDown(Enum.KeyCode.S) then v += Vector3.new(0, 0,  1) end
            if services.UserInputService:IsKeyDown(Enum.KeyCode.A) then v += Vector3.new(-1, 0, 0) end
            if services.UserInputService:IsKeyDown(Enum.KeyCode.D) then v += Vector3.new( 1, 0, 0) end
            if services.UserInputService:IsKeyDown(Enum.KeyCode.Space) then v += Vector3.new(0,  1, 0) end
            if services.UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or services.UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
                v += Vector3.new(0, -1, 0)
            end
            if camera and v.Magnitude > 0 then
                v = camera.CFrame:VectorToWorldSpace(v).Unit
            end
            return v
        end

        -- === No-collision while flying (verbatim idea) ===
        local function FlightUpdateNoCollision()
            local ch = services.Players.LocalPlayer and services.Players.LocalPlayer.Character
            if not ch then return end
            Variables.FlightNoCollideOriginalByPart = Variables.FlightNoCollideOriginalByPart or setmetatable({}, { __mode = "k" })
            for _, p in ipairs(ch:GetDescendants()) do
                if p:IsA("BasePart") then
                    local orig = Variables.FlightNoCollideOriginalByPart[p]
                    if orig == nil then
                        Variables.FlightNoCollideOriginalByPart[p] = p.CanCollide
                    end
                    p.CanCollide = false
                end
            end
        end
        local function FlightRestoreCollision()
            if not Variables.FlightNoCollideOriginalByPart then return end
            for part, orig in pairs(Variables.FlightNoCollideOriginalByPart) do
                if part and part.Parent then
                    pcall(function() part.CanCollide = orig end)
                end
                Variables.FlightNoCollideOriginalByPart[part] = nil
            end
        end

        -- === Start/Stop (verbatim structure) ===
        local function start()
            if Variables.FlightEnabled then return end
            Variables.FlightEnabled = true

            local base = FlightGetBasePart()
            if not base then
                Variables.FlightEnabled = false
                return
            end

            local bv = FlightEnsureBodyVelocity()
            local bg = FlightEnsureBodyGyro()
            bv.Parent = base
            bg.Parent = base

            local rs = services.RunService.RenderStepped:Connect(function()
                if not Variables.FlightEnabled then return end
                local dir = FlightComputeDirectionVector()
                local speed = (UI.Options and UI.Options.FlightSlider and tonumber(UI.Options.FlightSlider.Value)) or tonumber(Variables.FlightSpeed) or 0
                bv.Velocity = dir * speed

                -- if seated, yaw follow camera
                local seat = Variables.FlightSeatPart
                if seat then
                    local cam = services.Workspace.CurrentCamera
                    if cam then
                        bg.CFrame = CFrame.new(base.Position, base.Position + cam.CFrame.LookVector)
                    end
                end

                FlightUpdateNoCollision()
            end)
            Variables.Maids.Flight:GiveTask(rs)
            Variables.Maids.Flight:GiveTask(function()
                Variables.FlightEnabled = false
                FlightRestoreCollision()
                if Variables.FlightBodyVelocity then Variables.FlightBodyVelocity.Parent = nil end
                if Variables.FlightBodyGyro then Variables.FlightBodyGyro.Parent = nil end
            end)
        end

        local function stop()
            if not Variables.FlightEnabled then return end
            Variables.FlightEnabled = false
            Variables.Maids.Flight:DoCleaning()
            FlightRestoreCollision()
            if Variables.FlightBodyVelocity then Variables.FlightBodyVelocity.Parent = nil end
            if Variables.FlightBodyGyro then Variables.FlightBodyGyro.Parent = nil end
        end

        -- === UI (verbatim IDs) ===
        do
            local tab = UI.Tabs.Main or UI.Tabs.Misc or UI.Tabs.Visual
            local group = tab:AddLeftGroupbox("Movement", "person-standing") -- same group as speedhack (UIRegistry dedupes)

            group:AddToggle("FlightToggle", {
                Text = "Fly",
                Tooltip = "Makes you fly.",
                DisabledTooltip = "Feature Disabled!",
                Default = false,
                Disabled = false,
                Visible = true,
                Risky = false,
            })
            UI.Toggles.FlightToggle:AddKeyPicker("FlightKeybind", {
                Text = "Fly",
                SyncToggleState = true,
                Mode = "Toggle",
                NoUI = false,
            })
            group:AddSlider("FlightSlider", {
                Text = "Flight Speed",
                Default = 250,
                Min = 0,
                Max = 500,
                Rounding = 1,
                Compact = true,
                Tooltip = "Changes flight speed.",
                DisabledTooltip = "Feature Disabled!",
                Disabled = false,
                Visible = true,
            })
        end

        -- OnChanged (verbatim)
        if UI.Toggles and UI.Toggles.FlightToggle then
            UI.Toggles.FlightToggle:OnChanged(function(value)
                Variables.FlightEnabled = value and true or false
                if Variables.FlightEnabled then start() else stop() end
            end)
            Variables.FlightEnabled = UI.Toggles.FlightToggle.Value and true or false
            if Variables.FlightEnabled then start() end
        end
        if UI.Options and UI.Options.FlightSlider and UI.Options.FlightSlider.OnChanged then
            UI.Options.FlightSlider:OnChanged(function(newSpeed)
                Variables.FlightSpeed = tonumber(newSpeed)
            end)
        end
        Variables.FlightSpeed = tonumber(UI.Options and UI.Options.FlightSlider and UI.Options.FlightSlider.Value) or Variables.FlightSpeed

        local function Stop()
            stop()
        end

        return { Name = "Flight", Stop = Stop }
    end
end
