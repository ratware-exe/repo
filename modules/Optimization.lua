-- modules/Optimization.lua
do
    return function(UI)
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv = (getgenv and getgenv()) or _G
        GlobalEnv.Signal = GlobalEnv.Signal or loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()
        local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
-- modules/Optimization.lua
do
    return function(UI)
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid       = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        -- ====================================================================
        -- Variables / State (single table per your rules)
        -- ====================================================================
        local Variables = {
            Maids = {
                Optimization = Maid.new(),
                Watchers     = Maid.new(),
                EmitterGuards= Maid.new(),  -- connections guarding emitter .Enabled when StopParticleSystems is ON
            },

            Config = {
                Enabled = false,

                -- Rendering / UI
                DisableThreeDRendering = false,
                TargetFramesPerSecond  = 30,
                HidePlayerGui          = true,
                HideCoreGui            = true,
                DisableViewportFrames  = true,
                DisableVideoFrames     = true,
                MuteAllSounds          = true,

                -- Animation / Motion
                PauseCharacterAnimations = true,
                PauseOtherAnimations     = true,   -- props/UI/NPCs you see client‑side; not other players’ tracks
                FreezeWorldAssemblies    = false,  -- reversible (anchors non‑character parts)
                DisableConstraints       = true,   -- reversible (excludes Motor6D)

                -- Physics / Network
                AnchorCharacter           = true,
                ReduceSimulationRadius    = true,  -- best‑effort
                RemoveLocalNetworkOwnership = true,

                -- Materials / Effects
                StopParticleSystems      = true,   -- reversible
                DestroyEmitters          = false,  -- irreversible
                SmoothPlasticEverywhere  = true,   -- reversible
                HideDecals               = true,   -- reversible
                NukeTextures             = false,  -- irreversible

                RemoveGrassDecoration    = true,   -- best‑effort
                DisablePostEffects       = true,   -- reversible (Bloom/CC/DoF/SunRays/Blur)
                GraySky                  = true,   -- reversible
                FullBright               = true,   -- reversible
                UseMinimumQuality        = true,   -- reversible
                ForceClearBlurOnRestore  = true,

                -- Water replacement (visual only)
                ReplaceWaterWithBlock      = false,
                WaterBlockTransparencyPercent = 25, -- 0..100
                WaterBlockColorR = 30,
                WaterBlockColorG = 85,
                WaterBlockColorB = 255,
                WaterBlockY       = 0,
                WaterBlockSizeX   = 20000,
                WaterBlockSizeZ   = 20000,
                WaterBlockThickness= 2,
            },

            Snapshot = {
                RenderingEnabled = true,

                PlayerGuiEnabled   = {},  -- ScreenGui -> bool
                CoreGuiState       = {},  -- CoreGuiType -> bool

                ViewportVisible    = {},  -- ViewportFrame -> bool
                VideoPlaying       = {},  -- VideoFrame -> bool
                SoundProps         = {},  -- Sound -> { Volume, Playing }

                AnimatorGuards     = {},  -- Animator -> { Tracks = {track->oldSpeed}, Conns = {...} }
                AnimateScripts     = {},  -- LocalScript "Animate" under character -> bool

                ConstraintEnabled  = {},  -- Constraint -> bool
                PartAnchored       = {},  -- BasePart -> bool (frozen)
                CharacterAnchored  = {},  -- BasePart -> bool

                PartMaterial       = {},  -- BasePart -> { Material, Reflectance, CastShadow }
                DecalTransparency  = {},  -- Decal/Texture -> number
                EmitterEnabled     = {},  -- ParticleEmitter/Trail/Beam/Fire/Smoke -> bool

                LightingProps = {         -- to restore
                    GlobalShadows = nil, Brightness = nil, ClockTime = nil,
                    Ambient = nil, OutdoorAmbient = nil,
                    EnvironmentDiffuseScale = nil, EnvironmentSpecularScale = nil,
                },
                PostEffects      = {},     -- Effect -> Enabled
                TerrainDecoration= nil,    -- bool
                SavedQuality     = nil,    -- Enum.QualityLevel

                WaterTransparency= nil,    -- number (Terrain)
            },

            Irreversible = {
                EmittersDestroyed = false,
                TexturesNuked     = false,
            },

            State = {
                WaterProxyPart            = nil,
                LightingApplyScheduled    = false, -- debounce flag for ApplyLowLighting
            },
        }

        -- ====================================================================
        -- Helpers / utilities
        -- ====================================================================

        local function StoreOnce(mapTable, key, value)
            if mapTable[key] == nil then mapTable[key] = value end
        end

        local function EachDescendantChunked(rootInstance, predicateFn, actionFn)
            local processedCount = 0
            local listOfDescendants = rootInstance:GetDescendants()
            for arrayIndex = 1, #listOfDescendants do
                local instanceObject = listOfDescendants[arrayIndex]
                if not Variables.Config.Enabled then break end
                if predicateFn(instanceObject) then
                    actionFn(instanceObject)
                end
                processedCount += 1
                if processedCount % 500 == 0 then task.wait() end
            end
        end

        local function TrySetFramesPerSecondCap(targetFps)
            local candidates = {
                (getgenv and getgenv().setfpscap),
                rawget(_G, "setfpscap"),
                rawget(_G, "set_fps_cap"),
                rawget(_G, "setfps"),
                rawget(_G, "setfps_max"),
            }
            for candidateIndex = 1, #candidates do
                local functionObject = candidates[candidateIndex]
                if typeof(functionObject) == "function" then
                    local operationSucceeded = pcall(functionObject, targetFps)
                    if operationSucceeded then return true end
                end
            end
            return false
        end

        -- ====================================================================
        -- Sounds
        -- ====================================================================

        local function GuardSound(soundInstance)
            if not soundInstance or not soundInstance:IsA("Sound") then return end
            StoreOnce(Variables.Snapshot.SoundProps, soundInstance, {
                Volume = (function() local ok, v = pcall(function() return soundInstance.Volume end) return ok and v or 1 end)(),
                Playing= (function() local ok, v = pcall(function() return soundInstance.Playing end) return ok and v or false end)(),
            })
            pcall(function()
                soundInstance.Playing = false
                soundInstance.Volume  = 0
            end)
            local connectionVolume = soundInstance:GetPropertyChangedSignal("Volume"):Connect(function()
                if Variables.Config.Enabled and Variables.Config.MuteAllSounds then
                    pcall(function() soundInstance.Volume = 0 end)
                end
            end)
            local connectionPlaying = soundInstance:GetPropertyChangedSignal("Playing"):Connect(function()
                if Variables.Config.Enabled and Variables.Config.MuteAllSounds and soundInstance.Playing then
                    pcall(function() soundInstance.Playing = false end)
                end
            end)
            Variables.Maids.Watchers:GiveTask(connectionVolume)
            Variables.Maids.Watchers:GiveTask(connectionPlaying)
        end

        local function ApplyMuteAllSounds()
            EachDescendantChunked(game, function(instanceObject)
                return instanceObject:IsA("Sound")
            end, GuardSound)
        end

        local function RestoreSounds()
            for soundInstance, properties in pairs(Variables.Snapshot.SoundProps) do
                pcall(function()
                    if soundInstance and soundInstance.Parent then
                        soundInstance.Volume  = properties.Volume
                        soundInstance.Playing = properties.Playing
                    end
                end)
                Variables.Snapshot.SoundProps[soundInstance] = nil
            end
        end

        -- ====================================================================
        -- Animations (character + other client‑driven animators)
        -- ====================================================================

        local function ShouldPauseAnimator(animatorObject)
            local localPlayer = RbxService.Players.LocalPlayer
            local character   = localPlayer and localPlayer.Character
            local isCharacter = character and animatorObject:IsDescendantOf(character)
            if isCharacter then
                return Variables.Config.PauseCharacterAnimations
            else
                return Variables.Config.PauseOtherAnimations
            end
        end

        local function GuardAnimator(animatorObject)
            if not animatorObject or not animatorObject:IsA("Animator") then return end
            if not ShouldPauseAnimator(animatorObject) then return end
            if Variables.Snapshot.AnimatorGuards[animatorObject] then return end

            local guardBundle = { Tracks = {}, Conns = {} }
            Variables.Snapshot.AnimatorGuards[animatorObject] = guardBundle

            local function CaptureAndFreeze(trackObject)
                if guardBundle.Tracks[trackObject] == nil then
                    local operationSucceeded, speedValue = pcall(function() return trackObject.Speed end)
                    guardBundle.Tracks[trackObject] = (operationSucceeded and speedValue) or 1
                end
                pcall(function() trackObject:AdjustSpeed(0) end)
                table.insert(guardBundle.Conns, trackObject.Stopped:Connect(function()
                    guardBundle.Tracks[trackObject] = nil
                end))
            end

            local listSucceeded, list = pcall(function() return animatorObject:GetPlayingAnimationTracks() end)
            if listSucceeded and list then
                for listIndex = 1, #list do CaptureAndFreeze(list[listIndex]) end
            end

            table.insert(guardBundle.Conns, animatorObject.AnimationPlayed:Connect(function(newTrack)
                if Variables.Config.Enabled and ShouldPauseAnimator(animatorObject) then
                    CaptureAndFreeze(newTrack)
                end
            end))

            table.insert(guardBundle.Conns, animatorObject.AncestryChanged:Connect(function(_, parentNow)
                if parentNow == nil then
                    for connIndex = 1, #guardBundle.Conns do
                        local connectionObject = guardBundle.Conns[connIndex]
                        if connectionObject then connectionObject:Disconnect() end
                    end
                    Variables.Snapshot.AnimatorGuards[animatorObject] = nil
                end
            end))
        end

        local function DisableCharacterAnimateScripts(restoreBack)
            local localPlayer = RbxService.Players.LocalPlayer
            local character   = localPlayer and localPlayer.Character
            if not character then return end
            local childrenArray = character:GetChildren()
            for childIndex = 1, #childrenArray do
                local childObject = childrenArray[childIndex]
                if childObject:IsA("LocalScript") and childObject.Name == "Animate" then
                    if restoreBack then
                        local previous = Variables.Snapshot.AnimateScripts[childObject]
                        Variables.Snapshot.AnimateScripts[childObject] = nil
                        if previous ~= nil then pcall(function() childObject.Enabled = previous end) end
                    else
                        StoreOnce(Variables.Snapshot.AnimateScripts, childObject,
                            (function() local ok, v = pcall(function() return childObject.Enabled end) return ok and v or true end)())
                        pcall(function() childObject.Enabled = false end)
                    end
                end
            end
        end

        local function ReleaseAnimatorGuards()
            for animatorObject, bundle in pairs(Variables.Snapshot.AnimatorGuards) do
                if bundle and bundle.Tracks then
                    for trackObject, oldSpeed in pairs(bundle.Tracks) do
                        pcall(function() trackObject:AdjustSpeed(oldSpeed or 1) end)
                    end
                end
                if bundle and bundle.Conns then
                    for connIndex = 1, #bundle.Conns do
                        local connectionObject = bundle.Conns[connIndex]
                        if connectionObject then connectionObject:Disconnect() end
                    end
                end
                Variables.Snapshot.AnimatorGuards[animatorObject] = nil
            end
        end

        -- ====================================================================
        -- Particles / decals / materials
        -- ====================================================================

        local function IsEmitter(instanceObject)
            return instanceObject:IsA("ParticleEmitter")
                or instanceObject:IsA("Trail")
                or instanceObject:IsA("Beam")
                or instanceObject:IsA("Fire")
                or instanceObject:IsA("Smoke")
        end

        local function StopEmitter(instanceObject)
            local enabledNow
            local readOk = pcall(function() enabledNow = instanceObject.Enabled end)
            StoreOnce(Variables.Snapshot.EmitterEnabled, instanceObject, readOk and enabledNow or true)
            pcall(function() instanceObject.Enabled = false end)

            -- Guard while ON
            local changedConn = instanceObject:GetPropertyChangedSignal("Enabled"):Connect(function()
                if Variables.Config.Enabled and Variables.Config.StopParticleSystems then
                    pcall(function() instanceObject.Enabled = false end)
                end
            end)
            Variables.Maids.EmitterGuards:GiveTask(changedConn)
            local ancestryConn = instanceObject.AncestryChanged:Connect(function(_, parentNow)
                if parentNow == nil then
                    Variables.Snapshot.EmitterEnabled[instanceObject] = nil
                end
            end)
            Variables.Maids.EmitterGuards:GiveTask(ancestryConn)
        end

        local function RestoreEmitters()
            Variables.Maids.EmitterGuards:DoCleaning() -- disconnect all .Enabled guards
            for emitterInstance, oldEnabled in pairs(Variables.Snapshot.EmitterEnabled) do
                pcall(function()
                    if emitterInstance and emitterInstance.Parent then
                        emitterInstance.Enabled = oldEnabled and true or false
                    end
                end)
                Variables.Snapshot.EmitterEnabled[emitterInstance] = nil
            end
        end

        local function DestroyEmittersIrreversible(instanceObject)
            if IsEmitter(instanceObject) then
                pcall(function() instanceObject:Destroy() end)
            end
        end

        local function HideDecalOrTexture(instanceObject)
            if instanceObject:IsA("Decal") or instanceObject:IsA("Texture") then
                StoreOnce(Variables.Snapshot.DecalTransparency, instanceObject,
                    (function() local ok, v = pcall(function() return instanceObject.Transparency end) return ok and v or 0 end)())
                pcall(function() instanceObject.Transparency = 1 end)
            end
        end

        local function RestoreDecalsAndTextures()
            for decalOrTexture, oldTransparency in pairs(Variables.Snapshot.DecalTransparency) do
                pcall(function()
                    if decalOrTexture and decalOrTexture.Parent then
                        decalOrTexture.Transparency = oldTransparency
                    end
                end)
                Variables.Snapshot.DecalTransparency[decalOrTexture] = nil
            end
        end

        local function SmoothPlasticPart(instanceObject)
            if not instanceObject:IsA("BasePart") then return end
            local character = RbxService.Players.LocalPlayer.Character
            if character and instanceObject:IsDescendantOf(character) then return end
            StoreOnce(Variables.Snapshot.PartMaterial, instanceObject, {
                Material    = instanceObject.Material,
                Reflectance = instanceObject.Reflectance,
                CastShadow  = instanceObject.CastShadow,
            })
            pcall(function()
                instanceObject.Material    = Enum.Material.SmoothPlastic
                instanceObject.Reflectance = 0
                instanceObject.CastShadow  = false
            end)
        end

        local function RestorePartMaterials()
            local processedCount = 0
            for partInstance, props in pairs(Variables.Snapshot.PartMaterial) do
                pcall(function()
                    if partInstance and partInstance.Parent then
                        partInstance.Material    = props.Material
                        partInstance.Reflectance = props.Reflectance
                        partInstance.CastShadow  = props.CastShadow
                    end
                end)
                Variables.Snapshot.PartMaterial[partInstance] = nil
                processedCount += 1
                if processedCount % 500 == 0 then task.wait() end
            end
        end

        local function NukeTexturesIrreversible(instanceObject)
            if instanceObject:IsA("Decal") or instanceObject:IsA("Texture") or instanceObject:IsA("SurfaceAppearance") then
                pcall(function() instanceObject:Destroy() end)
            elseif instanceObject:IsA("MeshPart") or instanceObject:IsA("BasePart") then
                pcall(function() instanceObject.Material = Enum.Material.SmoothPlastic end)
            end
        end

        -- ====================================================================
        -- Freeze world, constraints, ownership
        -- ====================================================================

        local function FreezeWorldPart(instanceObject)
            if not instanceObject:IsA("BasePart") then return end
            local character = RbxService.Players.LocalPlayer.Character
            if character and instanceObject:IsDescendantOf(character) then return end
            if instanceObject:GetAttribute("WFYB_FrozenByOptimization") then return end
            StoreOnce(Variables.Snapshot.PartAnchored, instanceObject, instanceObject.Anchored)
            pcall(function()
                instanceObject.AssemblyLinearVelocity  = Vector3.new()
                instanceObject.AssemblyAngularVelocity = Vector3.new()
                instanceObject.Anchored = true
                instanceObject:SetAttribute("WFYB_FrozenByOptimization", true)
            end)
        end

        local function RestoreAnchoredParts()
            local counter = 0
            for partInstance, wasAnchored in pairs(Variables.Snapshot.PartAnchored) do
                pcall(function()
                    if partInstance and partInstance.Parent then
                        partInstance.Anchored = wasAnchored and true or false
                        partInstance:SetAttribute("WFYB_FrozenByOptimization", nil)
                    end
                end)
                Variables.Snapshot.PartAnchored[partInstance] = nil
                counter += 1
                if counter % 500 == 0 then task.wait() end
            end
            -- Safety: also untag any stragglers we anchored but missed in the map
            EachDescendantChunked(RbxService.Workspace, function(inst)
                return inst:IsA("BasePart") and inst:GetAttribute("WFYB_FrozenByOptimization") == true
            end, function(basePart)
                pcall(function()
                    basePart:SetAttribute("WFYB_FrozenByOptimization", nil)
                    -- If we didn’t snapshot it, fall back to unanchoring
                    if Variables.Snapshot.PartAnchored[basePart] == nil then basePart.Anchored = false end
                end)
            end)
        end

        local function DisableWorldConstraints()
            EachDescendantChunked(RbxService.Workspace, function(instanceObject)
                return instanceObject:IsA("Constraint") and not instanceObject:IsA("Motor6D")
            end, function(constraintInstance)
                StoreOnce(Variables.Snapshot.ConstraintEnabled, constraintInstance, constraintInstance.Enabled)
                pcall(function() constraintInstance.Enabled = false end)
            end)
        end

        local function RestoreWorldConstraints()
            local count = 0
            for constraintInstance, oldEnabled in pairs(Variables.Snapshot.ConstraintEnabled) do
                pcall(function()
                    if constraintInstance and constraintInstance.Parent then
                        constraintInstance.Enabled = oldEnabled and true or false
                    end
                end)
                Variables.Snapshot.ConstraintEnabled[constraintInstance] = nil
                count += 1
                if count % 500 == 0 then task.wait() end
            end
        end

        local function CharacterAnchorSet(anchorOn)
            local localPlayer = RbxService.Players.LocalPlayer
            local character   = localPlayer and localPlayer.Character
            if not character then return end
            local descendants = character:GetDescendants()
            for descIndex = 1, #descendants do
                local partInstance = descendants[descIndex]
                if partInstance:IsA("BasePart") then
                    StoreOnce(Variables.Snapshot.CharacterAnchored, partInstance, partInstance.Anchored)
                    pcall(function() partInstance.Anchored = anchorOn and true or false end)
                end
            end
        end

        local function ReduceSimulationRadius()
            if not Variables.Config.ReduceSimulationRadius then return end
            local localPlayer = RbxService.Players.LocalPlayer
            if not localPlayer then return end
            local setter = sethiddenproperty or set_hidden_property or set_hidden_prop
            if setter then
                pcall(function()
                    setter(localPlayer, "SimulationRadius", 0)
                    setter(localPlayer, "MaxSimulationRadius", 0)
                end)
            end
        end

        local function RemoveNetOwnership()
            if not Variables.Config.RemoveLocalNetworkOwnership then return end
            EachDescendantChunked(RbxService.Workspace, function(instanceObject)
                return instanceObject:IsA("BasePart")
            end, function(partInstance)
                pcall(function()
                    if not partInstance.Anchored then
                        partInstance:SetNetworkOwner(nil)
                    end
                end)
            end)
        end

        -- ====================================================================
        -- Lighting / PostFX / Grass
        -- ====================================================================

        local function SnapshotLighting()
            local L = RbxService.Lighting
            Variables.Snapshot.LightingProps.GlobalShadows          = L.GlobalShadows
            Variables.Snapshot.LightingProps.Brightness             = L.Brightness
            Variables.Snapshot.LightingProps.ClockTime              = L.ClockTime
            Variables.Snapshot.LightingProps.Ambient                = L.Ambient
            Variables.Snapshot.LightingProps.OutdoorAmbient         = L.OutdoorAmbient
            Variables.Snapshot.LightingProps.EnvironmentDiffuseScale= L.EnvironmentDiffuseScale
            Variables.Snapshot.LightingProps.EnvironmentSpecularScale= L.EnvironmentSpecularScale
        end

        local function ApplyLowLighting()
            -- debounced via Variables.State.LightingApplyScheduled
            local L = RbxService.Lighting
            pcall(function()
                L.GlobalShadows = false
                L.Brightness    = Variables.Config.FullBright and 2 or 1
                L.EnvironmentDiffuseScale  = 0
                L.EnvironmentSpecularScale = 0
                if Variables.Config.GraySky then
                    L.ClockTime      = 12
                    L.Ambient        = Color3.fromRGB(128, 128, 128)
                    L.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
                end
            end)
        end

        local function ScheduleApplyLowLighting()
            if Variables.State.LightingApplyScheduled then return end
            Variables.State.LightingApplyScheduled = true
            task.defer(function()
                if Variables.Config.Enabled and (Variables.Config.GraySky or Variables.Config.FullBright) then
                    ApplyLowLighting()
                end
                Variables.State.LightingApplyScheduled = false
            end)
        end

        local function DisablePostEffects()
            local L = RbxService.Lighting
            local children = L:GetChildren()
            for idx = 1, #children do
                local effect = children[idx]
                if effect:IsA("BlurEffect") or effect:IsA("SunRaysEffect") or effect:IsA("ColorCorrectionEffect")
                   or effect:IsA("BloomEffect") or effect:IsA("DepthOfFieldEffect") then
                    StoreOnce(Variables.Snapshot.PostEffects, effect, effect.Enabled)
                    pcall(function() effect.Enabled = false end)
                end
            end
        end

        local function RestorePostEffects()
            for effectInstance, wasEnabled in pairs(Variables.Snapshot.PostEffects) do
                pcall(function()
                    if effectInstance and effectInstance.Parent then
                        effectInstance.Enabled = wasEnabled and true or false
                    end
                end)
                Variables.Snapshot.PostEffects[effectInstance] = nil
            end
        end

        local function TerrainDecorationSet(disableOn)
            local terrain = RbxService.Workspace:FindFirstChildOfClass("Terrain")
            if not terrain then return end
            if Variables.Snapshot.TerrainDecoration == nil then
                local ok, existing = pcall(function() return terrain.Decoration end)
                if ok then Variables.Snapshot.TerrainDecoration = existing end
            end
            pcall(function()
                if typeof(terrain.Decoration) == "boolean" then
                    terrain.Decoration = not disableOn
                end
            end)
            if RbxService.MaterialService then
                pcall(function()
                    RbxService.MaterialService.FallbackMaterial = disableOn and Enum.Material.SmoothPlastic or Enum.Material.Plastic
                end)
            end
        end

        local function ApplyQualityMinimum()
            if Variables.Snapshot.SavedQuality == nil then
                local ok, level = pcall(function() return settings().Rendering.QualityLevel end)
                if ok then Variables.Snapshot.SavedQuality = level end
            end
            pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
        end

        local function RestoreQuality()
            if Variables.Snapshot.SavedQuality ~= nil then
                pcall(function() settings().Rendering.QualityLevel = Variables.Snapshot.SavedQuality end)
                Variables.Snapshot.SavedQuality = nil
            end
        end

        -- ====================================================================
        -- Viewport/Video frames (Workspace + PlayerGui + CoreGui)
        -- ====================================================================

        local function DisableViewportAndVideoFramesScan()
            local function handleRoot(rootGui)
                if not rootGui then return end
                EachDescendantChunked(rootGui, function(inst)
                    return inst:IsA("ViewportFrame") or inst:IsA("VideoFrame")
                end, function(frame)
                    if frame:IsA("ViewportFrame") and Variables.Config.DisableViewportFrames then
                        StoreOnce(Variables.Snapshot.ViewportVisible, frame, frame.Visible)
                        pcall(function() frame.Visible = false end)
                    elseif frame:IsA("VideoFrame") and Variables.Config.DisableVideoFrames then
                        StoreOnce(Variables.Snapshot.VideoPlaying, frame, frame.Playing)
                        pcall(function() frame.Playing = false end)
                    end
                end)
            end
            handleRoot(RbxService.Players.LocalPlayer and RbxService.Players.LocalPlayer:FindFirstChildOfClass("PlayerGui"))
            handleRoot(RbxService.CoreGui)
        end

        local function RestoreViewportAndVideoFrames()
            for frame, wasVisible in pairs(Variables.Snapshot.ViewportVisible) do
                pcall(function() if frame and frame.Parent then frame.Visible = wasVisible and true or false end end)
                Variables.Snapshot.ViewportVisible[frame] = nil
            end
            for frame, wasPlaying in pairs(Variables.Snapshot.VideoPlaying) do
                pcall(function() if frame and frame.Parent then frame.Playing = wasPlaying and true or false end end)
                Variables.Snapshot.VideoPlaying[frame] = nil
            end
        end

        -- ====================================================================
        -- Gui hiding
        -- ====================================================================

        local function HidePlayerGuiAll()
            local playerGui = RbxService.Players.LocalPlayer and RbxService.Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
            if not playerGui then return end
            local children = playerGui:GetChildren()
            for idx = 1, #children do
                local screenGui = children[idx]
                if screenGui:IsA("ScreenGui") then
                    StoreOnce(Variables.Snapshot.PlayerGuiEnabled, screenGui, screenGui.Enabled)
                    pcall(function() screenGui.Enabled = false end)
                end
            end
        end

        local function RestorePlayerGuiAll()
            for screenGui, wasEnabled in pairs(Variables.Snapshot.PlayerGuiEnabled) do
                pcall(function()
                    if screenGui and screenGui.Parent then
                        screenGui.Enabled = wasEnabled and true or false
                    end
                end)
                Variables.Snapshot.PlayerGuiEnabled[screenGui] = nil
            end
        end

        local function HideCoreGuiAll(hiddenState)
            if Variables.Snapshot.CoreGuiState["__snap__"] == nil then
                for _, coreType in ipairs({
                    Enum.CoreGuiType.Chat, Enum.CoreGuiType.Backpack, Enum.CoreGuiType.EmotesMenu,
                    Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.Health,
                }) do
                    Variables.Snapshot.CoreGuiState[coreType] = RbxService.StarterGui:GetCoreGuiEnabled(coreType)
                end
                Variables.Snapshot.CoreGuiState["__snap__"] = true
            end
            for coreType, _ in pairs(Variables.Snapshot.CoreGuiState) do
                if typeof(coreType) == "EnumItem" then
                    pcall(function() RbxService.StarterGui:SetCoreGuiEnabled(coreType, not hiddenState) end)
                end
            end
        end

        local function RestoreCoreGuiAll()
            for coreType, wasEnabled in pairs(Variables.Snapshot.CoreGuiState) do
                if typeof(coreType) == "EnumItem" then
                    pcall(function() RbxService.StarterGui:SetCoreGuiEnabled(coreType, wasEnabled and true or false) end)
                end
            end
            Variables.Snapshot.CoreGuiState = {}
        end

        -- ====================================================================
        -- Water replacement (visual only)
        -- ====================================================================

        local function ApplyWaterReplacement()
            local terrain = RbxService.Workspace:FindFirstChildOfClass("Terrain")
            if terrain then
                if Variables.Snapshot.WaterTransparency == nil then
                    local ok, valueNow = pcall(function() return terrain.WaterTransparency end)
                    if ok then Variables.Snapshot.WaterTransparency = valueNow end
                end
                pcall(function() terrain.WaterTransparency = 1 end)
            end

            if Variables.State.WaterProxyPart and Variables.State.WaterProxyPart.Parent then
                pcall(function() Variables.State.WaterProxyPart:Destroy() end)
                Variables.State.WaterProxyPart = nil
            end

            local proxy = Instance.new("Part")
            proxy.Name        = "WFYB_WaterProxy"
            proxy.Anchored    = true
            proxy.CanCollide  = false
            proxy.Material    = Enum.Material.SmoothPlastic
            proxy.Transparency= math.clamp(Variables.Config.WaterBlockTransparencyPercent / 100, 0, 1)
            proxy.Color       = Color3.fromRGB(
                math.clamp(Variables.Config.WaterBlockColorR, 0, 255),
                math.clamp(Variables.Config.WaterBlockColorG, 0, 255),
                math.clamp(Variables.Config.WaterBlockColorB, 0, 255)
            )
            proxy.Size = Vector3.new(
                math.max(10, Variables.Config.WaterBlockSizeX),
                math.max(0.1, Variables.Config.WaterBlockThickness),
                math.max(10, Variables.Config.WaterBlockSizeZ)
            )
            proxy.CFrame = CFrame.new(0, Variables.Config.WaterBlockY, 0)
            proxy.Parent = RbxService.Workspace
            Variables.State.WaterProxyPart = proxy
        end

        local function RemoveWaterReplacement()
            if Variables.State.WaterProxyPart then
                pcall(function() Variables.State.WaterProxyPart:Destroy() end)
                Variables.State.WaterProxyPart = nil
            end
            local terrain = RbxService.Workspace:FindFirstChildOfClass("Terrain")
            if terrain and Variables.Snapshot.WaterTransparency ~= nil then
                pcall(function() terrain.WaterTransparency = Variables.Snapshot.WaterTransparency end)
                Variables.Snapshot.WaterTransparency = nil
            end
        end

        -- ====================================================================
        -- Event‑driven watchers (rebuilt on relevant toggle changes)
        -- ====================================================================

        local function BuildWatchers()
            Variables.Maids.Watchers:DoCleaning()

            -- Workspace stream
            Variables.Maids.Watchers:GiveTask(RbxService.Workspace.DescendantAdded:Connect(function(instanceObject)
                if not Variables.Config.Enabled then return end

                -- New emitters
                if Variables.Config.DestroyEmitters and IsEmitter(instanceObject) then
                    DestroyEmittersIrreversible(instanceObject)
                elseif Variables.Config.StopParticleSystems and IsEmitter(instanceObject) then
                    StopEmitter(instanceObject)
                end

                -- Materials/decals
                if Variables.Config.SmoothPlasticEverywhere and instanceObject:IsA("BasePart") then
                    SmoothPlasticPart(instanceObject)
                end
                if Variables.Config.HideDecals and (instanceObject:IsA("Decal") or instanceObject:IsA("Texture")) then
                    HideDecalOrTexture(instanceObject)
                end

                -- Freeze world
                if Variables.Config.FreezeWorldAssemblies and instanceObject:IsA("BasePart") then
                    FreezeWorldPart(instanceObject)
                end

                -- Net owner
                if Variables.Config.RemoveLocalNetworkOwnership and instanceObject:IsA("BasePart") then
                    pcall(function() if not instanceObject.Anchored then instanceObject:SetNetworkOwner(nil) end end)
                end

                -- Sounds
                if Variables.Config.MuteAllSounds and instanceObject:IsA("Sound") then
                    GuardSound(instanceObject)
                end

                -- Animators
                if instanceObject:IsA("Animator") then
                    GuardAnimator(instanceObject)
                end
            end))

            -- PlayerGui & CoreGui streams for Viewport/Video/Sound/Ani
            local function BuildGuiWatcher(rootGui)
                if not rootGui then return end
                Variables.Maids.Watchers:GiveTask(rootGui.DescendantAdded:Connect(function(instanceObject)
                    if not Variables.Config.Enabled then return end
                    if Variables.Config.DisableViewportFrames and instanceObject:IsA("ViewportFrame") then
                        StoreOnce(Variables.Snapshot.ViewportVisible, instanceObject, instanceObject.Visible)
                        pcall(function() instanceObject.Visible = false end)
                    elseif Variables.Config.DisableVideoFrames and instanceObject:IsA("VideoFrame") then
                        StoreOnce(Variables.Snapshot.VideoPlaying, instanceObject, instanceObject.Playing)
                        pcall(function() instanceObject.Playing = false end)
                    end
                    if Variables.Config.MuteAllSounds and instanceObject:IsA("Sound") then
                        GuardSound(instanceObject)
                    end
                    if instanceObject:IsA("Animator") then
                        GuardAnimator(instanceObject)
                    end
                end))
            end
            BuildGuiWatcher(RbxService.Players.LocalPlayer and RbxService.Players.LocalPlayer:FindFirstChildOfClass("PlayerGui"))
            BuildGuiWatcher(RbxService.CoreGui)

            -- Lighting guards (forced skybox battles)
            Variables.Maids.Watchers:GiveTask(RbxService.Lighting.ChildAdded:Connect(function(childObject)
                if not Variables.Config.Enabled then return end
                if Variables.Config.DisablePostEffects and (childObject:IsA("BlurEffect") or childObject:IsA("SunRaysEffect")
                    or childObject:IsA("ColorCorrectionEffect") or childObject:IsA("BloomEffect") or childObject:IsA("DepthOfFieldEffect")) then
                    StoreOnce(Variables.Snapshot.PostEffects, childObject, childObject.Enabled)
                    pcall(function() childObject.Enabled = false end)
                end
                if Variables.Config.GraySky or Variables.Config.FullBright then
                    ScheduleApplyLowLighting()
                end
            end))
            Variables.Maids.Watchers:GiveTask(RbxService.Lighting.Changed:Connect(function()
                if not Variables.Config.Enabled then return end
                if Variables.Config.GraySky or Variables.Config.FullBright then
                    ScheduleApplyLowLighting()
                end
            end))
        end

        -- ====================================================================
        -- Apply / Restore (master switch)
        -- ====================================================================

        local function ApplyAll()
            Variables.Config.Enabled = true
            Variables.State.LightingApplyScheduled = false

            -- Snapshots
            Variables.Snapshot.RenderingEnabled = true
            SnapshotLighting()

            -- Rendering
            if Variables.Config.DisableThreeDRendering then
                pcall(function() RbxService.RunService:Set3dRenderingEnabled(false) end)
            end
            if Variables.Config.TargetFramesPerSecond and Variables.Config.TargetFramesPerSecond > 0 then
                TrySetFramesPerSecondCap(Variables.Config.TargetFramesPerSecond)
            end

            -- GUI
            if Variables.Config.HidePlayerGui then HidePlayerGuiAll() end
            if Variables.Config.HideCoreGui then HideCoreGuiAll(true) end

            -- Viewport/Video & Sounds
            if Variables.Config.DisableViewportFrames or Variables.Config.DisableVideoFrames then
                DisableViewportAndVideoFramesScan()
            end
            if Variables.Config.MuteAllSounds then
                ApplyMuteAllSounds()
            end

            -- Animations
            EachDescendantChunked(RbxService.Workspace, function(instanceObject) return instanceObject:IsA("Animator") end, GuardAnimator)
            if Variables.Config.PauseCharacterAnimations then
                DisableCharacterAnimateScripts(false)
            end

            -- World freeze / constraints
            if Variables.Config.FreezeWorldAssemblies then
                EachDescendantChunked(RbxService.Workspace, function(instanceObject) return instanceObject:IsA("BasePart") end, FreezeWorldPart)
            end
            if Variables.Config.DisableConstraints then
                DisableWorldConstraints()
            end

            -- Physics / Net
            if Variables.Config.AnchorCharacter then CharacterAnchorSet(true) end
            ReduceSimulationRadius()
            RemoveNetOwnership()

            -- Particles / Materials / Decals
            if Variables.Config.StopParticleSystems then
                EachDescendantChunked(RbxService.Workspace, IsEmitter, StopEmitter)
            end
            if Variables.Config.DestroyEmitters and not Variables.Irreversible.EmittersDestroyed then
                EachDescendantChunked(RbxService.Workspace, IsEmitter, DestroyEmittersIrreversible)
                Variables.Irreversible.EmittersDestroyed = true
            end
            if Variables.Config.SmoothPlasticEverywhere then
                EachDescendantChunked(RbxService.Workspace, function(inst) return inst:IsA("BasePart") end, SmoothPlasticPart)
            end
            if Variables.Config.HideDecals then
                EachDescendantChunked(RbxService.Workspace, function(inst) return inst:IsA("Decal") or inst:IsA("Texture") end, HideDecalOrTexture)
            end
            if Variables.Config.NukeTextures and not Variables.Irreversible.TexturesNuked then
                EachDescendantChunked(RbxService.Workspace, function(inst)
                    return inst:IsA("Decal") or inst:IsA("Texture") or inst:IsA("SurfaceAppearance") or inst:IsA("MeshPart") or inst:IsA("BasePart")
                end, NukeTexturesIrreversible)
                Variables.Irreversible.TexturesNuked = true
            end

            -- Lighting / Quality
            if Variables.Config.RemoveGrassDecoration then TerrainDecorationSet(true) end
            if Variables.Config.DisablePostEffects then DisablePostEffects() end
            if Variables.Config.GraySky or Variables.Config.FullBright then ScheduleApplyLowLighting() end
            if Variables.Config.UseMinimumQuality then ApplyQualityMinimum() end

            -- Water replacement
            if Variables.Config.ReplaceWaterWithBlock then ApplyWaterReplacement() end

            -- Event guards
            BuildWatchers()
        end

        local function RestoreAll()
            Variables.Config.Enabled = false
            Variables.Maids.Watchers:DoCleaning()
            Variables.Maids.EmitterGuards:DoCleaning()
            Variables.State.LightingApplyScheduled = false

            -- Rendering
            if Variables.Config.DisableThreeDRendering then
                pcall(function() RbxService.RunService:Set3dRenderingEnabled(true) end)
            end

            -- UI/Media/Sound
            RestoreViewportAndVideoFrames()
            RestoreSounds()

            -- Animations
            ReleaseAnimatorGuards()
            DisableCharacterAnimateScripts(true)

            -- World / Constraints / Character
            if Variables.Config.FreezeWorldAssemblies then RestoreAnchoredParts() end
            if Variables.Config.DisableConstraints then RestoreWorldConstraints() end
            if Variables.Config.AnchorCharacter then CharacterAnchorSet(false) end

            -- GUI
            RestorePlayerGuiAll()
            RestoreCoreGuiAll()

            -- Materials / Decals / Emitters
            RestorePartMaterials()
            RestoreDecalsAndTextures()
            RestoreEmitters()

            -- Lighting
            pcall(function()
                local P = Variables.Snapshot.LightingProps
                if P then
                    RbxService.Lighting.GlobalShadows = P.GlobalShadows
                    RbxService.Lighting.Brightness    = P.Brightness
                    RbxService.Lighting.ClockTime     = P.ClockTime
                    RbxService.Lighting.Ambient       = P.Ambient
                    RbxService.Lighting.OutdoorAmbient= P.OutdoorAmbient
                    RbxService.Lighting.EnvironmentDiffuseScale  = P.EnvironmentDiffuseScale
                    RbxService.Lighting.EnvironmentSpecularScale = P.EnvironmentSpecularScale
                end
                if Variables.Config.ForceClearBlurOnRestore then
                    local children = RbxService.Lighting:GetChildren()
                    for idx = 1, #children do
                        local child = children[idx]
                        if child:IsA("BlurEffect") then child.Enabled = false end
                    end
                end
            end)
            RestorePostEffects()
            if Variables.Snapshot.TerrainDecoration ~= nil then
                local terrain = RbxService.Workspace:FindFirstChildOfClass("Terrain")
                pcall(function()
                    if terrain and typeof(terrain.Decoration) == "boolean" then
                        terrain.Decoration = Variables.Snapshot.TerrainDecoration
                    end
                end)
                Variables.Snapshot.TerrainDecoration = nil
            end
            RestoreQuality()

            -- Water replacement
            RemoveWaterReplacement()

            -- Clear small snapshots
            Variables.Snapshot.PlayerGuiEnabled = {}
            Variables.Snapshot.CoreGuiState     = {}
            Variables.Snapshot.ViewportVisible  = {}
            Variables.Snapshot.VideoPlaying     = {}
        end

        -- ====================================================================
        -- UI (Obsidian) — all sliders now use "Text" (not "Label")
        -- ====================================================================

        local group = UI.Tabs.Misc:AddRightGroupbox("Optimization", "power")

        group:AddToggle("OptEnabled", {
            Text = "Enable Optimization",
            Default = false,
            Tooltip = "Master switch – applies your selections below.",
        }):OnChanged(function(state)
            if state then ApplyAll() else RestoreAll() end
        end)

        group:AddSlider("OptFps", {
            Text = "Target FPS",
            Min = 1, Max = 120,
            Default = Variables.Config.TargetFramesPerSecond,
            Suffix = "FPS",
        }):OnChanged(function(value)
            Variables.Config.TargetFramesPerSecond = math.floor(value)
            if Variables.Config.Enabled then
                TrySetFramesPerSecondCap(Variables.Config.TargetFramesPerSecond)
            end
        end)

        group:AddDivider()
        group:AddLabel("Rendering / UI")
        group:AddToggle("Opt3D", { Text="Disable 3D Rendering", Default=Variables.Config.DisableThreeDRendering })
            :OnChanged(function(state)
                Variables.Config.DisableThreeDRendering = state
                if Variables.Config.Enabled then
                    pcall(function() RbxService.RunService:Set3dRenderingEnabled(not state and true or false) end)
                end
            end)
        group:AddToggle("OptHidePlayerGui", { Text="Hide PlayerGui", Default=Variables.Config.HidePlayerGui })
            :OnChanged(function(state)
                Variables.Config.HidePlayerGui = state
                if not Variables.Config.Enabled then return end
                if state then HidePlayerGuiAll() else RestorePlayerGuiAll() end
            end)
        group:AddToggle("OptHideCoreGui", { Text="Hide CoreGui", Default=Variables.Config.HideCoreGui })
            :OnChanged(function(state)
                Variables.Config.HideCoreGui = state
                if Variables.Config.Enabled then HideCoreGuiAll(state) end
            end)
        group:AddToggle("OptNoViewports", { Text="Disable ViewportFrames", Default=Variables.Config.DisableViewportFrames })
            :OnChanged(function(state)
                Variables.Config.DisableViewportFrames = state
                if Variables.Config.Enabled then
                    if state then DisableViewportAndVideoFramesScan() else RestoreViewportAndVideoFrames() end
                    BuildWatchers()
                end
            end)
        group:AddToggle("OptNoVideos", { Text="Disable VideoFrames", Default=Variables.Config.DisableVideoFrames })
            :OnChanged(function(state)
                Variables.Config.DisableVideoFrames = state
                if Variables.Config.Enabled then
                    if state then DisableViewportAndVideoFramesScan() else RestoreViewportAndVideoFrames() end
                    BuildWatchers()
                end
            end)
        group:AddToggle("OptMute", { Text="Mute All Sounds", Default=Variables.Config.MuteAllSounds })
            :OnChanged(function(state)
                Variables.Config.MuteAllSounds = state
                if Variables.Config.Enabled then
                    if state then ApplyMuteAllSounds() else RestoreSounds() end
                    BuildWatchers()
                end
            end)

        group:AddDivider()
        group:AddLabel("Animation / Motion")
        group:AddToggle("OptPauseCharAnim", { Text="Pause Character Animations", Default=Variables.Config.PauseCharacterAnimations })
            :OnChanged(function(state)
                Variables.Config.PauseCharacterAnimations = state
                if Variables.Config.Enabled then
                    if state then DisableCharacterAnimateScripts(false) else DisableCharacterAnimateScripts(true) end
                    ReleaseAnimatorGuards()
                    EachDescendantChunked(RbxService.Workspace, function(inst) return inst:IsA("Animator") end, GuardAnimator)
                    BuildWatchers()
                end
            end)
        group:AddToggle("OptPauseOtherAnim", { Text="Pause Other Animations (client‑driven)", Default=Variables.Config.PauseOtherAnimations })
            :OnChanged(function(state)
                Variables.Config.PauseOtherAnimations = state
                if Variables.Config.Enabled then
                    ReleaseAnimatorGuards()
                    EachDescendantChunked(RbxService.Workspace, function(inst) return inst:IsA("Animator") end, GuardAnimator)
                    BuildWatchers()
                end
            end)
        group:AddToggle("OptFreezeWorld", { Text="Freeze World Assemblies (reversible)", Default=Variables.Config.FreezeWorldAssemblies })
            :OnChanged(function(state)
                Variables.Config.FreezeWorldAssemblies = state
                if Variables.Config.Enabled then
                    if state then
                        EachDescendantChunked(RbxService.Workspace, function(inst) return inst:IsA("BasePart") end, FreezeWorldPart)
                    else
                        RestoreAnchoredParts()
                    end
                    BuildWatchers()
                end
            end)
        group:AddToggle("OptNoConstraints", { Text="Disable Constraints (reversible)", Default=Variables.Config.DisableConstraints })
            :OnChanged(function(state)
                Variables.Config.DisableConstraints = state
                if Variables.Config.Enabled then
                    if state then DisableWorldConstraints() else RestoreWorldConstraints() end
                end
            end)

        group:AddDivider()
        group:AddLabel("Physics / Network")
        group:AddToggle("OptAnchorChar", { Text="Anchor Character", Default=Variables.Config.AnchorCharacter })
            :OnChanged(function(state)
                Variables.Config.AnchorCharacter = state
                if Variables.Config.Enabled then CharacterAnchorSet(state) end
            end)
        group:AddToggle("OptSimRadius", { Text="Reduce Simulation Radius", Default=Variables.Config.ReduceSimulationRadius })
            :OnChanged(function(state)
                Variables.Config.ReduceSimulationRadius = state
                if Variables.Config.Enabled and state then ReduceSimulationRadius() end
            end)
        group:AddToggle("OptNoNetOwner", { Text="Remove Local Network Ownership", Default=Variables.Config.RemoveLocalNetworkOwnership })
            :OnChanged(function(state)
                Variables.Config.RemoveLocalNetworkOwnership = state
                if Variables.Config.Enabled and state then RemoveNetOwnership() end
                if Variables.Config.Enabled then BuildWatchers() end
            end)

        group:AddDivider()
        group:AddLabel("Particles / Effects / Materials")
        group:AddToggle("OptStopParticles", { Text="Stop Particle Systems (reversible)", Default=Variables.Config.StopParticleSystems })
            :OnChanged(function(state)
                Variables.Config.StopParticleSystems = state
                if Variables.Config.Enabled then
                    if state then
                        EachDescendantChunked(RbxService.Workspace, IsEmitter, StopEmitter)
                        BuildWatchers()
                    else
                        RestoreEmitters()
                    end
                end
            end)
        group:AddToggle("OptDestroyEmitters", { Text="Destroy Emitters (irreversible)", Default=Variables.Config.DestroyEmitters })
            :OnChanged(function(state)
                Variables.Config.DestroyEmitters = state
                if Variables.Config.Enabled and state and not Variables.Irreversible.EmittersDestroyed then
                    EachDescendantChunked(RbxService.Workspace, IsEmitter, DestroyEmittersIrreversible)
                    Variables.Irreversible.EmittersDestroyed = true
                    BuildWatchers()
                end
            end)
        group:AddToggle("OptSmoothPlastic", { Text="Force SmoothPlastic (reversible)", Default=Variables.Config.SmoothPlasticEverywhere })
            :OnChanged(function(state)
                Variables.Config.SmoothPlasticEverywhere = state
                if Variables.Config.Enabled then
                    if state then
                        EachDescendantChunked(RbxService.Workspace, function(inst) return inst:IsA("BasePart") end, SmoothPlasticPart)
                        BuildWatchers()
                    else
                        RestorePartMaterials()
                    end
                end
            end)
        group:AddToggle("OptHideDecals", { Text="Hide Decals/Textures (reversible)", Default=Variables.Config.HideDecals })
            :OnChanged(function(state)
                Variables.Config.HideDecals = state
                if Variables.Config.Enabled then
                    if state then
                        EachDescendantChunked(RbxService.Workspace, function(inst) return inst:IsA("Decal") or inst:IsA("Texture") end, HideDecalOrTexture)
                        BuildWatchers()
                    else
                        RestoreDecalsAndTextures()
                    end
                end
            end)
        group:AddToggle("OptNukeTextures", { Text="Nuke Textures (irreversible)", Default=Variables.Config.NukeTextures })
            :OnChanged(function(state)
                Variables.Config.NukeTextures = state
                if Variables.Config.Enabled and state and not Variables.Irreversible.TexturesNuked then
                    EachDescendantChunked(RbxService.Workspace, function(inst)
                        return inst:IsA("Decal") or inst:IsA("Texture") or inst:IsA("SurfaceAppearance") or inst:IsA("MeshPart") or inst:IsA("BasePart")
                    end, NukeTexturesIrreversible)
                    Variables.Irreversible.TexturesNuked = true
                    BuildWatchers()
                end
            end)

        group:AddDivider()
        group:AddLabel("Lighting / Quality")
        group:AddToggle("OptNoGrass", { Text="Remove Grass Decoration", Default=Variables.Config.RemoveGrassDecoration })
            :OnChanged(function(state)
                Variables.Config.RemoveGrassDecoration = state
                if Variables.Config.Enabled then TerrainDecorationSet(state) end
            end)
        group:AddToggle("OptNoPostFX", { Text="Disable Post‑FX (Bloom/CC/DoF/SunRays/Blur)", Default=Variables.Config.DisablePostEffects })
            :OnChanged(function(state)
                Variables.Config.DisablePostEffects = state
                if Variables.Config.Enabled then if state then DisablePostEffects() else RestorePostEffects() end end
                if Variables.Config.Enabled then BuildWatchers() end
            end)
        group:AddToggle("OptGraySky", { Text="Gray Sky", Default=Variables.Config.GraySky })
            :OnChanged(function(state)
                Variables.Config.GraySky = state
                if Variables.Config.Enabled and state then ScheduleApplyLowLighting() end
                if Variables.Config.Enabled then BuildWatchers() end
            end)
        group:AddToggle("OptFullBright", { Text="Full Bright", Default=Variables.Config.FullBright })
            :OnChanged(function(state)
                Variables.Config.FullBright = state
                if Variables.Config.Enabled and state then ScheduleApplyLowLighting() end
                if Variables.Config.Enabled then BuildWatchers() end
            end)
        group:AddToggle("OptMinQuality", { Text="Use Minimum Quality", Default=Variables.Config.UseMinimumQuality })
            :OnChanged(function(state)
                Variables.Config.UseMinimumQuality = state
                if Variables.Config.Enabled then if state then ApplyQualityMinimum() else RestoreQuality() end end
            end)
        group:AddToggle("OptClearBlurRestore", { Text="Force Clear Blur on Restore", Default=Variables.Config.ForceClearBlurOnRestore })
            :OnChanged(function(state)
                Variables.Config.ForceClearBlurOnRestore = state
            end)

        group:AddDivider()
        group:AddLabel("Water Replacement (visual)")
        group:AddToggle("OptWaterProxy", { Text="Replace Water With Block", Default=Variables.Config.ReplaceWaterWithBlock })
            :OnChanged(function(state)
                Variables.Config.ReplaceWaterWithBlock = state
                if not Variables.Config.Enabled then return end
                if state then ApplyWaterReplacement() else RemoveWaterReplacement() end
            end)
        group:AddSlider("OptWaterTransparency", { Text="Water Block Transparency", Min=0, Max=100, Default=Variables.Config.WaterBlockTransparencyPercent, Suffix="%" })
            :OnChanged(function(value)
                Variables.Config.WaterBlockTransparencyPercent = math.floor(value)
                if Variables.State.WaterProxyPart then
                    Variables.State.WaterProxyPart.Transparency = math.clamp(Variables.Config.WaterBlockTransparencyPercent / 100, 0, 1)
                end
            end)
        group:AddSlider("OptWaterR", { Text="Water Block Red", Min=0, Max=255, Default=Variables.Config.WaterBlockColorR })
            :OnChanged(function(value)
                Variables.Config.WaterBlockColorR = math.floor(value)
                if Variables.State.WaterProxyPart then
                    Variables.State.WaterProxyPart.Color = Color3.fromRGB(Variables.Config.WaterBlockColorR, Variables.Config.WaterBlockColorG, Variables.Config.WaterBlockColorB)
                end
            end)
        group:AddSlider("OptWaterG", { Text="Water Block Green", Min=0, Max=255, Default=Variables.Config.WaterBlockColorG })
            :OnChanged(function(value)
                Variables.Config.WaterBlockColorG = math.floor(value)
                if Variables.State.WaterProxyPart then
                    Variables.State.WaterProxyPart.Color = Color3.fromRGB(Variables.Config.WaterBlockColorR, Variables.Config.WaterBlockColorG, Variables.Config.WaterBlockColorB)
                end
            end)
        group:AddSlider("OptWaterB", { Text="Water Block Blue", Min=0, Max=255, Default=Variables.Config.WaterBlockColorB })
            :OnChanged(function(value)
                Variables.Config.WaterBlockColorB = math.floor(value)
                if Variables.State.WaterProxyPart then
                    Variables.State.WaterProxyPart.Color = Color3.fromRGB(Variables.Config.WaterBlockColorR, Variables.Config.WaterBlockColorG, Variables.Config.WaterBlockColorB)
                end
            end)
        group:AddSlider("OptWaterY", { Text="Water Block Y Level", Min=-1000, Max=1000, Default=Variables.Config.WaterBlockY })
            :OnChanged(function(value)
                Variables.Config.WaterBlockY = math.floor(value)
                if Variables.State.WaterProxyPart then
                    Variables.State.WaterProxyPart.CFrame = CFrame.new(0, Variables.Config.WaterBlockY, 0)
                end
            end)
        group:AddSlider("OptWaterSizeX", { Text="Water Block Size X", Min=1000, Max=40000, Default=Variables.Config.WaterBlockSizeX })
            :OnChanged(function(value)
                Variables.Config.WaterBlockSizeX = math.floor(value)
                if Variables.State.WaterProxyPart then
                    Variables.State.WaterProxyPart.Size = Vector3.new(Variables.Config.WaterBlockSizeX, Variables.State.WaterProxyPart.Size.Y, Variables.State.WaterProxyPart.Size.Z)
                end
            end)
        group:AddSlider("OptWaterSizeZ", { Text="Water Block Size Z", Min=1000, Max=40000, Default=Variables.Config.WaterBlockSizeZ })
            :OnChanged(function(value)
                Variables.Config.WaterBlockSizeZ = math.floor(value)
                if Variables.State.WaterProxyPart then
                    Variables.State.WaterProxyPart.Size = Vector3.new(Variables.State.WaterProxyPart.Size.X, Variables.State.WaterProxyPart.Size.Y, Variables.Config.WaterBlockSizeZ)
                end
            end)
        group:AddSlider("OptWaterThickness", { Text="Water Block Thickness", Min=1, Max=50, Default=Variables.Config.WaterBlockThickness })
            :OnChanged(function(value)
                Variables.Config.WaterBlockThickness = math.floor(value)
                if Variables.State.WaterProxyPart then
                    Variables.State.WaterProxyPart.Size = Vector3.new(Variables.State.WaterProxyPart.Size.X, Variables.Config.WaterBlockThickness, Variables.State.WaterProxyPart.Size.Z)
                end
            end)

        -- stop hook
        local function ModuleStop()
            if UI.Toggles.OptEnabled then UI.Toggles.OptEnabled:SetValue(false) end
            RestoreAll()
            Variables.Maids.Optimization:DoCleaning()
        end

        return { Name = "Optimization", Stop = ModuleStop }
    end
end

