-- modules/pvpmode.lua
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

        local Vars = { Maid=Maid.new(), Run=false, LastSend=0, Interval=0.1, Nevermore=nil, GameMode=nil }
        local function EnsureNevermore()
            if not Vars.Nevermore then Vars.Nevermore = require(RbxService.ReplicatedStorage:WaitForChild("Nevermore")) end
            if not Vars.GameMode then Vars.GameMode = Vars.Nevermore("GameModeManager") end
        end
        local function VipCmd(s)
            local chat = RbxService.ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents")
            if chat and chat:FindFirstChild("SayMessageRequest") then chat.SayMessageRequest:FireServer(s,"All"); return end
            local chans = RbxService.TextChatService:FindFirstChild("TextChannels")
            local ch = chans and (chans:FindFirstChild("RBXGeneral") or chans:FindFirstChild("General"))
            if ch and ch.SendAsync then ch:SendAsync(s) end
        end
        local function CombatEnabled()
            EnsureNevermore()
            local M = Vars.GameMode; if not M then return false end
            local mode = M:GetMode("CombatEnabled"); return mode and mode.Enabled==true
        end
        local function OnHB()
            if not Vars.Run then return end
            if CombatEnabled() then return end
            if time() - Vars.LastSend >= Vars.Interval then Vars.LastSend=time(); VipCmd("/vipnextmode") end
        end

        local function Start()
            if Vars.Run then return end
            Vars.Run=true; Vars.LastSend=0; EnsureNevermore()
            local m=Vars.GameMode; if m then
                local mode = m:GetMode("CombatEnabled")
                if mode and mode.EnabledChanged then
                    Vars.Maid:GiveTask(mode.EnabledChanged:Connect(function() end))
                end
            end
            Vars.Maid:GiveTask(RbxService.RunService.Heartbeat:Connect(function() OnHB() end))
            Vars.Maid:GiveTask(function() Vars.Run=false end)
        end
        local function Stop() if not Vars.Run then return end Vars.Run=false; Vars.Maid:DoCleaning() end

        -- UI (EXP -> EXP Farm)
        local id="AutoPVPModeToggle"
        local tgl=UI and UI.Toggles and UI.Toggles[id]
        if not tgl then
            local gb=EnsureSharedGroupbox("EXP","EXPFarm","Left","EXP Farm","arrow-right-left")
            tgl=EnsureToggle(id,"PVP Mode","Turn Feature [ON/OFF].",false,gb)
        end
        if tgl and tgl.OnChanged then tgl:OnChanged(function(on) if on then Start() else Stop() end end) end

        return { Name="PVPMode", Stop=Stop }
    end
end
