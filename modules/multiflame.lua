
-- modules/multi_flame.lua
do
    return function(UI)
        -- Dependencies
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv  = (getgenv and getgenv()) or _G
        GlobalEnv.Signal = GlobalEnv.Signal or loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()
        local Maid       = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()


        local Variables = {
            Maids = { MultiFlame = Maid.new() },
            RunFlag = false,
            FlamethrowerTriggers = {},
            BurstSize = 4,
            RoundRobinIndex = 1,
        }

        local function RefreshTriggers()
            Variables.FlamethrowerTriggers = {}
            for _, inst in ipairs(game:GetDescendants()) do
                if inst.Name == "FlamethrowerTrigger" or inst.Name == "Flamethrower" then
                    table.insert(Variables.FlamethrowerTriggers, inst)
                end
            end
        end

        local function Pulse()
            local list = Variables.FlamethrowerTriggers
            local n = #list
            if n == 0 then return end
            for i = 1, Variables.BurstSize do
                local idx = ((Variables.RoundRobinIndex + i - 2) % n) + 1
                local trg = list[idx]
                pcall(function()
                    if trg and trg.Parent then
                        if trg.Fire then trg:Fire() end
                        if trg.Parent and trg.Parent.Fire then trg.Parent:Fire() end
                    end
                end)
            end
            Variables.RoundRobinIndex = ((Variables.RoundRobinIndex + Variables.BurstSize - 1) % n) + 1
        end

        local Module = {}
        function Module.Start()
            if Variables.RunFlag then return end
            Variables.RunFlag = true
            RefreshTriggers()
            local hb = RbxService.RunService.Heartbeat:Connect(function()
                if Variables.RunFlag then Pulse() end
            end)
            Variables.Maids.MultiFlame:GiveTask(hb)
            Variables.Maids.MultiFlame:GiveTask(function() Variables.RunFlag = false end)
        end
        function Module.Stop()
            if not Variables.RunFlag then return end
            Variables.RunFlag = false
            Variables.Maids.MultiFlame:DoCleaning()
        end

        local box = UI.Tabs.EXP:AddLeftGroupbox("Multiple Flame", "flame")
        box:AddToggle("MultiFlameToggle", { Text = "Multiple Flame", Default = false, Tooltip = "Auto‑fire multiple flamethrowers." })
        UI.Toggles.MultiFlameToggle:OnChanged(function(b) if b then Module.Start() else Module.Stop() end end)

        local ModuleContract = { Name = "MultiFlame", Stop = Module.Stop }

        return ModuleContract
    end
end
