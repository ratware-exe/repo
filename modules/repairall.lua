
-- modules/repairall.lua
do
    return function(UI)
        -- Dependencies
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv  = (getgenv and getgenv()) or _G
        GlobalEnv.Signal = GlobalEnv.Signal or loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()
        local Maid       = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()


        local Variables = {
            Maids = { RepairAll = Maid.new() },
            RunFlag = false,
            Nevermore = nil,
            GetRemoteFunction = nil,
            BoatConstants = nil,
            ClientBinders = nil,
            BoatRemote = nil,
            TargetBoats = {},
            BoatIndex = 1,
            LastInvokeTime = 0,
            AccumulatedTime = 0,
            InvokeCooldown = 0.20,
        }

        local function EnsureNevermore()
            if not Variables.Nevermore then
                Variables.Nevermore = require(RbxService.ReplicatedStorage:WaitForChild("Nevermore"))
            end
            Variables.GetRemoteFunction = Variables.GetRemoteFunction or Variables.Nevermore("GetRemoteFunction")
            Variables.BoatConstants = Variables.BoatConstants or Variables.Nevermore("BoatConstants")
            Variables.ClientBinders = Variables.ClientBinders or Variables.Nevermore("ClientBinders")
            Variables.BoatRemote = Variables.BoatRemote or Variables.GetRemoteFunction(Variables.BoatConstants.API_REMOTE_FUNCTION)
        end

        local function BoatsFolder() return RbxService.Workspace:FindFirstChild("Boats") end
        local function OwnerUserId(model)
            local bind = Variables.ClientBinders and Variables.ClientBinders.Boat and Variables.ClientBinders.Boat:Get(model)
            if bind and bind.GetOwnerUserId then
                local ok,uid = pcall(function() return bind:GetOwnerUserId() end)
                if ok and uid then return uid end
            end
            return model:GetAttribute("OwnerUserId") or model:GetAttribute("BoatOwnerUserId")
        end
        local function RebuildTargets()
            Variables.TargetBoats = {}
            local boats = BoatsFolder(); if not boats then return end
            for _,m in ipairs(boats:GetChildren()) do
                if m:IsA("Model") then table.insert(Variables.TargetBoats, m) end
            end
        end
        local function OnHeartbeat(dt)
            Variables.AccumulatedTime = Variables.AccumulatedTime + dt
            if Variables.AccumulatedTime - Variables.LastInvokeTime < Variables.InvokeCooldown then return end
            Variables.LastInvokeTime = Variables.AccumulatedTime
            if #Variables.TargetBoats == 0 then RebuildTargets() end
            if #Variables.TargetBoats == 0 then return end
            Variables.BoatIndex = ((Variables.BoatIndex - 1) % #Variables.TargetBoats) + 1
            local m = Variables.TargetBoats[Variables.BoatIndex]
            pcall(function() Variables.BoatRemote:InvokeServer("RepairBoat", m) end)
        end

        local Module = {}
        function Module.Start()
            if Variables.RunFlag then return end
            Variables.RunFlag = true
            EnsureNevermore()
            RebuildTargets()
            local hb = RbxService.RunService.Heartbeat:Connect(OnHeartbeat)
            Variables.Maids.RepairAll:GiveTask(hb)
            Variables.Maids.RepairAll:GiveTask(function() Variables.RunFlag = false end)
        end
        function Module.Stop()
            if not Variables.RunFlag then return end
            Variables.RunFlag = false
            Variables.TargetBoats, Variables.BoatIndex = {}, 1
            Variables.LastInvokeTime, Variables.AccumulatedTime = 0, 0
            Variables.Maids.RepairAll:DoCleaning()
        end

        local box = UI.Tabs.EXP:AddRightGroupbox("Repair All", "wrench")
        box:AddToggle("RepairAllToggle", { Text = "Repair All", Default = False, Tooltip = "Invoke Repair on every boat in rotation." })
        UI.Toggles.RepairAllToggle:OnChanged(function(b) if b then Module.Start() else Module.Stop() end end)

        local ModuleContract = { Name = "RepairAll", Stop = Module.Stop }

        return ModuleContract
    end
end
