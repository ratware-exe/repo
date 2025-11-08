-- "modules/wfyb/automation/autoflip.lua"
do
    return function(UI)
        -- [1] LOAD DEPENDENCIES
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv = (getgenv and getgenv()) or _G
        local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
        
        -- [2] MODULE STATE
        local ModuleName = "AutoFlip"
        local Variables = {
            Maids = { [ModuleName] = Maid.new() },
            RunFlag = false,
            Player = RbxService.Players.LocalPlayer,
            SeatWatchMaids = setmetatable({}, { __mode = "k" }), -- Use weak table for seat maids
        }
        local maid = Variables.Maids[ModuleName] -- Main module maid

        -- [3] HELPER FUNCTIONS
        local function toLowerContainsSeat(nameText)
            if typeof(nameText) ~= "string" then return false end
            return string.find(string.lower(nameText), "seat", 1, true) ~= nil
        end

        local function resolveOwnerNameOrPlayer(ownerInstance)
            if not ownerInstance then return nil, nil end
            if ownerInstance:IsA("StringValue") then
                return ownerInstance.Value, nil
            end
            if ownerInstance:IsA("ObjectValue") then
                local v = ownerInstance.Value
                if typeof(v) == "Instance" and v:IsA("Player") then
                    return v.Name, v
                elseif typeof(v) == "Instance" and v.Name then
                    return v.Name, v
                end
            end
            return nil, nil
        end

        local function getOwnedBoatModel()
            local boatsFolder = RbxService.Workspace:FindFirstChild("Boats")
            if not boatsFolder then return nil end
            local localPlayer = Variables.Player
            if not localPlayer then return nil end

            for _, modelCandidate in ipairs(boatsFolder:GetChildren()) do
                if modelCandidate:IsA("Model") then
                    local boatData = modelCandidate:FindFirstChild("BoatData")
                    if boatData then
                        local ownerValue = boatData:FindFirstChild("Owner")
                        if ownerValue then
                            local ownerName, ownerPlayer = resolveOwnerNameOrPlayer(ownerValue)
                            if ownerName == localPlayer.Name then
                                return modelCandidate
                            end
                        end
                    end
                end
            end
            return nil
        end
        
        -- FIX 2: Check for existing Cooldown object
        local function findBoatFlipperRemoteEvent(seatContainer)
            local seatNode = seatContainer:FindFirstChild("Seat")
            if seatNode then
                local boatFlipper = seatNode:FindFirstChild("BoatFlipper")
                if boatFlipper then
                    -- Check if a cooldown is *already* active
                    local cooldown = boatFlipper:FindFirstChild("Cooldown")
                    if cooldown then
                        return nil -- Don't fire, it's already active/cooling down
                    end
                    
                    local remoteEvent = boatFlipper:FindFirstChild("BoatFlipperRemoteEvent")
                    if remoteEvent and remoteEvent:IsA("RemoteEvent") then
                        return remoteEvent
                    end
                end
            end
            
            -- Fallback, but also check for cooldown
            local boatFlipperDeep = seatContainer:FindFirstChild("BoatFlipper", true)
            if boatFlipperDeep then
                local cooldown = boatFlipperDeep:FindFirstChild("Cooldown")
                if cooldown then
                    return nil -- Don't fire
                end
                
                local remoteEventDeep = boatFlipperDeep:FindFirstChild("BoatFlipperRemoteEvent")
                if remoteEventDeep and remoteEventDeep:IsA("RemoteEvent") then
                    return remoteEventDeep
                end
            end
            
            return nil
        end
        
        local function FireRemote(remoteEvent)
            pcall(function()
                remoteEvent:FireServer()
            end)
        end

        -- [4] CORE LOGIC
        
        local function WatchSeat(seatContainer)
            if not Variables.RunFlag then return end
            
            -- Clean up old watcher for this seat, if any
            if Variables.SeatWatchMaids[seatContainer] then
                Variables.SeatWatchMaids[seatContainer]:DoCleaning()
                Variables.SeatWatchMaids[seatContainer] = nil
            end
            
            local seatMaid = Maid.new()
            Variables.SeatWatchMaids[seatContainer] = seatMaid
            -- No need to give to main maid, weak table will handle it
            
            -- FIX 1: Watch the *Seat* object, not its parent container
            local seatNode = seatContainer:FindFirstChild("Seat")
            if not seatNode then return end -- No seat, nothing to watch
            
            -- 1. Check if flipper already exists when we start watching
            local existingRemote = findBoatFlipperRemoteEvent(seatContainer)
            if existingRemote then
                FireRemote(existingRemote)
            end
            
            -- 2. Watch for flipper to be added *to the Seat*
            local conn = seatNode.ChildAdded:Connect(function(child)
                if child.Name == "BoatFlipper" then
                    -- Wait a frame for the remote event to be parented
                    task.wait() 
                    local remote = findBoatFlipperRemoteEvent(seatContainer)
                    if remote then
                        FireRemote(remote)
                    end
                end
            end)
            seatMaid:GiveTask(conn)
            
            -- Clean up this maid if the seat is removed
            seatMaid:GiveTask(seatNode.Destroying:Connect(function()
                seatMaid:DoCleaning()
                Variables.SeatWatchMaids[seatContainer] = nil
            end))
        end
        
        local function ScanForBoatAndSeats()
            if not Variables.RunFlag then return end
            
            local boatModel = getOwnedBoatModel()
            if boatModel then
                -- Watch for new seats being added (e.g., build mode)
                maid:GiveTask(boatModel.ChildAdded:Connect(function(child)
                    if toLowerContainsSeat(child.Name) then
                        WatchSeat(child)
                    end
                end), "BoatChildAdded")
                
                -- Watch existing seats
                for _, child in ipairs(boatModel:GetChildren()) do
                    if toLowerContainsSeat(child.Name) then
                        WatchSeat(child)
                    end
                end
            end
        end
        
        local function Start()
            if Variables.RunFlag then return end
            Variables.RunFlag = true
            
            -- Watch for respawns
            maid:GiveTask(Variables.Player.CharacterAdded:Connect(function()
                task.wait(2) -- Wait for boat to load
                if not Variables.RunFlag then return end
                ScanForBoatAndSeats()
            end), "CharacterAdded")
            
            -- Initial scan
            ScanForBoatAndSeats()
        end

        local function Stop()
            if not Variables.RunFlag then return end
            Variables.RunFlag = false
            
            -- Clean up CharacterAdded listener
            maid:Clean("CharacterAdded")
            maid:Clean("BoatChildAdded")
            
            -- Clean up all individual seat watchers
            for seat, seatMaid in pairs(Variables.SeatWatchMaids) do
                seatMaid:DoCleaning()
            end
            Variables.SeatWatchMaids = setmetatable({}, { __mode = "k" })
        end

        -- [5] UI CREATION
        -- Safely get or create the Automation tab/groupbox
        local AutomationTab = UI.Tabs.Automation or UI:AddTab("Automation", "tractor")
        local CombatGroupBox = AutomationTab:AddLeftGroupbox("Combat", "swords")
        
        local AutoFlipToggle = CombatGroupBox:AddToggle("AutoFlipToggle", {
            Text = "Auto Flip Boat",
            Tooltip = "Automatically flips boat if possible.",
            DisabledTooltip = "Feature Disabled!",
            Default = false,
            Disabled = false,
            Visible = true,
            Risky = false,
        })

        -- [6] UI WIRING
        -- FIX: Define OnChanged *before* calling it
        local function OnChanged(Value)
            if Value then
                Start()
            else
                Stop()
            end
        end
        
        AutoFlipToggle:OnChanged(OnChanged)
        
        OnChanged(AutoFlipToggle.Value)

        -- [7] RETURN MODULE
        return { Name = ModuleName, Stop = Stop }
    end
end
