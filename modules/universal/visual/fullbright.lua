-- "modules/universal/visual/fullbright.lua",
do
    return function(UI)
        -- [1] LOAD DEPENDENCIES
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv = (getgenv and getgenv()) or _G
        local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        -- [2] MODULE STATE
        local ModuleName = "Fullbright"
        local Variables = {
            Maids = { [ModuleName] = Maid.new() },
            RunFlag = false, -- Corresponds to FullbrightEnable
            FullbrightIntensity = 1,
            Backup = nil,
        }

        -- [3] CORE LOGIC
        local function onRenderStep()
            if not Variables.RunFlag then return end
            pcall(function()
                RbxService.Lighting.Brightness = tonumber(Variables.FullbrightIntensity)
                RbxService.Lighting.ClockTime = 12
            end)
        end

        local function Start()
            if Variables.RunFlag then return end
            Variables.RunFlag = true

            if not Variables.Backup then
                Variables.Backup = {
                    Brightness = RbxService.Lighting.Brightness,
                    ClockTime = RbxService.Lighting.ClockTime,
                }
            end
            
            Variables.Maids[ModuleName]:GiveTask(RbxService.RunService.RenderStepped:Connect(onRenderStep))
            Variables.Maids[ModuleName]:GiveTask(function() Variables.RunFlag = false end)
        end

        local function Stop()
            if not Variables.RunFlag then return end
            Variables.RunFlag = false
            
            Variables.Maids[ModuleName]:DoCleaning()

            if Variables.Backup then
                pcall(function()
                    RbxService.Lighting.Brightness = Variables.Backup.Brightness
                    RbxService.Lighting.ClockTime = Variables.Backup.ClockTime
                end)
                Variables.Backup = nil
            end
        end

        -- [4] UI CREATION
        -- NOTE: This UI was missing from your 'prompt.lua' UI constructor.
        -- I have created it here based on the wiring logic.
        local VisualGroupBox = UI.Tabs.Visual:AddRightGroupbox("World", "sun")
        
        VisualGroupBox:AddToggle("FullbrightToggle", {
            Text = "Fullbright",
            Tooltip = "Sets brightness to maximum.",
            Default = false,
        })
        
        VisualGroupBox:AddSlider("FullbrightSlider", {
			Text = "Intensity",
			Default = 1, Min = 0, Max = 10, Rounding = 1, Compact = true,
			Tooltip = "Changes fullbright intensity.",
		})
        
        -- [5] UI WIRING (CORRECTED)
        UI.Toggles.FullbrightToggle:OnChanged(function(enabledState)
            if enabledState then Start() else Stop() end
        end)
        
        UI.Options.FullbrightSlider:OnChanged(function(v)
            Variables.FullbrightIntensity = tonumber(v) or 1
        end)
        
        -- Seed default values
        Variables.FullbrightIntensity = tonumber(UI.Options.FullbrightSlider.Value) or 1
        
        -- Start if already enabled
        if UI.Toggles.FullbrightToggle.Value then
            Start()
        end

        -- [6] RETURN MODULE
        return { Name = ModuleName, Stop = Stop }
    end
end
