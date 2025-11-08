-- "modules/universal/travel/teleportplayer.lua",
do
    return function(UI)
        -- [1] LOAD DEPENDENCIES
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv = (getgenv and getgenv()) or _G
        local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        -- [2] MODULE STATE
        local ModuleName = "TeleportPlayer"
        local Variables = {
            Maids = { [ModuleName] = Maid.new() },
            PlayerTPTargetName = "",
            NotifyFunc = nil, -- Placeholder for notifier
        }

        -- [3] CORE LOGIC
        local function notify(msg)
            if Variables.NotifyFunc then
                pcall(Variables.NotifyFunc, msg)
            else
                print(msg) -- Fallback
            end
        end

        local function PlayerTPTeleportOnce()
            local PlayerTPChosenTargetName = Variables.PlayerTPTargetName
            
            if type(PlayerTPChosenTargetName) ~= "string" or PlayerTPChosenTargetName == "" then
                notify("Player TP: Please Select Target!")
                return
            end

            local PlayerTPTargetPlayer = RbxService.Players:FindFirstChild(PlayerTPChosenTargetName)
            if not PlayerTPTargetPlayer then
                notify("Player TP: Target Not Found!")
                return
            end
            
            local LocalPlayer = RbxService.Players.LocalPlayer
            if not (LocalPlayer and LocalPlayer.Character) then
                notify("Player TP: You're Not Spawned In!.")
                return
            end

            local PlayerTPLocalCharacter = LocalPlayer.Character
            local PlayerTPTargetCharacter = PlayerTPTargetPlayer.Character
            if not (PlayerTPLocalCharacter and PlayerTPTargetCharacter) then
                notify("Player TP: Character Missing!")
                return
            end

            local PlayerTPLocalHumanoidRootPart = PlayerTPLocalCharacter:FindFirstChild("HumanoidRootPart")
            local PlayerTPTargetHumanoidRootPart = PlayerTPTargetCharacter:FindFirstChild("HumanoidRootPart")
            if not (PlayerTPLocalHumanoidRootPart and PlayerTPTargetHumanoidRootPart) then
                notify("Player TP: Target Not Found!")
                return
            end

            PlayerTPLocalHumanoidRootPart.CFrame = PlayerTPTargetHumanoidRootPart.CFrame
            notify(("Teleported To Player: %s"):format(PlayerTPChosenTargetName))
        end

        local function Start() end
        local function Stop()
            Variables.Maids[ModuleName]:DoCleaning()
        end

        -- [4] UI CREATION
        local TeleportBox = UI.Tabs.Main:AddRightTabbox("Teleport") 
		local PlayerTPTabBox = TeleportBox:AddTab("Player TP")
        PlayerTPTabBox:AddDropdown("PlayerTPDropdown", {
            SpecialType = "Player",
            ExcludeLocalPlayer = true, 
            Text = "Select Player:",
            Tooltip = "Select player to tp to.", 
        })
        local PlayerTPButton = PlayerTPTabBox:AddButton({
            Text = "Teleport To Player",
            Func = function() end, -- Wired below
            DoubleClick = true,
            Tooltip = "Double click to teleport to player.",
        })
        
        -- [5] UI WIRING
        local function updateTarget(PlayerTPDropdownValue)
            if typeof(PlayerTPDropdownValue) == "Instance" and PlayerTPDropdownValue:IsA("Player") then
                Variables.PlayerTPTargetName = PlayerTPDropdownValue.Name
            elseif type(PlayerTPDropdownValue) == "string" then
                Variables.PlayerTPTargetName = PlayerTPDropdownValue
            else
                Variables.PlayerTPTargetName = ""
            end
        end
        
        UI.Options.PlayerTPDropdown:OnChanged(updateTarget)
        updateTarget(UI.Options.PlayerTPDropdown.Value) -- Seed initial value
        
        local function PlayerTPButtonCallback()
            -- re-read UI selection just before teleport
            updateTarget(UI.Options.PlayerTPDropdown.Value)
            PlayerTPTeleportOnce()
        end
        
        if PlayerTPButton.SetCallback then
            PlayerTPButton:SetCallback(PlayerTPButtonCallback)
        else
            PlayerTPButton.Func = PlayerTPButtonCallback
        end

        Variables.Maids[ModuleName]:GiveTask(function()
            if PlayerTPButton.SetCallback then
                PlayerTPButton:SetCallback(function() end)
            else
                PlayerTPButton.Func = function() end
            end
        end)

        -- [6] RETURN MODULE
        return { Name = ModuleName, Stop = Stop }
    end
end
