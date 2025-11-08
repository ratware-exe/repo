-- "modules/universal/movement/infinitejump.lua",
do
	return function(UI)
		-- [1] LOAD DEPENDENCIES
		local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
		local GlobalEnv = (getgenv and getgenv()) or _G
		local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
		
		-- [2] MODULE STATE
		local ModuleName = "InfiniteJump"
		local Variables = {
			Maids = { [ModuleName] = Maid.new() },
			NotifyFunc = UI.Notify,
			RunFlag = false, -- Tracks if the module is active
			SpaceHeld = false, -- Tracks if spacebar is held
			Player = RbxService.Players.LocalPlayer
		}

		-- [3] CORE LOGIC
		
		-- Helper to perform a jump and push upward
		local function tryJumpAndAscend()
			local char = Variables.Player and Variables.Player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso"))
			
			if hum and hum.Health > 0 then
				pcall(function()
					-- Request a jump (keeps humanoid state consistent)
					hum.Jump = true
					hum:ChangeState(Enum.HumanoidStateType.Freefall)
				end)
			end
			if root then
				pcall(function()
					-- Push player upward while holding space
					local ok, vel = pcall(function() return root.AssemblyLinearVelocity end)
					vel = (ok and vel) or Vector3.new(0, 0, 0)
					local ascentSpeed = 60 -- Tweak this value to control ascent rate
					if vel.Y < ascentSpeed then
						root.AssemblyLinearVelocity = Vector3.new(vel.X, ascentSpeed, vel.Z)
					end
				end)
			end
		end
		
		-- Function to enable the module
		local function Start()
			if Variables.RunFlag then return end
			Variables.RunFlag = true
			
			local uis = RbxService.UserInputService
			local RunService = RbxService.RunService
			local maid = Variables.Maids[ModuleName]

			-- Input began/ended to track holding space (ignore when typing in GUI)
			local inputBeganConn = uis.InputBegan:Connect(function(input, gameProcessed)
				if gameProcessed then return end
				if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.Space then
					Variables.SpaceHeld = true
				end
			end)
			maid:GiveTask(inputBeganConn)

			local inputEndedConn = uis.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.Space then
					Variables.SpaceHeld = false
				end
			end)
			maid:GiveTask(inputEndedConn)

			-- Heartbeat loop applies jump/ascend while space is held
			local hbConn = RunService.Heartbeat:Connect(function()
				if Variables.SpaceHeld then
					tryJumpAndAscend()
				end
			end)
			maid:GiveTask(hbConn)

			-- Rehook on respawn so it works with new character
			local charConn = Variables.Player.CharacterAdded:Connect(function()
				-- Reset state and nudge once after spawn
				Variables.SpaceHeld = false
				task.wait(0.05)
				tryJumpAndAscend()
			end)
			maid:GiveTask(charConn)
			
			-- Add cleanup tasks to the Maid
			maid:GiveTask(function() 
				Variables.RunFlag = false 
				Variables.SpaceHeld = false
			end)
		end

		-- Function to disable the module
		local function Stop()
			if not Variables.RunFlag then return end
			-- This runs all cleanup tasks: disconnects events, resets RunFlag, etc.
			Variables.Maids[ModuleName]:DoCleaning()
		end

		-- [4] UI CREATION
		-- Add a Groupbox to the "Misc" tab
		local MovementGroupbox = UI.Tabs.Main:AddLeftGroupbox("Movement")
		
		-- Add the Toggle
		local InfiniteJumpToggle = MovementGroupbox:AddToggle("InfiniteJumpToggle", {
			Text = "Infinite Jump",
			Tooltip = "Hold Spacebar to fly upwards.",
			Default = false,
		})
		
		-- [5] UI WIRING
		-- Connect the Toggle to Start/Stop
		local function OnChanged(Value)
			if Value then
				Start()
			else
				Stop()
			end
		end
		
		-- Connect the event (do NOT give to maid, per your dev guide)
		InfiniteJumpToggle:OnChanged(OnChanged)
		
		-- Apply current state on load
		OnChanged(InfiniteJumpToggle.Value)

		-- [6] RETURN MODULE
		-- This is required by the loader to manage the module
		return { Name = ModuleName, Stop = Stop }
	end
end
