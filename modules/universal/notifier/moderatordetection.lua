-- "modules/universal/notifier/moderatordetection.lua",
do
	return function(UI)
		-- [1] LOAD DEPENDENCIES
		local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
		local GlobalEnv = (getgenv and getgenv()) or _G
		local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

		-- [2] MODULE STATE
		local ModuleName = "ModeratorDetection" -- Unique name for this module
		local Variables = {
			Maids = { [ModuleName] = Maid.new() },
			ModeratorDetectionRunFlag = false,

			-- Toggle states
			ModeratorDetectionDetectByNotifier = false, -- set by the "Moderator Detection" toggle
			ModeratorDetectionDetectByKick = false, -- set by the "Kick on Detection" toggle
			ModeratorDetectionKickOnDetection = false, -- kicks when a target is detected
			-- Optional direct user-id hits
			ModeratorDetectionUserIds = {}, -- e.g. {12345, 67890}
			-- Per-group targets (names and/or ranks)
			ModeratorDetectionGroupTargets = {
				{
					GroupId = 2648514, -- Whatever Floats Your Boat Rbx Group
					RoleNames = { "Group Moderators", "Group Staff", "Community Manager", "Game Creator" },
					Ranks = {}, -- e.g., {200, 230, 240, 255}
				},
				{
					GroupId = 16837440, -- Studio Koi Koi Rbx Group
					RoleNames = { "Moderator", "Developer", "Owner" },
					Ranks = {}, -- e.g., {200, 230, 240, 255}
				},
			},
			-- Runtime
			ModeratorDetectionCompiledTargets = {}, -- [groupId] = { RoleNamesSet = {}, RanksSet = {} }
			ModeratorDetectionKnownModerators = {}, -- [Player] = true
			ModeratorDetectionNotifications = {}, -- [Player] = Obsidian Notification handle
		}

		-- [3] CORE LOGIC
		
		-- Helper functions from original script
		local function ListenToPlayersAdded(listener)
			local function onAdded(pl) task.spawn(listener, pl) end
			local existing = RbxService.Players:GetPlayers()
			for i = 1, #existing do task.spawn(onAdded, existing[i]) end
			return RbxService.Players.PlayerAdded:Connect(onAdded)
		end

		local function NormalizeRoleName(s)
			if type(s) ~= "string" then return "" end
			return (s:gsub("^%s+", ""):gsub("%s+$", "")):lower()
		end

		local function BuildSet(arr, transform)
			local set = {}
			if type(arr) ~= "table" then return set end
			for i = 1, #arr do
				local k = transform and transform(arr[i]) or arr[i]
				if k ~= nil then set[k] = true end
			end
			return set
		end

		local function CompileGroupTargets()
			Variables.ModeratorDetectionCompiledTargets = {}
			local targets = Variables.ModeratorDetectionGroupTargets or {}
			for i = 1, #targets do
				local t = targets[i]
				local gid = tonumber(t.GroupId)
				if gid and gid > 0 then
					Variables.ModeratorDetectionCompiledTargets[gid] = {
						RoleNamesSet = BuildSet(t.RoleNames, NormalizeRoleName),
						RanksSet = BuildSet(t.Ranks),
					}
				end
			end
		end

		local function SafeIsInGroup(player, groupId)
			local ok, res = pcall(player.IsInGroup, player, groupId)
			return ok and res == true
		end
		local function SafeGetRole(player, groupId)
			local ok, res = pcall(player.GetRoleInGroup, player, groupId)
			return ok and type(res) == "string" and res or nil
		end
		local function SafeGetRank(player, groupId)
			local ok, res = pcall(player.GetRankInGroup, player, groupId)
			return ok and type(res) == "number" and res or 0
		end

		local function IsModerator(player)
			if not player then return false end
			if player == RbxService.Players.LocalPlayer then return false end

			local ids = Variables.ModeratorDetectionUserIds or {}
			for i = 1, #ids do
				if tonumber(ids[i]) == tonumber(player.UserId) then return true end
			end

			local compiled = Variables.ModeratorDetectionCompiledTargets or {}
			for gid, filters in pairs(compiled) do
				if SafeIsInGroup(player, gid) then
					local byName = filters.RoleNamesSet and next(filters.RoleNamesSet) ~= nil
					local byRank = filters.RanksSet and next(filters.RanksSet) ~= nil
					if (not byName and not byRank) then
						return true -- any member qualifies if no filters supplied
					end
					if byName then
						local role = SafeGetRole(player, gid)
						if role and filters.RoleNamesSet[NormalizeRoleName(role)] then return true end
					end
					if byRank then
						local rank = SafeGetRank(player, gid)
						if filters.RanksSet[rank] then return true end
					end
				end
			end
			return false
		end

		-- Obsidian persistent card (visibility only; kick logic ignores this)
		local function OpenPersistentNotificationFor(player)
			if Variables.ModeratorDetectionNotifications[player] then return end
			
			-- Use the 'UI' object passed into the module (which is the Library)
			local Notification = UI:Notify({
				Title = "Moderator Detected",
				Description = ("Detected %s in this server."):format(player.Name),
				Persist = true,
			})
			if Notification then
				Variables.ModeratorDetectionNotifications[player] = Notification
				
				-- Give the cleanup task directly to the module's Maid
				Variables.Maids[ModuleName]:GiveTask(function() 
					pcall(function() Notification:Destroy() end) 
				end)
			end
		end
		local function ClosePersistentNotificationFor(player)
			local Notification = Variables.ModeratorDetectionNotifications[player]
			if Notification then
				pcall(function() Notification:Destroy() end)
				Variables.ModeratorDetectionNotifications[player] = nil
			end
		end

		local function KickLocalNow()
			if not Variables.ModeratorDetectionKickOnDetection then return end
			local lp = RbxService.Players.LocalPlayer
			if lp then pcall(function() lp:Kick("Moderator detected. Leaving.") end) end
		end

		local function OnPlayerAdded(player)
			if not Variables.ModeratorDetectionRunFlag then return end
			if not IsModerator(player) then return end

			if not Variables.ModeratorDetectionKnownModerators[player] then
				Variables.ModeratorDetectionKnownModerators[player] = true
				-- Only show notification when user enabled the notifier toggle
				if Variables.ModeratorDetectionDetectByNotifier then
					OpenPersistentNotificationFor(player)
				end
			end

			-- Kick purely based on detection + kick toggle
			KickLocalNow()
		end

		local function OnPlayerRemoving(player)
			if Variables.ModeratorDetectionKnownModerators[player] then
				Variables.ModeratorDetectionKnownModerators[player] = nil
				ClosePersistentNotificationFor(player)
			end
		end

		local function ShouldRunDetection()
			return Variables.ModeratorDetectionDetectByNotifier or Variables.ModeratorDetectionDetectByKick
		end

		local function Rescan()
			local players = RbxService.Players:GetPlayers()
			for i = 1, #players do
				local pl = players[i]
				if IsModerator(pl) then
					-- remember + show card only if notifier is enabled
					if not Variables.ModeratorDetectionKnownModerators[pl] then
						Variables.ModeratorDetectionKnownModerators[pl] = true
						if Variables.ModeratorDetectionRunFlag and Variables.ModeratorDetectionDetectByNotifier then
							OpenPersistentNotificationFor(pl)
						end
					end
					-- kick purely based on detection + kick toggle
					KickLocalNow()
					-- one kick is enough
					break
				end
			end
		end

		-- Function to enable the module
		local function Start()
			if Variables.ModeratorDetectionRunFlag then return end
			Variables.ModeratorDetectionRunFlag = true
			Variables.ModeratorDetectionKnownModerators = {}
			Variables.ModeratorDetectionNotifications = {}
			CompileGroupTargets()

			local addedConn = ListenToPlayersAdded(OnPlayerAdded) -- primes existing, then listens
			local removingConn = RbxService.Players.PlayerRemoving:Connect(OnPlayerRemoving)
			
			-- Give tasks to the Maid
			Variables.Maids[ModuleName]:GiveTask(addedConn)
			Variables.Maids[ModuleName]:GiveTask(removingConn)
			Variables.Maids[ModuleName]:GiveTask(function() 
				Variables.ModeratorDetectionRunFlag = false 
				
				-- Also clean up any remaining notifications just in case
				for pl, notif in pairs(Variables.ModeratorDetectionNotifications) do
					pcall(function() notif:Destroy() end)
					Variables.ModeratorDetectionNotifications[pl] = nil
				end
				Variables.ModeratorDetectionKnownModerators = {}
			end)
		end

		-- Function to disable the module
		local function Stop()
			-- Prevent running if already stopped
			if not Variables.ModeratorDetectionRunFlag then return end
			Variables.ModeratorDetectionRunFlag = false
			
			-- This runs all cleanup tasks: disconnects events, runs the flag reset, etc.
			Variables.Maids[ModuleName]:DoCleaning()
		end

		-- [4] UI CREATION
		
		-- A. Add a Groupbox to the correct tab
		-- (Using the original script's "Main" tab and "Right" groupbox)
		local NotifiersGroupBox = UI.Tabs.Main:AddRightGroupbox("Notifiers", "bell-ring")
		
		-- B. Add the Toggles
		local ModeratorDetectionToggle = NotifiersGroupBox:AddToggle("ModeratorDetectionToggle", {
			Text = "Moderator Detection",
			Tooltip = "Sends a notification when a moderator is detected in game.",	
			DisabledTooltip = "Feature Disabled!",	
			Default = false,	
			Disabled = false,	
			Visible = true,	
			Risky = false,	
		})
		local ModeratorDetectionKickToggle = NotifiersGroupBox:AddToggle("ModeratorDetectionKickToggle", {
			Text = "Kick on Detection",
			Tooltip = "Automatically kicks when a moderator is detected in game.",	
			DisabledTooltip = "Feature Disabled!",	
			Default = false,	
			Disabled = false,	
			Visible = true,	
			Risky = false,	
		})
		
		-- C. Connect the Toggles to Start/Stop
		ModeratorDetectionToggle:OnChanged(function(enabled)
			Variables.ModeratorDetectionDetectByNotifier = (enabled == true)
		
			if ShouldRunDetection() then
				if not Variables.ModeratorDetectionRunFlag then
					Start()
				end
			else
				Stop()
			end
		end)
		
		-- Kick toggle (also activates detection engine by itself)
		ModeratorDetectionKickToggle:OnChanged(function(enabled)
			Variables.ModeratorDetectionKickOnDetection = (enabled == true)
			Variables.ModeratorDetectionDetectByKick = (enabled == true)
		
			if ShouldRunDetection() then
				if not Variables.ModeratorDetectionRunFlag then
					Start()
				end
				-- retroactive: if a target is already present, kick now
				Rescan()
			else
				-- only stop if notifier is also off
				Stop()
			end
		end)

		-- [5] RETURN MODULE
		-- This is required by the loader to manage the module
		return { Name = ModuleName, Stop = Stop }
	end
end
