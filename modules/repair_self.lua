
-- modules/repair_self.lua
do
    return function(UI)
        -- Dependencies
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv  = (getgenv and getgenv()) or _G
        GlobalEnv.Signal = GlobalEnv.Signal or loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()
        local Maid       = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()


        local Variables = {
            Maids = { RepairSelf = Maid.new() },
            RunFlag = false,
            Nevermore = nil,
            GetRemoteFunction = nil,
            BoatConstants = nil,
            ClientBinders = nil,
            BoatRemote = nil,
            BoatSearchTimeoutSeconds = 6,
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
        local function WaitBinder(model, tmo)
            local deadline = os.clock() + (tmo or 6)
            repeat
                local b = Variables.ClientBinders and Variables.ClientBinders.Boat and Variables.ClientBinders.Boat:Get(model)
                if b then return b end
                RbxService.RunService.Heartbeat:Wait()
            until os.clock() > deadline
            return nil
        end
        local function FindOwnBoatModel(tmo)
            local lp = RbxService.Players.LocalPlayer; if not lp then return nil end
            local deadline = os.clock() + (tmo or Variables.BoatSearchTimeoutSeconds)
            repeat
                local folder = BoatsFolder()
                if folder then
                    for _,m in ipairs(folder:GetChildren()) do
                        if m:IsA("Model") then
                            local b = Variables.ClientBinders and Variables.ClientBinders.Boat and Variables.ClientBinders.Boat:Get(m)
                            local ok,uid = pcall(function() return b and b:GetOwnerUserId() end)
                            if ok and uid == lp.UserId then return m end
                        end
                    end
                end
                RbxService.RunService.Heartbeat:Wait()
            until os.clock() > deadline
            return nil
        end
        local Module = {}
        function Module.Start()
            if Variables.RunFlag then return end
            Variables.RunFlag = true
            EnsureNevermore()
            local hb = RbxService.RunService.Heartbeat:Connect(function()
                local m = FindOwnBoatModel(2)
                if m then pcall(function() Variables.BoatRemote:InvokeServer("RepairBoat", m) end) end
            end)
            Variables.Maids.RepairSelf:GiveTask(hb)
            Variables.Maids.RepairSelf:GiveTask(function() Variables.RunFlag = false end)
        end
        function Module.Stop()
            if not Variables.RunFlag then return end
            Variables.RunFlag = false
            Variables.Maids.RepairSelf:DoCleaning()
        end

        local box = UI.Tabs.EXP:AddRightGroupbox("Repair Self", "wrench")
        box:AddToggle("RepairSelfToggle", { Text = "Repair Self", Default = false, Tooltip = "Invoke Repair on your own boat." })
        UI.Toggles.RepairSelfToggle:OnChanged(function(b) if b then Module.Start() else Module.Stop() end end)

        local ModuleContract = { Name = "RepairSelf", Stop = Module.Stop }

        return ModuleContract
    end
end
