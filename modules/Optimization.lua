-- modules/Optimization.lua
do
    return function(UI)
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv = (getgenv and getgenv()) or _G
        GlobalEnv.Signal = GlobalEnv.Signal or loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()
        local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

    ------------------------------------------------------------------------
    -- State
    ------------------------------------------------------------------------
    local Variables = {
        Maids = {
            Optimization  = Maid.new(),
            Watchers      = Maid.new(),
            EmitGuards    = Maid.new(),  -- guards .Enabled while reversible stop is ON
        },
        Config = {
            Enabled = false,

            -- Rendering / UI
            DisableThreeDRendering = false,
            TargetFPS              = 30,
            HidePlayerGui          = true,
            HideCoreGui            = true,
            DisableViewportFrames  = true,
            DisableVideoFrames     = true,
            MuteAllSounds          = true,

            -- Animation / Motion
            PauseCharacterAnimations = true,
            PauseOtherAnimations     = true, -- client-driven Animators (NPC/UI/props)
            FreezeWorldAssemblies    = false,
            DisableConstraints       = true, -- excludes Motor6D

            -- Physics / Network
            AnchorCharacter            = true,
            ReduceSimulationRadius     = true,
            RemoveLocalNetworkOwnership= true,

            -- Materials / Effects
            StopParticleSystems      = true,    -- reversible
            DestroyEmitters          = false,   -- irreversible
            SmoothPlasticEverywhere  = true,    -- reversible
            HideDecals               = true,    -- reversible
            NukeTextures             = false,   -- irreversible

            RemoveGrassDecoration    = true,
            DisablePostEffects       = true,    -- Bloom/CC/DoF/SunRays/Blur
            GraySky                  = true,
            FullBright               = true,
            UseMinimumQuality        = true,
            ForceClearBlurOnRestore  = true,

            -- Water replacement (visual)
            ReplaceWaterWithBlock    = false,
            WaterBlockColor          = Color3.fromRGB(30,85,255),
            WaterBlockTransparency   = 0.25, -- 0..1
            WaterY                   = 0,
            WaterSizeX               = 20000,
            WaterSizeZ               = 20000,
            WaterThickness           = 2,
        },

        Snapshot = {
            PlayerGuiEnabled   = {},   -- ScreenGui -> bool
            CoreGuiState       = {},   -- CoreGuiType -> bool
            ViewportVisible    = {},   -- ViewportFrame -> bool
            VideoPlaying       = {},   -- VideoFrame -> bool
            SoundProps         = {},   -- Sound -> {Volume, Playing}

            AnimatorGuards     = {},   -- Animator -> {tracks={track->oldSpeed}, conns={...}}

            ConstraintEnabled  = {},   -- Constraint -> bool
            PartAnchored       = {},   -- BasePart -> bool
            CharAnchored       = {},   -- BasePart -> bool

            PartMaterial       = {},   -- BasePart -> {Material, Reflectance, CastShadow}
            DecalTransparency  = {},   -- Decal/Texture -> number
            EmitterEnabled     = {},   -- Emitter -> bool

            LightingProps      = {},   -- for restore
            PostEffects        = {},   -- Effect -> Enabled
            TerrainDecoration  = nil,  -- bool
            QualityLevel       = nil,  -- Enum.QualityLevel

            WaterTransparency  = nil,  -- Terrain.WaterTransparency
        },

        Irreversible = {
            EmittersDestroyed = false,
            TexturesNuked     = false,
        },

        Runtime = {
            WaterProxyPart = nil,
            LightDebounce  = false, -- prevent recursive ApplyLowLighting storms
        },
    }

    ------------------------------------------------------------------------
    -- Small utils
    ------------------------------------------------------------------------
    local function storeOnce(map, key, value)
        if map[key] == nil then map[key] = value end
    end

    local function eachDescendantChunked(root, pred, act)
        local d = root:GetDescendants()
        for i = 1, #d do
            local inst = d[i]
            if Variables.Config.Enabled == false then break end
            if pred(inst) then act(inst) end
            if (i % 500) == 0 then task.wait() end
        end
    end

    local function setFpsCap(target)
        local candidates = {
            (getgenv and getgenv().setfpscap),
            rawget(_G,"setfpscap"),
            rawget(_G,"set_fps_cap"),
            rawget(_G,"setfps"),
            rawget(_G,"setfps_max")
        }
        for _,fn in ipairs(candidates) do
            if typeof(fn) == "function" then
                local ok = pcall(fn, target)
                if ok then return true end
            end
        end
        return false
    end

    ------------------------------------------------------------------------
    -- Sounds
    ------------------------------------------------------------------------
    local function guardSound(s)
        if not s or not s:IsA("Sound") then return end
        storeOnce(Variables.Snapshot.SoundProps, s, {
            Volume = (function() local ok,v=pcall(function() return s.Volume end) return ok and v or 1 end)(),
            Playing= (function() local ok,v=pcall(function() return s.Playing end) return ok and v or false end)(),
        })
        pcall(function() s.Playing = false s.Volume = 0 end)

        -- Guard (while option ON)
        local c1 = s:GetPropertyChangedSignal("Volume"):Connect(function()
            if Variables.Config.Enabled and Variables.Config.MuteAllSounds then pcall(function() s.Volume = 0 end) end
        end)
        local c2 = s:GetPropertyChangedSignal("Playing"):Connect(function()
            if Variables.Config.Enabled and Variables.Config.MuteAllSounds and s.Playing then pcall(function() s.Playing = false end) end
        end)
        Variables.Maids.Watchers:GiveTask(c1)
        Variables.Maids.Watchers:GiveTask(c2)
    end

    local function applyMuteAllSounds()
        eachDescendantChunked(game, function(x) return x:IsA("Sound") end, guardSound)
    end

    local function restoreSounds()
        Variables.Maids.Watchers:DoCleaning() -- disconnect property guards we attached for sounds/frames (safe)
        for s,props in pairs(Variables.Snapshot.SoundProps) do
            pcall(function()
                if s and s.Parent then
                    s.Volume  = props.Volume
                    s.Playing = props.Playing
                end
            end)
            Variables.Snapshot.SoundProps[s] = nil
        end
    end

    ------------------------------------------------------------------------
    -- Animations
    ------------------------------------------------------------------------
    local function shouldPauseAnimator(anim)
        local lp  = RbxService.Players.LocalPlayer
        local chr = lp and lp.Character
        local isChar = chr and anim:IsDescendantOf(chr)
        return isChar and Variables.Config.PauseCharacterAnimations or Variables.Config.PauseOtherAnimations
    end

    local function guardAnimator(anim)
        if not anim or not anim:IsA("Animator") then return end
        if not shouldPauseAnimator(anim) then return end
        if Variables.Snapshot.AnimatorGuards[anim] then return end

        local guard = { tracks = {}, conns = {} }
        Variables.Snapshot.AnimatorGuards[anim] = guard

        local function speedOf(track)
            local ok,s = pcall(function() return track.Speed end)
            return (ok and typeof(s)=="number") and s or 1
        end
        local function freeze(track)
            if not track then return end
            if guard.tracks[track] == nil then guard.tracks[track] = speedOf(track) end
            pcall(function() track:AdjustSpeed(0) end)
            table.insert(guard.conns, track.Stopped:Connect(function() guard.tracks[track] = nil end))
        end

        local ok, list = pcall(function() return anim:GetPlayingAnimationTracks() end)
        if ok and list then for _,t in ipairs(list) do freeze(t) end end

        table.insert(guard.conns, anim.AnimationPlayed:Connect(function(t)
            if Variables.Config.Enabled and shouldPauseAnimator(anim) then freeze(t) end
        end))
        table.insert(guard.conns, anim.AncestryChanged:Connect(function(_,p)
            if p==nil then
                for _,c in ipairs(guard.conns) do if c then c:Disconnect() end end
                Variables.Snapshot.AnimatorGuards[anim] = nil
            end
        end))
    end

    local function releaseAnimatorGuards()
        for anim,b in pairs(Variables.Snapshot.AnimatorGuards) do
            if b and b.tracks then
                for track,spd in pairs(b.tracks) do pcall(function() track:AdjustSpeed(spd or 1) end) end
            end
            if b and b.conns then for _,c in ipairs(b.conns) do if c then c:Disconnect() end end end
            Variables.Snapshot.AnimatorGuards[anim] = nil
        end
    end

    local function toggleCharacterAnimateScripts(enableBack)
        local lp = RbxService.Players.LocalPlayer
        local ch = lp and lp.Character
        if not ch then return end
        for _,c in ipairs(ch:GetChildren()) do
            if c:IsA("LocalScript") and c.Name=="Animate" then
                if enableBack then
                    local prev = Variables.Snapshot.AnimateFlag and Variables.Snapshot.AnimateFlag[c]
                    if prev ~= nil then pcall(function() c.Enabled = prev end) end
                else
                    Variables.Snapshot.AnimateFlag = Variables.Snapshot.AnimateFlag or {}
                    Variables.Snapshot.AnimateFlag[c] = c.Enabled
                    pcall(function() c.Enabled = false end)
                end
            end
        end
    end

    ------------------------------------------------------------------------
    -- Particles / decals / materials
    ------------------------------------------------------------------------
    local function isEmitter(x)
        return x:IsA("ParticleEmitter") or x:IsA("Trail") or x:IsA("Beam") or x:IsA("Fire") or x:IsA("Smoke")
    end

    local function stopEmitter(e)
        local ok,en = pcall(function() return e.Enabled end)
        storeOnce(Variables.Snapshot.EmitterEnabled, e, ok and en or true)
        pcall(function() e.Enabled = false end)

        local c1 = e:GetPropertyChangedSignal("Enabled"):Connect(function()
            if Variables.Config.Enabled and Variables.Config.StopParticleSystems then pcall(function() e.Enabled = false end) end
        end)
        local c2 = e.AncestryChanged:Connect(function(_,p)
            if p==nil then Variables.Snapshot.EmitterEnabled[e] = nil end
        end)
        Variables.Maids.EmitGuards:GiveTask(c1)
        Variables.Maids.EmitGuards:GiveTask(c2)
    end

    local function restoreEmitters()
        Variables.Maids.EmitGuards:DoCleaning()
        for e,en in pairs(Variables.Snapshot.EmitterEnabled) do
            pcall(function() if e and e.Parent then e.Enabled = en and true or false end end)
            Variables.Snapshot.EmitterEnabled[e] = nil
        end
    end

    local function destroyEmitterIrreversible(e)
        if isEmitter(e) then pcall(function() e:Destroy() end) end
    end

    local function hideDecal(tex)
        if tex:IsA("Decal") or tex:IsA("Texture") then
            storeOnce(Variables.Snapshot.DecalTransparency, tex, (function() local ok,v=pcall(function() return tex.Transparency end) return ok and v or 0 end)())
            pcall(function() tex.Transparency = 1 end)
        end
    end

    local function restoreDecals()
        for d,t in pairs(Variables.Snapshot.DecalTransparency) do
            pcall(function() if d and d.Parent then d.Transparency = t end end)
            Variables.Snapshot.DecalTransparency[d] = nil
        end
    end

    local function smoothPlastic(part)
        if not part:IsA("BasePart") then return end
        local lp = RbxService.Players.LocalPlayer
        local ch = lp and lp.Character
        if ch and part:IsDescendantOf(ch) then return end
        storeOnce(Variables.Snapshot.PartMaterial, part, {
            Material    = part.Material,
            Reflectance = part.Reflectance,
            CastShadow  = part.CastShadow,
        })
        pcall(function()
            part.Material    = Enum.Material.SmoothPlastic
            part.Reflectance = 0
            part.CastShadow  = false
        end)
    end

    local function restorePartMaterials()
        local n = 0
        for p,props in pairs(Variables.Snapshot.PartMaterial) do
            pcall(function()
                if p and p.Parent then
                    p.Material    = props.Material
                    p.Reflectance = props.Reflectance
                    p.CastShadow  = props.CastShadow
                end
            end)
            Variables.Snapshot.PartMaterial[p] = nil
            n += 1
            if (n % 500) == 0 then task.wait() end
        end
    end

    local function nukeTexturesIrreversible(inst)
        if inst:IsA("Decal") or inst:IsA("Texture") or inst:IsA("SurfaceAppearance") then
            pcall(function() inst:Destroy() end)
        elseif inst:IsA("MeshPart") or inst:IsA("BasePart") then
            pcall(function() inst.Material = Enum.Material.SmoothPlastic end)
        end
    end

    ------------------------------------------------------------------------
    -- Freeze world / constraints / net
    ------------------------------------------------------------------------
    local function freezePart(part)
        if not part:IsA("BasePart") then return end
        local lp = RbxService.Players.LocalPlayer
        local ch = lp and lp.Character
        if ch and part:IsDescendantOf(ch) then return end
        if part:GetAttribute("WFYB_FrozenByOptimization") then return end
        storeOnce(Variables.Snapshot.PartAnchored, part, part.Anchored)
        pcall(function()
            part.AssemblyLinearVelocity  = Vector3.new()
            part.AssemblyAngularVelocity = Vector3.new()
            part.Anchored = true
            part:SetAttribute("WFYB_FrozenByOptimization", true)
        end)
    end

    local function restoreFrozenParts()
        local i = 0
        for part,was in pairs(Variables.Snapshot.PartAnchored) do
            pcall(function()
                if part and part.Parent then
                    part.Anchored = was and true or false
                    part:SetAttribute("WFYB_FrozenByOptimization", nil)
                end
            end)
            Variables.Snapshot.PartAnchored[part] = nil
            i += 1
            if (i % 500) == 0 then task.wait() end
        end
        -- Safety sweep for any leftover tags we set
        eachDescendantChunked(RbxService.Workspace, function(x)
            return x:IsA("BasePart") and x:GetAttribute("WFYB_FrozenByOptimization") == true
        end, function(p)
            pcall(function()
                p:SetAttribute("WFYB_FrozenByOptimization", nil)
                if Variables.Snapshot.PartAnchored[p] == nil then p.Anchored = false end
            end)
        end)
    end

    local function disableConstraints()
        eachDescendantChunked(RbxService.Workspace, function(x)
            return x:IsA("Constraint") and not x:IsA("Motor6D")
        end, function(c)
            storeOnce(Variables.Snapshot.ConstraintEnabled, c, c.Enabled)
            pcall(function() c.Enabled = false end)
        end)
    end

    local function restoreConstraints()
        local n = 0
        for c,en in pairs(Variables.Snapshot.ConstraintEnabled) do
            pcall(function() if c and c.Parent then c.Enabled = en and true or false end end)
            Variables.Snapshot.ConstraintEnabled[c] = nil
            n += 1
            if (n % 500) == 0 then task.wait() end
        end
    end

    local function anchorCharacter(on)
        local lp = RbxService.Players.LocalPlayer
        local ch = lp and lp.Character
        if not ch then return end
        for _,d in ipairs(ch:GetDescendants()) do
            if d:IsA("BasePart") then
                storeOnce(Variables.Snapshot.CharAnchored, d, d.Anchored)
                pcall(function() d.Anchored = on and true or false end)
            end
        end
    end

    local function reduceSimRadius()
        if not Variables.Config.ReduceSimulationRadius then return end
        local lp = RbxService.Players.LocalPlayer
        if not lp then return end
        local sethp = sethiddenproperty or set_hidden_property or set_hidden_prop
        if sethp then pcall(function()
            sethp(lp, "SimulationRadius", 0)
            sethp(lp, "MaxSimulationRadius", 0)
        end) end
    end

    local function clearNetOwner()
        if not Variables.Config.RemoveLocalNetworkOwnership then return end
        eachDescendantChunked(RbxService.Workspace, function(x) return x:IsA("BasePart") end, function(p)
            pcall(function() if not p.Anchored then p:SetNetworkOwner(nil) end end)
        end)
    end

    ------------------------------------------------------------------------
    -- Lighting / PostFX / Grass
    ------------------------------------------------------------------------
    local function snapshotLighting()
        local L = RbxService.Lighting
        Variables.Snapshot.LightingProps = {
            GlobalShadows = L.GlobalShadows,
            Brightness    = L.Brightness,
            ClockTime     = L.ClockTime,
            Ambient       = L.Ambient,
            OutdoorAmbient= L.OutdoorAmbient,
            EnvironmentDiffuseScale  = L.EnvironmentDiffuseScale,
            EnvironmentSpecularScale = L.EnvironmentSpecularScale,
        }
    end

    local function applyLowLighting()
        local L = RbxService.Lighting
        pcall(function()
            L.GlobalShadows = false
            L.Brightness    = Variables.Config.FullBright and 2 or 1
            L.EnvironmentDiffuseScale  = 0
            L.EnvironmentSpecularScale = 0
            if Variables.Config.GraySky then
                L.ClockTime      = 12
                L.Ambient        = Color3.fromRGB(128,128,128)
                L.OutdoorAmbient = Color3.fromRGB(128,128,128)
            end
        end)
    end

    local function scheduleApplyLowLighting()
        if Variables.Runtime.LightDebounce then return end
        Variables.Runtime.LightDebounce = true
        task.defer(function()
            if Variables.Config.Enabled and (Variables.Config.GraySky or Variables.Config.FullBright) then
                applyLowLighting()
            end
            Variables.Runtime.LightDebounce = false
        end)
    end

    local function disablePostFX()
        local L = RbxService.Lighting
        for _,e in ipairs(L:GetChildren()) do
            if e:IsA("BlurEffect") or e:IsA("SunRaysEffect") or e:IsA("ColorCorrectionEffect") or
               e:IsA("BloomEffect") or e:IsA("DepthOfFieldEffect") then
                storeOnce(Variables.Snapshot.PostEffects, e, e.Enabled)
                pcall(function() e.Enabled = false end)
            end
        end
    end

    local function restorePostFX()
        for e,en in pairs(Variables.Snapshot.PostEffects) do
            pcall(function() if e and e.Parent then e.Enabled = en and true or false end end)
            Variables.Snapshot.PostEffects[e] = nil
        end
    end

    local function terrainDecoration(disable)
        local t = RbxService.Workspace:FindFirstChildOfClass("Terrain")
        if t then
            if Variables.Snapshot.TerrainDecoration == nil then
                local ok, v = pcall(function() return t.Decoration end)
                if ok then Variables.Snapshot.TerrainDecoration = v end
            end
            pcall(function() if typeof(t.Decoration)=="boolean" then t.Decoration = not disable end end)
            if RbxService.MaterialService then
                pcall(function()
                    RbxService.MaterialService.FallbackMaterial = disable and Enum.Material.SmoothPlastic or Enum.Material.Plastic
                end)
            end
        end
    end

    local function applyMinQuality()
        if Variables.Snapshot.QualityLevel == nil then
            local ok, q = pcall(function() return settings().Rendering.QualityLevel end)
            if ok then Variables.Snapshot.QualityLevel = q end
        end
        pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
    end

    local function restoreQuality()
        if Variables.Snapshot.QualityLevel ~= nil then
            pcall(function() settings().Rendering.QualityLevel = Variables.Snapshot.QualityLevel end)
            Variables.Snapshot.QualityLevel = nil
        end
    end

    ------------------------------------------------------------------------
    -- Viewport / VideoFrames
    ------------------------------------------------------------------------
    local function scanViewportAndVideo()
        local function scan(root)
            if not root then return end
            eachDescendantChunked(root, function(i)
                return i:IsA("ViewportFrame") or i:IsA("VideoFrame")
            end, function(f)
                if f:IsA("ViewportFrame") and Variables.Config.DisableViewportFrames then
                    storeOnce(Variables.Snapshot.ViewportVisible, f, f.Visible)
                    pcall(function() f.Visible = false end)
                elseif f:IsA("VideoFrame") and Variables.Config.DisableVideoFrames then
                    storeOnce(Variables.Snapshot.VideoPlaying, f, f.Playing)
                    pcall(function() f.Playing = false end)
                end
            end)
        end
        local pg = RbxService.Players.LocalPlayer and RbxService.Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
        scan(pg); scan(RbxService.CoreGui)
    end

    local function restoreViewportAndVideo()
        for v,vis in pairs(Variables.Snapshot.ViewportVisible) do
            pcall(function() if v and v.Parent then v.Visible = vis and true or false end end)
            Variables.Snapshot.ViewportVisible[v] = nil
        end
        for v,play in pairs(Variables.Snapshot.VideoPlaying) do
            pcall(function() if v and v.Parent then v.Playing = play and true or false end end)
            Variables.Snapshot.VideoPlaying[v] = nil
        end
    end

    ------------------------------------------------------------------------
    -- GUI hide/show
    ------------------------------------------------------------------------
    local function hidePlayerGui()
        local pg = RbxService.Players.LocalPlayer and RbxService.Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if not pg then return end
        for _,g in ipairs(pg:GetChildren()) do
            if g:IsA("ScreenGui") then
                storeOnce(Variables.Snapshot.PlayerGuiEnabled, g, g.Enabled)
                pcall(function() g.Enabled = false end)
            end
        end
    end

    local function restorePlayerGui()
        for g,en in pairs(Variables.Snapshot.PlayerGuiEnabled) do
            pcall(function() if g and g.Parent then g.Enabled = en and true or false end end)
            Variables.Snapshot.PlayerGuiEnabled[g] = nil
        end
    end

    local function hideCoreGui(on)
        if Variables.Snapshot.CoreGuiState["__snap__"] == nil then
            for _,t in ipairs({
                Enum.CoreGuiType.Chat, Enum.CoreGuiType.Backpack, Enum.CoreGuiType.EmotesMenu,
                Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.Health,
            }) do
                Variables.Snapshot.CoreGuiState[t] = RbxService.StarterGui:GetCoreGuiEnabled(t)
            end
            Variables.Snapshot.CoreGuiState["__snap__"] = true
        end
        for t,_ in pairs(Variables.Snapshot.CoreGuiState) do
            if typeof(t) == "EnumItem" then
                pcall(function() RbxService.StarterGui:SetCoreGuiEnabled(t, not on) end)
            end
        end
    end

    local function restoreCoreGui()
        for t,en in pairs(Variables.Snapshot.CoreGuiState) do
            if typeof(t) == "EnumItem" then
                pcall(function() RbxService.StarterGui:SetCoreGuiEnabled(t, en and true or false) end)
            end
        end
        Variables.Snapshot.CoreGuiState = {}
    end

    ------------------------------------------------------------------------
    -- Water Replacement
    ------------------------------------------------------------------------
    local function applyWaterReplacement()
        local terrain = RbxService.Workspace:FindFirstChildOfClass("Terrain")
        if terrain then
            if Variables.Snapshot.WaterTransparency == nil then
                local ok, v = pcall(function() return terrain.WaterTransparency end)
                if ok then Variables.Snapshot.WaterTransparency = v end
            end
            pcall(function() terrain.WaterTransparency = 1 end)
        end

        if Variables.Runtime.WaterProxyPart then
            pcall(function() Variables.Runtime.WaterProxyPart:Destroy() end)
            Variables.Runtime.WaterProxyPart = nil
        end

        local p = Instance.new("Part")
        p.Name        = "WFYB_WaterProxy"
        p.Anchored    = true
        p.CanCollide  = false
        p.Material    = Enum.Material.SmoothPlastic
        p.Transparency= math.clamp(Variables.Config.WaterBlockTransparency, 0, 1)
        p.Color       = Variables.Config.WaterBlockColor
        p.Size        = Vector3.new(
            math.max(10, Variables.Config.WaterSizeX),
            math.max(0.1, Variables.Config.WaterThickness),
            math.max(10, Variables.Config.WaterSizeZ)
        )
        p.CFrame      = CFrame.new(0, Variables.Config.WaterY, 0)
        p.Parent      = RbxService.Workspace
        Variables.Runtime.WaterProxyPart = p
    end

    local function removeWaterReplacement()
        if Variables.Runtime.WaterProxyPart then
            pcall(function() Variables.Runtime.WaterProxyPart:Destroy() end)
            Variables.Runtime.WaterProxyPart = nil
        end
        local terrain = RbxService.Workspace:FindFirstChildOfClass("Terrain")
        if terrain and Variables.Snapshot.WaterTransparency ~= nil then
            pcall(function() terrain.WaterTransparency = Variables.Snapshot.WaterTransparency end)
            Variables.Snapshot.WaterTransparency = nil
        end
    end

    ------------------------------------------------------------------------
    -- Watchers
    ------------------------------------------------------------------------
    local function buildWatchers()
        Variables.Maids.Watchers:DoCleaning()

        -- Workspace stream: emitters, parts, constraints, animators, sounds
        Variables.Maids.Watchers:GiveTask(RbxService.Workspace.DescendantAdded:Connect(function(inst)
            if not Variables.Config.Enabled then return end

            if Variables.Config.DestroyEmitters and isEmitter(inst) then
                destroyEmitterIrreversible(inst)
            elseif Variables.Config.StopParticleSystems and isEmitter(inst) then
                stopEmitter(inst)
            end

            if Variables.Config.SmoothPlasticEverywhere and inst:IsA("BasePart") then smoothPlastic(inst) end
            if Variables.Config.HideDecals and (inst:IsA("Decal") or inst:IsA("Texture")) then hideDecal(inst) end
            if Variables.Config.FreezeWorldAssemblies and inst:IsA("BasePart") then freezePart(inst) end

            if Variables.Config.RemoveLocalNetworkOwnership and inst:IsA("BasePart") then
                pcall(function() if not inst.Anchored then inst:SetNetworkOwner(nil) end end)
            end

            if Variables.Config.MuteAllSounds and inst:IsA("Sound") then guardSound(inst) end
            if inst:IsA("Animator") then guardAnimator(inst) end
        end))

        -- GUI stream for frames/sounds/animators
        local function streamGui(root)
            if not root then return end
            Variables.Maids.Watchers:GiveTask(root.DescendantAdded:Connect(function(inst)
                if not Variables.Config.Enabled then return end
                if Variables.Config.DisableViewportFrames and inst:IsA("ViewportFrame") then
                    storeOnce(Variables.Snapshot.ViewportVisible, inst, inst.Visible)
                    pcall(function() inst.Visible = false end)
                elseif Variables.Config.DisableVideoFrames and inst:IsA("VideoFrame") then
                    storeOnce(Variables.Snapshot.VideoPlaying, inst, inst.Playing)
                    pcall(function() inst.Playing = false end)
                end
                if Variables.Config.MuteAllSounds and inst:IsA("Sound") then guardSound(inst) end
                if inst:IsA("Animator") then guardAnimator(inst) end
            end))
        end
        streamGui(RbxService.Players.LocalPlayer and RbxService.Players.LocalPlayer:FindFirstChildOfClass("PlayerGui"))
        streamGui(RbxService.CoreGui)

        -- Lighting guards (for games that keep forcing their sky/FX)
        Variables.Maids.Watchers:GiveTask(RbxService.Lighting.ChildAdded:Connect(function(child)
            if not Variables.Config.Enabled then return end
            if Variables.Config.DisablePostEffects and (child:IsA("BlurEffect") or child:IsA("SunRaysEffect")
                or child:IsA("ColorCorrectionEffect") or child:IsA("BloomEffect") or child:IsA("DepthOfFieldEffect")) then
                storeOnce(Variables.Snapshot.PostEffects, child, child.Enabled)
                pcall(function() child.Enabled = false end)
            end
            if Variables.Config.GraySky or Variables.Config.FullBright then scheduleApplyLowLighting() end
        end))
        Variables.Maids.Watchers:GiveTask(RbxService.Lighting.Changed:Connect(function()
            if not Variables.Config.Enabled then return end
            if Variables.Config.GraySky or Variables.Config.FullBright then scheduleApplyLowLighting() end
        end))
    end

    ------------------------------------------------------------------------
    -- Apply / Restore
    ------------------------------------------------------------------------
    local function applyAll()
        Variables.Config.Enabled = true
        snapshotLighting()

        if Variables.Config.DisableThreeDRendering then pcall(function() RbxService.RunService:Set3dRenderingEnabled(false) end) end
        if Variables.Config.TargetFPS and Variables.Config.TargetFPS > 0 then setFpsCap(Variables.Config.TargetFPS) end

        if Variables.Config.HidePlayerGui then hidePlayerGui() end
        if Variables.Config.HideCoreGui then hideCoreGui(true) end

        if Variables.Config.DisableViewportFrames or Variables.Config.DisableVideoFrames then scanViewportAndVideo() end
        if Variables.Config.MuteAllSounds then applyMuteAllSounds() end

        eachDescendantChunked(RbxService.Workspace, function(x) return x:IsA("Animator") end, guardAnimator)
        if Variables.Config.PauseCharacterAnimations then toggleCharacterAnimateScripts(false) end

        if Variables.Config.FreezeWorldAssemblies then
            eachDescendantChunked(RbxService.Workspace, function(x) return x:IsA("BasePart") end, freezePart)
        end
        if Variables.Config.DisableConstraints then disableConstraints() end

        if Variables.Config.AnchorCharacter then anchorCharacter(true) end
        reduceSimRadius(); clearNetOwner()

        if Variables.Config.StopParticleSystems then eachDescendantChunked(RbxService.Workspace, isEmitter, stopEmitter) end
        if Variables.Config.DestroyEmitters and not Variables.Irreversible.EmittersDestroyed then
            eachDescendantChunked(RbxService.Workspace, isEmitter, destroyEmitterIrreversible)
            Variables.Irreversible.EmittersDestroyed = true
        end
        if Variables.Config.SmoothPlasticEverywhere then eachDescendantChunked(RbxService.Workspace, function(x) return x:IsA("BasePart") end, smoothPlastic) end
        if Variables.Config.HideDecals then eachDescendantChunked(RbxService.Workspace, function(x) return x:IsA("Decal") or x:IsA("Texture") end, hideDecal) end
        if Variables.Config.NukeTextures and not Variables.Irreversible.TexturesNuked then
            eachDescendantChunked(RbxService.Workspace, function(x)
                return x:IsA("Decal") or x:IsA("Texture") or x:IsA("SurfaceAppearance") or x:IsA("MeshPart") or x:IsA("BasePart")
            end, nukeTexturesIrreversible)
            Variables.Irreversible.TexturesNuked = true
        end

        if Variables.Config.RemoveGrassDecoration then terrainDecoration(true) end
        if Variables.Config.DisablePostEffects then disablePostFX() end
        if Variables.Config.GraySky or Variables.Config.FullBright then scheduleApplyLowLighting() end
        if Variables.Config.UseMinimumQuality then applyMinQuality() end

        if Variables.Config.ReplaceWaterWithBlock then applyWaterReplacement() end

        buildWatchers()
    end

    local function restoreAll()
        Variables.Config.Enabled = false
        Variables.Maids.Watchers:DoCleaning()
        Variables.Maids.EmitGuards:DoCleaning()

        if Variables.Config.DisableThreeDRendering then pcall(function() RbxService.RunService:Set3dRenderingEnabled(true) end) end

        restoreViewportAndVideo()
        restoreSounds()

        releaseAnimatorGuards()
        toggleCharacterAnimateScripts(true)

        if Variables.Config.FreezeWorldAssemblies then restoreFrozenParts() end
        if Variables.Config.DisableConstraints then restoreConstraints() end
        if Variables.Config.AnchorCharacter then anchorCharacter(false) end

        restorePlayerGui()
        restoreCoreGui()

        restorePartMaterials()
        restoreDecals()

        restoreEmitters()

        pcall(function()
            local P = Variables.Snapshot.LightingProps
            if P then
                local L = RbxService.Lighting
                L.GlobalShadows = P.GlobalShadows
                L.Brightness    = P.Brightness
                L.ClockTime     = P.ClockTime
                L.Ambient       = P.Ambient
                L.OutdoorAmbient= P.OutdoorAmbient
                L.EnvironmentDiffuseScale  = P.EnvironmentDiffuseScale
                L.EnvironmentSpecularScale = P.EnvironmentSpecularScale
            end
            if Variables.Config.ForceClearBlurOnRestore then
                for _,c in ipairs(RbxService.Lighting:GetChildren()) do
                    if c:IsA("BlurEffect") then c.Enabled = false end
                end
            end
        end)
        restorePostFX()

        if Variables.Snapshot.TerrainDecoration ~= nil then
            local t = RbxService.Workspace:FindFirstChildOfClass("Terrain")
            pcall(function()
                if t and typeof(t.Decoration)=="boolean" then t.Decoration = Variables.Snapshot.TerrainDecoration end
            end)
            Variables.Snapshot.TerrainDecoration = nil
        end
        restoreQuality()

        removeWaterReplacement()

        -- clear small maps
        Variables.Snapshot.PlayerGuiEnabled = {}
        Variables.Snapshot.CoreGuiState     = {}
        Variables.Snapshot.ViewportVisible  = {}
        Variables.Snapshot.VideoPlaying     = {}
    end

    ------------------------------------------------------------------------
    -- UI (Obsidian)
    ------------------------------------------------------------------------
    local grp = UI.Tabs.Misc:AddRightGroupbox("Optimization", "power")

    grp:AddToggle("OptEnabled", {
        Text = "Enable Optimization", Default = false,
        Tooltip = "Master switch",
    }):OnChanged(function(on) if on then applyAll() else restoreAll() end end)

    grp:AddSlider("OptFPS", {
        Text = "Target FPS", Min = 1, Max = 120, Default = Variables.Config.TargetFPS, Suffix = "FPS",
    }):OnChanged(function(v)
        Variables.Config.TargetFPS = math.floor(v)
        if Variables.Config.Enabled then setFpsCap(Variables.Config.TargetFPS) end
    end)

    grp:AddDivider(); grp:AddLabel("Rendering / UI")
    grp:AddToggle("Opt3D", {Text="Disable 3D Rendering", Default=Variables.Config.DisableThreeDRendering})
        :OnChanged(function(s) Variables.Config.DisableThreeDRendering = s; if Variables.Config.Enabled then pcall(function() RbxService.RunService:Set3dRenderingEnabled(not s) end) end end)
    grp:AddToggle("OptHidePG", {Text="Hide PlayerGui", Default=Variables.Config.HidePlayerGui})
        :OnChanged(function(s) Variables.Config.HidePlayerGui = s; if Variables.Config.Enabled then if s then hidePlayerGui() else restorePlayerGui() end end end)
    grp:AddToggle("OptHideCG", {Text="Hide CoreGui", Default=Variables.Config.HideCoreGui})
        :OnChanged(function(s) Variables.Config.HideCoreGui = s; if Variables.Config.Enabled then hideCoreGui(s) end end)
    grp:AddToggle("OptNoViewport", {Text="Disable ViewportFrames", Default=Variables.Config.DisableViewportFrames})
        :OnChanged(function(s) Variables.Config.DisableViewportFrames = s; if Variables.Config.Enabled then if s then scanViewportAndVideo() else restoreViewportAndVideo() end buildWatchers() end end)
    grp:AddToggle("OptNoVideo", {Text="Disable VideoFrames", Default=Variables.Config.DisableVideoFrames})
        :OnChanged(function(s) Variables.Config.DisableVideoFrames = s; if Variables.Config.Enabled then if s then scanViewportAndVideo() else restoreViewportAndVideo() end buildWatchers() end end)
    grp:AddToggle("OptMute", {Text="Mute All Sounds", Default=Variables.Config.MuteAllSounds})
        :OnChanged(function(s) Variables.Config.MuteAllSounds = s; if Variables.Config.Enabled then if s then applyMuteAllSounds() else restoreSounds() end buildWatchers() end end)

    grp:AddDivider(); grp:AddLabel("Animation / Motion")
    grp:AddToggle("OptPauseChar", {Text="Pause Character Animations", Default=Variables.Config.PauseCharacterAnimations})
        :OnChanged(function(s) Variables.Config.PauseCharacterAnimations = s; if Variables.Config.Enabled then if s then toggleCharacterAnimateScripts(false) else toggleCharacterAnimateScripts(true) end releaseAnimatorGuards(); eachDescendantChunked(RbxService.Workspace, function(i) return i:IsA("Animator") end, guardAnimator); buildWatchers() end end)
    grp:AddToggle("OptPauseOther", {Text="Pause Other Animations (client‑driven)", Default=Variables.Config.PauseOtherAnimations})
        :OnChanged(function(s) Variables.Config.PauseOtherAnimations = s; if Variables.Config.Enabled then releaseAnimatorGuards(); eachDescendantChunked(RbxService.Workspace, function(i) return i:IsA("Animator") end, guardAnimator); buildWatchers() end end)
    grp:AddToggle("OptFreeze", {Text="Freeze World Assemblies (reversible)", Default=Variables.Config.FreezeWorldAssemblies})
        :OnChanged(function(s) Variables.Config.FreezeWorldAssemblies = s; if Variables.Config.Enabled then if s then eachDescendantChunked(RbxService.Workspace, function(i) return i:IsA("BasePart") end, freezePart) else restoreFrozenParts() end buildWatchers() end end)
    grp:AddToggle("OptNoConstraints", {Text="Disable Constraints (reversible)", Default=Variables.Config.DisableConstraints})
        :OnChanged(function(s) Variables.Config.DisableConstraints = s; if Variables.Config.Enabled then if s then disableConstraints() else restoreConstraints() end end end)

    grp:AddDivider(); grp:AddLabel("Physics / Network")
    grp:AddToggle("OptAnchorChar", {Text="Anchor Character", Default=Variables.Config.AnchorCharacter})
        :OnChanged(function(s) Variables.Config.AnchorCharacter = s; if Variables.Config.Enabled then anchorCharacter(s) end end)
    grp:AddToggle("OptSimRadius", {Text="Reduce Simulation Radius", Default=Variables.Config.ReduceSimulationRadius})
        :OnChanged(function(s) Variables.Config.ReduceSimulationRadius = s; if Variables.Config.Enabled and s then reduceSimRadius() end end)
    grp:AddToggle("OptNoNet", {Text="Remove Local Network Ownership", Default=Variables.Config.RemoveLocalNetworkOwnership})
        :OnChanged(function(s) Variables.Config.RemoveLocalNetworkOwnership = s; if Variables.Config.Enabled and s then clearNetOwner() end if Variables.Config.Enabled then buildWatchers() end end)

    grp:AddDivider(); grp:AddLabel("Particles / Effects / Materials")
    grp:AddToggle("OptStopParticles", {Text="Stop Particle Systems (reversible)", Default=Variables.Config.StopParticleSystems})
        :OnChanged(function(s) Variables.Config.StopParticleSystems = s; if Variables.Config.Enabled then if s then eachDescendantChunked(RbxService.Workspace, isEmitter, stopEmitter); buildWatchers() else restoreEmitters() end end end)
    grp:AddToggle("OptDestroyEmitters", {Text="Destroy Emitters (irreversible)", Default=Variables.Config.DestroyEmitters})
        :OnChanged(function(s) Variables.Config.DestroyEmitters = s; if Variables.Config.Enabled and s and not Variables.Irreversible.EmittersDestroyed then eachDescendantChunked(RbxService.Workspace, isEmitter, destroyEmitterIrreversible); Variables.Irreversible.EmittersDestroyed = true; buildWatchers() end end)
    grp:AddToggle("OptSmooth", {Text="Force SmoothPlastic (reversible)", Default=Variables.Config.SmoothPlasticEverywhere})
        :OnChanged(function(s) Variables.Config.SmoothPlasticEverywhere = s; if Variables.Config.Enabled then if s then eachDescendantChunked(RbxService.Workspace, function(i) return i:IsA("BasePart") end, smoothPlastic); buildWatchers() else restorePartMaterials() end end end)
    grp:AddToggle("OptHideDecals", {Text="Hide Decals/Textures (reversible)", Default=Variables.Config.HideDecals})
        :OnChanged(function(s) Variables.Config.HideDecals = s; if Variables.Config.Enabled then if s then eachDescendantChunked(RbxService.Workspace, function(i) return i:IsA("Decal") or i:IsA("Texture") end, hideDecal); buildWatchers() else restoreDecals() end end end)
    grp:AddToggle("OptNukeTextures", {Text="Nuke Textures (irreversible)", Default=Variables.Config.NukeTextures})
        :OnChanged(function(s) Variables.Config.NukeTextures = s; if Variables.Config.Enabled and s and not Variables.Irreversible.TexturesNuked then eachDescendantChunked(RbxService.Workspace, function(i) return i:IsA("Decal") or i:IsA("Texture") or i:IsA("SurfaceAppearance") or i:IsA("MeshPart") or i:IsA("BasePart") end, nukeTexturesIrreversible); Variables.Irreversible.TexturesNuked = true; buildWatchers() end end)

    grp:AddDivider(); grp:AddLabel("Lighting / Quality")
    grp:AddToggle("OptNoGrass", {Text="Remove Grass Decoration", Default=Variables.Config.RemoveGrassDecoration})
        :OnChanged(function(s) Variables.Config.RemoveGrassDecoration = s; if Variables.Config.Enabled then terrainDecoration(s) end end)
    grp:AddToggle("OptNoPost", {Text="Disable Post‑FX (Bloom/CC/DoF/SunRays/Blur)", Default=Variables.Config.DisablePostEffects})
        :OnChanged(function(s) Variables.Config.DisablePostEffects = s; if Variables.Config.Enabled then if s then disablePostFX() else restorePostFX() end buildWatchers() end end)
    grp:AddToggle("OptGray", {Text="Gray Sky", Default=Variables.Config.GraySky})
        :OnChanged(function(s) Variables.Config.GraySky = s; if Variables.Config.Enabled and s then scheduleApplyLowLighting() end if Variables.Config.Enabled then buildWatchers() end end)
    grp:AddToggle("OptFullBright", {Text="Full Bright", Default=Variables.Config.FullBright})
        :OnChanged(function(s) Variables.Config.FullBright = s; if Variables.Config.Enabled and s then scheduleApplyLowLighting() end if Variables.Config.Enabled then buildWatchers() end end)
    grp:AddToggle("OptMinQ", {Text="Use Minimum Quality", Default=Variables.Config.UseMinimumQuality})
        :OnChanged(function(s) Variables.Config.UseMinimumQuality = s; if Variables.Config.Enabled then if s then applyMinQuality() else restoreQuality() end end end)
    grp:AddToggle("OptClearBlur", {Text="Force Clear Blur on Restore", Default=Variables.Config.ForceClearBlurOnRestore})
        :OnChanged(function(s) Variables.Config.ForceClearBlurOnRestore = s end)

    grp:AddDivider(); grp:AddLabel("Water Replacement (visual)")
    grp:AddToggle("OptWater", {Text="Replace Water With Block", Default=Variables.Config.ReplaceWaterWithBlock})
        :OnChanged(function(s)
            Variables.Config.ReplaceWaterWithBlock = s
            if not Variables.Config.Enabled then return end
            if s then applyWaterReplacement() else removeWaterReplacement() end
        end)

    -- Prefer Obsidian ColorPicker; gracefully fallback to RGB sliders if picker isn't available
    if type(grp.AddColorPicker) == "function" then
        grp:AddColorPicker("OptWaterColor", {
            Text = "Water Block Color",
            Default = Variables.Config.WaterBlockColor,
        }):OnChanged(function(c)
            Variables.Config.WaterBlockColor = c
            if Variables.Runtime.WaterProxyPart then Variables.Runtime.WaterProxyPart.Color = c end
        end)
    else
        -- Fallback (rare): RGB sliders
        grp:AddSlider("OptWaterR", { Text="Water Color - R", Min=0, Max=255, Default=Variables.Config.WaterBlockColor.R*255 })
            :OnChanged(function(v) local c = Variables.Config.WaterBlockColor; Variables.Config.WaterBlockColor = Color3.fromRGB(math.floor(v), math.floor(c.G*255), math.floor(c.B*255)); if Variables.Runtime.WaterProxyPart then Variables.Runtime.WaterProxyPart.Color = Variables.Config.WaterBlockColor end end)
        grp:AddSlider("OptWaterG", { Text="Water Color - G", Min=0, Max=255, Default=Variables.Config.WaterBlockColor.G*255 })
            :OnChanged(function(v) local c = Variables.Config.WaterBlockColor; Variables.Config.WaterBlockColor = Color3.fromRGB(math.floor(c.R*255), math.floor(v), math.floor(c.B*255)); if Variables.Runtime.WaterProxyPart then Variables.Runtime.WaterProxyPart.Color = Variables.Config.WaterBlockColor end end)
        grp:AddSlider("OptWaterB", { Text="Water Color - B", Min=0, Max=255, Default=Variables.Config.WaterBlockColor.B*255 })
            :OnChanged(function(v) local c = Variables.Config.WaterBlockColor; Variables.Config.WaterBlockColor = Color3.fromRGB(math.floor(c.R*255), math.floor(c.G*255), math.floor(v)); if Variables.Runtime.WaterProxyPart then Variables.Runtime.WaterProxyPart.Color = Variables.Config.WaterBlockColor end end)
    end

    grp:AddSlider("OptWaterTrans", { Text="Water Block Transparency", Min=0, Max=100, Default=Variables.Config.WaterBlockTransparency*100, Suffix="%" })
        :OnChanged(function(v)
            Variables.Config.WaterBlockTransparency = math.clamp(v/100, 0, 1)
            if Variables.Runtime.WaterProxyPart then Variables.Runtime.WaterProxyPart.Transparency = Variables.Config.WaterBlockTransparency end
        end)
    grp:AddSlider("OptWaterY", { Text="Water Block Y Level", Min=-1000, Max=1000, Default=Variables.Config.WaterY })
        :OnChanged(function(v) Variables.Config.WaterY = math.floor(v); if Variables.Runtime.WaterProxyPart then Variables.Runtime.WaterProxyPart.CFrame = CFrame.new(0, Variables.Config.WaterY, 0) end end)
    grp:AddSlider("OptWaterX", { Text="Water Block Size X", Min=1000, Max=40000, Default=Variables.Config.WaterSizeX })
        :OnChanged(function(v) Variables.Config.WaterSizeX = math.floor(v); if Variables.Runtime.WaterProxyPart then Variables.Runtime.WaterProxyPart.Size = Vector3.new(Variables.Config.WaterSizeX, Variables.Runtime.WaterProxyPart.Size.Y, Variables.Runtime.WaterProxyPart.Size.Z) end end)
    grp:AddSlider("OptWaterZ", { Text="Water Block Size Z", Min=1000, Max=40000, Default=Variables.Config.WaterSizeZ })
        :OnChanged(function(v) Variables.Config.WaterSizeZ = math.floor(v); if Variables.Runtime.WaterProxyPart then Variables.Runtime.WaterProxyPart.Size = Vector3.new(Variables.Runtime.WaterProxyPart.Size.X, Variables.Runtime.WaterProxyPart.Size.Y, Variables.Config.WaterSizeZ) end end)
    grp:AddSlider("OptWaterThick", { Text="Water Block Thickness", Min=1, Max=50, Default=Variables.Config.WaterThickness })
        :OnChanged(function(v) Variables.Config.WaterThickness = math.floor(v); if Variables.Runtime.WaterProxyPart then Variables.Runtime.WaterProxyPart.Size = Vector3.new(Variables.Runtime.WaterProxyPart.Size.X, Variables.Config.WaterThickness, Variables.Runtime.WaterProxyPart.Size.Z) end end)

    ------------------------------------------------------------------------
    -- Module Stop (enforced clean restore)
    ------------------------------------------------------------------------
    local function Stop()
        if UI and UI.Toggles and UI.Toggles.OptEnabled then UI.Toggles.OptEnabled:SetValue(false) end
        restoreAll()
        Variables.Maids.Optimization:DoCleaning()
    end

    return { Name = "Optimization", Stop = Stop }
end
end
