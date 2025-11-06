-- modules/autoflame.lua
do
    return function(UI)
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv  = (getgenv and getgenv()) or _G
        GlobalEnv.Signal = GlobalEnv.Signal or loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()
        local Maid       = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local function EnsureSharedGroupbox(tabKey, boxKey, side, title, icon)
            if not UI or not UI.Tabs or not UI.Tabs[tabKey] then return nil end
            GlobalEnv.__WFYB_Groupboxes = GlobalEnv.__WFYB_Groupboxes or {}
            local GB = GlobalEnv.__WFYB_Groupboxes; GB[tabKey] = GB[tabKey] or {}
            if GB[tabKey][boxKey] and GB[tabKey][boxKey].__alive then return GB[tabKey][boxKey] end
            local tab = UI.Tabs[tabKey]
            local box = (side=="Right") and tab:AddRightGroupbox(title, icon) or tab:AddLeftGroupbox(title, icon)
            box.__alive=true; GB[tabKey][boxKey]=box; return box
        end
        local function EnsureToggle(id, text, tip, default, groupbox)
            if UI and UI.Toggles and UI.Toggles[id] then return UI.Toggles[id] end
            if not groupbox then return nil end
            return groupbox:AddToggle(id, { Text=text, Tooltip=tip, Default=default or false })
        end

        local Vars = {
            Maid = Maid.new(),
            Run  = false,
            MaxTriggerDistance = 800,
            MaxViewDistance    = 1200,
            LeewayDistance     = 40,
            FireRateHertz      = 15,
            Patched = false,
            Watched = {},
            LastPulse = 0,
            Accum = 0,
            ClientBinders = nil,
            LastTrigger  = nil,
        }

        local function Loader() local m=RbxService.ReplicatedStorage:WaitForChild("Nevermore"); local ok,l=pcall(require,m); return ok and l end
        local function EnsureBinders()
            if Vars.ClientBinders then return Vars.ClientBinders end
            local L=Loader(); if not L then return nil end
            local ok,cb=pcall(function() return L("ClientBinders") end)
            if ok and cb then Vars.ClientBinders=cb return cb end
            return nil
        end
        local function PatchConstants()
            local L=Loader(); if not L then return end
            local ok,c=pcall(function() return L("TriggerConstants") end)
            if not (ok and type(c)=="table") then return end
            c.MAX_TRIGGER_DISTANCE=Vars.MaxTriggerDistance
            c.MAX_VIEW_DISTANCE   =Vars.MaxViewDistance
            c.LEEWAY_DISTANCE     =Vars.LeewayDistance
        end
        local function PatchCooldowns()
            if Vars.Patched then return end
            local L=Loader(); if not L then return end
            local okS,svc=pcall(function() return L("TriggerCooldownService") end)
            if okS and svc then
                local origIs,origMk=svc.IsGlobalCoolingDown,svc.MarkGlobalCooldown
                svc.IsGlobalCoolingDown=function(...) return false end
                svc.MarkGlobalCooldown=function(...) end
                Vars.Maid:GiveTask(function() svc.IsGlobalCoolingDown=origIs; svc.MarkGlobalCooldown=origMk end)
            end
            local okH,helper=pcall(function() return L("CooldownHelper") end)
            if okH and helper and type(helper.getCooldown)=="function" then
                local orig=helper.getCooldown; helper.getCooldown=function(...) return false end
                Vars.Maid:GiveTask(function() helper.getCooldown=orig end)
            end
            Vars.Patched=true
        end
        local function GetTriggerBinder() local L=Loader(); if not L then return nil end; local ok,cb=pcall(function() return L("ClientBinders") end); return (ok and cb and cb.Trigger) or nil end
        local function WrappedAttachment(t) return rawget(t,"_obj") or rawget(t,"Instance") or rawget(t,"_instance") or (typeof(t.GetObject)=="function" and t:GetObject()) or nil end
        local function IsFlameTrigger(t)
            local a=WrappedAttachment(t); if not (a and a:IsA("Attachment")) then return false end
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
        local function DisableCooldownNode(node)
            if not node or not node.Parent or node.Name~="Cooldown" then return end
            task.defer(function()
                if node and node.Parent and node.Name=="Cooldown" then
                    node.Name="CooldownDisabled"; pcall(function() node:SetAttribute("Disabled",true) end)
                end
            end)
        end
        local function WatchAttachment(t)
            if not IsFlameTrigger(t) then return end
            local a=WrappedAttachment(t); if not (a and a:IsA("Attachment")) or Vars.Watched[a] then return end
            for _,c in ipairs(a:GetChildren()) do if c.Name=="Cooldown" then DisableCooldownNode(c) end end
            local conn=a.ChildAdded:Connect(function(nc) if nc and nc.Name=="Cooldown" then DisableCooldownNode(nc) end end)
            Vars.Watched[a]=conn; Vars.Maid:GiveTask(conn)
        end
        local function RefreshWatch()
            local bind=GetTriggerBinder(); if not bind then return end
            local ok,list=pcall(function() return bind:GetAll() end); if not (ok and type(list)=="table") then return end
            for _,t in ipairs(list) do WatchAttachment(t) end
        end
        local function SelectTrigger()
            local bind=GetTriggerBinder(); if not bind then return nil end
            local ok,list=pcall(function() return bind:GetAll() end); if not (ok and type(list)=="table") then return nil end
            local first,preferred=nil,nil
            for _,t in ipairs(list) do
                if IsFlameTrigger(t) then
                    first = first or t
                    local okP,isPref=pcall(function() return t.Preferred and t.Preferred.Value end)
                    if okP and isPref then preferred=t end
                    if Vars.LastTrigger==t then return t end
                end
            end
            return preferred or first
        end

        local function OnHB(dt)
            PatchConstants(); PatchCooldowns()
            Vars.Accum += dt
            if Vars.Accum >= 0.2 then Vars.Accum=0; RefreshWatch() end
            if not Vars.Run then return end
            local now=time(); local minInt = 1/math.max(1, Vars.FireRateHertz)
            if now - Vars.LastPulse < minInt then return end
            Vars.LastPulse = now
            local trg=SelectTrigger()
            if trg then Vars.LastTrigger=trg; pcall(function() trg:Activate() end) end
        end

        local function Start()
            if Vars.Run then return end
            Vars.Run=true; PatchConstants(); PatchCooldowns(); RefreshWatch()
            Vars.Maid:GiveTask(RbxService.RunService.Heartbeat:Connect(OnHB))
            Vars.Maid:GiveTask(function() Vars.Run=false end)
        end
        local function Stop()
            if not Vars.Run then return end
            Vars.Run=false
            for a,c in pairs(Vars.Watched) do if typeof(c)=="RBXScriptConnection" then pcall(function() c:Disconnect() end) end Vars.Watched[a]=nil end
            Vars.Maid:DoCleaning()
        end

        -- UI (EXP -> EXP Farm)
        local id="AutoFlamethrowerToggle"
        local tgl = UI and UI.Toggles and UI.Toggles[id]
        if not tgl then
            local gb = EnsureSharedGroupbox("EXP","EXPFarm","Left","EXP Farm","arrow-right-left")
            tgl = EnsureToggle(id, "Single Flame", "Turn Feature [ON/OFF].", false, gb)
        end
        if tgl and tgl.OnChanged then tgl:OnChanged(function(on) if on then Start() else Stop() end end) end

        return { Name="AutoFlame", Stop=Stop }
    end
end
