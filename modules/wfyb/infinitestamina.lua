-- modules/universal/infinitestamina.lua
do
    return function(ui)
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local maid = Maid.new()
        local running = false

        local candidate_names = { "Stamina", "stamina", "Oxygen", "oxygen", "Breath", "breath", "Energy", "energy" }

        local function set_value_if_number(obj, n)
            if typeof(obj) == "Instance" then
                if obj:IsA("NumberValue") or obj:IsA("IntValue") then
                    pcall(function() obj.Value = n end)
                end
            end
        end

        local function pump()
            local player = services.Players.LocalPlayer
            local character = player and player.Character
            local container = character or player
            if not container then return end

            for _, name in ipairs(candidate_names) do
                local inst = character and character:FindFirstChild(name, true)
                if inst then set_value_if_number(inst, 999999) end
            end

            -- Attributes variant
            if character then
                for _, name in ipairs(candidate_names) do
                    if character:GetAttribute(name) ~= nil then
                        pcall(function() character:SetAttribute(name, 999999) end)
                    end
                end
            end
        end

        local function start()
            if running then return end
            running = true
            local hb = services.RunService.Heartbeat:Connect(function()
                if running then pump() end
            end)
            maid:GiveTask(hb)
            maid:GiveTask(function() running = false end)
        end

        local function stop()
            running = false
            maid:DoCleaning()
        end

        -- UI (Bypass)
        local bypass_tab = ui.Tabs.Main or ui.Tabs["Main"]
        local group = bypass_tab:AddLeftGroupbox("Bypass", "shield-off")
        group:AddToggle("InfiniteStaminaToggle", {
            Text = "Infinite Stamina",
            Tooltip = "Stay underwater indefinitely.",
            Default = false,
        })
        ui.Toggles.InfiniteStaminaToggle:OnChanged(function(enabled)
            if enabled then start() else stop() end
        end)

        return { Name = "InfiniteStamina", Stop = stop }
    end
end
