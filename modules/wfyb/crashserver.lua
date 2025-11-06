-- modules/wfyb/crashserver.lua
do
    return function(ui)
        local rbxservice = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local maidclass  = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local state = {
            maid = maidclass.new(),
            run_flag = false,

            spawn_throttle_seconds = 5,
            stack_gap_y = 10,
            boat_extents_y = nil,

            selected_boat_name = nil,
            selected_boat_id = nil,

            boat_id_by_name = {},
            boat_raw_by_id  = {},
            values_cache = {},

            target_world_pivot = nil,

            nevermore = nil,
            save_client = nil,

            ui_gate = nil,
        }

        local function ensure_deps()
            if not state.nevermore then
                state.nevermore = require(rbxservice.ReplicatedStorage:WaitForChild("Nevermore"))
            end
            if not state.save_client then
                state.save_client = state.nevermore("BoatSaveManagerClient")
            end
        end

        local function boats_folder()
            return rbxservice.Workspace:FindFirstChild("Boats")
        end

        local function boat_owner_user_id(boat)
            if not (boat and boat:IsA("Model")) then return nil end
            local attrs = boat:GetAttributes()
            for k, v in pairs(attrs) do
                local lower = string.lower(k)
                if lower == "owneruserid" or lower == "owner" then
                    local n = tonumber(v); if n then return n end
                end
            end
            local data = boat:FindFirstChild("BoatData")
            if data then
                for _, ch in ipairs(data:GetChildren()) do
                    local lower = string.lower(ch.Name)
                    if ch:IsA("IntValue") and string.find(lower, "owner") then return ch.Value end
                    if ch:IsA("ObjectValue") and lower == "owner" then
                        local p = ch.Value; if p and p.UserId then return p.UserId end
                    end
                    if ch:IsA("StringValue") and string.find(lower, "owner") then
                        local n = tonumber(ch.Value); if n then return n end
                    end
                end
            end
            for _, d in ipairs(boat:GetDescendants()) do
                if d:IsA("IntValue") and (d.Name == "Owner" or d.Name == "OwnerUserId") then
                    return d.Value
                end
            end
            return nil
        end

        local function snapshot_owned(user_id)
            local map = {}
            local folder = boats_folder()
            if folder then
                for _, m in ipairs(folder:GetChildren()) do
                    if m:IsA("Model") and boat_owner_user_id(m) == user_id then
                        map[m] = true
                    end
                end
            end
            return map
        end

        local function wait_new_owned(user_id, before_set, timeout)
            local deadline = time() + (timeout or 12)
            while time() < deadline do
                local folder = boats_folder()
                if folder then
                    for _, m in ipairs(folder:GetChildren()) do
                        if m:IsA("Model") and boat_owner_user_id(m) == user_id and not before_set[m] then
                            return m
                        end
                    end
                end
                rbxservice.RunService.Heartbeat:Wait()
            end
            return nil
        end

        local function pivot_with_offset(base, dy)
            local rot = base - base.Position
            local pos = base.Position + Vector3.new(0, dy, 0)
            return CFrame.new(pos) * rot
        end

        -- dropdown helpers
        local function queue_dropdown_values(values)
            state.values_cache = values
            if state.ui_gate then
                state.ui_gate:Fire(values)
            end
        end

        local function refresh_dropdown()
            ensure_deps()
            local promise = state.save_client and state.save_client:GetBoatSlots()
            if promise and typeof(promise) == "table" and promise.Then then
                promise
                    :Then(function(slots)
                        state.boat_id_by_name = {}
                        state.boat_raw_by_id  = {}
                        local values = {}
                        if typeof(slots) == "table" then
                            for _, slot in ipairs(slots) do
                                local has = (slot and (slot.HasBoat == true or slot.hasBoat == true or slot.SaveExists == true))
                                if has then
                                    local name = slot.SlotName or slot.Name or ("Slot " .. tostring(slot.SlotKey or slot.Id or "?"))
                                    local id   = slot.SlotKey or slot.Id or slot.Key
                                    if name and id ~= nil then
                                        state.boat_id_by_name[name] = id
                                        state.boat_raw_by_id[id]    = slot
                                        table.insert(values, name)
                                    end
                                end
                            end
                        end
                        queue_dropdown_values(values)
                    end)
                    :Catch(function() end)
            end
        end

        local function start()
            if state.run_flag then return end
            state.run_flag = true
            ensure_deps()

            if not state.selected_boat_name then
                state.run_flag = false
                state.maid:DoCleaning()
                return
            end

            state.selected_boat_id = state.boat_id_by_name[state.selected_boat_name]
            if state.selected_boat_id == nil then
                state.run_flag = false
                state.maid:DoCleaning()
                return
            end

            local worker = task.spawn(function()
                while state.run_flag do
                    local lp = rbxservice.Players.LocalPlayer
                    local before = snapshot_owned(lp.UserId)

                    local pivot
                    if state.target_world_pivot then
                        local extra_up = (state.boat_extents_y or 10) + (state.stack_gap_y or 2)
                        pivot = pivot_with_offset(state.target_world_pivot, extra_up)
                    else
                        local char = (lp.Character or lp.CharacterAdded:Wait())
                        local root = char:WaitForChild("HumanoidRootPart")
                        pivot = root.CFrame
                    end

                    pcall(function()
                        state.save_client:LoadBoat(pivot, state.selected_boat_id)
                    end)

                    local new_model = wait_new_owned(lp.UserId, before, 12)
                    if new_model then
                        state.target_world_pivot = new_model:GetPivot()
                        if not state.boat_extents_y then
                            local y = new_model:GetExtentsSize().Y
                            if y and y > 0 then state.boat_extents_y = y end
                        end
                    end

                    task.wait(state.spawn_throttle_seconds)
                end
            end)

            state.maid:GiveTask(worker)
            state.maid:GiveTask(function() state.run_flag = false end)
        end

        local function stop()
            state.run_flag = false
            state.maid:DoCleaning()
        end

        -- ui
        local left = ui.Tabs.Dupe:AddRightGroupbox("Step #2", "bomb")
        left:AddDropdown("BoatDropdown", {
            Text = "Save Slot:",
            Values = state.values_cache,
            Multi = false,
        })
        if ui.Options and ui.Options.BoatDropdown and ui.Options.BoatDropdown.OnChanged then
            ui.Options.BoatDropdown:OnChanged(function(name)
                state.selected_boat_name = name
                state.selected_boat_id = state.boat_id_by_name and state.boat_id_by_name[name] or nil
            end)
        end

        left:AddToggle("CrashServerToggle", {
            Text = "Crash Server",
            Tooltip = "Turn Feature [ON/OFF].",
            Default = false,
        })
        ui.Toggles.CrashServerToggle:OnChanged(function(v)
            if v then start() else stop() end
        end)

        -- live dropdown refresh bridge
        state.ui_gate = state.ui_gate or Instance.new("BindableEvent")
        state.maid:GiveTask(state.ui_gate)
        local conn = state.ui_gate.Event:Connect(function(values)
            if ui.Options and ui.Options.BoatDropdown and ui.Options.BoatDropdown.SetValues then
                ui.Options.BoatDropdown:SetValues(values)
            end
        end)
        state.maid:GiveTask(conn)

        -- initial push
        task.defer(function() refresh_dropdown() end)

        return { Name = "CrashServer", Stop = stop }
    end
end
