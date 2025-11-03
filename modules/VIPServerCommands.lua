-- modules/VIPServerCommands.lua
do
    return function(UI)
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()

        local GlobalEnv = (getgenv and getgenv()) or _G
        GlobalEnv.Signal = GlobalEnv.Signal or loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()
        local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local Variables = {
            Maids = { VIPServerCommands = Maid.new() },
        }

        local function RunVipCommand(commandString)
            local defaultChatFolder = RbxService.ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents")
            if defaultChatFolder and defaultChatFolder:FindFirstChild("SayMessageRequest") then
                defaultChatFolder.SayMessageRequest:FireServer(commandString, "All")
                return
            end
            local textChannels = RbxService.TextChatService:FindFirstChild("TextChannels")
            local targetChannel = textChannels and (textChannels:FindFirstChild("RBXGeneral") or textChannels:FindFirstChild("General"))
            if targetChannel and targetChannel.SendAsync then
                targetChannel:SendAsync(commandString)
                return
            end
            warn("[VIP] No chat remotes or TextChat channel available.")
        end

        local ModuleApi = {}
        function ModuleApi.NextMode()
            RunVipCommand("/vipnextmode")
        end
        function ModuleApi.Freecam()
            local localPlayer = RbxService.Players.LocalPlayer
            if localPlayer and localPlayer.Name then
                RunVipCommand("/vipfreecam " .. localPlayer.Name)
            end
        end
        function ModuleApi.StopFreecam()
            local localPlayer = RbxService.Players.LocalPlayer
            if localPlayer and localPlayer.Name then
                RunVipCommand("/vipstopfreecam " .. localPlayer.Name)
            end
        end
        function ModuleApi.Stop()
            pcall(function() Variables.Maids.VIPServerCommands:DoCleaning() end)
        end

        -- UI
        local groupbox = UI.Tabs.Misc:AddLeftGroupbox("VIP Commands", "layout-dashboard")
        groupbox:AddButton({
            Text = "Next Mode",
            Func = function() ModuleApi.NextMode() end,
            DoubleClick = false,
            Tooltip = "Same as /vipnextmode.",
            DisabledTooltip = "Feature Disabled",
            Disabled = false,
        })
        groupbox:AddButton({
            Text = "Freecam",
            Func = function() ModuleApi.Freecam() end,
            DoubleClick = false,
            Tooltip = "Same as /vipfreecam.",
            DisabledTooltip = "Feature Disabled",
            Disabled = false,
        })
        groupbox:AddButton({
            Text = "Stop Freecam",
            Func = function() ModuleApi.StopFreecam() end,
            DoubleClick = false,
            Tooltip = "Same as /vipstopfreecam.",
            DisabledTooltip = "Feature Disabled",
            Disabled = false,
        })

        return { Name = "VIPServerCommands", Stop = ModuleApi.Stop }
    end
end
