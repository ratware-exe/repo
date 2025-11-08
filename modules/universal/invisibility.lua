-- "modules/universal/miscellaneous/invisibility.lua",
do
	return function(UI)
		-- [1] LOAD DEPENDENCIES
		local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
		local GlobalEnv = (getgenv and getgenv()) or _G
		local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
		
		-- [2] MODULE STATE
		local ModuleName = "Invisibility"
		local Variables = {
			Maids = { 
				[ModuleName] = Maid.new(), -- For persistent things (respawn, etc)
				ToggleMaid = Maid.new() -- For temporary things (loops, etc)
			},
			NotifyFunc = UI.Notify,
			RunFlag = false, -- Tracks if the toggle is ON
			IsInvisible = false, -- Tracks if the swap has happened
			
			Player = RbxService.Players.LocalPlayer,
			RealCharacter = nil,
			FakeCharacter = nil,
			Part = nil, -- The part to hold the real character
			
			-- Settings from original script
			Transparency = true,
			NoClip = false,
		}
		
		local moduleMaid = Variables.Maids[ModuleName]
		local toggleMaid = Variables.Maids.ToggleMaid

		-- [3] CORE LOGIC
		
		local function CreateFakeCharacter()
			-- Clean up any old instances first
			if Variables.FakeCharacter then pcall(Variables.FakeCharacter.Destroy, Variables.FakeCharacter) end
			if Variables.Part then pcall(Variables.Part.Destroy, Variables.Part) end
			
			Variables.RealCharacter = Variables.Player.Character or Variables.Player.CharacterAdded:Wait()
			if not Variables.RealCharacter then return end
			
			Variables.RealCharacter.Archivable = true
			Variables.FakeCharacter = Variables.RealCharacter:Clone()
			
			-- Create the containment part far away
			local Part = Instance.new("Part", workspace)
			Part.Anchored = true
			Part.Size = Vector3.new(200, 1, 200)
			Part.CFrame = CFrame.new(0, -500, 0) -- Far away
			Part.CanCollide = true
			Variables.Part = Part
			
			Variables.FakeCharacter.Parent = workspace
			Variables.FakeCharacter.HumanoidRootPart.CFrame = Part.CFrame * CFrame.new(0, 5, 0)
			
			-- Clone local scripts but keep them disabled
			for i, v in pairs(Variables.RealCharacter:GetChildren()) do
				if v:IsA("LocalScript") then
					local clone = v:Clone()
					clone.Disabled = true
					clone.Parent = Variables.FakeCharacter
				end
			end
			
			-- Apply transparency
			if Variables.Transparency then
				for i, v in pairs(Variables.FakeCharacter:GetDescendants()) do
					if v:IsA("BasePart") then
						v.Transparency = 0.7
					end
				end
			end
			
			-- Handle the real character dying
			local hum = Variables.RealCharacter:FindFirstChildOfClass("Humanoid")
			if hum then
				local diedConn = hum.Died:Connect(function()
					Variables.IsInvisible = false
					Variables.RunFlag = false
					if Variables.FakeCharacter then pcall(Variables.FakeCharacter.Destroy, Variables.FakeCharacter) end
					if Variables.Part then pcall(Variables.Part.Destroy, Variables.Part) end
					Variables.RealCharacter = nil
					Variables.FakeCharacter = nil
					Variables.Part = nil
				end)
				moduleMaid:GiveTask(diedConn) -- Give to main maid
			end
		end

		-- Function to enable the module (go invisible)
		local function Start()
			if Variables.RunFlag then return end
			if not Variables.RealCharacter or not Variables.FakeCharacter then
				pcall(CreateFakeCharacter)
				if not Variables.RealCharacter or not Variables.FakeCharacter then
					if Variables.NotifyFunc then Variables.NotifyFunc("Invisibility: Character not ready.") end
					return
				end
			end
			
			Variables.RunFlag = true
			if Variables.IsInvisible then return end
			
			local RealCharacter = Variables.RealCharacter
			local FakeCharacter = Variables.FakeCharacter
			
			local StoredCF = RealCharacter.HumanoidRootPart.CFrame
			RealCharacter.HumanoidRootPart.CFrame = FakeCharacter.HumanoidRootPart.CFrame
			FakeCharacter.HumanoidRootPart.CFrame = StoredCF
			RealCharacter.Humanoid:UnequipTools()
			
			Variables.Player.Character = FakeCharacter
			workspace.CurrentCamera.CameraSubject = FakeCharacter.Humanoid
			
			-- Start RenderStepped loop for pseudo-anchor and noclip
			local hbConn = RbxService.RunService.RenderStepped:Connect(function()
				if Variables.RealCharacter then
					Variables.RealCharacter.HumanoidRootPart.CFrame = Variables.Part.CFrame * CFrame.new(0, 5, 0)
				end
				if Variables.NoClip and Variables.FakeCharacter then
					Variables.FakeCharacter.Humanoid:ChangeState(11) -- Enum.HumanoidStateType.NoClip
				end
			end)
			toggleMaid:GiveTask(hbConn) -- Give to toggle maid
			
			-- Enable local scripts on fake char
			for i, v in pairs(FakeCharacter:GetChildren()) do
				if v:IsA("LocalScript") then
					v.Disabled = false
				end
			end
	
			Variables.IsInvisible = true
		end

		-- Function to disable the module (go visible)
		local function Stop()
			if not Variables.RunFlag then return end
			Variables.RunFlag = false
			
			-- Stop the RenderStepped loop
			toggleMaid:DoCleaning()
			
			if not Variables.IsInvisible then return end
			if not Variables.RealCharacter or not Variables.FakeCharacter then return end
			
			local RealCharacter = Variables.RealCharacter
			local FakeCharacter = Variables.FakeCharacter

			local StoredCF = FakeCharacter.HumanoidRootPart.CFrame
			FakeCharacter.HumanoidRootPart.CFrame = RealCharacter.HumanoidRootPart.CFrame
			RealCharacter.HumanoidRootPart.CFrame = StoredCF
	
			FakeCharacter.Humanoid:UnequipTools()
			Variables.Player.Character = RealCharacter
			workspace.CurrentCamera.CameraSubject = RealCharacter.Humanoid
			
			-- Disable local scripts on fake char
			for i, v in pairs(FakeCharacter:GetChildren()) do
				if v:IsA("LocalScript") then
					v.Disabled = true
				end
			end
			Variables.IsInvisible = false
		end
		
		-- [4] INITIALIZATION & RESPAWN HANDLING
		
		-- Create the first fake character
		pcall(CreateFakeCharacter)
		
		-- Handle respawns
		local charConn = Variables.Player.CharacterAppearanceLoaded:Connect(function(newChar)
			pcall(CreateFakeCharacter) -- This will clean old and make new
			if Variables.RunFlag then
				-- If toggle was on, immediately go invisible
				pcall(Start)
			end
		end)
		moduleMaid:GiveTask(charConn) -- Give to main maid

		-- [5] UI CREATION
		local MovementGroupbox = UI.Tabs.Misc:AddLeftGroupbox("Movement")
		
		local InvisibilityToggle = MovementGroupbox:AddToggle("InvisibilityToggle", {
			Text = "Enable Invisibility",
			Tooltip = "Swaps your real character with a fake one.",
			Default = false,
		})
		
		-- [6] UI WIRING
		local function OnChanged(Value)
			if Value then
				Start()
			else
				Stop()
			end
		end
		
		InvisibilityToggle:OnChanged(OnChanged)
		OnChanged(InvisibilityToggle.Value)

		-- [7] RETURN MODULE
		local function ModuleStop()
			Stop() -- Make player visible
			
			-- Full cleanup
			if Variables.FakeCharacter then pcall(Variables.FakeCharacter.Destroy, Variables.FakeCharacter) end
			if Variables.Part then pcall(Variables.Part.Destroy, Variables.Part) end
			
			moduleMaid:DoCleaning()
			toggleMaid:DoCleaning()
		end
		
		return { Name = ModuleName, Stop = ModuleStop }
	end
end
