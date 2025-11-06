-- modules/multiflame.lua
do
    return function(UI)
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv  = (getgenv and getgenv()) or _G
        GlobalEnv.Signal = GlobalEnv.Signal or loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()
        local Maid       = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local function EnsureSharedGroupbox(tabKey, boxKey, side, title, icon)
            if not UI or not UI.Tabs or not UI.Tabs[tabKey] then return nil end
            GlobalEnv.__WFYB_Groupboxes = GlobalEnv.__WFYB_Groupboxes or {}
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
            Maid = Maid.new(), Run=false,
            MaxTriggerDistance=800, MaxViewDistance=1200, LeewayDistance=40,
            FireRateHertz=15, PulseIntervalSeconds=2, BurstSize=100,
            OnlyFlame=true, Patched=false, Watched={},
            LastPulse=0, Accum=0, ClientBinders=nil, RoundRobin=1,
        }

        local function Loader() local m=RbxService.ReplicatedStorage:WaitForChild("Nevermore"); local ok,l=pcall(require,m); return ok and l end
        local function EnsureBinders()
            if Vars.ClientBinders then return Vars.ClientBinders end
            local L=Loader(); if not L then return nil end
            local ok,cb=pcall(function() return L("ClientBinders") end)
            if ok and cb then Vars.ClientBinders=cb; return cb end
            return nil
        end
        local function PatchConstants()
            local L=Loader(); if not L then return end
            local ok,c=pcall(function() return L("TriggerConstants") end)
            if not (ok and type(c)=="table") then return end
            c.MAX_TRIGGER_DISTANCE=Vars.MaxTriggerDistance
            c.MAX_VIEW_DISTANCE=Vars.MaxViewDistance
            c.LEEWAY_DISTANCE=Vars.LeewayDistance
        end
        local function PatchCooldowns()
            if Vars.Patched then return end
            local L=Loader(); if not L then return end
            local okS,svc=pcall(function() return L("TriggerCooldownService") end)
            if okS and svc then
                local oI,oM=svc.IsGlobalCoolingDown,svc.MarkGlobalCooldown
                svc.IsGlobalCoolingDown=function(...) return false end
                svc.MarkGlobalCooldown=function(...) end
                Vars.Maid:GiveTask(function() svc.IsGlobalCoolingDown=oI; svc.MarkGlobalCooldown=oM end)
            end
            local okH,helper=pcall(function() return L("CooldownHelper") end)
            if okH and helper and type(helper.getCooldown)=="function" then
                local og=helper.getCooldown; helper.getCooldown=function(...) return false end
                Vars.Maid:GiveTask(function() helper.getCooldown=og end)
            end
            Vars.Patched=true
        end
        local function GetTriggerBinder() local L=Loader(); if not L then return nil end; local ok,cb=pcall(function() return L("ClientBinders") end); return (ok and cb and cb.Trigger) or nil end
        local function Wrap(t) return rawget(t,"_obj") or rawget(t,"Instance") or rawget(t,"_instance") or (typeof(t.GetObject)=="function" and t:GetObject()) or nil end
        local function IsFlame(t)
            if Vars.OnlyFlame==false then return true end
            local a=Wrap(t); if not (a and a:IsA("Attachment")) then return false end
            local L=Loader(); if not L then return false end
            local okC,const=pcall(function() return L("TriggerConstants") end); if not (okC and const) then return false end
            local cb=EnsureBinders(); if not (cb and cb.Flamethrower) then return false end
            for _,ch in ipairs(a:GetChildren()) do
                if ch:IsA("ObjectValue") and ch.Name==const.TARGET_OBJECT_VALUE_NAME and ch.Value then
                    local ok,b=pcall(function() return cb.Flamethrower:Get(ch.Value) end)
                    if ok and b then return true end
                end
            end
            return false
        end
        local function NukeCooldown(n)
            if not n or not n.Parent or n.Name~="Cooldown" then return end
            task.defer(function() if n and n.Parent and n.Name=="Cooldown" then n.Name="CooldownDisabled"; pcall(function() n:SetAttribute("Disabled",true) end) end end)
        end
        local function Watch(t)
            if not IsFlame(t) then return end
            local a=Wrap(t); if not (a and a:IsA("Attachment")) or Vars.Watched[a] then return end
            for _,c in ipairs(a:GetChildren()) do if c.Name=="Cooldown" then NukeCooldown(c) end end
            local co=a.ChildAdded:Connect(function(nc) if nc and nc.Name=="Cooldown" then NukeCooldown(nc) end end)
            Vars.Watched[a]=co; Vars.Maid:GiveTask(co)
        end
        local function Refresh()
            local b=GetTriggerBinder(); if not b then return end
            local ok,list=pcall(function() return b:GetAll() end); if not (ok and type(list)=="table") then return end
            for _,t in ipairs(list) do Watch(t) end
        end
        local function Collect()
            local b=GetTriggerBinder(); if not b then return nil end
            local ok,list=pcall(function() return b:GetAll() end); if not (ok and type(list)=="table") then return nil end
            local out={} for _,t in ipairs(list) do if IsFlame(t) then table.insert(out,t) end end
            return out
        end

        local function OnHB(dt)
            PatchConstants(); PatchCooldowns()
            Vars.Accum += dt
            if Vars.Accum>=0.2 then Vars.Accum=0; Refresh() end
            if not Vars.Run then return end
            local interval = (Vars.PulseIntervalSeconds and Vars.PulseIntervalSeconds>0) and Vars.PulseIntervalSeconds or (1/math.max(1, Vars.FireRateHertz))
            if time() - Vars.LastPulse < interval then return end
            Vars.LastPulse = time()
            local list=Collect(); if not list or #list==0 then return end
            local count=#list
            local burst=math.clamp(tonumber(Vars.BurstSize) or count, 1, count)
            local start=tonumber(Vars.RoundRobin) or 1
            for i=0, burst-1 do
                local j=((start-1+i)%count)+1; local trg=list[j]
                if trg then pcall(function() trg:Activate() end) end
            end
            Vars.RoundRobin=((start-1+burst)%count)+1
        end

        local function Start()
            if Vars.Run then return end
            Vars.Run=true; Vars.LastPulse=0; Vars.Accum=0; Vars.RoundRobin=1
            PatchConstants(); PatchCooldowns(); Refresh()
            Vars.Maid:GiveTask(RbxService.RunService.Heartbeat:Connect(OnHB))
            Vars.Maid:GiveTask(function() Vars.Run=false end)
        end
        local function Stop()
            if not Vars.Run then return end
            Vars.Run=false; Vars.RoundRobin=1
            for a,c in pairs(Vars.Watched) do if typeof(c)=="RBXScriptConnection" then pcall(function() c:Disconnect() end) end Vars.Watched[a]=nil end
            Vars.Watched={}; Vars.Patched=false; Vars.LastPulse=0; Vars.Accum=0
            Vars.Maid:DoCleaning()
        end

        -- UI (EXP -> EXP Farm)
        local id="AutoMultiFlamethrowerToggle"
        local tgl = UI and UI.Toggles and UI.Toggles[id]
        if not tgl then
            local gb=EnsureSharedGroupbox("EXP","EXPFarm","Left","EXP Farm","arrow-right-left")
            tgl=EnsureToggle(id,"Multiple Flame","Turn Feature [ON/OFF].",false,gb)
        end
        if tgl and tgl.OnChanged then tgl:OnChanged(function(on) if on then Start() else Stop() end end) end

        return { Name="MultiFlame", Stop=Stop }
    end
end
