-- modules/universal/nofog.lua
do
    return function(ui)
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local maid = Maid.new()
        local backup = nil

        local function enable()
            if not backup then
                local a = services.Lighting:FindFirstChildOfClass("Atmosphere")
                backup = {
                    fogend = services.Lighting.FogEnd,
                    fogstart = services.Lighting.FogStart,
                    a = a and { Density=a.Density, Offset=a.Offset, Haze=a.Haze, Glare=a.Glare } or nil
                }
            end
            services.Lighting.FogStart = 0
            services.Lighting.FogEnd   = 1e6
            local atm = services.Lighting:FindFirstChildOfClass("Atmosphere")
            if atm then
                atm.Density = 0
                atm.Haze = 0
                atm.Glare = 0
                atm.Offset = 0
            end
        end

        local function disable()
            if not backup then return end
            services.Lighting.FogStart = backup.fogstart or services.Lighting.FogStart
            services.Lighting.FogEnd   = backup.fogend or services.Lighting.FogEnd
            local atm = services.Lighting:FindFirstChildOfClass("Atmosphere")
            if atm and backup.a then
                atm.Density = backup.a.Density
                atm.Haze = backup.a.Haze
                atm.Glare = backup.a.Glare
                atm.Offset = backup.a.Offset
            end
            backup = nil
        end

        -- UI
        local tab = ui.Tabs.Visual or ui.Tabs.Main
        local group = tab:AddRightGroupbox("World", "sun")
        group:AddToggle("NoFogToggle", { Text = "No Fog", Default = false })

        ui.Toggles.NoFogToggle:OnChanged(function(state)
            if state then enable() else disable() end
        end)
        if ui.Toggles.NoFogToggle.Value then enable() end

        return { Name = "NoFog", Stop = function() disable(); maid:DoCleaning() end }
    end
end
