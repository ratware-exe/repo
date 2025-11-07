-- modules/universal/noclip.lua
-- modules/noclip.lua
do
    return function(UI)
        -- [1] LOAD DEPENDENCIES
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv = (getgenv and getgenv()) or _G
        local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        -- [2] MODULE STATE
        local ModuleName = "NoClip"
        local Variables = {
            Maids = { [ModuleName] = Maid.new() },
            RunFlag = false, -- Corresponds to Noclip
        }

        -- [3] CORE LOGIC
        local function onStepped()
            if not Variables.RunFlag then return end
            
            local LocalPlayer = RbxService.Players.LocalPlayer
            if not LocalPlayer then return end

            local char = LocalPlayer.Character
            if not char then return end
            
            for _, inst in ipairs(char:GetDescendants()) do
                if inst:IsA("BasePart") then
                    pcall(function() inst.CanCollide = false end)
                end
            end
        end
        
        local function Start()
            if Variables.RunFlag then return end
            Variables.RunFlag = true
            
            local steppedConn = RbxService.RunService.Stepped:Connect(onStepped)
            Variables.Maids[ModuleName]:GiveTask(steppedConn)
            
            Variables.Maids[ModuleName]:GiveTask(function() Variables.RunFlag = false end)
        end

        local function Stop()
            if not Variables.RunFlag then return end
            Variables.RunFlag = false
            
            Variables.Maids[ModuleName]:DoCleaning()

            -- Restore HRP collision
            pcall(function()
                local LocalPlayer = RbxService.Players.LocalPlayer
                if not LocalPlayer then return end
                local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                if hrp then hrp.CanCollide = true end
            end)
        end

        -- [4] UI CREATION
        -- UI is already created by loader.

        -- [5] UI WIRING
        UI.Toggles.NoclipToggle:OnChanged(function(enabledState)
            Variables.RunFlag = enabledState
            if enabledState then Start() else Stop() end
        end)
        
        -- Seed default value
        Variables.RunFlag = UI.Toggles.NoclipToggle.Value
        
        -- Start if already enabled
        if Variables.RunFlag then
            Start()
        end

        -- [6] RETURN MODULE
        return { Name = ModuleName, Stop = Stop }
    end
end
