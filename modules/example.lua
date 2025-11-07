-- modules/your_module_name.lua
do
    return function(UI)
        -- [1] LOAD DEPENDENCIES
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv = (getgenv and getgenv()) or _G
        local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
        
        -- Optional: Load Signal ONLY if you need inter-module communication
        -- GlobalEnv.Signal = GlobalEnv.Signal or loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()

        -- [2] MODULE STATE
        local ModuleName = "MyModule" -- Change this to a unique name (e.g., "AutoHeal")
        local Variables = {
            Maids = { [ModuleName] = Maid.new() },
            RunFlag = false,
            Backup = nil,
            -- Add module-specific variables here
            -- Example: MyValue = 100 
        }

        -- [3] CORE LOGIC
        
        -- Function to enable the module
        local function Start()
            -- Prevent running if already running
            if Variables.RunFlag then return end
            Variables.RunFlag = true

            local LocalPlayer = RbxService.Players.LocalPlayer
            if not LocalPlayer then
                Variables.RunFlag = false
                return
            end

            -- A. (Optional) Back up original settings
            if not Variables.Backup then
                pcall(function()
                    Variables.Backup = {
                        -- Example: MaxHealth = LocalPlayer.Character.Humanoid.MaxHealth
                    }
                end)
            end

            -- B. Apply modifications
            pcall(function()
                -- Example: LocalPlayer.Character.Humanoid.MaxHealth = 9999
            end)

            -- C. (Optional) Create connections and give them to the Maid
            local myConnection = RbxService.RunService.RenderStepped:Connect(function()
                if not Variables.RunFlag then return end
                -- This code will run every frame
                pcall(function()
                    -- Example: LocalPlayer.Character.Humanoid.Health = 9999
                end)
            end)
            
            Variables.Maids[ModuleName]:GiveTask(myConnection)
            
            -- D. Give the RunFlag reset function to the Maid
            Variables.Maids[ModuleName]:GiveTask(function() 
                Variables.RunFlag = false 
            end)
        end

        -- Function to disable the module
        local function Stop()
            -- Prevent running if already stopped
            if not Variables.RunFlag then return end
            Variables.RunFlag = false
            
            -- This runs all cleanup tasks: disconnects events, runs functions, etc.
            Variables.Maids[ModuleName]:DoCleaning()

            -- A. (Optional) Restore original settings
            local LocalPlayer = RbxService.Players.LocalPlayer
            if LocalPlayer and Variables.Backup then
                pcall(function()
                    -- Example: LocalPlayer.Character.Humanoid.MaxHealth = Variables.Backup.MaxHealth
                end)
                -- Clear the backup so it's re-captured on next Start()
                Variables.Backup = nil
            end
        end

        -- [4] UI CREATION
        
        -- A. Add a Groupbox to the correct tab
        local MyGroupbox = UI.Tabs.Misc:AddLeftGroupbox("My Feature", "mouse-pointer-2")
        
        -- B. Add the Toggle
        MyGroupbox:AddToggle("MyModuleToggle", { -- This key MUST be unique!
            Text = "Enable My Feature",
            Tooltip = "A brief description of what this feature does.",
            Default = false,
        })
        
        -- C. Connect the Toggle to Start/Stop
        UI.Toggles.MyModuleToggle:OnChanged(function(enabledState)
            if enabledState then Start() else Stop() end
        end)

        -- [5] RETURN MODULE
        -- This is required by the loader to manage the module
        return { Name = ModuleName, Stop = Stop }
    end
end
