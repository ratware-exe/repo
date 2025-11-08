-- modules/automation/autoflip.lua
do
    return function(UI)
        -- [1] LOAD DEPENDENCIES
        local GlobalEnv = (getgenv and getgenv()) or _G
        local RbxService = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local Players = RbxService.Players
        local RunService = RbxService.RunService

        -- [2] MODULE STATE
        local ModuleName = "AutoFlip"
        local Variables = {
            Maids = { [ModuleName] = Maid.new() },
            RunFlag = false,
            Player = Players.LocalPlayer,
            SeatWatchMaids = setmetatable({}, { __mode = "k" }),
        }
        local maid = Variables.Maids[ModuleName]

        -- [3] HELPERS ----------------------------------------------

        local function clamp(x, a, b)
            if x < a then return a end
            if x > b then return b end
            return x
        end

        local UPRIGHT_TOLERANCE = 0.19634954084936207 -- ~11.25° in radians

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
                            local ownerName = resolveOwnerNameOrPlayer(ownerValue)
                            if ownerName == localPlayer.Name then
                                return modelCandidate
                            end
                        end
                    end
                end
            end
            return nil
        end

        local function findSeatFlipper(seat)
            -- In the place file: Seat / BoatFlipper (Attachment) / BoatFlipperRemoteEvent (RemoteEvent)
            if not seat or not seat.Parent then return nil end
            local attach = seat:FindFirstChild("BoatFlipper")
            if not attach or not attach:IsA("Attachment") then return nil end
            local remote = attach:FindFirstChild("BoatFlipperRemoteEvent")
            if not (remote and remote:IsA("RemoteEvent")) then return nil end
            return attach, remote
        end

        local function isLocalOccupant(seat)
            local occ = seat and seat.Occupant
            if not occ then return false end
            local character = occ.Parent
            if not character then return false end
            local ply = Players:GetPlayerFromCharacter(character)
            return ply == Variables.Player
        end

        local function isFlipping(attach)
            -- Mirrors BoatFlipperClient._updateIsFlipping:
            -- flipping if an AlignOrientation named "BoatFlipperAlignOrientation" exists under the BoatFlipper Attachment
            return attach and attach:FindFirstChild("BoatFlipperAlignOrientation") ~= nil
        end

        local function isUpright(attach)
            if not attach then return true end
            -- Mirrors BoatFlipperBase:IsUpright()
            local up = Vector3.new(0, 1, 0)
            local worldAxis = attach.WorldAxis or (attach.WorldCFrame and attach.WorldCFrame:VectorToWorldSpace(up)) or up
            local d = clamp(worldAxis:Dot(up), -1, 1)
            local angle = math.acos(d)
            return UPRIGHT_TOLERANCE > math.abs(angle)
        end

        -- [4] CORE ---------------------------------------------------

        local function WatchSeat(seat)
            if not Variables.RunFlag then return end
            if not seat or not (seat:IsA("Seat") or seat:IsA("VehicleSeat")) then return end

            -- clean existing
            if Variables.SeatWatchMaids[seat] then
                Variables.SeatWatchMaids[seat]:DoCleaning()
            end
            local seatMaid = Maid.new()
            Variables.SeatWatchMaids[seat] = seatMaid

            local attach, remote = findSeatFlipper(seat)

            -- small debounce per seat to avoid spamming
            local lastFire = 0
            local MIN_INTERVAL = 0.6

            local function tryFlip()
                if not Variables.RunFlag then return end
                if not isLocalOccupant(seat) then return end
                attach, remote = attach and remote and attach or findSeatFlipper(seat)
                if not (attach and remote) then return end

                -- Fire iff NOT upright AND NOT already flipping
                if (not isUpright(attach)) and (not isFlipping(attach)) then
                    local now = tick()
                    if (now - lastFire) >= MIN_INTERVAL then
                        lastFire = now
                        pcall(function() remote:FireServer() end)
                    end
                end
            end

            -- occupant changes
            seatMaid:GiveTask(seat:GetPropertyChangedSignal("Occupant"):Connect(tryFlip))

            -- watch for BoatFlipper creation/removal on this seat
            seatMaid:GiveTask(seat.ChildAdded:Connect(function(child)
                if child.Name == "BoatFlipper" then
                    attach, remote = findSeatFlipper(seat)
                    tryFlip()
                    -- watch flipping state changes
                    if attach then
                        seatMaid:GiveTask(attach.ChildAdded:Connect(function(grand)
                            if grand.Name == "BoatFlipperAlignOrientation" then
                                tryFlip()
                            end
                        end))
                        seatMaid:GiveTask(attach.ChildRemoved:Connect(function(grand)
                            if grand.Name == "BoatFlipperAlignOrientation" then
                                tryFlip()
                            end
                        end))
                    end
                end
            end))

            -- if the BoatFlipper attachment already exists, wire flipping state watchers
            if attach then
                seatMaid:GiveTask(attach.ChildAdded:Connect(function(grand)
                    if grand.Name == "BoatFlipperAlignOrientation" then
                        tryFlip()
                    end
                end))
                seatMaid:GiveTask(attach.ChildRemoved:Connect(function(grand)
                    if grand.Name == "BoatFlipperAlignOrientation" then
                        tryFlip()
                    end
                end))
            end

            -- periodic check to mirror ActionHint’s 0.25s refresh
            seatMaid:GiveTask(RunService.Heartbeat:Connect(function()
                -- keep it light; only check when occupied by us
                if isLocalOccupant(seat) then
                    tryFlip()
                end
            end))

            -- initial check
            tryFlip()

            -- cleanup when seat goes away
            seatMaid:GiveTask(seat.Destroying:Connect(function()
                seatMaid:DoCleaning()
                Variables.SeatWatchMaids[seat] = nil
            end))
        end

        local function ScanForBoatAndSeats()
            if not Variables.RunFlag then return end

            -- stop previous seat watchers
            for seat, sm in pairs(Variables.SeatWatchMaids) do
                sm:DoCleaning()
            end
            Variables.SeatWatchMaids = setmetatable({}, { __mode = "k" })

            -- clear old listener
            maid["BoatDescendantAdded"] = nil

            local boatModel = getOwnedBoatModel()
            if boatModel then
                -- watch future seats (descendant‑level, not just children)
                maid["BoatDescendantAdded"] = boatModel.DescendantAdded:Connect(function(desc)
                    if desc:IsA("Seat") or desc:IsA("VehicleSeat") then
                        WatchSeat(desc)
                    end
                end)

                -- watch existing seats (descendants)
                for _, desc in ipairs(boatModel:GetDescendants()) do
                    if desc:IsA("Seat") or desc:IsA("VehicleSeat") then
                        WatchSeat(desc)
                    end
                end
            end
        end

        local function Start()
            if Variables.RunFlag then return end
            Variables.RunFlag = true

            -- respawns → re‑scan after a moment
            maid["CharacterAdded"] = Variables.Player.CharacterAdded:Connect(function()
                task.wait(2)
                if not Variables.RunFlag then return end
                ScanForBoatAndSeats()
            end)

            ScanForBoatAndSeats()
        end

        local function Stop()
            if not Variables.RunFlag then return end
            Variables.RunFlag = false

            maid["CharacterAdded"] = nil
            maid["BoatDescendantAdded"] = nil

            for seat, sm in pairs(Variables.SeatWatchMaids) do
                sm:DoCleaning()
            end
            Variables.SeatWatchMaids = setmetatable({}, { __mode = "k" })
        end

        -- [5] UI WIRING (unchanged API; now lives under Automation → Combat)
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

        local function OnChanged(Value)
            if Value then Start() else Stop() end
        end
        AutoFlipToggle:OnChanged(OnChanged)
        OnChanged(AutoFlipToggle.Value)

        return { Name = ModuleName, Stop = Stop }
    end
end
