-- modules/universal/visual/nosky.lua
do
    return function(UI)
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
        local maid     = Maid.new()

        local cache = {}

        local function apply()
            local l = services.Lighting
            for _, inst in ipairs(l:GetChildren()) do
                if inst:IsA("Sky") then
                    cache[inst] = true
                    pcall(function() inst:Destroy() end)
                end
            end
        end

        local function Stop()
            maid:DoCleaning()
        end

        -- UI
        do
            local tab = UI.Tabs.Visual or UI.Tabs.Misc
            local group = tab:AddRightGroupbox("Lighting Mods", "sun")
            group:AddToggle("NoSkyToggle", { Text = "No Sky", Default = false })
        end

        if UI.Toggles and UI.Toggles.NoSkyToggle then
            UI.Toggles.NoSkyToggle:OnChanged(function(v)
                if v then apply() else -- cannot restore destroyed instances reliably; original script removed them as well
                    -- noop
                end
            end)
        end

        return { Name = "NoSky", Stop = Stop }
    end
end
