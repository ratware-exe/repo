-- modules/repairself.lua
do
    return function(UI)
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv  = (getgenv and getgenv()) or _G
        GlobalEnv.Signal = GlobalEnv.Signal or loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()
        local Maid       = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local function EnsureSharedGroupbox(tabKey, boxKey, side, title, icon)
            if not UI or not UI.Tabs or not UI.Tabs[tabKey] then return nil end
            GlobalEnv.__WFYB_Groupboxes=GlobalEnv.__WFYB_Groupboxes or {}
            local GB=GlobalEnv.__WFYB_Groupboxes; GB[tabKey]=GB[tabKey] or {}
            if GB[tabKey][boxKey] and GB[tabKey][boxKey].__alive then return GB[tabKey][boxKey] end
            local tab=UI.Tabs[tabKey]
            local box=(side=="Right") and tab:AddRightGroupbox(title,icon) or tab:AddLeftGroupbox(title,icon)
            box.__alive=true; GB[tabKey][boxKey]=box; return box
        end
        local function EnsureToggle(id, text, tip, default, groupbox)
            if UI and UI.Toggles and UI.Toggles[id] then return UI.Toggles[id] end
            if not groupbox then return nil end
            return groupbox:AddToggle(id, { Text=text, Tooltip=tip, Default=default or false })
        end

        local Vars = {
            Maid=Maid.new(), Run=false,
            Nevermore=nil, GetRF=nil, BoatConst=nil, ClientBinders=nil, BoatRF=nil,
            BoatSearchTimeout=12, InvokeThrottle=0.1, Rescan=0.1,
            LastInvoke=0, Accum=0, OwnBoat=nil,
        }

        local function EnsureNevermore()
            if not Vars.Nevermore      then Vars.Nevermore      = require(RbxService.ReplicatedStorage:WaitForChild("Nevermore")) end
            if not Vars.GetRF          then Vars.GetRF          = Vars.Nevermore("GetRemoteFunction") end
            if not Vars.BoatConst      then Vars.BoatConst      = Vars.Nevermore("BoatConstants") end
            if not Vars.ClientBinders  then Vars.ClientBinders  = Vars.Nevermore("ClientBinders") end
            if not Vars.BoatRF         then Vars.BoatRF         = Vars.GetRF(Vars.BoatConst.API_REMOTE_FUNCTION) end
        end
        local function Boats() return RbxService.Workspace:FindFirstChild("Boats") end
        local function FindOwn(timeout)
            local deadline = os.clock() + (timeout or Vars.BoatSearchTimeout)
            repeat
                local folder=Boats()
                if folder then
                    for _,m in ipairs(folder:GetChildren()) do
                        if m:IsA("Model") then
                            local b = (Vars.ClientBinders and Vars.ClientBinders.Boat and Vars.ClientBinders.Boat:Get(m))
                            if not b then
                                local st=os.clock()+1
                                repeat
                                    b = (Vars.ClientBinders and Vars.ClientBinders.Boat and Vars.ClientBinders.Boat:Get(m))
                                    if b then break end
                                    RbxService.RunService.Heartbeat:Wait()
                                until os.clock()>st
                            end
                            if b and b.CanModify and b:CanModify(RbxService.Players.LocalPlayer) then
                                return m, b
                            end
                        end
                    end
                end
                RbxService.RunService.Heartbeat:Wait()
            until os.clock()>deadline
            return nil,nil
        end

        local function TryRepair(model)
            if not (Vars.BoatRF and model) then return end
            pcall(function() Vars.BoatRF:InvokeServer("RepairBoat", model) end)
        end

        local function OnHB(dt)
            if not Vars.Run then return end
            Vars.Accum += dt
            if Vars.Accum >= Vars.Rescan then
                Vars.Accum=0
                if (not Vars.OwnBoat) or (not Vars.OwnBoat.Parent) then
                    Vars.OwnBoat = (FindOwn(1.0))
                end
            end
            if not Vars.OwnBoat then return end
            if time() - Vars.LastInvoke >= Vars.InvokeThrottle then
                Vars.LastInvoke = time(); TryRepair(Vars.OwnBoat)
            end
        end

        local function Start()
            if Vars.Run then return end
            Vars.Run=true
            EnsureNevermore()
            Vars.OwnBoat = (FindOwn(Vars.BoatSearchTimeout))
            Vars.Maid:GiveTask(RbxService.RunService.Heartbeat:Connect(OnHB))
            Vars.Maid:GiveTask(function() Vars.Run=false end)
        end
        local function Stop()
            if not Vars.Run then return end
            Vars.Run=false; Vars.OwnBoat=nil
            Vars.Maid:DoCleaning()
        end

        -- UI (EXP -> EXP Farm)
        local id="AutoRepairSelfToggle"
        local tgl=UI and UI.Toggles and UI.Toggles[id]
        if not tgl then
            local gb=EnsureSharedGroupbox("EXP","EXPFarm","Left","EXP Farm","arrow-right-left")
            tgl=EnsureToggle(id,"Repair Self","Turn Feature [ON/OFF].",false,gb)
        end
        if tgl and tgl.OnChanged then tgl:OnChanged(function(on) if on then Start() else Stop() end end) end

        return { Name="RepairSelf", Stop=Stop }
    end
end
