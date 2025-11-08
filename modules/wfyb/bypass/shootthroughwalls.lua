-- "modules/wfyb/bypass/shootthroughwalls.lua"
do
	return function(UI)
		-- [1] LOAD DEPENDENCIES
		local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
		local GlobalEnv = (getgenv and getgenv()) or _G
		local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
		
		-- [2] MODULE STATE
		local ModuleName = "ShootThroughWalls"
		local Variables = {
			Maids = { [ModuleName] = Maid.new() },

			-- Shoot-Through-Walls (LOS/wall gates)
			WallsPatchApplied = false,
			WallsPatchedFunctions = {},
		}

		-- [3] CORE LOGIC

		-- == Helper: Nevermore ==
		local function getNevermore()
			return require(RbxService.ReplicatedStorage:WaitForChild("Nevermore"))
		end
		
		local function getModule(name)
			local nm = getNevermore()
			local ok, mod = pcall(nm, name)
			return (ok and type(mod) == "table") and mod or nil
		end

		-- == Shoot-Through-Walls Logic ==
		local function ApplyShootThroughWallsPatch()
      
			Variables.WallsPatchedFunctions = Variables.WallsPatchedFunctions or {}

			local patched = 0

			-- 1) GunAimer:IsClippingThroughWalls -> always false
			do
				local GunAimer = getModule("GunAimer")
				if type(GunAimer) == "table" and type(GunAimer.IsClippingThroughWalls) == "function" then
					table.insert(Variables.WallsPatchedFunctions, { module = GunAimer, key = "IsClippingThroughWalls", original = GunAimer.IsClippingThroughWalls })
					GunAimer.IsClippingThroughWalls = function(...) return false end
					patched += 1
				end
			end

			-- 2) CannonClient:_isInsideWalls -> always false
			do
				local CannonClient = getModule("CannonClient")
				if type(CannonClient) == "table" and type(CannonClient._isInsideWalls) == "function" then
					table.insert(Variables.WallsPatchedFunctions, { module = CannonClient, key = "_isInsideWalls", original = CannonClient._isInsideWalls })
					CannonClient._isInsideWalls = function(...) return false end
					patched += 1
				end
			end

			-- 3) FlamethrowerClient:_isInsideWalls -> always false (same snackbar gate)
			do
				local FlamethrowerClient = getModule("FlamethrowerClient")
				if type(FlamethrowerClient) == "table" and type(FlamethrowerClient._isInsideWalls) == "function" then
					table.insert(Variables.WallsPatchedFunctions, { module = FlamethrowerClient, key = "_isInsideWalls", original = FlamethrowerClient._isInsideWalls })
					FlamethrowerClient._isInsideWalls = function(...) return false end
					patched += 1
				end
			end

			Variables.WallsPatchApplied = patched > 0
      
		end

		local function RevertShootThroughWallsPatch()
			if not Variables.WallsPatchApplied then return end -- Check run flag
			if not Variables.WallsPatchedFunctions then return end
			
			local restored = 0
			for i = #Variables.WallsPatchedFunctions, 1, -1 do
				local rec = Variables.WallsPatchedFunctions[i]
				if rec.module and rec.key and rec.original then
					rec.module[rec.key] = rec.original
					restored += 1
				end
				table.remove(Variables.WallsPatchedFunctions, i)
			end
			
			Variables.WallsPatchApplied = false
		end

		-- == Module Stop Function ==
		local function Stop()
			RevertShootThroughWallsPatch() -- This unpatches
			Variables.Maids[ModuleName]:DoCleaning() -- This cleans up any other tasks
		end

		-- [4] UI CREATION
		-- Find or create the "Removals" groupbox (deduplicated by UIRegistry)
		local RemovalGroupBox = UI.Tabs.Main:AddLeftGroupbox("Removals")
		
		-- Add the new toggle
		local ShootThroughWallsToggle = RemovalGroupBox:AddToggle("ShootThroughWallsToggle", {
			Text = "Shoot Through Walls",
			Tooltip = "Bypass LOS/wall checks on the client.",
			Default = false,
			Disabled = false,
			Visible = true,
			Risky = false,
		})

		-- [5] UI WIRING
		-- Hook the toggle to the Start/Stop functions
		local function OnChanged(Value)
			if Value then
				ApplyShootThroughWallsPatch()
			else
				RevertShootThroughWallsPatch()
			end
		end
		
		-- Connect the event (do NOT give to maid, per our previous fix)
		ShootThroughWallsToggle:OnChanged(OnChanged)
		
		-- Apply current state on load
		OnChanged(ShootThroughWallsToggle.Value)
		
		-- [6] RETURN MODULE
		return { Name = ModuleName, Stop = Stop }
	end
end
