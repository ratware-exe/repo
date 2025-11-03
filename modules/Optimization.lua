-- modules/Optimization.lua
do
    return function(UI)
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv = (getgenv and getgenv()) or _G
        GlobalEnv.Signal = GlobalEnv.Signal or loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()
        local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        -- Constants / Tags
        local TAG_FROZEN = "OptFrozen"

        -- State
        local Variables = {
            Maids = {
                Optimization = Maid.new(),
                Watchers     = Maid.new(), -- all event-driven; no polling
            },

            -- Config (defaults preserved)
            Config = {
                Enabled                      = false,

                -- Rendering / UI
                DisableThreeDRendering       = false,
                TargetFramesPerSecond        = 30,
                HidePlayerGui                = true,
                HideCoreGui                  = true,
                DisableViewportFrames        = true,
                DisableVideoFrames           = true,
                MuteAllSounds                = true,

                -- Animation / Motion
                PauseCharacterAnimations     = true,
                PauseOtherAnimations         = true,
                FreezeWorldAssemblies        = false,  -- reversible
                DisableConstraints           = true,   -- reversible (excludes Motor6D)

                -- Physics / Net
                AnchorCharacter              = true,
                ReduceSimulationRadius       = true,   -- best‑effort
                RemoveLocalNetworkOwnership  = true,

                -- Materials / Effects
                StopParticleSystems          = true,   -- reversible
                DestroyEmitters              = false,  -- irreversible
                SmoothPlasticEverywhere      = true,   -- reversible
                HideDecals                   = true,   -- reversible
                NukeTextures                 = false,  -- irreversible

                RemoveGrassDecoration        = true,   -- terrain/material service
                DisablePostEffects           = true,   -- Bloom/CC/DoF/SunRays/Blur (reversible)
                GraySky                      = true,   -- reversible
                FullBright                   = true,   -- reversible
                UseMinimumQuality            = true,   -- reversible
                ForceClearBlurOnRestore      = true,

                -- Water replacement (visual only)
                ReplaceWaterWithBlock        = false,
                WaterBlockTransparencyPercent= 25,    -- 0..100
                WaterBlockColorR             = 30,    -- 0..255
                WaterBlockColorG             = 85,    -- 0..255
                WaterBlockColorB             = 255,   -- 0..255
                WaterBlockY                  = 0,
                WaterBlockSizeX              = 20000,
                WaterBlockSizeZ              = 20000,
                WaterBlockThickness          = 2,
            },

            Snapshot = {
                RenderingEnabled             = true,
                SavedQuality                 = nil,

                PlayerGuiEnabled             = {}, -- ScreenGui -> bool
                CoreGuiState                 = {}, -- CoreGuiType -> bool

                ViewportVisible              = {}, -- ViewportFrame -> bool
                VideoPlaying                 = {}, -- VideoFrame -> bool
                SoundProps                   = {}, -- Sound -> {Volume, Playing}

                AnimatorGuards               = {}, -- Animator -> {Tracks={track->oldSpeed}, Conns={...}}
                AnimateScripts               = {}, -- LocalScript "Animate" under our character -> bool

                ConstraintEnabled            = {}, -- Constraint -> bool
                PartAnchored                 = {}, -- BasePart -> bool (for reversible freeze)
                CharacterAnchored            = {}, -- BasePart -> bool

                PartMaterial                 = {}, -- BasePart -> {Mat, Refl, CastShadow}
                DecalTransparency            = {}, -- Decal/Texture -> number
                EmitterEnabled               = {}, -- Emitter/Trail/Beam/Fire/Smoke -> bool

                LightingProps = {
                    GlobalShadows            = nil,
                    Brightness               = nil,
                    ClockTime                = nil,
                    Ambient                  = nil,
                    OutdoorAmbient           = nil,
                    EnvironmentDiffuseScale  = nil,
                    EnvironmentSpecularScale = nil,
                },
                PostEffects                  = {}, -- Effect -> Enabled
                TerrainDecoration            = nil,
                WaterTransparency            = nil,
            },

            Irreversible = {
                EmittersDestroyed            = false,
                TexturesNuked                = false,
            },

            State = {
                WaterProxyPart               = nil,

                -- Lighting guards (fix crash/timeout)
                LightingApplyInProgress      = false,
                LightingReapplyScheduled     = false,
                LightingLastApplyClock       = 0,
            },
        }

        ---------------------------------------------------------------------
        -- Utilities (no polling)
        ---------------------------------------------------------------------
        local function StoreOnce(map, key, value)
            if map[key] == nil then
                map[key] = value
            end
        end

        local function ColorsEqual3(a, b)
            return a and b and a.R == b.R and a.G == b.G and a.B == b.B
        end

        local function SetIfDifferent(object, prop, desired)
            local ok, current = pcall(function() return object[prop] end)
            if not ok then return end
            local doSet = false
            if typeof(desired) == "Color3" then
                doSet = not ColorsEqual3(current, desired)
            else
                doSet = current ~= desired
            end
            if doSet then pcall(function() object[prop] = desired end) end
        end

        local function EachDescendantChunked(root, predicate, action)
            local list = root:GetDescendants()
            local processed = 0
            for idx = 1, #list do
                local inst = list[idx]
                if not Variables.Config.Enabled then break end
                if predicate(inst) then action(inst) end
                processed = processed + 1
                if processed % 500 == 0 then task.wait() end
            end
        end

        local function TrySetFramesPerSecondCap(target)
            local c = {
                (getgenv and getgenv().setfpscap),
                rawget(_G, "setfpscap"),
                rawget(_G, "set_fps_cap"),
                rawget(_G, "setfps"),
                rawget(_G, "setfps_max"),
            }
            for i = 1, #c do
                local f = c[i]
                if typeof(f) == "function" then
                    if pcall(f, target) then return true end
                end
            end
            return false
        end

        ---------------------------------------------------------------------
        -- Sounds (per-Sound, reversible)
        ---------------------------------------------------------------------
        local function GuardSound(sound)
            if not sound or not sound:IsA("Sound") then return end
            StoreOnce(Variables.Snapshot.SoundProps, sound, {
                Volume  = (function() local ok,v=pcall(function() return sound.Volume end); return ok and v or 1 end)(),
                Playing = (function() local ok,v=pcall(function() return sound.Playing end); return ok and v or false end)(),
            })
            pcall(function() sound.Playing=false; sound.Volume=0 end)
            local vConn = sound:GetPropertyChangedSignal("Volume"):Connect(function()
                if Variables.Config.Enabled and Variables.Config.MuteAllSounds then
                    pcall(function() sound.Volume=0 end)
                end
            end)
            local pConn = sound:GetPropertyChangedSignal("Playing"):Connect(function()
                if Variables.Config.Enabled and Variables.Config.MuteAllSounds and sound.Playing then
                    pcall(function() sound.Playing=false end)
                end
            end)
            Variables.Maids.Watchers:GiveTask(vConn)
            Variables.Maids.Watchers:GiveTask(pConn)
        end

        local function ApplyMuteAllSounds()
            EachDescendantChunked(game, function(x) return x:IsA("Sound") end, GuardSound)
        end

        local function RestoreSounds()
            for snd, props in pairs(Variables.Snapshot.SoundProps) do
                pcall(function()
                    if snd and snd.Parent then
                        snd.Volume  = props.Volume
                        snd.Playing = props.Playing
                    end
                end)
                Variables.Snapshot.SoundProps[snd] = nil
            end
        end

        ---------------------------------------------------------------------
        -- Animations (character + others)
        ---------------------------------------------------------------------
        local function ShouldPauseAnimator(animator)
            local lp = RbxService.Players.LocalPlayer
            local ch = lp and lp.Character
            local isChar = ch and animator:IsDescendantOf(ch)
            if isChar then
                return Variables.Config.PauseCharacterAnimations
            else
                return Variables.Config.PauseOtherAnimations
            end
        end

        local function GuardAnimator(animator)
            if not animator or not animator:IsA("Animator") then return end
            if not ShouldPauseAnimator(animator) then return end
            if Variables.Snapshot.AnimatorGuards[animator] then return end

            local bundle = { Tracks = {}, Conns = {} }
            Variables.Snapshot.AnimatorGuards[animator] = bundle

            local function cacheAndFreeze(track)
                if not track then return end
                if bundle.Tracks[track] == nil then
                    local ok, spd = pcall(function() return track.Speed end)
                    bundle.Tracks[track] = ok and spd or 1
                end
                -- Try both methods locally; some remotes ignore AdjustSpeed but respect Stop(0)
                pcall(function() track:AdjustSpeed(0) end)
                pcall(function() track:Stop(0) end)
                table.insert(bundle.Conns, track.Stopped:Connect(function()
                    bundle.Tracks[track] = nil
                end))
            end

            local okL, list = pcall(function() return animator:GetPlayingAnimationTracks() end)
            if okL and list then
                for tIdx = 1, #list do cacheAndFreeze(list[tIdx]) end
            end

            table.insert(bundle.Conns, animator.AnimationPlayed:Connect(function(newTrack)
                if Variables.Config.Enabled and ShouldPauseAnimator(animator) then
                    cacheAndFreeze(newTrack)
                end
            end))

            table.insert(bundle.Conns, animator.AncestryChanged:Connect(function(_, parent)
                if parent == nil then
                    for i = 1, #bundle.Conns do local c = bundle.Conns[i]; if c then c:Disconnect() end end
                    Variables.Snapshot.AnimatorGuards[animator] = nil
                end
            end))
        end

        local function ReleaseAnimatorGuards()
            for animator, bundle in pairs(Variables.Snapshot.AnimatorGuards) do
                if bundle and bundle.Tracks then
                    for track, oldSpeed in pairs(bundle.Tracks) do
                        pcall(function() track:AdjustSpeed(oldSpeed or 1) end)
                    end
                end
                if bundle and bundle.Conns then
                    for i = 1, #bundle.Conns do local c = bundle.Conns[i]; if c then c:Disconnect() end end
                end
                Variables.Snapshot.AnimatorGuards[animator] = nil
            end
        end

        local function DisableCharacterAnimateScripts(enableBack)
            local lp = RbxService.Players.LocalPlayer
            local ch = lp and lp.Character
            if not ch then return end
            local children = ch:GetChildren()
            for i = 1, #children do
                local obj = children[i]
                if obj:IsA("LocalScript") and obj.Name == "Animate" then
                    if enableBack then
                        local prev = Variables.Snapshot.AnimateScripts[obj]
                        Variables.Snapshot.AnimateScripts[obj] = nil
                        if prev ~= nil then pcall(function() obj.Enabled = prev end) end
                    else
                        StoreOnce(Variables.Snapshot.AnimateScripts, obj,
                            (function() local ok,v=pcall(function() return obj.Enabled end); return ok and v or true end)())
                        pcall(function() obj.Enabled = false end)
                    end
                end
            end
        end

        ---------------------------------------------------------------------
        -- Particles / decals / materials
        ---------------------------------------------------------------------
        local function IsEmitter(x)
            return x:IsA("ParticleEmitter") or x:IsA("Trail") or x:IsA("Beam") or x:IsA("Fire") or x:IsA("Smoke")
        end

        local function StopEmitter(x)
            local ok, current = pcall(function() return x.Enabled end)
            StoreOnce(Variables.Snapshot.EmitterEnabled, x, ok and current or true)
            pcall(function() x.Enabled = false end)
            local conn = x:GetPropertyChangedSignal("Enabled"):Connect(function()
                if Variables.Config.Enabled and Variables.Config.StopParticleSystems then
                    pcall(function() x.Enabled = false end)
                end
            end)
            Variables.Maids.Watchers:GiveTask(conn)
            -- Clean snapshot if the instance disappears
            local ac = x.AncestryChanged:Connect(function(_, parent)
                if parent == nil then Variables.Snapshot.EmitterEnabled[x] = nil end
            end)
            Variables.Maids.Watchers:GiveTask(ac)
        end

        local function RestoreEmitters()
            for inst, old in pairs(Variables.Snapshot.EmitterEnabled) do
                pcall(function()
                    if inst and inst.Parent then inst.Enabled = old and true or false end
                end)
                Variables.Snapshot.EmitterEnabled[inst] = nil
            end
        end

        local function DestroyEmittersIrreversible(x)
            if IsEmitter(x) then pcall(function() x:Destroy() end) end
        end

        local function HideDecalOrTexture(x)
            if x:IsA("Decal") or x:IsA("Texture") then
                StoreOnce(Variables.Snapshot.DecalTransparency, x,
                    (function() local ok,v=pcall(function() return x.Transparency end); return ok and v or 0 end)())
                pcall(function() x.Transparency = 1 end)
            end
        end

        local function RestoreDecalsAndTextures()
            for inst, tr in pairs(Variables.Snapshot.DecalTransparency) do
                pcall(function() if inst and inst.Parent then inst.Transparency = tr end end)
                Variables.Snapshot.DecalTransparency[inst] = nil
            end
        end

        local function SmoothPlasticPart(x)
            if not x:IsA("BasePart") then return end
            local ch = RbxService.Players.LocalPlayer.Character
            if ch and x:IsDescendantOf(ch) then return end
            StoreOnce(Variables.Snapshot.PartMaterial, x, {
                Mat = x.Material, Reflectance = x.Reflectance, CastShadow = x.CastShadow
            })
            pcall(function()
                x.Material = Enum.Material.SmoothPlastic
                x.Reflectance = 0
                x.CastShadow = false
            end)
        end

        local function RestorePartMaterials()
            local processed = 0
            for part, props in pairs(Variables.Snapshot.PartMaterial) do
                pcall(function()
                    if part and part.Parent then
                        part.Material    = props.Mat
                        part.Reflectance = props.Reflectance
                        part.CastShadow  = props.CastShadow
                    end
                end)
                Variables.Snapshot.PartMaterial[part] = nil
                processed = processed + 1
                if processed % 500 == 0 then task.wait() end
            end
        end

        local function NukeTexturesIrreversible(x)
            if x:IsA("Decal") or x:IsA("Texture") or x:IsA("SurfaceAppearance") then
                pcall(function() x:Destroy() end)
            elseif x:IsA("MeshPart") or x:IsA("BasePart") then
                pcall(function() x.Material = Enum.Material.SmoothPlastic end)
            end
        end

        ---------------------------------------------------------------------
        -- Freeze world / constraints / ownership
        ---------------------------------------------------------------------
        local function FreezeWorldPart(p)
            if not p:IsA("BasePart") then return end
            local ch = RbxService.Players.LocalPlayer.Character
            if ch and p:IsDescendantOf(ch) then return end
            StoreOnce(Variables.Snapshot.PartAnchored, p, p.Anchored)
            pcall(function()
                p.AssemblyLinearVelocity  = Vector3.new()
                p.AssemblyAngularVelocity = Vector3.new()
                p.Anchored = true
                RbxService.CollectionService:AddTag(p, TAG_FROZEN)
            end)
            local ac = p.AncestryChanged:Connect(function(_, parent)
                if parent == nil then
                    Variables.Snapshot.PartAnchored[p] = nil
                    pcall(function() RbxService.CollectionService:RemoveTag(p, TAG_FROZEN) end)
                end
            end)
            Variables.Maids.Watchers:GiveTask(ac)
        end

        local function RestoreAnchoredParts()
            -- restore everything we snapshot
            local restored = 0
            for part, was in pairs(Variables.Snapshot.PartAnchored) do
                pcall(function()
                    if part and part.Parent then part.Anchored = was and true or false end
                    RbxService.CollectionService:RemoveTag(part, TAG_FROZEN)
                end)
                Variables.Snapshot.PartAnchored[part] = nil
                restored = restored + 1
                if restored % 500 == 0 then task.wait() end
            end
            -- clean any stragglers we tagged (safety net)
            local tagged = {}
            pcall(function() tagged = RbxService.CollectionService:GetTagged(TAG_FROZEN) end)
            for i = 1, #tagged do
                local q = tagged[i]
                pcall(function() RbxService.CollectionService:RemoveTag(q, TAG_FROZEN) end)
            end
        end

        local function DisableWorldConstraints()
            EachDescendantChunked(RbxService.Workspace, function(x)
                return x:IsA("Constraint") and not x:IsA("Motor6D")
            end, function(c)
                StoreOnce(Variables.Snapshot.ConstraintEnabled, c, c.Enabled)
                pcall(function() c.Enabled = false end)
            end)
        end

        local function RestoreWorldConstraints()
            local n = 0
            for c, old in pairs(Variables.Snapshot.ConstraintEnabled) do
                pcall(function() if c and c.Parent then c.Enabled = old and true or false end end)
                Variables.Snapshot.ConstraintEnabled[c] = nil
                n = n + 1
                if n % 500 == 0 then task.wait() end
            end
        end

        local function CharacterAnchorSet(on)
            local lp = RbxService.Players.LocalPlayer
            local ch = lp and lp.Character
            if not ch then return end
            local desc = ch:GetDescendants()
            for i = 1, #desc do
                local p = desc[i]
                if p:IsA("BasePart") then
                    StoreOnce(Variables.Snapshot.CharacterAnchored, p, p.Anchored)
                    pcall(function() p.Anchored = on and true or false end)
                end
            end
        end

        local function ReduceSimulationRadius()
            if not Variables.Config.ReduceSimulationRadius then return end
            local lp = RbxService.Players.LocalPlayer
            if not lp then return end
            local seth = sethiddenproperty or set_hidden_property or set_hidden_prop
            if seth then
                pcall(function()
                    seth(lp, "SimulationRadius", 0)
                    seth(lp, "MaxSimulationRadius", 0)
                end)
            end
        end

        local function RemoveNetOwnership()
            if not Variables.Config.RemoveLocalNetworkOwnership then return end
            EachDescendantChunked(RbxService.Workspace, function(x) return x:IsA("BasePart") end, function(p)
                pcall(function() if not p.Anchored then p:SetNetworkOwner(nil) end end)
            end)
        end

        ---------------------------------------------------------------------
        -- Lighting / PostFX (fixed re-apply loop + debounce)
        ---------------------------------------------------------------------
        local function SnapshotLighting()
            local L = RbxService.Lighting
            Variables.Snapshot.LightingProps.GlobalShadows            = L.GlobalShadows
            Variables.Snapshot.LightingProps.Brightness               = L.Brightness
            Variables.Snapshot.LightingProps.ClockTime                = L.ClockTime
            Variables.Snapshot.LightingProps.Ambient                  = L.Ambient
            Variables.Snapshot.LightingProps.OutdoorAmbient           = L.OutdoorAmbient
            Variables.Snapshot.LightingProps.EnvironmentDiffuseScale  = L.EnvironmentDiffuseScale
            Variables.Snapshot.LightingProps.EnvironmentSpecularScale = L.EnvironmentSpecularScale
        end

        local function ApplyLowLighting()
            if Variables.State.LightingApplyInProgress then return end
            Variables.State.LightingApplyInProgress = true
            local L = RbxService.Lighting
            -- set only when different to avoid re-trigger storms
            SetIfDifferent(L, "GlobalShadows", false)
            SetIfDifferent(L, "Brightness", 1)
            SetIfDifferent(L, "EnvironmentDiffuseScale", 0)
            SetIfDifferent(L, "EnvironmentSpecularScale", 0)
            if Variables.Config.GraySky then
                SetIfDifferent(L, "ClockTime", 12)
                SetIfDifferent(L, "Ambient",        Color3.fromRGB(128,128,128))
                SetIfDifferent(L, "OutdoorAmbient", Color3.fromRGB(128,128,128))
            end
            if Variables.Config.FullBright then
                SetIfDifferent(L, "Brightness", 2)
            end
            Variables.State.LightingApplyInProgress = false
            Variables.State.LightingLastApplyClock = os.clock()
        end

        local function ScheduleLightingReapply()
            if not (Variables.Config.GraySky or Variables.Config.FullBright) then return end
            if Variables.State.LightingReapplyScheduled then return end
            Variables.State.LightingReapplyScheduled = true
            task.delay(0.25, function()
                Variables.State.LightingReapplyScheduled = false
                if Variables.Config.Enabled then ApplyLowLighting() end
            end)
        end

        local function DisablePostEffects()
            local children = RbxService.Lighting:GetChildren()
            for i = 1, #children do
                local e = children[i]
                if e:IsA("BlurEffect") or e:IsA("SunRaysEffect") or e:IsA("ColorCorrectionEffect")
                   or e:IsA("BloomEffect") or e:IsA("DepthOfFieldEffect") then
                    StoreOnce(Variables.Snapshot.PostEffects, e, e.Enabled)
                    pcall(function() e.Enabled = false end)
                end
            end
        end

        local function RestorePostEffects()
            for e, was in pairs(Variables.Snapshot.PostEffects) do
                pcall(function() if e and e.Parent then e.Enabled = was and true or false end end)
                Variables.Snapshot.PostEffects[e] = nil
            end
        end

        local function TerrainDecorationSet(disable)
            local terrain = RbxService.Workspace:FindFirstChildOfClass("Terrain")
            if not terrain then return end
            if Variables.Snapshot.TerrainDecoration == nil then
                local ok, v = pcall(function() return terrain.Decoration end)
                if ok then Variables.Snapshot.TerrainDecoration = v end
            end
            pcall(function() if typeof(terrain.Decoration)=="boolean" then terrain.Decoration = not disable end end)
            if RbxService.MaterialService then
                pcall(function()
                    RbxService.MaterialService.FallbackMaterial = disable and Enum.Material.SmoothPlastic or Enum.Material.Plastic
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

        ---------------------------------------------------------------------
        -- Viewport/Video (PlayerGui + CoreGui)
        ---------------------------------------------------------------------
        local function DisableViewportAndVideoFramesScan()
            local function handle(root)
                if not root then return end
                EachDescendantChunked(root, function(i)
                    return i:IsA("ViewportFrame") or i:IsA("VideoFrame")
                end, function(f)
                    if f:IsA("ViewportFrame") and Variables.Config.DisableViewportFrames then
                        StoreOnce(Variables.Snapshot.ViewportVisible, f, f.Visible)
                        pcall(function() f.Visible = false end)
                    elseif f:IsA("VideoFrame") and Variables.Config.DisableVideoFrames then
                        StoreOnce(Variables.Snapshot.VideoPlaying, f, f.Playing)
                        pcall(function() f.Playing = false end)
                    end
                end)
            end
            local pg = RbxService.Players.LocalPlayer and RbxService.Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
            handle(pg); handle(RbxService.CoreGui)
        end

        local function RestoreViewportAndVideoFrames()
            for f, v in pairs(Variables.Snapshot.ViewportVisible) do
                pcall(function() if f and f.Parent then f.Visible = v and true or false end end)
                Variables.Snapshot.ViewportVisible[f] = nil
            end
            for f, p in pairs(Variables.Snapshot.VideoPlaying) do
                pcall(function() if f and f.Parent then f.Playing = p and true or false end end)
                Variables.Snapshot.VideoPlaying[f] = nil
            end
        end

        ---------------------------------------------------------------------
        -- GUI hiding
        ---------------------------------------------------------------------
        local function HidePlayerGuiAll()
            local pg = RbxService.Players.LocalPlayer and RbxService.Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
            if not pg then return end
            local kids = pg:GetChildren()
            for i = 1, #kids do
                local gui = kids[i]
                if gui:IsA("ScreenGui") then
                    StoreOnce(Variables.Snapshot.PlayerGuiEnabled, gui, gui.Enabled)
                    pcall(function() gui.Enabled = false end)
                end
            end
        end

        local function RestorePlayerGuiAll()
            for gui, en in pairs(Variables.Snapshot.PlayerGuiEnabled) do
                pcall(function() if gui and gui.Parent then gui.Enabled = en and true or false end end)
                Variables.Snapshot.PlayerGuiEnabled[gui] = nil
            end
        end

        local function HideCoreGuiAll(hidden)
            if Variables.Snapshot.CoreGuiState["__snap__"] == nil then
                for _, tp in ipairs({
                    Enum.CoreGuiType.Chat, Enum.CoreGuiType.Backpack, Enum.CoreGuiType.EmotesMenu,
                    Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.Health
                }) do
                    Variables.Snapshot.CoreGuiState[tp] = RbxService.StarterGui:GetCoreGuiEnabled(tp)
                end
                Variables.Snapshot.CoreGuiState["__snap__"] = true
            end
            for tp, _ in pairs(Variables.Snapshot.CoreGuiState) do
                if typeof(tp) == "EnumItem" then
                    pcall(function() RbxService.StarterGui:SetCoreGuiEnabled(tp, not hidden) end)
                end
            end
        end

        local function RestoreCoreGuiAll()
            for tp, was in pairs(Variables.Snapshot.CoreGuiState) do
                if typeof(tp) == "EnumItem" then
                    pcall(function() RbxService.StarterGui:SetCoreGuiEnabled(tp, was and true or false) end)
                end
            end
            Variables.Snapshot.CoreGuiState = {}
        end

        ---------------------------------------------------------------------
        -- Water replacement (visual proxy)
        ---------------------------------------------------------------------
        local function ApplyWaterReplacement()
            local terrain = RbxService.Workspace:FindFirstChildOfClass("Terrain")
            if terrain then
                if Variables.Snapshot.WaterTransparency == nil then
                    local ok, v = pcall(function() return terrain.WaterTransparency end)
                    if ok then Variables.Snapshot.WaterTransparency = v end
                end
                pcall(function() terrain.WaterTransparency = 1 end)
            end
            if Variables.State.WaterProxyPart and Variables.State.WaterProxyPart.Parent then
                pcall(function() Variables.State.WaterProxyPart:Destroy() end)
                Variables.State.WaterProxyPart = nil
            end
            local p = Instance.new("Part")
            p.Name = "WaterProxy"
            p.Anchored = true
            p.CanCollide = false
            p.Material = Enum.Material.SmoothPlastic
            p.Transparency = math.clamp(Variables.Config.WaterBlockTransparencyPercent / 100, 0, 1)
            p.Color = Color3.fromRGB(
                math.clamp(Variables.Config.WaterBlockColorR, 0, 255),
                math.clamp(Variables.Config.WaterBlockColorG, 0, 255),
                math.clamp(Variables.Config.WaterBlockColorB, 0, 255)
            )
            p.Size = Vector3.new(
                math.max(10, Variables.Config.WaterBlockSizeX),
                math.max(0.1, Variables.Config.WaterBlockThickness),
                math.max(10, Variables.Config.WaterBlockSizeZ)
            )
            p.CFrame = CFrame.new(0, Variables.Config.WaterBlockY, 0)
            p.Parent = RbxService.Workspace
            Variables.State.WaterProxyPart = p
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

        ---------------------------------------------------------------------
        -- Watchers (event‑driven; rebuilt on demand)
        ---------------------------------------------------------------------
        local function BuildWatchers()
            Variables.Maids.Watchers:DoCleaning()

            -- Workspace stream
            Variables.Maids.Watchers:GiveTask(RbxService.Workspace.DescendantAdded:Connect(function(inst)
                if not Variables.Config.Enabled then return end

                -- emitters
                if Variables.Config.DestroyEmitters and IsEmitter(inst) then
                    DestroyEmittersIrreversible(inst)
                elseif Variables.Config.StopParticleSystems and IsEmitter(inst) then
                    StopEmitter(inst)
                end

                -- materials & decals
                if Variables.Config.SmoothPlasticEverywhere and inst:IsA("BasePart") then SmoothPlasticPart(inst) end
                if Variables.Config.HideDecals and (inst:IsA("Decal") or inst:IsA("Texture")) then HideDecalOrTexture(inst) end

                -- freeze world
                if Variables.Config.FreezeWorldAssemblies and inst:IsA("BasePart") then FreezeWorldPart(inst) end

                -- ownership
                if Variables.Config.RemoveLocalNetworkOwnership and inst:IsA("BasePart") then
                    pcall(function() if not inst.Anchored then inst:SetNetworkOwner(nil) end end)
                end

                -- sounds
                if Variables.Config.MuteAllSounds and inst:IsA("Sound") then GuardSound(inst) end

                -- animators
                if inst:IsA("Animator") then GuardAnimator(inst) end
            end))

            -- PlayerGui/CoreGui stream (viewport/video + sounds + animators)
            local pg = RbxService.Players.LocalPlayer and RbxService.Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
            if pg then
                Variables.Maids.Watchers:GiveTask(pg.DescendantAdded:Connect(function(inst)
                    if not Variables.Config.Enabled then return end
                    if Variables.Config.DisableViewportFrames and inst:IsA("ViewportFrame") then
                        StoreOnce(Variables.Snapshot.ViewportVisible, inst, inst.Visible)
                        pcall(function() inst.Visible = false end)
                    elseif Variables.Config.DisableVideoFrames and inst:IsA("VideoFrame") then
                        StoreOnce(Variables.Snapshot.VideoPlaying, inst, inst.Playing)
                        pcall(function() inst.Playing = false end)
                    end
                    if Variables.Config.MuteAllSounds and inst:IsA("Sound") then GuardSound(inst) end
                    if inst:IsA("Animator") then GuardAnimator(inst) end
                end))
            end

            Variables.Maids.Watchers:GiveTask(RbxService.CoreGui.DescendantAdded:Connect(function(inst)
                if not Variables.Config.Enabled then return end
                if Variables.Config.DisableViewportFrames and inst:IsA("ViewportFrame") then
                    StoreOnce(Variables.Snapshot.ViewportVisible, inst, inst.Visible)
                    pcall(function() inst.Visible = false end)
                elseif Variables.Config.DisableVideoFrames and inst:IsA("VideoFrame") then
                    StoreOnce(Variables.Snapshot.VideoPlaying, inst, inst.Playing)
                    pcall(function() inst.Playing = false end)
                end
                if Variables.Config.MuteAllSounds and inst:IsA("Sound") then GuardSound(inst) end
                if inst:IsA("Animator") then GuardAnimator(inst) end
            end))

            -- Lighting guards (debounced; no self-loop)
            Variables.Maids.Watchers:GiveTask(RbxService.Lighting.ChildAdded:Connect(function(child)
                if not Variables.Config.Enabled then return end
                if Variables.Config.DisablePostEffects and (child:IsA("BlurEffect") or child:IsA("SunRaysEffect")
                    or child:IsA("ColorCorrectionEffect") or child:IsA("BloomEffect") or child:IsA("DepthOfFieldEffect")) then
                    StoreOnce(Variables.Snapshot.PostEffects, child, child.Enabled)
                    pcall(function() child.Enabled = false end)
                end
                ScheduleLightingReapply()
            end))
            Variables.Maids.Watchers:GiveTask(RbxService.Lighting.Changed:Connect(function()
                if not Variables.Config.Enabled then return end
                if Variables.State.LightingApplyInProgress then return end
                ScheduleLightingReapply()
            end))
        end

        ---------------------------------------------------------------------
        -- Apply / Restore
        ---------------------------------------------------------------------
        local function ApplyAll()
            Variables.Config.Enabled = true

            Variables.Snapshot.RenderingEnabled = true
            SnapshotLighting()

            if Variables.Config.DisableThreeDRendering then
                pcall(function() RbxService.RunService:Set3dRenderingEnabled(false) end)
            end
            if Variables.Config.TargetFramesPerSecond > 0 then
                TrySetFramesPerSecondCap(Variables.Config.TargetFramesPerSecond)
            end

            if Variables.Config.HidePlayerGui then HidePlayerGuiAll() end
            if Variables.Config.HideCoreGui  then HideCoreGuiAll(true) end

            if Variables.Config.DisableViewportFrames or Variables.Config.DisableVideoFrames then
                DisableViewportAndVideoFramesScan()
            end
            if Variables.Config.MuteAllSounds then ApplyMuteAllSounds() end

            EachDescendantChunked(RbxService.Workspace, function(x) return x:IsA("Animator") end, GuardAnimator)
            if Variables.Config.PauseCharacterAnimations then DisableCharacterAnimateScripts(false) end

            if Variables.Config.FreezeWorldAssemblies then
                EachDescendantChunked(RbxService.Workspace, function(x) return x:IsA("BasePart") end, FreezeWorldPart)
            end
            if Variables.Config.DisableConstraints then DisableWorldConstraints() end

            if Variables.Config.AnchorCharacter then CharacterAnchorSet(true) end
            ReduceSimulationRadius()
            RemoveNetOwnership()

            if Variables.Config.StopParticleSystems then
                EachDescendantChunked(RbxService.Workspace, IsEmitter, StopEmitter)
            end
            if Variables.Config.DestroyEmitters and not Variables.Irreversible.EmittersDestroyed then
                EachDescendantChunked(RbxService.Workspace, IsEmitter, DestroyEmittersIrreversible)
                Variables.Irreversible.EmittersDestroyed = true
            end
            if Variables.Config.SmoothPlasticEverywhere then
                EachDescendantChunked(RbxService.Workspace, function(x) return x:IsA("BasePart") end, SmoothPlasticPart)
            end
            if Variables.Config.HideDecals then
                EachDescendantChunked(RbxService.Workspace, function(x) return x:IsA("Decal") or x:IsA("Texture") end, HideDecalOrTexture)
            end
            if Variables.Config.NukeTextures and not Variables.Irreversible.TexturesNuked then
                EachDescendantChunked(RbxService.Workspace, function(x)
                    return x:IsA("Decal") or x:IsA("Texture") or x:IsA("SurfaceAppearance") or x:IsA("MeshPart") or x:IsA("BasePart")
                end, NukeTexturesIrreversible)
                Variables.Irreversible.TexturesNuked = true
            end

            if Variables.Config.RemoveGrassDecoration then TerrainDecorationSet(true) end
            if Variables.Config.DisablePostEffects    then DisablePostEffects() end
            if Variables.Config.GraySky or Variables.Config.FullBright then ApplyLowLighting() end
            if Variables.Config.UseMinimumQuality then ApplyQualityMinimum() end

            if Variables.Config.ReplaceWaterWithBlock then ApplyWaterReplacement() end

            BuildWatchers()
        end

        local function RestoreAll()
            Variables.Config.Enabled = false
            Variables.Maids.Watchers:DoCleaning()

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

            -- Lighting/PostFX restore
            pcall(function()
                local p = Variables.Snapshot.LightingProps
                if p then
                    local L = RbxService.Lighting
                    L.GlobalShadows            = p.GlobalShadows
                    L.Brightness               = p.Brightness
                    L.ClockTime                = p.ClockTime
                    L.Ambient                  = p.Ambient
                    L.OutdoorAmbient           = p.OutdoorAmbient
                    L.EnvironmentDiffuseScale  = p.EnvironmentDiffuseScale
                    L.EnvironmentSpecularScale = p.EnvironmentSpecularScale
                end
                if Variables.Config.ForceClearBlurOnRestore then
                    local kids = RbxService.Lighting:GetChildren()
                    for i = 1, #kids do if kids[i]:IsA("BlurEffect") then kids[i].Enabled = false end end
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

            Variables.Snapshot.PlayerGuiEnabled = {}
            Variables.Snapshot.CoreGuiState     = {}
            Variables.Snapshot.ViewportVisible  = {}
            Variables.Snapshot.VideoPlaying     = {}
        end

        ---------------------------------------------------------------------
        -- UI (labels fixed; immediate reactions; no polling)
        ---------------------------------------------------------------------
        local grp = UI.Tabs.Misc:AddRightGroupbox("Optimization", "power")

        grp:AddToggle("OptEnabled", { Text="Enable Optimization", Default=false })
            :OnChanged(function(x) if x then ApplyAll() else RestoreAll() end end)

        grp:AddSlider("OptFps", {
            Text = "Target FPS",
            Min = 1, Max = 120,
            Default = Variables.Config.TargetFramesPerSecond,
            Suffix = "FPS",
        }):OnChanged(function(v)
            Variables.Config.TargetFramesPerSecond = math.floor(v)
            if Variables.Config.Enabled then
                TrySetFramesPerSecondCap(Variables.Config.TargetFramesPerSecond)
                -- Tip if executor ignores ultra-low caps
                if Variables.Config.TargetFramesPerSecond <= 5 and not Variables.Config.DisableThreeDRendering then
                    RbxService.StarterGui:SetCore("SendNotification", {
                        Title = "Optimization",
                        Text  = "If 1–5 FPS cap is ignored by your executor, toggle \"Disable 3D Rendering\" for maximum savings.",
                        Duration = 4
                    })
                end
            end
        end)

        grp:AddDivider(); grp:AddLabel("Rendering / UI")
        grp:AddToggle("Opt3D", { Text="Disable 3D Rendering", Default=Variables.Config.DisableThreeDRendering })
            :OnChanged(function(s)
                Variables.Config.DisableThreeDRendering = s
                if Variables.Config.Enabled then pcall(function() RbxService.RunService:Set3dRenderingEnabled(not s and true or false) end) end
            end)
        grp:AddToggle("OptHidePlayerGui", { Text="Hide PlayerGui", Default=Variables.Config.HidePlayerGui })
            :OnChanged(function(s) Variables.Config.HidePlayerGui=s; if Variables.Config.Enabled then if s then HidePlayerGuiAll() else RestorePlayerGuiAll() end end end)
        grp:AddToggle("OptHideCoreGui", { Text="Hide CoreGui", Default=Variables.Config.HideCoreGui })
            :OnChanged(function(s) Variables.Config.HideCoreGui=s; if Variables.Config.Enabled then HideCoreGuiAll(s) end end)
        grp:AddToggle("OptNoViewports", { Text="Disable ViewportFrames", Default=Variables.Config.DisableViewportFrames })
            :OnChanged(function(s) Variables.Config.DisableViewportFrames=s; if Variables.Config.Enabled then if s then DisableViewportAndVideoFramesScan() else RestoreViewportAndVideoFrames() end; BuildWatchers() end end)
        grp:AddToggle("OptNoVideos", { Text="Disable VideoFrames", Default=Variables.Config.DisableVideoFrames })
            :OnChanged(function(s) Variables.Config.DisableVideoFrames=s; if Variables.Config.Enabled then if s then DisableViewportAndVideoFramesScan() else RestoreViewportAndVideoFrames() end; BuildWatchers() end end)
        grp:AddToggle("OptMute", { Text="Mute All Sounds", Default=Variables.Config.MuteAllSounds })
            :OnChanged(function(s) Variables.Config.MuteAllSounds=s; if Variables.Config.Enabled then if s then ApplyMuteAllSounds() else RestoreSounds() end; BuildWatchers() end end)

        grp:AddDivider(); grp:AddLabel("Animation / Motion")
        grp:AddToggle("OptPauseCharAnim", { Text="Pause Character Animations", Default=Variables.Config.PauseCharacterAnimations })
            :OnChanged(function(s) Variables.Config.PauseCharacterAnimations=s; if Variables.Config.Enabled then if s then DisableCharacterAnimateScripts(false) else DisableCharacterAnimateScripts(true); ReleaseAnimatorGuards() end; BuildWatchers() end end)
        grp:AddToggle("OptPauseOtherAnim", { Text="Pause Other Animations (best-effort)", Default=Variables.Config.PauseOtherAnimations })
            :OnChanged(function(s) Variables.Config.PauseOtherAnimations=s; if Variables.Config.Enabled then if s then EachDescendantChunked(RbxService.Workspace,function(x) return x:IsA("Animator") end, GuardAnimator) else ReleaseAnimatorGuards() end; BuildWatchers() end end)
        grp:AddToggle("OptFreezeWorld", { Text="Freeze World Assemblies (reversible)", Default=Variables.Config.FreezeWorldAssemblies })
            :OnChanged(function(s) Variables.Config.FreezeWorldAssemblies=s; if Variables.Config.Enabled then if s then EachDescendantChunked(RbxService.Workspace,function(x) return x:IsA("BasePart") end, FreezeWorldPart) else RestoreAnchoredParts() end; BuildWatchers() end end)
        grp:AddToggle("OptNoConstraints", { Text="Disable Constraints (reversible)", Default=Variables.Config.DisableConstraints })
            :OnChanged(function(s) Variables.Config.DisableConstraints=s; if Variables.Config.Enabled then if s then DisableWorldConstraints() else RestoreWorldConstraints() end end end)

        grp:AddDivider(); grp:AddLabel("Physics / Network")
        grp:AddToggle("OptAnchorChar", { Text="Anchor Character", Default=Variables.Config.AnchorCharacter })
            :OnChanged(function(s) Variables.Config.AnchorCharacter=s; if Variables.Config.Enabled then CharacterAnchorSet(s) end end)
        grp:AddToggle("OptSimRadius", { Text="Reduce Simulation Radius", Default=Variables.Config.ReduceSimulationRadius })
            :OnChanged(function(s) Variables.Config.ReduceSimulationRadius=s; if Variables.Config.Enabled and s then ReduceSimulationRadius() end end)
        grp:AddToggle("OptNoNetOwner", { Text="Remove Local Network Ownership", Default=Variables.Config.RemoveLocalNetworkOwnership })
            :OnChanged(function(s) Variables.Config.RemoveLocalNetworkOwnership=s; if Variables.Config.Enabled and s then RemoveNetOwnership() end; if Variables.Config.Enabled then BuildWatchers() end end)

        grp:AddDivider(); grp:AddLabel("Particles / Effects / Materials")
        grp:AddToggle("OptStopParticles", { Text="Stop Particle Systems (reversible)", Default=Variables.Config.StopParticleSystems })
            :OnChanged(function(s)
                Variables.Config.StopParticleSystems=s
                if Variables.Config.Enabled then if s then EachDescendantChunked(RbxService.Workspace, IsEmitter, StopEmitter) else RestoreEmitters() end; BuildWatchers() end
            end)
        grp:AddToggle("OptDestroyEmitters", { Text="Destroy Emitters (irreversible)", Default=Variables.Config.DestroyEmitters })
            :OnChanged(function(s) Variables.Config.DestroyEmitters=s; if Variables.Config.Enabled and s and not Variables.Irreversible.EmittersDestroyed then EachDescendantChunked(RbxService.Workspace, IsEmitter, DestroyEmittersIrreversible); Variables.Irreversible.EmittersDestroyed=true; BuildWatchers() end end)
        grp:AddToggle("OptSmoothPlastic", { Text="Force SmoothPlastic (reversible)", Default=Variables.Config.SmoothPlasticEverywhere })
            :OnChanged(function(s) Variables.Config.SmoothPlasticEverywhere=s; if Variables.Config.Enabled then if s then EachDescendantChunked(RbxService.Workspace,function(x) return x:IsA("BasePart") end, SmoothPlasticPart); BuildWatchers() else RestorePartMaterials() end end end)
        grp:AddToggle("OptHideDecals", { Text="Hide Decals/Textures (reversible)", Default=Variables.Config.HideDecals })
            :OnChanged(function(s) Variables.Config.HideDecals=s; if Variables.Config.Enabled then if s then EachDescendantChunked(RbxService.Workspace,function(x) return x:IsA("Decal") or x:IsA("Texture") end, HideDecalOrTexture); BuildWatchers() else RestoreDecalsAndTextures() end end end)
        grp:AddToggle("OptNukeTextures", { Text="Nuke Textures (irreversible)", Default=Variables.Config.NukeTextures })
            :OnChanged(function(s) Variables.Config.NukeTextures=s; if Variables.Config.Enabled and s and not Variables.Irreversible.TexturesNuked then EachDescendantChunked(RbxService.Workspace,function(x) return x:IsA("Decal") or x:IsA("Texture") or x:IsA("SurfaceAppearance") or x:IsA("MeshPart") or x:IsA("BasePart") end, NukeTexturesIrreversible); Variables.Irreversible.TexturesNuked=true; BuildWatchers() end end)

        grp:AddDivider(); grp:AddLabel("Lighting / Quality")
        grp:AddToggle("OptNoGrass", { Text="Remove Grass Decoration", Default=Variables.Config.RemoveGrassDecoration })
            :OnChanged(function(s) Variables.Config.RemoveGrassDecoration=s; if Variables.Config.Enabled then TerrainDecorationSet(s) end end)
        grp:AddToggle("OptNoPostFX", { Text="Disable Post‑FX (Bloom/CC/DoF/SunRays/Blur)", Default=Variables.Config.DisablePostEffects })
            :OnChanged(function(s) Variables.Config.DisablePostEffects=s; if Variables.Config.Enabled then if s then DisablePostEffects() else RestorePostEffects() end; BuildWatchers() end end)
        grp:AddToggle("OptGraySky", { Text="Gray Sky", Default=Variables.Config.GraySky })
            :OnChanged(function(s) Variables.Config.GraySky=s; if Variables.Config.Enabled and s then ApplyLowLighting() end; if Variables.Config.Enabled then BuildWatchers() end end)
        grp:AddToggle("OptFullBright", { Text="Full Bright", Default=Variables.Config.FullBright })
            :OnChanged(function(s) Variables.Config.FullBright=s; if Variables.Config.Enabled and s then ApplyLowLighting() end; if Variables.Config.Enabled then BuildWatchers() end end)
        grp:AddToggle("OptMinQuality", { Text="Use Minimum Quality", Default=Variables.Config.UseMinimumQuality })
            :OnChanged(function(s) Variables.Config.UseMinimumQuality=s; if Variables.Config.Enabled then if s then ApplyQualityMinimum() else RestoreQuality() end end end)
        grp:AddToggle("OptClearBlurRestore", { Text="Force Clear Blur on Restore", Default=Variables.Config.ForceClearBlurOnRestore })
            :OnChanged(function(s) Variables.Config.ForceClearBlurOnRestore=s end)

        grp:AddDivider(); grp:AddLabel("Water Replacement (visual)")
        grp:AddToggle("OptWaterProxy", { Text="Replace Water With Block", Default=Variables.Config.ReplaceWaterWithBlock })
            :OnChanged(function(s) Variables.Config.ReplaceWaterWithBlock=s; if not Variables.Config.Enabled then return end; if s then ApplyWaterReplacement() else RemoveWaterReplacement() end end)
        grp:AddSlider("OptWaterTransparency", { Text="Transparency", Min=0, Max=100, Default=Variables.Config.WaterBlockTransparencyPercent, Suffix="%" })
            :OnChanged(function(v) Variables.Config.WaterBlockTransparencyPercent=math.floor(v); if Variables.State.WaterProxyPart then Variables.State.WaterProxyPart.Transparency = math.clamp(Variables.Config.WaterBlockTransparencyPercent/100,0,1) end end)
        grp:AddSlider("OptWaterR", { Text="Red", Min=0, Max=255, Default=Variables.Config.WaterBlockColorR })
            :OnChanged(function(v) Variables.Config.WaterBlockColorR=math.floor(v); if Variables.State.WaterProxyPart then Variables.State.WaterProxyPart.Color = Color3.fromRGB(Variables.Config.WaterBlockColorR,Variables.Config.WaterBlockColorG,Variables.Config.WaterBlockColorB) end end)
        grp:AddSlider("OptWaterG", { Text="Green", Min=0, Max=255, Default=Variables.Config.WaterBlockColorG })
            :OnChanged(function(v) Variables.Config.WaterBlockColorG=math.floor(v); if Variables.State.WaterProxyPart then Variables.State.WaterProxyPart.Color = Color3.fromRGB(Variables.Config.WaterBlockColorR,Variables.Config.WaterBlockColorG,Variables.Config.WaterBlockColorB) end end)
        grp:AddSlider("OptWaterB", { Text="Blue", Min=0, Max=255, Default=Variables.Config.WaterBlockColorB })
            :OnChanged(function(v) Variables.Config.WaterBlockColorB=math.floor(v); if Variables.State.WaterProxyPart then Variables.State.WaterProxyPart.Color = Color3.fromRGB(Variables.Config.WaterBlockColorR,Variables.Config.WaterBlockColorG,Variables.Config.WaterBlockColorB) end end)
        grp:AddSlider("OptWaterY", { Text="Y Level", Min=-1000, Max=1000, Default=Variables.Config.WaterBlockY })
            :OnChanged(function(v) Variables.Config.WaterBlockY=math.floor(v); if Variables.State.WaterProxyPart then Variables.State.WaterProxyPart.CFrame = CFrame.new(0,Variables.Config.WaterBlockY,0) end end)
        grp:AddSlider("OptWaterSizeX", { Text="Size X", Min=1000, Max=40000, Default=Variables.Config.WaterBlockSizeX })
            :OnChanged(function(v) Variables.Config.WaterBlockSizeX=math.floor(v); if Variables.State.WaterProxyPart then Variables.State.WaterProxyPart.Size = Vector3.new(Variables.Config.WaterBlockSizeX, Variables.State.WaterProxyPart.Size.Y, Variables.State.WaterProxyPart.Size.Z) end end)
        grp:AddSlider("OptWaterSizeZ", { Text="Size Z", Min=1000, Max=40000, Default=Variables.Config.WaterBlockSizeZ })
            :OnChanged(function(v) Variables.Config.WaterBlockSizeZ=math.floor(v); if Variables.State.WaterProxyPart then Variables.State.WaterProxyPart.Size = Vector3.new(Variables.State.WaterProxyPart.Size.X, Variables.State.WaterProxyPart.Size.Y, Variables.Config.WaterBlockSizeZ) end end)
        grp:AddSlider("OptWaterThickness", { Text="Thickness", Min=1, Max=50, Default=Variables.Config.WaterBlockThickness })
            :OnChanged(function(v) Variables.Config.WaterBlockThickness=math.floor(v); if Variables.State.WaterProxyPart then Variables.State.WaterProxyPart.Size = Vector3.new(Variables.State.WaterProxyPart.Size.X, Variables.Config.WaterBlockThickness, Variables.State.WaterProxyPart.Size.Z) end end)

        -- Module Stop
        local function ModuleStop()
            if UI.Toggles.OptEnabled then UI.Toggles.OptEnabled:SetValue(false) end
            RestoreAll()
            Variables.Maids.Optimization:DoCleaning()
        end

        return { Name = "Optimization", Stop = ModuleStop }
    end
end
