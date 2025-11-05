
-- modules/transfer_money.lua
do
    return function(UI)
        -- Dependencies
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv  = (getgenv and getgenv()) or _G
        GlobalEnv.Signal = GlobalEnv.Signal or loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()
        local Maid       = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()


        local Variables = {
            Maids = { TransferMoney = Maid.new() },
            RunFlag = false,
            Nevermore = nil,
            BoatApi = nil,
            PropClassProvider = nil,
            ClientBinders = nil,
            RelativePinkGyroCFrame = CFrame.new(0,2,0),
            SearchTimeoutSeconds = 3,
            PlaceThrottleSeconds = 0.20,
            PinkClass = nil,
            PlacedCount = 0,
            SoldCount = 0,
        }

        local function EnsureNevermore()
            if not Variables.Nevermore then
                Variables.Nevermore = require(RbxService.ReplicatedStorage:WaitForChild("Nevermore"))
            end
            Variables.BoatApi = Variables.BoatApi or Variables.Nevermore("BoatAPIServiceClient")
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
            Variables.ClientBinders = Variables.ClientBinders or Variables.Nevermore("ClientBinders")
        end

        local function QuantizeCFrame(cf)
            local function r(n) return math.floor((n or 0)*10000+0.5)/10000 end
            local x,y,z,r00,r01,r02,r10,r11,r12,r20,r21,r22 = cf:GetComponents()
            return CFrame.new(r(x),r(y),r(z),r(r00),r(r01),r(r02),r(r10),r(r11),r(r12),r(r20),r(r21),r(r22))
        end

        local function ResolvePinkClass(timeout)
            EnsureNevermore()
            local deadline = time() + (timeout or 8)
            repeat
                local pink =
                    (Variables.PropClassProvider and Variables.PropClassProvider.GetPropClass and Variables.PropClassProvider:GetPropClass("PinkGyro"))
                    or (Variables.PropClassProvider and Variables.PropClassProvider.Get and Variables.PropClassProvider:Get("PinkGyro"))
                if pink then return pink end
                task.wait()
            until time() > deadline
            return nil
        end

        local function BoatsFolder() return RbxService.Workspace:FindFirstChild("Boats") end
        local function FindTeammateBoat()
            local lp = RbxService.Players.LocalPlayer; if not lp then return nil end
            local team = lp.Team; if not team then return nil end
            local f = BoatsFolder(); if not f then return nil end
            for _,m in ipairs(f:GetChildren()) do
                if m:IsA("Model") then
                    local b = Variables.ClientBinders and Variables.ClientBinders.Boat and Variables.ClientBinders.Boat:Get(m)
                    local ok,owner = pcall(function() return b and b:GetOwner() end)
                    if ok and owner and owner ~= lp and owner.Team == team then
                        return m
                    end
                end
            end
            return nil
        end

        local function ModelWorldCFrame(model) local p; pcall(function() p=model:GetPivot() end); return p or CFrame.new() end
        local function FindPlacedPink(boatModel, desiredWorldCf)
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

        local Module = {}
        function Module.Start()
            if Variables.RunFlag then return end
            Variables.RunFlag = true
            EnsureNevermore()
            Variables.RelativePinkGyroCFrame = QuantizeCFrame(Variables.RelativePinkGyroCFrame)
            Variables.PinkClass = Variables.PinkClass or ResolvePinkClass(10)
            if not Variables.PinkClass then Variables.RunFlag=false; return end

            local worker = task.spawn(function()
                while Variables.RunFlag do
                    local m = FindTeammateBoat()
                    if not m then task.wait(0.5) else
                        local okPlace = pcall(function()
                            Variables.BoatApi:PlacePropOnBoat(Variables.PinkClass, Variables.RelativePinkGyroCFrame, m)
                        end)
                        if okPlace then Variables.PlacedCount = Variables.PlacedCount + 1 end

                        local worldTarget = m:GetPivot() * Variables.RelativePinkGyroCFrame
                        local found, t0 = nil, time()
                        repeat
                            found = FindPlacedPink(m, worldTarget)
                            if found then break end
                            RbxService.RunService.Heartbeat:Wait()
                        until time()-t0 > Variables.SearchTimeoutSeconds
                        if found then
                            pcall(function() Variables.BoatApi:SellProp(found) end)
                            Variables.SoldCount = Variables.SoldCount + 1
                        end
                        task.wait(Variables.PlaceThrottleSeconds)
                    end
                end
            end)
            Variables.Maids.TransferMoney:GiveTask(worker)
            Variables.Maids.TransferMoney:GiveTask(function() Variables.RunFlag = false end)
        end
        function Module.Stop()
            if not Variables.RunFlag then return end
            Variables.RunFlag = false
            Variables.Maids.TransferMoney:DoCleaning()
        end

        local box = UI.Tabs.Dupe:AddLeftGroupbox("Step #1", "arrow-right-left")
        box:AddToggle("TransferMoneyToggle", { Text = "Transfer Money", Default = false, Tooltip = "Place+Sell PinkGyro on teammate boat." })
        UI.Toggles.TransferMoneyToggle:OnChanged(function(b) if b then Module.Start() else Module.Stop() end end)

        local ModuleContract = { Name = "TransferMoney", Stop = Module.Stop }

        return ModuleContract
    end
end
