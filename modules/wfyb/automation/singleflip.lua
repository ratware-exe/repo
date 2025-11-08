-- "modules/wfyb/automation/singleflip.lua",
do
	return function(UI)
		-- [1] LOAD DEPENDENCIES
		local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
		local GlobalEnv = (getgenv and getgenv()) or _G
		local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
		
		-- [2] MODULE STATE
		local ModuleName = "SingleFlip"
		local Variables = {
			Maids = { [ModuleName] = Maid.new() },
			NotifyFunc = UI.Notify,
		}
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
		
		-- [4] CORE LOGIC (Single Fire)
		local function FireOnce()
			local boatModel = getOwnedBoatModel()
			if not boatModel then
				if Variables.NotifyFunc then
					Variables.NotifyFunc("Single Flip: No boat found.")
				end
				return
			end
			
			local seatsToFire = collectSeatChildrenAndRemotes(boatModel)
			if #seatsToFire == 0 then
				if Variables.NotifyFunc then
					Variables.NotifyFunc("Single Flip: No flip remotes found on boat.")
				end
				return
			end

			for _, entry in ipairs(seatsToFire) do
				pcall(function()
					entry.remote:FireServer()
				end)
			end
			
			if Variables.NotifyFunc then
				Variables.NotifyFunc(string.format("Single Flip: Fired %d remote(s).", #seatsToFire))
			end
		end

		-- [5] CONTROL FUNCTIONS (START/STOP)
		-- This module has no persistent loop, so Start/Stop are minimal
		local function Start()
			-- Nothing to do here
		end

		local function Stop()
			-- Nothing to clean up
			Variables.Maids[ModuleName]:DoCleaning()
		end

		-- [6] UI CREATION
		local AutomationTab = UI.Tabs.Automation or UI:AddTab("Automation", "tractor")
		local CombatGroupBox = AutomationTab:AddLeftGroupbox("Combat", "swords")
		
		local SingleFlipButton = CombatGroupBox:AddButton({
			Text = "Single Flip Boat",
			Func = FireOnce, -- Wire logic directly to the button
			DoubleClick = false,
			Tooltip = "Fires all flip remotes on your boat once.",
		})

		-- [7] UI WIRING
		-- Logic is already wired in the button creation
		
		-- [8] RETURN MODULE
		return { Name = ModuleName, Stop = Stop }
	end
end
