-- modules/blockpopup.lua
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

        local Vars = { Maid=Maid.new(), Run=false, Nevermore=nil, Patched=false, PatchedTargets={} }
        local function EnsureNevermore()
            if not Vars.Nevermore then Vars.Nevermore = require(RbxService.ReplicatedStorage:WaitForChild("Nevermore")) end
        end
        local function TryLoad(name)
            EnsureNevermore()
            local ok,m = pcall(function() return Vars.Nevermore(name) end)
            return ok and m or nil
        end
        local function Patch(moduleTable, key)
            if not (moduleTable and type(moduleTable)=="table") then return false end
            local orig = moduleTable[key]; if type(orig)~="function" then return false end
            table.insert(Vars.PatchedTargets, {M=moduleTable,K=key,O=orig})
            moduleTable[key]=function(...) end
            Vars.Maid:GiveTask(function() if moduleTable and moduleTable[key]~=nil then moduleTable[key]=orig end end)
            return true
        end
        local function ApplyPatches()
            if Vars.Patched then return end
            local exp = TryLoad("ExperienceChangeNotifier") ; if exp then Patch(exp, "_showExperienceGain") end
            local lvl = TryLoad("LevelUpNotifier")         ; if lvl then Patch(lvl, "_showLevelUpNotification") end
            local cash= TryLoad("MoneyChangeNotifier")     ; if cash then Patch(cash,"_showMoneyGain"); Patch(cash,"_showMoneyLoss") end
            local bar = TryLoad("LevelBar")                ; if bar then
                Patch(bar,"_updateValue"); Patch(bar,"_handleExperienceValueChanged"); Patch(bar,"_animateUpToLevel"); Patch(bar,"_animateLevelsImprove")
            end
            local stat= TryLoad("StatRow")                 ; if stat then Patch(stat,"_startUpdate"); Patch(stat,"_update") end
            Vars.Patched=true; Vars.Maid:GiveTask(function() Vars.Patched=false; Vars.PatchedTargets={} end)
        end

        local function Start()
            if Vars.Run then return end
            Vars.Run=true; EnsureNevermore(); ApplyPatches()
            Vars.Maid:GiveTask(function() Vars.Run=false end)
        end
        local function Stop()
            if not Vars.Run then return end
            Vars.Run=false
            for i=#Vars.PatchedTargets,1,-1 do local e=Vars.PatchedTargets[i]; if e and e.M and e.K and e.O then pcall(function() e.M[e.K]=e.O end) end; Vars.PatchedTargets[i]=nil end
            Vars.Patched=false
            Vars.Maid:DoCleaning()
        end

        -- UI (EXP -> EXP Farm)
        local id="AutoPopupToggle"
        local tgl=UI and UI.Toggles and UI.Toggles[id]
        if not tgl then
            local gb=EnsureSharedGroupbox("EXP","EXPFarm","Left","EXP Farm","arrow-right-left")
            tgl=EnsureToggle(id,"Remove Popup","Turn Feature [ON/OFF].",false,gb)
        end
        if tgl and tgl.OnChanged then tgl:OnChanged(function(on) if on then Start() else Stop() end end) end

        return { Name="BlockPopup", Stop=Stop }
    end
end
