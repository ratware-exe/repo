-- modules/universal/flight.lua
do
    return function(ui)
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local maid = Maid.new()
        local running = false
        local speedvalue = 250

        local bodyvel, bodygyro, lastbase

        local function get_camera()
            return services.Workspace.CurrentCamera
        end

        local function get_basepart()
            local player = services.Players.LocalPlayer
            local character = player and player.Character
            if not character then return nil end
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.SeatPart then
                return humanoid.SeatPart
            end
            return character:FindFirstChild("HumanoidRootPart")
        end

        local function ensure_forces()
            local base = get_basepart()
            if not base then return end
            if base ~= lastbase then
                if bodyvel then bodyvel:Destroy() bodyvel = nil end
                if bodygyro then bodygyro:Destroy() bodygyro = nil end
                lastbase = base
            end
            if not bodyvel then
                bodyvel = Instance.new("BodyVelocity")
                bodyvel.MaxForce = Vector3.new(1e9, 1e9, 1e9)
                bodyvel.P = 25_000
                bodyvel.Velocity = Vector3.zero
                bodyvel.Parent = base
                maid:GiveTask(bodyvel)
            end
            if not bodygyro then
                bodygyro = Instance.new("BodyGyro")
                bodygyro.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
                bodygyro.P = 25_000
                bodygyro.CFrame = base.CFrame
                bodygyro.Parent = base
                maid:GiveTask(bodygyro)
            end
        end

        local function input_direction()
            local uis = services.UserInputService
            local cam = get_camera()
            if not cam then return Vector3.zero end

            local look = cam.CFrame:VectorToWorldSpace(Vector3.new(0, 0, -1))
            local right = cam.CFrame:VectorToWorldSpace(Vector3.new(1, 0, 0))
            local dir = Vector3.zero

            if uis:IsKeyDown(Enum.KeyCode.W) then dir += Vector3.new(look.X, 0, look.Z) end
            if uis:IsKeyDown(Enum.KeyCode.S) then dir -= Vector3.new(look.X, 0, look.Z) end
            if uis:IsKeyDown(Enum.KeyCode.A) then dir -= Vector3.new(right.X, 0, right.Z) end
            if uis:IsKeyDown(Enum.KeyCode.D) then dir += Vector3.new(right.X, 0, right.Z) end
            if uis:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.new(0, 1, 0) end
            if uis:IsKeyDown(Enum.KeyCode.LeftControl) or uis:IsKeyDown(Enum.KeyCode.LeftShift) then
                dir -= Vector3.new(0, 1, 0)
            end

            if dir.Magnitude > 0 then dir = dir.Unit end
            return dir
        end

        local function start()
            if running then return end
            running = true

            ensure_forces()

            local rs = services.RunService.RenderStepped:Connect(function()
                if not running then return end
                ensure_forces()
                local base = lastbase
                if not base then return end
                local dir = input_direction()
                local cam = get_camera()
                if bodyvel then bodyvel.Velocity = dir * speedvalue end
                if bodygyro and cam then
                    bodygyro.CFrame = CFrame.new(base.Position, base.Position + cam.CFrame.LookVector)
                end
            end)
            maid:GiveTask(rs)
            maid:GiveTask(function() running = false end)
        end

        local function stop()
            if not running then return end
            running = false
            maid:DoCleaning()
        end

        -- UI
        local movement_tab = ui.Tabs.Main or ui.Tabs.Misc or ui.Tabs["Misc"]
        local group = movement_tab:AddLeftGroupbox("Movement", "person-standing")

        group:AddToggle("FlightToggle", {
            Text = "Fly",
            Tooltip = "Makes you fly.",
            Default = false,
        })
        ui.Toggles.FlightToggle:AddKeyPicker("FlightKeybind", {
            Text = "Fly",
            SyncToggleState = true,
            Mode = "Toggle",
            NoUI = false,
        })
        group:AddSlider("FlightSlider", {
            Text = "Flight Speed",
            Default = 250, Min = 0, Max = 500, Rounding = 1, Compact = true,
            Tooltip = "Changes flight speed.",
        })

        if ui.Options.FlightSlider then
            ui.Options.FlightSlider:OnChanged(function(v)
                local n = tonumber(v)
                if n then speedvalue = n end
            end)
            speedvalue = tonumber(ui.Options.FlightSlider.Value) or speedvalue
        end

        ui.Toggles.FlightToggle:OnChanged(function(enabled)
            if enabled then start() else stop() end
        end)

        return { Name = "Flight", Stop = stop }
    end
end
