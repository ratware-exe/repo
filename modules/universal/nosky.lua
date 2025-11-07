-- modules/universal/nosky.lua
do
    return function(ui)
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
        local maid     = Maid.new()

        local removed = {}

        local function start()
            local L = services.Lighting
            for _, inst in ipairs(L:GetChildren()) do
                if inst:IsA("Sky") or inst:IsA("Clouds") then
                    table.insert(removed, inst)
                    pcall(function() inst.Parent = nil end)
                end
            end
            maid:GiveTask(function()
                for _, s in ipairs(removed) do
                    pcall(function() s.Parent = services.Lighting end)
                end
                removed = {}
            end)
        end

        local function stop()
            maid:DoCleaning()
        end

        local group = ui.Tabs.Visual:AddRightGroupbox("World", "cloud-off")
        group:AddToggle("NoSkyEnable", { Text="No Sky", Default=false })

        ui.Toggles.NoSkyEnable:OnChanged(function(v)
            if v then start() else stop() end
        end)

        return { Name = "NoSky", Stop = stop }
    end
end
