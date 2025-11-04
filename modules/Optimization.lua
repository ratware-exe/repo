-- modules/Optimization.lua
do return function(UI)

----------------------------------------------------------------------
-- Bootstrap (Services / Maid / Signal)
----------------------------------------------------------------------
local GlobalEnv = (getgenv and getgenv()) or _G

GlobalEnv.Signal = GlobalEnv.Signal or loadstring(
    game:HttpGet(GlobalEnv.RepoBase .. "dependency/Signal.lua"),
    "@Signal.lua"
)()

local Maid = loadstring(
    game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"),
    "@Maid.lua"
)()

local RbxService = loadstring(
    game:HttpGet(GlobalEnv.RepoBase .. "dependency/Services.lua"),
    "@Services.lua"
)()

-- Obsidian registries (preferred wiring point for :OnChanged)
local Toggles = (UI and UI.Toggles) or GlobalEnv.Toggles or _G.Toggles or {}
local Options = (UI and UI.Options) or GlobalEnv.Options or _G.Options or {}

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local Variables = {
    Maids = {
        Optimization  = Maid.new(),
        Watchers      = Maid.new(), -- workspace/gui/lighting watchers while enabled
        EmitterGuards = Maid.new(), -- reversible particle suppression
        WaterWatch    = Maid.new(), -- tracks the live water source (part mode)
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
        PauseOtherAnimations     = true,  -- client-driven only (NPC/UI/props)
        FreezeWorldAssemblies    = false,
        DisableConstraints       = true,  -- excludes Motor6D

        -- Physics / Network
        AnchorCharacter         = true,
        ReduceSimulationRadius  = true,
        RemoveLocalNetworkOwnership = true,

        -- Materials / Effects
        StopParticleSystems     = true,   -- reversible
        DestroyEmitters         = false,  -- irreversible
        SmoothPlasticEverywhere = true,   -- reversible
        HideDecals              = true,   -- reversible
        NukeTextures            = false,  -- irreversible

        RemoveGrassDecoration   = true,
        DisablePostEffects      = true,   -- Bloom/CC/DoF/SunRays/Blur

        GraySky                 = true,
        -- GraySkyShade (REMOVED)
        FullBright              = true,
        FullBrightLevel         = 2,      -- 0..5
        
        RemoveFog               = false, 
        RemoveSkybox            = false, 

        UseMinimumQuality       = true,
        ForceClearBlurOnRestore = true,

        -- Water replacement (auto‑mimic)
        ReplaceWaterWithBlock   = false,
        WaterTransparency       = 0.25,   -- 0..1
    },

    Snapshot = {
        PlayerGuiEnabled   = {},  -- ScreenGui -> bool
        CoreGuiState       = {},  -- CoreGuiType -> bool
        ViewportVisible    = {},  -- ViewportFrame -> bool
        VideoPlaying       = {},  -- VideoFrame -> bool
        SoundProps         = {},  -- Sound -> {Volume, Playing}

        AnimatorGuards     = {},  -- Animator -> {tracks={track->oldSpeed}, conns={...}}
        ConstraintEnabled  = {},  -- Constraint -> bool
        PartAnchored       = {},  -- BasePart -> bool
        CharacterAnchored  = {},  -- BasePart -> bool
        PartMaterial       = {},  -- BasePart -> {Material, Reflectance, CastShadow}
        DecalTransparency  = {},  -- Decal/Texture -> number

        EmitterProps       = {},  -- [reversible stop] per type snapshot (see stopEmitter)

        LightingProps      = { 
            FogStart = nil,
            FogEnd = nil,
            FogColor = nil,
            -- Snapshot full lighting state
            GlobalShadows = nil,
            Brightness = nil,
            ClockTime = nil,
            Ambient = nil,
            OutdoorAmbient = nil,
            EnvironmentDiffuseScale = nil,
            EnvironmentSpecularScale = nil
        },  -- saved lighting fields
        PostEffects        = {},  -- Effect -> Enabled
        TerrainDecoration  = nil, -- bool
        QualityLevel       = nil, -- Enum.QualityLevel

        Skyboxes           = {}, -- To store removed skyboxes

        TerrainWater = {          -- for Terrain mimic mode
            WaterTransparency= nil,
            WaveSize         = nil,
            WaveSpeed        = nil,
            Reflectance      = nil,
        },
    },

    Irreversible = {
        EmittersDestroyed = false,
        TexturesNuked     = false,
    },

    Runtime = {
        LightingApplyScheduled = false,
        WaterProxyPart = nil,
        WaterMode      = "None",  -- "Part" | "Terrain" | "None"
        WaterSource    = nil,     -- source BasePart (part mode)

        -- NEW: anti-race
        inTransition     = false, -- a master apply/restore is running
        desiredEnabled   = false, -- last requested state
        cancelRequested  = false, -- request current pass to stop early
        transitionId     = 0,     -- increases for every master transition
    },
}

----------------------------------------------------------------------
-- Anti‑race helpers
----------------------------------------------------------------------
local function shouldCancel()
    return Variables.Runtime.cancelRequested
end

-- Each long traversal checks both "Enabled" and a guard token; if a new
-- request arrives, we stop the traversal ASAP.
local function eachDescendantChunked(root, predicateFn, actionFn)
    local descendants = root:GetDescendants()
    for i = 1, #descendants do
        local inst = descendants[i]
        if shouldCancel() then break end
        if predicateFn(inst) then actionFn(inst) end
        if (i % 400) == 0 then
            if shouldCancel() then break end
            task.wait()
        end
    end
end

----------------------------------------------------------------------
-- Utilities
----------------------------------------------------------------------
local function storeOnce(mapTable, key, value)
    if mapTable[key] == nil then
        mapTable[key] = value
    end
end

local function setFpsCap(targetFps)
    local candidates = {
        (getgenv and getgenv().setfpscap),
        rawget(_G, "setfpscap"),
        rawget(_G, "set_fps_cap"),
        rawget(_G, "setfps"),
        rawget(_G, "setfps_max"),
    }
    for _, fn in ipairs(candidates) do
        if typeof(fn) == "function" then
            if pcall(fn, targetFps) then return true end
        end
    end
    return false
end

----------------------------------------------------------------------
-- Sounds
----------------------------------------------------------------------
local function guardSound(snd)
    if not snd or not snd:IsA("Sound") then return end
    storeOnce(Variables.Snapshot.SoundProps, snd, {
        Volume  = (function() local ok,v=pcall(function() return snd.Volume end)  return ok and v or 1 end)(),
        Playing = (function() local ok,v=pcall(function() return snd.Playing end) return ok and v or false end)(),
    })
    pcall(function() snd.Playing = false; snd.Volume = 0 end)

    local c1 = snd:GetPropertyChangedSignal("Volume"):Connect(function()
        -- transition guard: don't enforce during/after cancel
        if Variables.Config.Enabled and not Variables.Runtime.cancelRequested and Variables.Config.MuteAllSounds then
            pcall(function() snd.Volume = 0 end)
        end
    end)
    local c2 = snd:GetPropertyChangedSignal("Playing"):Connect(function()
        if Variables.Config.Enabled and not Variables.Runtime.cancelRequested and Variables.Config.MuteAllSounds and snd.Playing then
            pcall(function() snd.Playing = false end)
        end
    end)
    Variables.Maids.Watchers:GiveTask(c1)
    Variables.Maids.Watchers:GiveTask(c2)
end

local function applyMuteAllSounds()
    eachDescendantChunked(game, function(inst) return inst:IsA("Sound") end, guardSound)
end

local function restoreSounds()
    for snd, props in pairs(Variables.Snapshot.SoundProps) do
        if shouldCancel() then break end
        pcall(function()
            if snd and snd.Parent then
                snd.Volume  = props.Volume
                snd.Playing = props.Playing
            end
        end)
        Variables.Snapshot.SoundProps[snd] = nil
    end
end

----------------------------------------------------------------------
-- Animations (character + client-driven others)
----------------------------------------------------------------------
local function shouldPauseAnimator(anim)
    local lp = RbxService.Players.LocalPlayer
    local char = lp and lp.Character
    local isChar = char and anim:IsDescendantOf(char)
    if isChar then return Variables.Config.PauseCharacterAnimations
    else          return Variables.Config.PauseOtherAnimations end
end

local function guardAnimator(anim)
    if not anim or not anim:IsA("Animator") then return end
    if not shouldPauseAnimator(anim) then return end
    if Variables.Snapshot.AnimatorGuards[anim] then return end

    local bundle = { tracks = {}, conns = {} }
    Variables.Snapshot.AnimatorGuards[anim] = bundle

    local function getTrackSpeed(track)
        local ok, s = pcall(function() return track.Speed end)
        return (ok and typeof(s) == "number") and s or 1
    end

    local function freeze(track)
        if not track then return end
        if bundle.tracks[track] == nil then
            bundle.tracks[track] = getTrackSpeed(track)
        end
        pcall(function() track:AdjustSpeed(0) end)
        table.insert(bundle.conns, track.Stopped:Connect(function()
            bundle.tracks[track] = nil
        end))
    end

    local ok, list = pcall(function() return anim:GetPlayingAnimationTracks() end)
    if ok and list then
        for i=1,#list do freeze(list[i]) end
    end

    table.insert(bundle.conns, anim.AnimationPlayed:Connect(function(newTrack)
        if Variables.Config.Enabled and not Variables.Runtime.cancelRequested and shouldPauseAnimator(anim) then freeze(newTrack) end
    end))

    table.insert(bundle.conns, anim.AncestryChanged:Connect(function(_, parentNow)
        if parentNow == nil then
            for i=1,#bundle.conns do local c=bundle.conns[i]; if c then c:Disconnect() end end
            Variables.Snapshot.AnimatorGuards[anim] = nil
        end
    end))
end

local function releaseAnimatorGuards()
    for anim, bundle in pairs(Variables.Snapshot.AnimatorGuards) do
        if bundle and bundle.tracks then
            for track, old in pairs(bundle.tracks) do
                pcall(function() track:AdjustSpeed(old or 1) end)
            end
        end
        if bundle and bundle.conns then
            for i=1,#bundle.conns do local c=bundle.conns[i]; if c then c:Disconnect() end end
        end
        Variables.Snapshot.AnimatorGuards[anim] = nil
    end
end

local function toggleCharacterAnimateScripts(restoreBack)
    local lp = RbxService.Players.LocalPlayer
    local char = lp and lp.Character
    if not char then return end

    for _, child in ipairs(char:GetChildren()) do
        if child:IsA("LocalScript") and child.Name == "Animate" then
            if restoreBack then
                local prev = Variables.Snapshot.AnimatePrev and Variables.Snapshot.AnimatePrev[child]
                if prev ~= nil then pcall(function() child.Enabled = prev end) end
            else
                Variables.Snapshot.AnimatePrev = Variables.Snapshot.AnimatePrev or {}
                Variables.Snapshot.AnimatePrev[child] = child.Enabled
                pcall(function() child.Enabled = false end)
            end
        end
    end
end

----------------------------------------------------------------------
-- Particles / decals / materials
----------------------------------------------------------------------
local function isEmitter(inst)
    return inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam")
        or inst:IsA("Fire") or inst:IsA("Smoke")
        or inst:IsA("Sparkles")
end

-- Reversible STOP
local function stopEmitter(inst)
    if inst:IsA("ParticleEmitter") then
        storeOnce(Variables.Snapshot.EmitterProps, inst, {
            Class   = "ParticleEmitter",
            Enabled = inst.Enabled,
            Rate    = inst.Rate,
        })
        pcall(function() inst.Enabled = false; inst.Rate = 0 end)
        local a = inst:GetPropertyChangedSignal("Enabled"):Connect(function()
            if Variables.Config.Enabled and not Variables.Runtime.cancelRequested and Variables.Config.StopParticleSystems then
                pcall(function() inst.Enabled = false end)
            end
        end)
        local b = inst:GetPropertyChangedSignal("Rate"):Connect(function()
            if Variables.Config.Enabled and not Variables.Runtime.cancelRequested and Variables.Config.StopParticleSystems then
                pcall(function() inst.Rate = 0 end)
            end
        end)
        local c = inst.AncestryChanged:Connect(function(_, parentNow)
            if parentNow == nil then Variables.Snapshot.EmitterProps[inst] = nil end
        end)
        Variables.Maids.EmitterGuards:GiveTask(a)
        Variables.Maids.EmitterGuards:GiveTask(b)
        Variables.Maids.EmitterGuards:GiveTask(c)

    elseif inst:IsA("Fire") then
        storeOnce(Variables.Snapshot.EmitterProps, inst, {
            Class   = "Fire",
            Enabled = inst.Enabled,
            Heat    = inst.Heat,
            Size    = inst.Size,
        })
        pcall(function() inst.Enabled = false; inst.Heat = 0; inst.Size = 0 end)
        local c1 = inst:GetPropertyChangedSignal("Enabled"):Connect(function()
            if Variables.Config.Enabled and not Variables.Runtime.cancelRequested and Variables.Config.StopParticleSystems then
                pcall(function() inst.Enabled = false end)
            end
        end)
        Variables.Maids.EmitterGuards:GiveTask(c1)

    elseif inst:IsA("Smoke") then
        storeOnce(Variables.Snapshot.EmitterProps, inst, {
            Class   = "Smoke",
            Enabled = inst.Enabled,
            Opacity = inst.Opacity,
            Size    = inst.Size,
        })
        pcall(function() inst.Enabled = false; inst.Opacity = 0; inst.Size = 0 end)
        local c2 = inst:GetPropertyChangedSignal("Enabled"):Connect(function()
            if Variables.Config.Enabled and not Variables.Runtime.cancelRequested and Variables.Config.StopParticleSystems then
                pcall(function() inst.Enabled = false end)
            end
        end)
        Variables.Maids.EmitterGuards:GiveTask(c2)

    elseif inst:IsA("Trail") then
        storeOnce(Variables.Snapshot.EmitterProps, inst, {
            Class   = "Trail",
            Enabled = inst.Enabled,
        })
        pcall(function() inst.Enabled = false end)
        local c3 = inst:GetPropertyChangedSignal("Enabled"):Connect(function()
            if Variables.Config.Enabled and not Variables.Runtime.cancelRequested and Variables.Config.StopParticleSystems then
                pcall(function() inst.Enabled = false end)
            end
        end)
        Variables.Maids.EmitterGuards:GiveTask(c3)

    elseif inst:IsA("Beam") then
        storeOnce(Variables.Snapshot.EmitterProps, inst, {
            Class        = "Beam",
            Enabled      = inst.Enabled,
            Transparency = inst.Transparency,
        })
        pcall(function() inst.Enabled = false end)
        local c4 = inst:GetPropertyChangedSignal("Enabled"):Connect(function()
            if Variables.Config.Enabled and not Variables.Runtime.cancelRequested and Variables.Config.StopParticleSystems then
                pcall(function() inst.Enabled = false end)
            end
        end)
        Variables.Maids.EmitterGuards:GiveTask(c4)
    
    elseif inst:IsA("Sparkles") then
        storeOnce(Variables.Snapshot.EmitterProps, inst, {
            Class   = "Sparkles",
            Enabled = inst.Enabled,
        })
        pcall(function() inst.Enabled = false end)
        local c5 = inst:GetPropertyChangedSignal("Enabled"):Connect(function()
            if Variables.Config.Enabled and not Variables.Runtime.cancelRequested and Variables.Config.StopParticleSystems then
                pcall(function() inst.Enabled = false end)
            end
        end)
        Variables.Maids.EmitterGuards:GiveTask(c5)
    end
end

local function restoreEmitters()
    Variables.Maids.EmitterGuards:DoCleaning()
    for emitter, props in pairs(Variables.Snapshot.EmitterProps) do
        if shouldCancel() then break end
        pcall(function()
            if emitter and emitter.Parent then
                if props.Class == "ParticleEmitter" then
                    emitter.Rate    = props.Rate
                    emitter.Enabled = props.Enabled
                elseif props.Class == "Fire" then
                    emitter.Heat    = props.Heat
                    emitter.Size    = props.Size
                    emitter.Enabled = props.Enabled
                elseif props.Class == "Smoke" then
                    emitter.Opacity = props.Opacity
                    emitter.Size    = props.Size
                    emitter.Enabled = props.Enabled
                elseif props.Class == "Trail" then
                    emitter.Enabled = props.Enabled
                elseif props.Class == "Beam" then
                    emitter.Transparency = props.Transparency
                    emitter.Enabled      = props.Enabled
                elseif props.Class == "Sparkles" then
                    emitter.Enabled = props.Enabled
                end
            end
        end)
        Variables.Snapshot.EmitterProps[emitter] = nil
    end
end

local function destroyEmitterIrreversible(inst)
    if isEmitter(inst) then pcall(function() inst:Destroy() end) end
end

local function hideDecalOrTexture(inst)
    if inst:IsA("Decal") or inst:IsA("Texture") then
        storeOnce(Variables.Snapshot.DecalTransparency, inst,
            (function() local ok,v=pcall(function() return inst.Transparency end) return ok and v or 0 end)()
        )
        pcall(function() inst.Transparency = 1 end)
    end
end

local function restoreDecalsAndTextures()
    for inst, old in pairs(Variables.Snapshot.DecalTransparency) do
        if shouldCancel() then break end
        pcall(function()
            if inst and inst.Parent then inst.Transparency = old end
        end)
        Variables.Snapshot.DecalTransparency[inst] = nil
    end
end

local function smoothPlasticPart(inst)
    if not inst:IsA("BasePart") then return end
    local char = RbxService.Players.LocalPlayer and RbxService.Players.LocalPlayer.Character
    if char and inst:IsDescendantOf(char) then return end
    storeOnce(Variables.Snapshot.PartMaterial, inst, {
        Material    = inst.Material,
        Reflectance = inst.Reflectance,
        CastShadow  = inst.CastShadow,
    })
    pcall(function()
        inst.Material    = Enum.Material.SmoothPlastic
        inst.Reflectance = 0
        inst.CastShadow  = false
    end)
end

local function restorePartMaterials()
    local counter = 0
    for part, props in pairs(Variables.Snapshot.PartMaterial) do
        if shouldCancel() then break end
        pcall(function()
            if part and part.Parent then
                part.Material    = props.Material
                part.Reflectance = props.Reflectance
                part.CastShadow  = props.CastShadow
            end
        end)
        Variables.Snapshot.PartMaterial[part] = nil
        counter += 1
        if (counter % 500) == 0 then
            if shouldCancel() then break end
            task.wait()
        end
    end
end

-- Irreversible “Nuke”
local function nukeTexturesIrreversible(inst)
    if inst:IsA("Decal") or inst:IsA("Texture") then
        pcall(function() inst.Texture = "" end)
        pcall(function() inst:Destroy() end)

    elseif inst:IsA("SurfaceAppearance") then
        pcall(function() inst:Destroy() end)

    elseif inst:IsA("MeshPart") then
        pcall(function() inst.TextureID = "" end)
        pcall(function() inst.Material  = Enum.Material.SmoothPlastic end)

    elseif inst:IsA("SpecialMesh") then
        pcall(function() inst.TextureId = "" end)

    elseif inst:IsA("Shirt") then
        pcall(function() inst.ShirtTemplate = "" end)

    elseif inst:IsA("Pants") then
        pcall(function() inst.PantsTemplate = "" end)

    elseif inst:IsA("ShirtGraphic") then
        pcall(function() inst.Graphic = "" end)

    elseif inst:IsA("BasePart") then -- Catches regular Parts, etc.
        pcall(function() inst.Material = Enum.Material.SmoothPlastic end)

    -- Also strip UI carriers so users can see it actually "does something"
    elseif inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
        pcall(function() inst.Image = "" end)
    end
end

----------------------------------------------------------------------
-- Freeze world / constraints / net
----------------------------------------------------------------------
local function freezeWorldPart(inst)
    if not inst:IsA("BasePart") then return end
    local char = RbxService.Players.LocalPlayer and RbxService.Players.LocalPlayer.Character
    if char and inst:IsDescendantOf(char) then return end
    if inst:GetAttribute("WFYB_FrozenByOptimization") then return end

    storeOnce(Variables.Snapshot.PartAnchored, inst, inst.Anchored)
    pcall(function()
        inst.AssemblyLinearVelocity  = Vector3.new()
        inst.AssemblyAngularVelocity = Vector3.new()
        inst.Anchored = true
        inst:SetAttribute("WFYB_FrozenByOptimization", true)
    end)
end

local function restoreAnchoredParts()
    local counter = 0
    for part, wasAnchored in pairs(Variables.Snapshot.PartAnchored) do
        if shouldCancel() then break end
        pcall(function()
            if part and part.Parent then
                part.Anchored = wasAnchored and true or false
                part:SetAttribute("WFYB_FrozenByOptimization", nil)
            end
        end)
        Variables.Snapshot.PartAnchored[part] = nil
        counter += 1
        if (counter % 500) == 0 then
            if shouldCancel() then break end
            task.wait()
        end
    end

    -- Safety sweep
    if not shouldCancel() then
        eachDescendantChunked(RbxService.Workspace,
            function(x) return x:IsA("BasePart") and x:GetAttribute("WFYB_FrozenByOptimization") == true end,
            function(p)
                pcall(function()
                    p:SetAttribute("WFYB_FrozenByOptimization", nil)
                    if Variables.Snapshot.PartAnchored[p] == nil then p.Anchored = false end
                end)
            end
        )
    end
end

-- NEW:Constraint disabler, from V2.lua
local function disableConstraint(instance)
    if not Variables.Config.DisableConstraints then return false end
    local localPlayer = RbxService.Players.LocalPlayer
    if localPlayer and localPlayer.Character and instance:IsDescendantOf(localPlayer.Character) then return false end
    if instance:IsA("Motor6D") then return false end
    if instance:IsA("Constraint") or instance:IsA("HingeConstraint") or instance:IsA("RodConstraint")
       or instance:IsA("AlignPosition") or instance:IsA("AlignOrientation") then
        if instance.Enabled ~= nil then
            storeOnce(Variables.Snapshot.ConstraintEnabled, instance, instance.Enabled)
            pcall(function() instance.Enabled = false end)
        end
        return true
    end
    return false
end

local function disableWorldConstraints()
    eachDescendantChunked(RbxService.Workspace,
        function(inst) return (inst:IsA("Constraint") or inst:IsA("AlignPosition") or inst:IsA("AlignOrientation")) end,
        disableConstraint
    )
end

local function restoreWorldConstraints()
    local counter = 0
    for c, old in pairs(Variables.Snapshot.ConstraintEnabled) do
        if shouldCancel() then break end
        pcall(function()
            if c and c.Parent then c.Enabled = old and true or false end
        end)
        Variables.Snapshot.ConstraintEnabled[c] = nil
        counter += 1
        if (counter % 500) == 0 then
            if shouldCancel() then break end
            task.wait()
        end
    end
end

local function anchorCharacter(anchorOn)
    local lp = RbxService.Players.LocalPlayer
    local char = lp and lp.Character
    if not char then return end

    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("BasePart") then
            storeOnce(Variables.Snapshot.CharacterAnchored, d, d.Anchored)
            pcall(function() d.Anchored = anchorOn and true or false end)
        end
    end
end

local function restoreCharacterAnchors() -- NEW: restore original char anchoring
    for part, was in pairs(Variables.Snapshot.CharacterAnchored) do
        if shouldCancel() then break end
        pcall(function() if part and part.Parent then part.Anchored = was and true or false end end)
        Variables.Snapshot.CharacterAnchored[part] = nil
    end
end

local function reduceSimulationRadius()
    if not Variables.Config.ReduceSimulationRadius then return end
    local lp = RbxService.Players.LocalPlayer
    if not lp then return end
    local sethp = sethiddenproperty or set_hidden_property or set_hidden_prop
    if sethp then
        pcall(function()
            sethp(lp, "SimulationRadius", 0)
            sethp(lp, "MaxSimulationRadius", 0)
        end)
    end
end

local function removeNetOwnership()
    if not Variables.Config.RemoveLocalNetworkOwnership then return end
    eachDescendantChunked(RbxService.Workspace,
        function(inst) return inst:IsA("BasePart") end,
        function(part)
            pcall(function() if not part.Anchored then part:SetNetworkOwner(nil) end end)
        end
    )
end

----------------------------------------------------------------------
-- Lighting / PostFX / Grass
----------------------------------------------------------------------
local function snapshotLighting()
    local L = RbxService.Lighting
    local P = Variables.Snapshot.LightingProps
    P.GlobalShadows           = L.GlobalShadows
    P.Brightness              = L.Brightness
    P.ClockTime               = L.ClockTime
    P.Ambient                 = L.Ambient
    P.OutdoorAmbient          = L.OutdoorAmbient
    P.EnvironmentDiffuseScale = L.EnvironmentDiffuseScale
    P.EnvironmentSpecularScale= L.EnvironmentSpecularScale
    P.FogStart                = L.FogStart
    P.FogEnd                  = L.FogEnd
    P.FogColor                = L.FogColor
end

--[[
    FIX (APPLIED):
    - GraySky: Sets ambient to 128 gray, DOES NOT touch brightness/time, removes sky/clouds/atmosphere, and forces fog to gray.
    - FullBright: Sets brightness from slider, and ambient to 192 gray.
]]
local function applyLowLighting()
    local L = RbxService.Lighting
    pcall(function()
        L.GlobalShadows = false
        L.EnvironmentDiffuseScale  = 0
        L.EnvironmentSpecularScale = 0

        if Variables.Config.GraySky then
            -- Gray Sky mode: Overrides FullBright's settings.
            -- Simple, solid gray.
            local color = Color3.fromRGB(128, 128, 128) -- Hardcoded gray
            
            -- FIX: Use snapshot brightness/time, not "1" or "12"
            local P = Variables.Snapshot.LightingProps
            if P then
                -- Don't touch brightness, use snapshot
                L.Brightness = P.Brightness
                L.ClockTime = P.ClockTime
            else
                -- Fallback if no snapshot (this should not happen, but safe)
                L.Brightness = 1 
                L.ClockTime = 12
            end
            
            L.Ambient = color
            L.OutdoorAmbient = color

            -- Remove skybox, clouds, AND atmosphere
            for _, child in ipairs(L:GetChildren()) do
                if child:IsA("Sky") or child:IsA("Clouds") or child:IsA("Atmosphere") then -- ADDED ATMOSPHERE
                    if not table.find(Variables.Snapshot.Skyboxes, child) then
                        table.insert(Variables.Snapshot.Skyboxes, child)
                    end
                    child.Parent = nil
                end
            end
            
            -- NEW: Force fog to solid gray, but far away
            L.FogColor = color
            L.FogStart = 0
            L.FogEnd = 999999 -- FIX: Was 0, now high value
        
        elseif Variables.Config.FullBright then
            -- Full Bright mode: High brightness + bright ambient.
            L.Brightness = math.clamp(Variables.Config.FullBrightLevel, 0, 5)
            -- Add the "non-blinding bright side effect"
            local brightAmbient = Color3.fromRGB(192, 192, 192)
            L.Ambient = brightAmbient
            L.OutdoorAmbient = brightAmbient
            -- We DON'T touch ClockTime or Skybox here, letting the original sky show.
        end
    end)
end

local function applyRemoveFog()
    pcall(function()
        RbxService.Lighting.FogStart = 999998
        RbxService.Lighting.FogEnd = 999999
    end)
end

local function scheduleApplyLighting()
    if Variables.Runtime.LightingApplyScheduled then return end
    Variables.Runtime.LightingApplyScheduled = true
    task.defer(function()
        -- Check master enabled flag first
        if Variables.Config.Enabled and not Variables.Runtime.cancelRequested then
            if (Variables.Config.GraySky or Variables.Config.FullBright) then
                applyLowLighting()
            else
                -- Restore Ambient/OutdoorAmbient/ClockTime/Brightness if both are off
                pcall(function()
                    local P = Variables.Snapshot.LightingProps
                    if P then
                        local L = RbxService.Lighting
                        L.Brightness = P.Brightness
                        L.Ambient = P.Ambient
                        L.OutdoorAmbient = P.OutdoorAmbient
                        L.ClockTime = P.ClockTime
                    end
                end)
            end
            
            -- Fog logic: Apply or Restore
            if Variables.Config.RemoveFog then
                applyRemoveFog()
            elseif not Variables.Config.GraySky then -- Don't restore if GraySky is on
                -- Restore fog if NoFog is off AND GraySky is off
                pcall(function()
                    local P = Variables.Snapshot.LightingProps
                    if P and P.FogStart ~= nil then
                        local L = RbxService.Lighting
                        L.FogStart = P.FogStart
                        L.FogEnd = P.FogEnd
                        L.FogColor = P.FogColor
                    end
                end)
            end
        end
        Variables.Runtime.LightingApplyScheduled = false
    end)
end

local function disablePostEffects()
    local L = RbxService.Lighting
    for _, effect in ipairs(L:GetChildren()) do
        if effect:IsA("BlurEffect") or effect:IsA("SunRaysEffect")
        or effect:IsA("ColorCorrectionEffect") or effect:IsA("BloomEffect")
        or effect:IsA("DepthOfFieldEffect") then
            storeOnce(Variables.Snapshot.PostEffects, effect, effect.Enabled)
            pcall(function() effect.Enabled = false end)
        end
    end
end

local function restorePostEffects()
    for eff, wasEnabled in pairs(Variables.Snapshot.PostEffects) do
        pcall(function()
            if eff and eff.Parent then eff.Enabled = wasEnabled and true or false end
        end)
        Variables.Snapshot.PostEffects[eff] = nil
    end
end

local function terrainDecorationSet(disableOn)
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
            RbxService.MaterialService.FallbackMaterial =
                disableOn and Enum.Material.SmoothPlastic or Enum.Material.Plastic
        end)
    end
end

local function applyQualityMinimum()
    if Variables.Snapshot.QualityLevel == nil then
        local ok, level = pcall(function() return settings().Rendering.QualityLevel end)
        if ok then Variables.Snapshot.QualityLevel = level end
    end
    pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
end

local function restoreQuality()
    if Variables.Snapshot.QualityLevel ~= nil then
        pcall(function() settings().Rendering.QualityLevel = Variables.Snapshot.QualityLevel end)
        Variables.Snapshot.QualityLevel = nil
    end
end

----------------------------------------------------------------------
-- Viewport / VideoFrames and GUI hide/show
----------------------------------------------------------------------
-- NEW: Functions based on V2.lua
local function hideViewport(frame)
    if not frame or not frame:IsA("ViewportFrame") then return end
    storeOnce(Variables.Snapshot.ViewportVisible, frame, frame.Visible)
    pcall(function() frame.Visible = false end)
end

local function hideVideo(frame)
    if not frame or not frame:IsA("VideoFrame") then return end
    storeOnce(Variables.Snapshot.VideoPlaying, frame, frame.Playing)
    pcall(function() frame.Playing = false end)
end

local function scanViewportAndVideo()
    eachDescendantChunked(game, function(inst) return inst:IsA("ViewportFrame") end, hideViewport)
    eachDescendantChunked(game, function(inst) return inst:IsA("VideoFrame") end, hideVideo)
end

local function restoreViewportAndVideo()
    for frame, wasVisible in pairs(Variables.Snapshot.ViewportVisible) do
        if shouldCancel() then break end
        pcall(function() if frame and frame.Parent then frame.Visible = wasVisible and true or false end end)
        Variables.Snapshot.ViewportVisible[frame] = nil
    end
    for frame, wasPlaying in pairs(Variables.Snapshot.VideoPlaying) do
        if shouldCancel() then break end
        pcall(function() if frame and frame.Parent then frame.Playing = wasPlaying and true or false end end)
        Variables.Snapshot.VideoPlaying[frame] = nil
    end
end

local function hidePlayerGui(gui)
    if gui:IsA("ScreenGui") then
        storeOnce(Variables.Snapshot.PlayerGuiEnabled, gui, gui.Enabled)
        pcall(function() gui.Enabled = false end)
    end
end

local function hidePlayerGuiAll()
    local pg = RbxService.Players.LocalPlayer and RbxService.Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not pg then return end
    for _, gui in ipairs(pg:GetChildren()) do
        hidePlayerGui(gui)
    end
end

local function restorePlayerGuiAll()
    for gui, wasEnabled in pairs(Variables.Snapshot.PlayerGuiEnabled) do
        pcall(function() if gui and gui.Parent then gui.Enabled = wasEnabled and true or false end end)
        Variables.Snapshot.PlayerGuiEnabled[gui] = nil
    end
end

local function hideCoreGuiAll(hideOn)
    if Variables.Snapshot.CoreGuiState["__snap__"] == nil then
        for _, coreType in ipairs({
            Enum.CoreGuiType.Chat,
            Enum.CoreGuiType.Backpack,
            Enum.CoreGuiType.EmotesMenu,
            Enum.CoreGuiType.PlayerList,
            Enum.CoreGuiType.Health,
        }) do
            Variables.Snapshot.CoreGuiState[coreType] = RbxService.StarterGui:GetCoreGuiEnabled(coreType)
        end
        Variables.Snapshot.CoreGuiState["__snap__"] = true
    end

    for coreType, _ in pairs(Variables.Snapshot.CoreGuiState) do
        if typeof(coreType) == "EnumItem" then
            pcall(function() RbxService.StarterGui:SetCoreGuiEnabled(coreType, not hideOn) end)
        end
    end
end

local function restoreCoreGuiAll()
    for coreType, wasEnabled in pairs(Variables.Snapshot.CoreGuiState) do
        if typeof(coreType) == "EnumItem" then
            pcall(function() RbxService.StarterGui:SetCoreGuiEnabled(coreType, wasEnabled and true or false) end)
        end
    end
    Variables.Snapshot.CoreGuiState = {}
end

----------------------------------------------------------------------
-- Water Replacement (Auto‑mimic)
----------------------------------------------------------------------
local function findWaterSource()
    -- Try: largest BasePart with Material = Water
    local largestPart, largestVolume = nil, 0
    for _, inst in ipairs(RbxService.Workspace:GetDescendants()) do
        if inst:IsA("BasePart") and inst.Material == Enum.Material.Water then
            local vol = inst.Size.X * inst.Size.Y * inst.Size.Z
            if vol > largestVolume then largestVolume, largestPart = vol, inst end
        end
    end
    if largestPart then return "Part", largestPart end

    -- Fallback: Terrain water (mimic by setting Terrain properties)
    local terrain = RbxService.Workspace:FindFirstChildOfClass("Terrain")
    if terrain then return "Terrain", terrain end

    return "None", nil
end

local function applyWaterReplacement()
    Variables.Maids.WaterWatch:DoCleaning()
    Variables.Runtime.WaterMode, Variables.Runtime.WaterSource = findWaterSource()

    if Variables.Runtime.WaterMode == "Part" and Variables.Runtime.WaterSource then
        local source = Variables.Runtime.WaterSource

        if Variables.Runtime.WaterProxyPart and Variables.Runtime.WaterProxyPart.Parent then
            pcall(function() Variables.Runtime.WaterProxyPart:Destroy() end)
            Variables.Runtime.WaterProxyPart = nil
        end

        local proxy = Instance.new("Part")
        proxy.Name = "WFYB_WaterProxy"
        proxy.Anchored = true
        proxy.CanCollide = false
        proxy.Material = Enum.Material.SmoothPlastic
        proxy.Transparency = math.clamp(Variables.Config.WaterTransparency, 0, 1)
        proxy.Size = source.Size
        proxy.CFrame = source.CFrame
        proxy.Parent = RbxService.Workspace
        Variables.Runtime.WaterProxyPart = proxy

        -- Make the original visual invisible (but keep physics)
        storeOnce(Variables.Snapshot.PartMaterial, source, {
            Material    = source.Material,
            Reflectance = source.Reflectance,
            CastShadow  = source.CastShadow
        })
        pcall(function()
            source.Transparency = 1
            source.Reflectance = 0
        end)

        local function syncProxy()
            if proxy and proxy.Parent and source and source.Parent then
                proxy.Size = source.Size
                proxy.CFrame = source.CFrame
            end
        end
        syncProxy()

        local c1 = source:GetPropertyChangedSignal("CFrame"):Connect(syncProxy)
        local c2 = source:GetPropertyChangedSignal("Size"):Connect(syncProxy)
        local c3 = source.AncestryChanged:Connect(function(_, parentNow)
            if parentNow == nil then
                Variables.Maids.WaterWatch:DoCleaning()
                if proxy and proxy.Parent then pcall(function() proxy:Destroy() end) end
                Variables.Runtime.WaterProxyPart = nil
            end
        end)
        Variables.Maids.WaterWatch:GiveTask(c1)
        Variables.Maids.WaterWatch:GiveTask(c2)
        Variables.Maids.WaterWatch:GiveTask(c3)

    elseif Variables.Runtime.WaterMode == "Terrain" then
        local terrain = Variables.Runtime.WaterSource
        if terrain then
            if Variables.Snapshot.TerrainWater.WaterTransparency == nil then
                local okT, tr = pcall(function() return terrain.WaterTransparency end)
                if okT then Variables.Snapshot.TerrainWater.WaterTransparency = tr end
            end
            if Variables.Snapshot.TerrainWater.WaveSize == nil then
                local okS, sz = pcall(function() return terrain.WaterWaveSize end)
                if okS then Variables.Snapshot.TerrainWater.WaveSize = sz end
            end
            if Variables.Snapshot.TerrainWater.WaveSpeed == nil then
                local okW, sp = pcall(function() return terrain.WaterWaveSpeed end)
                if okW then Variables.Snapshot.TerrainWater.WaveSpeed = sp end
            end
            if Variables.Snapshot.TerrainWater.Reflectance == nil then
                local okR, rf = pcall(function() return terrain.WaterReflectance end)
                if okR then Variables.Snapshot.TerrainWater.Reflectance = rf end
            end

            pcall(function()
                terrain.WaterTransparency = math.clamp(Variables.Config.WaterTransparency, 0, 1)
                terrain.WaterWaveSize     = 0
                terrain.WaterWaveSpeed    = 0
                terrain.WaterReflectance  = 0
            end)
        end
    end
end

local function removeWaterReplacement()
    Variables.Maids.WaterWatch:DoCleaning()

    if Variables.Runtime.WaterProxyPart then
        pcall(function() Variables.Runtime.WaterProxyPart:Destroy() end)
        Variables.Runtime.WaterProxyPart = nil
    end

    if Variables.Runtime.WaterMode == "Part" and Variables.Runtime.WaterSource then
        local source = Variables.Runtime.WaterSource
        local saved = Variables.Snapshot.PartMaterial[source]
        pcall(function()
            if source and source.Parent then
                if saved then
                    source.Material    = saved.Material
                    source.Reflectance = saved.Reflectance
                    source.CastShadow  = saved.CastShadow
                    -- Use the saved reflectance, don't default to 0
                    source.Transparency = 0 
                else
                    -- Fallback if no snapshot
                    source.Transparency = 0
                    source.Reflectance = 0.5 -- A sensible default
                end
            end
        end)
        Variables.Snapshot.PartMaterial[source] = nil

    elseif Variables.Runtime.WaterMode == "Terrain" and Variables.Runtime.WaterSource then
        local terrain = Variables.Runtime.WaterSource
        local snap = Variables.Snapshot.TerrainWater
        pcall(function()
            if terrain then
                if snap.WaterTransparency then terrain.WaterTransparency = snap.WaterTransparency end
                if snap.WaveSize          then terrain.WaterWaveSize     = snap.WaveSize          end
                if snap.WaveSpeed         then terrain.WaterWaveSpeed    = snap.WaveSpeed         end
                if snap.Reflectance       then terrain.WaterReflectance  = snap.Reflectance       end
            end
        end)
        Variables.Snapshot.TerrainWater = {
            WaterTransparency=nil, WaveSize=nil, WaveSpeed=nil, Reflectance=nil
        }
    end

    Variables.Runtime.WaterMode   = "None"
    Variables.Runtime.WaterSource = nil
end

----------------------------------------------------------------------
-- Watchers (NEW: V2.lua / AFK script logic)
----------------------------------------------------------------------
-- This function is called by the watchers and by the initial ApplyBatch
local function ApplyToInstance(inst)
    if not inst then return end
    
    --[[
        FIX (APPLIED):
        Watcher now catches Sky, Clouds, AND Atmosphere.
    ]]
    -- Sky/Clouds (runs if GraySky OR RemoveSkybox is on)
    if (Variables.Config.GraySky or Variables.Config.RemoveSkybox) and (inst:IsA("Sky") or inst:IsA("Clouds") or inst:IsA("Atmosphere")) then
        if not table.find(Variables.Snapshot.Skyboxes, inst) then
            table.insert(Variables.Snapshot.Skyboxes, inst)
        end
        inst.Parent = nil
        return -- It's gone, no need to check other things
    end

    -- PostFX
    if Variables.Config.DisablePostEffects and (inst:IsA("BlurEffect") or inst:IsA("SunRaysEffect")
        or inst:IsA("ColorCorrectionEffect") or inst:IsA("BloomEffect")
        or inst:IsA("DepthOfFieldEffect")) then
        storeOnce(Variables.Snapshot.PostEffects, inst, inst.Enabled)
        pcall(function() inst.Enabled = false end)
    end
    
    -- Emitters
    if Variables.Config.DestroyEmitters and isEmitter(inst) then
        destroyEmitterIrreversible(inst)
        return
    elseif Variables.Config.StopParticleSystems and isEmitter(inst) then
        stopEmitter(inst)
    end

    -- Textures / Materials
    if Variables.Config.NukeTextures then
        nukeTexturesIrreversible(inst)
    elseif Variables.Config.HideDecals and (inst:IsA("Decal") or inst:IsA("Texture")) then
        hideDecalOrTexture(inst)
    end

    if Variables.Config.SmoothPlasticEverywhere and inst:IsA("BasePart") then
        smoothPlasticPart(inst)
    end

    -- Physics
    if Variables.Config.FreezeWorldAssemblies and inst:IsA("BasePart") then
        freezeWorldPart(inst)
    end

    if Variables.Config.RemoveLocalNetworkOwnership and inst:IsA("BasePart") then
        pcall(function() if not inst.Anchored then inst:SetNetworkOwner(nil) end end)
    end

    if Variables.Config.DisableConstraints then
        disableConstraint(inst)
    end

    -- Sounds
    if Variables.Config.MuteAllSounds and inst:IsA("Sound") then 
        guardSound(inst)
    end

    --[[
        FIX (APPLIED):
        Corrected config variable name from 'PauseAllAnimations'
        to 'PauseOtherAnimations' to match your Config table.
    ]]
    -- Animators
    if (Variables.Config.PauseCharacterAnimations or Variables.Config.PauseOtherAnimations) and inst:IsA("Animator") then
        guardAnimator(inst)
    end

    -- GUI
    if Variables.Config.DisableViewportFrames and inst:IsA("ViewportFrame") then
        hideViewport(inst)
    end
    if Variables.Config.DisableVideoFrames and inst:IsA("VideoFrame") then
        hideVideo(inst)
    end
    if Variables.Config.HidePlayerGui and inst:IsA("ScreenGui") then
        local pg = RbxService.Players.LocalPlayer and RbxService.Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if pg and inst.Parent == pg then
            hidePlayerGui(inst)
        end
    end
end

-- NEW: A batch function to run on Start, based on V2.lua
local function ApplyBatch()
    eachDescendantChunked(RbxService.Workspace, function() return true end, ApplyToInstance)
    eachDescendantChunked(RbxService.Lighting, function() return true end, ApplyToInstance)
    eachDescendantChunked(RbxService.SoundService, function() return true end, ApplyToInstance)

    local pg = RbxService.Players.LocalPlayer and RbxService.Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if pg then
        eachDescendantChunked(pg, function() return true end, ApplyToInstance)
    end
end

-- NEW: Rebuilt watchers based on V2.lua
local function buildWatchers()
    Variables.Maids.Watchers:DoCleaning()
    local myTransition = Variables.Runtime.transitionId -- guard

    local function OnDescendantAdded(inst)
         if not Variables.Config.Enabled or Variables.Runtime.cancelRequested or Variables.Runtime.transitionId ~= myTransition then return end
         ApplyToInstance(inst)
    end

    -- Workspace: emitters, parts, constraints, animators, sounds, textures
    Variables.Maids.Watchers:GiveTask(RbxService.Workspace.DescendantAdded:Connect(OnDescendantAdded))
    Variables.Maids.Watchers:GiveTask(RbxService.Lighting.DescendantAdded:Connect(OnDescendantAdded))
    Variables.Maids.Watchers:GiveTask(RbxService.SoundService.DescendantAdded:Connect(OnDescendantAdded))

    -- PlayerGui & CoreGui
    local pg = RbxService.Players.LocalPlayer and RbxService.Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if pg then
        Variables.Maids.Watchers:GiveTask(pg.DescendantAdded:Connect(OnDescendantAdded))
    end
    Variables.Maids.Watchers:GiveTask(RbxService.CoreGui.DescendantAdded:Connect(OnDescendantAdded))

    -- Lighting stabilization
    Variables.Maids.Watchers:GiveTask(RbxService.Lighting.Changed:Connect(function()
        if not Variables.Config.Enabled or Variables.Runtime.cancelRequested or Variables.Runtime.transitionId ~= myTransition then return end
        scheduleApplyLighting()
    end))
end

----------------------------------------------------------------------
-- Apply / Restore (master switch) with atomic gating (CHANGED)
----------------------------------------------------------------------
local function applyAll()
    Variables.Config.Enabled = true
    -- 'cancelRequested' is reset by the requestEnabled loop

    local function try3D(disable)
        pcall(function() RbxService.RunService:Set3dRenderingEnabled(not (disable == true)) end)
    end

    snapshotLighting()

    if Variables.Config.DisableThreeDRendering then
        try3D(true)
    end

    if Variables.Config.TargetFramesPerSecond and Variables.Config.TargetFramesPerSecond > 0 then
        setFpsCap(Variables.Config.TargetFramesPerSecond)
    end

    if Variables.Config.HideCoreGui  then hideCoreGuiAll(true) end

    -- NEW: Run the V2.lua-style batch process
    ApplyBatch()

    -- These are still needed for non-descendant properties
    if Variables.Config.AnchorCharacter   then anchorCharacter(true) end
    if Variables.Config.ReduceSimulationRadius then reduceSimulationRadius() end
    if Variables.Config.RemoveGrassDecoration then terrainDecorationSet(true) end
    if Variables.Config.UseMinimumQuality then applyQualityMinimum() end
    if Variables.Config.ReplaceWaterWithBlock then applyWaterReplacement() end
    
    -- Schedule lighting *after* batch
    scheduleApplyLighting()

    -- Only build watchers if this transition is still current
    buildWatchers()
end

local function restoreAll()
    -- 'cancelRequested = true' is REMOVED from here.
    
    -- Shut down watchers first
    Variables.Maids.Watchers:DoCleaning()
    Variables.Maids.EmitterGuards:DoCleaning()

    -- ALWAYS restore (fixes spam-toggle wedge)
    pcall(function() RbxService.RunService:Set3dRenderingEnabled(true) end)

    restoreViewportAndVideo()
    restoreSounds()
    releaseAnimatorGuards()
    toggleCharacterAnimateScripts(true)

    restoreAnchoredParts()
    restoreWorldConstraints()
    restoreCharacterAnchors()

    restorePlayerGuiAll()
    restoreCoreGuiAll()
    restorePartMaterials()
    restoreDecalsAndTextures()
    restoreEmitters()

    -- Lighting + postFX
    pcall(function()
        local P = Variables.Snapshot.LightingProps
        if P then
            local L = RbxService.Lighting
            L.GlobalShadows            = P.GlobalShadows
            L.Brightness               = P.Brightness
            L.ClockTime                = P.ClockTime
            L.Ambient                  = P.Ambient
            L.OutdoorAmbient           = P.OutdoorAmbient
            L.EnvironmentDiffuseScale  = P.EnvironmentDiffuseScale
            L.EnvironmentSpecularScale = P.EnvironmentSpecularScale
            -- Restore fog
            L.FogStart                 = P.FogStart
            L.FogEnd                   = P.FogEnd
            L.FogColor                 = P.FogColor
        end
        if Variables.Config.ForceClearBlurOnRestore then
            for _, child in ipairs(RbxService.Lighting:GetChildren()) do
                if child:IsA("BlurEffect") then child.Enabled = false end
            end
        end
    end)
    restorePostEffects()

    -- Restore Skyboxes
    for _, inst in ipairs(Variables.Snapshot.Skyboxes) do
        if inst then pcall(function() inst.Parent = RbxService.Lighting end) end
    end
    Variables.Snapshot.Skyboxes = {}

    if Variables.Snapshot.TerrainDecoration ~= nil then
        local terrain = RbxService.Workspace:FindFirstChildOfClass("Terrain")
        pcall(function()
            if terrain and typeof(terrain.Decoration) == "boolean" then
                terrain.Decoration = Variables.Snapshot.TerrainDecoration
            end
        end)
        Variables.Snapshot.TerrainDecoration = nil
    end

    restoreQuality()
    removeWaterReplacement()

    -- Clear lightweight maps
    Variables.Snapshot.PlayerGuiEnabled = {}
    Variables.Snapshot.CoreGuiState     = {}
    Variables.Snapshot.ViewportVisible  = {}
    Variables.Snapshot.VideoPlaying     = {}

    Variables.Config.Enabled = false
    Variables.Runtime.cancelRequested = false -- Be officially "not cancelled"
end

-- NEW: atomic, coalescing master state changer
local function requestEnabled(desired)
    Variables.Runtime.desiredEnabled = desired

    if Variables.Runtime.inTransition then
        -- Tell current sweeps to stop sooner and let the outer loop pick up new desired state
        Variables.Runtime.cancelRequested = true
        return
    end

    Variables.Runtime.inTransition = true
    task.spawn(function()
        -- Use a pcall to catch any error in the master loop
        local success, err = pcall(function()
            while Variables.Config.Enabled ~= Variables.Runtime.desiredEnabled do
                Variables.Runtime.transitionId += 1
                local want = Variables.Runtime.desiredEnabled
                
                Variables.Runtime.cancelRequested = false
                
                if want then
                    applyAll()
                else
                    restoreAll()
                end
                task.wait() -- yield to allow rapid flips to coalesce
            end
        end)

        -- CRITICAL: Always set inTransition to false, even if the loop errored.
        -- This "un-bricks" the module.
        Variables.Runtime.inTransition = false

        if not success then
            warn("Optimization master loop failed:", err)
        end
    end)
end

----------------------------------------------------------------------
-- UI (Obsidian)
----------------------------------------------------------------------
-- Pick a tab/groupbox that exists; prefer 'Misc', then 'Main'
local Tabs = UI and UI.Tabs or {}
local TargetTab = Tabs.Misc or Tabs.Main or Tabs["UI Settings"] or (function()
    for _, anyTab in pairs(Tabs) do return anyTab end
    return nil
end)()

local group
if TargetTab and typeof(TargetTab.AddRightGroupbox) == "function" then
    group = TargetTab:AddRightGroupbox("Optimization", "power")
elseif TargetTab and typeof(TargetTab.AddLeftGroupbox) == "function" then
    group = TargetTab:AddLeftGroupbox("Optimization", "power")
else
    -- Last resort: try root UI
    group = UI.Tabs.Main and UI.Tabs.Main:AddLeftGroupbox("Optimization", "power")
end

-- Build controls (no chained :OnChanged!)
group:AddToggle("OptEnabled", { Text = "Enable Optimization", Default = false, Tooltip = "Master switch" })

group:AddSlider("OptFps", {
    Text = "Target FPS",
    Min = 1, Max = 120,
    Default = Variables.Config.TargetFramesPerSecond,
    Suffix = "FPS",
})

group:AddDivider()
group:AddLabel("Rendering / UI")

group:AddToggle("Opt3D",             { Text="Disable 3D Rendering",      Default=Variables.Config.DisableThreeDRendering })
group:AddToggle("OptHidePlayerGui",  { Text="Hide PlayerGui",            Default=Variables.Config.HidePlayerGui })
group:AddToggle("OptHideCoreGui",    { Text="Hide CoreGui",              Default=Variables.Config.HideCoreGui })
group:AddToggle("OptNoViewports",    { Text="Disable ViewportFrames",    Default=Variables.Config.DisableViewportFrames })
group:AddToggle("OptNoVideos",       { Text="Disable VideoFrames",       Default=Variables.Config.DisableVideoFrames })
group:AddToggle("OptMute",           { Text="Mute All Sounds",           Default=Variables.Config.MuteAllSounds })

group:AddDivider()
group:AddLabel("Animation / Motion")

group:AddToggle("OptPauseChar",      { Text="Pause Character Animations", Default=Variables.Config.PauseCharacterAnimations })
group:AddToggle("OptPauseOther",     { Text="Pause Other Animations (client‑driven)", Default=Variables.Config.PauseOtherAnimations })
group:AddToggle("OptFreeze",         { Text="Freeze World Assemblies (reversible)",   Default=Variables.Config.FreezeWorldAssemblies })
group:AddToggle("OptNoConstraints",  { Text="Disable Constraints (reversible)",       Default=Variables.Config.DisableConstraints })

group:AddDivider()
group:AddLabel("Physics / Network")

group:AddToggle("OptAnchorChar",     { Text="Anchor Character",                 Default=Variables.Config.AnchorCharacter })
group:AddToggle("OptSimRadius",      { Text="Reduce Simulation Radius",         Default=Variables.Config.ReduceSimulationRadius })
group:AddToggle("OptNoNet",          { Text="Remove Local Network Ownership",   Default=Variables.Config.RemoveLocalNetworkOwnership })

group:AddDivider()
group:AddLabel("Particles / Effects / Materials")

group:AddToggle("OptStopParticles",  { Text="Stop Particle Systems (reversible)", Default=Variables.Config.StopParticleSystems })
group:AddToggle("OptDestroyEmitters",{ Text="Destroy Emitters (irreversible)",    Default=Variables.Config.DestroyEmitters })
group:AddToggle("OptSmooth",         { Text="Force SmoothPlastic (reversible)",   Default=Variables.Config.SmoothPlasticEverywhere })
group:AddToggle("OptHideDecals",     { Text="Hide Decals/Textures (reversible)",  Default=Variables.Config.HideDecals })
group:AddToggle("OptNukeTextures",   { Text="Nuke Textures (irreversible)",       Default=Variables.Config.NukeTextures })

group:AddDivider()
group:AddLabel("Lighting / Quality")

group:AddToggle("OptNoGrass",        { Text="Remove Grass Decoration", Default=Variables.Config.RemoveGrassDecoration })
group:AddToggle("OptNoPostFX",       { Text="Disable Post‑FX (Bloom/CC/DoF/SunRays/Blur)", Default=Variables.Config.DisablePostEffects })
group:AddToggle("OptGraySky",        { Text="Gray Sky",                 Default=Variables.Config.GraySky })
-- REMOVED: group:AddSlider("OptGraySkyShade",   { Text="Gray Sky Shade", Min=0, Max=255, Default=Variables.Config.GraySkyShade })
group:AddToggle("OptFullBright",     { Text="Full Bright",              Default=Variables.Config.FullBright })
group:AddSlider("OptFullBrightLvl",  { Text="Full Bright Level", Min=0, Max=5, Default=Variables.Config.FullBrightLevel })
group:AddToggle("OptNoFog",          { Text="Remove Fog",               Default=Variables.Config.RemoveFog })
group:AddToggle("OptNoSky",          { Text="Remove Skybox",            Default=Variables.Config.RemoveSkybox })
group:AddToggle("OptMinQuality",     { Text="Use Minimum Quality",      Default=Variables.Config.UseMinimumQuality })
group:AddToggle("OptClearBlurRestore",{ Text="Force Clear Blur on Restore", Default=Variables.Config.ForceClearBlurOnRestore })

group:AddDivider()
group:AddLabel("Water Replacement (auto‑mimic)")

group:AddToggle("OptWaterProxy",     { Text="Replace Water", Default=Variables.Config.ReplaceWaterWithBlock })
group:AddSlider("OptWaterTrans", {
    Text    = "Water Transparency",
    Min     = 0,
    Max     = 100,
    Default = Variables.Config.WaterTransparency * 100,
    Suffix  = "%",
})

----------------------------------------------------------------------
-- Wire handlers via Toggles/Options (no chained :OnChanged on returns)
----------------------------------------------------------------------
local function bindToggle(idx, fn)
    local t = Toggles[idx]
    if t and typeof(t.OnChanged) == "function" then
        t:OnChanged(function() fn(t.Value) end)
    end
end

local function bindOption(idx, fn)
    local o = Options[idx]
    if o and typeof(o.OnChanged) == "function" then
        o:OnChanged(function() fn(o.Value, o) end)
    end
end

-- Master (CHANGED: now atomic & coalescing)
bindToggle("OptEnabled", function(v) requestEnabled(v) end)

-- FPS
bindOption("OptFps", function(v)
    v = math.floor(tonumber(v) or Variables.Config.TargetFramesPerSecond)
    Variables.Config.TargetFramesPerSecond = v
    if Variables.Config.Enabled then setFpsCap(v) end
end)

-- Rendering / UI
bindToggle("Opt3D", function(v)
    Variables.Config.DisableThreeDRendering = v
    if Variables.Config.Enabled then pcall(function() RbxService.RunService:Set3dRenderingEnabled(not v) end) end
end)

bindToggle("OptHidePlayerGui", function(v)
    Variables.Config.HidePlayerGui = v
    if Variables.Config.Enabled then
        if v then hidePlayerGuiAll() else restorePlayerGuiAll() end
        buildWatchers() -- Re-arm watcher
    end
end)

bindToggle("OptHideCoreGui", function(v)
    Variables.Config.HideCoreGui = v
    if Variables.Config.Enabled then hideCoreGuiAll(v) end
end)

bindToggle("OptNoViewports", function(v)
    Variables.Config.DisableViewportFrames = v
    if Variables.Config.Enabled then
        if v then scanViewportAndVideo() else restoreViewportAndVideo() end
        buildWatchers()
    end
end)

bindToggle("OptNoVideos", function(v)
    Variables.Config.DisableVideoFrames = v
    if Variables.Config.Enabled then
        if v then scanViewportAndVideo() else restoreViewportAndVideo() end
        buildWatchers()
    end
end)

bindToggle("OptMute", function(v)
    Variables.Config.MuteAllSounds = v
    if Variables.Config.Enabled then
        if v then applyMuteAllSounds() else restoreSounds() end
        buildWatchers()
    end
end)

-- Animation / Motion
bindToggle("OptPauseChar", function(v)
    Variables.Config.PauseCharacterAnimations = v
    if Variables.Config.Enabled then
        if v then toggleCharacterAnimateScripts(false) else toggleCharacterAnimateScripts(true) end
        releaseAnimatorGuards()
        eachDescendantChunked(RbxService.Workspace, function(inst) return inst:IsA("Animator") end, guardAnimator)
        buildWatchers()
    end
end)

bindToggle("OptPauseOther", function(v)
    Variables.Config.PauseOtherAnimations = v
    if Variables.Config.Enabled then
        releaseAnimatorGuards()
        eachDescendantChunked(RbxService.Workspace, function(inst) return inst:IsA("Animator") end, guardAnimator)
        buildWatchers()
    end
end)

bindToggle("OptFreeze", function(v)
    Variables.Config.FreezeWorldAssemblies = v
    if Variables.Config.Enabled then
        if v then
            eachDescendantChunked(RbxService.Workspace, function(inst) return inst:IsA("BasePart") end, freezeWorldPart)
        else
            restoreAnchoredParts()
        end
        buildWatchers()
    end
end)

bindToggle("OptNoConstraints", function(v)
    Variables.Config.DisableConstraints = v
    if Variables.Config.Enabled then
        if v then disableWorldConstraints() else restoreWorldConstraints() end
        buildWatchers()
    end
end)

-- Physics / Network
bindToggle("OptAnchorChar", function(v)
    Variables.Config.AnchorCharacter = v
    if Variables.Config.Enabled then
        if v then anchorCharacter(true) else restoreCharacterAnchors() end
    end
end)

bindToggle("OptSimRadius", function(v)
    Variables.Config.ReduceSimulationRadius = v
    if Variables.Config.Enabled and v then reduceSimulationRadius() end
end)

bindToggle("OptNoNet", function(v)
    Variables.Config.RemoveLocalNetworkOwnership = v
    if Variables.Config.Enabled and v then removeNetOwnership() end
    if Variables.Config.Enabled then buildWatchers() end
end)

-- Particles / Effects / Materials
bindToggle("OptStopParticles", function(v)
    Variables.Config.StopParticleSystems = v
    if Variables.Config.Enabled then
        if v then eachDescendantChunked(RbxService.Workspace, isEmitter, stopEmitter)
        else restoreEmitters() end
        buildWatchers()
    end
end)

bindToggle("OptDestroyEmitters", function(v)
    Variables.Config.DestroyEmitters = v
    if Variables.Config.Enabled and v and not Variables.Irreversible.EmittersDestroyed then
        eachDescendantChunked(RbxService.Workspace, isEmitter, destroyEmitterIrreversible)
        Variables.Irreversible.EmittersDestroyed = true
        buildWatchers()
    end
end)

bindToggle("OptSmooth", function(v)
    Variables.Config.SmoothPlasticEverywhere = v
    if Variables.Config.Enabled then
        if v then
            eachDescendantChunked(RbxService.Workspace, function(inst) return inst:IsA("BasePart") end, smoothPlasticPart)
            buildWatchers()
        else
            restorePartMaterials()
        end
    end
end)

bindToggle("OptHideDecals", function(v)
    Variables.Config.HideDecals = v
    if Variables.Config.Enabled then
        if v then
            eachDescendantChunked(RbxService.Workspace, function(inst) return inst:IsA("Decal") or inst:IsA("Texture") end, hideDecalOrTexture)
            buildWatchers()
        else
            restoreDecalsAndTextures()
        end
    end
end)

bindToggle("OptNukeTextures", function(v)
    Variables.Config.NukeTextures = v
    if Variables.Config.Enabled and v and not Variables.Irreversible.TexturesNuked then
        -- Rerun the nuke functions
        pcall(function()
            if RbxService.MaterialService then
                RbxService.MaterialService.FallbackMaterial = Enum.Material.SmoothPlastic
                if typeof(RbxService.MaterialService.Use2022Materials) == "boolean" then
                    RbxService.MaterialService.Use2022Materials = false
                end
                for _, variant in ipairs(RbxService.MaterialService:GetChildren()) do
                    if variant:IsA("MaterialVariant") then
                        pcall(function() variant:Destroy() end)
                    end
                end
            end
        end)
        eachDescendantChunked(RbxService.Workspace, function(inst)
            return inst:IsA("Decal") or inst:IsA("Texture") or inst:IsA("SurfaceAppearance")
                or inst:IsA("MeshPart") or inst:IsA("SpecialMesh") or inst:IsA("Shirt")
                or inst:IsA("Pants") or inst:IsA("ShirtGraphic") or inst:IsA("BasePart")
        end, nukeTexturesIrreversible)
        eachDescendantChunked(game, function(inst)
            return inst:IsA("ImageLabel") or inst:IsA("ImageButton")
        end, nukeTexturesIrreversible)
        
        Variables.Irreversible.TexturesNuked = true
        buildWatchers()
    end
end)

-- Lighting / Quality
bindToggle("OptNoGrass", function(v)
    Variables.Config.RemoveGrassDecoration = v
    if Variables.Config.Enabled then terrainDecorationSet(v) end
end)

bindToggle("OptNoPostFX", function(v)
    Variables.Config.DisablePostEffects = v
    if Variables.Config.Enabled then
        if v then disablePostEffects() else restorePostEffects() end
        buildWatchers()
    end
end)

-- NEW: Helper function to restore skybox if BOTH sky toggles are off
local function ConditionalRestoreSkybox()
    if not Variables.Config.GraySky and not Variables.Config.RemoveSkybox then
        for _, inst in ipairs(Variables.Snapshot.Skyboxes) do
            if inst then pcall(function() inst.Parent = RbxService.Lighting end) end
        end
        Variables.Snapshot.Skyboxes = {}
    end
end

bindToggle("OptGraySky", function(v)
    Variables.Config.GraySky = v
    if Variables.Config.Enabled then
        if not v then
            ConditionalRestoreSkybox()
        end
        scheduleApplyLighting()
        buildWatchers()
    end
end)

-- REMOVED: bindOption("OptGraySkyShade", ...)

bindToggle("OptFullBright", function(v)
    Variables.Config.FullBright = v
    if Variables.Config.Enabled then 
        scheduleApplyLighting()
        buildWatchers() 
    end
end)

bindOption("OptFullBrightLvl", function(v)
    v = math.floor(tonumber(v) or Variables.Config.FullBrightLevel)
    Variables.Config.FullBrightLevel = v
    if Variables.Config.Enabled and Variables.Config.FullBright then 
        scheduleApplyLighting() 
    end
end)

bindToggle("OptNoFog", function(v)
    Variables.Config.RemoveFog = v
    if Variables.Config.Enabled then
        -- Let the main scheduler handle applying/restoring fog
        scheduleApplyLighting()
        buildWatchers() -- Re-arm the lighting watcher
    end
end)

bindToggle("OptNoSky", function(v)
    Variables.Config.RemoveSkybox = v
    if Variables.Config.Enabled then
        if v then
            -- Apply: Find all current skyboxes, snapshot, and remove
            local currentSkies = {}
            for _, child in ipairs(RbxService.Lighting:GetChildren()) do
                -- FIX: IsA, not IsC
                if child:IsA("Sky") or child:IsA("Clouds") or child:IsA("Atmosphere") then
                    table.insert(currentSkies, child)
                end
            end
            for _, sky in ipairs(currentSkies) do
                if not table.find(Variables.Snapshot.Skyboxes, sky) then -- Check before adding
                    table.insert(Variables.Snapshot.Skyboxes, sky)
                end
                sky.Parent = nil
            end
        else
            -- Restore: Put back the skyboxes we took
            ConditionalRestoreSkybox()
        end
        buildWatchers() -- Re-arm the childadded watcher
    end
end)


bindToggle("OptMinQuality", function(v)
    Variables.Config.UseMinimumQuality = v
    if Variables.Config.Enabled then
        if v then applyQualityMinimum() else restoreQuality() end
    end
end)

bindToggle("OptClearBlurRestore", function(v)
    Variables.Config.ForceClearBlurOnRestore = v
end)

-- Water
bindToggle("OptWaterProxy", function(v)
    Variables.Config.ReplaceWaterWithBlock = v
    if not Variables.Config.Enabled then return end
    if v then applyWaterReplacement() else removeWaterReplacement() end
end)

bindOption("OptWaterTrans", function(v)
    local t = math.clamp((tonumber(v) or 0) / 100, 0, 1)
    Variables.Config.WaterTransparency = t
    if Variables.Runtime.WaterMode == "Part" and Variables.Runtime.WaterProxyPart then
        Variables.Runtime.WaterProxyPart.Transparency = t
    elseif Variables.Runtime.WaterMode == "Terrain" and Variables.Runtime.WaterSource then
        pcall(function() Variables.Runtime.WaterSource.WaterTransparency = t end)
    end
end)

----------------------------------------------------------------------
-- Module Stop
----------------------------------------------------------------------
local function Stop()
    if Toggles and Toggles.OptEnabled and typeof(Toggles.OptEnabled.SetValue) == "function" then
        Toggles.OptEnabled:SetValue(false)
    else
        requestEnabled(false)
    end
    Variables.Maids.Optimization:DoCleaning()
end

return { Name = "Optimization", Stop = Stop }

end end
