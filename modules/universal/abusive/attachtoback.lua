-- modules/universal/rage/attachtoback.lua
do
    return function(UI)
        -- [1] LOAD DEPENDENCIES
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv = (getgenv and getgenv()) or _G
        local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        -- [2] MODULE STATE
        local ModuleName = "AttachToBack"
        local Variables = {
            Maids = { [ModuleName] = Maid.new() },
            RunFlag = false, -- Corresponds to AttachToBackEnabled
            AttachToBackTargetName = "",
            AttachToBackOffsetX = 0,
            AttachToBackOffsetY = 0,
            AttachToBackOffsetZ = 2,
            AttachToBackCurrentWeld = nil,
        }

        -- [3] CORE LOGIC
        local function ATB_DestroyWeld()
            if Variables.AttachToBackCurrentWeld then
                pcall(function() Variables.AttachToBackCurrentWeld:Destroy() end)
                Variables.AttachToBackCurrentWeld = nil
            end
            
            -- Clean up character removing connections
            local maid = Variables.Maids[ModuleName]
            if maid["ATB_LocalCharRemoving"] then
                maid.ATB_LocalCharRemoving = nil -- Disconnects via Maid's __newindex
            end
            if maid["ATB_TargetCharRemoving"] then
                maid.ATB_TargetCharRemoving = nil
            end
        end

        local function onHeartbeat()
            if not Variables.RunFlag then return end
            
            pcall(function()
                local LocalPlayer = RbxService.Players.LocalPlayer
                if not LocalPlayer then
                    ATB_DestroyWeld()
                    return
                end
                
                if not (type(Variables.AttachToBackTargetName) == "string" and Variables.AttachToBackTargetName ~= "") then
                    ATB_DestroyWeld()
                    return
                end

                local targetPlayer = RbxService.Players:FindFirstChild(Variables.AttachToBackTargetName)
                if not targetPlayer then
                    ATB_DestroyWeld()
                    return
                end

                if not (LocalPlayer.Character
                    and targetPlayer.Character
                    and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                    and targetPlayer.Character:FindFirstChild("HumanoidRootPart")) then
                    ATB_DestroyWeld()
                    return
                end

                local attachToBackOffsetCFrame = CFrame.new(
                    tonumber(Variables.AttachToBackOffsetX) or 0,
                    tonumber(Variables.AttachToBackOffsetY) or 0,
                    tonumber(Variables.AttachToBackOffsetZ) or 2
                )

                if not Variables.AttachToBackCurrentWeld then
                    -- initial snap
                    (LocalPlayer.Character:FindFirstChild("HumanoidRootPart")).CFrame =
                        (targetPlayer.Character:FindFirstChild("HumanoidRootPart")).CFrame * attachToBackOffsetCFrame

                    local newWeld = Instance.new("Weld")
                    newWeld.Name = "HummanoidRootBody"
                    newWeld.Part0 = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
                    newWeld.Part1 = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                    newWeld.C0 = attachToBackOffsetCFrame
                    newWeld.C1 = CFrame.new()
                    newWeld.Parent = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                    Variables.AttachToBackCurrentWeld = newWeld

                    -- cleanup on either character despawn
                    Variables.Maids[ModuleName].ATB_LocalCharRemoving =
                        LocalPlayer.CharacterRemoving:Connect(ATB_DestroyWeld)
                    
                    Variables.Maids[ModuleName].ATB_TargetCharRemoving =
                        targetPlayer.CharacterRemoving:Connect(ATB_DestroyWeld)
                else
                    -- live offset updates
                    Variables.AttachToBackCurrentWeld.C0 = attachToBackOffsetCFrame
                end
            end)
        end

        local function Start()
            if Variables.RunFlag then return end
            Variables.RunFlag = true
            
            local maid = Variables.Maids[ModuleName]
            maid:GiveTask(RbxService.RunService.Heartbeat:Connect(onHeartbeat))
            maid:GiveTask(function() Variables.RunFlag = false end)
            maid:GiveTask(ATB_DestroyWeld) -- Final cleanup
        end

        local function Stop()
            if not Variables.RunFlag then return end
            Variables.RunFlag = false
            Variables.Maids[ModuleName]:DoCleaning()
        end

        -- [4] UI CREATION
        local AttachToBackGroupBox = UI.Tabs.Main:AddLeftGroupbox("Attach To Back", "paperclip")
		AttachToBackGroupBox:AddDropdown("AttachToBackDropdown", {
			SpecialType = "Player",
			ExcludeLocalPlayer = true, 
			Text = "Select Target:",
			Tooltip = "Select attach to back target player.", 
		})
		local AttachToBackToggle = AttachToBackGroupBox:AddToggle("AttachToBackToggle", {
			Text = "Enable",
			Tooltip = "Turns attach to back [ON]/[OFF].", 
			Default = false, 
		})
		UI.Toggles.AttachToBackToggle:AddKeyPicker("AttachToBackKeybind", {
			Text = "Attach To Back",
			SyncToggleState = true,
			Mode = "Toggle", 
		})
		AttachToBackGroupBox:AddSlider("AttachToBackToggleXSlider", {
			Text = "[X] Distance",
			Default = 0,
			Min = -250,
			Max = 250,
			Rounding = 1,
			Compact = true,
			Tooltip = "Changes attach to back [X] axis distance.", 
		})
		AttachToBackGroupBox:AddSlider("AttachToBackToggleYSlider", {
			Text = "[Y] Distance",
			Default = 0,
			Min = -250,
			Max = 250,
			Rounding = 1,
			Compact = true,
			Tooltip = "Changes attach to back [Y] axis distance.", 
		})
		AttachToBackGroupBox:AddSlider("AttachToBackToggleZSlider", {
			Text = "[Z] Distance",
			Default = 2, -- Default was 0 in UI but 2 in logic, using 2 to match logic
			Min = -250,
			Max = 250,
			Rounding = 1,
			Compact = true,
			Tooltip = "Changes attach to back [Z] axis distance.", 
		})

        -- [5] UI WIRING (CORRECTED)
        UI.Toggles.AttachToBackToggle:OnChanged(function(enabledState)
            if enabledState then Start() else Stop() end
        end)
        
        local function updateTarget(value)
            if typeof(value) == "Instance" and value:IsA("Player") then
                Variables.AttachToBackTargetName = value.Name
            elseif type(value) == "string" then
                Variables.AttachToBackTargetName = value
            else
                Variables.AttachToBackTargetName = ""
            end
            ATB_DestroyWeld() -- Drop stale weld when target changes
        end
        UI.Options.AttachToBackDropdown:OnChanged(updateTarget)
        
        UI.Options.AttachToBackToggleXSlider:OnChanged(function(n) Variables.AttachToBackOffsetX = tonumber(n) or 0 end)
        UI.Options.AttachToBackToggleYSlider:OnChanged(function(n) Variables.AttachToBackOffsetY = tonumber(n) or 0 end)
        UI.Options.AttachToBackToggleZSlider:OnChanged(function(n) Variables.AttachToBackOffsetZ = tonumber(n) or 2 end)
        
        -- Seed default values
        updateTarget(UI.Options.AttachToBackDropdown.Value)
        Variables.AttachToBackOffsetX = tonumber(UI.Options.AttachToBackToggleXSlider.Value) or 0
        Variables.AttachToBackOffsetY = tonumber(UI.Options.AttachToBackToggleYSlider.Value) or 0
        Variables.AttachToBackOffsetZ = tonumber(UI.Options.AttachToBackToggleZSlider.Value) or 2
        
        -- Start if already enabled
        if UI.Toggles.AttachToBackToggle.Value then
            Start()
        end

        -- [6] RETURN MODULE
        return { Name = ModuleName, Stop = Stop }
    end
end
