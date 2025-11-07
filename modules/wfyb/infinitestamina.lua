-- modules/universal/infinite_stamina.lua
do
    return function(UI)
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
        local maid     = Maid.new()

        local Variables = {
            StaminaToggle = false,
            StaminaApplied = false,
            StaminaOriginalWaterLevel = nil,
        }

        -- verbatim helpers from prompt.lua
        local function getGC()
            local nevermore = require(services.ReplicatedStorage:WaitForChild("Nevermore"))
            return nevermore("GameConstants")
        end

        function Variables.ApplyStaminaPatch()
            if Variables.StaminaApplied then return end
            local GC = getGC()
            if GC then
                if type(Variables.StaminaOriginalWaterLevel) ~= "number" then
                    Variables.StaminaOriginalWaterLevel = GC.WATER_LEVEL_TORSO
                end
                GC.WATER_LEVEL_TORSO = -math.huge
                Variables.StaminaApplied = true
                if Variables.notify then Variables.notify("Infinite Stamina: [ON].") end
            end
        end

        function Variables.RevertStaminaPatch()
            if not Variables.StaminaApplied then return end
            local GC = getGC()
            if GC and type(Variables.StaminaOriginalWaterLevel) == "number" then
                GC.WATER_LEVEL_TORSO = Variables.StaminaOriginalWaterLevel
            end
            Variables.StaminaApplied = false
            if Variables.notify then
                Variables.notify("Infinite Stamina: [OFF].")
            end
        end

        -- UI (verbatim)
        do
            local tab = UI.Tabs.Main or UI.Tabs.Misc
            local group = tab:AddLeftGroupbox("Bypass", "shield-off")
            group:AddToggle("InfiniteStaminaToggle", {
                Text = "Infinite Stamina",
                Tooltip = "Stay underwater indefinitely.",
                DisabledTooltip = "Feature Disabled!",
                Default = false,
                Disabled = false,
                Visible = true,
                Risky = false,
            })
        end

        -- OnChanged (verbatim)
        if UI.Toggles and UI.Toggles.InfiniteStaminaToggle then
            UI.Toggles.InfiniteStaminaToggle:OnChanged(function(v)
                Variables.StaminaToggle = v and true or false
                if Variables.StaminaToggle then
                    Variables.ApplyStaminaPatch()
                else
                    Variables.RevertStaminaPatch()
                end
            end)
            Variables.StaminaToggle = UI.Toggles.InfiniteStaminaToggle.Value and true or false
            if Variables.StaminaToggle then
                Variables.ApplyStaminaPatch()
            else
                Variables.RevertStaminaPatch()
            end
        end

        local function Stop()
            Variables.StaminaToggle = false
            Variables.RevertStaminaPatch()
            maid:DoCleaning()
        end

        return { Name = "InfiniteStamina", Stop = Stop }
    end
end
