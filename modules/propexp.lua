-- modules/propexp.lua
do
    return function(UI)
        ----------------------------------------------------------------------
        -- Repo dependencies
        ----------------------------------------------------------------------
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv  = (getgenv and getgenv()) or _G
        GlobalEnv.Signal = GlobalEnv.Signal or loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()
        local Maid       = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        ----------------------------------------------------------------------
        -- Shared UI helpers (groupbox registry)
        ----------------------------------------------------------------------
        local function EnsureSharedGroupbox(tabKey, boxKey, side, title, icon)
            if not UI or not UI.Tabs or not UI.Tabs[tabKey] then return nil end
            GlobalEnv.__WFYB_Groupboxes = GlobalEnv.__WFYB_Groupboxes or {}
            local GB = GlobalEnv.__WFYB_Groupboxes
            GB[tabKey] = GB[tabKey] or {}

            if GB[tabKey][boxKey] and GB[tabKey][boxKey].__alive then
                return GB[tabKey][boxKey]
            end

            local tab = UI.Tabs[tabKey]
            local box = (side == "Right") and tab:AddRightGroupbox(title, icon) or tab:AddLeftGroupbox(title, icon)
            box.__alive = true
            GB[tabKey][boxKey] = box
            return box
        end

        local function EnsureToggle(id, text, tip, default, groupbox)
            if UI and UI.Toggles and UI.Toggles[id] then return UI.Toggles[id] end
            if not groupbox then return nil end
            return groupbox:AddToggle(id, {
                Text = text, Tooltip = tip, Default = default or false
            })
        end

        ----------------------------------------------------------------------
        -- State/vars
        ----------------------------------------------------------------------
        local Vars = {
            Maid    = Maid.new(),
            Running = false,

            Nevermore          = nil,
            BoatAPI            = nil,
            PropClassProvider  = nil,
            ClientBinders      = nil,

            PinkClass     = nil,
            OwnBoatModel  = nil,

            IntervalSeconds          = 2.00,
            ResolveTickSeconds       = 0.25,
            RetrySeconds             = 0.70,
            RelativeCFrame           = CFrame.new(0, 1.6, 0),
            BoatSearchTimeoutSeconds = 12,
            SpawnYOffset             = 0,
        }

        ----------------------------------------------------------------------
        -- Utility & game helpers (verbatim behavior)
        ----------------------------------------------------------------------
        local function SafeCall(target, methodName, ...)
            local fn = target and target[methodName]
            if type(fn) ~= "function" then return nil end
            local args = { ... }
            local ok, res = pcall(function() return fn(target, table.unpack(args)) end)
            if ok and res ~= nil then return res end
            ok, res = pcall(function() return fn(table.unpack(args)) end)
            if ok and res ~= nil then return res end
            return nil
        end

        local function Round4(n) return math.floor((n or 0) * 10000 + 0.5) / 10000 end
        local function QuantizeCFrame(cf)
            local x,y,z,r00,r01,r02,r10,r11,r12,r20,r21,r22 = cf:GetComponents()
            return CFrame.new(
                Round4(x),Round4(y),Round4(z),
                Round4(r00),Round4(r01),Round4(r02),
                Round4(r10),Round4(r11),Round4(r12),
                Round4(r20),Round4(r21),Round4(r22)
            )
        end

        local function BoatsFolder() return RbxService.Workspace:FindFirstChild("Boats") end
        local function BoatOwnerUserId(boatModel)
            if not (boatModel and boatModel:IsA("Model")) then return nil end
            local attrs = boatModel:GetAttributes()
            for k,v in pairs(attrs) do
                local lk = string.lower(k)
                if lk == "owneruserid" or lk == "owner" then
                    local n = tonumber(v); if n then return n end
                end
            end
            local data = boatModel:FindFirstChild("BoatData")
            if data then
                for _,ch in ipairs(data:GetChildren()) do
                    local ln = string.lower(ch.Name)
                    if ch:IsA("IntValue") and string.find(ln,"owner") then return ch.Value end
                    if ch:IsA("ObjectValue") and ln=="owner" then
                        local p = ch.Value; if p and p.UserId then return p.UserId end
                    end
                    if ch:IsA("StringValue") and string.find(ln,"owner") then
                        local n = tonumber(ch.Value); if n then return n end
                    end
                end
            end
            for _,d in ipairs(boatModel:GetDescendants()) do
                if d:IsA("IntValue") and (d.Name=="Owner" or d.Name=="OwnerUserId") then
                    return d.Value
                end
            end
            return nil
        end

        local function FindOwnBoat()
            local folder = BoatsFolder(); if not folder then return nil end
            local userId = RbxService.Players.LocalPlayer and RbxService.Players.LocalPlayer.UserId
            if not userId then return nil end
            for _,modelCandidate in ipairs(folder:GetChildren()) do
                if modelCandidate:IsA("Model") and BoatOwnerUserId(modelCandidate) == userId then
                    return modelCandidate
                end
            end
            return nil
        end

        local function SnapshotOwnedBoats(userId)
            local out, folder = {}, BoatsFolder()
            if not folder then return out end
            for _,m in ipairs(folder:GetChildren()) do
                if m:IsA("Model") and BoatOwnerUserId(m) == userId then out[m] = true end
            end
            return out
        end

        local function WaitForNewOwnedBoat(userId, beforeSet, timeoutSeconds)
            local deadline = time() + (timeoutSeconds or Vars.BoatSearchTimeoutSeconds or 12)
            while time() < deadline do
                local folder = BoatsFolder()
                if folder then
                    for _,m in ipairs(folder:GetChildren()) do
                        if m:IsA("Model") and BoatOwnerUserId(m) == userId and not beforeSet[m] then
                            return m
                        end
                    end
                end
                RbxService.RunService.Heartbeat:Wait()
            end
            return nil
        end

        local PinkIdCandidates   = { "PinkGyro","PinkExperimental","PinkExperimentalBlock","ExperimentalBlockPink" }
        local PinkTKeyCandidates = { "props.pinkGyro","props.pinkExperimental","props.pink_experimental" }

        local function EnsureNevermoreReady()
            if not Vars.Nevermore         then Vars.Nevermore         = require(RbxService.ReplicatedStorage:WaitForChild("Nevermore")) end
            if not Vars.BoatAPI           then Vars.BoatAPI           = Vars.Nevermore("BoatAPIServiceClient") end
            if not Vars.PropClassProvider then
                local ok, p = pcall(function() return Vars.Nevermore("PropClassProviderClient") end)
                Vars.PropClassProvider = ok and p or Vars.Nevermore("PropClassProvider")
            end
            if not Vars.ClientBinders     then Vars.ClientBinders     = Vars.Nevermore("ClientBinders") end
        end

        local function ResolvePinkClass()
            if Vars.PinkClass then return true end
            if not Vars.PropClassProvider then return false end

            for _,propId in ipairs(PinkIdCandidates) do
                local classObj =
                    SafeCall(Vars.PropClassProvider, "GetPropClassFromPropId", propId) or
                    SafeCall(Vars.PropClassProvider, "GetFromPropId", propId) or
                    SafeCall(Vars.PropClassProvider, "FromPropId", propId) or
                    SafeCall(Vars.PropClassProvider, "GetPropClass", propId) or
                    SafeCall(Vars.PropClassProvider, "Get", propId)
                if classObj then Vars.PinkClass = classObj; return true end
            end
            for _,tKey in ipairs(PinkTKeyCandidates) do
                local classObj =
                    SafeCall(Vars.PropClassProvider, "GetPropClassFromTranslationKey", tKey) or
                    SafeCall(Vars.PropClassProvider, "GetFromTranslationKey", tKey) or
                    SafeCall(Vars.PropClassProvider, "FromTranslationKey", tKey)
                if classObj then Vars.PinkClass = classObj; return true end
            end
            return false
        end

        local function GetPropBinder(model)
            local ok,binder = pcall(function() return Vars.ClientBinders.Prop:Get(model) end)
            return (ok and binder) or nil
        end

        local function ModelWorldCFrame(model)
            local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
            return primary and primary.CFrame or nil
        end

        local function FindNewlyPlacedPink(boatModel, desiredWorld, timeoutSeconds)
            local deadline  = time() + (timeoutSeconds or 3)
            local bestModel = nil
            local bestDist  = math.huge
            repeat
                for _, childModel in ipairs(boatModel:GetChildren()) do
                    if childModel:IsA("Model") and GetPropBinder(childModel) then
                        local ln = string.lower(childModel.Name)
                        if string.find(ln,"pink") or string.find(ln,"gyro") or string.find(ln,"experimental") then
                            local cf = ModelWorldCFrame(childModel)
                            if cf then
                                local dist = (cf.Position - desiredWorld.Position).Magnitude
                                if dist < bestDist then bestModel, bestDist = childModel, dist end
                            end
                        end
                    end
                end
                if bestModel then return bestModel end
                RbxService.RunService.Heartbeat:Wait()
            until time() > deadline
            return nil
        end

        local function PlaceWithRetry(relative, boatModel)
            local ok = pcall(function() Vars.BoatAPI:PlacePropOnBoat(Vars.PinkClass, relative, boatModel) end)
            if ok then return true end
            task.wait(Vars.RetrySeconds or 0.7)
            local ok2 = pcall(function() Vars.BoatAPI:PlacePropOnBoat(Vars.PinkClass, relative, boatModel) end)
            return ok2 or false
        end

        local function EnsureOwnBoat()
            if Vars.OwnBoatModel and Vars.OwnBoatModel.Parent then return true end
            local existing = FindOwnBoat()
            if existing then Vars.OwnBoatModel = existing; return true end
            if not Vars.PinkClass then return false end

            local lp = RbxService.Players.LocalPlayer; if not lp then return false end
            local hrp = (lp.Character or lp.CharacterAdded:Wait()):WaitForChild("HumanoidRootPart")
            local pivot = hrp.CFrame * CFrame.new(0, (tonumber(Vars.SpawnYOffset) or 0), 0)
            local beforeSet = SnapshotOwnedBoats(lp.UserId)
            pcall(function() Vars.BoatAPI:PlaceNewBoat(Vars.PinkClass, pivot) end)
            local newBoat = WaitForNewOwnedBoat(lp.UserId, beforeSet, Vars.BoatSearchTimeoutSeconds or 12)
            if not newBoat then return false end

            local initialProp = FindNewlyPlacedPink(newBoat, pivot, 3)
            if initialProp then pcall(function() Vars.BoatAPI:SellProp(initialProp) end) end
            Vars.OwnBoatModel = newBoat
            return true
        end

        local function PlaceAndSellOnce()
            if not (Vars.OwnBoatModel and Vars.PinkClass) then return end
            local relQ = QuantizeCFrame(Vars.RelativeCFrame or CFrame.new(0, 1.6, 0))
            local desiredWorld = Vars.OwnBoatModel:GetPivot() * relQ
            if not PlaceWithRetry(relQ, Vars.OwnBoatModel) then return end
            local placed = FindNewlyPlacedPink(Vars.OwnBoatModel, desiredWorld, 3)
            if placed then pcall(function() Vars.BoatAPI:SellProp(placed) end) end
        end

        ----------------------------------------------------------------------
        -- Lifecycle
        ----------------------------------------------------------------------
        local function Start()
            if Vars.Running then return end
            Vars.Running = true
            EnsureNevermoreReady()
            if not Vars.PinkClass     then ResolvePinkClass() end
            if not Vars.OwnBoatModel  then Vars.OwnBoatModel = FindOwnBoat() end

            local thread = task.spawn(function()
                while Vars.Running do
                    if not Vars.PinkClass and not ResolvePinkClass() then
                        task.wait(Vars.ResolveTickSeconds or 0.25)
                    elseif not EnsureOwnBoat() then
                        task.wait(Vars.ResolveTickSeconds or 0.25)
                    else
                        PlaceAndSellOnce()
                        task.wait(Vars.IntervalSeconds or 2.0)
                    end
                end
            end)
            Vars.Maid:GiveTask(thread)
            Vars.Maid:GiveTask(function() Vars.Running = false end)
        end

        local function Stop()
            if not Vars.Running then return end
            Vars.Running = false
            Vars.Maid:DoCleaning()
        end

        ----------------------------------------------------------------------
        -- UI (shared groupbox: EXP -> "EXP Farm")
        ----------------------------------------------------------------------
        local toggleId = "AutoPropEXPToggle"
        local toggle = UI and UI.Toggles and UI.Toggles[toggleId]

        if not toggle then
            local gb = EnsureSharedGroupbox("EXP", "EXPFarm", "Left", "EXP Farm", "arrow-right-left")
            toggle = EnsureToggle(toggleId, "Prop EXP", "Turn Feature [ON/OFF].", false, gb)
        end

        if toggle and toggle.OnChanged then
            toggle:OnChanged(function(on) if on then Start() else Stop() end end)
        end

        return { Name = "PropEXP", Stop = Stop }
    end
end
