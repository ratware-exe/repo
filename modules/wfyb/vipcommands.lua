-- modules/wfyb/VIPServerCommands.lua
-- Buttons to emit VIP chat commands (works with legacy and new TextChatService).

return function()
    local RbxService
    local Variables
    local Maid
    local Signal
    local Library

    local Module = {}

    function Module.Init(env)
        RbxService = env.RbxService
        Variables  = env.Variables
        Maid       = env.Maid
        Signal     = env.Signal
        Library    = env.Library
        if not Variables.Maids.VIPServerCommands then
            Variables.Maids.VIPServerCommands = Maid.new()
        end
    end

    local function sayMessage(text)
        -- Legacy chat
        local ChatEvents = RbxService.ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents")
        if ChatEvents and ChatEvents:FindFirstChild("SayMessageRequest") then
            pcall(function()
                ChatEvents.SayMessageRequest:FireServer(text, "All")
            end)
            return
        end
        -- New TextChatService
        local Channels = RbxService.TextChatService:FindFirstChild("TextChannels")
        if Channels then
            local General = Channels:FindFirstChild("RBXGeneral") or Channels:FindFirstChild("General")
            if General and General.SendAsync then
                pcall(function()
                    General:SendAsync(text)
                end)
            end
        end
    end

    function Module.BuildUI(Tabs)
        local Group = Tabs.Misc:AddLeftGroupbox("VIP Commands", "layout-dashboard")

        Group:AddButton({ Text = "Next Mode", Func = function()
            sayMessage("/vipnextmode")
        end })

        Group:AddButton({ Text = "Freecam (Me)", Func = function()
            local LocalPlayer = RbxService.Players.LocalPlayer
            if LocalPlayer and LocalPlayer.Name then
                sayMessage("/vipfreecam " .. LocalPlayer.Name)
            end
        end })

        Group:AddButton({ Text = "Stop Freecam (Me)", Func = function()
            local LocalPlayer = RbxService.Players.LocalPlayer
            if LocalPlayer and LocalPlayer.Name then
                sayMessage("/vipstopfreecam " .. LocalPlayer.Name)
            end
        end })
    end

    function Module.Start() end
    function Module.Stop()
        if Variables.Maids.VIPServerCommands then
            Variables.Maids.VIPServerCommands:DoCleaning()
        end
    end

    return Module
end
