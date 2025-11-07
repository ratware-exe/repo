-- modules/universal/nosky.lua
do
    return function(ui)
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local maid = Maid.new()
        local enabled = false
        local saved = {}

        local function clear_skies()
            for _, ch in ipairs(services.Lighting:GetChildren()) do
                if ch:IsA("Sky") then
                    table.insert(saved, ch:Clone())
                    ch:Destroy()
                end
            end
        end

        local function enable()
            clear_skies()
            maid:GiveTask(services.Lighting.ChildAdded:Connect(function(ch)
                if enabled and ch:IsA("Sky") then
                    task.defer(function() if ch and ch.Parent then ch:Destroy() end end)
                end
            end))
        end

        local function disable()
            for _, s in ipairs(saved) do s:Clone().Parent = services.Lighting end
            table.clear(saved)
        end

        local heartbeat_last
        local function heartbeat()
            if enabled ~= heartbeat_last then
                heartbeat_last = enabled
                if enabled then enable() else disable() end
            end
        end

        local hb_conn

        local function start()
            enabled = true
            if hb_conn then return end
            hb_conn = services.RunService.Heartbeat:Connect(heartbeat)
            maid:GiveTask(hb_conn)
        end

        local function stop()
            enabled = false
            if hb_conn then pcall(function() hb_conn:Disconnect() end); hb_conn = nil end
            disable()
            maid:DoCleaning()
        end

        -- UI (Visual)
        local tab = ui.Tabs.Visual or ui.Tabs.Main
        local group = tab:AddRightGroupbox("World", "sun")
        group:AddToggle("RemoveSkyToggle", { Text = "No Sky", Default = false })
        ui.Toggles.RemoveSkyToggle:OnChanged(function(v) if v then start() else stop() end end)

        return { Name = "NoSky", Stop = stop }
    end
end
