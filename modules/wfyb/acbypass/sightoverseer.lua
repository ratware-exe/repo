-- modules/acbypass/SightOverseer.lua
do
    return function(UI)
        -- [1] LOAD DEPENDENCIES
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv = (getgenv and getgenv()) or _G
        local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
        
        -- [2] MODULE STATE
        local ModuleName = "ACBypassSightOverseer"
        local Variables = {
            Maids = { [ModuleName] = Maid.new() },
        }

        -- [3] CORE LOGIC
        -- This is a run-once module, logic goes in the main body.
        
        pcall(function()
            local maid = Variables.Maids[ModuleName]
            
            local function disableConnectionsOfSignal(signalObject)
                local callSucceeded, connectionsList = pcall(getconnections, signalObject)
                if not callSucceeded or type(connectionsList) ~= "table" then
                    return
                end
                for index = 1, #connectionsList do
                    local connectionObject = connectionsList[index]
                    local disabledSuccessfully = pcall(function()
                        connectionObject:Disable()
                    end)
                    if not disabledSuccessfully then
                        pcall(function()
                            connectionObject:Disconnect()
                        end)
                    end
                end
            end
        
            local function protectCharacter(characterInstance)
                if not characterInstance then
                    return
                end
                task.wait(0.1)
                disableConnectionsOfSignal(characterInstance.DescendantAdded)
        
                local humanoidObject = characterInstance:FindFirstChildOfClass("Humanoid")
                if humanoidObject then
                    disableConnectionsOfSignal(humanoidObject:GetPropertyChangedSignal("WalkSpeed"))
                    disableConnectionsOfSignal(humanoidObject:GetPropertyChangedSignal("JumpPower"))
                end
            end
            
            local LocalPlayer = RbxService.Players.LocalPlayer
            if not LocalPlayer then return end
        
            if LocalPlayer.Character then
                protectCharacter(LocalPlayer.Character)
            end
        
            maid:GiveTask(LocalPlayer.CharacterAdded:Connect(function(newCharacter)
                protectCharacter(newCharacter)
            end))
        end)
        
        -- [4] UI CREATION
        -- No UI for this module

        -- [5] RETURN MODULE
        local function Stop()
            -- This will disconnect the CharacterAdded connection
            Variables.Maids[ModuleName]:DoCleaning()
        end
        
        return { Name = ModuleName, Stop = Stop }
    end
end
