-- modules/wfyb/pvpmode.lua
do
    return function(ui)
        local rbxservice = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local maidclass  = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local state = {
            maid = maidclass.new(),
            run_flag = false,
            send_interval_seconds = 0.1,
            last_send_time = 0,

            nevermore = nil,
            game_mode_manager = nil,
        }

        local function ensure_nevermore()
            if not state.nevermore then
                state.nevermore = require(rbxservice.ReplicatedStorage:WaitForChild("Nevermore"))
            end
            if not state.game_mode_manager then
                state.game_mode_manager = state.nevermore("GameModeManager")
            end
        end

        local function run_vip_cmd(text)
            local chat_events = rbxservice.ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents")
            if chat_events and chat_events:FindFirstChild("SayMessageRequest") then
                chat_events.SayMessageRequest:FireServer(text, "All")
                return
            end
            local channels = rbxservice.TextChatService:FindFirstChild("TextChannels")
            local target = channels and (channels:FindFirstChild("RBXGeneral") or channels:FindFirstChild("General"))
            if target and target.SendAsync then target:SendAsync(text) end
        end

        local function combat_enabled()
            ensure_nevermore()
            local mgr = state.game_mode_manager
            if not mgr then return false end
            local mode = mgr:GetMode("CombatEnabled")
            return mode and mode.Enabled == true
        end

        local function on_heartbeat()
            if not state.run_flag then return end
            if combat_enabled() then return end
            local now = time()
            if now - state.last_send_time >= state.send_interval_seconds then
                state.last_send_time = now
                run_vip_cmd("/vipnextmode")
            end
        end

        local function start()
            if state.run_flag then return end
            state.run_flag = true
            state.last_send_time = 0
            ensure_nevermore()
            local mgr = state.game_mode_manager
            if mgr then
                local mode = mgr:GetMode("CombatEnabled")
                if mode and mode.EnabledChanged then
                    local c = mode.EnabledChanged:Connect(function() end)
                    state.maid:GiveTask(c)
                end
            end
            local hb = rbxservice.RunService.Heartbeat:Connect(on_heartbeat)
            state.maid:GiveTask(hb)
            state.maid:GiveTask(function() state.run_flag = false end)
        end

        local function stop()
            state.run_flag = false
            state.maid:DoCleaning()
        end

        local group = ui.Tabs.EXP:AddLeftGroupbox("EXP Farm", "arrow-right-left")
        group:AddToggle("AutoPVPModeToggle", {
            Text = "PVP Mode",
            Tooltip = "Turn Feature [ON/OFF].",
            Default = false,
        })
        ui.Toggles.AutoPVPModeToggle:OnChanged(function(v)
            if v then start() else stop() end
        end)

        return { Name = "PVPMode", Stop = stop }
    end
end
