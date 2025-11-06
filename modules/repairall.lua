-- modules/repairall.lua
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
            Maid=Maid.new(), Run=false, Nevermore=nil, GetRF=nil, BoatConst=nil, ClientBinders=nil, BoatRF=nil,
            Rescan=0.1, Throttle=0.1, LastInvoke=0, Accum=0, Targets={}, Index=1
        }

        local function EnsureNevermore()
            if not Vars.Nevermore      then Vars.Nevermore      = require(RbxService.ReplicatedStorage:WaitForChild("Nevermore")) end
            if not Vars.GetRF          then Vars.GetRF          = Vars.Nevermore("GetRemoteFunction") end
            if not Vars.BoatConst      then Vars.BoatConst      = Vars.Nevermore("BoatConstants") end
            if not Vars.ClientBinders  then Vars.ClientBinders  = Vars.Nevermore("ClientBinders") end
            if not Vars.BoatRF         then Vars.BoatRF         = Vars.GetRF(Vars.BoatConst.API_REMOTE_FUNCTION) end
        end

        local function Boats() return RbxService.Workspace:FindFirstChild("Boats") end
        local function OwnerUserId(model)
            if not model or not model:IsA("Model") then return nil end
            local attrs=model:GetAttributes()
            for k,v in pairs(attrs) do local lk=string.lower(k); if lk=="owneruserid" or lk=="owner" then local n=tonumber(v); if n then return n end end end
            local data=model:FindFirstChild("BoatData"); if data then
                for _,ch in ipairs(data:GetChildren()) do
                    local ln=string.lower(ch.Name)
                    if ch:IsA("IntValue") and string.find(ln,"owner") then return ch.Value end
                    if ch:IsA("ObjectValue") and ln=="owner" then local p=ch.Value; if p and p.UserId then return p.UserId end end
                    if ch:IsA("StringValue") and string.find(ln,"owner") then local n=tonumber(ch.Value); if n then return n end end
                end
            end
            for _,d in ipairs(model:GetDescendants()) do if d:IsA("IntValue") and (d.Name=="Owner" or d.Name=="OwnerUserId") then return d.Value end end
            return nil
        end
        local function IsMineOrTeam(model)
            local lp = RbxService.Players.LocalPlayer; if not lp then return false end
            local id=OwnerUserId(model); if not id then return false end
            if id==lp.UserId then return true end
            local owner = RbxService.Players:GetPlayerByUserId(id)
            return owner and lp.Team and owner.Team==lp.Team
        end
        local function RebuildTargets()
            local f=Boats(); local list={}
            if f then for _,m in ipairs(f:GetChildren()) do if m:IsA("Model") and IsMineOrTeam(m) then table.insert(list,m) end end end
            Vars.Targets=list; if Vars.Index>#Vars.Targets then Vars.Index=1 end
        end

        local function TryRepair(model)
            if not (Vars.BoatRF and model) then return end
            pcall(function() Vars.BoatRF:InvokeServer("RepairBoat", model) end)
        end

        local function OnHB(dt)
            Vars.Accum += dt
            if Vars.Accum >= Vars.Rescan then Vars.Accum=0; RebuildTargets() end
            if not Vars.Run then return end
            local list=Vars.Targets; if not list or #list==0 then return end
            if time() - Vars.LastInvoke < Vars.Throttle then return end
            Vars.LastInvoke = time()
            local i=Vars.Index; if i<1 then i=1 end; if i>#list then i=1 end
            local m=list[i]; Vars.Index=(i % #list) + 1
            if m and m.Parent then TryRepair(m) end
        end

        local function Start()
            if Vars.Run then return end
            Vars.Run=true; Vars.LastInvoke=0; Vars.Accum=0; Vars.Index=1
            EnsureNevermore(); RebuildTargets()
            Vars.Maid:GiveTask(RbxService.RunService.Heartbeat:Connect(OnHB))
            Vars.Maid:GiveTask(function() Vars.Run=false end)
        end
        local function Stop()
            if not Vars.Run then return end
            Vars.Run=false; Vars.Targets={}; Vars.Index=1; Vars.LastInvoke=0; Vars.Accum=0
            Vars.Maid:DoCleaning()
        end

        -- UI (EXP -> EXP Farm)
        local id="AutoRepairAllToggle"
        local tgl = UI and UI.Toggles and UI.Toggles[id]
        if not tgl then
            local gb=EnsureSharedGroupbox("EXP","EXPFarm","Left","EXP Farm","arrow-right-left")
            tgl=EnsureToggle(id,"Repair All","Turn Feature [ON/OFF].",false,gb)
        end
        if tgl and tgl.OnChanged then tgl:OnChanged(function(on) if on then Start() else Stop() end end) end

        return { Name="RepairAll", Stop=Stop }
    end
end
