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
			FakeDisplayName 	 = "NameSpoof", -- For leaderboard ONLY
			FakeName 			 = "NameSpoof", -- This is the 'getgenv().name' from your script
		}

		-- === Backup (Run this ONCE) ===================
		local function ensureBackup()
			if GlobalEnv.NameSpoofBackup or not LocalPlayer then return end
			pcall(function()
				GlobalEnv.NameSpoofBackup = {
					Name 				= LocalPlayer.Name, -- Your 'Plr.Name'
					DisplayName 		= LocalPlayer.DisplayName, -- For leaderboard
				}
			end)
		end
		ensureBackup() 

		-- === State (continued) ==============================================
		local Variables = {
			Maids = { NameSpoofer = Maid.new() }, -- For cleanup
			RunFlag = false, -- For toggle
			Backup = GlobalEnv.NameSpoofBackup, 
			Config = GlobalEnv.NameSpoofConfig,
			
			-- We store the 'Active' name so Stop() knows what to replace
			ActiveConfig = { FakeName = "" } 
		}

		local OUR_INPUT_ATTR = "CNS_Ignore"

		-- === Utils ==========================================================
		local function esc(s) s = tostring(s or ""); return (s:gsub("(%W)","%%%1")) end

		local function killOldStandaloneUi()
			local old = CoreGui:FindFirstChild("NameSpoofUI")
			if old then old:Destroy() end
		end

		-- This ONLY affects the leaderboard
		local function applyPlayerFields()
			pcall(function() LocalPlayer.DisplayName = Variables.Config.FakeDisplayName end)
		end

		-- This ONLY restores the leaderboard
		local function restorePlayerFields()
			if not Variables.Backup then return end
			pcall(function() LocalPlayer.DisplayName = Variables.Backup.DisplayName end)
		end

		-- === Core Spoof Logic (1:1 with your script) ========================
		
		-- This is the function inside your 'GetPropertyChangedSignal'
		-- It ONLY replaces Name with FakeName.
		local function replaceText(obj)
			if not Variables.RunFlag or not obj or not obj:IsA("TextLabel") then return end
			if obj:GetAttribute(OUR_INPUT_ATTR) then return end

			local currentText = tostring(obj.Text or "")
			
			-- This is your logic: obj.Text:gsub(Plr.Name, name)
			-- It reads the LIVE config, so it's dynamic
			local newText = currentText:gsub(esc(Variables.Backup.Name), Variables.Config.FakeName)

			if currentText ~= newText then
				obj.Text = newText
			end
		end

		-- This function IS THE LOGIC from your 'if Value.ClassName == "TextLabel" then' block
		local function hookObject(obj)
			if obj:IsA("TextLabel") and not obj:GetAttribute(OUR_INPUT_ATTR) then
				
				-- This is your 'if has then ...' block
				local has = string.find(tostring(obj.Text or ""), Variables.Backup.Name, 1, true)
				if has then
					replaceText(obj) -- Spoof it once initially
				end
				
				-- This IS your 'Value:GetPropertyChangedSignal("Text"):Connect(...)' hook
				local conn = obj:GetPropertyChangedSignal("Text"):Connect(function()
					replaceText(obj)
				end)
				Variables.Maids.NameSpoofer:GiveTask(conn) -- Add to cleanup
			end
		end

		-- This function IS your 'for...in next' loop and 'DescendantAdded' hook
		local function hookGlobal()
			-- This IS your 'for Index, Value in next, game:GetDescendants() do' loop
			for _, obj in pairs(game:GetDescendants()) do
				hookObject(obj)
			end
			
			-- This IS your 'game.DescendantAdded:Connect(function(Value)' hook
			local conn = game.DescendantAdded:Connect(function(obj)
				hookObject(obj)
			end)
			Variables.Maids.NameSpoofer:GiveTask(conn) -- Add to cleanup
		end

		-- === Lifecycle ======================================================
		local function Start()
			if Variables.RunFlag then return end 
			Variables.RunFlag = true
			
			-- Store the name we are applying, so Stop() can find it
			Variables.ActiveConfig.FakeName = Variables.Config.FakeName
			
			killOldStandaloneUi()
			applyPlayerFields() -- Apply leaderboard name
			hookGlobal() -- Apply TextLabel hooks

			Variables.Maids.NameSpoofer:GiveTask(function() Variables.RunFlag = false end)
		end

		local function Stop()
			if not Variables.RunFlag then return end
			Variables.RunFlag = false

			Variables.Maids.NameSpoofer:DoCleaning() -- Disconnects all hooks
			restorePlayerFields() -- Restores leaderboard name
			
			-- Manually scan and restore all text
			for _, obj in pairs(game:GetDescendants()) do
				if obj:IsA("TextLabel") then
					local currentText = tostring(obj.Text or "")
					
					-- Restore by replacing the *active* fake name with the backup
					local newText = currentText:gsub(esc(Variables.ActiveConfig.FakeName), Variables.Backup.Name)
					
					if currentText ~= newText then
						obj.Text = newText
					end
				end
			end
		end

		-- === UI (Misc) ======================================================
		local groupbox = UI.Tabs.Misc:AddLeftGroupbox("Client Name Spoofer", "user")

		groupbox:AddInput("CNS_DisplayName", {
			Text = "Fake Display Name (Leaderboard)",
			Default = tostring(Variables.Config.FakeDisplayName or ""),
			Finished = false, 
			Placeholder = "Display name...",
			ClearTextOnFocus = false,
		})
		groupbox:AddInput("CNS_Username", {
			Text = "Fake Username (UI Text)",
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

		-- === Inputs → live config ===========================================
		
		-- This input is SEPARATE. It only affects the leaderboard.
		UI.Options.CNS_DisplayName:OnChanged(function(v)
			Variables.Config.FakeDisplayName = v or ""
			if Variables.RunFlag then
				applyPlayerFields() -- Dynamically update leaderboard
			end
		end)
		
		-- This input is SEPARATE. It only affects TextLabels.
		UI.Options.CNS_Username:OnChanged(function(v)
			Variables.Config.FakeName = v or ""
			if Variables.RunFlag then
				-- We must Stop/Start to replace the old hooks/text
				Stop()
				Start()
			end
		end)
		
		UI.Toggles.CNS_Enable:OnChanged(function(enabledState)
			if enabledState then Start() else Stop() end
		end)

		-- === Module API =====================================================
		return { Name = "ClientNameSpoof", Stop = Stop }
	end
end
