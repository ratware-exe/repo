-- modules/universal/visual/fullbright.lua
do
    return function(UI)
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
        local maid     = Maid.new()

        local original = nil
        local running = false

        local function apply()
            if running then return end
            running = true
            local l = services.Lighting
            if not original then
                original = {
                    brightness = l.Brightness,
                    clock = l.ClockTime,
                    fogstart = l.FogStart,
                    fogend = l.FogEnd,
                    ambient = l.Ambient,
                    outdoor = l.OutdoorAmbient,
                }
            end
            pcall(function()
                l.Brightness = 2
                l.ClockTime = 14
                l.FogStart = 0
                l.FogEnd = 1e6
                l.Ambient = Color3.new(1,1,1)
                l.OutdoorAmbient = Color3.new(1,1,1)
            end)
        end

        local function revert()
            if not running then return end
            running = false
            local l = services.Lighting
            if original then
                pcall(function()
                    l.Brightness = original.brightness
                    l.ClockTime = original.clock
                    l.FogStart = original.fogstart
                    l.FogEnd = original.fogend
                    l.Ambient = original.ambient
                    l.OutdoorAmbient = original.outdoor
                end)
            end
            original = nil
        end

        -- UI
        do
            local tab = UI.Tabs.Visual or UI.Tabs.Misc
            local group = tab:AddRightGroupbox("Lighting Mods", "sun")
            group:AddToggle("FullbrightToggle", { Text = "Full Bright", Default = false })
        end

        if UI.Toggles and UI.Toggles.FullbrightToggle then
            UI.Toggles.FullbrightToggle:OnChanged(function(v)
                if v then apply() else revert() end
            end)
        end

        local function Stop()
            revert()
            maid:DoCleaning()
        end

        return { Name = "FullBright", Stop = Stop }
    end
end
