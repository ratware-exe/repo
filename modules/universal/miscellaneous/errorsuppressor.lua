-- modules/errorsuppressor.lua
do
    return function(ui)
        local rbxservice = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local maid       = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
        local tasks      = maid.new()

        local run_flag = false
        local disabled = {}   -- [RBXScriptConnection] = true
        local watch_thread = nil

        -- executor-only helper; noop on unsupported environments
        local function list_connections(signal)
            local ok, conns = pcall(getconnections, signal)
            if not ok or not conns then return {} end
            return conns
        end

        local function disable_signal(signal)
            for _, c in ipairs(list_connections(signal)) do
                pcall(function()
                    if c and c.Disable then c:Disable() end
                    disabled[c] = true
                end)
            end
        end

        local function enable_all_saved()
            for c in pairs(disabled) do
                pcall(function()
                    if c and c.Enable then c:Enable() end
                end)
                disabled[c] = nil
            end
        end

        local function refresh_once()
            -- LogService outputs
            pcall(function() disable_signal(rbxservice.LogService.MessageOut) end)
            pcall(function()
                local with_stack = rbxservice.LogService.MessageOutWithStack or rbxservice.LogService.MessageOutWithStackTrace
                if with_stack then disable_signal(with_stack) end
            end)
            pcall(function() disable_signal(rbxservice.LogService.HttpResultOut) end)

            -- ScriptContext warnings/errors
            pcall(function() disable_signal(rbxservice.ScriptContext.Warning) end)
            pcall(function() disable_signal(rbxservice.ScriptContext.Error) end)
        end

        local function start()
            if run_flag then return end
            run_flag = true

            -- initial sweep
            refresh_once()

            -- keep things quiet as new connections appear
            watch_thread = task.spawn(function()
                while run_flag do
                    refresh_once()
                    task.wait(0.5)
                end
            end)
            tasks:GiveTask(function()
                run_flag = false
            end)
            tasks:GiveTask(function()
                if watch_thread then pcall(task.cancel, watch_thread) end
                watch_thread = nil
            end)
        end

        local function stop()
            run_flag = false
            if watch_thread then pcall(task.cancel, watch_thread) end
            watch_thread = nil
            enable_all_saved()
            tasks:DoCleaning()
        end

        -- UI on Debug tab (mirrors your layout)
        local tab = ui.Tabs.Debug or ui.Tabs["Debug"]
        if not tab then
            tab = ui.Tabs.Misc or ui.Tabs["Misc"]
        end

        local group = tab:AddRightGroupbox("Console Noise Suppressor", "ban")
        group:AddToggle("ErrorWarningSuppressorToggle", {
            Text = "Suppress Errors / Warnings / Http logs",
            Tooltip = "Disables existing LogService and ScriptContext connections and keeps them disabled while on.",
            Default = false,
        })
        ui.Toggles.ErrorWarningSuppressorToggle:OnChanged(function(enabled)
            if enabled then start() else stop() end
        end)

        return { Name = "errorsuppressor", Stop = stop }
    end
end
