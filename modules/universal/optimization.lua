-- modules/wfyb/UltraAFK.lua
-- Low-power AFK profile: FPS cap, graphics/lighting reduction, audio dim, optional freeze/hide.
-- Designed to be safe to toggle and fully restore on Stop().

return function()
    local RbxService
    local Variables
    local Maid
    local Signal
    local Library

    local Module = {}

    -- Config lives in Variables so other features could read it if needed
    local function ensureConfig()
        Variables.UltraAFKConfig = Variables.UltraAFKConfig or {
            FpsCap = 10,              -- 5..240
            MasterVolume = 0,         -- 0..10 (Roblox volume scale)
            HideLocalCharacter = true,
            FreezeLocalCharacter = false,
            LowerGraphics = true,
            DimPostEffects = true
        }
    end

    local function captureBackups()
        -- Only capture once per Start
        if Variables.UltraAFKBackup then return end
        local RenderingSettings = settings().Rendering
        Variables.UltraAFKBackup = {
            FpsCap = (typeof(getfpscap) == "function" and getfpscap()) or nil,
            QualityLevel = RenderingSettings and RenderingSettings.QualityLevel or nil,
            GlobalShadows = RbxService.Lighting.GlobalShadows,
            EnvironmentDiffuseScale = RbxService.Lighting.EnvironmentDiffuseScale,
            EnvironmentSpecularScale = RbxService.Lighting.EnvironmentSpecularScale,
            Brightness = RbxService.Lighting.Brightness,
            FogEnd = RbxService.Lighting.FogEnd,
            Ambient = RbxService.Lighting.Ambient,
            OutdoorAmbient = RbxService.Lighting.OutdoorAmbient,
            SoundServiceVolume = RbxService.SoundService.Volume,
        }
    end

    local function restoreBackups()
        local Backup = Variables.UltraAFKBackup
        if not Backup then return end

        pcall(function()
            if Backup.FpsCap and typeof(setfpscap) == "function" then
                setfpscap(Backup.FpsCap)
            end
        end)

        pcall(function()
            if Backup.QualityLevel ~= nil then
                local RenderingSettings = settings().Rendering
                RenderingSettings.QualityLevel = Backup.QualityLevel
            end
        end)

        pcall(function() RbxService.Lighting.GlobalShadows = Backup.GlobalShadows end)
        pcall(function() RbxService.Lighting.EnvironmentDiffuseScale = Backup.EnvironmentDiffuseScale end)
        pcall(function() RbxService.Lighting.EnvironmentSpecularScale = Backup.EnvironmentSpecularScale end)
        pcall(function() RbxService.Lighting.Brightness = Backup.Brightness end)
        pcall(function() RbxService.Lighting.FogEnd = Backup.FogEnd end)
        pcall(function() RbxService.Lighting.Ambient = Backup.Ambient end)
        pcall(function() RbxService.Lighting.OutdoorAmbient = Backup.OutdoorAmbient end)
        pcall(function() RbxService.SoundService.Volume = Backup.SoundServiceVolume end)

        Variables.UltraAFKBackup = nil
    end

    local function applyLowPower()
        local Cfg = Variables.UltraAFKConfig

        -- FPS Cap (executor-dependent)
        pcall(function()
            if typeof(setfpscap) == "function" then
                setfpscap(tonumber(Cfg.FpsCap) or 10)
            end
        end)

        -- Lower quality level (client-side)
        pcall(function()
            if Cfg.LowerGraphics then
                local RenderingSettings = settings().Rendering
                RenderingSettings.QualityLevel = Enum.QualityLevel.Level01
            end
        end)

        -- Lighting/visual budget
        pcall(function()
            if Cfg.DimPostEffects then
                RbxService.Lighting.GlobalShadows = false
                RbxService.Lighting.EnvironmentDiffuseScale = 0
                RbxService.Lighting.EnvironmentSpecularScale = 0
                RbxService.Lighting.Brightness = 1
                RbxService.Lighting.FogEnd = math.huge
                RbxService.Lighting.Ambient = Color3.fromRGB(127, 127, 127)
                RbxService.Lighting.OutdoorAmbient = Color3.fromRGB(127, 127, 127)
            end
        end)

        -- Volume dim
        pcall(function()
            RbxService.SoundService.Volume = math.clamp(Cfg.MasterVolume or 0, 0, 10)
        end)

        -- Character privacy and freeze
        local LocalPlayer = RbxService.Players.LocalPlayer
        local Character = LocalPlayer and LocalPlayer.Character
        if Character then
            if Cfg.HideLocalCharacter then
                for _, Descendant in ipairs(Character:GetDescendants()) do
                    if Descendant:IsA("BasePart") then
                        pcall(function() Descendant.LocalTransparencyModifier = 1 end)
                    elseif Descendant:IsA("Decal") or Descendant:IsA("Texture") then
                        pcall(function() Descendant.Transparency = 1 end)
                    elseif Descendant:IsA("ParticleEmitter") then
                        pcall(function() Descendant.Enabled = false end)
                    end
                end
            end
            if Cfg.FreezeLocalCharacter then
                local HumanoidRootPart = Character:FindFirstChild("HumanoidRootPart")
                if HumanoidRootPart then
                    pcall(function()
                        HumanoidRootPart.AssemblyLinearVelocity = Vector3.new()
                        HumanoidRootPart.AssemblyAngularVelocity = Vector3.new()
                        HumanoidRootPart.Anchored = true
                    end)
                end
            end
        end
    end

    local function clearCharacterTweaks()
        local LocalPlayer = RbxService.Players.LocalPlayer
        local Character = LocalPlayer and LocalPlayer.Character
        if not Character then return end

        for _, Descendant in ipairs(Character:GetDescendants()) do
            if Descendant:IsA("BasePart") then
                pcall(function() Descendant.LocalTransparencyModifier = 0 end)
            elseif Descendant:IsA("Decal") or Descendant:IsA("Texture") then
                -- leave as-is; not all games restore decal transparency reliably
            elseif Descendant:IsA("ParticleEmitter") then
                pcall(function() Descendant.Enabled = true end)
            end
        end

        local HumanoidRootPart = Character:FindFirstChild("HumanoidRootPart")
        if HumanoidRootPart then
            pcall(function() HumanoidRootPart.Anchored = false end)
        end
    end

    function Module.Init(env)
        RbxService = env.RbxService
        Variables  = env.Variables
        Maid       = env.Maid
        Signal     = env.Signal
        Library    = env.Library

        if not Variables.Maids.UltraAFK then
            Variables.Maids.UltraAFK = Maid.new()
        end
        ensureConfig()
    end

    function Module.BuildUI(Tabs)
        ensureConfig()
        local Group = Tabs.Misc:AddRightGroupbox("Ultra AFK", "moon")

        Group:AddToggle("WFYB_UltraAFKToggle", {
            Text = "Ultra AFK Mode",
            Default = false
        })

        Group:AddSlider("WFYB_UltraAFK_FpsCap", {
            Text = "FPS Cap",
            Min = 5,
            Max = 240,
            Default = Variables.UltraAFKConfig.FpsCap,
            Rounding = 0
        })

        Group:AddSlider("WFYB_UltraAFK_MasterVolume", {
            Text = "Master Volume",
            Min = 0,
            Max = 10,
            Default = Variables.UltraAFKConfig.MasterVolume,
            Rounding = 0
        })

        Group:AddToggle("WFYB_UltraAFK_HideCharacter", {
            Text = "Hide Local Character",
            Default = Variables.UltraAFKConfig.HideLocalCharacter
        })

        Group:AddToggle("WFYB_UltraAFK_FreezeCharacter", {
            Text = "Freeze Local Character",
            Default = Variables.UltraAFKConfig.FreezeLocalCharacter
        })

        Group:AddToggle("WFYB_UltraAFK_LowerGraphics", {
            Text = "Lower Graphics",
            Default = Variables.UltraAFKConfig.LowerGraphics
        })

        Group:AddToggle("WFYB_UltraAFK_DimPostEffects", {
            Text = "Dim Post Effects",
            Default = Variables.UltraAFKConfig.DimPostEffects
        })

        -- Wiring
        Library.Toggles.WFYB_UltraAFKToggle:OnChanged(function(isOn)
            if isOn then Module.Start() else Module.Stop() end
        end)

        Library.Options.WFYB_UltraAFK_FpsCap:OnChanged(function(value)
            Variables.UltraAFKConfig.FpsCap = value
            if Variables.UltraAFKRunFlag then
                pcall(function()
                    if typeof(setfpscap) == "function" then
                        setfpscap(value)
                    end
                end)
            end
        end)

        Library.Options.WFYB_UltraAFK_MasterVolume:OnChanged(function(value)
            Variables.UltraAFKConfig.MasterVolume = value
            if Variables.UltraAFKRunFlag then
                pcall(function()
                    RbxService.SoundService.Volume = value
                end)
            end
        end)

        Library.Toggles.WFYB_UltraAFK_HideCharacter:OnChanged(function(value)
            Variables.UltraAFKConfig.HideLocalCharacter = value
            if Variables.UltraAFKRunFlag then
                if value then applyLowPower() else clearCharacterTweaks() end
            end
        end)

        Library.Toggles.WFYB_UltraAFK_FreezeCharacter:OnChanged(function(value)
            Variables.UltraAFKConfig.FreezeLocalCharacter = value
            if Variables.UltraAFKRunFlag then
                if value then applyLowPower() else clearCharacterTweaks() end
            end
        end)

        Library.Toggles.WFYB_UltraAFK_LowerGraphics:OnChanged(function(value)
            Variables.UltraAFKConfig.LowerGraphics = value
            if Variables.UltraAFKRunFlag then applyLowPower() end
        end)

        Library.Toggles.WFYB_UltraAFK_DimPostEffects:OnChanged(function(value)
            Variables.UltraAFKConfig.DimPostEffects = value
            if Variables.UltraAFKRunFlag then applyLowPower() end
        end)
    end

    function Module.Start()
        if Variables.UltraAFKRunFlag then return end
        Variables.UltraAFKRunFlag = true

        captureBackups()
        applyLowPower()

        -- Keep-low-power enforcer (rare resets by games)
        local Enforce = RbxService.RunService.RenderStepped:Connect(function()
            if not Variables.UltraAFKRunFlag then return end
            -- Periodically re-apply minimal settings that games often override
            if Variables.UltraAFKConfig.DimPostEffects then
                pcall(function()
                    RbxService.Lighting.GlobalShadows = false
                end)
            end
        end)
        Variables.Maids.UltraAFK:GiveTask(Enforce)
        Variables.Maids.UltraAFK:GiveTask(function() Variables.UltraAFKRunFlag = false end)
    end

    function Module.Stop()
        if not Variables.UltraAFKRunFlag then return end
        Variables.UltraAFKRunFlag = false

        Variables.Maids.UltraAFK:DoCleaning()
        clearCharacterTweaks()
        restoreBackups()
    end

    return Module
end
