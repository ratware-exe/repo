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
		
		-- Based on .rbxlx analysis:
		-- SeatCylinder.Seat.BoatFlipper (ProximityPrompt)
		-- SeatCylinder.Shared.BoatFlipperRemoteEvent (RemoteEvent)
		-- SeatCylinder.Shared.Cooldown (NumberValue)
		
		local function GetSeatComponents(seatContainer)
			local seat = seatContainer:FindFirstChild("Seat")
			local shared = seatContainer:FindFirstChild("Shared")
			if not (seat and shared) then return nil end
			
			local prompt = seat:FindFirstChild("BoatFlipper")
			local remote = shared:FindFirstChild("BoatFlipperRemoteEvent")
			local cooldown = shared:FindFirstChild("Cooldown")
			
			if prompt and remote and remote:IsA("RemoteEvent") then
				return {
					Prompt = prompt,
					Remote = remote,
					Cooldown = cooldown -- This can be nil, which is fine
				}
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
			end
			
			local seatMaid = Maid.new()
			Variables.SeatWatchMaids[seatContainer] = seatMaid
			
			local seat = seatContainer:FindFirstChild("Seat")
			local shared = seatContainer:FindFirstChild("Shared")
			if not (seat and shared) then return end -- Invalid seat structure
			
			local function CheckAndFire()
				if not Variables.RunFlag then return end
				
				local components = GetSeatComponents(seatContainer)
				if components and components.Prompt.Enabled and not components.Cooldown then
					-- Prompt is visible AND there is no cooldown, so fire.
					FireRemote(components.Remote)
				end
			end
			
			-- 1. Watch for the prompt to be enabled
			local prompt = seat:FindFirstChild("BoatFlipper")
			if prompt then
				seatMaid:GiveTask(prompt:GetPropertyChangedSignal("Enabled"):Connect(CheckAndFire))
			else
				seatMaid:GiveTask(seat.ChildAdded:Connect(function(child)
					if child.Name == "BoatFlipper" then
						seatMaid:GiveTask(child:GetPropertyChangedSignal("Enabled"):Connect(CheckAndFire))
						CheckAndFire() -- Check immediately
					end
				end))
			end
			
			-- 2. Watch for the cooldown to be removed
			seatMaid:GiveTask(shared.ChildRemoved:Connect(function(child)
				if child.Name == "Cooldown" then
					-- Cooldown was removed, check if we should fire
					CheckAndFire()
				end
			end))
			
			-- 3. Initial check
			CheckAndFire()
			
			-- Clean up this maid if the seat is removed
			seatMaid:GiveTask(seatContainer.Destroying:Connect(function()
				seatMaid:DoCleaning()
				Variables.SeatWatchMaids[seatContainer] = nil
			end))
		end
		
		local function ScanForBoatAndSeats()
			if not Variables.RunFlag then return end
			
			-- Stop all previous seat watchers
			for seat, seatMaid in pairs(Variables.SeatWatchMaids) do
				seatMaid:DoCleaning()
			end
			Variables.SeatWatchMaids = setmetatable({}, { __mode = "k" })
			maid:Clean("BoatChildAdded") -- Clear old listener
			
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
