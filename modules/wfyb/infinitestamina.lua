-- modules/universal/infinitestamina.lua
-- Infinite stamina for titles that compute stamina by water level constants (WFYB-style).
do
    return function(ui)
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
        local maid     = Maid.new()

        local state = {
            enabled = false,
            saved_value = nil,
        }

        local function try_patch(value)
            local ok, pool = pcall(getgc, false)
            if not ok or type(pool) ~= "table" then return end
            for _, t in ipairs(pool) do
                if type(t) == "table" and rawget(t, "WATER_LEVEL_TORSO") ~= nil then
                    if state.saved_value == nil then state.saved_value = t.WATER_LEVEL_TORSO end
                    pcall(function() t.WATER_LEVEL_TORSO = value end)
                    break
                end
            end
        end

        local function start()
            if state.enabled then return end
            state.enabled = true
            -- Push the threshold way down to prevent stamina drain checks from triggering
            try_patch(-math.huge)
            maid:GiveTask(function()
                state.enabled = false
                -- restore on cleanup
                if state.saved_value ~= nil then
                    local ok, pool = pcall(getgc, false)
                    if ok and type(pool) == "table" then
                        for _, t in ipairs(pool) do
                            if type(t) == "table" and rawget(t, "WATER_LEVEL_TORSO") ~= nil then
                                pcall(function() t.WATER_LEVEL_TORSO = state.saved_value end)
                                break
                            end
                        end
                    end
                end
            end)
        end

        local function stop()
            if not state.enabled then return end
            state.enabled = false
            maid:DoCleaning()
        end

        local group = ui.Tabs.Main:AddRightGroupbox("Bypass", "droplet")
        group:AddToggle("InfiniteStaminaToggle", {
            Text = "Infinite Stamina",
            Tooltip = "Neutralizes stamina/water checks (restored on stop).",
            Default = false,
        })

        ui.Toggles.InfiniteStaminaToggle:OnChanged(function(v)
            if v then start() else stop() end
        end)

        return { Name = "InfiniteStamina", Stop = stop }
    end
end
