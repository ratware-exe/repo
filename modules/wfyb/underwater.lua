-- "modules/fire_underwater.lua"
do
	return function(UI)
		-- [1] LOAD DEPENDENCIES
		local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
		local GlobalEnv = (getgenv and getgenv()) or _G
		local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
		
		-- UI/Game Services
		local Players = RbxService.Players
		local LocalPlayer = Players.LocalPlayer

		-- [2] MODULE STATE
		local ModuleName = "FireUnderwater"
		local Variables = {
			Maids = { [ModuleName] = Maid.new() },
			NotifyFunc = UI.Notify,

			-- Cannon
			CannonPatchApplied = false,
			CannonOriginalWaterLevel = nil,
			CannonHardPatchApplied = false,
			CannonPatchedFunctions = {},

			-- Desync
			DesyncEnabled = false,
			CharacterParts = {},
			DesyncThread = nil,
		}

		-- [3] CORE LOGIC

		-- == Helper: Notifier ==
		local function notify(msg)
			if Variables.NotifyFunc then
				pcall(Variables.NotifyFunc, msg)
			else
				print(msg) -- Fallback
			end
		end
		Variables.notify = notify -- Assign to Variables table for legacy scripts

		-- == Helper: Nevermore ==
		local function getNevermore()
			return require(RbxService.ReplicatedStorage:WaitForChild("Nevermore"))
		end

		local function getGameConstants()
			local nm = getNevermore()
			local gc = nm("GameConstants")
			return (typeof(gc) == "table") and gc or nil
		end

		local function getModule(name)
			local nm = getNevermore()
			local ok, mod = pcall(nm, name)
			if ok and type(mod) == "table" then return mod end
			return nil
		end

		-- == Underwater Cannons: Soft Patch ==
		function Variables.ApplyUnderwaterCannonsPatch()
			local gc = getGameConstants()
			if not gc or type(gc.WATER_LEVEL_TURRETS_AND_GUNS) ~= "number" then return end

			if Variables.CannonOriginalWaterLevel == nil then
				Variables.CannonOriginalWaterLevel = gc.WATER_LEVEL_TURRETS_AND_GUNS
			end

			gc.WATER_LEVEL_TURRETS_AND_GUNS = -1e9
			Variables.CannonPatchApplied = true
			if Variables.notify then Variables.notify("Underwater Cannons (Const): [ON].") end
		end

		function Variables.RevertUnderwaterCannonsPatch()
			if not Variables.CannonPatchApplied then return end
			local gc = getGameConstants()
			if gc and type(Variables.CannonOriginalWaterLevel) == "number" then
				gc.WATER_LEVEL_TURRETS_AND_GUNS = Variables.CannonOriginalWaterLevel
			end
			Variables.CannonPatchApplied = false
			if Variables.notify then Variables.notify("Underwater Cannons (Const): [OFF].") end
		end

		-- == Underwater Cannons: Hard Patch ==
		function Variables.ApplyUnderwaterCannonsHardPatch()
			if Variables.CannonHardPatchApplied then
				if Variables.notify then Variables.notify("Underwater Cannons (Hard): already ON.") end
				return
			end

			Variables.CannonPatchedFunctions = Variables.CannonPatchedFunctions or {}

			local targets = {
				{ name = "ProjectileOutputBase", methods = { "IsUnderWater", "IsBelowWater", "IsBelowWaterLevel" } },
				{ name = "GunAimer", methods = { "IsUnderWater", "IsBelowWater", "IsBelowWaterLevel" } },
				{ name = "CannonClient", methods = { "IsUnderWater", "IsBelowWater", "IsBelowWaterLevel", "CanFire", "CanShoot" } },
			}

			local patchedCount = 0

			for _, entry in ipairs(targets) do
				local mod = getModule(entry.name)
				if type(mod) == "table" then
					for _, method in ipairs(entry.methods) do
						local fn = rawget(mod, method)
						if type(fn) == "function" then
							-- Save original once
							table.insert(Variables.CannonPatchedFunctions, {
								moduleName = entry.name,
								methodName = method,
								original = fn,
							})

							-- Replace with permissive shim
							if method == "CanFire" or method == "CanShoot" then
								mod[method] = function(...) return true end
							else
								mod[method] = function(...) return false end
							end
							patchedCount += 1
						end
					end
				end
			end

			Variables.CannonHardPatchApplied = patchedCount > 0
			if Variables.notify then
				if Variables.CannonHardPatchApplied then
					Variables.notify(("Underwater Cannons (Hard): [ON] (%d hooks)."):format(patchedCount))
				else
					Variables.notify("Underwater Cannons (Hard): no targets found (safe no-op).")
				end
			end
		end

		function Variables.RevertUnderwaterCannonsHardPatch()
			if not Variables.CannonHardPatchApplied then return end
			local list = Variables.CannonPatchedFunctions
			if type(list) ~= "table" then return end

			local restored = 0
			for i = #list, 1, -1 do
				local item = list[i]
				local mod = getModule(item.moduleName)
				if type(mod) == "table" and type(item.original) == "function" then
					mod[item.methodName] = item.original
					restored += 1
				end
				table.remove(list, i) -- Use table.remove to safely remove
			end

			Variables.CannonHardPatchApplied = false
			if Variables.notify then Variables.notify(("Underwater Cannons (Hard): [OFF] (%d restored)."):format(restored)) end
		end

		-- == Desync Logic (Refactored) ==
		local function UpdateCharacterParts()
			table.clear(Variables.CharacterParts)
			local character = LocalPlayer.Character
			if not character then return end

			for _, part in ipairs(character:GetDescendants()) do
				if part:IsA("BasePart") then
					table.insert(Variables.CharacterParts, part)
				end
			end
		end

		local function DesyncLoop()
			while Variables.DesyncEnabled do
				if #Variables.CharacterParts == 0 then
					UpdateCharacterParts() -- Find parts
				end
				
				for _, part in ipairs(Variables.CharacterParts) do
					if part and part.Parent then -- Check if part is still valid
						part.Anchored = true
						part.CanCollide = false
						part:SetNetworkOwner(nil)
					else
						-- Part is invalid, force a repopulate on next loop
						table.clear(Variables.CharacterParts)
						break
					end
				end
				task.wait(0.1) -- Polling rate
			end
		end

		function Variables.EnableDesync()
			if Variables.DesyncEnabled then return end
			Variables.DesyncEnabled = true
			notify("Desync: [ON].")

			UpdateCharacterParts() -- Get initial parts

			-- Start the loop
			Variables.DesyncThread = task.spawn(DesyncLoop)
			
			-- Hook to respawns to update parts list
			local maid = Variables.Maids[ModuleName]
			maid:GiveTask(LocalPlayer.CharacterAdded:Connect(function(newCharacter)
				task.wait(0.5) -- Wait for parts to load
				UpdateCharacterParts() -- Update the list for the loop to use
			end), "DesyncCharacterAdded")
		end

		function Variables.DisableDesync()
			if not Variables.DesyncEnabled then return end
			Variables.DesyncEnabled = false
			notify("Desync: [OFF].")

			-- Stop the loop
			if Variables.DesyncThread then
				task.cancel(Variables.DesyncThread)
				Variables.DesyncThread = nil
			end

			-- Remove the respawn hook
			Variables.Maids[ModuleName]:Clean("DesyncCharacterAdded")
		end

		function Variables.DisableDesync()
			if not Variables.DesyncEnabled then return end
			Variables.DesyncEnabled = false
			notify("Desync: [OFF].")

			-- Stop the loop
			local threadToCancel = Variables.DesyncThread -- Get local reference
			Variables.DesyncThread = nil -- Set to nil *before* cancelling to prevent race condition

			if threadToCancel then
				task.cancel(threadToCancel) -- Cancel the local reference
			end

			-- Remove the respawn hook
			Variables.Maids[ModuleName]:Clean("DesyncCharacterAdded")

		-- == Main Control Functions ==
		local function EnableAllFeatures()
			Variables.ApplyUnderwaterCannonsPatch()
			Variables.ApplyUnderwaterCannonsHardPatch()
			Variables.EnableDesync()
		end

		local function DisableAllFeatures()
			Variables.RevertUnderwaterCannonsHardPatch()
			Variables.RevertUnderwaterCannonsPatch()
			Variables.DisableDesync()
		end

		-- == Module Stop Function ==
		local function Stop()
			DisableAllFeatures() -- This unpatches and stops the loop
			Variables.Maids[ModuleName]:DoCleaning() -- This cleans up CharacterAdded + OnChanged
		end

		-- [4] UI CREATION
		-- Create the UI elements this module needs
		local RemovalGroupBox = UI.Tabs.Main:AddLeftGroupbox("Removals")
		
		local NoWaterHeightToggle = RemovalGroupBox:AddToggle("NoWaterHeightToggle", {
			Text = "Fire Underwater",
			Tooltip = "Fire weapons underwater & desyncs physics.",
			DisabledTooltip = "Feature Disabled!",
			Default = false,
			Disabled = false,
			Visible = true,
			Risky = false,
		})


		-- [5] UI WIRING
		-- Now that 'NoWaterHeightToggle' is created, we can hook into it
		local maid = Variables.Maids[ModuleName]
		
		local function OnChanged(Value)
			if Value then
				EnableAllFeatures()
			else
				DisableAllFeatures()
			end
		end
		
		-- Give the connection to the maid so it's cleaned up on Stop()
		maid:GiveTask(NoWaterHeightToggle:OnChanged(OnChanged))
		
		-- Apply current state on load
		OnChanged(NoWaterHeightToggle.Value)
		
		-- [6] RETURN MODULE
		return { Name = ModuleName, Stop = Stop }
	end
end
