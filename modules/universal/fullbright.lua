-- modules/universal/fullbright.lua
do
    return function(ui)
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local maid = Maid.new()
        local running = false
        local intensity = 3

        local function step()
            if not running then return end
            pcall(function()
                services.Lighting.Brightness = tonumber(intensity) or intensity
                services.Lighting.ClockTime = 12
            end)
        end

        local function start()
            if running then return end
            running = true
            local rs = services.RunService.RenderStepped:Connect(step)
            maid:GiveTask(rs)
            maid:GiveTask(function() running = false end)
        end
        local function stop() running = false; maid:DoCleaning() end

        -- UI (Visual)
        local tab = ui.Tabs.Visual or ui.Tabs.Main
        local group = tab:AddRightGroupbox("World", "sun")
        group:AddToggle("FullbrightToggle", { Text = "Fullbright", Default = false })
        group:AddSlider("FullbrightSlider", { Text="Intensity", Default = 3, Min=0, Max=8, Rounding=1, Compact=true })

        if ui.Options.FullbrightSlider then
            ui.Options.FullbrightSlider:OnChanged(function(v) intensity = tonumber(v) or intensity end)
            intensity = tonumber(ui.Options.FullbrightSlider.Value) or intensity
        end
        ui.Toggles.FullbrightToggle:OnChanged(function(v) if v then start() else stop() end end)

        return { Name = "Fullbright", Stop = stop }
    end
end
