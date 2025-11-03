-- modules/UltraAFK.lua
do
return function(UI)
    local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
    local GlobalEnv = (getgenv and getgenv()) or _G
    GlobalEnv.Signal = GlobalEnv.Signal or loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()
    local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

    local Variables = {
        Maids = { UltraAFK = Maid.new() },
        RunFlag = false,
        Config = {
            UltraPreset = true,
            ReversibleMode = true,
            TargetFpsWhileLowPower = 1,
            HidePlayerGuiWhileLowPower = true,
            HideCoreGuiWhileLowPower  = true,
            LowerLightingWhileLowPower = true,
            UseMinimumGraphicsQuality  = true,
            PauseCharacterAnimations   = true,
            PauseAllAnimations         = true,
            PauseAllTweens             = true,
            DisableViewportFrames      = true,
            DisableVideoFrames         = true,
            AnchorCharacterWhileLowPower = true,
            ReduceSimulationRadius = true,
            RemoveLocalNetworkOwnership = true,
            DisableConstraintsAggressive = true,
            RemoveGrassDecoration   = true,
            SmoothPlasticEverywhere = true,
            GraySkyEnabled = true,
            FullBrightEnabled = true,
            DestroyEmitters = false,
            NukeTextures   = false,
            ForceClearBlurOnRestore = true,
        },
        State = {
            SoundGuards = {},
            ViewportGuards = {},
            VideoGuards = {},
            ConstraintStates = {},
        },
        Snapshot = {
            RenderingEnabled = true,
            CameraType = nil, CameraSubject = nil, CameraFOV = nil,
            UserMasterVolume = nil,
            PlayerGuiStates = {}, CoreGuiStates = {},
            EffectEnabled = {}, LightEnabled = {}, SoundVolume = {},
            ViewportFrameVisible = {}, VideoFramePlaying = {},
            AnimatorGuards = {},
            Lighting = { GlobalShadows=nil, Brightness=nil, EnvironmentDiffuseScale=nil, EnvironmentSpecularScale=nil, Atmospheres = {} },
            TerrainDecoration = nil,
            SavedQualityLevel = nil,
            CharacterAnchored = {},
            HumanoidProps = { WalkSpeed=nil, JumpPower=nil, AutoRotate=nil, PlatformStand=nil },
            PartMaterial = {},
            DecalTransparency = {},
        },
    }

    -- Helpers
    local function TrySetFpsCap(targetFps)
        local candidates = {
            (getgenv and getgenv().setfpscap) or nil,
            rawget(_G, "setfpscap"),
            rawget(_G, "set_fps_cap"),
            rawget(_G, "setfps"),
            rawget(_G, "setfps_max"),
        }
        for functionIndex = 1, #candidates do
            local candidate = candidates[functionIndex]
            if typeof(candidate) == "function" then
                local callSucceeded = pcall(candidate, targetFps)
                if callSucceeded then return true end
            end
        end
        return false
    end

    local function ApplyUltraPreset()
        local Config = Variables.Config
        if not Config.UltraPreset then return end
        Config.TargetFpsWhileLowPower = 1
        Config.HidePlayerGuiWhileLowPower = true
        Config.HideCoreGuiWhileLowPower  = true
        Config.LowerLightingWhileLowPower = true
        Config.UseMinimumGraphicsQuality  = true
        Config.PauseCharacterAnimations   = true
        Config.PauseAllAnimations         = true
        Config.PauseAllTweens             = true
        Config.DisableViewportFrames      = true
        Config.DisableVideoFrames         = true
        Config.AnchorCharacterWhileLowPower = true
        Config.ReduceSimulationRadius = true
        Config.RemoveLocalNetworkOwnership = true
        Config.DisableConstraintsAggressive = true
        Config.RemoveGrassDecoration = true
        Config.SmoothPlasticEverywhere = true
        Config.GraySkyEnabled = true
        Config.FullBrightEnabled = true
        if Config.ReversibleMode then
            Config.DestroyEmitters = false
            Config.NukeTextures = false
        else
            Config.DestroyEmitters = true
            Config.NukeTextures = true
        end
    end

    local function Unguard(guardTable, guardedInstance)
        local bundle = guardTable[guardedInstance]
        if bundle then
            for connectionIndex = 1, #bundle do
                local connectionObject = bundle[connectionIndex]
                if connectionObject then connectionObject:Disconnect() end
            end
        end
        guardTable[guardedInstance] = nil
    end

    -- Animator guards (pause via track speeds)
    local function ShouldPauseAnimator(animator)
        local localPlayer = RbxService.Players.LocalPlayer
        local character = localPlayer and localPlayer.Character
        local isCharacterAnimator = character and animator:IsDescendantOf(character)
        if isCharacterAnimator then
            return Variables.Config.PauseCharacterAnimations
        else
            return Variables.Config.PauseAllAnimations
        end
    end

    local function GuardAnimator(animator)
        if not animator or not animator:IsA("Animator") then return end
        if not ShouldPauseAnimator(animator) then return end
        local Snapshot = Variables.Snapshot
        if Snapshot.AnimatorGuards[animator] then return end

        local guardRecord = { tracks = {}, conns = {} }
        Snapshot.AnimatorGuards[animator] = guardRecord

        local function getTrackSpeed(track)
            local ok, speed = pcall(function() return track.Speed end)
            if ok and typeof(speed) == "number" then
                return speed
            end
            return 1
        end

        local function freezeTrack(animationTrack)
            if not animationTrack then return end
            if guardRecord.tracks[animationTrack] == nil then
                guardRecord.tracks[animationTrack] = getTrackSpeed(animationTrack)
            end
            pcall(function() animationTrack:AdjustSpeed(0) end)
            table.insert(guardRecord.conns, animationTrack.Stopped:Connect(function()
                guardRecord.tracks[animationTrack] = nil
            end))
        end

        local callSucceeded, tracks = pcall(function() return animator:GetPlayingAnimationTracks() end)
        if callSucceeded and tracks then
            for trackIndex = 1, #tracks do
                freezeTrack(tracks[trackIndex])
            end
        end

        table.insert(guardRecord.conns, animator.AnimationPlayed:Connect(function(newTrack)
            if Variables.RunFlag and ShouldPauseAnimator(animator) then
                freezeTrack(newTrack)
            end
        end))

        table.insert(guardRecord.conns, animator.AncestryChanged:Connect(function(_, newParent)
            if newParent == nil then
                for connectionIndex = 1, #guardRecord.conns do
                    local connectionObject = guardRecord.conns[connectionIndex]
                    if connectionObject then connectionObject:Disconnect() end
                end
                Snapshot.AnimatorGuards[animator] = nil
            end
        end))
    end

    local function ReleaseAnimatorGuards()
        local Snapshot = Variables.Snapshot
        for animator, guardRecord in pairs(Snapshot.AnimatorGuards) do
            if guardRecord.tracks then
                for animationTrack, oldSpeed in pairs(guardRecord.tracks) do
                    pcall(function() animationTrack:AdjustSpeed(oldSpeed or 1) end)
                    guardRecord.tracks[animationTrack] = nil
                end
            end
            if guardRecord.conns then
                for connectionIndex = 1, #guardRecord.conns do
                    local connectionObject = guardRecord.conns[connectionIndex]
                    if connectionObject then connectionObject:Disconnect() end
                end
            end
            Snapshot.AnimatorGuards[animator] = nil
        end
    end

    -- Guards for other objects
    local function GuardSound(soundInstance)
        if not soundInstance or not soundInstance:IsA("Sound") then return end
        local Snapshot, State = Variables.Snapshot, Variables.State
        if Snapshot.SoundVolume[soundInstance] == nil then
            Snapshot.SoundVolume[soundInstance] = soundInstance.Volume
        end
        pcall(function() soundInstance.Volume = 0; soundInstance.Playing = false end)
        if State.SoundGuards[soundInstance] then return end
        State.SoundGuards[soundInstance] = {
            soundInstance:GetPropertyChangedSignal("Volume"):Connect(function()
                if Variables.RunFlag then pcall(function() soundInstance.Volume = 0 end) end
            end),
            soundInstance:GetPropertyChangedSignal("Playing"):Connect(function()
                if Variables.RunFlag and soundInstance.Playing then pcall(function() soundInstance.Playing = false end) end
            end),
            soundInstance.AncestryChanged:Connect(function(_, newParent)
                if newParent == nil then
                    Unguard(State.SoundGuards, soundInstance)
                    Snapshot.SoundVolume[soundInstance] = nil
                end
            end),
        }
    end

    local function GuardViewportFrame(viewportFrame)
        if not Variables.Config.DisableViewportFrames or not viewportFrame or not viewportFrame:IsA("ViewportFrame") then return end
        local Snapshot, State = Variables.Snapshot, Variables.State
        if Snapshot.ViewportFrameVisible[viewportFrame] == nil then
            Snapshot.ViewportFrameVisible[viewportFrame] = viewportFrame.Visible
        end
        pcall(function() viewportFrame.Visible = false end)
        if State.ViewportGuards[viewportFrame] then return end
        State.ViewportGuards[viewportFrame] = {
            viewportFrame:GetPropertyChangedSignal("Visible"):Connect(function()
                if Variables.RunFlag then pcall(function() viewportFrame.Visible = false end) end
            end),
            viewportFrame.AncestryChanged:Connect(function(_, newParent)
                if newParent == nil then
                    Unguard(State.ViewportGuards, viewportFrame)
                    Snapshot.ViewportFrameVisible[viewportFrame] = nil
                end
            end),
        }
    end

    local function GuardVideoFrame(videoFrame)
        if not Variables.Config.DisableVideoFrames or not videoFrame or not videoFrame:IsA("VideoFrame") then return end
        local Snapshot, State = Variables.Snapshot, Variables.State
        if Snapshot.VideoFramePlaying[videoFrame] == nil then
            Snapshot.VideoFramePlaying[videoFrame] = videoFrame.Playing
        end
        pcall(function() videoFrame.Playing = false end)
        if State.VideoGuards[videoFrame] then return end
        State.VideoGuards[videoFrame] = {
            videoFrame:GetPropertyChangedSignal("Playing"):Connect(function()
                if Variables.RunFlag and videoFrame.Playing then pcall(function() videoFrame.Playing = false end) end
            end),
            videoFrame.AncestryChanged:Connect(function(_, newParent)
                if newParent == nil then
                    Unguard(State.VideoGuards, videoFrame)
                    Snapshot.VideoFramePlaying[videoFrame] = nil
                end
            end),
        }
    end

    -- Lighting and quality
    local function DisableCoreGui()
        if not Variables.Config.HideCoreGuiWhileLowPower then return end
        local Snapshot = Variables.Snapshot
        local coreTypes = { Enum.CoreGuiType.Chat, Enum.CoreGuiType.Backpack, Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.Health, Enum.CoreGuiType.EmotesMenu }
        for typeIndex = 1, #coreTypes do
            local coreType = coreTypes[typeIndex]
            local callSucceeded, wasEnabled = pcall(function() return RbxService.StarterGui:GetCoreGuiEnabled(coreType) end)
            if callSucceeded then Snapshot.CoreGuiStates[coreType] = wasEnabled end
            pcall(function() RbxService.StarterGui:SetCoreGuiEnabled(coreType, false) end)
        end
        pcall(function() RbxService.StarterGui:SetCore("TopbarEnabled", false) end)
    end

    local function RestoreCoreGui()
        if not Variables.Config.HideCoreGuiWhileLowPower then return end
        local Snapshot = Variables.Snapshot
        for coreType, wasEnabled in pairs(Snapshot.CoreGuiStates) do
            pcall(function() RbxService.StarterGui:SetCoreGuiEnabled(coreType, wasEnabled and true or false) end)
            Snapshot.CoreGuiStates[coreType] = nil
        end
        pcall(function() RbxService.StarterGui:SetCore("TopbarEnabled", true) end)
    end

    local function LowerLighting()
        if not Variables.Config.LowerLightingWhileLowPower then return end
        local Snapshot = Variables.Snapshot
        local lighting = RbxService.Lighting
        Snapshot.Lighting.GlobalShadows = lighting.GlobalShadows
        Snapshot.Lighting.Brightness = lighting.Brightness
        Snapshot.Lighting.EnvironmentDiffuseScale = lighting.EnvironmentDiffuseScale
        Snapshot.Lighting.EnvironmentSpecularScale = lighting.EnvironmentSpecularScale
        pcall(function()
            lighting.GlobalShadows = false
            lighting.Brightness = 0
            lighting.EnvironmentDiffuseScale = 0
            lighting.EnvironmentSpecularScale = 0
        end)
        local lightingDescendants = lighting:GetDescendants()
        for descendantIndex = 1, #lightingDescendants do
            local descendant = lightingDescendants[descendantIndex]
            if descendant:IsA("Atmosphere") then
                Snapshot.Lighting.Atmospheres[descendant] = descendant.Density
                pcall(function() descendant.Density = 0 end)
            end
        end
        if Variables.Config.GraySkyEnabled then
            local children = lighting:GetChildren()
            for childIndex = 1, #children do
                local childInstance = children[childIndex]
                if childInstance:IsA("Sky") or childInstance:IsA("Clouds") then
                    pcall(function() childInstance:Destroy() end)
                end
            end
            local newSky = Instance.new("Sky")
            newSky.SunAngularSize = 0
            newSky.MoonAngularSize = 0
            newSky.StarCount = 0
            newSky.Parent = lighting
        end
        if Variables.Config.FullBrightEnabled then
            pcall(function()
                lighting.OutdoorAmbient = Color3.new(1, 1, 1)
                lighting.Ambient = Color3.new(1, 1, 1)
                lighting.ExposureCompensation = 0
            end)
        end
    end

    local function RestoreLighting()
        if not Variables.Config.LowerLightingWhileLowPower then return end
        local Snapshot = Variables.Snapshot
        local lighting = RbxService.Lighting
        if Snapshot.Lighting.GlobalShadows ~= nil then pcall(function() lighting.GlobalShadows = Snapshot.Lighting.GlobalShadows end) end
        if Snapshot.Lighting.Brightness ~= nil then pcall(function() lighting.Brightness = Snapshot.Lighting.Brightness end) end
        if Snapshot.Lighting.EnvironmentDiffuseScale ~= nil then pcall(function() lighting.EnvironmentDiffuseScale = Snapshot.Lighting.EnvironmentDiffuseScale end) end
        if Snapshot.Lighting.EnvironmentSpecularScale ~= nil then pcall(function() lighting.EnvironmentSpecularScale = Snapshot.Lighting.EnvironmentSpecularScale end) end
        for atmosphereInstance, oldDensity in pairs(Snapshot.Lighting.Atmospheres) do
            if atmosphereInstance and atmosphereInstance.Parent then
                pcall(function() atmosphereInstance.Density = oldDensity end)
            end
            Snapshot.Lighting.Atmospheres[atmosphereInstance] = nil
        end
    end

    local function LowerGraphicsQuality()
        if not Variables.Config.UseMinimumGraphicsQuality then return end
        local callSucceeded, userSettingsService = pcall(function() return UserSettings():GetService("UserGameSettings") end)
        if callSucceeded and userSettingsService then
            Variables.Snapshot.SavedQualityLevel = userSettingsService.SavedQualityLevel
            pcall(function() userSettingsService.SavedQualityLevel = Enum.SavedQualitySetting.QualityLevel1 end)
        end
    end

    local function RestoreGraphicsQuality()
        if not Variables.Config.UseMinimumGraphicsQuality then return end
        if Variables.Snapshot.SavedQualityLevel ~= nil then
            local callSucceeded, userSettingsService = pcall(function() return UserSettings():GetService("UserGameSettings") end)
            if callSucceeded and userSettingsService then
                pcall(function() userSettingsService.SavedQualityLevel = Variables.Snapshot.SavedQualityLevel end)
            end
            Variables.Snapshot.SavedQualityLevel = nil
        end
    end

    -- World slimming
    local function DestroyEmitterLike(instanceObject)
        if not Variables.Config.DestroyEmitters then return false end
        local localPlayer = RbxService.Players.LocalPlayer
        local character = localPlayer and localPlayer.Character
        if character and instanceObject:IsDescendantOf(character) then return false end
        if instanceObject:IsA("ParticleEmitter") or instanceObject:IsA("Trail") or instanceObject:IsA("Fire") or instanceObject:IsA("Smoke") or instanceObject:IsA("Sparkles") then
            pcall(function() instanceObject:Destroy() end)
            return true
        end
        return false
    end

    local function DisableConstraint(instanceObject)
        if not Variables.Config.DisableConstraintsAggressive then return false end
        local localPlayer = RbxService.Players.LocalPlayer
        local character = localPlayer and localPlayer.Character
        if character and instanceObject:IsDescendantOf(character) then return false end
        if instanceObject:IsA("Motor6D") then return false end
        if instanceObject:IsA("Constraint") or instanceObject:IsA("HingeConstraint") or instanceObject:IsA("RodConstraint") or instanceObject:IsA("AlignPosition") or instanceObject:IsA("AlignOrientation") then
            if instanceObject.Enabled ~= nil then
                if Variables.State.ConstraintStates[instanceObject] == nil then
                    Variables.State.ConstraintStates[instanceObject] = instanceObject.Enabled
                end
                pcall(function() instanceObject.Enabled = false end)
            end
            return true
        end
        return false
    end

    local function SmoothifyAndNukeTextures(instanceObject)
        local localPlayer = RbxService.Players.LocalPlayer
        local character = localPlayer and localPlayer.Character
        if character and instanceObject:IsDescendantOf(character) then return end

        if instanceObject:IsA("BasePart") then
            if Variables.Config.SmoothPlasticEverywhere then
                if Variables.Snapshot.PartMaterial[instanceObject] == nil then
                    Variables.Snapshot.PartMaterial[instanceObject] = { Material = instanceObject.Material, Reflectance = instanceObject.Reflectance, CastShadow = instanceObject.CastShadow }
                end
                pcall(function()
                    instanceObject.Material = Enum.Material.SmoothPlastic
                    instanceObject.Reflectance = 0
                    instanceObject.CastShadow = false
                end)
            end
            if Variables.Config.NukeTextures then
                local children = instanceObject:GetChildren()
                for childIndex = 1, #children do
                    local child = children[childIndex]
                    if child:IsA("Decal") then
                        if Variables.Snapshot.DecalTransparency[child] == nil then
                            Variables.Snapshot.DecalTransparency[child] = child.Transparency
                        end
                        pcall(function() child.Transparency = 1 end)
                    end
                end
            end
        elseif Variables.Config.NukeTextures and (instanceObject:IsA("Decal") or instanceObject:IsA("Texture") or instanceObject:IsA("ImageLabel") or instanceObject:IsA("ImageButton")) then
            if instanceObject:IsA("Decal") then
                if Variables.Snapshot.DecalTransparency[instanceObject] == nil then
                    Variables.Snapshot.DecalTransparency[instanceObject] = instanceObject.Transparency
                end
                pcall(function() instanceObject.Transparency = 1 end)
            else
                pcall(function() instanceObject.Transparency = 1 end)
            end
        end
    end

    local function RemoveGrass()
        if not Variables.Config.RemoveGrassDecoration then return end
        local terrain = RbxService.Workspace:FindFirstChildOfClass("Terrain")
        if not terrain then return end
        local setHiddenProperty = rawget(_G, "sethiddenproperty") or (getgenv and getgenv().sethiddenproperty) or _G.sethiddenproperty
        if typeof(setHiddenProperty) == "function" then
            if Variables.Snapshot.TerrainDecoration == nil then
                pcall(function() Variables.Snapshot.TerrainDecoration = terrain.Decoration end)
            end
            pcall(function() setHiddenProperty(terrain, "Decoration", false) end)
        end
    end

    local function RestoreGrass()
        local terrain = RbxService.Workspace:FindFirstChildOfClass("Terrain")
        if not terrain then return end
        local setHiddenProperty = rawget(_G, "sethiddenproperty") or (getgenv and getgenv().sethiddenproperty) or _G.sethiddenproperty
        if typeof(setHiddenProperty) == "function" then
            local desired = (Variables.Snapshot.TerrainDecoration == nil) and true or Variables.Snapshot.TerrainDecoration
            pcall(function() setHiddenProperty(terrain, "Decoration", desired) end)
            Variables.Snapshot.TerrainDecoration = nil
        end
    end

    local function ApplyToInstance(instanceObject)
        if DestroyEmitterLike(instanceObject) then return end

        if instanceObject:IsA("PostEffect") or instanceObject:IsA("ParticleEmitter") or instanceObject:IsA("Beam") or instanceObject:IsA("Trail")
            or instanceObject:IsA("Fire") or instanceObject:IsA("Smoke") or instanceObject:IsA("Sparkles") then
            if Variables.Snapshot.EffectEnabled[instanceObject] == nil then
                local current = false
                if instanceObject:IsA("PostEffect") then
                    current = instanceObject.Enabled
                else
                    current = (instanceObject.Enabled ~= nil) and instanceObject.Enabled or true
                end
                Variables.Snapshot.EffectEnabled[instanceObject] = current
            end
            pcall(function()
                if instanceObject:IsA("PostEffect") then
                    instanceObject.Enabled = false
                else
                    if instanceObject.Enabled ~= nil then instanceObject.Enabled = false end
                end
            end)
            return
        end

        if instanceObject:IsA("PointLight") or instanceObject:IsA("SpotLight") or instanceObject:IsA("SurfaceLight") then
            if Variables.Snapshot.LightEnabled[instanceObject] == nil then
                Variables.Snapshot.LightEnabled[instanceObject] = instanceObject.Enabled
            end
            pcall(function() instanceObject.Enabled = false end)
            return
        end

        if instanceObject:IsA("Animator") then
            GuardAnimator(instanceObject)
            return
        end

        if instanceObject:IsA("Sound") then GuardSound(instanceObject); return end
        if Variables.Config.DisableVideoFrames and instanceObject:IsA("VideoFrame") then GuardVideoFrame(instanceObject); return end
        if Variables.Config.DisableViewportFrames and instanceObject:IsA("ViewportFrame") then GuardViewportFrame(instanceObject); return end

        DisableConstraint(instanceObject)
        SmoothifyAndNukeTextures(instanceObject)

        if Variables.Config.HidePlayerGuiWhileLowPower then
            local localPlayer = RbxService.Players.LocalPlayer
            local playerGui = localPlayer and localPlayer:FindFirstChild("PlayerGui")
            if instanceObject:IsA("ScreenGui") and playerGui and instanceObject.Parent == playerGui then
                if Variables.Snapshot.PlayerGuiStates[instanceObject] == nil then
                    Variables.Snapshot.PlayerGuiStates[instanceObject] = instanceObject.Enabled
                end
                pcall(function() instanceObject.Enabled = false end)
            end
        end
    end

    local function ApplyBatch()
        local workspaceDescendants = RbxService.Workspace:GetDescendants()
        for index = 1, #workspaceDescendants do ApplyToInstance(workspaceDescendants[index]) end

        local lightingDescendants = RbxService.Lighting:GetDescendants()
        for index = 1, #lightingDescendants do ApplyToInstance(lightingDescendants[index]) end

        local soundDescendants = RbxService.SoundService:GetDescendants()
        for index = 1, #soundDescendants do ApplyToInstance(soundDescendants[index]) end

        local localPlayer = RbxService.Players.LocalPlayer
        if Variables.Config.HidePlayerGuiWhileLowPower and localPlayer then
            local playerGui = localPlayer:FindFirstChild("PlayerGui")
            if playerGui then
                local guiChildren = playerGui:GetChildren()
                for index = 1, #guiChildren do ApplyToInstance(guiChildren[index]) end
            end
        end
        if localPlayer and localPlayer.Character then
            local characterDescendants = localPlayer.Character:GetDescendants()
            for index = 1, #characterDescendants do ApplyToInstance(characterDescendants[index]) end
        end
    end

    local function WatchForNewInstances()
        local maid = Variables.Maids.UltraAFK
        maid.WSAdd = RbxService.Workspace.DescendantAdded:Connect(function(instanceObject) if Variables.RunFlag then ApplyToInstance(instanceObject) end end)
        maid.LightAdd = RbxService.Lighting.DescendantAdded:Connect(function(instanceObject) if Variables.RunFlag then ApplyToInstance(instanceObject) end end)
        maid.SoundAdd = RbxService.SoundService.DescendantAdded:Connect(function(instanceObject) if Variables.RunFlag then ApplyToInstance(instanceObject) end end)

        local localPlayer = RbxService.Players.LocalPlayer
        if localPlayer then
            local function SetupPlayerGui(playerGui)
                if not playerGui or not playerGui:IsA("PlayerGui") then return end
                maid.PGAdd = playerGui.DescendantAdded:Connect(function(instanceObject) if Variables.RunFlag then ApplyToInstance(instanceObject) end end)
                if Variables.RunFlag and Variables.Config.HidePlayerGuiWhileLowPower then
                    local children = playerGui:GetChildren()
                    for index = 1, #children do ApplyToInstance(children[index]) end
                end
            end
            maid.PGWatcher = localPlayer.ChildAdded:Connect(SetupPlayerGui)
            SetupPlayerGui(localPlayer:FindFirstChild("PlayerGui"))

            maid.CharAdded = localPlayer.CharacterAdded:Connect(function(character)
                if Variables.RunFlag then
                    local descendants = character:GetDescendants()
                    for index = 1, #descendants do ApplyToInstance(descendants[index]) end
                    -- anchor again if needed
                end
            end)
        end
    end

    local function AnchorCharacter()
        if not Variables.Config.AnchorCharacterWhileLowPower then return end
        local localPlayer = RbxService.Players.LocalPlayer
        if not localPlayer or not localPlayer.Character then return end
        local humanoid = localPlayer.Character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            Variables.Snapshot.HumanoidProps.WalkSpeed = humanoid.WalkSpeed
            Variables.Snapshot.HumanoidProps.JumpPower = humanoid.JumpPower
            Variables.Snapshot.HumanoidProps.AutoRotate = humanoid.AutoRotate
            Variables.Snapshot.HumanoidProps.PlatformStand = humanoid.PlatformStand
            pcall(function()
                humanoid.WalkSpeed = 0
                humanoid.JumpPower = 0
                humanoid.AutoRotate = false
                humanoid.PlatformStand = true
            end)
        end
        local characterDescendants = localPlayer.Character:GetDescendants()
        for index = 1, #characterDescendants do
            local part = characterDescendants[index]
            if part:IsA("BasePart") then
                Variables.Snapshot.CharacterAnchored[part] = part.Anchored
                pcall(function()
                    part.Anchored = true
                    part.AssemblyLinearVelocity = Vector3.new()
                    part.AssemblyAngularVelocity = Vector3.new()
                end)
                if Variables.Config.RemoveLocalNetworkOwnership then
                    pcall(function() part:SetNetworkOwner(nil) end)
                end
            end
        end
    end

    local function UnanchorCharacter()
        local localPlayer = RbxService.Players.LocalPlayer
        if not localPlayer or not localPlayer.Character then return end
        local humanoid = localPlayer.Character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            local props = Variables.Snapshot.HumanoidProps
            pcall(function()
                if props.WalkSpeed ~= nil then humanoid.WalkSpeed = props.WalkSpeed end
                if props.JumpPower ~= nil then humanoid.JumpPower = props.JumpPower end
                if props.AutoRotate ~= nil then humanoid.AutoRotate = props.AutoRotate end
                if props.PlatformStand ~= nil then humanoid.PlatformStand = props.PlatformStand end
            end)
            Variables.Snapshot.HumanoidProps = { WalkSpeed=nil, JumpPower=nil, AutoRotate=nil, PlatformStand=nil }
        end
        for basePart, wasAnchored in pairs(Variables.Snapshot.CharacterAnchored) do
            if basePart and basePart.Parent then
                pcall(function() basePart.Anchored = wasAnchored end)
            end
            Variables.Snapshot.CharacterAnchored[basePart] = nil
        end
    end

    local function TryReduceSimulationRadius()
        if not Variables.Config.ReduceSimulationRadius then return end
        local localPlayer = RbxService.Players.LocalPlayer
        if not localPlayer then return end
        local setHiddenProperty = rawget(_G, "sethiddenproperty") or (getgenv and getgenv().sethiddenproperty) or _G.sethiddenproperty
        if typeof(setHiddenProperty) == "function" then
            for _, propertyName in ipairs({ "SimulationRadius", "MaxSimulationRadius", "MaximumSimulationRadius" }) do
                pcall(function() setHiddenProperty(localPlayer, propertyName, 0) end)
            end
        end
        local setSimulationRadius = rawget(_G, "setsimulationradius") or (getgenv and getgenv().setsimulationradius)
        if typeof(setSimulationRadius) == "function" then pcall(function() setSimulationRadius(0) end) end
    end

    local function DisableRenderingIfConfigured()
        if not Variables.Config.UseMinimumGraphicsQuality then
            Variables.Snapshot.RenderingEnabled = true
            return
        end
        local callSucceeded, wasEnabled = pcall(function() return RbxService.RunService:Is3dRenderingEnabled() end)
        Variables.Snapshot.RenderingEnabled = callSucceeded and wasEnabled or true
        pcall(function() RbxService.RunService:Set3dRenderingEnabled(false) end)
    end

    -- Enter/Exit
    local function EnterLowPower()
        if Variables.RunFlag then return end
        Variables.RunFlag = true

        ApplyUltraPreset()

        -- Sync UI with Config
        for key, option in pairs(UI.Options) do
            local id = option.Id
            if id and Variables.Config[id] ~= nil and option.Value ~= nil then
                Variables.Config[id] = option.Value
            end
        end

        DisableRenderingIfConfigured()

        local camera = workspace.CurrentCamera
        if camera then
            Variables.Snapshot.CameraType = camera.CameraType
            Variables.Snapshot.CameraSubject = camera.CameraSubject
            Variables.Snapshot.CameraFOV = camera.FieldOfView
            pcall(function() camera.CameraType = Enum.CameraType.Scriptable end)
        end

        local settingsSucceeded, userGameSettings = pcall(function() return UserSettings():GetService("UserGameSettings") end)
        if settingsSucceeded and userGameSettings and typeof(userGameSettings.MasterVolume) == "number" then
            Variables.Snapshot.UserMasterVolume = userGameSettings.MasterVolume
            pcall(function() userGameSettings.MasterVolume = 0 end)
        end

        TrySetFpsCap(Variables.Config.TargetFpsWhileLowPower)
        if Variables.Config.HideCoreGuiWhileLowPower then DisableCoreGui() end
        if Variables.Config.LowerLightingWhileLowPower then LowerLighting() end
        if Variables.Config.UseMinimumGraphicsQuality then LowerGraphicsQuality() end

        AnchorCharacter()
        TryReduceSimulationRadius()
        RemoveGrass()

        if Variables.Config.PauseAllTweens then
            local tweensOk, playingTweens = pcall(function() return RbxService.TweenService:GetPlayingTweens() end)
            if tweensOk and playingTweens then
                for tweenIndex = 1, #playingTweens do
                    local tween = playingTweens[tweenIndex]
                    pcall(function() tween:Pause() end)
                end
            end
        end

        ApplyBatch()
        WatchForNewInstances()
        print("[Ultra AFK] Enabled.")
    end

    local function RestoreInstanceStates()
        local Snapshot, State = Variables.Snapshot, Variables.State
        for instanceObject, enabledValue in pairs(Snapshot.EffectEnabled) do
            if instanceObject and instanceObject.Parent then
                pcall(function()
                    if instanceObject:IsA("PostEffect") then
                        instanceObject.Enabled = enabledValue
                    else
                        if instanceObject.Enabled ~= nil then instanceObject.Enabled = enabledValue end
                    end
                end)
            end
            Snapshot.EffectEnabled[instanceObject] = nil
        end
        for lightObject, wasEnabled in pairs(Snapshot.LightEnabled) do
            if lightObject and lightObject.Parent then pcall(function() lightObject.Enabled = wasEnabled end) end
            Snapshot.LightEnabled[lightObject] = nil
        end
        for soundObject, oldVolume in pairs(Snapshot.SoundVolume) do
            if soundObject and soundObject.Parent then pcall(function() soundObject.Volume = oldVolume end) end
            Snapshot.SoundVolume[soundObject] = nil
        end
        for viewportFrame, wasVisible in pairs(Snapshot.ViewportFrameVisible) do
            if viewportFrame and viewportFrame.Parent then pcall(function() viewportFrame.Visible = wasVisible end) end
            Snapshot.ViewportFrameVisible[viewportFrame] = nil
        end
        for videoFrame, wasPlaying in pairs(Snapshot.VideoFramePlaying) do
            if videoFrame and videoFrame.Parent then pcall(function() videoFrame.Playing = wasPlaying end) end
            Snapshot.VideoFramePlaying[videoFrame] = nil
        end
        for constraintObject, wasEnabled in pairs(State.ConstraintStates) do
            if constraintObject and constraintObject.Parent and constraintObject.Enabled ~= nil then
                pcall(function() constraintObject.Enabled = wasEnabled end)
            end
            State.ConstraintStates[constraintObject] = nil
        end
        for basePart, saved in pairs(Snapshot.PartMaterial) do
            if basePart and basePart.Parent then
                pcall(function()
                    basePart.Material = saved.Material
                    basePart.Reflectance = saved.Reflectance
                    basePart.CastShadow = saved.CastShadow
                end)
            end
            Snapshot.PartMaterial[basePart] = nil
        end
        for decal, savedTransparency in pairs(Snapshot.DecalTransparency) do
            if decal and decal.Parent then pcall(function() decal.Transparency = savedTransparency end) end
            Snapshot.DecalTransparency[decal] = nil
        end
    end

    local function RestorePlayerGui()
        for screenGui, wasEnabled in pairs(Variables.Snapshot.PlayerGuiStates) do
            if screenGui and screenGui.Parent then
                pcall(function() screenGui.Enabled = wasEnabled and true or false end)
            end
            Variables.Snapshot.PlayerGuiStates[screenGui] = nil
        end
    end

    local function ExitLowPower()
        if not Variables.RunFlag then return end
        Variables.RunFlag = false

        pcall(function() RbxService.RunService:Set3dRenderingEnabled(Variables.Snapshot.RenderingEnabled) end)

        local camera = workspace.CurrentCamera
        if camera then
            if Variables.Snapshot.CameraType then pcall(function() camera.CameraType = Variables.Snapshot.CameraType end) end
            if Variables.Snapshot.CameraSubject then
                pcall(function() camera.CameraSubject = Variables.Snapshot.CameraSubject end)
            else
                local localPlayer = RbxService.Players.LocalPlayer
                if localPlayer and localPlayer.Character then
                    local humanoid = localPlayer.Character:FindFirstChildOfClass("Humanoid")
                    if humanoid then pcall(function() camera.CameraSubject = humanoid end) end
                end
            end
            if Variables.Snapshot.CameraFOV then
                pcall(function() camera.FieldOfView = Variables.Snapshot.CameraFOV end)
            else
                pcall(function() camera.FieldOfView = 70 end)
            end
        end

        local settingsSucceeded, userGameSettings = pcall(function() return UserSettings():GetService("UserGameSettings") end)
        if settingsSucceeded and userGameSettings and Variables.Snapshot.UserMasterVolume ~= nil then
            pcall(function() userGameSettings.MasterVolume = Variables.Snapshot.UserMasterVolume end)
            Variables.Snapshot.UserMasterVolume = nil
        end

        TrySetFpsCap(60)
        if Variables.Config.ForceClearBlurOnRestore then
            task.defer(function()
                local lighting = RbxService.Lighting
                local children = lighting:GetChildren()
                for index = 1, #children do
                    local effect = children[index]
                    if effect:IsA("BlurEffect") then pcall(function() effect.Enabled = false; effect.Size = 0 end) end
                    if effect:IsA("DepthOfFieldEffect") then pcall(function() effect.Enabled = false end) end
                end
            end)
        end

        UnanchorCharacter()
        ReleaseAnimatorGuards()

        for soundInstance, _ in pairs(Variables.State.SoundGuards) do Unguard(Variables.State.SoundGuards, soundInstance) end
        for viewportFrame, _ in pairs(Variables.State.ViewportGuards) do Unguard(Variables.State.ViewportGuards, viewportFrame) end
        for videoFrame, _ in pairs(Variables.State.VideoGuards) do Unguard(Variables.State.VideoGuards, videoFrame) end
        Variables.State.SoundGuards, Variables.State.ViewportGuards, Variables.State.VideoGuards = {}, {}, {}

        if Variables.Config.LowerLightingWhileLowPower then RestoreLighting() end
        if Variables.Config.UseMinimumGraphicsQuality then RestoreGraphicsQuality() end
        if Variables.Config.HideCoreGuiWhileLowPower then RestoreCoreGui() end
        RestorePlayerGui()
        RestoreGrass()
        RestoreInstanceStates()

        print("[Ultra AFK] Disabled.")
    end

    -- UI
    local groupbox = UI.Tabs.Misc:AddRightGroupbox("AFK Optimizer", "power")
    groupbox:AddToggle("UltraAFKToggle", {
        Text = "Ultra AFK Mode",
        Tooltip = "Toggle the AFK optimizer [ON/OFF].",
        Default = false,
    })

    groupbox:AddDivider()
    groupbox:AddSlider("UltraAFK_TargetFpsWhileLowPower", {
        Label = "Target FPS",
        Min = 1, Max = 60,
        Default = Variables.Config.TargetFpsWhileLowPower,
        Suffix = "FPS",
        Callback = function(value) Variables.Config.TargetFpsWhileLowPower = math.floor(value) end,
        Id = "TargetFpsWhileLowPower",
    })

    groupbox:AddDivider()
    local function AddToggle(idKey, labelText, defaultValue, tooltipText)
        return groupbox:AddToggle("UltraAFK_" .. idKey, {
            Text = labelText,
            Default = defaultValue,
            Tooltip = tooltipText,
            Id = idKey,
        })
    end

    local presetToggle              = AddToggle("UltraPreset", "Ultra Preset", Variables.Config.UltraPreset, "Aggressive settings for maximum savings.")
    local reversibleToggle          = AddToggle("ReversibleMode", "Reversible Mode", Variables.Config.ReversibleMode, "Avoid destructive changes.")
    groupbox:AddDivider()
    AddToggle("HidePlayerGuiWhileLowPower", "Hide PlayerGui", Variables.Config.HidePlayerGuiWhileLowPower)
    AddToggle("HideCoreGuiWhileLowPower",  "Hide CoreGui",   Variables.Config.HideCoreGuiWhileLowPower)
    AddToggle("LowerLightingWhileLowPower","Lower Lighting", Variables.Config.LowerLightingWhileLowPower)
    AddToggle("UseMinimumGraphicsQuality", "Use Minimum Graphics", Variables.Config.UseMinimumGraphicsQuality)
    AddToggle("DisableViewportFrames",     "Disable ViewportFrames", Variables.Config.DisableViewportFrames)
    AddToggle("DisableVideoFrames",        "Disable VideoFrames", Variables.Config.DisableVideoFrames)
    AddToggle("PauseCharacterAnimations",  "Pause Character Animations", Variables.Config.PauseCharacterAnimations)
    AddToggle("PauseAllAnimations",        "Pause All Animations", Variables.Config.PauseAllAnimations)
    AddToggle("PauseAllTweens",            "Pause All Tweens", Variables.Config.PauseAllTweens)
    AddToggle("AnchorCharacterWhileLowPower","Anchor Character", Variables.Config.AnchorCharacterWhileLowPower)
    AddToggle("ReduceSimulationRadius",    "Reduce Simulation Radius", Variables.Config.ReduceSimulationRadius)
    AddToggle("RemoveLocalNetworkOwnership","Remove Network Ownership", Variables.Config.RemoveLocalNetworkOwnership)
    AddToggle("DisableConstraintsAggressive","Disable Constraints", Variables.Config.DisableConstraintsAggressive)
    AddToggle("RemoveGrassDecoration",     "Remove Grass", Variables.Config.RemoveGrassDecoration)
    AddToggle("SmoothPlasticEverywhere",   "Force SmoothPlastic", Variables.Config.SmoothPlasticEverywhere)
    AddToggle("GraySkyEnabled",            "Make Sky Gray", Variables.Config.GraySkyEnabled)
    AddToggle("FullBrightEnabled",         "Full Bright Lighting", Variables.Config.FullBrightEnabled)
    AddToggle("ForceClearBlurOnRestore",   "Force Clear Blur on Restore", Variables.Config.ForceClearBlurOnRestore)
    AddToggle("DestroyEmitters",           "Destroy Emitters (Irreversible)", Variables.Config.DestroyEmitters)
    AddToggle("NukeTextures",              "Nuke Textures (Irreversible)", Variables.Config.NukeTextures)

    -- Wiring
    UI.Toggles.UltraAFKToggle:OnChanged(function(enabledState)
        if enabledState then
            EnterLowPower()
            Variables.Maids.UltraAFK:GiveTask(function() Variables.RunFlag = false end)
        else
            ExitLowPower()
            Variables.Maids.UltraAFK:DoCleaning()
        end
    end)

    local function OnPresetChanged(value)
        Variables.Config.UltraPreset = value
        ApplyUltraPreset()
        -- sync visible UI controls to the Config snapshot
        for key, optionObj in pairs(UI.Options) do
            local id = optionObj.Id
            if id and Variables.Config[id] ~= nil and optionObj.Set then
                optionObj:Set(Variables.Config[id], false)
            end
        end
    end
    presetToggle:OnChanged(OnPresetChanged)
    reversibleToggle:OnChanged(OnPresetChanged)

    -- Sync option changes into Config generically
    for optionKey, optionObj in pairs(UI.Options) do
        local id = optionObj.Id
        if id and Variables.Config[id] ~= nil and optionObj.OnChanged then
            optionObj:OnChanged(function(newValue) Variables.Config[id] = newValue end)
        end
    end

    -- Return API to the loader
    local function Stop()
        if UI.Toggles.UltraAFKToggle and UI.Toggles.UltraAFKToggle.Value then
            UI.Toggles.UltraAFKToggle:SetValue(false)
        end
        ExitLowPower()
        Variables.Maids.UltraAFK:DoCleaning()
    end

    return { Name = "UltraAFK", Stop = Stop }
end
end
