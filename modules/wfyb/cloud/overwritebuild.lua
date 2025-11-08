-- "modules/wfyb/cloud/overwritebuild.lua",
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
		local ModuleName = "OverwriteBuild"
		local Variables = {
			Maids = { [ModuleName] = Maid.new() },
			
			ButtonCooldowns = {
				Duration = 5, 
				LastOverwriteClick = 0,
			},
			NoBoatsNotified = false,
			ServerRelayBaseUrl = "https://wfyb-serverrelay.wfyb-exploits.workers.dev",
			GetServerRelayApiUrl  = function(self) return self.ServerRelayBaseUrl .. "/api" end,
			GetServerCodeUrlSave  = function(self) return self.ServerRelayBaseUrl .. "/savecode?which=serversave" end,
			
			serversave = {
				BoatsFolderRef = nil,         
				IsActive = false,
				RequestScanBoats = false,
				OwnedBoatNames = {},      
				OverwriteTarget = nil,    
				RequestRefreshOverwrite = false,
				OverwriteMap = {},   
				OverwriteDisplay = {},   
				RequestOverwrite = false,         
				OverwriteSourceBoatName = nil,           
				OverwriteTargetDisplay = nil,           
				Module = nil
			},
		}
		
		-- Create sub-maids for cleanup
		local moduleMaid = Variables.Maids[ModuleName]
		local serverSaveMaid = Maid.new()
		local uiMaid = Maid.new()
		moduleMaid:GiveTask(serverSaveMaid)
		moduleMaid:GiveTask(uiMaid)
		

		-- [3] UI CREATION
		local OverwriteGroupbox = Tabs.Cloud:AddRightGroupbox("Overwrite Save", "square-pen")
		OverwriteGroupbox:AddDropdown("OverwriteSourceBoatDropdown", {
			Values = {},                     
			Text = "Select Build:",
			Multi = false,
			Searchable = true,
		})
		OverwriteGroupbox:AddDivider()
		OverwriteGroupbox:AddDropdown("OverwriteTargetDropdown", {
			Values = {},
			Text = "Select Save Slot:",
			Multi = false,
			Searchable = true,
		})
		local OverwriteButton = OverwriteGroupbox:AddButton({
			Text = "Overwrite Save",
			DoubleClick = true,
			Tooltip = "Double click to overwrite the selected server save with the selected build",
			DisabledTooltip = "Pick both dropdowns first",
			Func = function() end,       
		})
		
		
		-- [4] CORE LOGIC
		do
			local pcall, type, tostring, pairs, ipairs, tonumber, loadstring = pcall, type, tostring, pairs, ipairs, tonumber, loadstring
			local floor = math.floor
			local clock = os.clock
			local concat, sort = table.concat, table.sort
			local HttpService = RbxService.HttpService
			local Players = RbxService.Players
			local Workspace = RbxService.Workspace
			local RunService = RbxService.RunService
			local UrlEncode = HttpService.UrlEncode
			local JSONDecode = HttpService.JSONDecode
			local HttpGet = game.HttpGet
			local serversaveModule = {}
			local serverState = Variables.serversave 
			local SetDropdownValuesSafe 
			local function GetBoatsFolder()
				return Workspace:FindFirstChild("Boats") or nil
			end
			local function BuildQuery(params)
				local acc = {}
				for k, v in pairs(params) do
					acc[#acc+1] = k .. "=" .. UrlEncode(HttpService, tostring(v))
				end
				return concat(acc, "&")
			end
			local function HttpGetJson(url)
				local ok, res = pcall(HttpGet, url)
				if not ok or type(res) ~= "string" or #res == 0 then return nil end
				local okj, obj = pcall(JSONDecode, HttpService, res)
				if not okj or type(obj) ~= "table" then return nil end
				return obj
			end
			local function ParseFilenameParts(filename)
				if type(filename) ~= "string" then return nil end
				local slot, boat = string.match(filename, "^Slot#(%d+):%s*(.-)%s*%(")
				if not slot then return nil end
				return { SlotNumber = tonumber(slot), BoatName = boat }
			end
			local function LocalUserId()
				local lp = Players.LocalPlayer
				return (lp and lp.UserId) or 0
			end
			local function RefreshOverwriteListForSaveDropdown()
				local overwriteDisplay = serverState.OverwriteDisplay
				local overwriteMap = serverState.OverwriteMap
				overwriteDisplay = {} 
				overwriteMap = {} 
				local apiUrl = Variables:GetServerRelayApiUrl()
				local userId = LocalUserId()
				local url = apiUrl .. "?" .. BuildQuery({
					action = "list",
					userid = userId,
					t = floor(clock()*1000),
				})
				local obj = HttpGetJson(url)
				if obj and obj.ok and type(obj.files) == "table" then
					for _, raw in ipairs(obj.files) do
						local fname = (type(raw) == "string") and raw or tostring(raw or "")
						if #fname > 0 then
							local p = ParseFilenameParts(fname)
							local display = p and ("Slot#%d: %s"):format(p.SlotNumber, p.BoatName) or fname
							table.insert(overwriteDisplay, display)
							overwriteMap[display] = fname
						end
					end
				end
				sort(overwriteDisplay, function(a,b) return tostring(a) < tostring(b) end)
				serverState.OverwriteDisplay = overwriteDisplay
				serverState.OverwriteMap = overwriteMap
				SetDropdownValuesSafe("OverwriteTargetDropdown", overwriteDisplay)
			end
			local function GetBoatOwnerUserId(model)
				if not (model and model:IsA("Model")) then return nil end
				local attributes = model:GetAttributes()
				for key, value in pairs(attributes) do
					local k = string.lower(key)
					if k == "owneruserid" or k == "owner" then
						local n = tonumber(value)
						if n then return n end
					end
				end
				local boatData = model:FindFirstChild("BoatData")
				if boatData then
					for _, child in ipairs(boatData:GetChildren()) do
						local nm = string.lower(child.Name)
						if child:IsA("IntValue") and string.find(nm, "owner") then
							return child.Value
						end
						if child:IsA("ObjectValue") and nm == "owner" then
							local p = child.Value
							if p and p.UserId then return p.UserId end
						end
						if child:IsA("StringValue") and string.find(nm, "owner") then
							local n = tonumber(child.Value)
							if n then return n end
						end
					end
				end
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("IntValue") and (d.Name == "Owner" or d.Name == "OwnerUserId") then
						return d.Value
					end
				end
				return nil
			end

			local function ReadBoatName(model)
				local bd = model:FindFirstChild("BoatData")
				local u  = bd and bd:FindFirstChild("UnfilteredBoatName")
				if u and typeof(u.Value) == "string" and #u.Value > 0 then
					return u.Value
				end
				return model.Name
			end
			local function SnapshotOwnedBoatNamesForLocalPlayer()
				local out, set_ = {}, {}
				local localPlayer = Players.LocalPlayer
				if not localPlayer then return out end
				local userId = localPlayer.UserId 
				local folder = GetBoatsFolder()
				if not folder then return out end
				for _, m in ipairs(folder:GetChildren()) do
					if m:IsA("Model") and GetBoatOwnerUserId(m) == userId then
						local nm = ReadBoatName(m)
						if nm and not set_[nm] then
							set_[nm] = true
							table.insert(out, nm)
						end
					end
				end
				sort(out, function(a,b) return tostring(a) < tostring(b) end)
				return out
			end
			function SetDropdownValuesSafe(dropdownKey, values)
				pcall(function()
					local dd = Options and Options[dropdownKey]
					if not (dd and dd.SetValues) then return end
					dd:SetValues(values)
					local current = dd.GetValue and dd:GetValue() or nil
					local stillThere = false
					for i = 1, #values do if values[i] == current then stillThere = true; break end end
					if not stillThere and dd.SetValue then
						dd:SetValue(nil)
						local ssState = Variables.serversave
						if dropdownKey == "OverwriteSourceBoatDropdown" then
							ssState.OverwriteSourceBoatName = nil
						elseif dropdownKey == "OverwriteTargetDropdown" then
							ssState.OverwriteTarget = nil
							ssState.OverwriteTargetDisplay = nil
						end
					end
				end)
			end
			local function Notify(text)
				pcall(function()
					if Library and Library.Notify then
						Library:Notify(text, 5)
					end
				end)
			end
			local function BindBoatsFolderWatchers()
				serverState.RequestRefreshOverwrite = true
				serverState.BoatsFolderRef = GetBoatsFolder()
				serverSaveMaid.BoatsChildAdded = nil
				serverSaveMaid.BoatsChildRemoved = nil
				serverSaveMaid.WorkspaceBoatsWatcher = nil
				local boatsFolder = serverState.BoatsFolderRef
				if boatsFolder then
					serverSaveMaid.BoatsChildAdded = boatsFolder.ChildAdded:Connect(function()
						serverState.RequestScanBoats = true
					end)
					serverSaveMaid.BoatsChildRemoved = boatsFolder.ChildRemoved:Connect(function()
						serverState.RequestScanBoats = true
					end)
				end
				serverSaveMaid.WorkspaceBoatsWatcher = Workspace.ChildAdded:Connect(function(child)
					if child and child.Name == "Boats" then
						BindBoatsFolderWatchers()
						serverState.RequestScanBoats = true
					end
				end)
			end
			function serversaveModule.Start()
				if serverState.IsActive then return end
				serverState.IsActive = true
				BindBoatsFolderWatchers()
				serverState.RequestScanBoats = true
				
				-- Listen for refresh events from other modules (like Save)
				moduleMaid:GiveTask(GlobalEnv.CloudRefreshEvent:Connect(function()
					serverState.RequestRefreshOverwrite = true
				end))
				
				local heartbeatConnection = RunService.Heartbeat:Connect(function()
					local requestRefreshOverwrite = serverState.RequestRefreshOverwrite
					local requestScanBoats = serverState.RequestScanBoats
					local requestOverwrite = serverState.RequestOverwrite
					if requestRefreshOverwrite then
						serverState.RequestRefreshOverwrite = false 
						RefreshOverwriteListForSaveDropdown()
					end
					if requestScanBoats then
						serverState.RequestScanBoats = false 
						local names = SnapshotOwnedBoatNamesForLocalPlayer()
						serverState.OwnedBoatNames = names
						SetDropdownValuesSafe("OverwriteSourceBoatDropdown", names)
						if #names == 0 then
							if not Variables.NoBoatsNotified then
								Variables.NoBoatsNotified = true
							end
						else
							Variables.NoBoatsNotified = false 
						end
					end
				
					if requestOverwrite then
						serverState.RequestOverwrite = false 
						local src = serverState.OverwriteSourceBoatName
						local tgt = serverState.OverwriteTarget
						local tgtDisplay = serverState.OverwriteTargetDisplay
						if not src or src == "" then
							Notify("Error! Please pick a spawned build first.")
							return 
						end
						if not tgt or tgt == "" then
							Notify("Error! Please select an old save slot first.")
							return 
						end
						local getgenv_func = getgenv
						if getgenv_func then
							local env = getgenv_func()
							env.WFYB_SAVE_SELECTOR = { mode = "ByBoatName", value = src }
							env.WFYB_SAVE_MODE = "overwrite"
							env.WFYB_SAVE_TARGET = tgt
						end
						local codeUrl = Variables:GetServerCodeUrlSave()
						local ok, err = pcall(function()
							local code = HttpGet(codeUrl)
							local fn = loadstring(code)
							return fn()
						end)
						if ok then
							Notify(("Overwriting %s with boat '%s'…"):format(tostring(tgtDisplay or tgt), src))
							GlobalEnv.CloudRefreshEvent:Fire() -- Fire event for load module
							serverState.RequestRefreshOverwrite = true
						else
							Notify("Error! Overwrite failed: " .. tostring(err))
						end
					end
				end)
				serverSaveMaid:GiveTask(heartbeatConnection)
			end
			function serversaveModule.Stop()
				if not serverState.IsActive then return end
				serverState.IsActive = false
				serverState.RequestScanBoats = false
				serverState.RequestOverwrite = false
				serverState.RequestRefreshOverwrite = false
				serverState.BoatsFolderRef = nil
				pcall(function() serverSaveMaid:DoCleaning() end)
			end
			serverState.Module = serversaveModule
		end

		-- [5] UI WIRING & STARTUP
		Variables.serversave.Module.Start()
		
		pcall(function()
			local dd = Options and Options.OverwriteSourceBoatDropdown
			if dd then
				if dd.OnOpen then
					uiMaid:GiveTask(
						dd:OnOpen(function()
							Variables.serversave.RequestScanBoats = true
						end)
					)
				end
				if dd.OnChanged then
					uiMaid:GiveTask(
						dd:OnChanged(function(name)
							Variables.serversave.OverwriteSourceBoatName = name
						end)
					)
				end
			end
		end)
		pcall(function()
			local dd = Options and Options.OverwriteTargetDropdown
			if dd then
				if dd.OnOpen then
					uiMaid:GiveTask(
						dd:OnOpen(function()
							Variables.serversave.RequestRefreshOverwrite = true
						end)
					)
				else
					Variables.serversave.RequestRefreshOverwrite = true 
				end
				if dd.OnChanged then
					uiMaid:GiveTask(
						dd:OnChanged(function(display)
							local ssState = Variables.serversave 
							ssState.OverwriteTargetDisplay = display
							local targetFile = ssState.OverwriteMap[display]
							ssState.OverwriteTarget = targetFile
						end)
					)
				end
			else
				Variables.serversave.RequestRefreshOverwrite = true 
			end
		end)
		pcall(function()
			local btn = OverwriteButton
			local callback = function() 
				local now = os.clock()
				local cd = Variables.ButtonCooldowns
				if (now - cd.LastOverwriteClick) < cd.Duration then
					Library:Notify("WARNING: Please wait before overwriting again!", 3)
					return 
				end
				cd.LastOverwriteClick = now 
				Library:Notify("Overwriting! Please wait...", 4)
				Variables.serversave.RequestOverwrite = true 
			end
			if btn then
				if btn.SetFunction then btn:SetFunction(callback)
				elseif btn.SetCallback then btn:SetCallback(callback)
				else btn.Func = callback end 
			end
		end)

		-- [6] RETURN MODULE
		local function Stop()
			if Variables.serversave.Module and Variables.serversave.Module.Stop then
				Variables.serversave.Module.Stop()
			end
			Variables.Maids[ModuleName]:DoCleaning()
		end
		
		return { Name = ModuleName, Stop = Stop }
	end
end
