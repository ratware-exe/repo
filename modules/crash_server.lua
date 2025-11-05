
-- modules/crash_server.lua
do
    return function(UI)
        -- Dependencies
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv  = (getgenv and getgenv()) or _G
        GlobalEnv.Signal = GlobalEnv.Signal or loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()
        local Maid       = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()


        local Variables = {
            Maids = { CrashServer = Maid.new(), CrashServerUiBridge = Maid.new() },
            RunFlag = false,
            Nevermore = nil,
            SaveClient = nil, -- BoatSaveManagerClient
            TargetWorldPivot = nil,
            BoatExtentsY = nil,
            StackGapY = 2,
            SelectedBoatName = nil,
            SelectedBoatId = nil,
            BoatIdByName = {},
            BoatRawById = {},
            PendingDropdownValues = nil,
        }

        local function Ensure()
            if not Variables.Nevermore then
                Variables.Nevermore = require(RbxService.ReplicatedStorage:WaitForChild("Nevermore"))
            end
            Variables.SaveClient = Variables.SaveClient or Variables.Nevermore("BoatSaveManagerClient")
        end

        local function BoatsFolder() return RbxService.Workspace:FindFirstChild("Boats") end
        local function OwnerUserId(model)
            local attr = model:GetAttribute("OwnerUserId") or model:GetAttribute("BoatOwnerUserId")
            return attr
        end

        local function SnapshotOwnedBoats(ownerUserId)
            local res = {}
            local f = BoatsFolder(); if not f then return res end
            for _,m in ipairs(f:GetChildren()) do
                if m:IsA("Model") and OwnerUserId(m) == ownerUserId then res[m]=true end
            end
            return res
        end
        local function WaitForNewOwnedBoat(ownerUserId, before, timeout)
            local deadline = os.clock() + (timeout or 6)
            repeat
                local f = BoatsFolder(); if not f then RbxService.RunService.Heartbeat:Wait() goto continue end
                for _,m in ipairs(f:GetChildren()) do
                    if m:IsA("Model") and OwnerUserId(m) == ownerUserId and not before[m] then return m end
                end
                ::continue::
                RbxService.RunService.Heartbeat:Wait()
            until os.clock() > deadline
            return nil
        end

        local function PivotWithWorldYOffset(cf, up)
            return cf * CFrame.new(0, up or 0, 0)
        end

        -- Dropdown refresh (ported) 【Crash Server UI bridge】
        local function QueueDropdownValues(values)
            Variables.PendingDropdownValues = values
            local opt = UI.Options and UI.Options.BoatDropdown
            if opt and opt.SetValues then
                opt:SetValues(values)
                Variables.PendingDropdownValues = nil
            end
        end

        local function RefreshBoatSaveDropdown()
            Ensure()
            local promise = Variables.SaveClient and Variables.SaveClient:GetBoatSlots()
            if promise and typeof(promise) == "table" and promise.Then then
                promise:Then(function(slots)
                    Variables.BoatIdByName, Variables.BoatRawById = {}, {}
                    local values = {}
                    if typeof(slots) == "table" then
                        for _, slot in ipairs(slots) do
                            local hasBoat = (slot and (slot.HasBoat == true or slot.hasBoat == true or slot.SaveExists == true))
                            if hasBoat then
                                local name = slot.SlotName or slot.Name or ("Slot " .. tostring(slot.SlotKey or slot.Id or "?"))
                                local id   = slot.SlotKey or slot.Id or slot.Key
                                if name and id ~= nil then
                                    Variables.BoatIdByName[name] = id
                                    Variables.BoatRawById[id]    = slot
                                    table.insert(values, name)
                                end
                            end
                        end
                    end
                    QueueDropdownValues(values)
                end):Catch(function() end)
            end
        end

        local function AttachBoatDropdownLiveRefresh()
            local opt = UI.Options and UI.Options.BoatDropdown
            if not opt then return end
            local function refresh() RefreshBoatSaveDropdown() end
            local attached=false
            pcall(function() if type(opt.OnMenuOpened)=="function" then opt:OnMenuOpened(refresh); attached=true end end)
            pcall(function() if (not attached) and type(opt.OnOpen)=="function" then opt:OnOpen(refresh); attached=true end end)
            if not attached then
                local methods = { "OpenMenu","Toggle","ToggleMenu","ShowDropdown","Show","Open","SetOpen","_Open","_Toggle","_Show","SetVisible","SetListVisible" }
                for _,m in ipairs(methods) do
                    local fn = opt[m]
                    if type(fn)=="function" then
                        opt[m] = function(self, ...) refresh(); return fn(self, ...) end
                        attached=true; break
                    end
                end
            end
            if not attached then
                local probableRoots = {}
                for k,v in pairs(opt) do if typeof(v)=="Instance" then table.insert(probableRoots,v) end end
                for _,root in ipairs(probableRoots) do
                    local menu = root:FindFirstChild("Options", true) or root:FindFirstChild("Menu", true) or root:FindFirstChild("List", true) or root:FindFirstChild("Dropdown", true)
                    if menu and menu:IsA("GuiObject") then
                        local last = menu.Visible
                        local c = menu:GetPropertyChangedSignal("Visible"):Connect(function()
                            local now = menu.Visible
                            if now and not last then refresh() end
                            last = now
                        end)
                        Variables.Maids.CrashServerUiBridge:GiveTask(c)
                        attached=true; break
                    end
                end
            end
        end

        local Module = {}
        function Module.Start()
            if Variables.RunFlag then return end
            Variables.RunFlag = true
            Ensure()

            if not Variables.SelectedBoatName then
                Variables.RunFlag=false
                Variables.Maids.CrashServer:DoCleaning()
                return
            end
            Variables.SelectedBoatId = Variables.BoatIdByName[Variables.SelectedBoatName]
            if Variables.SelectedBoatId == nil then
                Variables.RunFlag=false
                Variables.Maids.CrashServer:DoCleaning()
                return
            end

            local thread = task.spawn(function()
                while Variables.RunFlag do
                    local lp = RbxService.Players.LocalPlayer; if not lp then break end
                    local before = SnapshotOwnedBoats(lp.UserId)
                    local pivot
                    if Variables.TargetWorldPivot then
                        local up = (Variables.BoatExtentsY or 10) + (Variables.StackGapY or 2)
                        pivot = PivotWithWorldYOffset(Variables.TargetWorldPivot, up)
                    else
                        local hrp = (lp.Character or lp.CharacterAdded:Wait()):WaitForChild("HumanoidRootPart")
                        pivot = hrp.CFrame
                    end
                    pcall(function()
                        Variables.SaveClient:LoadBoat(pivot, Variables.SelectedBoatId)
                    end)
                    local newBoat = WaitForNewOwnedBoat(lp.UserId, before, 10)
                    task.wait(0.20)
                end
            end)
            Variables.Maids.CrashServer:GiveTask(thread)
            Variables.Maids.CrashServer:GiveTask(function() Variables.RunFlag = false end)
        end
        function Module.Stop()
            if not Variables.RunFlag then return end
            Variables.RunFlag = false
            Variables.Maids.CrashServer:DoCleaning()
        end

        local box = UI.Tabs.Dupe:AddRightGroupbox("Step #2", "bomb")
        box:AddDropdown("BoatDropdown", { Text = "Save Slot:", Values = {}, Multi = false })
        box:AddToggle("CrashServerToggle", { Text = "Crash Server", Default = false, Tooltip = "Continuously loads a save slot at your position." })

        UI.Options.BoatDropdown:OnChanged(function(val)
            Variables.SelectedBoatName = val
        end)

        UI.Toggles.CrashServerToggle:OnChanged(function(b) if b then Module.Start() else Module.Stop() end end)

        task.defer(function()
            RefreshBoatSaveDropdown()
            AttachBoatDropdownLiveRefresh()
        end)

        local ModuleContract = { Name = "CrashServer", Stop = Module.Stop }

        return ModuleContract
    end
end
