-- modules/universal/fullbright.lua
do
    return function(ui)
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
        local maid     = Maid.new()

        local saved = { outdoor = nil, ambient = nil, exposure = nil }

        local function start()
            local L = services.Lighting
            if saved.outdoor == nil then saved.outdoor = L.OutdoorAmbient end
            if saved.ambient == nil then saved.ambient = L.Ambient end
            if saved.exposure == nil then saved.exposure = L.ExposureCompensation end
            pcall(function()
                L.OutdoorAmbient = Color3.new(1,1,1)
                L.Ambient = Color3.new(1,1,1)
                L.ExposureCompensation = 0
            end)
            maid:GiveTask(function()
                pcall(function()
                    if saved.outdoor then L.OutdoorAmbient = saved.outdoor end
                    if saved.ambient then L.Ambient = saved.ambient end
                    if saved.exposure ~= nil then L.ExposureCompensation = saved.exposure end
                end)
            end)
        end

        local function stop()
            maid:DoCleaning()
        end

        local group = ui.Tabs.Visual:AddRightGroupbox("World", "sun")
        group:AddToggle("FullbrightEnable", { Text="Fullbright", Default=false })

        ui.Toggles.FullbrightEnable:OnChanged(function(v)
            if v then start() else stop() end
        end)

        return { Name = "Fullbright", Stop = stop }
    end
end
