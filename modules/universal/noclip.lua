-- modules/universal/noclip.lua
do
    return function(UI)
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local variables = {
            maids = { noclip = Maid.new() },
            noclip = false,
        }

        -- step loop: HRP no-collide (verbatim intent)
        local stepped = services.RunService.Stepped:Connect(function()
            if not variables.noclip then return end
            local lp = services.Players.LocalPlayer
            local ch = lp and lp.Character
            local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
            if hrp then
                pcall(function() hrp.CanCollide = false end)
            end
        end)
        variables.maids.noclip:GiveTask(stepped)

        -- UI (verbatim IDs)
        do
            local tab = UI.Tabs.Main or UI.Tabs.Misc
            local group = tab:AddLeftGroupbox("Movement", "person-standing")
            group:AddToggle("NoclipToggle", {
                Text = "No Clip",
                Tooltip = "Makes you go through objects.",
                DisabledTooltip = "Feature Disabled!",
                Default = false,
                Disabled = false,
                Visible = true,
                Risky = false,
            })
            UI.Toggles.NoclipToggle:AddKeyPicker("NoclipKeybind", {
                Text = "No Clip",
                SyncToggleState = true,
                Mode = "Toggle",
                NoUI = false,
            })
        end

        -- OnChanged (verbatim)
        if UI.Toggles and UI.Toggles.NoclipToggle then
            UI.Toggles.NoclipToggle:OnChanged(function(enabled)
                variables.noclip = enabled and true or false
                if not enabled then
                    local lp = services.Players.LocalPlayer
                    local ch = lp and lp.Character
                    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
                    if hrp then hrp.CanCollide = true end
                end
            end)
        end

        local function Stop()
            variables.noclip = false
            variables.maids.noclip:DoCleaning()
            local lp = services.Players.LocalPlayer
            local ch = lp and lp.Character
            local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
            if hrp then pcall(function() hrp.CanCollide = true end) end
        end

        return { Name = "Noclip", Stop = Stop }
    end
end
