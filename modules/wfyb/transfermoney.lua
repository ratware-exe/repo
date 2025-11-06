-- modules/wfyb/transfermoney.lua
do
    return function(ui)
        local rbxservice = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local maidclass  = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local state = {
            maid = maidclass.new(),
            run_flag = false,

            place_throttle_seconds = 0,
            search_timeout_seconds = 0,
            relative_cframe = CFrame.new(0, 1.6, 0),

            placed_count = 0,
            sold_count   = 0,

            nevermore = nil,
            boat_api = nil,
            prop_class_provider = nil,
            client_binders = nil,
            pink_class = nil,
        }

        local function round4(n) return math.floor((n or 0) * 10000 + 0.5) / 10000 end
        local function quantize_cframe(cf)
            local x,y,z,r00,r01,r02,r10,r11,r12,r20,r21,r22 = cf:GetComponents()
            return CFrame.new(
                round4(x),round4(y),round4(z),
                round4(r00),round4(r01),round4(r02),
                round4(r10),round4(r11),round4(r12),
                round4(r20),round4(r21),round4(r22)
            )
        end

        local function ensure_deps()
            if not state.nevermore then
                state.nevermore = require(rbxservice.ReplicatedStorage:WaitForChild("Nevermore"))
            end
            if not state.boat_api then
                state.boat_api = state.nevermore("BoatAPIServiceClient")
            end
            if not state.prop_class_provider then
                state.prop_class_provider = state.nevermore("PropClassProviderClient")
            end
            if not state.client_binders then
                state.client_binders = state.nevermore("ClientBinders")
            end
        end

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

        local function get_boats_folder()
            return rbxservice.Workspace:FindFirstChild("Boats")
        end

        local function boat_owner_user_id(boat)
            if not (boat and boat:IsA("Model")) then return nil end
            local attrs = boat:GetAttributes()
            for k,v in pairs(attrs) do
                local lower = string.lower(k)
                if lower == "owneruserid" or lower == "owner" then
                    local n = tonumber(v); if n then return n end
                end
            end
            local data = boat:FindFirstChild("BoatData")
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
            for _, d in ipairs(boat:GetDescendants()) do
                if d:IsA("IntValue") and (d.Name == "Owner" or d.Name == "OwnerUserId") then
                    return d.Value
                end
            end
            return nil
        end

        local function get_prop_binder(model)
            local ok, binder = pcall(function()
                return state.client_binders.Prop:Get(model)
            end)
            if ok and binder then return binder end
            return nil
        end

        local function world_cframe(model)
            local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
            return primary and primary.CFrame or nil
        end

        local function find_teammate_boat()
            local folder = get_boats_folder()
            local lp = rbxservice.Players.LocalPlayer
            if not folder or not lp or not lp.Team then return nil end
            for _, m in ipairs(folder:GetChildren()) do
                if m:IsA("Model") then
                    local owner_id = boat_owner_user_id(m)
                    if owner_id and owner_id ~= lp.UserId then
                        local owner_plr = rbxservice.Players:GetPlayerByUserId(owner_id)
                        if owner_plr and owner_plr.Team == lp.Team then
                            return m
                        end
                    end
                end
            end
            return nil
        end

        local function find_placed_pink_gyro(boat, desired_world_cf)
            local best, best_dist = nil, math.huge
            for _, child in ipairs(boat:GetChildren()) do
                if child:IsA("Model") and child.Name == "PinkGyro" and get_prop_binder(child) then
                    local cf = world_cframe(child)
                    if cf then
                        local d = (cf.Position - desired_world_cf.Position).Magnitude
                        if d < best_dist then best, best_dist = child, d end
                    end
                end
            end
            return best
        end

        local function wait_pink_class(timeout_seconds)
            local deadline = time() + (timeout_seconds or 10)
            repeat
                local class =
                    safe_call(state.prop_class_provider, "GetPropClassFromPropId", "PinkGyro") or
                    safe_call(state.prop_class_provider, "GetFromPropId", "PinkGyro") or
                    safe_call(state.prop_class_provider, "FromPropId", "PinkGyro") or
                    safe_call(state.prop_class_provider, "GetPropClassFromTranslationKey", "props.pinkGyro") or
                    safe_call(state.prop_class_provider, "GetPropClass", "PinkGyro") or
                    safe_call(state.prop_class_provider, "Get", "PinkGyro")
                if class then return class end
                rbxservice.RunService.Heartbeat:Wait()
            until time() > deadline
            return nil
        end

        local function start()
            state.maid:DoCleaning()
            state.maid = maidclass.new()

            state.run_flag = true
            state.relative_cframe = quantize_cframe(state.relative_cframe)

            ensure_deps()
            state.pink_class = state.pink_class or wait_pink_class(10)
            if not state.pink_class then
                state.run_flag = false
                state.maid:DoCleaning()
                return
            end

            local worker = task.spawn(function()
                while state.run_flag do
                    local teammate = find_teammate_boat()
                    if not teammate then
                        task.wait(0.5)
                    else
                        local placed_ok = pcall(function()
                            state.boat_api:PlacePropOnBoat(state.pink_class, state.relative_cframe, teammate)
                        end)
                        if placed_ok then state.placed_count += 1 end

                        local desired = teammate:GetPivot() * state.relative_cframe
                        local found, start_time = nil, time()
                        repeat
                            found = find_placed_pink_gyro(teammate, desired)
                            if found then break end
                            rbxservice.RunService.Heartbeat:Wait()
                        until time() - start_time > state.search_timeout_seconds

                        if found then
                            pcall(function() state.boat_api:SellProp(found) end)
                            state.sold_count += 1
                        end

                        task.wait(state.place_throttle_seconds)
                    end
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
        local group = ui.Tabs.Dupe:AddLeftGroupbox("Step #1", "arrow-right-left")
        group:AddToggle("TransferMoneyToggle", {
            Text = "Transfer Money",
            Tooltip = "Turn Feature [ON/OFF].",
            Default = false,
        })
        ui.Toggles.TransferMoneyToggle:OnChanged(function(v)
            if v then start() else stop() end
        end)
        ui.Toggles.TransferMoneyToggle:AddKeyPicker("TransferMoneyKeybind", {
            Text = "Transfer Money",
            SyncToggleState = true,
            Mode = "Toggle",
            NoUI = false,
        })

        return { Name = "TransferMoney", Stop = stop }
    end
end
