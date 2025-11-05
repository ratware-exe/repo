-- modules/clientnamespoofer.lua
do
	return function(UI)
		-- === Services / Deps (match repo style like infinitezoom.lua) ======
		local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
		local GlobalEnv  = (getgenv and getgenv()) or _G
		GlobalEnv.Signal = GlobalEnv.Signal or loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()
		local Maid 		 = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

		local Players 	= RbxService.Players
		local CoreGui 	= RbxService.CoreGui
		local LocalPlayer 	= Players.LocalPlayer

		-- === State ==========================================================
		GlobalEnv.NameSpoofConfig = GlobalEnv.NameSpoofConfig or {
			FakeDisplayName 	 = "NameSpoof",
			FakeName 			 = "NameSpoof",
			FakeId 				 = 0,
			BlankProfilePicture = true,
		}

		-- === Backup (Run this ONCE, as early as possible) ===================
		local function ensureBackup()
			if GlobalEnv.NameSpoofBackup or not LocalPlayer then return end
			pcall(function()
				GlobalEnv.NameSpoofBackup = {
					Name 				= LocalPlayer.Name,
					DisplayName 		= LocalPlayer.DisplayName,
					UserId 				= LocalPlayer.UserId,
					CharacterAppearanceId = LocalPlayer.CharacterAppearanceId or LocalPlayer.UserId,
				}
			end)
		end
		ensureBackup() 

		-- === State (continued) ==============================================
		local Variables = {
			Maids = { NameSpoofer = Maid.new() },
			RunFlag = false,

			Backup = GlobalEnv.NameSpoofBackup, 
			Snapshots = {
				Text  = setmetatable({}, { __mode = "k" }),
				Image = setmetatable({}, { __mode = "k" }),
			},

			Config = GlobalEnv.NameSpoofConfig,
		}

		local BLANKS = {
			"rbxasset://textures/ui/GuiImagePlaceholder.png",
			"rbxassetid://0",
			"http://www.roblox.com/asset/?id=0",
		}

		local OUR_INPUT_ATTR = "CNS_Ignore"

		-- === Utils ==========================================================
		local function esc(s) s = tostring(s or ""); return (s:gsub("(%W)","%%%1")) end

		local function killOldStandaloneUi()
			local old = CoreGui:FindFirstChild("NameSpoofUI")
			if old then old:Destroy() end
		end

		local function applyPlayerFields()
			pcall(function() LocalPlayer.DisplayName = Variables.Config.FakeDisplayName end)
			pcall(function() LocalPlayer.CharacterAppearanceId = tonumber(Variables.Config.FakeId) or Variables.Config.FakeId end)
		end

		local function restorePlayerFields()
			if not Variables.Backup then return end
			pcall(function() LocalPlayer.DisplayName = Variables.Backup.DisplayName end)
			pcall(function() LocalPlayer.CharacterAppearanceId = Variables.Backup.CharacterAppearanceId end)
		end

		-- === Simplified Replacement Functions ================================
		local function replaceTextInObject(obj)
			if not obj or not obj.Parent then return end
			if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
				if obj:GetAttribute(OUR_INPUT_ATTR) then return end 
				if obj:GetAttribute("TextReplaced") then return end
				obj:SetAttribute("TextReplaced", true)

				-- Take snapshot ONCE
				if Variables.Snapshots.Text[obj] == nil then
					Variables.Snapshots.Text[obj] = tostring(obj.Text or "")
				end

				-- Apply spoof based on original snapshot text
				local text = Variables.Snapshots.Text[obj]
				if string.find(text, Variables.Backup.Name, 1, true) then
					obj.Text = (text:gsub(esc(Variables.Backup.Name), Variables.Config.FakeName))
				elseif string.find(text, Variables.Backup.DisplayName, 1, true) then
					obj.Text = (text:gsub(esc(Variables.Backup.DisplayName), Variables.Config.FakeDisplayName))
				elseif string.find(text, tostring(Variables.Backup.UserId), 1, true) then
					obj.Text = (text:gsub(esc(tostring(Variables.Backup.UserId)), tostring(Variables.Config.FakeId)))
				end
				-- NO GetPropertyChangedSignal hook. It's not needed and caused all the problems.
			end
		end

		local function replaceImageInObject(obj)
			if not obj or not obj.Parent then return end
			if obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
				if obj:GetAttribute("ImageReplaced") then return end
				obj:SetAttribute("ImageReplaced", true)

				if Variables.Snapshots.Image[obj] == nil then
					Variables.Snapshots.Image[obj] = obj.Image
				end

				local image = Variables.Snapshots.Image[obj]
				if Variables.Config.BlankProfilePicture then
					if string.find(image, tostring(Variables.Backup.UserId), 1, true) or string.find(image, Variables.Backup.Name, 1, true) then
						obj.Image = BLANKS[1]
					end
				end
				-- NO GetPropertyChangedSignal hook.
			end
		end

		-- === Hooks ==========================================================
		local function setupGlobalHook()
			for _, obj in pairs(game:GetDescendants()) do
				if obj:GetAttribute("TextReplaced") then obj:SetAttribute("TextReplaced", nil) end
				if obj:GetAttribute("ImageReplaced") then obj:SetAttribute("ImageReplaced", nil) end
				replaceTextInObject(obj)
				replaceImageInObject(obj)
			end

			local conn = game.DescendantAdded:Connect(function(obj)
				if not Variables.RunFlag then return end
				replaceTextInObject(obj)
				replaceImageInObject(obj)
			end)
			Variables.Maids.NameSpoofer:GiveTask(conn)
		end

		local function hookPlayerList()
			local playerList = CoreGui:FindFirstChild("PlayerList")
			if not playerList then return end
			for _, obj in ipairs(playerList:GetDescendants()) do
				if obj:GetAttribute("TextReplaced") then obj:SetAttribute("TextReplaced", nil) end
				if obj:GetAttribute("ImageReplaced") then obj:SetAttribute("ImageReplaced", nil) end
				replaceTextInObject(obj)
				replaceImageInObject(obj)
			end
			local conn = playerList.DescendantAdded:Connect(function(obj)
				if not Variables.RunFlag then return end
				replaceTextInObject(obj)
				replaceImageInObject(obj)
			end)
			Variables.Maids.NameSpoofer:GiveTask(conn)
		end

		local function hookCoreGui()
			for _, obj in pairs(CoreGui:GetDescendants()) do
				if obj:GetAttribute("TextReplaced") then obj:SetAttribute("TextReplaced", nil) end
				if obj:GetAttribute("ImageReplaced") then obj:SetAttribute("ImageReplaced", nil) end
				replaceTextInObject(obj)
				replaceImageInObject(obj)
			end
			local conn = CoreGui.DescendantAdded:Connect(function(obj)
				if not Variables.RunFlag then return end
				replaceTextInObject(obj)
				replaceImageInObject(obj)
			end)
			Variables.Maids.NameSpoofer:GiveTask(conn)
		end

		-- === Lifecycle ======================================================
		local function Start()
			-- This block is for DYNAMICALLY UPDATING when you type in the box
			if Variables.RunFlag then
				for obj, base in pairs(Variables.Snapshots.Text) do
					if obj and obj.Parent then
						local t = base
						if string.find(t, Variables.Backup.Name, 1, true) then
							obj.Text = (t:gsub(esc(Variables.Backup.Name), Variables.Config.FakeName))
						elseif string.find(t, Variables.Backup.DisplayName, 1, true) then
							obj.Text = (t:gsub(esc(Variables.Backup.DisplayName), Variables.Config.FakeDisplayName))
						elseif string.find(t, tostring(Variables.Backup.UserId), 1, true) then
							obj.Text = (t:gsub(esc(tostring(Variables.Backup.UserId)), tostring(Variables.Config.FakeId)))
						end
					end
				end
				applyPlayerFields()
				return
			end

			-- This block is for the FIRST TIME you toggle it on
			Variables.RunFlag = true
			killOldStandaloneUi()

			setupGlobalHook()
			hookPlayerList()
			hookCoreGui()

			applyPlayerFields()

			Variables.Maids.NameSpoofer:GiveTask(function() Variables.RunFlag = false end)
		end

		local function Stop()
			if not Variables.RunFlag then return end
			Variables.RunFlag = false

			Variables.Maids.NameSpoofer:DoCleaning()

			-- Restore from snapshots
			for obj, base in pairs(Variables.Snapshots.Text) do
				if obj and obj.Parent then
					pcall(function()
						obj.Text = base
						if obj:GetAttribute("TextReplaced") then obj:SetAttribute("TextReplaced", nil) end
					end)
				end
				Variables.Snapshots.Text[obj] = nil
			end
			for obj, baseIm in pairs(Variables.Snapshots.Image) do
				if obj and obj.Parent then
					pcall(function()
						obj.Image = baseIm
						if obj:GetAttribute("ImageReplaced") then obj:SetAttribute("ImageReplaced", nil) end
					end)
				end
				Variables.Snapshots.Image[obj] = nil
			end

			restorePlayerFields()
		end

		-- === UI (Misc) ======================================================
		local groupbox = UI.Tabs.Misc:AddLeftGroupbox("Client Name Spoofer", "user")

		groupbox:AddInput("CNS_DisplayName", {
			Text = "Fake Display Name",
			Default = tostring(Variables.Config.FakeDisplayName or ""),
			Finished = false, 
			Placeholder = "Display name...",
			ClearTextOnFocus = false,
		})
		groupbox:AddInput("CNS_Username", {
			Text = "Fake Username",
			Default = tostring(Variables.Config.FakeName or ""),
			Finished = false,
			Placeholder = "Username...",
			ClearTextOnFocus = false,
		})
		groupbox:AddInput("CNS_UserId", {
			Text = "Fake UserId",
			Default = tostring(Variables.Config.FakeId or 0),
			Numeric = true,
			Finished = false,
			Placeholder = "123456",
			ClearTextOnFocus = false,
		})
		groupbox:AddToggle("CNS_BlankPfp", {
			Text = "Blank Profile Picture",
			Default = Variables.Config.BlankProfilePicture == true,
		})
		groupbox:AddToggle("CNS_Enable", {
			Text = "Enable Name Spoofer",
			Default = false,
		})

		-- Mark inputs so spoofing never touches them
		pcall(function()
			if UI.Options.CNS_DisplayName.Textbox then
				UI.Options.CNS_DisplayName.Textbox:SetAttribute(OUR_INPUT_ATTR, true)
			end
			if UI.Options.CNS_Username.Textbox then
				UI.Options.CNS_Username.Textbox:SetAttribute(OUR_INPUT_ATTR, true)
			end
			if UI.Options.CNS_UserId.Textbox then
				UI.Options.CNS_UserId.Textbox:SetAttribute(OUR_INPUT_ATTR, true)
			end
		end)

		-- Inputs → live config (reapply if running)
		UI.Options.CNS_DisplayName:OnChanged(function(v)
			v = v or ""
			Variables.Config.FakeDisplayName = v
			if Variables.RunFlag then Start() end
		end)
		UI.Options.CNS_Username:OnChanged(function(v)
			v = v or ""
			Variables.Config.FakeName = v
			if Variables.RunFlag then Start() end
		end)
		UI.Options.CNS_UserId:OnChanged(function(v)
			v = v or ""
			local n = tonumber(v)
			if n then
				Variables.Config.FakeId = n
			elseif v == "" then
				Variables.Config.FakeId = 0
			end
			if Variables.RunFlag then Start() end
		end)
		UI.Toggles.CNS_BlankPfp:OnChanged(function(val)
			Variables.Config.BlankProfilePicture = val and true or false
			if Variables.RunFlag then Start() end
		end)
		UI.Toggles.CNS_Enable:OnChanged(function(enabledState)
			if enabledState then Start() else Stop() end
		end)

		-- === Module API =====================================================
		return { Name = "ClientNameSpoofer", Stop = Stop }
	end
end
