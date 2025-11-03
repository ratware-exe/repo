-- modules/Optimization.lua
do
    return function(UI)
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv = (getgenv and getgenv()) or _G
        GlobalEnv.Signal = GlobalEnv.Signal or loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()
        local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local Variables = {
            Maids = {
                Optimization = Maid.new(),
                Watchers = Maid.new(),
            },
            Config = {
                Enabled = false,

                -- Rendering / UI
                DisableThreeDRendering = false,
                TargetFramesPerSecond = 30,
                HidePlayerGui = true,
                HideCoreGui = true,
                DisableViewportFrames = true,
                DisableVideoFrames = true,
                MuteAllSounds = true,

                -- Animation / Motion
                PauseCharacterAnimations = true,
                PauseOtherAnimations = true,
                FreezeWorldAssemblies = false,     -- reversible
                DisableConstraints = true,         -- reversible (excludes Motor6D)

                -- Physics / Network
                AnchorCharacter = true,
                ReduceSimulationRadius = true,     -- best‑effort (hidden properties; ignored if not available)
                RemoveLocalNetworkOwnership = true,

                -- Materials / Effects
                StopParticleSystems = true,        -- reversible
                DestroyEmitters = false,           -- irreversible
                SmoothPlasticEverywhere = true,    -- reversible
                HideDecals = true,                 -- reversible
                NukeTextures = false,              -- irreversible

                RemoveGrassDecoration = true,      -- Terrain & MaterialService best‑effort
                DisablePostEffects = true,         -- Bloom/CC/DoF/SunRays/Blur (reversible)
                GraySky = true,                    -- reversible
                FullBright = true,                 -- reversible
                UseMinimumQuality = true,          -- reversible
                ForceClearBlurOnRestore = true,

                -- Water replacement (visual only)
                ReplaceWaterWithBlock = false,
                WaterBlockTransparencyPercent = 25, -- 0..100
                WaterBlockColorR = 30,              -- RGB 0..255
                WaterBlockColorG = 85,
                WaterBlockColorB = 255,
                WaterBlockY = 0,                    -- plane height
                WaterBlockSizeX = 20000,
                WaterBlockSizeZ = 20000,
                WaterBlockThickness = 2,            -- Y thickness
            },

            Snapshot = {
                RenderingEnabled = true,
                SavedQuality = nil,

                PlayerGuiEnabled = {},      -- ScreenGui -> bool
                CoreGuiState = {},          -- CoreGuiType -> bool

                VideoPlaying = {},          -- VideoFrame -> bool
                ViewportVisible = {},       -- ViewportFrame -> bool
                SoundProps = {},            -- Sound -> {Volume, Playing}

                AnimatorGuards = {},        -- Animator -> {Tracks={track->oldSpeed}, Conns={...}}
                AnimateScripts = {},        -- LocalScript under character "Animate" -> Disabled

                ConstraintEnabled = {},     -- Constraint -> bool
                PartAnchored = {},          -- BasePart -> bool (world freeze)
                CharacterAnchored = {},     -- BasePart -> bool

                PartMaterial = {},          -- BasePart -> {Material, Reflectance, CastShadow}
                DecalTransparency = {},     -- Decal/Texture -> number
                EmitterEnabled = {},        -- ParticleEmitter/Trail/Beam/Fire/Smoke -> bool

                LightingProps = {
                    GlobalShadows = nil, Brightness = nil, ClockTime = nil,
                    Ambient = nil, OutdoorAmbient = nil,
                    EnvironmentDiffuseScale = nil, EnvironmentSpecularScale = nil,
                },
                PostEffects = {},           -- Effect -> Enabled
                TerrainDecoration = nil,    -- bool
                WaterTransparency = nil,    -- number
            },

            Irreversible = {
                EmittersDestroyed = false,
                TexturesNuked = false,
            },

            State = {
                WaterProxyPart = nil,
            },
        }

        ----------------------------------------------------------------------
        -- Small helpers (no polling; use events + chunked scans)
        ----------------------------------------------------------------------

        local function StoreOnce(map, key, value)
            if map[key] == nil then
                map[key] = value
            end
        end

        local function EachDescendantChunked(root, predicate, action)
            local processed = 0
            local list = root:GetDescendants()
            for index = 1, #list do
                local instanceObject = list[index]
                if not Variables.Config.Enabled then break end
                if predicate(instanceObject) then
                    action(instanceObject)
                end
                processed = processed + 1
                if processed % 500 == 0 then task.wait() end
            end
        end

        local function TrySetFramesPerSecondCap(target)
            local candidates = {
                (getgenv and getgenv().setfpscap),
                rawget(_G, "setfpscap"),
                rawget(_G, "set_fps_cap"),
                rawget(_G, "setfps"),
                rawget(_G, "setfps_max"),
            }
            for index = 1, #candidates do
                local functionObject = candidates[index]
                if typeof(functionObject) == "function" then
                    local ok = pcall(functionObject, target)
                    if ok then return true end
                end
            end
            return false
        end

        ----------------------------------------------------------------------
        -- Sound muting (per‑Sound, reversible)
        ----------------------------------------------------------------------

        local function GuardSound(soundInstance)
            if not soundInstance or not soundInstance:IsA("Sound") then return end
            StoreOnce(Variables.Snapshot.SoundProps, soundInstance, {
                Volume = (function() local ok, v = pcall(function() return soundInstance.Volume end) return ok and v or 1 end)(),
                Playing = (function() local ok, v = pcall(function() return soundInstance.Playing end) return ok and v or false end)(),
            })
            pcall(function()
                soundInstance.Playing = false
                soundInstance.Volume = 0
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
            for soundInstance, props in pairs(Variables.Snapshot.SoundProps) do
                pcall(function()
                    if soundInstance and soundInstance.Parent then
                        soundInstance.Volume = props.Volume
                        soundInstance.Playing = props.Playing
                    end
                end)
                Variables.Snapshot.SoundProps[soundInstance] = nil
            end
        end

        ----------------------------------------------------------------------
        -- Animation freeze (character and others)
        ----------------------------------------------------------------------

        local function ShouldPauseAnimator(animator)
            local localPlayer = RbxService.Players.LocalPlayer
            local character = localPlayer and localPlayer.Character
            local isCharacter = character and animator:IsDescendantOf(character)
            if isCharacter then
                return Variables.Config.PauseCharacterAnimations
            else
                return Variables.Config.PauseOtherAnimations
            end
        end

        local function FreezeTrack(track)
            if not track then return end
            -- Cache speed once
            local animatorBundle = Variables.Snapshot.AnimatorGuards[track] -- not used; keep per animator bundle
            pcall(function() track:AdjustSpeed(0) end)
        end

        local function GuardAnimator(animator)
            if not animator or not animator:IsA("Animator") then return end
            if not ShouldPauseAnimator(animator) then return end
            if Variables.Snapshot.AnimatorGuards[animator] then return end

            local guardBundle = { Tracks = {}, Conns = {} }
            Variables.Snapshot.AnimatorGuards[animator] = guardBundle

            local function CacheAndFreeze(track)
                if guardBundle.Tracks[track] == nil then
                    local okSpeed, speedValue = pcall(function() return track.Speed end)
                    guardBundle.Tracks[track] = okSpeed and speedValue or 1
                end
                pcall(function() track:AdjustSpeed(0) end)
                table.insert(guardBundle.Conns, track.Stopped:Connect(function()
                    guardBundle.Tracks[track] = nil
                end))
            end

            local okList, list = pcall(function() return animator:GetPlayingAnimationTracks() end)
            if okList and list then
                for index = 1, #list do
                    CacheAndFreeze(list[index])
                end
            end

            table.insert(guardBundle.Conns, animator.AnimationPlayed:Connect(function(newTrack)
                if Variables.Config.Enabled and ShouldPauseAnimator(animator) then
                    CacheAndFreeze(newTrack)
                end
            end))

            table.insert(guardBundle.Conns, animator.AncestryChanged:Connect(function(_, parent)
                if parent == nil then
                    for connIndex = 1, #guardBundle.Conns do
                        local connObject = guardBundle.Conns[connIndex]
                        if connObject then connObject:Disconnect() end
                    end
                    Variables.Snapshot.AnimatorGuards[animator] = nil
                end
            end))
        end

        local function DisableCharacterAnimateScripts(enableBack)
            local localPlayer = RbxService.Players.LocalPlayer
            local character = localPlayer and localPlayer.Character
            if not character then return end
            for childIndex = 1, #character:GetChildren() do
                local childObject = character:GetChildren()[childIndex]
                if childObject:IsA("LocalScript") and childObject.Name == "Animate" then
                    if enableBack then
                        local previous = Variables.Snapshot.AnimateScripts[childObject]
                        Variables.Snapshot.AnimateScripts[childObject] = nil
                        if previous ~= nil then
                            pcall(function() childObject.Enabled = previous end)
                        end
                    else
                        StoreOnce(Variables.Snapshot.AnimateScripts, childObject,
                            (function() local ok, v = pcall(function() return childObject.Enabled end) return ok and v or true end)())
                        pcall(function() childObject.Enabled = false end)
                    end
                end
            end
        end

        local function ReleaseAnimatorGuards()
            for animatorObject, guardBundle in pairs(Variables.Snapshot.AnimatorGuards) do
                if guardBundle and guardBundle.Tracks then
                    for trackObject, oldSpeedValue in pairs(guardBundle.Tracks) do
                        pcall(function() trackObject:AdjustSpeed(oldSpeedValue or 1) end)
                    end
                end
                if guardBundle and guardBundle.Conns then
                    for connIndex = 1, #guardBundle.Conns do
                        local connObject = guardBundle.Conns[connIndex]
                        if connObject then connObject:Disconnect() end
                    end
                end
                Variables.Snapshot.AnimatorGuards[animatorObject] = nil
            end
        end

        ----------------------------------------------------------------------
        -- Particles / decals / materials
        ----------------------------------------------------------------------

        local function IsEmitter(instanceObject)
            return instanceObject:IsA("ParticleEmitter")
                or instanceObject:IsA("Trail")
                or instanceObject:IsA("Beam")
                or instanceObject:IsA("Fire")
                or instanceObject:IsA("Smoke")
        end

        local function StopEmitter(instanceObject)
            local okGet, current = pcall(function() return instanceObject.Enabled end)
            StoreOnce(Variables.Snapshot.EmitterEnabled, instanceObject, okGet and current or true)
            pcall(function() instanceObject.Enabled = false end)
            local conn = instanceObject:GetPropertyChangedSignal("Enabled"):Connect(function()
                if Variables.Config.Enabled and Variables.Config.StopParticleSystems then
                    pcall(function() instanceObject.Enabled = false end)
                end
            end)
            Variables.Maids.Watchers:GiveTask(conn)
        end

        local function RestoreEmitters()
            for emitterInstance, oldEnabled in pairs(Variables.Snapshot.EmitterEnabled) do
                pcall(function()
                    if emitterInstance and emitterInstance.Parent then
                        emitterInstance.Enabled = oldEnabled and true or false
                    end
                end)
                Variables.Snapshot.EmitterEnabled[emitterInstance] = nil
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
            for instanceObject, oldTransparency in pairs(Variables.Snapshot.DecalTransparency) do
                pcall(function()
                    if instanceObject and instanceObject.Parent then
                        instanceObject.Transparency = oldTransparency
                    end
                end)
                Variables.Snapshot.DecalTransparency[instanceObject] = nil
            end
        end

        local function SmoothPlasticPart(instanceObject)
            if not instanceObject:IsA("BasePart") then return end
            local character = RbxService.Players.LocalPlayer.Character
            if character and instanceObject:IsDescendantOf(character) then return end
            StoreOnce(Variables.Snapshot.PartMaterial, instanceObject, {
                Material = instanceObject.Material,
                Reflectance = instanceObject.Reflectance,
                CastShadow = instanceObject.CastShadow,
            })
            pcall(function()
                instanceObject.Material = Enum.Material.SmoothPlastic
                instanceObject.Reflectance = 0
                instanceObject.CastShadow = false
            end)
        end

        local function RestorePartMaterials()
            local processed = 0
            for partInstance, props in pairs(Variables.Snapshot.PartMaterial) do
                pcall(function()
                    if partInstance and partInstance.Parent then
                        partInstance.Material = props.Material
                        partInstance.Reflectance = props.Reflectance
                        partInstance.CastShadow = props.CastShadow
                    end
                end)
                Variables.Snapshot.PartMaterial[partInstance] = nil
                processed = processed + 1
                if processed % 500 == 0 then task.wait() end
            end
        end

        local function DestroyEmittersIrreversible(instanceObject)
            if IsEmitter(instanceObject) then
                pcall(function() instanceObject:Destroy() end)
            end
        end

        local function NukeTexturesIrreversible(instanceObject)
            if instanceObject:IsA("Decal") or instanceObject:IsA("Texture") or instanceObject:IsA("SurfaceAppearance") then
                pcall(function() instanceObject:Destroy() end)
            elseif instanceObject:IsA("MeshPart") or instanceObject:IsA("BasePart") then
                pcall(function() instanceObject.Material = Enum.Material.SmoothPlastic end)
            end
        end

        ----------------------------------------------------------------------
        -- World freeze, constraints, ownership
        ----------------------------------------------------------------------

        local function FreezeWorldPart(instanceObject)
            if not instanceObject:IsA("BasePart") then return end
            local character = RbxService.Players.LocalPlayer.Character
            if character and instanceObject:IsDescendantOf(character) then return end
            StoreOnce(Variables.Snapshot.PartAnchored, instanceObject, instanceObject.Anchored)
            pcall(function()
                instanceObject.AssemblyLinearVelocity = Vector3.new()
                instanceObject.AssemblyAngularVelocity = Vector3.new()
                instanceObject.Anchored = true
            end)
        end

        local function RestoreAnchoredParts()
            local count = 0
            for partInstance, wasAnchored in pairs(Variables.Snapshot.PartAnchored) do
                pcall(function()
                    if partInstance and partInstance.Parent then
                        partInstance.Anchored = wasAnchored and true or false
                    end
                end)
                Variables.Snapshot.PartAnchored[partInstance] = nil
                count = count + 1
                if count % 500 == 0 then task.wait() end
            end
        end

        local function DisableWorldConstraints()
            EachDescendantChunked(RbxService.Workspace, function(inst)
                return inst:IsA("Constraint") and not inst:IsA("Motor6D")
            end, function(constraintInst)
                StoreOnce(Variables.Snapshot.ConstraintEnabled, constraintInst, constraintInst.Enabled)
                pcall(function() constraintInst.Enabled = false end)
            end)
        end

        local function RestoreWorldConstraints()
            local count = 0
            for constraintInst, oldEnabled in pairs(Variables.Snapshot.ConstraintEnabled) do
                pcall(function()
                    if constraintInst and constraintInst.Parent then
                        constraintInst.Enabled = oldEnabled and true or false
                    end
                end)
                Variables.Snapshot.ConstraintEnabled[constraintInst] = nil
                count = count + 1
                if count % 500 == 0 then task.wait() end
            end
        end

        local function CharacterAnchorSet(anchorOn)
            local character = RbxService.Players.LocalPlayer and RbxService.Players.LocalPlayer.Character
            if not character then return end
            for index = 1, #character:GetDescendants() do
                local partInstance = character:GetDescendants()[index]
                if partInstance:IsA("BasePart") then
                    StoreOnce(Variables.Snapshot.CharacterAnchored, partInstance, partInstance.Anchored)
                    pcall(function() partInstance.Anchored = anchorOn and true or false end)
                end
            end
        end

        local function ReduceSimulationRadius()
            if not Variables.Config.ReduceSimulationRadius then return end
            local target = RbxService.Players.LocalPlayer
            if not target then return end
            local setter = sethiddenproperty or set_hidden_property or set_hidden_prop
            if setter then
                pcall(function()
                    setter(target, "SimulationRadius", 0)
                    setter(target, "MaxSimulationRadius", 0)
                end)
            end
        end

        local function RemoveNetOwnership()
            if not Variables.Config.RemoveLocalNetworkOwnership then return end
            EachDescendantChunked(RbxService.Workspace, function(inst)
                return inst:IsA("BasePart")
            end, function(partInstance)
                pcall(function()
                    if not partInstance.Anchored then
                        partInstance:SetNetworkOwner(nil)
                    end
                end)
            end)
        end

        ----------------------------------------------------------------------
        -- Lighting, post‑FX, grass/material service
        ----------------------------------------------------------------------

        local function SnapshotLighting()
            Variables.Snapshot.LightingProps.GlobalShadows = RbxService.Lighting.GlobalShadows
            Variables.Snapshot.LightingProps.Brightness = RbxService.Lighting.Brightness
            Variables.Snapshot.LightingProps.ClockTime = RbxService.Lighting.ClockTime
            Variables.Snapshot.LightingProps.Ambient = RbxService.Lighting.Ambient
            Variables.Snapshot.LightingProps.OutdoorAmbient = RbxService.Lighting.OutdoorAmbient
            Variables.Snapshot.LightingProps.EnvironmentDiffuseScale = RbxService.Lighting.EnvironmentDiffuseScale
            Variables.Snapshot.LightingProps.EnvironmentSpecularScale = RbxService.Lighting.EnvironmentSpecularScale
        end

        local function ApplyLowLighting()
            pcall(function()
                RbxService.Lighting.GlobalShadows = false
                RbxService.Lighting.Brightness = 1
                RbxService.Lighting.EnvironmentDiffuseScale = 0
                RbxService.Lighting.EnvironmentSpecularScale = 0
                if Variables.Config.GraySky then
                    RbxService.Lighting.ClockTime = 12
                    RbxService.Lighting.Ambient = Color3.fromRGB(128, 128, 128)
                    RbxService.Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
                end
                if Variables.Config.FullBright then
                    RbxService.Lighting.Brightness = 2
                end
            end)
        end

        local function DisablePostEffects()
            local children = RbxService.Lighting:GetChildren()
            for index = 1, #children do
                local child = children[index]
                if child:IsA("BlurEffect") or child:IsA("SunRaysEffect") or child:IsA("ColorCorrectionEffect")
                   or child:IsA("BloomEffect") or child:IsA("DepthOfFieldEffect") then
                    StoreOnce(Variables.Snapshot.PostEffects, child, child.Enabled)
                    pcall(function() child.Enabled = false end)
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

        local function TerrainDecorationSet(disable)
            local terrain = RbxService.Workspace:FindFirstChildOfClass("Terrain")
            if not terrain then return end
            if Variables.Snapshot.TerrainDecoration == nil then
                local ok, value = pcall(function() return terrain.Decoration end)
                if ok then Variables.Snapshot.TerrainDecoration = value end
            end
            pcall(function()
                if typeof(terrain.Decoration) == "boolean" then
                    terrain.Decoration = not disable
                end
            end)
            if RbxService.MaterialService then
                pcall(function()
                    if disable then
                        RbxService.MaterialService.FallbackMaterial = Enum.Material.SmoothPlastic
                    else
                        RbxService.MaterialService.FallbackMaterial = Enum.Material.Plastic
                    end
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

        ----------------------------------------------------------------------
        -- Viewport/Video frames (in PlayerGui/CoreGui)
        ----------------------------------------------------------------------

        local function DisableViewportAndVideoFramesScan()
            local function handleGuiRoot(guiRoot)
                if not guiRoot then return end
                EachDescendantChunked(guiRoot, function(inst)
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

            local playerGui = RbxService.Players.LocalPlayer and RbxService.Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
            handleGuiRoot(playerGui)
            handleGuiRoot(RbxService.CoreGui)
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

        ----------------------------------------------------------------------
        -- Gui hiding
        ----------------------------------------------------------------------

        local function HidePlayerGuiAll()
            local playerGui = RbxService.Players.LocalPlayer and RbxService.Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
            if not playerGui then return end
            local children = playerGui:GetChildren()
            for index = 1, #children do
                local screen = children[index]
                if screen:IsA("ScreenGui") then
                    StoreOnce(Variables.Snapshot.PlayerGuiEnabled, screen, screen.Enabled)
                    pcall(function() screen.Enabled = false end)
                end
            end
        end

        local function RestorePlayerGuiAll()
            for guiInst, wasEnabled in pairs(Variables.Snapshot.PlayerGuiEnabled) do
                pcall(function()
                    if guiInst and guiInst.Parent then
                        guiInst.Enabled = wasEnabled and true or false
                    end
                end)
                Variables.Snapshot.PlayerGuiEnabled[guiInst] = nil
            end
        end

        local function HideCoreGuiAll(hidden)
            if Variables.Snapshot.CoreGuiState["__snap__"] == nil then
                for coreIndex = 1, #({Enum.CoreGuiType.Chat, Enum.CoreGuiType.Backpack, Enum.CoreGuiType.EmotesMenu,
                    Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.Health}) do end
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
                    pcall(function() RbxService.StarterGui:SetCoreGuiEnabled(coreType, not hidden) end)
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

        ----------------------------------------------------------------------
        -- Water replacement (visual proxy)
        ----------------------------------------------------------------------

        local function ApplyWaterReplacement()
            -- Hide real water
            local terrain = RbxService.Workspace:FindFirstChildOfClass("Terrain")
            if terrain then
                if Variables.Snapshot.WaterTransparency == nil then
                    local ok, val = pcall(function() return terrain.WaterTransparency end)
                    if ok then Variables.Snapshot.WaterTransparency = val end
                end
                pcall(function() terrain.WaterTransparency = 1 end)
            end

            -- Create proxy part
            if Variables.State.WaterProxyPart and Variables.State.WaterProxyPart.Parent then
                pcall(function() Variables.State.WaterProxyPart:Destroy() end)
                Variables.State.WaterProxyPart = nil
            end

            local proxy = Instance.new("Part")
            proxy.Name = "WFYB_WaterProxy"
            proxy.Anchored = true
            proxy.CanCollide = false
            proxy.Material = Enum.Material.SmoothPlastic
            proxy.Transparency = math.clamp(Variables.Config.WaterBlockTransparencyPercent / 100, 0, 1)
            proxy.Color = Color3.fromRGB(
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

        ----------------------------------------------------------------------
        -- Watchers (event‑driven; rebuilt on demand)
        ----------------------------------------------------------------------

        local function BuildWatchers()
            Variables.Maids.Watchers:DoCleaning()

            -- Workspace stream
            local workspaceConn = RbxService.Workspace.DescendantAdded:Connect(function(inst)
                if not Variables.Config.Enabled then return end

                -- particles
                if Variables.Config.DestroyEmitters and IsEmitter(inst) then
                    DestroyEmittersIrreversible(inst)
                elseif Variables.Config.StopParticleSystems and IsEmitter(inst) then
                    StopEmitter(inst)
                end

                -- materials/decals
                if Variables.Config.SmoothPlasticEverywhere and inst:IsA("BasePart") then
                    SmoothPlasticPart(inst)
                end
                if Variables.Config.HideDecals and (inst:IsA("Decal") or inst:IsA("Texture")) then
                    HideDecalOrTexture(inst)
                end

                -- freeze world
                if Variables.Config.FreezeWorldAssemblies and inst:IsA("BasePart") then
                    FreezeWorldPart(inst)
                end

                -- ownership
                if Variables.Config.RemoveLocalNetworkOwnership and inst:IsA("BasePart") then
                    pcall(function() if not inst.Anchored then inst:SetNetworkOwner(nil) end end)
                end

                -- sounds
                if Variables.Config.MuteAllSounds and inst:IsA("Sound") then
                    GuardSound(inst)
                end

                -- animations
                if inst:IsA("Animator") then
                    GuardAnimator(inst)
                end
            end)
            Variables.Maids.Watchers:GiveTask(workspaceConn)

            -- GUI stream
            local playerGui = RbxService.Players.LocalPlayer and RbxService.Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
            if playerGui then
                local guiConn = playerGui.DescendantAdded:Connect(function(inst)
                    if not Variables.Config.Enabled then return end
                    if Variables.Config.DisableViewportFrames and inst:IsA("ViewportFrame") then
                        StoreOnce(Variables.Snapshot.ViewportVisible, inst, inst.Visible)
                        pcall(function() inst.Visible = false end)
                    elseif Variables.Config.DisableVideoFrames and inst:IsA("VideoFrame") then
                        StoreOnce(Variables.Snapshot.VideoPlaying, inst, inst.Playing)
                        pcall(function() inst.Playing = false end)
                    end
                    if Variables.Config.MuteAllSounds and inst:IsA("Sound") then
                        GuardSound(inst)
                    end
                    if inst:IsA("Animator") then
                        GuardAnimator(inst)
                    end
                end)
                Variables.Maids.Watchers:GiveTask(guiConn)
            end

            -- CoreGui for Viewport/Video
            local coreConn = RbxService.CoreGui.DescendantAdded:Connect(function(inst)
                if not Variables.Config.Enabled then return end
                if Variables.Config.DisableViewportFrames and inst:IsA("ViewportFrame") then
                    StoreOnce(Variables.Snapshot.ViewportVisible, inst, inst.Visible)
                    pcall(function() inst.Visible = false end)
                elseif Variables.Config.DisableVideoFrames and inst:IsA("VideoFrame") then
                    StoreOnce(Variables.Snapshot.VideoPlaying, inst, inst.Playing)
                    pcall(function() inst.Playing = false end)
                end
                if Variables.Config.MuteAllSounds and inst:IsA("Sound") then
                    GuardSound(inst)
                end
                if inst:IsA("Animator") then
                    GuardAnimator(inst)
                end
            end)
            Variables.Maids.Watchers:GiveTask(coreConn)

            -- Lighting guards (forced sky / brightness wars)
            local lightChildConn = RbxService.Lighting.ChildAdded:Connect(function(child)
                if not Variables.Config.Enabled then return end
                if Variables.Config.DisablePostEffects and (child:IsA("BlurEffect") or child:IsA("SunRaysEffect")
                    or child:IsA("ColorCorrectionEffect") or child:IsA("BloomEffect") or child:IsA("DepthOfFieldEffect")) then
                    StoreOnce(Variables.Snapshot.PostEffects, child, child.Enabled)
                    pcall(function() child.Enabled = false end)
                end
                if Variables.Config.GraySky or Variables.Config.FullBright then
                    task.defer(ApplyLowLighting)
                end
            end)
            Variables.Maids.Watchers:GiveTask(lightChildConn)

            local lightChangedConn = RbxService.Lighting.Changed:Connect(function()
                if not Variables.Config.Enabled then return end
                if Variables.Config.GraySky or Variables.Config.FullBright then
                    task.defer(ApplyLowLighting)
                end
            end)
            Variables.Maids.Watchers:GiveTask(lightChangedConn)
        end

        ----------------------------------------------------------------------
        -- Apply / Restore (master switch)
        ----------------------------------------------------------------------

        local function ApplyAll()
            Variables.Config.Enabled = true

            -- global snapshots
            Variables.Snapshot.RenderingEnabled = true
            SnapshotLighting()

            -- rendering / fps
            if Variables.Config.DisableThreeDRendering then
                pcall(function() RbxService.RunService:Set3dRenderingEnabled(false) end)
            end
            if Variables.Config.TargetFramesPerSecond and Variables.Config.TargetFramesPerSecond > 0 then
                TrySetFramesPerSecondCap(Variables.Config.TargetFramesPerSecond)
            end

            -- GUI
            if Variables.Config.HidePlayerGui then HidePlayerGuiAll() end
            if Variables.Config.HideCoreGui then HideCoreGuiAll(true) end

            -- viewport/video + sound
            if Variables.Config.DisableViewportFrames or Variables.Config.DisableVideoFrames then
                DisableViewportAndVideoFramesScan()
            end
            if Variables.Config.MuteAllSounds then
                ApplyMuteAllSounds()
            end

            -- animations
            EachDescendantChunked(RbxService.Workspace, function(inst) return inst:IsA("Animator") end, GuardAnimator)
            if Variables.Config.PauseCharacterAnimations then
                DisableCharacterAnimateScripts(false)
            end

            -- world freeze / constraints
            if Variables.Config.FreezeWorldAssemblies then
                EachDescendantChunked(RbxService.Workspace, function(inst) return inst:IsA("BasePart") end, FreezeWorldPart)
            end
            if Variables.Config.DisableConstraints then
                DisableWorldConstraints()
            end

            -- physics / net
            if Variables.Config.AnchorCharacter then CharacterAnchorSet(true) end
            ReduceSimulationRadius()
            RemoveNetOwnership()

            -- particles/effects/materials
            if Variables.Config.StopParticleSystems then
                EachDescendantChunked(RbxService.Workspace, function(inst) return IsEmitter(inst) end, StopEmitter)
            end
            if Variables.Config.DestroyEmitters and not Variables.Irreversible.EmittersDestroyed then
                EachDescendantChunked(RbxService.Workspace, function(inst) return IsEmitter(inst) end, DestroyEmittersIrreversible)
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

            -- lighting / quality
            if Variables.Config.RemoveGrassDecoration then TerrainDecorationSet(true) end
            if Variables.Config.DisablePostEffects then DisablePostEffects() end
            if Variables.Config.GraySky or Variables.Config.FullBright then ApplyLowLighting() end
            if Variables.Config.UseMinimumQuality then ApplyQualityMinimum() end

            -- water proxy
            if Variables.Config.ReplaceWaterWithBlock then ApplyWaterReplacement() end

            -- event‑driven guards
            BuildWatchers()
        end

        local function RestoreAll()
            Variables.Config.Enabled = false
            Variables.Maids.Watchers:DoCleaning()

            -- reverse order of apply
            if Variables.Config.DisableThreeDRendering then
                pcall(function() RbxService.RunService:Set3dRenderingEnabled(true) end)
            end

            RestoreViewportAndVideoFrames()
            RestoreSounds()

            ReleaseAnimatorGuards()
            DisableCharacterAnimateScripts(true)

            if Variables.Config.FreezeWorldAssemblies then RestoreAnchoredParts() end
            if Variables.Config.DisableConstraints then RestoreWorldConstraints() end
            if Variables.Config.AnchorCharacter then CharacterAnchorSet(false) end

            RestorePlayerGuiAll()
            RestoreCoreGuiAll()

            RestorePartMaterials()
            RestoreDecalsAndTextures()
            RestoreEmitters()

            -- lighting restore
            pcall(function()
                local p = Variables.Snapshot.LightingProps
                if p then
                    RbxService.Lighting.GlobalShadows = p.GlobalShadows
                    RbxService.Lighting.Brightness = p.Brightness
                    RbxService.Lighting.ClockTime = p.ClockTime
                    RbxService.Lighting.Ambient = p.Ambient
                    RbxService.Lighting.OutdoorAmbient = p.OutdoorAmbient
                    RbxService.Lighting.EnvironmentDiffuseScale = p.EnvironmentDiffuseScale
                    RbxService.Lighting.EnvironmentSpecularScale = p.EnvironmentSpecularScale
                end
                if Variables.Config.ForceClearBlurOnRestore then
                    local children = RbxService.Lighting:GetChildren()
                    for index = 1, #children do
                        local c = children[index]
                        if c:IsA("BlurEffect") then c.Enabled = false end
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

            RemoveWaterReplacement()

            -- clear small snapshots
            Variables.Snapshot.PlayerGuiEnabled = {}
            Variables.Snapshot.CoreGuiState = {}
            Variables.Snapshot.ViewportVisible = {}
            Variables.Snapshot.VideoPlaying = {}
        end

        ----------------------------------------------------------------------
        -- UI (all individual toggles; real‑time responders)
        ----------------------------------------------------------------------

        local group = UI.Tabs.Misc:AddRightGroupbox("Optimization", "power")

        group:AddToggle("OptEnabled", {
            Text = "Enable Optimization",
            Default = false,
            Tooltip = "Master switch – applies your selections below.",
        }):OnChanged(function(state)
            if state then ApplyAll() else RestoreAll() end
        end)

        group:AddSlider("OptFps", {
            Label = "Target FPS",
            Min = 1, Max = 120,
            Default = Variables.Config.TargetFramesPerSecond,
            Suffix = "FPS",
        }):OnChanged(function(value)
            Variables.Config.TargetFramesPerSecond = math.floor(value)
            if Variables.Config.Enabled then
                TrySetFramesPerSecondCap(Variables.Config.TargetFramesPerSecond)
                if Variables.Config.TargetFramesPerSecond <= 5 and not Variables.Config.DisableThreeDRendering then
                    -- optional hint: ultra‑low caps often unsupported; disable rendering for real savings
                    RbxService.StarterGui:SetCore("SendNotification", {
                        Title = "Optimization",
                        Text = "Executor may ignore ultra‑low FPS caps. Consider enabling \"Disable 3D Rendering\".",
                        Duration = 4
                    })
                end
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
                    if state then
                        DisableCharacterAnimateScripts(false)
                        EachDescendantChunked(RbxService.Workspace, function(inst) return inst:IsA("Animator") end, GuardAnimator)
                    else
                        DisableCharacterAnimateScripts(true)
                        ReleaseAnimatorGuards()
                    end
                    BuildWatchers()
                end
            end)
        group:AddToggle("OptPauseOtherAnim", { Text="Pause Other Animations", Default=Variables.Config.PauseOtherAnimations })
            :OnChanged(function(state)
                Variables.Config.PauseOtherAnimations = state
                if Variables.Config.Enabled then
                    if state then
                        EachDescendantChunked(RbxService.Workspace, function(inst) return inst:IsA("Animator") end, GuardAnimator)
                    else
                        ReleaseAnimatorGuards()
                    end
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
                        EachDescendantChunked(RbxService.Workspace, function(inst) return IsEmitter(inst) end, StopEmitter)
                    else
                        RestoreEmitters()
                    end
                    BuildWatchers()
                end
            end)
        group:AddToggle("OptDestroyEmitters", { Text="Destroy Emitters (irreversible)", Default=Variables.Config.DestroyEmitters })
            :OnChanged(function(state)
                Variables.Config.DestroyEmitters = state
                if Variables.Config.Enabled and state and not Variables.Irreversible.EmittersDestroyed then
                    EachDescendantChunked(RbxService.Workspace, function(inst) return IsEmitter(inst) end, DestroyEmittersIrreversible)
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
                if Variables.Config.Enabled and state then ApplyLowLighting() end
                if Variables.Config.Enabled then BuildWatchers() end
            end)
        group:AddToggle("OptFullBright", { Text="Full Bright", Default=Variables.Config.FullBright })
            :OnChanged(function(state)
                Variables.Config.FullBright = state
                if Variables.Config.Enabled and state then ApplyLowLighting() end
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
        group:AddSlider("OptWaterTransparency", { Label="Water Block Transparency", Min=0, Max=100, Default=Variables.Config.WaterBlockTransparencyPercent, Suffix="%" })
            :OnChanged(function(value)
                Variables.Config.WaterBlockTransparencyPercent = math.floor(value)
                if Variables.State.WaterProxyPart then
                    Variables.State.WaterProxyPart.Transparency = math.clamp(Variables.Config.WaterBlockTransparencyPercent / 100, 0, 1)
                end
            end)
        group:AddSlider("OptWaterR", { Label="Water Block Red", Min=0, Max=255, Default=Variables.Config.WaterBlockColorR })
            :OnChanged(function(value)
                Variables.Config.WaterBlockColorR = math.floor(value)
                if Variables.State.WaterProxyPart then
                    Variables.State.WaterProxyPart.Color = Color3.fromRGB(Variables.Config.WaterBlockColorR, Variables.Config.WaterBlockColorG, Variables.Config.WaterBlockColorB)
                end
            end)
        group:AddSlider("OptWaterG", { Label="Water Block Green", Min=0, Max=255, Default=Variables.Config.WaterBlockColorG })
            :OnChanged(function(value)
                Variables.Config.WaterBlockColorG = math.floor(value)
                if Variables.State.WaterProxyPart then
                    Variables.State.WaterProxyPart.Color = Color3.fromRGB(Variables.Config.WaterBlockColorR, Variables.Config.WaterBlockColorG, Variables.Config.WaterBlockColorB)
                end
            end)
        group:AddSlider("OptWaterB", { Label="Water Block Blue", Min=0, Max=255, Default=Variables.Config.WaterBlockColorB })
            :OnChanged(function(value)
                Variables.Config.WaterBlockColorB = math.floor(value)
                if Variables.State.WaterProxyPart then
                    Variables.State.WaterProxyPart.Color = Color3.fromRGB(Variables.Config.WaterBlockColorR, Variables.Config.WaterBlockColorG, Variables.Config.WaterBlockColorB)
                end
            end)
        group:AddSlider("OptWaterY", { Label="Water Block Y Level", Min=-1000, Max=1000, Default=Variables.Config.WaterBlockY })
            :OnChanged(function(value)
                Variables.Config.WaterBlockY = math.floor(value)
                if Variables.State.WaterProxyPart then
                    Variables.State.WaterProxyPart.CFrame = CFrame.new(0, Variables.Config.WaterBlockY, 0)
                end
            end)
        group:AddSlider("OptWaterSizeX", { Label="Water Block Size X", Min=1000, Max=40000, Default=Variables.Config.WaterBlockSizeX })
            :OnChanged(function(value)
                Variables.Config.WaterBlockSizeX = math.floor(value)
                if Variables.State.WaterProxyPart then
                    Variables.State.WaterProxyPart.Size = Vector3.new(Variables.Config.WaterBlockSizeX, Variables.State.WaterProxyPart.Size.Y, Variables.State.WaterProxyPart.Size.Z)
                end
            end)
        group:AddSlider("OptWaterSizeZ", { Label="Water Block Size Z", Min=1000, Max=40000, Default=Variables.Config.WaterBlockSizeZ })
            :OnChanged(function(value)
                Variables.Config.WaterBlockSizeZ = math.floor(value)
                if Variables.State.WaterProxyPart then
                    Variables.State.WaterProxyPart.Size = Vector3.new(Variables.State.WaterProxyPart.Size.X, Variables.State.WaterProxyPart.Size.Y, Variables.Config.WaterBlockSizeZ)
                end
            end)
        group:AddSlider("OptWaterThickness", { Label="Water Block Thickness", Min=1, Max=50, Default=Variables.Config.WaterBlockThickness })
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
