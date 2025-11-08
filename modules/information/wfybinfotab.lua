-- "modules/information/wfybinfotab.lua"
do
	return function(UI)
		-- [1] LOAD DEPENDENCIES
		local GlobalEnv = (getgenv and getgenv()) or _G
		local Maid = GlobalEnv.Maid
		local RbxService = GlobalEnv.RbxService
		
		-- Access UI components
		local Library = UI.Library
		local Tabs = UI.Tabs
		
		-- [2] MODULE STATE
		local ModuleName = "Info"
		local Variables = GlobalEnv.Variables
		
		-- Ensure the global maid table exists for this module
		Variables.Maids[ModuleName] = Variables.Maids[ModuleName] or Maid.new()
		local InfoMaid = Variables.Maids[ModuleName]

		-- [3] UI CREATION & LOGIC
		-- This block is self-contained and runs immediately
		do
			pcall(function()
				local PlayersService = RbxService.Players
				local HttpService = RbxService.HttpService
				local ContentProvider = RbxService.ContentProvider
				local LocalizationService = RbxService.LocalizationService
				local UserInputService = RbxService.UserInputService
				local StatsService = RbxService.Stats
				local Workspace = RbxService.Workspace
				local os_time = os.time
				local os_date = os.date
				local math_floor = math.floor
				local string_format = string.format
				local string_match = string.match
				local pcall = pcall
				local type = type
				local tostring = tostring
				local tonumber = tonumber
				local setclipboard = setclipboard
				local task_spawn = task.spawn
				local task_wait = task.wait
				local localPlayer = PlayersService.LocalPlayer
				local sessionStartTime = os_time()
				local PlayerInfoBox = Tabs.Info:AddLeftGroupbox("Player", "user")
				local ServerInfoBox = Tabs.Info:AddRightGroupbox("Server", "server")
				local ScriptInfoBox = Tabs.Info:AddRightGroupbox("Script", "file-text")
				local initialAvatarUrl
				do
					local fetchSuccess, fetchedUrl = pcall(PlayersService.GetUserThumbnailAsync, PlayersService,
						localPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
					if fetchSuccess and type(fetchedUrl) == "string" and #fetchedUrl > 0 then
						initialAvatarUrl = fetchedUrl
						pcall(ContentProvider.PreloadAsync, ContentProvider, { fetchedUrl })
					end
				end
				local PlayerAvatarImage = PlayerInfoBox:AddImage("PlayerAvatar", {
					Image = initialAvatarUrl or "user",
					Height = 180,
					ScaleType = Enum.ScaleType.Fit,
				})
				PlayerInfoBox:AddDivider()
				local UsernameLabel = PlayerInfoBox:AddLabel("UsernameLabel", { Text = string_format("<b>Username:</b> %s", localPlayer.Name) })
				local DisplayNameLabel = PlayerInfoBox:AddLabel("DisplayNameLabel", { Text = string_format("<b>Display Name:</b> %s", localPlayer.DisplayName) })
				local UserIdLabel = PlayerInfoBox:AddLabel("UserIdLabel", { Text = string_format("<b>User ID:</b> %d", localPlayer.UserId) })
				local AccountAgeLabel = PlayerInfoBox:AddLabel("AccountAgeLabel", { Text = string_format("<b>Account Age:</b> %d days", localPlayer.AccountAge or 0) })
				local JoinDateLabel = PlayerInfoBox:AddLabel("JoinDateLabel", { Text = "<b>Join Date:</b> Loading..." })
				local PremiumStatusLabel = PlayerInfoBox:AddLabel("PremiumLabel", { Text = "<b>Premium:</b> Checking..." })
				local LocaleLabel = PlayerInfoBox:AddLabel("LocaleLabel", { Text = "<b>Locale:</b> " .. tostring(LocalizationService.RobloxLocaleId or "Unknown") })
				local DeviceTypeLabel = PlayerInfoBox:AddLabel("DeviceLabel", { Text = "<b>Device:</b> Checking..." })
				local PingLabel = PlayerInfoBox:AddLabel("PingLabel", { Text = "<b>Ping:</b> — ms" })
				local SessionTimeLabel = PlayerInfoBox:AddLabel("SessionLabel", { Text = "<b>Session:</b> 00:00:00" })
				PlayerInfoBox:AddButton("Copy User ID", function()
					local success = pcall(setclipboard, tostring(localPlayer.UserId))
					if Library and Library.Notify then
						Library:Notify(success and "Copied User ID" or string_format("User ID: %d", localPlayer.UserId), 3)
					end
				end)
				local PlaceIdLabel = ServerInfoBox:AddLabel("PlaceIdLabel", { Text = string_format("<b>Place Id:</b> %d", game.PlaceId) })
				local JobIdLabel = ServerInfoBox:AddLabel("JobIdLabel", { Text = string_format("<b>Job Id:</b> %s", game.JobId) })
				local PlayerCountLabel = ServerInfoBox:AddLabel("PlayersLabel", { Text = "<b>Players:</b> Loading..." })
				local ServerTypeLabel = ServerInfoBox:AddLabel("ServerTypeLabel", { Text = "<b>Server Type:</b> Checking..." })
				local ServerAgeLabel = ServerInfoBox:AddLabel("ServerAgeLabel", { Text = "<b>Server Age:</b> 00:00:00" })
				ServerInfoBox:AddButton("Copy Job Id", function()
					local success = pcall(setclipboard, tostring(game.JobId))
					if Library and Library.Notify then
						Library:Notify(success and "Copied Job Id" or string_format("Job Id: %s", game.JobId), 3)
					end
				end)
				ScriptInfoBox:AddLabel("ScriptInfo", {
					Text = "<u><b>WFYB Exploits Update Log:</b></u> <b>\n•</b> Version: WFYB.GG ☁️ <b>\n•</b> Last Update: Oct 18, 2025",
					DoesWrap = true,
				})
				ScriptInfoBox:AddLabel("ScriptUpdateNotes", {
					Text = "<u><b>Notes:</b></u> <b>\n•</b> Fix compatiblilty with Wave & Zenith. <b>\n•</b> Added vip server commands & heavily optimized the obfuscation method to reduce lag. <b>\n•</b> If there are any bugs, report them to @WFYBExploits by commenting on any of the uploaded youtube videos. Enjoy!",
					DoesWrap = true,
				})
				do
					PremiumStatusLabel:SetText(string_format("<b>Premium:</b> %s",
						localPlayer.MembershipType == Enum.MembershipType.Premium and "Yes" or "No"))
					local currentDevice = "PC"
					if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
						currentDevice = "Mobile"
					elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
						currentDevice = "Console"
					end
					DeviceTypeLabel:SetText("<b>Device:</b> " .. currentDevice)
				end
				InfoMaid:GiveTask(task_spawn(function()
					local joinDateString = nil
					local httpSuccess, responseBody = pcall(game.HttpGet, game, string_format("https://users.roblox.com/v1/users/%d", localPlayer.UserId))
					if httpSuccess and type(responseBody) == "string" and #responseBody > 0 then
						local decodeSuccess, userData = pcall(HttpService.JSONDecode, HttpService, responseBody)
						if decodeSuccess and userData and userData.created then
							local year, month, day = string_match(tostring(userData.created), "^(%d+)%-(%d+)%-(%d+)")
							if year and month and day then
								local monthNames = {"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"}
								joinDateString = string_format("%s %s, %s", monthNames[tonumber(month)] or month, day, year)
							else
								joinDateString = tostring(userData.created)
							end
						end
					end
					if not joinDateString then
						local approxJoinTimestamp = os_time() - ((localPlayer.AccountAge or 0) * 86400)
						joinDateString = os_date("%b %d, %Y", approxJoinTimestamp)
					end
					JoinDateLabel:SetText("<b>Join Date:</b> " .. joinDateString)
				end))
				InfoMaid:GiveTask(task_spawn(function()
					local function parseMilliseconds(rawValue)
						if type(rawValue) == "number" then
							return math_floor(rawValue + 0.5)
						elseif type(rawValue) == "string" then
							local numStr = string_match(rawValue, "([%d%.]+)")
							if numStr then
								local numVal = tonumber(numStr)
								if numVal then return math_floor(numVal + 0.5) end
							end
						end
						return nil
					end
					local function getCurrentPing()
						local statsInstance = StatsService
						if not statsInstance then return nil end
						local performanceStats = statsInstance.PerformanceStats
						if performanceStats and performanceStats.Ping then
							local success, value = pcall(function()
								if performanceStats.Ping.GetValue then return performanceStats.Ping:GetValue() end
								if performanceStats.Ping.GetValueString then return performanceStats.Ping:GetValueString() end
								return performanceStats.Ping.Value
							end)
							if success then
								local ms = parseMilliseconds(value)
								if ms then return ms end
							end
						end
						local dataPingItem = statsInstance.Network and statsInstance.Network.ServerStatsItem and statsInstance.Network.ServerStatsItem["Data Ping"]
						if dataPingItem then
							local success, value = pcall(function()
								if dataPingItem.GetValueString then return dataPingItem:GetValueString() end
								if dataPingItem.GetValue then return dataPingItem:GetValue() end
								return dataPingItem.Value
							end)
							if success then
								local ms = parseMilliseconds(value)
								if ms then return ms end
							end
						end
						return nil
					end
					local function formatTime(totalSeconds)
						local hours = math_floor(totalSeconds / 3600)
						local minutes = math_floor((totalSeconds % 3600) / 60)
						local seconds = math_floor(totalSeconds % 60) 
						return string_format("%02d:%02d:%02d", hours, minutes, seconds)
					end
					while task_wait(1) do
						local currentPing = getCurrentPing()
						if currentPing then
							PingLabel:SetText(string_format("<b>Ping:</b> %d ms", currentPing))
						end
						local elapsedSeconds = os_time() - sessionStartTime
						SessionTimeLabel:SetText("<b>Session:</b> " .. formatTime(elapsedSeconds))
						local serverAgeSeconds = Workspace.DistributedGameTime
						ServerAgeLabel:SetText("<b>Server Age:</b> " .. formatTime(serverAgeSeconds))
					end
				end))
				do
					pcall(function()
						local isPrivateServer = (game.PrivateServerId ~= "" and game.PrivateServerOwnerId ~= 0)
						ServerTypeLabel:SetText("<b>Server Type:</b> " .. (isPrivateServer and "Private" or "Public"))
					end)
					local function refreshPlayerCount()
						local currentPlayers = #PlayersService:GetPlayers()
						local maxPlayers = PlayersService.MaxPlayers or 0
						PlayerCountLabel:SetText(string_format("<b>Players:</b> %d / %d", currentPlayers, maxPlayers))
					end
					refreshPlayerCount()
					InfoMaid:GiveTask(PlayersService.PlayerAdded:Connect(refreshPlayerCount))
					InfoMaid:GiveTask(PlayersService.PlayerRemoving:Connect(refreshPlayerCount))
				end
			end)
		end
		
		-- [4] RETURN MODULE
		-- This module just runs, its cleanup is handled by the global maid
		local function Stop()
			pcall(function() Variables.Maids.Info:DoCleaning() end)
		end
		
		return { Name = ModuleName, Stop = Stop }
	end
end
