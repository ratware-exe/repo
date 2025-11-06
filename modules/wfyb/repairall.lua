-- modules/wfyb/repairall.lua
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
            target_boats = {},
            boat_index = 1,

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
                    local n = tonumber(v)
                    if n then return n end
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
                        local plr = ch.Value; if plr and plr.UserId then return plr.UserId end
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

        local function is_mine_or_teammate(boat_model)
            local lp = rbxservice.Players.LocalPlayer
            if not lp then return false end
            local owner_id = boat_owner_user_id(boat_model)
            if not owner_id then return false end
            if owner_id == lp.UserId then return true end
            local owner_plr = rbxservice.Players:GetPlayerByUserId(owner_id)
            if owner_plr and lp.Team and owner_plr.Team == lp.Team then
                return true
            end
            return false
        end

        local function rebuild_targets()
            local folder = boats_folder()
            local list = {}
            if folder then
                for _, m in ipairs(folder:GetChildren()) do
                    if m:IsA("Model") and is_mine_or_teammate(m) then
                        table.insert(list, m)
                    end
                end
            end
            state.target_boats = list
            if state.boat_index > #state.target_boats then
                state.boat_index = 1
            end
        end

        local function try_repair(boat_model)
            if not (state.boat_remote and boat_model) then return end
            pcall(function()
                state.boat_remote:InvokeServer("RepairBoat", boat_model)
            end)
        end

        local function on_heartbeat(dt)
            state.accumulated_time = state.accumulated_time + dt
            if state.accumulated_time >= state.rescan_interval_seconds then
                state.accumulated_time = 0
                rebuild_targets()
            end
            if not state.run_flag then return end

            local list = state.target_boats
            if not list or #list == 0 then return end

            local now = time()
            if now - state.last_invoke_time < state.invoke_throttle_seconds then return end
            state.last_invoke_time = now

            local index = state.boat_index
            if index < 1 then index = 1 end
            if index > #list then index = 1 end

            local model = list[index]
            state.boat_index = (index % #list) + 1

            if model and model.Parent then
                try_repair(model)
            end
        end

        local function start()
            if state.run_flag then return end
            state.run_flag = true
            state.last_invoke_time = 0
            state.accumulated_time = 0
            state.boat_index = 1
            ensure_nevermore()
            rebuild_targets()
            local hb = rbxservice.RunService.Heartbeat:Connect(on_heartbeat)
            state.maid:GiveTask(hb)
            state.maid:GiveTask(function() state.run_flag = false end)
        end

        local function stop()
            state.run_flag = false
            state.target_boats = {}
            state.boat_index = 1
            state.last_invoke_time = 0
            state.accumulated_time = 0
            state.maid:DoCleaning()
        end

        -- ui
        local group = ui.Tabs.EXP:AddLeftGroupbox("EXP Farm", "arrow-right-left")
        group:AddToggle("AutoRepairAllToggle", {
            Text = "Repair All",
            Tooltip = "Turn Feature [ON/OFF].",
            Default = false,
        })
        ui.Toggles.AutoRepairAllToggle:OnChanged(function(v)
            if v then start() else stop() end
        end)

        return { Name = "RepairAll", Stop = stop }
    end
end
