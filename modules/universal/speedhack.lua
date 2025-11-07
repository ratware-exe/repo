-- modules/universal/speedhack.lua
do
    return function(ui)
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local maid       = Maid.new()
        local running    = false
        local speedvalue = 250

        local function get_character()
            local player = services.Players.LocalPlayer
            local character = player and player.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            return player, character, humanoid, root
        end

        local function set_horizontal_velocity(root, humanoid, speed)
            if not (root and humanoid) then return end
            local move = humanoid.MoveDirection
            if move.Magnitude > 0 then
                local current = root.AssemblyLinearVelocity
                -- preserve vertical velocity; replace horizontal plane
                local horizontal = Vector3.new(move.X, 0, move.Z).Unit * speed
                if horizontal.Magnitude ~= horizontal.Magnitude then
                    -- NaN guard if Unit on zero vector
                    horizontal = Vector3.zero
                end
                root.AssemblyLinearVelocity = Vector3.new(horizontal.X, current.Y, horizontal.Z)
            end
        end

        local function start()
            if running then return end
            running = true

            local rs_conn = services.RunService.RenderStepped:Connect(function()
                if not running then return end
                local _, _, humanoid, root = get_character()
                if not humanoid or not root then return end
                set_horizontal_velocity(root, humanoid, speedvalue)
            end)
            maid:GiveTask(rs_conn)

            maid:GiveTask(function() running = false end)
        end

        local function stop()
            if not running then return end
            running = false
            maid:DoCleaning()
            -- try to clear horizontal boost
            local _, _, humanoid, root = get_character()
            if root and humanoid then
                local v = root.AssemblyLinearVelocity
                root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
            end
        end

        -- UI
        local movement_tab = ui.Tabs.Main or ui.Tabs.Misc or ui.Tabs["Misc"] or ui.Tabs.Visual
        local group = movement_tab:AddLeftGroupbox("Movement", "person-standing")

        group:AddToggle("SpeedhackToggle", {
            Text = "Speedhack",
            Tooltip = "Makes you extremely fast.",
            Default = false,
        })
        ui.Toggles.SpeedhackToggle:AddKeyPicker("SpeedhackKeybind", {
            Text = "Speedhack",
            SyncToggleState = true,
            Mode = "Toggle",
            NoUI = false,
        })
        group:AddSlider("SpeedhackSlider", {
            Text = "Speed",
            Default = 250, Min = 0, Max = 500, Rounding = 1, Compact = true,
            Tooltip = "Changes speedhack speed.",
        })

        if ui.Options.SpeedhackSlider then
            ui.Options.SpeedhackSlider:OnChanged(function(v)
                local n = tonumber(v)
                if n then speedvalue = n end
            end)
            speedvalue = tonumber(ui.Options.SpeedhackSlider.Value) or speedvalue
        end

        ui.Toggles.SpeedhackToggle:OnChanged(function(enabled)
            if enabled then start() else stop() end
        end)

        return { Name = "Speedhack", Stop = stop }
    end
end
