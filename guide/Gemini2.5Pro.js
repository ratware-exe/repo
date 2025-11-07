Module Development Guide & Template

This document outlines the architecture, patterns, and dependencies required to build a module compatible with the framework. All new modules MUST follow this structure to ensure stability, proper UI integration, and correct cleanup.

1. Core Module Philosophy

Entry Point: Each module is a Lua file that returns a single function. This function takes the UI object as its only argument (e.g., return function(UI) ... end).

Self-Contained: A module manages its own state, logic, and UI elements. It should not rely on other modules directly.

State Management: All module-specific variables (state flags, backups, etc.) are stored in a local Variables table.

Cleanup is Mandatory: Every module MUST be able to shut itself down cleanly. This is handled by the Stop() function and the Maid dependency. The module must return its Stop function to the loader.

Inter-Module Communication: Modules MUST NOT access each other's variables. All communication is handled via the Signal dependency (custom events).

2. Dependencies & How to Use Them

Modules load all dependencies from _G.RepoBase.

RbxService (Services.lua)

How to Load: local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()

What it is: A pre-cached table of all common Roblox services.

How to Use: Access services directly from this table instead of using game:GetService().

Example: RbxService.Players.LocalPlayer, RbxService.RunService.RenderStepped, RbxService.UserInputService.

Maid (Maid.lua)

What it is: A critical class for managing cleanup (disconnecting events, running cleanup functions) to prevent memory leaks.

How to Load: local Maid = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

How to Use (The Cleanup Pattern):

In Variables: Create a Maids table and add a new Maid instance for your module, keyed by the module's name.

local ModuleName = "MyCoolModule"
local Variables = {
    Maids = { [ModuleName] = Maid.new() },
    ...
}


In Start(): Give the Maid any task that needs cleaning up. This includes event connections, loops, and functions to run on Stop.

-- Give it an event connection
local myConnection = RbxService.RunService.RenderStepped:Connect(function() ... end)
Variables.Maids[ModuleName]:GiveTask(myConnection)

-- Give it a function to reset the run flag
Variables.Maids[ModuleName]:GiveTask(function() Variables.RunFlag = false end)


In Stop(): Call :DoCleaning() on your module's Maid. This single command will run all tasks (disconnect all connections, run all functions) you gave it.

Variables.Maids[ModuleName]:DoCleaning()


Signal (Signal.lua)

What it is: A class for creating custom events. This is the ONLY approved way for modules to communicate.

How to Load: GlobalEnv.Signal = GlobalEnv.Signal or loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()

Note: GlobalEnv is (getgenv and getgenv()) or _G.

How to Use:

Broadcasting (Firing): Create a global signal (if it doesn't exist) and fire it.

-- Create a globally accessible event
GlobalEnv.MyCustomEvent = GlobalEnv.MyCustomEvent or GlobalEnv.Signal.new()

-- Fire the event for any listening modules
GlobalEnv.MyCustomEvent:Fire("SomeData", 123)


Listening (Connecting): Connect to the global signal. CRITICAL: You MUST give the connection to your Maid for cleanup.

GlobalEnv.MyCustomEvent = GlobalEnv.MyCustomEvent or GlobalEnv.Signal.new()

local functionOnEvent(arg1, arg2)
    print("Module received event:", arg1, arg2)
end

local eventConnection = GlobalEnv.MyCustomEvent:Connect(functionOnEvent)

-- Give the connection to the Maid so it stops listening when this module stops
Variables.Maids[ModuleName]:GiveTask(eventConnection)


3. UI Integration (Obsidian)

Full Documentation: https://docs.mspaint.cc/obsidian

How it Works: The module's main function receives the UI object: return function(UI) ... end.

Standard UI Pattern:

Add a Groupbox: local MyGroupbox = UI.Tabs.Misc:AddLeftGroupbox("My Feature", "icon-name")

Choose the correct tab (e.to., UI.Tabs.Misc, UI.Tabs.Combat, UI.Tabs.Visuals).

Add a Toggle (or other element): MyGroupbox:AddToggle("MyFeatureToggle", { ... })

The key ("MyFeatureToggle") MUST be unique across the entire UI.

Properties: { Text = "Enable Feature", Tooltip = "Does a cool thing.", Default = false }

Connect the Toggle: UI.Toggles.MyFeatureToggle:OnChanged(function(enabledState) ... end)

This callback is used to trigger your module's Start() and Stop() functions.

Example: if enabledState then Start() else Stop() end

4. Module Template

Use this template as the structure for the new module.

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


5. main.lua Integration

After creating the module file (e.g., modules/universal/my_module.lua) and uploading it to the repository, add its path to the featurePaths table in main.lua to load it.

Example main.lua:

...
local featurePaths = {
    ...
    "modules/universal/clientnamespoofer.lua",
    "modules/universal/debugtools.lua",
    
    -- Add the new module's path here
    "modules/universal/my_module.lua" 
}

for i = 1, #featurePaths do
    loader.MountModule(featurePaths[i])
end
...
