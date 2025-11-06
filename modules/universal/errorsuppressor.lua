-- modules/universal/errorsuppressor.lua
do
    return function(UI)
        -- deps
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local maid = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local state = {
            maid = maid.new(),
            runflag = false,
            snapshot = {}, -- [signal] = { {mode="disabled", connection=RBXScriptConnection}, {mode="disconnected", func=function}, ... }
        }

        local function clear_snapshot()
            for k in pairs(state.snapshot) do state.snapshot[k] = nil end
        end

        local function target_signals()
            local log = services.LogService
            local sc  = services.ScriptContext
            local list = {
                log and log.MessageOut,
                log and (log.MessageOutWithStack or log.MessageOutWithStackTrace),
                log and log.HttpResultOut,
                sc  and sc.Warning,
                sc  and sc.Error,
            }
            local out = {}
            for i = 1, #list do if list[i] then out[#out+1] = list[i] end end
            return out
        end

        local function add_record(sig, rec)
            local bucket = state.snapshot[sig]
            if not bucket then
                bucket = {}
                state.snapshot[sig] = bucket
            end
            bucket[#bucket+1] = rec
        end

        local function suppress_once()
            for _, sig in ipairs(target_signals()) do
                local ok, conns = pcall(getconnections, sig)
                if ok and type(conns) == "table" then
                    for i = 1, #conns do
                        local conn = conns[i]

                        local disabled = false
                        if type(conn.Disable) == "function" then
                            local okd = pcall(function() conn:Disable() end)
                            if okd then
                                add_record(sig, { mode = "disabled", connection = conn })
                                disabled = true
                            end
                        end

                        if not disabled then
                            -- reversible disconnect path (only if we can read the original function)
                            local original = rawget(conn, "Function") or conn.Function
                            if type(conn.Disconnect) == "function" and type(original) == "function" then
                                local okdisc = pcall(function() conn:Disconnect() end)
                                if okdisc then
                                    add_record(sig, { mode = "disconnected", func = original })
                                end
                            end
                        end
                    end
                end
            end
            pcall(function() services.LogService:ClearOutput() end)
        end

        local function start()
            if state.runflag then return end
            state.runflag = true
            clear_snapshot()
            suppress_once()

            -- resuppress once after character spawns (to catch listeners that reattach on spawn)
            local lp = services.Players.LocalPlayer
            if lp then
                state.maid.char_added = lp.CharacterAdded:Connect(function()
                    task.delay(1, function()
                        if state.runflag then suppress_once() end
                    end)
                end)
            end
        end

        local function stop()
            if not state.runflag then return end
            state.runflag = false

            -- restore in LIFO-ish order (not strictly required, but fine)
            for sig, items in pairs(state.snapshot) do
                for i = 1, #items do
                    local item = items[i]
                    if item.mode == "disabled" then
                        pcall(function()
                            local c = item.connection
                            if typeof(c) == "RBXScriptConnection" and type(c.Enable) == "function" then
                                c:Enable()
                            end
                        end)
                    elseif item.mode == "disconnected" then
                        pcall(function()
                            if typeof(sig) == "RBXScriptSignal" and type(item.func) == "function" then
                                sig:Connect(item.func)
                            end
                        end)
                    end
                end
            end

            clear_snapshot()
            state.maid:DoCleaning()
        end

        -- UI
        local box = UI.Tabs.Misc:AddLeftGroupbox("Console", "terminal")
        box:AddToggle("ConsoleErrorSuppressorToggle", {
            Text = "Suppress Errors/Warnings",
            Tooltip = "Silences LogService/ScriptContext output and clears console. Fully reversible.",
            Default = false,
        })

        UI.Toggles.ConsoleErrorSuppressorToggle:OnChanged(function(enabled)
            if enabled then start() else stop() end
        end)

        return { Name = "ErrorSuppressor", Stop = stop }
    end
end
