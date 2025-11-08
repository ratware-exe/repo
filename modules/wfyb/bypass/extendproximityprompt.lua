-- "modules/wfyb/bypass/extendproximityprompt.lua",
do
	return function(UI)
		-- [1] LOAD DEPENDENCIES
		local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
		local GlobalEnv = (getgenv and getgenv()) or _G
		local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
		
		-- [2] MODULE STATE
		local ModuleName = "ExtendProximityPrompt"
		local Variables = {
			Maids = { [ModuleName] = Maid.new() },
			NotifyFunc = UI.Notify,
			RunFlag = false, -- Tracks if the module is active
			
			-- Nevermore modules
			L = nil,
			TriggerClient = nil,
			TriggerConstants = nil,
			ClientBinders = nil,
			CooldownConstants = nil,
			
			-- Config from original script
			DEFAULT_WEAPON_COOLDOWN = 2.0,
			GLOBAL_PAD = 0.40,
			FALLBACK_COOLDOWN = 0, -- Will be set in Start()
			
			-- Backups
			Originals = {
				Activate = nil,
				MAX_TRIGGER_DISTANCE = nil,
				MAX_VIEW_DISTANCE = nil,
				LEEWAY_DISTANCE = nil
			},
			
			-- State from original script
			GuardUntilByAttachment = {},
			SyntheticByAttachment  = {},
		}
		
		Variables.FALLBACK_COOLDOWN = Variables.DEFAULT_WEAPON_COOLDOWN + Variables.GLOBAL_PAD

		-- [3] CORE LOGIC
		
		-- == Helper: Notifier ==
		local function notify(msg)
			if Variables.NotifyFunc then
				pcall(Variables.NotifyFunc, msg)
			else
				print(msg) -- Fallback
			end
		end

		-- == Helper: Load Nevermore ==
		local function LoadNevermoreModules()
			if Variables.L then return true end -- Already loaded
			
			local ok, L = pcall(function()
				local nm = RbxService.ReplicatedStorage:WaitForChild("Nevermore")
				return require(nm)
			end)
			
			if not (ok and L) then
				notify("NoPopupCooldown: Nevermore loader not found")
				return false
			end
			
			Variables.L = L
			Variables.TriggerClient = L("TriggerClient")
			Variables.TriggerConstants = L("TriggerConstants")
			Variables.ClientBinders = L("ClientBinders")
			Variables.CooldownConstants = L("CooldownConstants")
			
			if not (Variables.TriggerClient and Variables.TriggerConstants and Variables.ClientBinders and Variables.CooldownConstants) then
				notify("NoPopupCooldown: Failed to load Nevermore modules")
				return false
			end
			
			return true
		end

		-- == Helpers from Original Script (Adapted) ==
		local function getObj(trig)
			local o
			pcall(function() if typeof(trig.GetObject) == "function" then o = trig:GetObject() end end)
			if not o then pcall(function() o = trig._obj end) end
			return o -- Attachment
		end

		local function computeSecondsFromContext(att)
			-- search upwards a few levels for a NumberValue named CooldownTime
			local cur, hops = att and att.Parent, 0
			while cur and hops < 8 do
				local v = cur:FindFirstChild(Variables.CooldownConstants.COOLDOWN_TIME_NAME)
				if v and v:IsA("NumberValue") and typeof(v.Value) == "number" then
					return v.Value + Variables.GLOBAL_PAD
				end
				cur, hops = cur.Parent, hops + 1
			end
			return Variables.FALLBACK_COOLDOWN
		end

		local function bindSyntheticCooldown(att, seconds)
			if not (att and att:IsA("Attachment")) then return end

			-- If server already put a real Cooldown here, do nothing.
			if att:FindFirstChild(Variables.CooldownConstants.COOLDOWN_NAME) then return end

			-- Per-popup guard: while cooling, ignore repeats (blocks autokey spam)
			local now = os.clock()
			if Variables.GuardUntilByAttachment[att] and now < Variables.GuardUntilByAttachment[att] then
				return
			end
			Variables.GuardUntilByAttachment[att] = now + seconds

			local cooldownBinder = Variables.ClientBinders and Variables.ClientBinders.Cooldown
			if not cooldownBinder then return end

			-- Create & bind BEFORE parenting so CooldownClient hooks instantly
			local nv = Instance.new("NumberValue")
			nv.Name = Variables.CooldownConstants.COOLDOWN_NAME
			nv.Value = seconds
			pcall(function() cooldownBinder:BindClient(nv) end)

			local start = Instance.new("NumberValue")
			start.Name = Variables.CooldownConstants.COOLDOWN_START_TIME_NAME
			start.Value = RbxService.Workspace:GetServerTimeNow()
			start.Parent = nv

			nv.Parent = att
			Variables.SyntheticByAttachment[att] = nv

			-- If a real server Cooldown shows up later, drop ours immediately
			local conn; conn = att.ChildAdded:Connect(function(ch)
				if ch.Name == Variables.CooldownConstants.COOLDOWN_NAME and ch ~= nv then
					if Variables.SyntheticByAttachment[att] == nv and nv.Parent then nv:Destroy() end
					Variables.SyntheticByAttachment[att] = nil
					if conn then conn:Disconnect() end
				end
			end)

			-- Hard cleanup: prevents any chance of “infinite cooldown”
			local delayMaid = Maid.new()
			delayMaid:GiveTask(conn)
			delayMaid:GiveTask(task.delay(seconds + 0.10, function()
				if Variables.SyntheticByAttachment[att] == nv and nv.Parent then nv:Destroy() end
				Variables.SyntheticByAttachment[att] = nil
				delayMaid:DoCleaning()
			end))
			
			-- Give this temporary maid to the main module maid
			Variables.Maids[ModuleName]:GiveTask(delayMaid)
		end
		
		-- == Hook Function ==
		local function HookedActivate(self, ...)
			local origActivate = Variables.Originals.Activate
			
			-- Call the real implementation first.
			local ok, res = pcall(origActivate, self, ...)

			-- If module is OFF, or activation failed, just return the original result.
			if not Variables.RunFlag or not ok or res == nil then
				return res
			end

			-- Module is ON and activation succeeded, apply our logic
			local att = getObj(self)
			if att then
				-- If a real Cooldown isn't present, add a synthetic one
				if not att:FindFirstChild(Variables.CooldownConstants.COOLDOWN_NAME) then
					local secs = computeSecondsFromContext(att)
					bindSyntheticCooldown(att, secs)
				end
			end

			return res
		end

		-- == Main Control Functions ==
		local function Start()
			if Variables.RunFlag then return end
			
			if not LoadNevermoreModules() then
				notify("NoPopupCooldown: Aborting Start(), modules not found.")
				return
			end
			
			Variables.RunFlag = true
			
			-- Backup originals
			Variables.Originals.MAX_TRIGGER_DISTANCE = Variables.TriggerConstants.MAX_TRIGGER_DISTANCE
			Variables.Originals.MAX_VIEW_DISTANCE = Variables.TriggerConstants.MAX_VIEW_DISTANCE
			Variables.Originals.LEEWAY_DISTANCE = Variables.TriggerConstants.LEEWAY_DISTANCE
			Variables.Originals.Activate = Variables.TriggerClient.Activate
			
			-- Apply patches
			Variables.TriggerConstants.MAX_TRIGGER_DISTANCE = 800
			Variables.TriggerConstants.MAX_VIEW_DISTANCE = 1200
			Variables.TriggerConstants.LEEWAY_DISTANCE = 40
			Variables.TriggerClient.Activate = HookedActivate
			
			notify("No Popup Cooldown: [ON]")
		end

		local function Stop()
			if not Variables.RunFlag then return end
			Variables.RunFlag = false
			
			-- Restore originals
			if Variables.TriggerClient and Variables.Originals.Activate then
				Variables.TriggerClient.Activate = Variables.Originals.Activate
			end
			if Variables.TriggerConstants then
				if Variables.Originals.MAX_TRIGGER_DISTANCE then
					Variables.TriggerConstants.MAX_TRIGGER_DISTANCE = Variables.Originals.MAX_TRIGGER_DISTANCE
				end
				if Variables.Originals.MAX_VIEW_DISTANCE then
					Variables.TriggerConstants.MAX_VIEW_DISTANCE = Variables.Originals.MAX_VIEW_DISTANCE
				end
				if Variables.Originals.LEEWAY_DISTANCE then
					Variables.TriggerConstants.LEEWAY_DISTANCE = Variables.Originals.LEEWAY_DISTANCE
				end
			end
			
			-- Clean up any active synthetic cooldowns
			for att, nv in pairs(Variables.SyntheticByAttachment) do
				if nv and nv.Parent then
					pcall(nv.Destroy, nv)
				end
			end
			
			-- Clear state
			table.clear(Variables.GuardUntilByAttachment)
			table.clear(Variables.SyntheticByAttachment)
			
			-- Clear backups
			Variables.Originals = {}
			
			Variables.Maids[ModuleName]:DoCleaning()
			notify("No Popup Cooldown: [OFF]")
		end

		-- [4] UI CREATION
		local RemovalGroupBox = UI.Tabs.Temp:AddLeftGroupbox("Removals")
		
		local ExtendEroximityPromptToggle = RemovalGroupBox:AddToggle("ExtendProximityPromptToggle", {
			Text = "Extend Proximity Prompt",
			Tooltip = "Extend proximity prompts of any weapon.",
			Default = false,
		})
		
		-- [5] UI WIRING
		local function OnChanged(Value)
			if Value then
				Start()
			else
				Stop()
			end
		end
		
		NoPopupCooldownToggle:OnChanged(OnChanged)
		OnChanged(NoPopupCooldownToggle.Value)

		-- [6] RETURN MODULE
		return { Name = ModuleName, Stop = Stop }
	end
end
