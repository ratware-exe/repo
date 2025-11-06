-- modules/errorsuppressor.lua
do
    return function(ui)
        -- deps
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
        local maid     = Maid.new()

        -- state
        local running = false
        local saved = nil  -- per-signal bucket of the exact connections we disabled

        -- helpers
        local function list_connections(signal)
            local ok, conns = pcall(getconnections, signal)
            if not ok or type(conns) ~= "table" then return {} end
            return conns
        end

        local function current_signals()
            local withstack = services.LogService.MessageOutWithStack or services.LogService.MessageOutWithStackTrace
            return {
                { name = "messageout",        sig = services.LogService.MessageOut },
                { name = "messageoutstack",   sig = withstack },
                { name = "httpresult",        sig = services.LogService.HttpResultOut },
                { name = "scriptwarn",        sig = services.ScriptContext.Warning },
                { name = "scripterror",       sig = services.ScriptContext.Error },
            }
        end

        local function disable_signal(signal, bucket)
            if not signal then return end
            local conns = list_connections(signal)
            for i = 1, #conns do
                local c = conns[i]
                if c and c.Disable and not bucket[c] then
                    -- Only Disable; never Disconnect (can’t safely restore Disconnect)
                    local ok = pcall(function() c:Disable() end)
                    if ok then
                        bucket[c] = true

                        -- re-enable this exact connection when we clean
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
            -- optional: clear visual spam too
            pcall(function() services.LogService:ClearOutput() end)
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

            -- safety: ensure re-enable happens even if the module is unloaded abruptly
            maid:GiveTask(function()
                running = false
                enable_saved()
            end)
        end

        local function stop()
            if not running then return end
            running = false

            -- stop background and re-enable exactly what we disabled
            maid:DoCleaning() -- triggers enable_saved via maid task above
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
