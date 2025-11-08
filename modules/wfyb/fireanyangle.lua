-- "modules/wfyb/fireanyangle.lua",
do
	return function(UI)
		-- [1] LOAD DEPENDENCIES
		local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
		local GlobalEnv = (getgenv and getgenv()) or _G
		local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
		
		-- [2] MODULE STATE
		local ModuleName = "AnyAngleCannons"
		local Variables = {
			Maids = { [ModuleName] = Maid.new() },
			NotifyFunc = UI.Notify,

			-- Any-Angle cannons (15° floor remover)
			AnglePatchApplied = false,
			AnglePatchedFunctions = {},
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

		-- == Helper: Nevermore ==
		local function getNevermore()
			return require(RbxService.ReplicatedStorage:WaitForChild("Nevermore"))
		end
		
		local function getModule(name)
			local nm = getNevermore()
			local ok, mod = pcall(nm, name)
			return (ok and type(mod) == "table") and mod or nil
		end

		-- == Any-Angle Cannons Logic ==
		local function ApplyAnyAngleCannonsPatch()
			if Variables.AnglePatchApplied then
				notify("Any-Angle Cannons: already [ON].")
				return
			end
			Variables.AnglePatchedFunctions = Variables.AnglePatchedFunctions or {}

			local OutputBase = getModule("ProjectileOutputBase")
			if type(OutputBase) == "table" and type(OutputBase.IsPointingDown) == "function" then
				table.insert(Variables.AnglePatchedFunctions, { module = OutputBase, key = "IsPointingDown", original = OutputBase.IsPointingDown })
				OutputBase.IsPointingDown = function(...) return false end -- allow any elevation
				Variables.AnglePatchApplied = true
				notify("Any-Angle Cannons: [ON].")
			else
				notify("Any-Angle Cannons: target not found (no-op).")
			end
		end

		local function RevertAnyAngleCannonsPatch()
			if not Variables.AnglePatchApplied then return end -- Check run flag
			if not Variables.AnglePatchedFunctions then return end
			
			for i = #Variables.AnglePatchedFunctions, 1, -1 do
				local rec = Variables.AnglePatchedFunctions[i]
				if rec.module and rec.key and rec.original then
					rec.module[rec.key] = rec.original
				end
				table.remove(Variables.AnglePatchedFunctions, i)
			end
			
			Variables.AnglePatchApplied = false
			notify("Any-Angle Cannons: [OFF].")
		end

		-- == Module Stop Function ==
		local function Stop()
			RevertAnyAngleCannonsPatch() -- This unpatches
			Variables.Maids[ModuleName]:DoCleaning() -- This cleans up any other tasks
		end

		-- [4] UI CREATION
		-- Find or create the "Removals" groupbox (deduplicated by UIRegistry)
		local RemovalGroupBox = UI.Tabs.Main:AddLeftGroupbox("Removals")
		
		-- Add the new toggle
		local AnyAngleCannonsToggle = RemovalGroupBox:AddToggle("AnyAngleCannonsToggle", {
			Text = "Any-Angle Cannons",
			Tooltip = "Remove the 15° angle limit; shoot at any elevation.",
			Default = false,
			Disabled = false,
			Visible = true,
			Risky = false,
		})

		-- [5] UI WIRING
		-- Hook the toggle to the Start/Stop functions
		local function OnChanged(Value)
			if Value then
				ApplyAnyAngleCannonsPatch()
			else
				RevertAnyAngleCannonsPatch()
			end
		end
		
		-- Connect the event (do NOT give to maid, per our previous fix)
		AnyAngleCannonsToggle:OnChanged(OnChanged)
		
		-- Apply current state on load
		OnChanged(AnyAngleCannonsToggle.Value)
		
		-- [6] RETURN MODULE
		return { Name = ModuleName, Stop = Stop }
	end
end
