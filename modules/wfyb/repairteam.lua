-- modules/wfyb/repairteam.lua
do
    return function(ui)
        local rbxservice = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local maidclass  = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local state = {
            maid = maidclass.new(),
            run_flag = false,

            boat_search_timeout_seconds = 12,
            invoke_throttle_seconds = 1,
            rescan_interval_seconds = 0.5,

            last_invoke_time = 0,
            accumulated_time = 0,
            last_teammate_boat_model = nil,

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

        local function boat_owner_user_id(boat_model)
            if not (boat_model and boat_model:IsA("Model")) then return nil end
            local attrs = boat_model:GetAttributes()
            for k, v in pairs(attrs) do
                local lower = string.lower(k)
                if lower == "owneruserid" or lower == "owner" then
                    local n = tonumber(v); if n then return n end
                end
            end
            local data = boat_model:FindFirstChild("BoatData")
            if data then
                for _, ch in ipairs(data:GetChildren()) do
                    local lower = string.lower(ch.Name)
                    if ch:IsA("IntValue") and string.find(lower, "owner") then
                        return ch.Value
                    end
                    if ch:IsA("ObjectValue") and lower == "owner" then
                        local p = ch.Value; if p and p.UserId then return p.UserId end
                    end
                    if ch:IsA("StringValue") and string.find(lower, "owner") then
                        local n = tonumber(ch.Value); if n then return n end
                    end
                end
            end
            for _, d in ipairs(boat_model:GetDescendants()) do
                if d:IsA("IntValue") and (d.Name == "Owner" or d.Name == "OwnerUserId") then
                    return d.Value
                end
            end
            return nil
        end

        local function find_teammate_boat(timeout_seconds)
            local deadline = time() + (timeout_seconds or state.boat_search_timeout_seconds)
            local lp = rbxservice.Players.LocalPlayer
            repeat
                local folder = boats_folder()
                if folder and lp and lp.Team then
                    for _, boat in ipairs(folder:GetChildren()) do
                        if boat:IsA("Model") then
                            local owner_id = boat_owner_user_id(boat)
                            if owner_id and owner_id ~= lp.UserId then
                                local owner_plr = rbxservice.Players:GetPlayerByUserId(owner_id)
                                if owner_plr and owner_plr.Team == lp.Team then
                                    local binder = state.client_binders and state.client_binders.Boat and state.client_binders.Boat:Get(boat)
                                    return boat, binder
                                end
                            end
                        end
                    end
                end
                rbxservice.RunService.Heartbeat:Wait()
            until time() > deadline
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
                if (not state.last_teammate_boat_model) or (not state.last_teammate_boat_model.Parent) then
                    state.last_teammate_boat_model = select(1, find_teammate_boat(1.0))
                end
            end
            if not state.last_teammate_boat_model then return end

            local now = time()
            if now - state.last_invoke_time >= state.invoke_throttle_seconds then
                state.last_invoke_time = now
                try_repair(state.last_teammate_boat_model)
            end
        end

        local function start()
            if state.run_flag then return end
            state.run_flag = true
            ensure_nevermore()
            state.last_teammate_boat_model = select(1, find_teammate_boat(state.boat_search_timeout_seconds))
            local hb = rbxservice.RunService.Heartbeat:Connect(on_heartbeat)
            state.maid:GiveTask(hb)
            state.maid:GiveTask(function() state.run_flag = false end)
        end

        local function stop()
            state.run_flag = false
            state.last_teammate_boat_model = nil
            state.maid:DoCleaning()
        end

        local group = ui.Tabs.EXP:AddLeftGroupbox("EXP Farm", "arrow-right-left")
        group:AddToggle("AutoRepairTeamToggle", {
            Text = "Repair Team",
            Tooltip = "Turn Feature [ON/OFF].",
            Default = false,
        })
        ui.Toggles.AutoRepairTeamToggle:OnChanged(function(v)
            if v then start() else stop() end
        end)

        return { Name = "RepairTeam", Stop = stop }
    end
end
