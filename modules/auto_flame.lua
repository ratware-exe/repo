
-- modules/auto_flame.lua
do
    return function(UI)
        -- Dependencies
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv  = (getgenv and getgenv()) or _G
        GlobalEnv.Signal = GlobalEnv.Signal or loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()
        local Maid       = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()


        local Variables = {
            Maids = { AutoFlame = Maid.new() },
            RunFlag = false,
            Nevermore = nil,
            ClientBinders = nil,
            TriggerConstants = nil,
            CooldownStack = nil,
            FlamethrowerTriggers = {},
        }

        -- Loader helpers (ported) 【auto flame: main-2.lua】
        local function GetLoader()
            if not Variables.Nevermore then
                Variables.Nevermore = require(RbxService.ReplicatedStorage:WaitForChild("Nevermore"))
            end
            return Variables.Nevermore
        end
        local function EnsureClientBinders()
            local loader = GetLoader()
            Variables.ClientBinders = Variables.ClientBinders or loader("ClientBinders")
        end
        local function PatchTriggerConstants()
            local loader = GetLoader()
            Variables.TriggerConstants = loader("TriggerConstants")
            if Variables.TriggerConstants then
                pcall(function()
                    Variables.TriggerConstants.DISABLE_TRIGGERS_DISTANCE = 9e9
                    Variables.TriggerConstants.TRIGGER_DISTANCE = 9e9
                end)
            end
        end
        local function PatchCooldownStack()
            local loader = GetLoader()
            Variables.CooldownStack = Variables.CooldownStack or loader("CooldownStack")
            if Variables.CooldownStack then
                pcall(function()
                    Variables.CooldownStack.Add = function() end
                    Variables.CooldownStack.GetCooldown = function() return 0 end
                    Variables.CooldownStack.IsCooldownActive = function() return false end
                    Variables.CooldownStack.Reset = function() end
                end)
            end
        end

        local function RefreshTriggersAndWatch()
            EnsureClientBinders()
            local descConn = nil
            local function rescan()
                Variables.FlamethrowerTriggers = {}
                for _, inst in ipairs(game:GetDescendants()) do
                    if inst.Name == "FlamethrowerTrigger" or inst.Name == "Flamethrower" then
                        table.insert(Variables.FlamethrowerTriggers, inst)
                    end
                end
            end
            rescan()
            descConn = game.DescendantAdded:Connect(function(i)
                if i.Name == "FlamethrowerTrigger" or i.Name == "Flamethrower" then
                    table.insert(Variables.FlamethrowerTriggers, i)
                end
            end)
            Variables.Maids.AutoFlame:GiveTask(descConn)
        end

        local function OnHeartbeat()
            if not Variables.RunFlag then return end
            for _, trg in ipairs(Variables.FlamethrowerTriggers) do
                pcall(function()
                    if trg and trg.Parent then
                        if trg.Fire then trg:Fire() end
                        if trg.Parent and trg.Parent.Fire then trg.Parent:Fire() end
                    end
                end)
            end
        end

        local Module = {}
        function Module.Start()
            if Variables.RunFlag then return end
            Variables.RunFlag = true
            PatchTriggerConstants()
            PatchCooldownStack()
            RefreshTriggersAndWatch()
            local hb = RbxService.RunService.Heartbeat:Connect(OnHeartbeat)
            Variables.Maids.AutoFlame:GiveTask(hb)
            Variables.Maids.AutoFlame:GiveTask(function() Variables.RunFlag = false end)
        end
        function Module.Stop()
            if not Variables.RunFlag then return end
            Variables.RunFlag = false
            Variables.Maids.AutoFlame:DoCleaning()
        end

        local box = UI.Tabs.EXP:AddLeftGroupbox("Single Flame", "flame")
        box:AddToggle("AutoFlameToggle", { Text = "Single Flame", Default = false, Tooltip = "Auto‑fire flamethrowers (single)." })
        UI.Toggles.AutoFlameToggle:OnChanged(function(b) if b then Module.Start() else Module.Stop() end end)

        local ModuleContract = { Name = "AutoFlame", Stop = Module.Stop }

        return ModuleContract
    end
end
