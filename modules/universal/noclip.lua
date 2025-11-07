-- modules/universal/noclip.lua
do
    return function(ui)
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
        local maid     = Maid.new()

        local state = { enabled = false }

        local function set_collide(character, can_collide)
            if not character then return end
            for _, part in ipairs(character:GetDescendants()) do
                if part:IsA("BasePart") then
                    pcall(function() part.CanCollide = can_collide end)
                end
            end
        end

        local function get_character()
            local player = services.Players.LocalPlayer
            return player and player.Character
        end

        local function start()
            if state.enabled then return end
            state.enabled = true
            local stepped = services.RunService.Stepped:Connect(function()
                if not state.enabled then return end
                set_collide(get_character(), false)
            end)
            maid:GiveTask(stepped)
            maid:GiveTask(function() state.enabled = false end)
        end

        local function stop()
            if not state.enabled then return end
            state.enabled = false
            maid:DoCleaning()
            set_collide(get_character(), true)
        end

        local group = ui.Tabs.Main:AddLeftGroupbox("Movement", "scan-line")
        group:AddToggle("NoclipToggle", {
            Text = "No Clip",
            Tooltip = "Disable collisions on your character.",
            Default = false,
        }):AddKeyPicker("NoclipKeybind", { Text = "No Clip Toggle", Default = "N", Mode = "Toggle", NoUI = true })

        ui.Toggles.NoclipToggle:OnChanged(function(v)
            if v then start() else stop() end
        end)

        return { Name = "NoClip", Stop = stop }
    end
end
