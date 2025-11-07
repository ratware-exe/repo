-- modules/universal/noclip.lua
do
    return function(ui)
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local maid = Maid.new()
        local running = false
        local original = setmetatable({}, { __mode = "k" })

        local function set_noclip(state)
            local player = services.Players.LocalPlayer
            local character = player and player.Character
            if not character then return end
            for _, inst in ipairs(character:GetDescendants()) do
                if inst:IsA("BasePart") and inst.CanCollide ~= not state then
                    if original[inst] == nil then original[inst] = inst.CanCollide end
                    inst.CanCollide = not state
                end
            end
        end

        local function restore()
            for part, can in pairs(original) do
                if part then pcall(function() part.CanCollide = can end) end
                original[part] = nil
            end
        end

        local function start()
            if running then return end
            running = true
            local stepped = services.RunService.Stepped:Connect(function()
                if not running then return end
                set_noclip(true)
            end)
            maid:GiveTask(stepped)
            maid:GiveTask(function() running = false end)
        end

        local function stop()
            if not running then return end
            running = false
            maid:DoCleaning()
            restore()
        end

        -- UI
        local movement_tab = ui.Tabs.Main or ui.Tabs.Misc
        local group = movement_tab:AddLeftGroupbox("Movement", "person-standing")
        group:AddToggle("NoclipToggle", {
            Text = "No Clip",
            Tooltip = "Makes you go through objects.",
            Default = false,
        })
        ui.Toggles.NoclipToggle:OnChanged(function(enabled)
            if enabled then start() else stop() end
        end)

        return { Name = "NoClip", Stop = stop }
    end
end
