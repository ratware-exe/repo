-- "modules/wfyb/vipservercommands.lua"
do
	return function(UI)
		-- [1] LOAD DEPENDENCIES
		local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
		local GlobalEnv = (getgenv and getgenv()) or _G
		local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

		-- [2] MODULE STATE
		local ModuleName = "VIPServerCommands"
		local Variables = {
			Maids = { [ModuleName] = Maid.new() },
		}
		
		-- This table will hold the module's functions
		local vipCommandsModule = {}

		-- [3] CORE LOGIC
		local function RunVipCmd(cmdString)
			local chatEvents = RbxService.ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents")
			if chatEvents and chatEvents:FindFirstChild("SayMessageRequest") then
				chatEvents.SayMessageRequest:FireServer(cmdString, "All")
				return
			end
			local channels = RbxService.TextChatService:FindFirstChild("TextChannels")
			local target = channels and (channels:FindFirstChild("RBXGeneral") or channels:FindFirstChild("General"))
			if target and target.SendAsync then
				target:SendAsync(cmdString)
			else
				-- Add notification here if needed
			end
		end

		function vipCommandsModule.Freecam()
			local localPlayer = RbxService.Players.LocalPlayer
			if localPlayer and localPlayer.Name then
				RunVipCmd("/vipfreecam " .. localPlayer.Name)
			else
				-- Add notification here if needed
			end
		end

		function vipCommandsModule.StopFreecam()
			local localPlayer = RbxService.Players.LocalPlayer
			if localPlayer and localPlayer.Name then
				RunVipCmd("/vipstopfreecam " .. localPlayer.Name)
			else
				-- Add notification here if needed
			end
		end

		function vipCommandsModule.NextMode()
			RunVipCmd("/vipnextmode")
		end

		local function Start()
			-- This module is event-driven, no main loop needed
		end

		local function Stop()
			pcall(function() Variables.Maids[ModuleName]:DoCleaning() end)
		end

		-- [4] UI CREATION
		local VIPServerCommandsGroupbox = UI.Tabs.Misc:AddLeftGroupbox("VIP Commands", "terminal")
		
		local vipnextmodeButton = VIPServerCommandsGroupbox:AddButton({
			Text = "Next Mode",
			Func = function() end, 
			DoubleClick = false,
			Tooltip = "Same as /vipnextmode.",
			DisabledTooltip = "Feature Disabled", 
			Disabled = false,
		})
		
		local vipfreecamButton = VIPServerCommandsGroupbox:AddButton({
			Text = "Freecam",
			Func = function() end, 
			DoubleClick = false,
			Tooltip = "Same as /vipfreecam.",
			DisabledTooltip = "Feature Disabled", 
			Disabled = false,
		})
		
		local vipstopfreecamButton = VIPServerCommandsGroupbox:AddButton({
			Text = "Stop Freecam",
			Func = function() end, 
			DoubleClick = false,
			Tooltip = "Same as /vipstopfreecam.",
			DisabledTooltip = "Feature Disabled", 
			Disabled = false,
		})

		-- [5] UI WIRING
		pcall(function()
			vipfreecamButton.Func = function()
				vipCommandsModule.Freecam()
			end
		end)
		
		pcall(function()
			vipstopfreecamButton.Func = function()
				vipCommandsModule.StopFreecam()
			end
		end)
		
		pcall(function()
			vipnextmodeButton.Func = function()
				vipCommandsModule.NextMode()
			end
		end)
		
		Start() -- Run the "start" logic

		-- [6] RETURN MODULE
		return { Name = ModuleName, Stop = Stop }
	end
end
