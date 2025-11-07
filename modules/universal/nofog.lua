-- modules/universal/nofog.lua
do
    return function(UI)
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
        local maid     = Maid.new()

        local saved = nil
        local function apply()
            local l = services.Lighting
            if not saved then
                local atmosphere = l:FindFirstChildOfClass("Atmosphere")
                saved = {
                    fogstart = l.FogStart, fogend = l.FogEnd,
                    density = atmosphere and atmosphere.Density,
                    haze = atmosphere and atmosphere.Haze,
                    glare = atmosphere and atmosphere.Glare,
                }
            end
            pcall(function()
                l.FogStart = 0
                l.FogEnd = 1e9
                local atm = l:FindFirstChildOfClass("Atmosphere")
                if atm then
                    atm.Density = 0
                    atm.Haze = 0
                    atm.Glare = 0
                end
            end)
        end
        local function revert()
            if not saved then return end
            local l = services.Lighting
            pcall(function()
                l.FogStart = saved.fogstart
                l.FogEnd = saved.fogend
                local atm = l:FindFirstChildOfClass("Atmosphere")
                if atm then
                    if saved.density ~= nil then atm.Density = saved.density end
                    if saved.haze    ~= nil then atm.Haze    = saved.haze end
                    if saved.glare   ~= nil then atm.Glare   = saved.glare end
                end
            end)
            saved = nil
        end

        do
            local tab = UI.Tabs.Visual or UI.Tabs.Misc
            local group = tab:AddRightGroupbox("Lighting Mods", "sun")
            group:AddToggle("NoFogToggle", { Text = "No Fog", Default = false })
        end
        if UI.Toggles and UI.Toggles.NoFogToggle then
            UI.Toggles.NoFogToggle:OnChanged(function(v)
                if v then apply() else revert() end
            end)
        end

        local function Stop()
            revert()
            maid:DoCleaning()
        end

        return { Name = "NoFog", Stop = Stop }
    end
end
