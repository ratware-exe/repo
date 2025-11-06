-- modules/crash_server.lua
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
        local function EnsureDropdown(id, text, values, groupbox)
            if UI and UI.Options and UI.Options[id] then return UI.Options[id] end
            if not groupbox then return nil end
            return groupbox:AddDropdown(id, { Text = text, Values = values or {}, Multi=false })
        end

        local Vars = {
            Maid=Maid.new(), Run=false,
            Nevermore=nil, SaveClient=nil,
            SpawnThrottle=5, StackGapY=10, BoatExtentsY=nil,
            SelectedBoatName=nil, SelectedBoatId=nil,
            BoatIdByName={}, BoatRawById={}, TargetPivot=nil,
            UiGate=nil, PendingValues=nil,
        }

        Vars.Nevermore  = require(RbxService.ReplicatedStorage:WaitForChild("Nevermore"))
        Vars.SaveClient = Vars.Nevermore("BoatSaveManagerClient")

        local function Boats() return RbxService.Workspace:FindFirstChild("Boats") end
        local function OwnerUserId(model)
            if not (model and model:IsA("Model")) then return nil end
            local attrs=model:GetAttributes(); for k,v in pairs(attrs) do local lk=string.lower(k); if lk=="owneruserid" or lk=="owner" then local n=tonumber(v); if n then return n end end end
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

        local function SnapshotMine(uid)
            -- FIX: one '='; comma-separated variables and values
            local snap, f = {}, Boats()
            if not f then return snap end
            for _, m in ipairs(f:GetChildren()) do
                if m:IsA("Model") and OwnerUserId(m) == uid then
                    snap[m] = true
                end
            end
            return snap
        end

        local function WaitNew(uid, before, timeout)
            local deadline=time()+(timeout or 12)
            while time()<deadline do
                local f=Boats()
                if f then
                    for _,m in ipairs(f:GetChildren()) do
                        if m:IsA("Model") and OwnerUserId(m)==uid and not before[m] then return m end
                    end
                end
                RbxService.RunService.Heartbeat:Wait()
            end
            return nil
        end
        local function PivotOffsetY(base, dy) local R=base-base.Position; local p=base.Position+Vector3.new(0,dy,0); return CFrame.new(p)*R end

        local function QueueValues(values)
            if Vars.UiGate then Vars.UiGate:Fire(values) else Vars.PendingValues = values end
        end
        local function RefreshDropdown()
            local promise = Vars.SaveClient and Vars.SaveClient:GetBoatSlots()
            if promise and typeof(promise)=="table" and promise.Then then
                promise
                :Then(function(slots)
                    Vars.BoatIdByName = {}; Vars.BoatRawById = {}; local values={}
                    if typeof(slots)=="table" then
                        for _,slot in ipairs(slots) do
                            local hasBoat = (slot and (slot.HasBoat==true or slot.hasBoat==true or slot.SaveExists==true))
                            if hasBoat then
                                local name = slot.SlotName or slot.Name or ("Slot " .. tostring(slot.SlotKey or slot.Id or "?"))
                                local id   = slot.SlotKey or slot.Id or slot.Key
                                if name and id ~= nil then
                                    Vars.BoatIdByName[name]=id; Vars.BoatRawById[id]=slot; table.insert(values, name)
                                end
                            end
                        end
                    end
                    QueueValues(values)
                end)
                :Catch(function() end)
            end
        end

        local function Start()
            if Vars.Run then return end
            Vars.Run=true
            if not Vars.SelectedBoatName then Vars.Run=false return end
            Vars.SelectedBoatId = Vars.BoatIdByName[Vars.SelectedBoatName]
            if Vars.SelectedBoatId==nil then Vars.Run=false return end

            local th = task.spawn(function()
                while Vars.Run do
                    local before=SnapshotMine(RbxService.Players.LocalPlayer.UserId)
                    local pivot
                    if Vars.TargetPivot then
                        local extra=(Vars.BoatExtentsY or 10)+(Vars.StackGapY or 2)
                        pivot = PivotOffsetY(Vars.TargetPivot, extra)
                    else
                        local lp=RbxService.Players.LocalPlayer
                        local hrp=(lp.Character or lp.CharacterAdded:Wait()):WaitForChild("HumanoidRootPart")
                        pivot = hrp.CFrame
                    end

                    pcall(function() Vars.SaveClient:LoadBoat(pivot, Vars.SelectedBoatId) end)

                    local newM = WaitNew(RbxService.Players.LocalPlayer.UserId, before, 12)
                    if newM then
                        Vars.TargetPivot = newM:GetPivot()
                        if not Vars.BoatExtentsY then local y = newM:GetExtentsSize().Y; if y and y>0 then Vars.BoatExtentsY=y end end
                    end
                    task.wait(Vars.SpawnThrottle)
                end
            end)
            Vars.Maid:GiveTask(th)
            Vars.Maid:GiveTask(function() Vars.Run=false end)
        end
        local function Stop() if not Vars.Run then return end Vars.Run=false; Vars.Maid:DoCleaning() end

        -- UI (Dupe -> Step #2)
        local gb = EnsureSharedGroupbox("Dupe","Step2","Right","Step #2","bomb")
        local dd = UI and UI.Options and UI.Options.BoatDropdown or EnsureDropdown("BoatDropdown","Save Slot:", {}, gb)
        local tglId="CrashServerToggle"
        local tgl = UI and UI.Toggles and UI.Toggles[tglId] or EnsureToggle(tglId,"Crash Server","Turn Feature [ON/OFF].",false,gb)

        -- Bridge dropdown values (live-refresh)
        Vars.UiGate = Vars.UiGate or Instance.new("BindableEvent")
        Vars.Maid:GiveTask(Vars.UiGate)
        Vars.Maid:GiveTask(Vars.UiGate.Event:Connect(function(values)
            if UI and UI.Options and UI.Options.BoatDropdown and UI.Options.BoatDropdown.SetValues then
                UI.Options.BoatDropdown:SetValues(values or {})
            end
        end))
        if Vars.PendingValues and UI and UI.Options and UI.Options.BoatDropdown and UI.Options.BoatDropdown.SetValues then
            UI.Options.BoatDropdown:SetValues(Vars.PendingValues); Vars.PendingValues=nil
        end

        if dd and dd.OnChanged then
            dd:OnChanged(function(name)
                Vars.SelectedBoatName = name
                Vars.SelectedBoatId   = Vars.BoatIdByName and Vars.BoatIdByName[name] or nil
            end)
        end

        -- Attach toggle
        if tgl and tgl.OnChanged then tgl:OnChanged(function(on) if on then Start() else Stop() end end) end

        -- Kick off first fetch (and re-fetch when dropdown opened, if library supports)
        task.defer(function() RefreshDropdown() end)

        return { Name="CrashServer", Stop=Stop }
    end
end
