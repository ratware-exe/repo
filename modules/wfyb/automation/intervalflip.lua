-- "modules/wfyb/automation/intervalflip.lua",
do
	return function(UI)
		-- [1] LOAD DEPENDENCIES
		local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
		local GlobalEnv = (getgenv and getgenv()) or _G
		local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
		
		-- [2] MODULE STATE
		local ModuleName = "IntervalFlip"
		local Variables = {
			Maids = { [ModuleName] = Maid.new() },
			RunFlag = false,
			FireIntervalSeconds = 1,
			TargetBoatModel = nil,
			SeatsToFire = {}, -- array of {container = Instance, remote = RemoteEvent}
		}
		local maid = Variables.Maids[ModuleName]
		local Players = RbxService.Players
		local Workspace = RbxService.Workspace

		-- [3] HELPER FUNCTIONS (from original script)
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
			local boatsFolder = Workspace:FindFirstChild("Boats")
			if not boatsFolder then return nil end
			local localPlayer = Players.LocalPlayer
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

		local function findBoatFlipperRemoteEventUnderSeatContainer(seatContainer)
			local seatNode = seatContainer:FindFirstChild("Seat")
			if seatNode then
				local boatFlipper = seatNode:FindFirstChild("BoatFlipper")
				if boatFlipper then
					local remoteEvent = boatFlipper:FindFirstChild("BoatFlipperRemoteEvent")
					if remoteEvent and remoteEvent:IsA("RemoteEvent") then
						return remoteEvent, "Seat/BoatFlipper path"
					end
				end
			end
			local remoteEventDeep = seatContainer:FindFirstChild("BoatFlipperRemoteEvent", true)
			if remoteEventDeep and remoteEventDeep:IsA("RemoteEvent") then
				return remoteEventDeep, "Deep fallback under seat container"
			end
			return nil, "Not found"
		end

		local function collectSeatChildrenAndRemotes(boatModel)
			local results = {}
			local directChildren = boatModel:GetChildren()

			for _, child in ipairs(directChildren) do
				if toLowerContainsSeat(child.Name) then
					local remoteEvent, howFound = findBoatFlipperRemoteEventUnderSeatContainer(child)
					if remoteEvent then
						table.insert(results, { container = child, remote = remoteEvent })
					end
				end
			end
			return results
		end

		local function refreshTargets()
			Variables.TargetBoatModel = getOwnedBoatModel()
			if not Variables.TargetBoatModel then
				Variables.SeatsToFire = {}
				return
			end
			Variables.SeatsToFire = collectSeatChildrenAndRemotes(Variables.TargetBoatModel)
		end

		local function fireAll()
			for _, entry in ipairs(Variables.SeatsToFire) do
				pcall(function()
					entry.remote:FireServer()
				end)
			end
		end

		-- [4] CORE LOGIC (Loop)
		local function IntervalLoop()
			local rediscoverStep = 0
			while Variables.RunFlag do
				if Variables.TargetBoatModel == nil or not Variables.TargetBoatModel.Parent then
					refreshTargets()
				end

				fireAll()

				rediscoverStep += 1
				if rediscoverStep >= 5 then
					refreshTargets()
					rediscoverStep = 0
				end

				task.wait(Variables.FireIntervalSeconds)
			end
		end

		-- [5] CONTROL FUNCTIONS (START/STOP)
		local function Start()
			if Variables.RunFlag then return end
			Variables.RunFlag = true
			refreshTargets() -- Initial discovery
			maid["MainThread"] = task.spawn(IntervalLoop)
		end

		local function Stop()
			if not Variables.RunFlag then return end
			Variables.RunFlag = false
			maid["MainThread"] = nil -- Stops the loop and cleans up the thread
		end

		-- [6] UI CREATION
		local AutomationTab = UI.Tabs.Automation or UI:AddTab("Automation", "tractor")
		local CombatGroupBox = AutomationTab:AddLeftGroupbox("Combat", "swords")
		
		local IntervalFlipToggle = CombatGroupBox:AddToggle("IntervalFlipToggle", {
			Text = "Interval Flip Boat",
			Tooltip = "Triggers the flip boat feature every 'x' seconds.",
			DisabledTooltip = "Feature Disabled!",
			Default = false,
			Disabled = false,
			Visible = true,
			Risky = false,
		})
		
		local IntervalFlipSlider = CombatGroupBox:AddSlider("IntervalFlipSlider", {
			Text = "Seconds",
			Default = 1,
			Min = 0,
			Max = 10,
			Rounding = 1,
			Compact = true,
			Tooltip = "Changes the boat flip trigger interval.",
			DisabledTooltip = "Feature Disabled!",
			Disabled = false,
			Visible = true,
		})

		-- [7] UI WIRING
		IntervalFlipToggle:OnChanged(function(Value)
			if Value then
				Start()
			else
				Stop()
			end
		end)
		
		IntervalFlipSlider:OnChanged(function(Value)
			Variables.FireIntervalSeconds = math.max(0, Value) -- Ensure it's not negative
		end)
		
		-- Apply current state on load
		Variables.FireIntervalSeconds = math.max(0, IntervalFlipSlider.Value)
		if IntervalFlipToggle.Value then
			Start()
		end

		-- [8] RETURN MODULE
		return { Name = ModuleName, Stop = Stop }
	end
end
