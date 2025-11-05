
-- modules/prop_exp.lua
do
    return function(UI)
        -- Dependencies
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv  = (getgenv and getgenv()) or _G
        GlobalEnv.Signal = GlobalEnv.Signal or loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()
        local Maid       = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()


        -- State
        local Variables = {
            Maids = { PropEXP = Maid.new() },
            RunFlag = false,
            Nevermore = nil,
            BoatApi = nil,
            PropClassProvider = nil,
            ClientBinders = nil,
            RelativePinkGyroCFrame = CFrame.new(0, 2, 0),
            SearchTimeoutSeconds = 3,
            PlaceThrottleSeconds = 0.20,
            PinkClass = nil,
        }

        -- Helpers (ported from main-2.lua) 【prop: main-2.lua Prop EXP】

        local function EnsureNevermoreReady()
            if not Variables.Nevermore then
                Variables.Nevermore = require(RbxService.ReplicatedStorage:WaitForChild("Nevermore"))
            end
            if not Variables.BoatApi then
                Variables.BoatApi = Variables.Nevermore("BoatAPIServiceClient")
            end
            if not Variables.PropClassProvider then
                local okClient, providerClient = pcall(function()
                    return Variables.Nevermore("PropClassProviderClient")
                end)
                if okClient and providerClient then
                    Variables.PropClassProvider = providerClient
                else
                    Variables.PropClassProvider = Variables.Nevermore("PropClassProvider")
                end
            end
            if not Variables.ClientBinders then
                Variables.ClientBinders = Variables.Nevermore("ClientBinders")
            end
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

        local function GetBoatsFolder()
            return RbxService.Workspace:FindFirstChild("Boats")
        end

        local function BoatOwnerUserId(model)
            if not model then return nil end
            -- Prefer client binder if available
            local binder = Variables.ClientBinders and Variables.ClientBinders.Boat and Variables.ClientBinders.Boat:Get(model)
            if binder and binder.GetOwnerUserId then
                local ok,uid = pcall(function() return binder:GetOwnerUserId() end)
                if ok and uid then return uid end
            end
            -- Fallback: attribute or tag
            local attr = model:GetAttribute("OwnerUserId") or model:GetAttribute("BoatOwnerUserId")
            if attr then return tonumber(attr) end
            return nil
        end

        local function FindOwnBoatModel(timeout)
            local deadline = os.clock() + (timeout or 6)
            local lp = RbxService.Players.LocalPlayer
            if not lp then return nil end
            repeat
                local boats = GetBoatsFolder()
                if boats then
                    for _,m in ipairs(boats:GetChildren()) do
                        if m:IsA("Model") then
                            if BoatOwnerUserId(m) == lp.UserId then
                                -- Wait for binder to be ready
                                local endt = os.clock() + 6
                                repeat
                                    local b = Variables.ClientBinders and Variables.ClientBinders.Boat and Variables.ClientBinders.Boat:Get(m)
                                    if b then return m end
                                    RbxService.RunService.Heartbeat:Wait()
                                until os.clock() > endt
                                return m
                            end
                        end
                    end
                end
                RbxService.RunService.Heartbeat:Wait()
            until os.clock() > deadline
            return nil
        end

        local function SnapshotOwnedBoats(ownerUserId)
            local boats = GetBoatsFolder()
            local res = {}
            if boats then
                for _,m in ipairs(boats:GetChildren()) do
                    if m:IsA("Model") and BoatOwnerUserId(m) == ownerUserId then
                        res[m] = true
                    end
                end
            end
            return res
        end

        local function WaitForNewOwnedBoat(ownerUserId, beforeSnapshot, timeout)
            local deadline = os.clock() + (timeout or 6)
            repeat
                local boats = GetBoatsFolder()
                if boats then
                    for _,m in ipairs(boats:GetChildren()) do
                        if m:IsA("Model") and BoatOwnerUserId(m) == ownerUserId and not beforeSnapshot[m] then
                            return m
                        end
                    end
                end
                RbxService.RunService.Heartbeat:Wait()
            until os.clock() > deadline
            return nil
        end

        local function ResolvePinkClass(timeout)
            EnsureNevermoreReady()
            local deadline = os.clock() + (timeout or 8)
            repeat
                local pink = (Variables.PropClassProvider and Variables.PropClassProvider.GetPropClass and Variables.PropClassProvider:GetPropClass("PinkGyro"))
                    or (Variables.PropClassProvider and Variables.PropClassProvider.Get and Variables.PropClassProvider:Get("PinkGyro"))
                if pink then return pink end
                task.wait()
            until os.clock() > deadline
            return nil
        end

        local function ModelWorldCFrame(model)
            local p = nil
            pcall(function() p = model:GetPivot() end)
            return p or CFrame.new()
        end

        local function FindNewlyPlacedPink(boatModel, desiredWorldCf)
            if not boatModel then return nil end
            local ok, found = pcall(function()
                for _, child in ipairs(boatModel:GetDescendants()) do
                    if child.Name == "PinkGyro" or (child:IsA("Model") and child:FindFirstChildWhichIsA("BasePart")) then
                        local cf = ModelWorldCFrame(child)
                        if (cf and (cf.Position - desiredWorldCf.Position).Magnitude < 0.2) then
                            return child
                        end
                    end
                end
                return nil
            end)
            return ok and found or nil
        end

        local function PlaceWithRetry(boatModel, relativeCf, maxRetrySec)
            local deadline = os.clock() + (maxRetrySec or 3)
            local placed = false
            repeat
                local ok = pcall(function()
                    Variables.BoatApi:PlacePropOnBoat(Variables.PinkClass, relativeCf, boatModel)
                end)
                if ok then
                    placed = true
                    break
                end
                task.wait(0.1)
            until os.clock() > deadline
            return placed
        end

        local function EnsureOwnBoat()
            local lp = RbxService.Players.LocalPlayer
            if not lp then return nil end

            local myBoat = FindOwnBoatModel(2)
            if myBoat then return myBoat end

            -- Spawn a tiny boat via SaveClient if needed (optional best-effort)
            local nevermore = require(RbxService.ReplicatedStorage:WaitForChild("Nevermore"))
            local saveClient = nevermore("BoatSaveManagerClient")
            local before = SnapshotOwnedBoats(lp.UserId)
            pcall(function() saveClient:NewBoat(CFrame.new(lp.Character and lp.Character:WaitForChild("HumanoidRootPart").Position or Vector3.new())) end)
            local newBoat = WaitForNewOwnedBoat(lp.UserId, before, 6)
            return newBoat or FindOwnBoatModel(2)
        end

        local function PlaceAndSellOnce()
            EnsureNevermoreReady()
            Variables.PinkClass = Variables.PinkClass or ResolvePinkClass(10)
            if not Variables.PinkClass then return end

            local boat = EnsureOwnBoat()
            if not boat then return end

            local relative = QuantizeCFrame(Variables.RelativePinkGyroCFrame)
            local worldTarget = boat:GetPivot() * relative

            if PlaceWithRetry(boat, relative, Variables.SearchTimeoutSeconds) then
                local foundModel
                local t0 = time()
                repeat
                    foundModel = FindNewlyPlacedPink(boat, worldTarget)
                    if foundModel then break end
                    task.wait()
                until time() - t0 > Variables.SearchTimeoutSeconds
                if foundModel then
                    pcall(function() Variables.BoatApi:SellProp(foundModel) end)
                end
            end
        end

        local Module = {}
        function Module.Start()
            if Variables.RunFlag then return end
            Variables.RunFlag = true
            EnsureNevermoreReady()
            Variables.MaidThread = task.spawn(function()
                while Variables.RunFlag do
                    PlaceAndSellOnce()
                    task.wait(Variables.PlaceThrottleSeconds)
                end
            end)
            Variables.Maids.PropEXP:GiveTask(function() Variables.RunFlag = false end)
            Variables.Maids.PropEXP:GiveTask(Variables.MaidThread)
        end
        function Module.Stop()
            if not Variables.RunFlag then return end
            Variables.RunFlag = false
            Variables.Maids.PropEXP:DoCleaning()
        end

        -- UI
        local box = UI.Tabs.EXP:AddLeftGroupbox("Prop EXP", "arrow-right-left")
        box:AddToggle("PropEXPToggle", { Text = "Prop EXP", Default = false, Tooltip = "Place+Sell PinkGyro on your boat for EXP." })
        UI.Toggles.PropEXPToggle:OnChanged(function(b) if b then Module.Start() else Module.Stop() end end)

        local ModuleContract = { Name = "PropEXP", Stop = Module.Stop }

        return ModuleContract
    end
end
