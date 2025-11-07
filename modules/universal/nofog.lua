-- modules/universal/nofog.lua
do
    return function(ui)
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
        local maid     = Maid.new()

        local saved = { fogstart=nil, fogend=nil, atmosphere_densities = {} }

        local function start()
            local L = services.Lighting
            if saved.fogstart == nil then saved.fogstart = L.FogStart end
            if saved.fogend == nil then saved.fogend = L.FogEnd end
            pcall(function()
                L.FogStart = 1e6
                L.FogEnd   = 1e6
            end)
            for _, a in ipairs(L:GetChildren()) do
                if a:IsA("Atmosphere") then
                    saved.atmosphere_densities[a] = a.Density
                    pcall(function() a.Density = 0 end)
                end
            end
            maid:GiveTask(function()
                local L2 = services.Lighting
                if saved.fogstart ~= nil then pcall(function() L2.FogStart = saved.fogstart end) end
                if saved.fogend ~= nil then pcall(function() L2.FogEnd = saved.fogend end) end
                for a, d in pairs(saved.atmosphere_densities) do
                    if a then pcall(function() a.Density = d end) end
                end
                saved.atmosphere_densities = {}
            end)
        end

        local function stop()
            maid:DoCleaning()
        end

        local group = ui.Tabs.Visual:AddRightGroupbox("World", "wind")
        group:AddToggle("NoFogEnable", { Text="No Fog", Default=false })

        ui.Toggles.NoFogEnable:OnChanged(function(v)
            if v then start() else stop() end
        end)

        return { Name = "NoFog", Stop = stop }
    end
end
