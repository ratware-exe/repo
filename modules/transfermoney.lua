-- modules/transfermoney.lua
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
            Nevermore=require(RbxService.ReplicatedStorage:WaitForChild("Nevermore")),
            BoatApi=nil, PropClassProvider=nil, ClientBinders=nil, PinkClass=nil,
            Rel= CFrame.new(0,1.6,0),
            PlaceThrottle=0, SearchTimeout=0,
            Placed=0, Sold=0,
        }
        Vars.BoatApi           = Vars.Nevermore("BoatAPIServiceClient")
        Vars.PropClassProvider = Vars.Nevermore("PropClassProviderClient")
        Vars.ClientBinders     = Vars.Nevermore("ClientBinders")

        local function SafeCall(t,m,...) local f=t and t[m]; if type(f)~="function" then return nil end
            local a={...}; local ok,r=pcall(function() return f(t,table.unpack(a)) end); if ok and r~=nil then return r end
            ok,r=pcall(function() return f(table.unpack(a)) end); if ok and r~=nil then return r end; return nil end

        local function Round4(n) return math.floor((n or 0)*10000+0.5)/10000 end
        local function QuantCF(cf) local x,y,z,r00,r01,r02,r10,r11,r12,r20,r21,r22=cf:GetComponents()
            return CFrame.new(Round4(x),Round4(y),Round4(z),Round4(r00),Round4(r01),Round4(r02),Round4(r10),Round4(r11),Round4(r12),Round4(r20),Round4(r21),Round4(r22)) end

        local function Boats() return RbxService.Workspace:FindFirstChild("Boats") end
        local function OwnerUserId(m)
            if not (m and m:IsA("Model")) then return nil end
            local attrs=m:GetAttributes(); for k,v in pairs(attrs) do local lk=string.lower(k); if lk=="owneruserid" or lk=="owner" then local n=tonumber(v); if n then return n end end end
            local data=m:FindFirstChild("BoatData"); if data then
                for _,ch in ipairs(data:GetChildren()) do local ln=string.lower(ch.Name)
                    if ch:IsA("IntValue") and string.find(ln,"owner") then return ch.Value end
                    if ch:IsA("ObjectValue") and ln=="owner" then local p=ch.Value; if p and p.UserId then return p.UserId end end
                    if ch:IsA("StringValue") and string.find(ln,"owner") then local n=tonumber(ch.Value); if n then return n end end
                end
            end
            for _,d in ipairs(m:GetDescendants()) do if d:IsA("IntValue") and (d.Name=="Owner" or d.Name=="OwnerUserId") then return d.Value end end
            return nil
        end

        local function PropBinder(model) local ok,b=pcall(function() return Vars.ClientBinders.Prop:Get(model) end); return (ok and b) or nil end
        local function WorldCF(model) local p=model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart",true); return p and p.CFrame or nil end

        local function FindTeamBoat()
            local f=Boats(); if not f then return nil end
            local lp=RbxService.Players.LocalPlayer; if not (lp and lp.Team) then return nil end
            for _,c in ipairs(f:GetChildren()) do
                if c:IsA("Model") then
                    local id=OwnerUserId(c)
                    if id and id ~= lp.UserId then local p=RbxService.Players:GetPlayerByUserId(id)
                        if p and p.Team==lp.Team then return c end end
                end
            end
            return nil
        end
        local function FindPlacedPink(boat, desired)
            local best,bestD=nil,math.huge
            for _,ch in ipairs(boat:GetChildren()) do
                if ch:IsA("Model") and ch.Name=="PinkGyro" and PropBinder(ch) then
                    local cf=WorldCF(ch)
                    if cf then local d=(cf.Position-desired.Position).Magnitude; if d<bestD then best,bestD=ch,d end end
                end
            end
            return best
        end
        local function WaitPinkClass(timeout)
            local deadline=time()+(timeout or 10)
            repeat
                local k = SafeCall(Vars.PropClassProvider,"GetPropClassFromPropId","PinkGyro")
                    or SafeCall(Vars.PropClassProvider,"GetFromPropId","PinkGyro")
                    or SafeCall(Vars.PropClassProvider,"FromPropId","PinkGyro")
                    or SafeCall(Vars.PropClassProvider,"GetPropClassFromTranslationKey","props.pinkGyro")
                    or SafeCall(Vars.PropClassProvider,"GetPropClass","PinkGyro")
                    or SafeCall(Vars.PropClassProvider,"Get","PinkGyro")
                if k then return k end
                RbxService.RunService.Heartbeat:Wait()
            until time()>deadline
            return nil
        end

        Vars.Rel = QuantCF(Vars.Rel)
        Vars.PinkClass = Vars.PinkClass or WaitPinkClass(10)

        local function Start()
            if Vars.Run then return end
            if not Vars.PinkClass then return end
            Vars.Run=true
            local th = task.spawn(function()
                while Vars.Run do
                    local boat=FindTeamBoat()
                    if not boat then task.wait(0.5) else
                        local ok=pcall(function() Vars.BoatApi:PlacePropOnBoat(Vars.PinkClass, Vars.Rel, boat) end)
                        if ok then Vars.Placed+=1 end
                        local desired=boat:GetPivot() * Vars.Rel
                        local found=nil; local t0=time()
                        repeat found=FindPlacedPink(boat, desired); if found then break end; RbxService.RunService.Heartbeat:Wait() until time()-t0 > Vars.SearchTimeout
                        if found then pcall(function() Vars.BoatApi:SellProp(found) end); Vars.Sold+=1 end
                        task.wait(Vars.PlaceThrottle)
                    end
                end
            end)
            Vars.Maid:GiveTask(th)
            Vars.Maid:GiveTask(function() Vars.Run=false end)
        end
        local function Stop() if not Vars.Run then return end Vars.Run=false; Vars.Maid:DoCleaning() end

        -- UI (Dupe -> Step #1)
        local id="TransferMoneyToggle"
        local tgl = UI and UI.Toggles and UI.Toggles[id]
        if not tgl then
            local gb=EnsureSharedGroupbox("Dupe","Step1","Left","Step #1","arrow-right-left")
            tgl = EnsureToggle(id,"Transfer Money","Turn Feature [ON/OFF].",false,gb)
            -- KeyPicker so keyboard toggle mirrors UI toggle
            if tgl and tgl.AddKeyPicker and (not UI.Options or not UI.Options.TransferMoneyKeybind) then
                tgl:AddKeyPicker("TransferMoneyKeybind", { Text="Transfer Money", SyncToggleState=true, Mode="Toggle", NoUI=false })
            end
        end
        if tgl and tgl.OnChanged then tgl:OnChanged(function(on) if on then Start() else Stop() end end) end

        return { Name="TransferMoney", Stop=Stop }
    end
end
