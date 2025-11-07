-- modules/universal/flight.lua
do
    return function(ui)
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
        local maid     = Maid.new()

        local state = {
            enabled = false,
            speed = 60,
            body_vel = nil,
            body_gyro = nil,
            base_part = nil,
        }

        local function get_hrp_or_seat()
            local player = services.Players.LocalPlayer
            local char = player and player.Character
            if not char then return nil end
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.SeatPart then
                return humanoid.SeatPart
            end
            return char:FindFirstChild("HumanoidRootPart")
        end

        local function cleanup_flight()
            if state.body_vel then pcall(function() state.body_vel:Destroy() end) end
            if state.body_gyro then pcall(function() state.body_gyro:Destroy() end) end
            state.body_vel, state.body_gyro, state.base_part = nil, nil, nil
        end

        local function start()
            if state.enabled then return end
            state.enabled = true

            state.base_part = get_hrp_or_seat()
            if not state.base_part then state.enabled = false; return end

            state.body_vel = Instance.new("BodyVelocity")
            state.body_vel.MaxForce = Vector3.new(1e6, 1e6, 1e6)
            state.body_vel.Velocity = Vector3.zero
            state.body_vel.Parent = state.base_part

            state.body_gyro = Instance.new("BodyGyro")
            state.body_gyro.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
            state.body_gyro.P = 2e4
            state.body_gyro.CFrame = workspace.CurrentCamera and workspace.CurrentCamera.CFrame or CFrame.new()
            state.body_gyro.Parent = state.base_part

            local rs = services.RunService.RenderStepped:Connect(function(dt)
                if not state.enabled then return end
                local camera = workspace.CurrentCamera
                local hrp = get_hrp_or_seat()
                if not (camera and hrp and state.body_vel and state.body_gyro) then return end

                -- WASD movement relative to camera
                local move_dir = Vector3.zero
                local uis = services.UserInputService
                if uis:IsKeyDown(Enum.KeyCode.W) then move_dir += camera.CFrame.LookVector end
                if uis:IsKeyDown(Enum.KeyCode.S) then move_dir -= camera.CFrame.LookVector end
                if uis:IsKeyDown(Enum.KeyCode.A) then move_dir -= camera.CFrame.RightVector end
                if uis:IsKeyDown(Enum.KeyCode.D) then move_dir += camera.CFrame.RightVector end
                if uis:IsKeyDown(Enum.KeyCode.Space) then move_dir += Vector3.new(0,1,0) end
                if uis:IsKeyDown(Enum.KeyCode.LeftControl) or uis:IsKeyDown(Enum.KeyCode.LeftShift) then
                    move_dir -= Vector3.new(0,1,0)
                end

                if move_dir.Magnitude > 0 then move_dir = move_dir.Unit end
                state.body_vel.Velocity = move_dir * state.speed
                state.body_gyro.CFrame = CFrame.new(hrp.Position, hrp.Position + camera.CFrame.LookVector)
            end)
            maid:GiveTask(rs)
            maid:GiveTask(function() state.enabled = false; cleanup_flight() end)
        end

        local function stop()
            if not state.enabled then return end
            state.enabled = false
            maid:DoCleaning()
            cleanup_flight()
        end

        -- UI (FlightToggle / FlightKeybind / FlightSlider)
        local group = ui.Tabs.Main:AddLeftGroupbox("Movement", "rocket")
        group:AddToggle("FlightToggle", {
            Text = "Flight",
            Tooltip = "Free-flight using camera direction.",
            Default = false,
        }):AddKeyPicker("FlightKeybind", { Text = "Flight Toggle", Default = "F", Mode = "Toggle", NoUI = true })

        group:AddSlider("FlightSlider", {
            Text = "Fly Speed",
            Default = 60, Min = 10, Max = 250, Rounding = 0,
            Tooltip = "Movement speed while flying.",
        })

        ui.Toggles.FlightToggle:OnChanged(function(v)
            if v then start() else stop() end
        end)
        if ui.Options.FlightSlider and ui.Options.FlightSlider.OnChanged then
            ui.Options.FlightSlider:OnChanged(function(val)
                local n = tonumber(val)
                if n then state.speed = n end
            end)
        end
        if ui.Options.FlightSlider and ui.Options.FlightSlider.Value ~= nil then
            state.speed = tonumber(ui.Options.FlightSlider.Value) or state.speed
        end

        return { Name = "Flight", Stop = stop }
    end
end
