-- modules/universal/gyroscope.lua
do
    return function(ui)
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local maid = Maid.new()
        local enabled = false
        local xdeg, ydeg, zdeg = 0, 0, 0
        local bodygyro, lastpart

        local function current_base()
            local player = services.Players.LocalPlayer
            local character = player and player.Character
            if not character then return nil end
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.Sit and humanoid.SeatPart then
                return humanoid.SeatPart
            end
            return character:FindFirstChild("HumanoidRootPart")
        end

        local function ensure_gyro()
            local base = current_base()
            if not base then return end
            if base ~= lastpart then
                if bodygyro then bodygyro:Destroy() bodygyro = nil end
                lastpart = base
            end
            if not bodygyro then
                bodygyro = Instance.new("BodyGyro")
                bodygyro.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
                bodygyro.P = 25_000
                bodygyro.Parent = base
                maid:GiveTask(bodygyro)
            end
        end

        local function update_orientation()
            if not enabled then return end
            ensure_gyro()
            if bodygyro and lastpart then
                local cf = CFrame.new(lastpart.Position) * CFrame.Angles(math.rad(xdeg), math.rad(ydeg), math.rad(zdeg))
                bodygyro.CFrame = cf
            end
        end

        local function start()
            if enabled then return end
            enabled = true
            ensure_gyro()
            local rs = services.RunService.RenderStepped:Connect(update_orientation)
            maid:GiveTask(rs)
            maid:GiveTask(function() enabled = false end)
        end

        local function stop()
            enabled = false
            maid:DoCleaning()
            if bodygyro then bodygyro:Destroy() bodygyro = nil end
        end

        -- UI (Modifiers)
        local tab = ui.Tabs.Main or ui.Tabs.Misc
        local group = tab:AddRightGroupbox("Modifiers", "package-plus")

        group:AddToggle("GyroToggle", {
            Text = "Custom Gyro",
            Tooltip = "Turns the custom gyroscope [ON]/[OFF].",
            Default = false,
        })
        group:AddSlider("XAxisAngle", { Text = "X Angle", Default = 0, Min = -180, Max = 180, Rounding = 1, Compact = true })
        group:AddSlider("YAxisAngle", { Text = "Y Angle", Default = 0, Min = -180, Max = 180, Rounding = 1, Compact = true })
        group:AddSlider("ZAxisAngle", { Text = "Z Angle", Default = 0, Min = -180, Max = 180, Rounding = 1, Compact = true })

        if ui.Options.XAxisAngle then
            ui.Options.XAxisAngle:OnChanged(function(v) xdeg = tonumber(v) or xdeg; update_orientation() end)
            xdeg = tonumber(ui.Options.XAxisAngle.Value) or 0
        end
        if ui.Options.YAxisAngle then
            ui.Options.YAxisAngle:OnChanged(function(v) ydeg = tonumber(v) or ydeg; update_orientation() end)
            ydeg = tonumber(ui.Options.YAxisAngle.Value) or 0
        end
        if ui.Options.ZAxisAngle then
            ui.Options.ZAxisAngle:OnChanged(function(v) zdeg = tonumber(v) or zdeg; update_orientation() end)
            zdeg = tonumber(ui.Options.ZAxisAngle.Value) or 0
        end

        ui.Toggles.GyroToggle:OnChanged(function(v) if v then start() else stop() end end)

        return { Name = "Gyroscope", Stop = stop }
    end
end
