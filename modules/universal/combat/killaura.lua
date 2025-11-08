-- "modules/universal/combat/aura.lua"
do
	return function(UI)
		-- [1] LOAD DEPENDENCIES
		local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
		local GlobalEnv = (getgenv and getgenv()) or _G
		local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
		
		-- [2] MODULE STATE
		local ModuleName = "Aura"
		local Variables = {
			Maids = { [ModuleName] = Maid.new() },
			RunFlag = false,
			HitboxSize = 10, -- Default radius
			DeathCheck = true,
			OverlapParams = OverlapParams.new(),
		}
		local maid = Variables.Maids[ModuleName]
		local lp = RbxService.Players.LocalPlayer

		-- [3] HELPER FUNCTIONS (from original script)
		local function getchar(plr)
			local plr = plr or lp
			return plr.Character
		end

		local function gethumanoid(plr)
			local char = plr:IsA("Model") and plr or getchar(plr)
			if char then
				return char:FindFirstChildWhichIsA("Humanoid")
			end
		end
		
		local function IsAlive(Humanoid)
			return Humanoid and Humanoid.Health > 0
		end

		local function GetTouchInterest(Tool)
			return Tool and Tool:FindFirstChildWhichIsA("TouchTransmitter", true)
		end

		local function GetCharacters(LocalPlayerChar)
			local Characters = {}
			for i, v in pairs(RbxService.Players:GetPlayers()) do
				local char = getchar(v)
				if char then
					table.insert(Characters, char)
				end
			end
			table.remove(Characters, table.find(Characters, LocalPlayerChar))
			return Characters
		end

		local function Attack(Tool, TouchPart, ToTouch)
			if Tool:IsDescendantOf(RbxService.Workspace) then
				Tool:Activate()
				firetouchinterest(TouchPart, ToTouch, 1)
				firetouchinterest(TouchPart, ToTouch, 0)
			end
		end

		-- [4] CORE LOGIC (LOOP)
		local function AuraLoop()
			while Variables.RunFlag do
				local char = getchar()
				if IsAlive(gethumanoid(char)) then
					local Tool = char and char:FindFirstChildWhichIsA("Tool")
					local TouchInterest = Tool and GetTouchInterest(Tool)

					if TouchInterest then
						local TouchPart = TouchInterest.Parent
						local Characters = GetCharacters(char)
						
						local op = Variables.OverlapParams
						op.FilterDescendantsInstances = Characters
						
						-- Use the variable from the slider
						local radius = Variables.HitboxSize
						local size = Vector3.new(radius, radius, radius)
						
						local InstancesInBox = RbxService.Workspace:GetPartBoundsInBox(TouchPart.CFrame, TouchPart.Size + size, op)

						for i, v in pairs(InstancesInBox) do
							local Character = v:FindFirstAncestorWhichIsA("Model")

							if table.find(Characters, Character) then
								if Variables.DeathCheck then
									if IsAlive(gethumanoid(Character)) then
										Attack(Tool, TouchPart, v)
									end
								else
									Attack(Tool, TouchPart, v)
								end
							end
						end
					end
				end
				RbxService.RunService.Heartbeat:Wait()
			end
		end

		-- [5] CONTROL FUNCTIONS (START/STOP)
		local function Start()
			if Variables.RunFlag then return end
			Variables.RunFlag = true
			
			-- Configure OverlapParams
			Variables.OverlapParams.FilterType = Enum.RaycastFilterType.Include
			
			-- Start the loop and give it to the maid
			maid.MainThread = task.spawn(AuraLoop)
		end

		local function Stop()
			if not Variables.RunFlag then return end
			Variables.RunFlag = false
			
			-- This will stop the loop and (on the next line) cancel the thread
			maid.MainThread = nil -- This tells the maid to run the cleanup
		end

		-- [6] UI CREATION
		local CombatGroupBox = UI.Tabs.Temp:AddLeftGroupbox("Combat")
		
		local AuraToggle = CombatGroupBox:AddToggle("AuraToggle", {
			Text = "Enable Aura",
			Tooltip = "Automatically attack players within a radius.",
			Default = false,
		})
		
		local AuraRadiusSlider = CombatGroupBox:AddSlider("AuraRadiusSlider", {
			Text = "Aura Radius",
			Min = 1,
			Max = 100,
			Default = 10,
			Rounding = 1,
			Compact = false,
		})

		-- [7] UI WIRING
		AuraToggle:OnChanged(function(Value)
			if Value then
				Start()
			else
				Stop()
			end
		end)
		
		AuraRadiusSlider:OnChanged(function(Value)
			Variables.HitboxSize = Value
		end)
		
		-- Set initial state from UI
		Variables.HitboxSize = AuraRadiusSlider.Value
		if AuraToggle.Value then
			Start()
		end

		-- [8] RETURN MODULE
		return { Name = ModuleName, Stop = Stop }
	end
end
