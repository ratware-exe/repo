-- "modules/automation/autochest.lua"
do
	return function(UI)
		-- [1] LOAD DEPENDENCIES
		local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
		local GlobalEnv = (getgenv and getgenv()) or _G
		local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
		
		-- [2] MODULE STATE
		local ModuleName = "AutoCollectChests"
		local Variables = {
			Maids = { [ModuleName] = Maid.new() },
			RunFlag = false,
			
			-- Settings from original script
			ScanIntervalSeconds = 1,   -- outer loop
			FireIntervalSeconds = 0.20,  -- inner loop while unopened
			RequireMoveToTarget = true,  -- MoveTo MetalOutline before firing
		}
		local maid = Variables.Maids[ModuleName]
		local lp = RbxService.Players.LocalPlayer

		-- [3] CORE LOGIC (Helpers)
		
		local function GetLocalCharacter()
			if not lp then return nil end
			return lp.Character or lp.CharacterAdded:Wait()
		end

		-- Returns remote (RemoteEvent) and marker (MetalOutline) if the full path exists; else nils.
		local function GetTriggerPath(chestModel)
			if not chestModel then return nil, nil end
			local chestBottom = chestModel:FindFirstChild("ChestBottom")
			if not chestBottom then return nil, nil end
			local metalOutline = chestBottom:FindFirstChild("MetalOutline")
			if not metalOutline then return nil, nil end
			local trigger = metalOutline:FindFirstChild("Trigger")
			if not trigger then return nil, metalOutline end
			local remote = trigger:FindFirstChild("TriggerRemoteEvent")
			if remote and remote.IsA and remote:IsA("RemoteEvent") then
				return remote, metalOutline
			end
			return nil, metalOutline
		end

		-- A chest is considered "opened" when the trigger path no longer exists.
		local function IsChestOpened(chestModel)
			local remote = GetTriggerPath(chestModel)
			return remote == nil
		end
		
		-- [4] CORE LOGIC (Loop)
		
		local function AutoChestLoop()
			while Variables.RunFlag do
				local chestsFolder = RbxService.Workspace:FindFirstChild("Chests")
				if chestsFolder and Variables.RunFlag then -- Re-check RunFlag
					local chestList = chestsFolder:GetChildren()
					for i = 1, #chestList do
						if not Variables.RunFlag then break end -- Stop mid-loop if toggled off
						
						local chest = chestList[i]
						if chest and chest.Parent == chestsFolder and not IsChestOpened(chest) then
							local remote, marker = GetTriggerPath(chest)

							-- Optional: move once near the marker to satisfy proximity checks
							if Variables.RequireMoveToTarget and marker and marker.Position then
								local character = GetLocalCharacter()
								if character and character.MoveTo then
									pcall(function()
										character:MoveTo(marker.Position)
									end)
								end
							end

							-- Fire repeatedly until the chest opens (trigger path gone)
							while Variables.RunFlag and chest and chest.Parent and not IsChestOpened(chest) do
								local currentRemote = GetTriggerPath(chest) -- refresh each tick
								if not currentRemote then break end
								pcall(function()
									currentRemote:FireServer()
								end)
								task.wait(Variables.FireIntervalSeconds)
							end
						end
					end
				end
				-- keep cycling; once all chests are gone, this just idles and rechecks
				task.wait(Variables.ScanIntervalSeconds)
			end
		end

		-- [5] CONTROL FUNCTIONS (START/STOP)
		
		local function Start()
			if Variables.RunFlag then return end
			Variables.RunFlag = true
			
			-- Start the loop and give it to the maid
			maid["MainThread"] = task.spawn(AutoChestLoop)
		end

		local function Stop()
			if not Variables.RunFlag then return end
			Variables.RunFlag = false
			
			-- This will stop the loop and (on the next line) cancel the thread
			maid["MainThread"] = nil -- This tells the maid to run the cleanup
		end

		-- [6] UI CREATION
		-- Safely get or create the Automation tab
		local AutomationTab = UI.Tabs.Automation or UI:AddTab("Automation", "tractor")
		
		local FarmGroupBox = AutomationTab:AddRightGroupbox("Farm", "tractor")
		local AutoCollectChestsToggle = FarmGroupBox:AddToggle("AutoCollectChestsToggle", {
			Text = "Collect Chests",
			Tooltip = "Automatically collects nearby chests.",
			DisabledTooltip = "Feature Disabled!",	
			Default = false,	
			Disabled = false,	
			Visible = true,	
		})

		-- [7] UI WIRING
		local function OnChanged(Value)
			if Value then
				Start()
			else
				Stop()
			end
		end
		
		AutoCollectChestsToggle:OnChanged(OnChanged)
		
		-- Apply current state on load
		OnChanged(AutoCollectChestsToggle.Value)

		-- [8] RETURN MODULE
		return { Name = ModuleName, Stop = Stop }
	end
end
