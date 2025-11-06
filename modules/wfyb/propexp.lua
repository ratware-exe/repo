-- modules/propexp.lua
return function(UI)
    local Env = (getgenv and getgenv()) or _G
    local RepoBase = Env.RepoBase
    local ObsidianRepoBase = Env.ObsidianRepoBase

    -- ---- Maid (repo -> fallback) -------------------------------------------
    local Maid = Env.WFYB_Maid
    if not Maid then
        local ok, mod = pcall(function()
            return loadstring(game:HttpGet(RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
        end)
        Maid = ok and mod or (function()
            local M = {}; M.__index = M
            function M.new() return setmetatable({ _t = {} }, M) end
            function M:GiveTask(t) local n = #self._t+1; self._t[n]=t; return n end
            function M:DoCleaning()
                for i=#self._t,1,-1 do
                    local v=self._t[i]
                    if typeof(v)=="RBXScriptConnection" then pcall(function() v:Disconnect() end)
                    elseif type(v)=="function" then pcall(v)
                    elseif typeof(v)=="Instance" then pcall(function() v:Destroy() end)
                    end
                    self._t[i]=nil
                end
            end
            return M
        end)()
        Env.WFYB_Maid = Maid
    end

    -- ---- Global per-feature state ------------------------------------------
    Env.WFYB_State = Env.WFYB_State or {}
    local S = Env.WFYB_State.PropEXP or {
        Run                      = false,
        IntervalSeconds          = 2.0,
        ResolveTickSeconds       = 0.25,
        RetrySeconds             = 0.70,
        RelativeCFrame           = CFrame.new(0, 1.6, 0),
        BoatSearchTimeoutSeconds = 12,
        SpawnYOffset             = 0,
        PinkClass                = nil,
        OwnBoatModel             = nil,
        Nevermore                = nil,
        BoatApi                  = nil,
        PropClassProvider        = nil,
        ClientBinders            = nil,
        ToggleWired              = false,
    }
    Env.WFYB_State.PropEXP = S

    Env.WFYB_Maids = Env.WFYB_Maids or {}
    Env.WFYB_Maids.PropEXP = Env.WFYB_Maids.PropEXP or Maid.new()
    local MaidBucket = Env.WFYB_Maids.PropEXP

    -- ---- Services helper ----------------------------------------------------
    local RbxService = setmetatable({}, {
        __index = function(t, k)
            local s = game:GetService(k)
            rawset(t, k, s)
            return s
        end
    })

    -- ---- UI resolve ---------------------------------------------------------
    local UIShared = Env.WFYB_UI -- provided by dependency/UIRegistry.lua
    local function getTab(name, icon)
        if UIShared and UIShared.Tabs and UIShared.Tabs[name] then
            return UIShared.Tabs[name]
        end
        -- fallback: create once via registry's window
        local Library = UIShared and UIShared.Library
        local Window  = UIShared and UIShared.Window
        if Library and Window then
            UIShared.Tabs = UIShared.Tabs or {}
            UIShared.Tabs[name] = Window:AddTab(name, icon or "circle")
            return UIShared.Tabs[name]
        end
        error("UI window not available (UIRegistry must mount first)")
    end
    local function getGroupbox(tab, side, title, icon)
        Env.__WFYB_Groupboxes = Env.__WFYB_Groupboxes or {}
        local key = (tostring(tab) or "?") .. "|" .. side .. "|" .. title
        if Env.__WFYB_Groupboxes[key] and Env.__WFYB_Groupboxes[key].__alive ~= false then
            return Env.__WFYB_Groupboxes[key]
        end
        local gb = (string.find(string.lower(side), "left") and tab.AddLeftGroupbox or tab.AddRightGroupbox)(tab, title, icon)
        Env.__WFYB_Groupboxes[key] = gb
        return gb
    end
    local function getOrCreateToggle(groupbox, id, args)
        local Library = UIShared and UIShared.Library
        local opt = Library and Library.Options and Library.Options[id]
        if opt and opt.Set then return opt end
        return groupbox:AddToggle(id, args)
    end

    -- ---- Original logic (verbatim) -----------------------------------------
    -- EnsureNevermoreReady / SafeCall / QuantizeCFrame / boat helpers / place cycle
    -- Source: modules in main-2.lua near Prop EXP section
    -- Citations across functions:
    --   EnsureNevermoreReady/SafeCall/QuantizeCFrame: :contentReference[oaicite:0]{index=0}
    --   Boat owner/scan helpers:                      :contentReference[oaicite:1]{index=1}
    --   FindNewlyPlacedPink/PlaceWithRetry:          :contentReference[oaicite:2]{index=2}
    --   Start/Stop loop cadence:                     :contentReference[oaicite:3]{index=3}

    local function EnsureNevermoreReady()
        if not S.Nevermore then
            S.Nevermore = require(RbxService.ReplicatedStorage:WaitForChild("Nevermore"))
        end
        if not S.BoatApi then
            S.BoatApi = S.Nevermore("BoatAPIServiceClient")
        end
        if not S.PropClassProvider then
            local okClient, providerClient = pcall(function()
                return S.Nevermore("PropClassProviderClient")
            end)
            if okClient and providerClient then
                S.PropClassProvider = providerClient
            else
                S.PropClassProvider = S.Nevermore("PropClassProvider")
            end
        end
        if not S.ClientBinders then
            S.ClientBinders = S.Nevermore("ClientBinders")
        end
    end -- :contentReference[oaicite:4]{index=4}

    local function SafeCall(target, methodName, ...)
        local TargetMethod = target and target[methodName]
        if type(TargetMethod) ~= "function" then return nil end
        local Args = { ... }
        local ok, res = pcall(function() return TargetMethod(target, table.unpack(Args)) end)
        if ok and res ~= nil then return res end
        ok, res = pcall(function() return TargetMethod(table.unpack(Args)) end)
        if ok and res ~= nil then return res end
        return nil
    end -- :contentReference[oaicite:5]{index=5}

    local function Round4(n) return math.floor((n or 0) * 10000 + 0.5) / 10000 end
    local function QuantizeCFrame(cf)
        local x,y,z,r00,r01,r02,r10,r11,r12,r20,r21,r22 = cf:GetComponents()
        return CFrame.new(
            Round4(x),Round4(y),Round4(z),
            Round4(r00),Round4(r01),Round4(r02),
            Round4(r10),Round4(r11),Round4(r12),
            Round4(r20),Round4(r21),Round4(r22)
        )
    end -- :contentReference[oaicite:6]{index=6}

    local function BoatsFolder()
        return RbxService.Workspace:FindFirstChild("Boats")
    end

    local function BoatOwnerUserId(boatModel)
        if not (boatModel and boatModel:IsA("Model")) then return nil end
        local attrs = boatModel:GetAttributes()
        for k,v in pairs(attrs) do
            local lk = string.lower(k)
            if lk == "owneruserid" or lk == "owner" then
                local n = tonumber(v)
                if n then return n end
            end
        end
        local boatDataFolder = boatModel:FindFirstChild("BoatData")
        if boatDataFolder then
            for _, ch in ipairs(boatDataFolder:GetChildren()) do
                local ln = string.lower(ch.Name)
                if ch:IsA("IntValue") and string.find(ln, "owner") then return ch.Value end
                if ch:IsA("ObjectValue") and ln == "owner" then local pl=ch.Value; if pl and pl.UserId then return pl.UserId end end
                if ch:IsA("StringValue") and string.find(ln, "owner") then local n=tonumber(ch.Value); if n then return n end end
            end
        end
        local descendants = boatModel:GetDescendants()
        for i=1,#descendants do
            local v = descendants[i]
            if v:IsA("IntValue") and (v.Name=="Owner" or v.Name=="OwnerUserId") then return v.Value end
        end
        return nil
    end -- :contentReference[oaicite:7]{index=7}

    local function SnapshotOwnedBoats(ownerUserId)
        local out = {}
        local f = BoatsFolder(); if not f then return out end
        for _, m in ipairs(f:GetChildren()) do
            if m:IsA("Model") and BoatOwnerUserId(m) == ownerUserId then
                out[m] = true
            end
        end
        return out
    end

    local function WaitForNewOwnedBoat(ownerUserId, beforeSet, timeoutSeconds)
        local deadline = time() + (timeoutSeconds or 12)
        while time() < deadline do
            local f = BoatsFolder()
            if f then
                for _, m in ipairs(f:GetChildren()) do
                    if m:IsA("Model") and BoatOwnerUserId(m) == ownerUserId and not beforeSet[m] then
                        return m
                    end
                end
            end
            RbxService.RunService.Heartbeat:Wait()
        end
        return nil
    end -- :contentReference[oaicite:8]{index=8}

    local function FindOwnBoat()
        local f = BoatsFolder(); if not f then return nil end
        local myId = RbxService.Players.LocalPlayer.UserId
        for _, m in ipairs(f:GetChildren()) do
            if m:IsA("Model") and BoatOwnerUserId(m) == myId then
                return m
            end
        end
        return nil
    end -- (same region as owner helpers) :contentReference[oaicite:9]{index=9}

    local function GetPropBinder(model)
        local okGet, binder = pcall(function()
            return S.ClientBinders.Prop:Get(model)
        end)
        if okGet and binder then return binder end
        return nil
    end -- :contentReference[oaicite:10]{index=10}

    local function ModelWorldCFrame(model)
        local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
        if primary then return primary.CFrame end
        return nil
    end

    local function FindNewlyPlacedPink(boatModel, desiredWorld, timeoutSeconds)
        local deadline = time() + (timeoutSeconds or 3)
        local bestModel, bestDistance = nil, math.huge
        repeat
            for _, childModel in ipairs(boatModel:GetChildren()) do
                if childModel:IsA("Model") and GetPropBinder(childModel) then
                    local ln = string.lower(childModel.Name)
                    if string.find(ln, "pink") or string.find(ln, "gyro") or string.find(ln, "experimental") then
                        local cf = ModelWorldCFrame(childModel)
                        if cf then
                            local dist = (cf.Position - desiredWorld.Position).Magnitude
                            if dist < bestDistance then bestModel, bestDistance = childModel, dist end
                        end
                    end
                end
            end
            if bestModel then return bestModel end
            RbxService.RunService.Heartbeat:Wait()
        until time() > deadline
        return nil
    end -- :contentReference[oaicite:11]{index=11}

    local function PlaceWithRetry(relative, boatModel)
        local firstOk = pcall(function()
            S.BoatApi:PlacePropOnBoat(S.PinkClass, relative, boatModel)
        end)
        if firstOk then return true end
        task.wait(S.RetrySeconds or 0.7)
        local secondOk = pcall(function()
            S.BoatApi:PlacePropOnBoat(S.PinkClass, relative, boatModel)
        end)
        return secondOk or false
    end -- :contentReference[oaicite:12]{index=12}

    local PinkIdCandidates = { "PinkGyro", "PinkExperimental", "PinkExperimentalBlock", "ExperimentalBlockPink" }
    local PinkTKeyCandidates = { "props.pinkGyro", "props.pinkExperimental", "props.pink_experimental" }

    local function ResolvePinkClass()
        if S.PinkClass then return true end
        if not S.PropClassProvider then return false end
        for _, propId in ipairs(PinkIdCandidates) do
            local classObj =
                SafeCall(S.PropClassProvider, "GetPropClassFromPropId", propId) or
                SafeCall(S.PropClassProvider, "GetFromPropId", propId) or
                SafeCall(S.PropClassProvider, "FromTranslationKey", propId) or
                SafeCall(S.PropClassProvider, "GetPropClass", propId) or
                SafeCall(S.PropClassProvider, "Get", propId)
            if classObj then S.PinkClass = classObj; return true end
        end
        for _, tKey in ipairs(PinkTKeyCandidates) do
            local classObj =
                SafeCall(S.PropClassProvider, "GetPropClassFromTranslationKey", tKey) or
                SafeCall(S.PropClassProvider, "GetFromTranslationKey", tKey) or
                SafeCall(S.PropClassProvider, "FromTranslationKey", tKey)
            if classObj then S.PinkClass = classObj; return true end
        end
        return false
    end -- :contentReference[oaicite:13]{index=13}

    local function EnsureOwnBoat()
        if S.OwnBoatModel and S.OwnBoatModel.Parent then return true end
        local existing = FindOwnBoat()
        if existing then S.OwnBoatModel = existing; return true end
        if not S.PinkClass then return false end

        local hrp = (RbxService.Players.LocalPlayer.Character or RbxService.Players.LocalPlayer.CharacterAdded:Wait()):WaitForChild("HumanoidRootPart")
        local pivot = hrp.CFrame * CFrame.new(0, tonumber(S.SpawnYOffset) or 0, 0)
        local beforeSet = SnapshotOwnedBoats(RbxService.Players.LocalPlayer.UserId)
        pcall(function() S.BoatApi:PlaceNewBoat(S.PinkClass, pivot) end)

        local newBoat = WaitForNewOwnedBoat(RbxService.Players.LocalPlayer.UserId, beforeSet, S.BoatSearchTimeoutSeconds or 12)
        if not newBoat then return false end

        local initial = FindNewlyPlacedPink(newBoat, pivot, 3)
        if initial then pcall(function() S.BoatApi:SellProp(initial) end) end
        S.OwnBoatModel = newBoat
        return true
    end -- :contentReference[oaicite:14]{index=14}

    local function PlaceAndSellOnce()
        if not (S.OwnBoatModel and S.PinkClass) then return end
        local relativeQ = QuantizeCFrame(S.RelativeCFrame or CFrame.new(0, 1.6, 0))
        local desiredWorld = S.OwnBoatModel:GetPivot() * relativeQ
        if not PlaceWithRetry(relativeQ, S.OwnBoatModel) then return end
        local placed = FindNewlyPlacedPink(S.OwnBoatModel, desiredWorld, 3)
        if placed then pcall(function() S.BoatApi:SellProp(placed) end) end
    end -- :contentReference[oaicite:15]{index=15}

    -- ---- Module API ---------------------------------------------------------
    local Module = {}

    function Module.Start()
        if S.Run then return end
        S.Run = true
        EnsureNevermoreReady()
        if not S.PinkClass then ResolvePinkClass() end
        if not S.OwnBoatModel then S.OwnBoatModel = FindOwnBoat() end

        local th = task.spawn(function()
            while S.Run do
                if not S.PinkClass then
                    if not ResolvePinkClass() then
                        task.wait(S.ResolveTickSeconds or 0.25)
                        continue
                    end
                end
                if not EnsureOwnBoat() then
                    task.wait(S.ResolveTickSeconds or 0.25)
                    continue
                end
                PlaceAndSellOnce()
                task.wait(S.IntervalSeconds or 2.0)
            end
        end)
        MaidBucket:GiveTask(th)
        MaidBucket:GiveTask(function() S.Run = false end)
    end -- :contentReference[oaicite:16]{index=16}

    function Module.Stop()
        S.Run = false
        MaidBucket:DoCleaning()
    end

    -- ---- UI wiring ----------------------------------------------------------
    local Tab = getTab("EXP", "tractor")
    local gb = getGroupbox(Tab, "left", "EXP Farm", "arrow-right-left")
    local t = getOrCreateToggle(gb, "AutoPropEXPToggle", {
        Text = "Prop EXP",
        Tooltip = "Turn Feature [ON/OFF].",
        Default = false,
    })
    if not S.ToggleWired and t and t.OnChanged then
        S.ToggleWired = true
        t:OnChanged(function(on)
            if on then Module.Start() else Module.Stop() end
        end)
    end

    -- expose for other modules (optional)
    Env.WFYB_Modules = Env.WFYB_Modules or {}
    Env.WFYB_Modules.PropEXP = Module
    return { Name = "PropEXP", Stop = Module.Stop }
end
