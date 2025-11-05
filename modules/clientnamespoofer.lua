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
			FakeName 			 = "NameSpoof", -- This is the 'getgenv().name' from your script
		}

		-- === Backup (Run this ONCE, as early as possible) ===================
		local function ensureBackup()
			if GlobalEnv.NameSpoofBackup or not LocalPlayer then return end
			pcall(function()
				GlobalEnv.NameSpoofBackup = {
					Name 				= LocalPlayer.Name,
					DisplayName 		= LocalPlayer.DisplayName,
					CharacterAppearanceId = LocalPlayer.CharacterAppearanceId or LocalPlayer.UserId,
				}
			end)
		end
		ensureBackup() 

		-- === State (continued) ==============================================
		local Variables = {
			Maids = { NameSpoofer = Maid.new() }, -- This is for cleanup
			RunFlag = false, -- This is for the toggle

			Backup = GlobalEnv.NameSpoofBackup, 
			Config = GlobalEnv.NameSpoofConfig,
			
			-- This is new: We need to store the config that is *currently* active
			-- so that Stop() knows what text to find and replace.
			ActiveConfig = {} 
		}

		local OUR_INPUT_ATTR = "CNS_Ignore"

		-- === Utils ==========================================================
		local function esc(s) s = tostring(s or ""); return (s:gsub("(%W)","%%%1")) end

		local function killOldStandaloneUi()
			local old = CoreGui:FindFirstChild("NameSpoofUI")
			if old then old:Destroy() end
		end

		-- This applies the leaderboard/player object spoof
		local function applyPlayerFields()
			pcall(function() LocalPlayer.DisplayName = Variables.Config.FakeDisplayName end)
		end

		-- This restores the leaderboard/player object
		local function restorePlayerFields()
			if not Variables.Backup then return end
			pcall(function() LocalPlayer.DisplayName = Variables.Backup.DisplayName end)
		end

		-- === Core Spoof Logic (Based on your script) ========================
		
		-- This is the function that runs on 'GetPropertyChangedSignal("Text")'
		local function replaceText(obj)
			if not Variables.RunFlag or not obj or not obj.Parent or not obj:IsA("TextLabel") then return end
			if obj:GetAttribute(OUR_INPUT_ATTR) then return end

			local currentText = tostring(obj.Text or "")
			local newText = currentText
			
			-- Apply spoofing based on the *active* config
			-- We do Name first, then DisplayName, just in case they are the same
			newText = newText:gsub(esc(Variables.Backup.Name), Variables.ActiveConfig.FakeName)
			newText = newText:gsub(esc(Variables.Backup.DisplayName), Variables.ActiveConfig.FakeDisplayName)

			if currentText ~= newText then
				obj.Text = newText
			end
		end

		-- This function IS THE LOGIC from your 'if Value.ClassName == "TextLabel" then' block
		local function hookObject(obj)
			if obj:IsA("TextLabel") and not obj:GetAttribute(OUR_INPUT_ATTR) then
				replaceText(obj) -- Spoof it once initially (your 'if has then...' block)
				
				-- This IS your 'Value:GetPropertyChangedSignal("Text"):Connect(...)' hook
				local conn = obj:GetPropertyChangedSignal("Text"):Connect(function()
					replaceText(obj)
				end)
				Variables.Maids.NameSpoofer:GiveTask(conn) -- This adds the hook to the cleanup system
			end
		end

		-- This function IS THE LOGIC from your two main blocks
		local function hookGlobal()
			-- This IS your 'for Index, Value in next, game:GetDescendants() do' loop
			for _, obj in pairs(game:GetDescendants()) do
				hookObject(obj)
			end
			
			-- This IS your 'game.DescendantAdded:Connect(function(Value)' hook
			local conn = game.DescendantAdded:Connect(function(obj)
				hookObject(obj)
			end)
			Variables.Maids.NameSpoofer:GiveTask(conn) -- This adds the hook to the cleanup system
		end

		-- === Lifecycle ======================================================
		local function Start()
			if Variables.RunFlag then return end 
			Variables.RunFlag = true
			
			-- Store the config that we are starting with
			Variables.ActiveConfig = {
				FakeDisplayName = Variables.Config.FakeDisplayName,
				FakeName = Variables.Config.FakeName,
			}
			
			killOldStandaloneUi()
			applyPlayerFields()
			hookGlobal() -- Run the hook logic from your script

			Variables.Maids.NameSpoofer:GiveTask(function() Variables.RunFlag = false end)
		end

		local function Stop()
			if not Variables.RunFlag then return end
			Variables.RunFlag = false

			Variables.Maids.NameSpoofer:DoCleaning() -- Disconnects all hooks
			restorePlayerFields()
			
			-- Manually scan and restore all text
			for _, obj in pairs(game:GetDescendants()) do
				if obj:IsA("TextLabel") then
					local currentText = tostring(obj.Text or "")
					local newText = currentText
					
					-- Use the 'ActiveConfig' to find the text we spoofed
					newText = newText:gsub(esc(Variables.ActiveConfig.FakeName), Variables.Backup.Name)
					newText = newText:gsub(esc(Variables.ActiveConfig.FakeDisplayName), Variables.Backup.DisplayName)
					
					if currentText ~= newText then
						obj.Text = newText
					end
				end
			end
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
			Placeholder = "Username (replaces @name)...",
			ClearTextOnFocus = false,
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
		end)

		-- === Inputs → live config (Clean Restart Logic) ==========
		
		UI.Options.CNS_DisplayName:OnChanged(function(v)
			Variables.Config.FakeDisplayName = v or ""
			if Variables.RunFlag then
				Stop()  -- Cleanly stop and restore
				Start() -- Restart with the new config
			end
		end)
		
		UI.Options.CNS_Username:OnChanged(function(v)
			Variables.Config.FakeName = v or ""
			if Variables.RunFlag then
				Stop()
				Start()
			end
		end)
		
		UI.TSoggles.CNS_Enable:OnChanged(function(enabledState)
			if enabledState then Start() else Stop() end
		end)

		-- === Module API =====================================================
		return { Name = "ClientNameSpoofer", Stop = Stop }
	end
end
