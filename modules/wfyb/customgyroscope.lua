-- modules/wfyb/customgyroscope.lua
do
    return function(ui)
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
        local maid     = Maid.new()

        local state = {
            enabled = false,
            x = 0, y = 0, z = 0,
            align = nil,
            base = nil,
        }

        local function get_base()
            local p = services.Players.LocalPlayer
            local c = p and p.Character
            if not c then return nil end
            local hum = c:FindFirstChildOfClass("Humanoid")
            if hum and hum.SeatPart then return hum.SeatPart end
            return c:FindFirstChild("HumanoidRootPart")
        end

        local function apply_angles()
            local base = state.base or get_base()
            if not (base and state.align) then return end
            local cf = CFrame.Angles(math.rad(state.x), math.rad(state.y), math.rad(state.z))
            state.align.CFrame = base.CFrame.Rotation * cf
        end

        local function start()
            if state.enabled then return end
            state.enabled = true
            state.base = get_base()
            if not state.base then state.enabled = false; return end

            local a0 = Instance.new("Attachment"); a0.Name="GyroAttachment"; a0.Parent = state.base
            local al = Instance.new("AlignOrientation")
            al.MaxAngularVelocity = math.huge
            al.Responsiveness = 200
            al.Mode = Enum.OrientationAlignmentMode.OneAttachment
            al.Attachment0 = a0
            al.Parent = state.base
            state.align = al

            apply_angles()
            local hb = services.RunService.Heartbeat:Connect(function()
                if not state.enabled then return end
                apply_angles()
            end)
            maid:GiveTask(hb)
            maid:GiveTask(function()
                state.enabled = false
                if state.align then pcall(function() state.align:Destroy() end) end
                state.align = nil
            end)
        end

        local function stop()
            if not state.enabled then return end
            state.enabled = false
            maid:DoCleaning()
        end

        -- UI: Gyro controls (same ids as prompt.lua)
        local group = ui.Tabs.Main:AddRightGroupbox("Gyroscope", "rotate-3d")
        group:AddToggle("GyroToggle", {
            Text = "Enable Gyro",
            Tooltip = "Force orientation using X/Y/Z angles.",
            Default = false,
        }):AddKeyPicker("GyroKeybind", { Text="Gyro Toggle", Default="J", Mode="Toggle", NoUI=true })

        group:AddSlider("XAxisAngle", { Text="X Axis", Default=0, Min=-180, Max=180, Rounding=0 })
        group:AddSlider("YAxisAngle", { Text="Y Axis", Default=0, Min=-180, Max=180, Rounding=0 })
        group:AddSlider("ZAxisAngle", { Text="Z Axis", Default=0, Min=-180, Max=180, Rounding=0 })

        ui.Toggles.GyroToggle:OnChanged(function(v)
            if v then start() else stop() end
        end)

        for id, key in pairs({ XAxisAngle="x", YAxisAngle="y", ZAxisAngle="z" }) do
            local opt = ui.Options[id]
            if opt and opt.OnChanged then
                opt:OnChanged(function(v)
                    local n = tonumber(v); if n then state[key] = n; apply_angles() end
                end)
            end
            if opt and opt.Value ~= nil then
                local n = tonumber(opt.Value); if n then state[key] = n end
            end
        end

        return { Name = "Gyroscope", Stop = stop }
    end
end
