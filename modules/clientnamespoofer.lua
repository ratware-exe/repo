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
		-- This is your 'OriginalValues' logic, guarded so it only runs once
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

			Backup = GlobalEnv.NameSpoofBackup, -- Replaces getgenv().OriginalValues
			Config = GlobalEnv.NameSpoofConfig, -- Replaces getgenv().Config
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

		-- === Replacement Functions (Ported 1:1 from original) ================
		local function replaceTextInObject(obj)
			if not obj or not obj.Parent then return end
			if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
				if obj:GetAttribute(OUR_INPUT_ATTR) then return end
				if obj:GetAttribute("TextReplaced") then return end
				obj:SetAttribute("TextReplaced", true)

				local text = tostring(obj.Text or "")
				if string.find(text, Variables.Backup.Name, 1, true) then
					obj.Text = (text:gsub(esc(Variables.Backup.Name), Variables.Config.FakeName))
				elseif string.find(text, Variables.Backup.DisplayName, 1, true) then
					obj.Text = (text:gsub(esc(Variables.Backup.DisplayName), Variables.Config.FakeDisplayName))
				elseif string.find(text, tostring(Variables.Backup.UserId), 1, true) then
					obj.Text = (text:gsub(esc(tostring(Variables.Backup.UserId)), tostring(Variables.Config.FakeId)))
				end

				local conn = obj:GetPropertyChangedSignal("Text"):Connect(function()
					if not Variables.RunFlag then return end 
					task.wait()
					local newText = tostring(obj.Text or "")
					
					if string.find(newText, Variables.Backup.Name, 1, true) then
						obj.Text = (newText:gsub(esc(Variables.Backup.Name), Variables.Config.FakeName))
					elseif string.find(newText, Variables.Backup.DisplayName, 1, true) then
						obj.Text = (newText:gsub(esc(Variables.Backup.DisplayName), Variables.Config.FakeDisplayName))
					elseif string.find(newText, tostring(Variables.Backup.UserId), 1, true) then
						obj.Text = (newText:gsub(esc(tostring(Variables.Backup.UserId)), tostring(Variables.Config.FakeId)))
					end
				end)
				Variables.Maids.NameSpoofer:GiveTask(conn) 
			end
		end

		local function replaceImageInObject(obj)
			if not obj or not obj.Parent then return end
			if Variables.Config.BlankProfilePicture and (obj:IsA("ImageLabel") or obj:IsA("ImageButton")) then
				if obj:GetAttribute("ImageReplaced") then return end
				obj:SetAttribute("ImageReplaced", true)

				local image = tostring(obj.Image or "")
				if string.find(image, tostring(Variables.Backup.UserId), 1, true) or string.find(image, Variables.Backup.Name, 1, true) then
					obj.Image = BLANKS[1]
				end

				local conn = obj:GetPropertyChangedSignal("Image"):Connect(function()
					if not Variables.RunFlag then return end 
					task.wait()
					local newImage = tostring(obj.Image or "")
					
					if Variables.Config.BlankProfilePicture then
						if string.find(newImage, tostring(Variables.Backup.UserId), 1, true) or string.find(newImage, Variables.Backup.Name, 1, true) then
							obj.Image = BLANKS[1]
						end
					end
				end)
				Variables.Maids.NameSpoofer:GiveTask(conn)
			end
		end

		-- === Hooks (Ported 1:1 from original, minus global hook) =============
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
			if Variables.RunFlag then return end 
			Variables.RunFlag = true
			
			killOldStandaloneUi()
			applyPlayerFields()

			-- Call the targeted hooks from your original script
			hookPlayerList()
			hookCoreGui()

			Variables.Maids.NameSpoofer:GiveTask(function() Variables.RunFlag = false end)
		end

		local function Stop()
			if not Variables.RunFlag then return end
			Variables.RunFlag = false

			Variables.Maids.NameSpoofer:DoCleaning() -- This is the 'cleanup()' function
			
			-- We must manually restore text, as the original script had no 'Stop'
			local playerList = CoreGui:FindFirstChild("PlayerList")
			local areasToRestore = {}
			
			for _, obj in ipairs(CoreGui:GetDescendants()) do
				table.insert(areasToRestore, obj)
			end
			if playerList then
				for _, obj in ipairs(playerList:GetDescendants()) do
					table.insert(areasToRestore, obj)
				end
			end

			for _, obj in pairs(areasToRestore) do
				if obj:GetAttribute("TextReplaced") then
					pcall(function()
						local text = tostring(obj.Text or "")
						-- Check in reverse order of application
						if string.find(text, Variables.Config.FakeName, 1, true) then
							obj.Text = (text:gsub(esc(Variables.Config.FakeName), Variables.Backup.Name))
						elseif string.find(text, Variables.Config.FakeDisplayName, 1, true) then
							obj.Text = (text:gsub(esc(Variables.Config.FakeDisplayName), Variables.Backup.DisplayName))
						elseif string.find(text, tostring(Variables.Config.FakeId), 1, true) then
							obj.Text = (text:gsub(esc(tostring(Variables.Config.FakeId)), tostring(Variables.Backup.UserId)))
						end
					end)
					obj:SetAttribute("TextReplaced", nil)
				end
				if obj:GetAttribute("ImageReplaced") then
					-- We can't reliably restore images, but we can un-blank them
					pcall(function()
						if obj.Image == BLANKS[1] then
							-- This is imperfect, but better than nothing
							obj.Image = string.gsub(obj.Image, "0", Variables.Backup.UserId) 
						end
					end)
					obj:SetAttribute("ImageReplaced", nil)
				end
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

		-- === Inputs → live config (Mimics original 'Apply' button) ==========
		
		UI.Options.CNS_DisplayName:OnChanged(function(v)
			Variables.Config.FakeDisplayName = v or ""
			if Variables.RunFlag then
				Stop()  -- Clean up old hooks
				Start() -- Re-apply with new config
			end
		end)
		
		UI.Options.CNS_Username:OnChanged(function(v)
			Variables.Config.FakeName = v or ""
			if Variables.RunFlag then
				Stop()
				Start()
			end
		end)
		
		UI.Options.CNS_UserId:OnChanged(function(v)
			local n = tonumber(v)
			if n then
				Variables.Config.FakeId = n
			elseif v == "" then
				Variables.Config.FakeId = 0
			end
			
			if Variables.RunFlag then
				Stop()
				Start()
			end
		end)
		
		UI.Toggles.CNS_BlankPfp:OnChanged(function(val)
			Variables.Config.BlankProfilePicture = val and true or false
			if Variables.RunFlag then
				Stop()  -- Re-hook to apply/remove image hooks
				Start()
			end
		end)
		
		UI.Toggles.CNS_Enable:OnChanged(function(enabledState)
			if enabledState then Start() else Stop() end
		end)

		-- === Module API =====================================================
		return { Name = "ClientNameSpoofer", Stop = Stop }
	end
end
