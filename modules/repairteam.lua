
-- modules/repairteam.lua
do
    return function(UI)
        -- Dependencies
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv  = (getgenv and getgenv()) or _G
        GlobalEnv.Signal = GlobalEnv.Signal or loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()
        local Maid       = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()


        local Variables = {
            Maids = { RepairTeam = Maid.new() },
            RunFlag = false,
            Nevermore = nil,
            GetRemoteFunction = nil,
            BoatConstants = nil,
            ClientBinders = nil,
            BoatRemote = nil,
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
        local function FindTeammateBoat()
            local lp = RbxService.Players.LocalPlayer; if not lp then return nil end
            local team = lp.Team; if not team then return nil end
            local folder = BoatsFolder(); if not folder then return nil end
            for _,m in ipairs(folder:GetChildren()) do
                if m:IsA("Model") then
                    local b = Variables.ClientBinders and Variables.ClientBinders.Boat and Variables.ClientBinders.Boat:Get(m)
                    local ok,owner = pcall(function() return b and b:GetOwner() end)
                    if ok and owner and owner.Team == team and owner ~= lp then
                        return m
                    end
                end
            end
            return nil
        end
        local Module = {}
        function Module.Start()
            if Variables.RunFlag then return end
            Variables.RunFlag = true
            EnsureNevermore()
            local hb = RbxService.RunService.Heartbeat:Connect(function()
                local m = FindTeammateBoat()
                if m then pcall(function() Variables.BoatRemote:InvokeServer("RepairBoat", m) end) end
            end)
            Variables.Maids.RepairTeam:GiveTask(hb)
            Variables.Maids.RepairTeam:GiveTask(function() Variables.RunFlag = false end)
        end
        function Module.Stop()
            if not Variables.RunFlag then return end
            Variables.RunFlag = false
            Variables.Maids.RepairTeam:DoCleaning()
        end

        local box = UI.Tabs.EXP:AddRightGroupbox("Repair Team", "wrench")
        box:AddToggle("RepairTeamToggle", { Text = "Repair Team", Default = false, Tooltip = "Invoke Repair on a teammate boat." })
        UI.Toggles.RepairTeamToggle:OnChanged(function(b) if b then Module.Start() else Module.Stop() end end)

        local ModuleContract = { Name = "RepairTeam", Stop = Module.Stop }

        return ModuleContract
    end
end
