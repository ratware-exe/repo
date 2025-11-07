-- modules/universal/speedhack.lua
do
    return function(ui)
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
        local maid     = Maid.new()

        local state = {
            running = false,
            default_speed = 16,
            target_speed = 32,
        }

        local function get_local_humanoid()
            local player = services.Players.LocalPlayer
            local character = player and player.Character
            if not character then return nil end
            return character:FindFirstChildOfClass("Humanoid")
        end

        local function start()
            if state.running then return end
            state.running = true

            local humanoid = get_local_humanoid()
            if humanoid then
                state.default_speed = humanoid.WalkSpeed
                pcall(function() humanoid.WalkSpeed = state.target_speed end)
            end

            local stepped = services.RunService.Stepped:Connect(function()
                if not state.running then return end
                local current = get_local_humanoid()
                if current then
                    pcall(function() current.WalkSpeed = state.target_speed end)
                end
            end)
            maid:GiveTask(stepped)
            maid:GiveTask(function() state.running = false end)
        end

        local function stop()
            if not state.running then return end
            state.running = false
            maid:DoCleaning()
            local humanoid = get_local_humanoid()
            if humanoid then
                pcall(function() humanoid.WalkSpeed = state.default_speed end)
            end
        end

        -- UI (matches prompt.lua ids)  SpeedhackToggle / SpeedhackKeybind / SpeedhackSlider
        local group = ui.Tabs.Main:AddLeftGroupbox("Movement", "zap")
        group:AddToggle("SpeedhackToggle", {
            Text = "Speedhack",
            Tooltip = "Increase WalkSpeed locally.",
            Default = false,
        }):AddKeyPicker("SpeedhackKeybind", { Text = "Speedhack Toggle", Default = "LeftShift", Mode = "Toggle", NoUI = true })

        group:AddSlider("SpeedhackSlider", {
            Text = "Speed",
            Default = 32, Min = 8, Max = 200, Rounding = 0,
            Tooltip = "WalkSpeed while speedhack is enabled.",
        })

        ui.Toggles.SpeedhackToggle:OnChanged(function(enabled)
            if enabled then start() else stop() end
        end)

        if ui.Options.SpeedhackSlider and ui.Options.SpeedhackSlider.OnChanged then
            ui.Options.SpeedhackSlider:OnChanged(function(v)
                local n = tonumber(v)
                if n then
                    state.target_speed = n
                end
            end)
        end
        if ui.Options.SpeedhackSlider and ui.Options.SpeedhackSlider.Value ~= nil then
            state.target_speed = tonumber(ui.Options.SpeedhackSlider.Value) or state.target_speed
        end

        return { Name = "Speedhack", Stop = stop }
    end
end
