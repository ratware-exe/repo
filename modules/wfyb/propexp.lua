-- modules/wfyb/propexp.lua
do
    return function(ui)
        local rbxservice = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local maidclass  = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local state = {
            maid = maidclass.new(),
            run_flag = false,

            interval_seconds = 2.0,
            resolve_tick_seconds = 0.25,
            retry_seconds = 0.70,

            relative_cframe = CFrame.new(0, 1.6, 0),
            boat_search_timeout_seconds = 12,
            spawn_y_offset = 0,

            pink_class = nil,
            own_boat_model = nil,

            nevermore = nil,
            boat_api = nil,
            prop_class_provider = nil,
            client_binders = nil,
        }

        -- === helpers ===
        local function safe_call(target, method_name, ...)
            local method = target and target[method_name]
            if type(method) ~= "function" then return nil end
            local args = { ... }
            local ok, res = pcall(function() return method(target, table.unpack(args)) end)
            if ok and res ~= nil then return res end
            ok, res = pcall(function() return method(table.unpack(args)) end)
            if ok and res ~= nil then return res end
            return nil
        end

        local function round4(n)
            return math.floor((n or 0) * 10000 + 0.5) / 10000
        end

        local function quantize_cframe(cf)
            local x,y,z,r00,r01,r02,r10,r11,r12,r20,r21,r22 = cf:GetComponents()
            return CFrame.new(
                round4(x),round4(y),round4(z),
                round4(r00),round4(r01),round4(r02),
                round4(r10),round4(r11),round4(r12),
                round4(r20),round4(r21),round4(r22)
            )
        end

        local function boats_folder()
            return rbxservice.Workspace:FindFirstChild("Boats")
        end

        local function boat_owner_user_id(boat_model)
            if not (boat_model and boat_model:IsA("Model")) then return nil end

            -- attributes path
            local attrs = boat_model:GetAttributes()
            for k, v in pairs(attrs) do
                local lower = string.lower(k)
                if lower == "owneruserid" or lower == "owner" then
                    local as_number = tonumber(v)
                    if as_number then return as_number end
                end
            end

            -- BoatData path
            local data = boat_model:FindFirstChild("BoatData")
            if data then
                for _, child in ipairs(data:GetChildren()) do
                    local lname = string.lower(child.Name)
                    if child:IsA("IntValue") and string.find(lname, "owner") then
                        return child.Value
                    end
                    if child:IsA("ObjectValue") and lname == "owner" then
                        local owner_plr = child.Value
                        if owner_plr and owner_plr.UserId then return owner_plr.UserId end
                    end
                    if child:IsA("StringValue") and string.find(lname, "owner") then
                        local as_number = tonumber(child.Value)
                        if as_number then return as_number end
                    end
                end
            end

            -- descendants fallback
            for _, v in ipairs(boat_model:GetDescendants()) do
                if v:IsA("IntValue") and (v.Name == "Owner" or v.Name == "OwnerUserId") then
                    return v.Value
                end
            end

            return nil
        end

        local function find_own_boat()
            local folder = boats_folder()
            if not folder then return nil end
            local lp = rbxservice.Players.LocalPlayer
            if not lp then return nil end

            for _, m in ipairs(folder:GetChildren()) do
                if m:IsA("Model") and boat_owner_user_id(m) == lp.UserId then
                    return m
                end
            end
            return nil
        end

        local function snapshot_owned_boats(user_id)
            local out = {}
            local folder = boats_folder()
            if folder then
                for _, m in ipairs(folder:GetChildren()) do
                    if m:IsA("Model") and boat_owner_user_id(m) == user_id then
                        out[m] = true
                    end
                end
            end
            return out
        end

        local function wait_for_new_owned_boat(user_id, before_set, timeout_seconds)
            local deadline = time() + (timeout_seconds or state.boat_search_timeout_seconds)
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

        local pink_id_candidates   = { "PinkGyro", "PinkExperimental", "PinkExperimentalBlock", "ExperimentalBlockPink" }
        local pink_tkey_candidates = { "props.pinkGyro", "props.pinkExperimental", "props.pink_experimental" }

        local function ensure_nevermore_ready()
            if not state.nevermore then
                state.nevermore = require(rbxservice.ReplicatedStorage:WaitForChild("Nevermore"))
            end
            if not state.boat_api then
                state.boat_api = state.nevermore("BoatAPIServiceClient")
            end
            if not state.prop_class_provider then
                local ok, client_provider = pcall(function()
                    return state.nevermore("PropClassProviderClient")
                end)
                state.prop_class_provider = ok and client_provider or state.nevermore("PropClassProvider")
            end
            if not state.client_binders then
                state.client_binders = state.nevermore("ClientBinders")
            end
        end

        local function resolve_pink_class()
            if state.pink_class or not state.prop_class_provider then return state.pink_class ~= nil end

            for _, id in ipairs(pink_id_candidates) do
                local class =
                    safe_call(state.prop_class_provider, "GetPropClassFromPropId", id) or
                    safe_call(state.prop_class_provider, "GetFromPropId", id) or
                    safe_call(state.prop_class_provider, "FromPropId", id) or
                    safe_call(state.prop_class_provider, "GetPropClass", id) or
                    safe_call(state.prop_class_provider, "Get", id)
                if class then
                    state.pink_class = class
                    return true
                end
            end

            for _, tkey in ipairs(pink_tkey_candidates) do
                local class =
                    safe_call(state.prop_class_provider, "GetPropClassFromTranslationKey", tkey) or
                    safe_call(state.prop_class_provider, "GetFromTranslationKey", tkey) or
                    safe_call(state.prop_class_provider, "FromTranslationKey", tkey)
                if class then
                    state.pink_class = class
                    return true
                end
            end

            return false
        end

        local function get_prop_binder(model)
            local ok, binder = pcall(function()
                return state.client_binders.Prop:Get(model)
            end)
            if ok and binder then return binder end
            return nil
        end

        local function model_world_cframe(model)
            local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
            return primary and primary.CFrame or nil
        end

        local function find_newly_placed_pink(boat_model, desired_world, timeout_seconds)
            local deadline = time() + (timeout_seconds or 3)
            local best, best_dist = nil, math.huge
            repeat
                for _, child in ipairs(boat_model:GetChildren()) do
                    if child:IsA("Model") and get_prop_binder(child) then
                        local lname = string.lower(child.Name)
                        if string.find(lname, "pink") or string.find(lname, "gyro") or string.find(lname, "experimental") then
                            local cf = model_world_cframe(child)
                            if cf then
                                local d = (cf.Position - desired_world.Position).Magnitude
                                if d < best_dist then
                                    best, best_dist = child, d
                                end
                            end
                        end
                    end
                end
                if best then return best end
                rbxservice.RunService.Heartbeat:Wait()
            until time() > deadline
            return nil
        end

        local function place_with_retry(relative, boat_model)
            local ok = pcall(function()
                state.boat_api:PlacePropOnBoat(state.pink_class, relative, boat_model)
            end)
            if ok then return true end
            task.wait(state.retry_seconds)
            return pcall(function()
                state.boat_api:PlacePropOnBoat(state.pink_class, relative, boat_model)
            end) == true
        end

        local function ensure_own_boat()
            if state.own_boat_model and state.own_boat_model.Parent then
                return true
            end

            local existing = find_own_boat()
            if existing then
                state.own_boat_model = existing
                return true
            end

            if not state.pink_class then return false end

            local lp = rbxservice.Players.LocalPlayer
            if not lp then return false end
            local char = lp.Character or lp.CharacterAdded:Wait()
            local root = char:WaitForChild("HumanoidRootPart")
            local pivot = root.CFrame * CFrame.new(0, tonumber(state.spawn_y_offset) or 0, 0)

            local before = snapshot_owned_boats(lp.UserId)
            pcall(function()
                state.boat_api:PlaceNewBoat(state.pink_class, pivot)
            end)

            local new_model = wait_for_new_owned_boat(lp.UserId, before, state.boat_search_timeout_seconds)
            if not new_model then return false end

            local initial = find_newly_placed_pink(new_model, pivot, 3)
            if initial then
                pcall(function() state.boat_api:SellProp(initial) end)
            end

            state.own_boat_model = new_model
            return true
        end

        local function place_and_sell_once()
            if not (state.own_boat_model and state.pink_class) then return end
            local relative_q = quantize_cframe(state.relative_cframe)
            local desired_world = state.own_boat_model:GetPivot() * relative_q

            if not place_with_retry(relative_q, state.own_boat_model) then
                return
            end

            local placed = find_newly_placed_pink(state.own_boat_model, desired_world, 3)
            if placed then
                pcall(function() state.boat_api:SellProp(placed) end)
            end
        end

        -- === lifecycle ===
        local function start()
            if state.run_flag then return end
            state.run_flag = true

            ensure_nevermore_ready()
            if not state.pink_class then resolve_pink_class() end
            if not state.own_boat_model then state.own_boat_model = find_own_boat() end

            local worker = task.spawn(function()
                while state.run_flag do
                    if not state.pink_class then
                        if not resolve_pink_class() then
                            task.wait(state.resolve_tick_seconds)
                            continue
                        end
                    end

                    if not ensure_own_boat() then
                        task.wait(state.resolve_tick_seconds)
                        continue
                    end

                    place_and_sell_once()
                    task.wait(state.interval_seconds)
                end
            end)

            state.maid:GiveTask(worker)
            state.maid:GiveTask(function() state.run_flag = false end)
        end

        local function stop()
            state.run_flag = false
            state.maid:DoCleaning()
        end

        -- === ui ===
        local group = ui.Tabs.EXP:AddLeftGroupbox("EXP Farm", "arrow-right-left")
        group:AddToggle("AutoPropEXPToggle", {
            Text = "Prop EXP",
            Tooltip = "Turn Feature [ON/OFF].",
            Default = false,
        })
        ui.Toggles.AutoPropEXPToggle:OnChanged(function(enabled)
            if enabled then start() else stop() end
        end)

        return { Name = "PropEXP", Stop = stop }
    end
end
