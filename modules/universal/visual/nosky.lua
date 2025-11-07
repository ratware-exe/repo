-- "modules/universal/visual/nosky.lua",
do
    return function(UI)
        -- [1] LOAD DEPENDENCIES
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv = (getgenv and getgenv()) or _G
        local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        -- [2] MODULE STATE
        local ModuleName = "NoSky"
        local Variables = {
            Maids = { [ModuleName] = Maid.new() },
            RunFlag = false, -- Corresponds to NoSkyEnable
            savedSkies = {},
        }

        -- [3] CORE LOGIC
        local function clearSkies()
            pcall(function()
                for _, ch in ipairs(RbxService.Lighting:GetChildren()) do
                    if ch:IsA("Sky") then
                        table.insert(Variables.savedSkies, ch:Clone())
                        ch:Destroy()
                    end
                end
            end)
        end

        local function Start()
            if Variables.RunFlag then return end
            Variables.RunFlag = true
            
            clearSkies()
            
            local childAddedConn = RbxService.Lighting.ChildAdded:Connect(function(ch)
                if Variables.RunFlag and ch:IsA("Sky") then
                    task.defer(function() if ch and ch.Parent then pcall(function() ch:Destroy() end) end end)
                end
            end)
            
            Variables.Maids[ModuleName]:GiveTask(childAddedConn)
            Variables.Maids[ModuleName]:GiveTask(function() Variables.RunFlag = false end)
        end

        local function Stop()
            if not Variables.RunFlag then return end
            Variables.RunFlag = false
            
            Variables.Maids[ModuleName]:DoCleaning()

            pcall(function()
                for _, s in ipairs(Variables.savedSkies) do s:Clone().Parent = RbxService.Lighting end
                table.clear(Variables.savedSkies)
            end)
        end

        -- [4] UI CREATION
        -- NOTE: This UI was missing from your 'prompt.lua' UI constructor.
        -- I have created it here based on the wiring logic.
        local VisualGroupBox = UI.Tabs.Visual:AddRightGroupbox("World", "sun")
        
        VisualGroupBox:AddToggle("RemoveSkyToggle", {
            Text = "Remove Sky",
            Tooltip = "Removes the skybox.",
            Default = false,
        })
        
        -- [5] UI WIRING (CORRECTED)
        UI.Toggles.RemoveSkyToggle:OnChanged(function(enabledState)
            if enabledState then Start() else Stop() end
        end)
        
        -- Start if already enabled
        if UI.Toggles.RemoveSkyToggle.Value then
            Start()
        end

        -- [6] RETURN MODULE
        return { Name = ModuleName, Stop = Stop }
    end
end
