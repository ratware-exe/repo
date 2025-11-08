-- "modules/wfyb/bypass/infinitestamina.lua",
do
    return function(UI)
        -- [1] LOAD DEPENDENCIES
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv = (getgenv and getgenv()) or _G
        local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        -- [2] MODULE STATE
        local ModuleName = "InfiniteStamina"
        local Variables = {
            Maids = { [ModuleName] = Maid.new() },
            RunFlag = false, -- Corresponds to StaminaToggle
            StaminaOriginalWaterLevel = nil,
            StaminaApplied = false,
            NotifyFunc = nil -- Placeholder for notifier
        }

        -- [3] CORE LOGIC
        local function notify(msg)
            if Variables.NotifyFunc then
                pcall(Variables.NotifyFunc, msg)
            else
                print(msg) -- Fallback
            end
        end

        local function getGC()
            local ok, Nevermore = pcall(require, RbxService.ReplicatedStorage:WaitForChild("Nevermore"))
            if not ok then return nil end
            local ok2, GC = pcall(Nevermore, "GameConstants")
            return (ok2 and typeof(GC) == "table") and GC or nil
        end
        
        local function Start()
            if Variables.RunFlag then return end
            Variables.RunFlag = true
            
            pcall(function()
                local GC = getGC()
                if not GC or type(GC.WATER_LEVEL_TORSO) ~= "number" then return end
                if Variables.StaminaOriginalWaterLevel == nil then
                    Variables.StaminaOriginalWaterLevel = GC.WATER_LEVEL_TORSO
                end
                GC.WATER_LEVEL_TORSO = -1e9
                Variables.StaminaApplied = true
                notify("Infinite Stamina: [ON].")
            end)
            
            Variables.Maids[ModuleName]:GiveTask(function() Variables.RunFlag = false end)
        end

        local function Stop()
            if not Variables.RunFlag and not Variables.StaminaApplied then return end
            Variables.RunFlag = false
            
            pcall(function()
                if not Variables.StaminaApplied then return end
                local GC = getGC()
                if GC and type(Variables.StaminaOriginalWaterLevel) == "number" then
                    GC.WATER_LEVEL_TORSO = Variables.StaminaOriginalWaterLevel
                end
                Variables.StaminaApplied = false
                notify("Infinite Stamina: [OFF].")
            end)
            
            Variables.Maids[ModuleName]:DoCleaning()
            Variables.StaminaOriginalWaterLevel = nil -- Clear backup
        end

        -- [4] UI CREATION
        local RemovalGroupBox = UI.Tabs.Main:AddLeftGroupbox("Bypass", "shield-off")
		local InfiniteStaminaToggle = RemovalGroupBox:AddToggle("InfiniteStaminaToggle", {
			Text = "Infinite Stamina",
			Tooltip = "Stay underwater indefinitely.", 
			Default = false, 
		})

        -- [5] UI WIRING (CORRECTED)
        UI.Toggles.InfiniteStaminaToggle:OnChanged(function(enabledState)
            if enabledState then Start() else Stop() end
        end)
        
        -- Start if already enabled
        if UI.Toggles.InfiniteStaminaToggle.Value then
            Start()
        end

        -- [6] RETURN MODULE
        return { Name = ModuleName, Stop = Stop }
    end
end
