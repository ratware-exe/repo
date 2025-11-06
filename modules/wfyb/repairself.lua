-- modules/wfyb/repairself.lua
do
    return function(ui)
        local rbxservice = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local maidclass  = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local state = {
            maid = maidclass.new(),
            run_flag = false,

            boat_search_timeout_seconds = 12,
            invoke_throttle_seconds = 0.1,
            rescan_interval_seconds = 0.1,

            last_invoke_time = 0,
            accumulated_time = 0,
            last_own_boat_model = nil,

            nevermore = nil,
            get_remote_function = nil,
            boat_constants = nil,
            client_binders = nil,
            boat_remote = nil,
        }

        local function ensure_nevermore()
            if not state.nevermore then
                state.nevermore = require(rbxservice.ReplicatedStorage:WaitForChild("Nevermore"))
            end
            if not state.get_remote_function then
                state.get_remote_function = state.nevermore("GetRemoteFunction")
            end
            if not state.boat_constants then
                state.boat_constants = state.nevermore("BoatConstants")
            end
            if not state.client_binders then
                state.client_binders = state.nevermore("ClientBinders")
            end
            if not state.boat_remote then
                state.boat_remote = state.get_remote_function(state.boat_constants.API_REMOTE_FUNCTION)
            end
        end

        local function boats_folder()
            return rbxservice.Workspace:FindFirstChild("Boats")
        end

        local function wait_for_boat_binder(boat_model, timeout_seconds)
            local deadline = os.clock() + (timeout_seconds or 6)
            repeat
                local has = state.client_binders and state.client_binders.Boat and state.client_binders.Boat:Get(boat_model)
                if has then return has end
                rbxservice.RunService.Heartbeat:Wait()
            until os.clock() > deadline
            return nil
        end

        local function find_own_boat_model(timeout_seconds)
            local deadline = os.clock() + (timeout_seconds or state.boat_search_timeout_seconds)
            local lp = rbxservice.Players.LocalPlayer
            repeat
                local folder = boats_folder()
                if folder and lp then
                    for _, m in ipairs(folder:GetChildren()) do
                        if m:IsA("Model") then
                            local binder = (state.client_binders and state.client_binders.Boat and state.client_binders.Boat:Get(m))
                                or wait_for_boat_binder(m, 1.0)
                            if binder and binder.CanModify and binder:CanModify(lp) then
                                return m, binder
                            end
                        end
                    end
                end
                rbxservice.RunService.Heartbeat:Wait()
            until os.clock() > deadline
            return nil, nil
        end

        local function try_repair(boat_model)
            if not (state.boat_remote and boat_model) then return end
            pcall(function()
                state.boat_remote:InvokeServer("RepairBoat", boat_model)
            end)
        end

        local function on_heartbeat(dt)
            if not state.run_flag then return end

            state.accumulated_time = state.accumulated_time + dt
            if state.accumulated_time >= state.rescan_interval_seconds then
                state.accumulated_time = 0
                if (not state.last_own_boat_model) or (not state.last_own_boat_model.Parent) then
                    local found = select(1, find_own_boat_model(1.0))
                    if found then state.last_own_boat_model = found end
                end
            end

            if not state.last_own_boat_model then return end

            local now = time()
            if now - state.last_invoke_time >= state.invoke_throttle_seconds then
                state.last_invoke_time = now
                try_repair(state.last_own_boat_model)
            end
        end

        local function start()
            if state.run_flag then return end
            state.run_flag = true
            ensure_nevermore()
            state.last_own_boat_model = select(1, find_own_boat_model(state.boat_search_timeout_seconds))
            local hb = rbxservice.RunService.Heartbeat:Connect(on_heartbeat)
            state.maid:GiveTask(hb)
            state.maid:GiveTask(function() state.run_flag = false end)
        end

        local function stop()
            state.run_flag = false
            state.last_own_boat_model = nil
            state.maid:DoCleaning()
        end

        -- ui
        local group = ui.Tabs.EXP:AddLeftGroupbox("EXP Farm", "arrow-right-left")
        group:AddToggle("AutoRepairSelfToggle", {
            Text = "Repair Self",
            Tooltip = "Turn Feature [ON/OFF].",
            Default = false,
        })
        ui.Toggles.AutoRepairSelfToggle:OnChanged(function(v)
            if v then start() else stop() end
        end)

        return { Name = "RepairSelf", Stop = stop }
    end
end
