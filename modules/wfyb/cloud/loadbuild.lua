-- "modules/wfyb/cloud/loadbuild.lua",
do
	return function(UI)
		-- [1] LOAD DEPENDENCIES
		local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
		local GlobalEnv = (getgenv and getgenv()) or _G
		local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
		local Signal = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()
		
		-- Get UI references
		local Library = UI.Library
		local Options = UI.Options
		local Tabs = UI.Tabs
		
		-- Ensure global event exists
		GlobalEnv.CloudRefreshEvent = GlobalEnv.CloudRefreshEvent or Signal.new()
		
		-- [2] MODULE STATE
		local ModuleName = "LoadBuild"
		local Variables = {
			Maids = { [ModuleName] = Maid.new() },
			
			ButtonCooldowns = {
				Duration = 5, 
				LastLoadClick = 0,
			},
			ExportDropdownBuilds = {},
			ServerRelayBaseUrl = "https://wfyb-serverrelay.wfyb-exploits.workers.dev",
			GetServerRelayApiUrl  = function(self) return self.ServerRelayBaseUrl .. "/api" end,
			GetServerCodeUrlBuild = function(self) return self.ServerRelayBaseUrl .. "/savecode?which=serverbuild" end,
			
			serverbuild = {
				IsActive = false,
				RequestListRefresh = false,
				RequestLoad = false,
				RequestInfoUpdate = false,
				SelectedDisplayKey = nil,  
				SelectedFilename = nil,   
				FileIndexMap = {},   
				AvailableSavesDisplay = {},    
				Module = nil
			},
		}
		
		-- Create sub-maids for cleanup
		local moduleMaid = Variables.Maids[ModuleName]
		local serverBuildMaid = Maid.new()
		local uiMaid = Maid.new()
		moduleMaid:GiveTask(serverBuildMaid)
		moduleMaid:GiveTask(uiMaid)
		

		-- [3] UI CREATION
		local LoadServerBuildGroupBox = Tabs.Cloud:AddLeftGroupbox("Load Build", "cloud-download")
		LoadServerBuildGroupBox:AddDropdown("LoadServerBuildDropdown", {
			Values = Variables.ExportDropdownBuilds,
			Text = "Select Build:",
			Multi = false,
			Tooltip = "Click on target & close dropdown to confirm selection.",
			DisabledTooltip = "Feature Disabled!",
			Searchable = true,
			Disabled = false,
			Visible = true,
		})
		local LoadInfoLabels = {
			Title = LoadServerBuildGroupBox:AddLabel({Text = "<b>Information:</b>", RichText = true}),
			LoadServerBuildGroupBox:AddDivider(),
			Slot = LoadServerBuildGroupBox:AddLabel({Text = "Slot #: ---", RichText = true}),
			BoatName = LoadServerBuildGroupBox:AddLabel({Text = "Boat Name: ---", RichText = true}),
			SaveDate = LoadServerBuildGroupBox:AddLabel({Text = "Save Date: ---", RichText = true}),
			SaveTime = LoadServerBuildGroupBox:AddLabel({Text = "Save Time: ---", RichText = true}),
			PropCount = LoadServerBuildGroupBox:AddLabel({Text = "Prop Count: ---", RichText = true}),
			Cost = LoadServerBuildGroupBox:AddLabel({Text = "Cost: ---", RichText = true}),
			LoadServerBuildGroupBox:AddDivider(),
		}
		local function LoadInfoSetDefault()
			local LoadInfoColor = "'rgb(0, 208, 255)'"
			local defaultValue = "<font color=" .. LoadInfoColor .. ">---</font>"
			LoadInfoLabels.Slot:SetText("Slot #: " .. defaultValue)
			LoadInfoLabels.BoatName:SetText("Boat Name: " .. defaultValue)
			LoadInfoLabels.SaveDate:SetText("Save Date: " .. defaultValue)
			LoadInfoLabels.SaveTime:SetText("Save Time: " .. defaultValue)
			LoadInfoLabels.PropCount:SetText("Prop Count: " .. defaultValue)
			LoadInfoLabels.Cost:SetText("Cost: " .. defaultValue)
		end
		LoadInfoSetDefault()
		local LoadServerBuildButton = LoadServerBuildGroupBox:AddButton({
			Text = "Load Build",
			Func = function() end,
			DoubleClick = true,
			Tooltip = "Double click to load build from database.",
			DisabledTooltip = "Feature Disabled",
			Disabled = false,
		})
		
		-- [4] CORE LOGIC
		do
			local pcall, type, tostring, pairs, ipairs, tonumber, loadstring, select = pcall, type, tostring, pairs, ipairs, tonumber, loadstring, select
			local floor = math.floor
			local clock = os.clock
			local concat, sort = table.concat, table.sort
			local HttpService = RbxService.HttpService
			local Players = RbxService.Players
			local RunService = RbxService.RunService
			local UrlEncode = HttpService.UrlEncode
			local JSONDecode = HttpService.JSONDecode
			local HttpGet = game.HttpGet
			local serverbuildModule = {}
			local buildState = Variables.serverbuild 
			local function StyleLoadInfoLabel()
				pcall(function()
					local holder = (InfoBody and (InfoBody.Instance or InfoBody.Object or InfoBody.Frame or InfoBody.Container)) or (InfoBody and InfoBody.GetFrame and InfoBody:GetFrame())
					holder = holder or (InfoBody and InfoBody.Label) or nil
					local lbl = holder and holder:FindFirstChildWhichIsA("TextLabel", true)
					if not lbl then return end
					lbl.TextWrapped = true
					lbl.TextXAlignment = Enum.TextXAlignment.Left
					lbl.TextYAlignment = Enum.TextYAlignment.Top
					lbl.AutomaticSize = Enum.AutomaticSize.Y
					lbl.Size = UDim2.new(1, 0, 0, 0)
					lbl.ClipsDescendants = false
					if holder and holder:IsA("GuiObject") then
						holder.AutomaticSize = Enum.AutomaticSize.Y
						holder.ClipsDescendants = false
					end
				end)
			end
			local function BuildQuery(params)
				local acc = {}
				for key, value in pairs(params) do
					acc[#acc+1] = key .. "=" .. UrlEncode(HttpService, tostring(value))
				end
				return concat(acc, "&")
			end
			local function HttpGetJson(url)
				local ok, res = pcall(HttpGet, url)
				if not ok or type(res) ~= "string" or #res == 0 then
					return nil, "Failed to send fetch request to server!"
				end
				local okj, obj = pcall(JSONDecode, HttpService, res)
				if not okj or type(obj) ~= "table" then
					return nil, "Failed to decode build data!"
				end
				return obj, nil
			end
			local function Notify(text)
				pcall(function()
					if Library and Library.Notify then
						Library:Notify(text, 5)
					end
				end)
			end
			local function ParseFilenameParts(filename)
				if type(filename) ~= "string" then return nil end
				local slot, boat, date, time, props, cost = string.match(
					filename,
					"^Slot#(%d+):%s*(.-)%s*%((%d%d%d%d%-%d%d%-%d%d),%s*([%d:]+),%s*(%d+),%s*(%d+)%)$"
				)
				if not slot then return nil end
				return {
					SlotNumber = tonumber(slot),
					BoatName = boat,
					SaveDate = date,
					SaveTime = time,
					PropCount = tonumber(props),
					Cost = tonumber(cost),
				}
			end
			local function SetDropdownValuesSafe(dropdownKey, values)
				pcall(function()
					local dd = Options and Options[dropdownKey]
					if dd and dd.SetValues then
						dd:SetValues(values)
					end
				end)
			end
			local function LocalUserId()
				local lp = Players.LocalPlayer
				return (lp and lp.UserId) or 0
			end
			local function RefreshSavesListForDropdown()
				local availableSaves = buildState.AvailableSavesDisplay
				local fileIndexMap = buildState.FileIndexMap
				availableSaves = {} 
				fileIndexMap = {} 
				local apiUrl = Variables:GetServerRelayApiUrl()
				local userId = LocalUserId()
				local url = apiUrl .. "?" .. BuildQuery({
					action = "list",
					userid = userId,
					t = floor(clock()*1000), 
				})
				local obj, err = HttpGetJson(url)
				if not obj or obj.ok ~= true or type(obj.files) ~= "table" then
					Notify("Error! Failed to fetch save slots from server." .. (err and (" Reason: "..err) or ""))
					return
				end
				for i = 1, #obj.files do
					local raw = obj.files[i]
					local fname = (type(raw) == "string") and raw or tostring(raw or "")
					if #fname > 0 then
						local parts = ParseFilenameParts(fname)
						local display = parts and parts.SlotNumber and parts.BoatName and ("Slot#%d: %s"):format(parts.SlotNumber, parts.BoatName) or fname
						fileIndexMap[display] = fname
						table.insert(availableSaves, display)
					end
				end
				sort(availableSaves, function(a,b) return tostring(a) < tostring(b) end)
				buildState.AvailableSavesDisplay = availableSaves
				buildState.FileIndexMap = fileIndexMap
				SetDropdownValuesSafe("LoadServerBuildDropdown", availableSaves)
				local current = (Options.LoadServerBuildDropdown and Options.LoadServerBuildDropdown.GetValue) and Options.LoadServerBuildDropdown:GetValue() or nil
				if current and not fileIndexMap[current] then
					pcall(function() Options.LoadServerBuildDropdown:SetValue(nil) end)
					LoadInfoSetDefault() 
					buildState.SelectedDisplayKey = nil 
					buildState.SelectedFilename = nil
				end
			end
			local function UpdateInfoPanelForSelection()
				local fn = buildState.SelectedFilename
				if not fn then
					LoadInfoSetDefault()
					return
				end
				local p = ParseFilenameParts(fn)
				local LoadInfoColor = "'rgb(0, 208, 255)'"
				if not p then
					LoadInfoSetDefault()
					local nameValue = "<font color=" .. LoadInfoColor .. ">" .. tostring(fn) .. "</font>"
					LoadInfoLabels.BoatName:SetText("Boat Name: " .. nameValue)
					return
				end
				local function styled(value)
					return "<font color=" .. LoadInfoColor .. ">" .. tostring(value or "—--") .. "</font>"
				end
				LoadInfoLabels.Slot:SetText("Slot #: " .. styled(p.SlotNumber))
				LoadInfoLabels.BoatName:SetText("Boat Name: " .. styled(p.BoatName))
				LoadInfoLabels.SaveDate:SetText("Save Date: " .. styled(p.SaveDate))
				LoadInfoLabels.SaveTime:SetText("Save Time: " .. styled(p.SaveTime))
				LoadInfoLabels.PropCount:SetText("Prop Count: " .. styled(p.PropCount))
				LoadInfoLabels.Cost:SetText("Cost: " .. styled(p.Cost))
			end
			function serverbuildModule.Start()
				if buildState.IsActive then return end
				buildState.IsActive = true
				
				-- Listen for refresh events from other modules
				moduleMaid:GiveTask(GlobalEnv.CloudRefreshEvent:Connect(function()
					buildState.RequestListRefresh = true
				end))
				
				local heartbeatConnection = RunService.Heartbeat:Connect(function()
					local refreshList = buildState.RequestListRefresh
					local updateInfo = buildState.RequestInfoUpdate
					local loadRequest = buildState.RequestLoad
					if refreshList then
						buildState.RequestListRefresh = false 
						RefreshSavesListForDropdown()
					end
					if updateInfo then
						buildState.RequestInfoUpdate = false
						UpdateInfoPanelForSelection()
					end
					if loadRequest then
						buildState.RequestLoad = false 
						local selectedFilename = buildState.SelectedFilename
						if type(selectedFilename) ~= "string" or #selectedFilename == 0 then
							Notify("Error! Please select a save slot first.")
							return 
						end
						local getgenv_func = getgenv
						if getgenv_func then
							getgenv_func().WFYB_BUILD_FILENAME = selectedFilename
						end

						local codeUrl = Variables:GetServerCodeUrlBuild()
						local ok, err = pcall(function()
							local code = HttpGet(codeUrl)
							local fn = loadstring(code)
							return fn()
						end)

						if ok then
							Notify("Successfully fetched save data! Loading build...")
							buildState.RequestListRefresh = true 
						else
							Notify("Error! Load failed: " .. tostring(err))
						end
					end
				end)
				serverBuildMaid:GiveTask(heartbeatConnection)
			end
			function serverbuildModule.Stop()
				if not buildState.IsActive then return end
				buildState.IsActive = false
				buildState.RequestLoad = false
				buildState.RequestListRefresh = false
				buildState.RequestInfoUpdate = false
				pcall(function() serverBuildMaid:DoCleaning() end)
			end
			buildState.Module = serverbuildModule
		end

		-- [5] UI WIRING & STARTUP
		Variables.serverbuild.Module.Start()
		
		pcall(function()
			local dd = Options and Options.LoadServerBuildDropdown
			if dd and dd.OnOpen then
				uiMaid:GiveTask(
					dd:OnOpen(function()
						Variables.serverbuild.RequestListRefresh = true
					end)
				)
			else
				Variables.serverbuild.RequestListRefresh = true 
			end
		end)
		pcall(function()
			local dd = Options and Options.LoadServerBuildDropdown
			if dd and dd.OnChanged then
				uiMaid:GiveTask(
					dd:OnChanged(function(displayKey)
						local sbState = Variables.serverbuild 
						sbState.SelectedDisplayKey = displayKey
						sbState.SelectedFilename = sbState.FileIndexMap[displayKey]
						sbState.RequestInfoUpdate = true
					end)
				)
			end
		end)
		pcall(function()
			local btn = LoadServerBuildButton
			local callback = function() 
				local now = os.clock()
				local cd = Variables.ButtonCooldowns
				if (now - cd.LastLoadClick) < cd.Duration then
					Library:Notify("WARNING: Please wait before loading again!", 3)
					return
				end
				cd.LastLoadClick = now 
				Library:Notify("Loading! Please wait...", 4)
				Variables.serverbuild.RequestLoad = true 
			end
			if btn then
				if btn.SetFunction then btn:SetFunction(callback)
				elseif btn.SetCallback then btn:SetCallback(callback)
				else btn.Func = callback end 
			end
		end)
		
		-- [6] RETURN MODULE
		local function Stop()
			if Variables.serverbuild.Module and Variables.serverbuild.Module.Stop then
				Variables.serverbuild.Module.Stop()
			end
			Variables.Maids[ModuleName]:DoCleaning()
		end
		
		return { Name = ModuleName, Stop = Stop }
	end
end
