-- modules/wfyb/autoflame.lua
do
    return function(ui)
        local rbxservice = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local maidclass  = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        -- shared Nevermore access
        local function get_loader()
            local nevermore = rbxservice.ReplicatedStorage:FindFirstChild("Nevermore") or rbxservice.ReplicatedStorage:WaitForChild("Nevermore")
            local ok, loader = pcall(require, nevermore)
            if ok then return loader end
            return nil
        end

        -- ===== SINGLE FLAME =====
        local single = {
            maid = maidclass.new(),
            run_flag = false,

            max_trigger_distance = 800,
            max_view_distance = 1200,
            leeway_distance = 40,
            fire_rate_hz = 15,

            patched = false,
            watched = {},
            last_pulse_time = 0,
            accumulated_time = 0,
            last_trigger = nil,
        }

        local function ensure_client_binders_single()
            if single.client_binders then return single.client_binders end
            local loader = get_loader()
            if not loader then return nil end
            local ok, binders = pcall(function() return loader("ClientBinders") end)
            if ok and binders then single.client_binders = binders end
            return single.client_binders
        end

        local function patch_constants_single()
            local loader = get_loader(); if not loader then return end
            local ok, trigger_constants = pcall(function() return loader("TriggerConstants") end)
            if not (ok and type(trigger_constants) == "table") then return end
            trigger_constants.MAX_TRIGGER_DISTANCE = single.max_trigger_distance
            trigger_constants.MAX_VIEW_DISTANCE    = single.max_view_distance
            trigger_constants.LEEWAY_DISTANCE      = single.leeway_distance
        end

        local function patch_cooldowns_single()
            if single.patched then return end
            local loader = get_loader(); if not loader then return end

            local ok1, cooldown_svc = pcall(function() return loader("TriggerCooldownService") end)
            if ok1 and cooldown_svc then
                local old_is   = cooldown_svc.IsGlobalCoolingDown
                local old_mark = cooldown_svc.MarkGlobalCooldown
                cooldown_svc.IsGlobalCoolingDown = function() return false end
                cooldown_svc.MarkGlobalCooldown  = function() end
                single.maid:GiveTask(function()
                    cooldown_svc.IsGlobalCoolingDown = old_is
                    cooldown_svc.MarkGlobalCooldown  = old_mark
                end)
            end

            local ok2, helper = pcall(function() return loader("CooldownHelper") end)
            if ok2 and helper and type(helper.getCooldown) == "function" then
                local old = helper.getCooldown
                helper.getCooldown = function() return false end
                single.maid:GiveTask(function() helper.getCooldown = old end)
            end

            single.patched = true
        end

        local function get_trigger_binder()
            local loader = get_loader(); if not loader then return nil end
            local ok, binders = pcall(function() return loader("ClientBinders") end)
            if not (ok and binders and binders.Trigger) then return nil end
            return binders.Trigger
        end

        local function unwrap_attachment(obj)
            return rawget(obj, "_obj")
                or rawget(obj, "Instance")
                or rawget(obj, "_instance")
                or (typeof(obj.GetObject) == "function" and obj:GetObject())
                or nil
        end

        local function is_flamethrower_trigger(obj)
            local attachment = unwrap_attachment(obj)
            if not (attachment and attachment:IsA("Attachment")) then return false end
            local loader = get_loader(); if not loader then return false end

            local okc, trigger_constants = pcall(function() return loader("TriggerConstants") end)
            if not (okc and trigger_constants) then return false end

            local binders = ensure_client_binders_single()
            if not binders or not binders.Flamethrower then return false end

            for _, child in ipairs(attachment:GetChildren()) do
                if child:IsA("ObjectValue") and child.Name == trigger_constants.TARGET_OBJECT_VALUE_NAME and child.Value then
                    local ok, flamer = pcall(function() return binders.Flamethrower:Get(child.Value) end)
                    if ok and flamer then
                        return true
                    end
                end
            end
            return false
        end

        local function neutralize_cooldown(child)
            if not child or not child.Parent or child.Name ~= "Cooldown" then return end
            task.defer(function()
                if child and child.Parent and child.Name == "Cooldown" then
                    child.Name = "CooldownDisabled"
                    pcall(function() child:SetAttribute("Disabled", true) end)
                end
            end)
        end

        local function watch_trigger(obj)
            if not is_flamethrower_trigger(obj) then return end
            local attachment = unwrap_attachment(obj)
            if not (attachment and attachment:IsA("Attachment")) then return end
            if single.watched[attachment] then return end

            for _, child in ipairs(attachment:GetChildren()) do
                if child.Name == "Cooldown" then
                    neutralize_cooldown(child)
                end
            end

            local conn = attachment.ChildAdded:Connect(function(new_child)
                if new_child and new_child.Name == "Cooldown" then
                    neutralize_cooldown(new_child)
                end
            end)

            single.watched[attachment] = conn
            single.maid:GiveTask(conn)
        end

        local function refresh_triggers()
            local binder = get_trigger_binder()
            if not binder then return end
            local ok, list = pcall(function() return binder:GetAll() end)
            if not (ok and type(list) == "table") then return end
            for _, t in ipairs(list) do
                watch_trigger(t)
            end
        end

        local function select_trigger()
            local binder = get_trigger_binder()
            if not binder then return nil end
            local ok, list = pcall(function() return binder:GetAll() end)
            if not (ok and type(list) == "table") then return nil end

            local flamers = {}
            local preferred = nil
            for _, t in ipairs(list) do
                if is_flamethrower_trigger(t) then
                    table.insert(flamers, t)
                    local okp, is_pref = pcall(function() return t.Preferred and t.Preferred.Value end)
                    if okp and is_pref then preferred = t end
                end
            end
            if #flamers == 0 then return nil end

            if single.last_trigger then
                for _, t in ipairs(flamers) do
                    if t == single.last_trigger then return t end
                end
            end
            return preferred or flamers[1]
        end

        local function on_heartbeat_single(dt)
            patch_constants_single()
            patch_cooldowns_single()
            single.accumulated_time = single.accumulated_time + dt
            if single.accumulated_time >= 0.2 then
                single.accumulated_time = 0
                refresh_triggers()
            end
            if not single.run_flag then return end

            local now = time()
            local min_interval = 1 / math.max(1, single.fire_rate_hz)
            if now - single.last_pulse_time < min_interval then return end
            single.last_pulse_time = now

            local trig = select_trigger()
            if trig then
                single.last_trigger = trig
                pcall(function() trig:Activate() end)
            end
        end

        local function start_single()
            if single.run_flag then return end
            single.run_flag = true
            patch_constants_single()
            patch_cooldowns_single()
            refresh_triggers()
            local hb = rbxservice.RunService.Heartbeat:Connect(on_heartbeat_single)
            single.maid:GiveTask(hb)
            single.maid:GiveTask(function() single.run_flag = false end)
        end

        local function stop_single()
            single.run_flag = false
            for a, c in pairs(single.watched) do
                if typeof(c) == "RBXScriptConnection" then pcall(function() c:Disconnect() end) end
                single.watched[a] = nil
            end
            single.maid:DoCleaning()
            single.last_trigger = nil
            single.patched = false
        end

        -- ===== MULTI FLAME =====
        local multi = {
            maid = maidclass.new(),
            run_flag = false,

            only_flamethrowers = true,

            max_trigger_distance = 800,
            max_view_distance    = 1200,
            leeway_distance      = 40,

            fire_rate_hz = 15,
            pulse_interval_seconds = 2.0, -- overrides hertz if > 0
            burst_size = 100,

            patched = false,
            watched = {},
            last_pulse_time = 0,
            accumulated_time = 0,
            round_robin_index = 1,
        }

        local function patch_constants_multi()
            local loader = get_loader(); if not loader then return end
            local ok, trigger_constants = pcall(function() return loader("TriggerConstants") end)
            if not (ok and type(trigger_constants) == "table") then return end
            trigger_constants.MAX_TRIGGER_DISTANCE = multi.max_trigger_distance
            trigger_constants.MAX_VIEW_DISTANCE    = multi.max_view_distance
            trigger_constants.LEEWAY_DISTANCE      = multi.leeway_distance
        end

        local function patch_cooldowns_multi()
            if multi.patched then return end
            local loader = get_loader(); if not loader then return end

            local ok1, cooldown_svc = pcall(function() return loader("TriggerCooldownService") end)
            if ok1 and cooldown_svc then
                local old_is   = cooldown_svc.IsGlobalCoolingDown
                local old_mark = cooldown_svc.MarkGlobalCooldown
                cooldown_svc.IsGlobalCoolingDown = function() return false end
                cooldown_svc.MarkGlobalCooldown  = function() end
                multi.maid:GiveTask(function()
                    cooldown_svc.IsGlobalCoolingDown = old_is
                    cooldown_svc.MarkGlobalCooldown  = old_mark
                end)
            end

            local ok2, helper = pcall(function() return loader("CooldownHelper") end)
            if ok2 and helper and type(helper.getCooldown) == "function" then
                local old = helper.getCooldown
                helper.getCooldown = function() return false end
                multi.maid:GiveTask(function() helper.getCooldown = old end)
            end

            multi.patched = true
        end

        local function ensure_client_binders_multi()
            if multi.client_binders then return multi.client_binders end
            local loader = get_loader(); if not loader then return nil end
            local ok, binders = pcall(function() return loader("ClientBinders") end)
            if ok and binders then multi.client_binders = binders end
            return multi.client_binders
        end

        local function is_multi_flame_trigger(obj)
            if multi.only_flamethrowers == false then return true end
            local attachment = unwrap_attachment(obj)
            if not (attachment and attachment:IsA("Attachment")) then return false end
            local loader = get_loader(); if not loader then return false end

            local okc, trigger_constants = pcall(function() return loader("TriggerConstants") end)
            if not (okc and trigger_constants) then return false end

            local binders = ensure_client_binders_multi()
            if not binders or not binders.Flamethrower then return false end

            for _, child in ipairs(attachment:GetChildren()) do
                if child:IsA("ObjectValue") and child.Name == trigger_constants.TARGET_OBJECT_VALUE_NAME and child.Value then
                    local ok, flamer = pcall(function() return binders.Flamethrower:Get(child.Value) end)
                    if ok and flamer then return true end
                end
            end
            return false
        end

        local function watch_multi(obj)
            if not is_multi_flame_trigger(obj) then return end
            local attachment = unwrap_attachment(obj)
            if not (attachment and attachment:IsA("Attachment")) then return end
            if multi.watched[attachment] then return end

            for _, child in ipairs(attachment:GetChildren()) do
                if child.Name == "Cooldown" then neutralize_cooldown(child) end
            end
            local conn = attachment.ChildAdded:Connect(function(new_child)
                if new_child and new_child.Name == "Cooldown" then
                    neutralize_cooldown(new_child)
                end
            end)
            multi.watched[attachment] = conn
            multi.maid:GiveTask(conn)
        end

        local function refresh_multi()
            local binder = get_trigger_binder()
            if not binder then return end
            local ok, list = pcall(function() return binder:GetAll() end)
            if not (ok and type(list) == "table") then return end
            for _, t in ipairs(list) do
                watch_multi(t)
            end
        end

        local function collect_multi()
            local binder = get_trigger_binder()
            if not binder then return nil end
            local ok, list = pcall(function() return binder:GetAll() end)
            if not (ok and type(list) == "table") then return nil end

            local out = {}
            for _, t in ipairs(list) do
                if is_multi_flame_trigger(t) then
                    table.insert(out, t)
                end
            end
            return out
        end

        local function on_heartbeat_multi(dt)
            patch_constants_multi()
            patch_cooldowns_multi()

            multi.accumulated_time = multi.accumulated_time + dt
            if multi.accumulated_time >= 0.2 then
                multi.accumulated_time = 0
                refresh_multi()
            end
            if not multi.run_flag then return end

            local pulse_interval = multi.pulse_interval_seconds
            if not pulse_interval or pulse_interval <= 0 then
                pulse_interval = 1 / math.max(1, multi.fire_rate_hz)
            end
            local now = time()
            if now - multi.last_pulse_time < pulse_interval then return end
            multi.last_pulse_time = now

            local triggers = collect_multi()
            if not triggers or #triggers == 0 then return end

            local count = #triggers
            local burst = math.clamp(tonumber(multi.burst_size) or count, 1, count)
            local start = tonumber(multi.round_robin_index) or 1

            for offset = 0, burst - 1 do
                local idx = ((start - 1 + offset) % count) + 1
                local trg = triggers[idx]
                if trg then pcall(function() trg:Activate() end) end
            end

            multi.round_robin_index = ((start - 1 + burst) % count) + 1
        end

        local function start_multi()
            if multi.run_flag then return end
            multi.run_flag = true
            multi.last_pulse_time = 0
            multi.accumulated_time = 0
            multi.round_robin_index = 1
            patch_constants_multi()
            patch_cooldowns_multi()
            refresh_multi()
            local hb = rbxservice.RunService.Heartbeat:Connect(on_heartbeat_multi)
            multi.maid:GiveTask(hb)
            multi.maid:GiveTask(function() multi.run_flag = false end)
        end

        local function stop_multi()
            multi.run_flag = false
            multi.round_robin_index = 1
            for a, c in pairs(multi.watched) do
                if typeof(c) == "RBXScriptConnection" then pcall(function() c:Disconnect() end) end
                multi.watched[a] = nil
            end
            multi.watched = {}
            multi.patched = false
            multi.last_pulse_time = 0
            multi.accumulated_time = 0
            multi.maid:DoCleaning()
        end

        -- === ui ===
        local group = ui.Tabs.EXP:AddLeftGroupbox("EXP Farm", "arrow-right-left")

        group:AddToggle("AutoFlamethrowerToggle", {
            Text = "Single Flame",
            Tooltip = "Turn Feature [ON/OFF].",
            Default = false,
        })
        ui.Toggles.AutoFlamethrowerToggle:OnChanged(function(v)
            if v then start_single() else stop_single() end
        end)

        group:AddToggle("AutoMultiFlamethrowerToggle", {
            Text = "Multiple Flame",
            Tooltip = "Turn Feature [ON/OFF].",
            Default = false,
        })
        ui.Toggles.AutoMultiFlamethrowerToggle:OnChanged(function(v)
            if v then start_multi() else stop_multi() end
        end)

        return {
            Name = "AutoFlame",
            Stop = function()
                stop_single()
                stop_multi()
            end
        }
    end
end
