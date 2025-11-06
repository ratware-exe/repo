-- modules/errorsuppressor.lua
print('new')
do
    return function(ui)
        -- deps
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
        local maid     = Maid.new()

        -- state
        local running = false
        local saved   = nil  -- name -> { [RBXScriptConnection] = true }

        -- helpers
        local function safe_typeof(v)
            local ok, t = pcall(function() return typeof(v) end)
            return ok and t or nil
        end

        local function list_connections(signal)
            if not signal then return {} end
            local ok, conns = pcall(getconnections, signal)
            if not ok or type(conns) ~= "table" then return {} end
            return conns
        end

        local function first_valid_signal(root, candidate_names)
            for i = 1, #candidate_names do
                local name = candidate_names[i]
                local ok, value = pcall(function() return root[name] end)
                if ok and safe_typeof(value) == "RBXScriptSignal" then
                    return value, name
                end
            end
            return nil, nil
        end

        local function current_signals()
            -- probe candidates; keep only what actually exists on this client
            local message_out          = first_valid_signal(services.LogService, { "MessageOut" })
            local message_out_with_any = first_valid_signal(services.LogService, {
                "MessageOutWithStack",        -- some environments
                "MessageOutWithStackTrace",   -- others
                -- (leave room for additional variants as needed)
            })
            local http_result          = first_valid_signal(services.LogService, { "HttpResultOut" })
            local script_warn          = first_valid_signal(services.ScriptContext, { "Warning" })
            local script_error         = first_valid_signal(services.ScriptContext, { "Error" })

            local out = {}

            if message_out         then table.insert(out, { name = "messageout",      sig = message_out }) end
            if message_out_with_any then table.insert(out, { name = "messageoutstack", sig = message_out_with_any }) end
            if http_result         then table.insert(out, { name = "httpresult",      sig = http_result }) end
            if script_warn         then table.insert(out, { name = "scriptwarn",      sig = script_warn }) end
            if script_error        then table.insert(out, { name = "scripterror",     sig = script_error }) end

            return out
        end

        local function disable_signal(signal, bucket)
            if not signal then return end
            local conns = list_connections(signal)
            for i = 1, #conns do
                local c = conns[i]
                if c and c.Disable and not bucket[c] then
                    local ok = pcall(function() c:Disable() end)
                    if ok then
                        bucket[c] = true
                        -- schedule exact re-enable for this connection
                        maid:GiveTask(function()
                            if c and c.Enable then pcall(function() c:Enable() end) end
                        end)
                    end
                end
            end
        end

        local function sweep_once()
            if not saved then return end
            for _, entry in ipairs(current_signals()) do
                local bucket = saved[entry.name]
                if bucket then disable_signal(entry.sig, bucket) end
            end
            -- optional: clear visual spam too; guard in case method isn’t present
            pcall(function()
                if services.LogService.ClearOutput then
                    services.LogService:ClearOutput()
                end
            end)
        end

        local function enable_saved()
            if not saved then return end
            for _, bucket in pairs(saved) do
                for c in pairs(bucket) do
                    pcall(function() if c and c.Enable then c:Enable() end end)
                    bucket[c] = nil
                end
            end
        end

        local function start()
            if running then return end
            running = true

            -- create one bucket per possible key so Stop() is deterministic
            saved = {
                messageout      = {},
                messageoutstack = {},
                httpresult      = {},
                scriptwarn      = {},
                scripterror     = {},
            }

            -- first pass + background catch for newly-added connections
            sweep_once()
            local hb = services.RunService.Heartbeat:Connect(sweep_once)
            maid:GiveTask(hb)

            -- ensure re-enable happens even if the module is unloaded abruptly
            maid:GiveTask(function()
                running = false
                enable_saved()
            end)
        end

        local function stop()
            if not running then return end
            running = false
            -- stop background and re-enable exactly what we disabled
            maid:DoCleaning() -- triggers enable_saved via the maid task above
            saved = nil
        end

        -- UI wiring (Debug tab; icon = terminal)
        do
            local group = ui.Tabs and ui.Tabs.Debug and ui.Tabs.Debug:AddRightGroupbox("Console", "terminal")
            if group then
                group:AddToggle("ErrorWarningSuppressorToggle", {
                    Text = "Suppress console errors & warnings",
                    Tooltip = "Temporarily disables LogService/ScriptContext handlers (no disconnects).",
                    Default = false
                })

                ui.Toggles.ErrorWarningSuppressorToggle:OnChanged(function(enabled)
                    if enabled then start() else stop() end
                end)
            end
        end

        return { Name = "ErrorSuppressor", Stop = stop }
    end
end
