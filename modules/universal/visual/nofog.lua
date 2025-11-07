-- "modules/universal/visual/nofog.lua",
do
    return function(UI)
        -- [1] LOAD DEPENDENCIES
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv = (getgenv and getgenv()) or _G
        local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        -- [2] MODULE STATE
        local ModuleName = "NoFog"
        local Variables = {
            Maids = { [ModuleName] = Maid.new() },
            RunFlag = false, -- Corresponds to NoFogEnable
            Backup = nil, -- Corresponds to NoFogBackup
        }

        -- [3] CORE LOGIC
        local function onRenderStep()
            if not Variables.RunFlag then return end
            pcall(function()
                RbxService.Lighting.FogStart = 1e6
                RbxService.Lighting.FogEnd = 1e6
                local a = RbxService.Lighting:FindFirstChildOfClass("Atmosphere")
                if not a then
                    a = Instance.new("Atmosphere")
                    a.Parent = RbxService.Lighting
                end
                a.Density, a.Offset = 0, 0
                if a.Glare ~= nil then a.Glare = 0 end
                if a.Haze ~= nil then a.Haze = 0 end
            end)
        end

        local function Start()
            if Variables.RunFlag then return end
            Variables.RunFlag = true
            
            pcall(function()
                if not Variables.Backup then
                    local atmosphere0 = RbxService.Lighting:FindFirstChildOfClass("Atmosphere")
                    Variables.Backup = {
                        FogStart = RbxService.Lighting.FogStart,
                        FogEnd = RbxService.Lighting.FogEnd,
                        AtmosphereExisted = atmosphere0 ~= nil,
                        Density = atmosphere0 and atmosphere0.Density or nil,
                        Offset = atmosphere0 and atmosphere0.Offset or nil,
                        Glare = (atmosphere0 and atmosphere0.Glare ~= nil) and atmosphere0.Glare or nil,
                        Haze = (atmosphere0 and atmosphere0.Haze ~= nil) and atmosphere0.Haze or nil,
                        CreatedAtmosphere = false,
                    }
                end

                local atmosphere = RbxService.Lighting:FindFirstChildOfClass("Atmosphere")
                if not atmosphere then
                    atmosphere = Instance.new("Atmosphere")
                    atmosphere.Parent = RbxService.Lighting
                    if Variables.Backup then -- Ensure backup exists before writing to it
                        Variables.Backup.CreatedAtmosphere = true
                    end
                end

                onRenderStep() -- Apply immediately
            end)

            Variables.Maids[ModuleName]:GiveTask(RbxService.RunService.RenderStepped:Connect(onRenderStep))
            Variables.Maids[ModuleName]:GiveTask(function() Variables.RunFlag = false end)
            
            -- This function needs to be in the maid to be called by Stop()
            Variables.Maids[ModuleName]:GiveTask(function()
                if not Variables.Backup then return end
                pcall(function()
                    RbxService.Lighting.FogStart = Variables.Backup.FogStart
                    RbxService.Lighting.FogEnd = Variables.Backup.FogEnd
                    local a = RbxService.Lighting:FindFirstChildOfClass("Atmosphere")
                    if Variables.Backup.CreatedAtmosphere and a then
                        a:Destroy()
                    elseif a then
                        if Variables.Backup.Density ~= nil then a.Density = Variables.Backup.Density end
                        if Variables.Backup.Offset  ~= nil then a.Offset  = Variables.Backup.Offset  end
                        if Variables.Backup.Glare   ~= nil and a.Glare ~= nil then a.Glare = Variables.Backup.Glare end
                        if Variables.Backup.Haze    ~= nil and a.Haze  ~= nil then a.Haze  = Variables.Backup.Haze  end
                    end
                    Variables.Backup = nil
                end)
            end)
        end

        local function Stop()
            if not Variables.RunFlag then return end
            Variables.RunFlag = false
            
            Variables.Maids[ModuleName]:DoCleaning()
            -- The cleanup function is now in the maid, so it will be called.
        end

        -- [4] UI CREATION
        -- NOTE: This UI was missing from your 'prompt.lua' UI constructor.
        -- I have created it here based on the wiring logic.
        local VisualGroupBox = UI.Tabs.Visual:AddRightGroupbox("World", "sun")
        
        VisualGroupBox:AddToggle("NoFogToggle", {
            Text = "No Fog",
            Tooltip = "Removes all fog and atmosphere.",
            Default = false,
        })
        
        -- [5] UI WIRING (CORRECTED)
        UI.Toggles.NoFogToggle:OnChanged(function(enabledState)
            if enabledState then Start() else Stop() end
        end)

        -- Start if already enabled
        if UI.Toggles.NoFogToggle.Value then
            Start()
        end

        -- [6] RETURN MODULE
        return { Name = ModuleName, Stop = Stop }
    end
end
