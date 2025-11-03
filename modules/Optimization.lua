-- modules/Optimization.lua
do
    return function(UI)
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv = (getgenv and getgenv()) or _G
        GlobalEnv.Signal = GlobalEnv.Signal or loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()
        local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local Variables = {
            Maids = { Optimization = Maid.new(), Watchers = Maid.new() },

            Config = {
                Enabled = false,

                -- Rendering / UI
                Disable3DRendering = false,
                TargetFps = 30,
                HidePlayerGui = true,
                HideCoreGui = true,
                DisableViewportFrames = true,
                DisableVideoFrames = true,
                MuteAllSounds = true,

                -- Animation / Motion
                PauseCharacterAnimations = true,
                PauseOtherAnimations = true,
                FreezeWorldAssemblies = false,     -- Reversible (anchors non-character)
                DisableConstraints = true,         -- Reversible (excludes Motor6D, Humanoid constraints)

                -- Physics / Net
                AnchorCharacter = true,
                ReduceSimulationRadius = true,     -- Best-effort (hidden property; ignored if not available)
                RemoveLocalNetworkOwnership = true,

                -- Materials / Effects
                StopParticleSystems = true,        -- Reversible
                DestroyEmitters = false,           -- Irreversible
                SmoothPlasticEverywhere = true,    -- Reversible
                HideDecals = true,                 -- Reversible
                NukeTextures = false,              -- Irreversible

                RemoveGrassDecoration = true,      -- Terrain/MaterialService best-effort
                DisablePostEffects = true,         -- Reversible (Bloom, CC, DoF, SunRays, Blur)
                GraySky = true,                    -- Reversible
                FullBright = true,                 -- Reversible
                UseMinimumQuality = true,          -- Reversible

                ForceClearBlurOnRestore = true,    -- Best-effort
            },

            Snapshot = {
                RenderingEnabled = true,
                SavedQuality = nil,

                PlayerGuiEnabled = {},  -- ScreenGui -> bool
                CoreGuiState = {},      -- CoreGuiType -> bool

                VideoPlaying = {},      -- VideoFrame -> bool
                ViewportVisible = {},   -- ViewportFrame -> bool
                SoundServiceVolume = nil,

                AnimatorGuards = {},    -- Animator -> { tracks={track->oldSpeed}, conns={...} }
                ConstraintEnabled = {}, -- Constraint -> bool
                PartAnchored = {},      -- BasePart -> bool (for FreezeWorldAssemblies)
                CharacterAnchored = {}, -- BasePart -> bool (character only)

                PartMaterial = {},      -- BasePart -> { Material, Reflectance, CastShadow }
                DecalTransparency = {}, -- Decal/Texture -> number

                LightingProps = {
                    GlobalShadows = nil, Brightness = nil,
                    ClockTime = nil, Ambient = nil, OutdoorAmbient = nil,
                    EnvironmentDiffuseScale = nil, EnvironmentSpecularScale = nil,
                },
                PostEffects = {},       -- Effect instance -> Enabled
                TerrainDecoration = nil,
            },

            Irreversible = {
                EmittersDestroyed = false,
                TexturesNuked = false,
            },
        }

        -- === helpers ===

        local function EachDescendantChunked(rootInstance, predicateFn, actionFn)
            local processed = 0
            for _, instanceObject in pairs(rootInstance:GetDescendants()) do
                if not Variables.Config.Enabled then break end
                if predicateFn(instanceObject) then
                    actionFn(instanceObject)
                end
                processed = processed + 1
                if processed % 500 == 0 then task.wait() end
            end
        end

        local function TrySetFpsCap(targetFps)
            local candidates = {
                (getgenv and getgenv().setfpscap),
                rawget(_G, "setfpscap"),
                rawget(_G, "set_fps_cap"),
                rawget(_G, "setfps"),
                rawget(_G, "setfps_max"),
            }
            for index = 1, #candidates do
                local fn = candidates[index]
                if typeof(fn) == "function" then
                    local ok = pcall(fn, targetFps)
                    if ok then return true end
                end
            end
            return false
        end

        local function GuardAnimator(animator)
            if not animator or not animator:IsA("Animator") then return end
            local character = RbxService.Players.LocalPlayer.Character
            local isCharacterAnimator = character and animator:IsDescendantOf(character)
            local shouldPause = isCharacterAnimator and Variables.Config.PauseCharacterAnimations
                or (not isCharacterAnimator and Variables.Config.PauseOtherAnimations)
            if not shouldPause then return end
            if Variables.Snapshot.AnimatorGuards[animator] then return end

            local guardData = { tracks = {}, conns = {} }
            Variables.Snapshot.AnimatorGuards[animator] = guardData

            local function OriginalSpeed(track)
                local ok, speedValue = pcall(function() return track.Speed end)
                return ok and speedValue or 1
            end
            local function FreezeTrack(track)
                if guardData.tracks[track] == nil then
                    guardData.tracks[track] = OriginalSpeed(track)
                end
                pcall(function() track:AdjustSpeed(0) end)
                table.insert(guardData.conns, track.Stopped:Connect(function()
                    guardData.tracks[track] = nil
                end))
            end

            local okTracks, playing = pcall(function() return animator:GetPlayingAnimationTracks() end)
            if okTracks and playing then
                for index = 1, #playing do
                    local track = playing[index]
                    FreezeTrack(track)
                end
            end

            table.insert(guardData.conns, animator.AnimationPlayed:Connect(function(track)
                if Variables.Config.Enabled then
                    FreezeTrack(track)
                end
            end))

            table.insert(guardData.conns, animator.AncestryChanged:Connect(function(_, parent)
                if parent == nil then
                    for index = 1, #guardData.conns do
                        local conn = guardData.conns[index]
                        if conn then conn:Disconnect() end
                    end
                    Variables.Snapshot.AnimatorGuards[animator] = nil
                end
            end))
        end

        local function ReleaseAnimatorGuards()
            for animator, bundle in pairs(Variables.Snapshot.AnimatorGuards) do
                if bundle and bundle.tracks then
                    for track, oldSpeed in pairs(bundle.tracks) do
                        pcall(function() track:AdjustSpeed(oldSpeed or 1) end)
                    end
                end
                if bundle and bundle.conns then
                    for index = 1, #bundle.conns do
                        local conn = bundle.conns[index]
                        if conn then conn:Disconnect() end
                    end
                end
                Variables.Snapshot.AnimatorGuards[animator] = nil
            end
        end

        local function StopParticle(instanceObject)
            if instanceObject:IsA("ParticleEmitter") or instanceObject:IsA("Trail") or instanceObject:IsA("Beam")
               or instanceObject:IsA("Fire") or instanceObject:IsA("Smoke") then
                if Variables.Snapshot.DecalTransparency[instanceObject] == nil and instanceObject:IsA("Decal") then
                    Variables.Snapshot.DecalTransparency[instanceObject] = instanceObject.Transparency
                end
                if instanceObject:IsA("ParticleEmitter") or instanceObject:IsA("Trail") or instanceObject:IsA("Beam")
                   or instanceObject:IsA("Fire") or instanceObject:IsA("Smoke") then
                    local enabledProp = rawget(instanceObject, "Enabled") ~= nil and "Enabled" or nil
                    if enabledProp then
                        if Variables.Snapshot.DecalTransparency[instanceObject] == nil then
                            -- (reuse DecalTransparency table as generic "bool snapshot" for emitters)
                            Variables.Snapshot.DecalTransparency[instanceObject] = instanceObject[enabledProp]
                        end
                        pcall(function() instanceObject[enabledProp] = false end)
                        local conn = instanceObject:GetPropertyChangedSignal(enabledProp):Connect(function()
                            if Variables.Config.Enabled and Variables.Config.StopParticleSystems then
                                pcall(function() instanceObject[enabledProp] = false end)
                            end
                        end)
                        Variables.Maids.Watchers:GiveTask(conn)
                    end
                end
            end
        end

        local function DestroyEmittersIrreversible(instanceObject)
            if instanceObject:IsA("ParticleEmitter") or instanceObject:IsA("Trail") or instanceObject:IsA("Beam")
               or instanceObject:IsA("Fire") or instanceObject:IsA("Smoke") then
                pcall(function() instanceObject:Destroy() end)
            end
        end

        local function SmoothPlasticPart(instanceObject)
            if not instanceObject:IsA("BasePart") then return end
            if instanceObject:IsDescendantOf(RbxService.Players.LocalPlayer.Character or instanceObject) then return end
            if Variables.Snapshot.PartMaterial[instanceObject] == nil then
                Variables.Snapshot.PartMaterial[instanceObject] = {
                    Material = instanceObject.Material,
                    Reflectance = instanceObject.Reflectance,
                    CastShadow = instanceObject.CastShadow,
                }
            end
            pcall(function()
                instanceObject.Material = Enum.Material.SmoothPlastic
                instanceObject.Reflectance = 0
                instanceObject.CastShadow = false
            end)
        end

        local function HideDecalOrTexture(instanceObject)
            if instanceObject:IsA("Decal") or instanceObject:IsA("Texture") then
                if Variables.Snapshot.DecalTransparency[instanceObject] == nil then
                    Variables.Snapshot.DecalTransparency[instanceObject] = instanceObject.Transparency
                end
                pcall(function() instanceObject.Transparency = 1 end)
            end
        end

        local function NukeTexturesIrreversible(instanceObject)
            if instanceObject:IsA("Decal") or instanceObject:IsA("Texture") or instanceObject:IsA("SurfaceAppearance") then
                pcall(function() instanceObject:Destroy() end)
            elseif instanceObject:IsA("MeshPart") or instanceObject:IsA("BasePart") then
                pcall(function() instanceObject.Material = Enum.Material.SmoothPlastic end)
            end
        end

        local function FreezeWorldPart(instanceObject)
            if not instanceObject:IsA("BasePart") then return end
            local char = RbxService.Players.LocalPlayer.Character
            if char and instanceObject:IsDescendantOf(char) then return end
            if Variables.Snapshot.PartAnchored[instanceObject] == nil then
                Variables.Snapshot.PartAnchored[instanceObject] = instanceObject.Anchored
            end
            pcall(function()
                instanceObject.AssemblyLinearVelocity = Vector3.new()
                instanceObject.AssemblyAngularVelocity = Vector3.new()
                instanceObject.Anchored = true
            end)
        end

        local function RestoreAnchoredParts()
            local restored = 0
            for partInstance, wasAnchored in pairs(Variables.Snapshot.PartAnchored) do
                pcall(function()
                    if partInstance and partInstance.Parent then
                        partInstance.Anchored = wasAnchored and true or false
                    end
                end)
                Variables.Snapshot.PartAnchored[partInstance] = nil
                restored = restored + 1
                if restored % 500 == 0 then task.wait() end
            end
        end

        local function DisableWorldConstraints()
            EachDescendantChunked(RbxService.Workspace, function(inst)
                return inst:IsA("Constraint")
                   and (not inst:IsA("Motor6D"))
            end, function(constraintInst)
                if Variables.Snapshot.ConstraintEnabled[constraintInst] == nil then
                    Variables.Snapshot.ConstraintEnabled[constraintInst] = constraintInst.Enabled
                end
                pcall(function() constraintInst.Enabled = false end)
            end)
        end

        local function RestoreWorldConstraints()
            local processed = 0
            for constraintInst, oldEnabled in pairs(Variables.Snapshot.ConstraintEnabled) do
                pcall(function()
                    if constraintInst and constraintInst.Parent then
                        constraintInst.Enabled = oldEnabled and true or false
                    end
                end)
                Variables.Snapshot.ConstraintEnabled[constraintInst] = nil
                processed = processed + 1
                if processed % 500 == 0 then task.wait() end
            end
        end

        local function HideCoreGui(allHidden)
            if Variables.Snapshot.CoreGuiState["__snap__"] == nil then
                -- Snapshot common CoreGui types
                for _, coreType in ipairs({
                    Enum.CoreGuiType.Chat, Enum.CoreGuiType.Backpack, Enum.CoreGuiType.EmotesMenu,
                    Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.Health, Enum.CoreGuiType.Backpack,
                }) do
                    Variables.Snapshot.CoreGuiState[coreType] = RbxService.StarterGui:GetCoreGuiEnabled(coreType)
                end
                Variables.Snapshot.CoreGuiState["__snap__"] = true
            end
            for coreType, _ in pairs(Variables.Snapshot.CoreGuiState) do
                if typeof(coreType) == "EnumItem" then
                    pcall(function() RbxService.StarterGui:SetCoreGuiEnabled(coreType, not allHidden) end)
                end
            end
        end

        local function RestoreCoreGui()
            for coreType, wasEnabled in pairs(Variables.Snapshot.CoreGuiState) do
                if typeof(coreType) == "EnumItem" then
                    pcall(function() RbxService.StarterGui:SetCoreGuiEnabled(coreType, wasEnabled and true or false) end)
                end
            end
            Variables.Snapshot.CoreGuiState = {}
        end

        local function HidePlayerGuiAll()
            local playerGui = RbxService.Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
            if not playerGui then return end
            for _, childGui in pairs(playerGui:GetChildren()) do
                if childGui:IsA("ScreenGui") then
                    if Variables.Snapshot.PlayerGuiEnabled[childGui] == nil then
                        Variables.Snapshot.PlayerGuiEnabled[childGui] = childGui.Enabled
                    end
                    pcall(function() childGui.Enabled = false end)
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

        local function DisableViewportsAndVideos()
            EachDescendantChunked(RbxService.Workspace, function(inst)
                return inst:IsA("ViewportFrame") or inst:IsA("VideoFrame")
            end, function(frame)
                if frame:IsA("ViewportFrame") then
                    if Variables.Snapshot.ViewportVisible[frame] == nil then
                        Variables.Snapshot.ViewportVisible[frame] = frame.Visible
                    end
                    pcall(function() frame.Visible = false end)
                else
                    if Variables.Snapshot.VideoPlaying[frame] == nil then
                        Variables.Snapshot.VideoPlaying[frame] = frame.Playing
                    end
                    pcall(function() frame.Playing = false end)
                end
            end)
        end

        local function RestoreViewportsAndVideos()
            for frame, old in pairs(Variables.Snapshot.ViewportVisible) do
                pcall(function() if frame and frame.Parent then frame.Visible = old and true or false end end)
                Variables.Snapshot.ViewportVisible[frame] = nil
            end
            for frame, old in pairs(Variables.Snapshot.VideoPlaying) do
                pcall(function() if frame and frame.Parent then frame.Playing = old and true or false end end)
                Variables.Snapshot.VideoPlaying[frame] = nil
            end
        end

        local function LightingSnapshot()
            local L = RbxService.Lighting
            Variables.Snapshot.LightingProps.GlobalShadows = L.GlobalShadows
            Variables.Snapshot.LightingProps.Brightness = L.Brightness
            Variables.Snapshot.LightingProps.ClockTime = L.ClockTime
            Variables.Snapshot.LightingProps.Ambient = L.Ambient
            Variables.Snapshot.LightingProps.OutdoorAmbient = L.OutdoorAmbient
            Variables.Snapshot.LightingProps.EnvironmentDiffuseScale = L.EnvironmentDiffuseScale
            Variables.Snapshot.LightingProps.EnvironmentSpecularScale = L.EnvironmentSpecularScale
        end

        local function LightingApplyLow()
            local L = RbxService.Lighting
            pcall(function()
                L.GlobalShadows = false
                L.Brightness = 1
                L.EnvironmentDiffuseScale = 0
                L.EnvironmentSpecularScale = 0
                if Variables.Config.GraySky then
                    L.ClockTime = 12
                    L.Ambient = Color3.fromRGB(128, 128, 128)
                    L.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
                end
                if Variables.Config.FullBright then
                    L.Brightness = 2
                end
            end)
        end

        local function PostEffectsDisable()
            local L = RbxService.Lighting
            for _, child in pairs(L:GetChildren()) do
                if child:IsA("BlurEffect") or child:IsA("SunRaysEffect") or child:IsA("ColorCorrectionEffect")
                   or child:IsA("BloomEffect") or child:IsA("DepthOfFieldEffect") then
                    if Variables.Snapshot.PostEffects[child] == nil then
                        Variables.Snapshot.PostEffects[child] = child.Enabled
                    end
                    pcall(function() child.Enabled = false end)
                end
            end
        end

        local function PostEffectsRestore()
            for effectInst, wasEnabled in pairs(Variables.Snapshot.PostEffects) do
                pcall(function()
                    if effectInst and effectInst.Parent then
                        effectInst.Enabled = wasEnabled and true or false
                    end
                end)
                Variables.Snapshot.PostEffects[effectInst] = nil
            end
        end

        local function TerrainDecorationSet(disable)
            local terrain = RbxService.Workspace:FindFirstChildOfClass("Terrain")
            if not terrain then return end
            if Variables.Snapshot.TerrainDecoration == nil then
                local ok, current = pcall(function() return terrain.Decoration end)
                if ok then Variables.Snapshot.TerrainDecoration = current end
            end
            pcall(function()
                if typeof(terrain.Decoration) == "boolean" then
                    terrain.Decoration = not disable
                end
            end)
            local ms = RbxService.MaterialService
            if ms then
                pcall(function()
                    if disable then ms.FallbackMaterial = Enum.Material.SmoothPlastic else ms.FallbackMaterial = Enum.Material.Plastic end
                end)
            end
        end

        local function CharacterAnchorSet(anchorOn)
            local char = RbxService.Players.LocalPlayer.Character
            if not char then return end
            for _, part in pairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    if Variables.Snapshot.CharacterAnchored[part] == nil then
                        Variables.Snapshot.CharacterAnchored[part] = part.Anchored
                    end
                    pcall(function() part.Anchored = anchorOn and true or false end)
                end
            end
        end

        local function ReduceSimRadius()
            if not Variables.Config.ReduceSimulationRadius then return end
            local target = RbxService.Players.LocalPlayer
            if not target then return end
            local setter = (sethiddenproperty or set_hidden_property or set_hidden_prop)
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
                return inst:IsA("BasePart") and inst:IsDescendantOf(RbxService.Players.LocalPlayer.Character) == false and inst.Anchored == false
            end, function(part)
                pcall(function() part:SetNetworkOwner(nil) end)
            end)
        end

        local function MuteSounds()
            if Variables.Snapshot.SoundServiceVolume == nil then
                Variables.Snapshot.SoundServiceVolume = RbxService.SoundService.Volume
            end
            pcall(function() RbxService.SoundService.Volume = 0 end)
        end

        local function RestoreSounds()
            if Variables.Snapshot.SoundServiceVolume ~= nil then
                pcall(function() RbxService.SoundService.Volume = Variables.Snapshot.SoundServiceVolume end)
                Variables.Snapshot.SoundServiceVolume = nil
            end
        end

        local function ApplyQuality(minimum)
            if Variables.Snapshot.SavedQuality == nil then
                local ok, level = pcall(function() return settings().Rendering.QualityLevel end)
                if ok then Variables.Snapshot.SavedQuality = level end
            end
            if minimum then
                pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
            end
        end

        local function RestoreQuality()
            if Variables.Snapshot.SavedQuality ~= nil then
                pcall(function() settings().Rendering.QualityLevel = Variables.Snapshot.SavedQuality end)
                Variables.Snapshot.SavedQuality = nil
            end
        end

        local function StartWatchers()
            -- Keep new stuff in check while enabled (particles, videos, viewports, animators, parts)
            Variables.Maids.Watchers:GiveTask(RbxService.Workspace.DescendantAdded:Connect(function(inst)
                if not Variables.Config.Enabled then return end
                if Variables.Config.StopParticleSystems then StopParticle(inst) end
                if Variables.Config.DisableViewportFrames and inst:IsA("ViewportFrame") then
                    if Variables.Snapshot.ViewportVisible[inst] == nil then Variables.Snapshot.ViewportVisible[inst] = inst.Visible end
                    pcall(function() inst.Visible = false end)
                end
                if Variables.Config.DisableVideoFrames and inst:IsA("VideoFrame") then
                    if Variables.Snapshot.VideoPlaying[inst] == nil then Variables.Snapshot.VideoPlaying[inst] = inst.Playing end
                    pcall(function() inst.Playing = false end)
                end
                if inst:IsA("Animator") then GuardAnimator(inst) end
                if Variables.Config.SmoothPlasticEverywhere and inst:IsA("BasePart") then SmoothPlasticPart(inst) end
                if Variables.Config.HideDecals and (inst:IsA("Decal") or inst:IsA("Texture")) then HideDecalOrTexture(inst) end
                if Variables.Config.FreezeWorldAssemblies and inst:IsA("BasePart") then FreezeWorldPart(inst) end
            end))
        end

        local function StopWatchers()
            Variables.Maids.Watchers:DoCleaning()
        end

        local function ApplyAll()
            Variables.Config.Enabled = true

            -- Snapshot some global states upfront
            Variables.Snapshot.RenderingEnabled = true
            LightingSnapshot()

            -- Rendering
            if Variables.Config.Disable3DRendering then pcall(function() RbxService.RunService:Set3dRenderingEnabled(false) end) end
            if Variables.Config.TargetFps and Variables.Config.TargetFps > 0 then TrySetFpsCap(Variables.Config.TargetFps) end
            if Variables.Config.HidePlayerGui then HidePlayerGuiAll() end
            if Variables.Config.HideCoreGui then HideCoreGui(true) end
            if Variables.Config.DisableViewportFrames or Variables.Config.DisableVideoFrames then
                DisableViewportsAndVideos()
            end
            if Variables.Config.MuteAllSounds then MuteSounds() end

            -- Animations & Motion
            EachDescendantChunked(RbxService.Workspace, function(inst) return inst:IsA("Animator") end, GuardAnimator)
            if Variables.Config.FreezeWorldAssemblies then
                EachDescendantChunked(RbxService.Workspace, function(inst) return inst:IsA("BasePart") end, FreezeWorldPart)
            end
            if Variables.Config.DisableConstraints then
                DisableWorldConstraints()
            end

            -- Physics/Net
            if Variables.Config.AnchorCharacter then CharacterAnchorSet(true) end
            ReduceSimRadius()
            RemoveNetOwnership()

            -- Particles/Effects/Materials
            if Variables.Config.StopParticleSystems then
                EachDescendantChunked(RbxService.Workspace, function(inst)
                    return inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam") or inst:IsA("Fire") or inst:IsA("Smoke")
                end, StopParticle)
            end
            if Variables.Config.DestroyEmitters and not Variables.Irreversible.EmittersDestroyed then
                EachDescendantChunked(RbxService.Workspace, function(inst)
                    return inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam") or inst:IsA("Fire") or inst:IsA("Smoke")
                end, DestroyEmittersIrreversible)
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

            if Variables.Config.RemoveGrassDecoration then TerrainDecorationSet(true) end
            if Variables.Config.DisablePostEffects then PostEffectsDisable() end
            if Variables.Config.GraySky or Variables.Config.FullBright then LightingApplyLow() end
            if Variables.Config.UseMinimumQuality then ApplyQuality(true) end

            StartWatchers()
        end

        local function RestoreAll()
            Variables.Config.Enabled = false
            StopWatchers()

            -- Global restores (chunked where large)
            if Variables.Config.Disable3DRendering then pcall(function() RbxService.RunService:Set3dRenderingEnabled(true) end) end

            RestoreViewportsAndVideos()
            RestoreSounds()
            ReleaseAnimatorGuards()
            if Variables.Config.FreezeWorldAssemblies then RestoreAnchoredParts() end
            if Variables.Config.DisableConstraints then RestoreWorldConstraints() end
            if Variables.Config.AnchorCharacter then CharacterAnchorSet(false) end

            -- Restore Player/Core GUI
            RestorePlayerGuiAll()
            RestoreCoreGui()

            -- Restore materials & decals
            local processedA = 0
            for part, props in pairs(Variables.Snapshot.PartMaterial) do
                pcall(function()
                    if part and part.Parent then
                        part.Material = props.Material
                        part.Reflectance = props.Reflectance
                        part.CastShadow = props.CastShadow
                    end
                end)
                Variables.Snapshot.PartMaterial[part] = nil
                processedA = processedA + 1
                if processedA % 500 == 0 then task.wait() end
            end

            local processedB = 0
            for decalOrTexture, oldTrans in pairs(Variables.Snapshot.DecalTransparency) do
                pcall(function()
                    if decalOrTexture and decalOrTexture.Parent and decalOrTexture:IsA("Decal") or decalOrTexture:IsA("Texture") then
                        decalOrTexture.Transparency = oldTrans
                    end
                end)
                Variables.Snapshot.DecalTransparency[decalOrTexture] = nil
                processedB = processedB + 1
                if processedB % 500 == 0 then task.wait() end
            end

            -- Lighting & PostFX
            local L = RbxService.Lighting
            pcall(function()
                local P = Variables.Snapshot.LightingProps
                if P then
                    L.GlobalShadows = P.GlobalShadows
                    L.Brightness = P.Brightness
                    L.ClockTime = P.ClockTime
                    L.Ambient = P.Ambient
                    L.OutdoorAmbient = P.OutdoorAmbient
                    L.EnvironmentDiffuseScale = P.EnvironmentDiffuseScale
                    L.EnvironmentSpecularScale = P.EnvironmentSpecularScale
                end
                if Variables.Config.ForceClearBlurOnRestore then
                    for _, child in pairs(L:GetChildren()) do
                        if child:IsA("BlurEffect") then child.Enabled = false end
                    end
                end
            end)
            PostEffectsRestore()
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

            -- clear remaining snapshots
            Variables.Snapshot.PlayerGuiEnabled = {}
            Variables.Snapshot.CoreGuiState = {}
            Variables.Snapshot.VideoPlaying = {}
            Variables.Snapshot.ViewportVisible = {}
        end

        -- === UI ===
        local group = UI.Tabs.Misc:AddRightGroupbox("Optimization", "power")

        group:AddToggle("OptEnabled", {
            Text = "Enable Optimization",
            Default = false,
            Tooltip = "Master switch – applies your selections below.",
        }):OnChanged(function(state)
            if state then ApplyAll() else RestoreAll() end
        end)

        group:AddSlider("OptFps", { Label="Target FPS", Min=1, Max=120, Default=Variables.Config.TargetFps, Suffix="FPS" })
            :OnChanged(function(value)
                Variables.Config.TargetFps = math.floor(value)
                if Variables.Config.Enabled then TrySetFpsCap(Variables.Config.TargetFps) end
            end)

        group:AddDivider()
        group:AddLabel("Rendering / UI")
        group:AddToggle("Opt3D", { Text="Disable 3D Rendering", Default=Variables.Config.Disable3DRendering })
            :OnChanged(function(v) Variables.Config.Disable3DRendering = v if Variables.Config.Enabled then pcall(function() RbxService.RunService:Set3dRenderingEnabled(not v and true or false) end) end end)
        group:AddToggle("OptHidePlayerGui", { Text="Hide PlayerGui", Default=Variables.Config.HidePlayerGui })
            :OnChanged(function(v) Variables.Config.HidePlayerGui = v if Variables.Config.Enabled then if v then HidePlayerGuiAll() else RestorePlayerGuiAll() end end end)
        group:AddToggle("OptHideCoreGui", { Text="Hide CoreGui", Default=Variables.Config.HideCoreGui })
            :OnChanged(function(v) Variables.Config.HideCoreGui = v if Variables.Config.Enabled then HideCoreGui(v) end end)
        group:AddToggle("OptNoViewports", { Text="Disable ViewportFrames", Default=Variables.Config.DisableViewportFrames })
            :OnChanged(function(v) Variables.Config.DisableViewportFrames = v if Variables.Config.Enabled and v then DisableViewportsAndVideos() end end)
        group:AddToggle("OptNoVideos", { Text="Disable VideoFrames", Default=Variables.Config.DisableVideoFrames })
            :OnChanged(function(v) Variables.Config.DisableVideoFrames = v if Variables.Config.Enabled and v then DisableViewportsAndVideos() end end)
        group:AddToggle("OptMute", { Text="Mute All Sounds", Default=Variables.Config.MuteAllSounds })
            :OnChanged(function(v) Variables.Config.MuteAllSounds = v if Variables.Config.Enabled then if v then MuteSounds() else RestoreSounds() end end end)

        group:AddDivider()
        group:AddLabel("Animation / Motion")
        group:AddToggle("OptPauseCharAnim", { Text="Pause Character Animations", Default=Variables.Config.PauseCharacterAnimations })
            :OnChanged(function(v) Variables.Config.PauseCharacterAnimations = v end)
        group:AddToggle("OptPauseOtherAnim", { Text="Pause Other Animations", Default=Variables.Config.PauseOtherAnimations })
            :OnChanged(function(v) Variables.Config.PauseOtherAnimations = v end)
        group:AddToggle("OptFreezeWorld", { Text="Freeze World Assemblies (reversible)", Default=Variables.Config.FreezeWorldAssemblies, Tooltip="Anchors non-character BaseParts; restores original Anchored states on disable." })
            :OnChanged(function(v) Variables.Config.FreezeWorldAssemblies = v if Variables.Config.Enabled then if v then EachDescendantChunked(RbxService.Workspace, function(inst) return inst:IsA("BasePart") end, FreezeWorldPart) else RestoreAnchoredParts() end end end)
        group:AddToggle("OptNoConstraints", { Text="Disable Constraints (reversible)", Default=Variables.Config.DisableConstraints })
            :OnChanged(function(v) Variables.Config.DisableConstraints = v if Variables.Config.Enabled then if v then DisableWorldConstraints() else RestoreWorldConstraints() end end end)

        group:AddDivider()
        group:AddLabel("Physics / Network")
        group:AddToggle("OptAnchorChar", { Text="Anchor Character", Default=Variables.Config.AnchorCharacter })
            :OnChanged(function(v) Variables.Config.AnchorCharacter = v if Variables.Config.Enabled then CharacterAnchorSet(v) end end)
        group:AddToggle("OptSimRadius", { Text="Reduce Simulation Radius", Default=Variables.Config.ReduceSimulationRadius })
            :OnChanged(function(v) Variables.Config.ReduceSimulationRadius = v if Variables.Config.Enabled and v then ReduceSimRadius() end end)
        group:AddToggle("OptNoNetOwner", { Text="Remove Local Network Ownership", Default=Variables.Config.RemoveLocalNetworkOwnership })
            :OnChanged(function(v) Variables.Config.RemoveLocalNetworkOwnership = v if Variables.Config.Enabled and v then RemoveNetOwnership() end end)

        group:AddDivider()
        group:AddLabel("Particles / Effects / Materials")
        group:AddToggle("OptStopParticles", { Text="Stop Particle Systems (reversible)", Default=Variables.Config.StopParticleSystems })
            :OnChanged(function(v)
                Variables.Config.StopParticleSystems = v
                if Variables.Config.Enabled then
                    if v then
                        EachDescendantChunked(RbxService.Workspace, function(inst)
                            return inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam") or inst:IsA("Fire") or inst:IsA("Smoke")
                        end, StopParticle)
                    else
                        -- restore captured 'Enabled' states
                        local processed = 0
                        for inst, old in pairs(Variables.Snapshot.DecalTransparency) do
                            if inst and inst.Parent and (inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam") or inst:IsA("Fire") or inst:IsA("Smoke")) then
                                pcall(function()
                                    if rawget(inst, "Enabled") ~= nil then inst.Enabled = old and true or false end
                                end)
                            end
                            Variables.Snapshot.DecalTransparency[inst] = nil
                            processed = processed + 1
                            if processed % 500 == 0 then task.wait() end
                        end
                    end
                end
            end)
        group:AddToggle("OptDestroyEmitters", { Text="Destroy Emitters (irreversible)", Default=Variables.Config.DestroyEmitters, Tooltip="Deletes ParticleEmitter/Trail/Beam/Fire/Smoke. Cannot be restored." })
            :OnChanged(function(v)
                Variables.Config.DestroyEmitters = v
                if Variables.Config.Enabled and v and not Variables.Irreversible.EmittersDestroyed then
                    EachDescendantChunked(RbxService.Workspace, function(inst)
                        return inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam") or inst:IsA("Fire") or inst:IsA("Smoke")
                    end, DestroyEmittersIrreversible)
                    Variables.Irreversible.EmittersDestroyed = true
                end
            end)
        group:AddToggle("OptSmoothPlastic", { Text="Force SmoothPlastic (reversible)", Default=Variables.Config.SmoothPlasticEverywhere })
            :OnChanged(function(v) Variables.Config.SmoothPlasticEverywhere = v if Variables.Config.Enabled then if v then EachDescendantChunked(RbxService.Workspace, function(inst) return inst:IsA("BasePart") end, SmoothPlasticPart) end end end)
        group:AddToggle("OptHideDecals", { Text="Hide Decals/Textures (reversible)", Default=Variables.Config.HideDecals })
            :OnChanged(function(v) Variables.Config.HideDecals = v if Variables.Config.Enabled then if v then EachDescendantChunked(RbxService.Workspace, function(inst) return inst:IsA("Decal") or inst:IsA("Texture") end, HideDecalOrTexture) end end end)
        group:AddToggle("OptNukeTextures", { Text="Nuke Textures (irreversible)", Default=Variables.Config.NukeTextures, Tooltip="Destroys Decal/Texture/SurfaceAppearance and forces SmoothPlastic. Cannot be restored." })
            :OnChanged(function(v)
                Variables.Config.NukeTextures = v
                if Variables.Config.Enabled and v and not Variables.Irreversible.TexturesNuked then
                    EachDescendantChunked(RbxService.Workspace, function(inst)
                        return inst:IsA("Decal") or inst:IsA("Texture") or inst:IsA("SurfaceAppearance") or inst:IsA("MeshPart") or inst:IsA("BasePart")
                    end, NukeTexturesIrreversible)
                    Variables.Irreversible.TexturesNuked = true
                end
            end)

        group:AddDivider()
        group:AddLabel("Lighting / Quality")
        group:AddToggle("OptNoGrass", { Text="Remove Grass Decoration", Default=Variables.Config.RemoveGrassDecoration })
            :OnChanged(function(v) Variables.Config.RemoveGrassDecoration = v if Variables.Config.Enabled then TerrainDecorationSet(v) end end)
        group:AddToggle("OptNoPostFX", { Text="Disable Post‑FX (Bloom/CC/DoF/SunRays/Blur)", Default=Variables.Config.DisablePostEffects })
            :OnChanged(function(v) Variables.Config.DisablePostEffects = v if Variables.Config.Enabled then if v then PostEffectsDisable() else PostEffectsRestore() end end end)
        group:AddToggle("OptGraySky", { Text="Gray Sky", Default=Variables.Config.GraySky })
            :OnChanged(function(v) Variables.Config.GraySky = v if Variables.Config.Enabled and v then LightingApplyLow() end end)
        group:AddToggle("OptFullBright", { Text="Full Bright", Default=Variables.Config.FullBright })
            :OnChanged(function(v) Variables.Config.FullBright = v if Variables.Config.Enabled and v then LightingApplyLow() end end)
        group:AddToggle("OptMinQuality", { Text="Use Minimum Quality", Default=Variables.Config.UseMinimumQuality })
            :OnChanged(function(v) Variables.Config.UseMinimumQuality = v if Variables.Config.Enabled then if v then ApplyQuality(true) else RestoreQuality() end end end)
        group:AddToggle("OptClearBlurRestore", { Text="Force Clear Blur on Restore", Default=Variables.Config.ForceClearBlurOnRestore })
            :OnChanged(function(v) Variables.Config.ForceClearBlurOnRestore = v end)

        -- Lifecycle
        local function ModuleStop()
            if UI.Toggles.OptEnabled then UI.Toggles.OptEnabled:SetValue(false) end
            RestoreAll()
            Variables.Maids.Optimization:DoCleaning()
        end

        return { Name = "Optimization", Stop = ModuleStop }
    end
end
