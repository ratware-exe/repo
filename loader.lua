-- loader.lua
do
    -- Required globals set by main.lua:
    -- _G.RepoBase           (base raw URL ending with '/')
    -- _G.ObsidianRepoBase   (obsidian UI repo base ending with '/')

    local function LoadText(path)
        local source = game:HttpGet(_G.RepoBase .. path)
        local chunk, compileError = loadstring(source, "@" .. path)
        if not chunk then error("loadstring failed for " .. path .. ": " .. tostring(compileError), 2) end
        return chunk()
    end

    -- Dependencies for loader-only tasks (re-enabling console connections on Unload)
    local RbxService = LoadText("dependency/Services.lua")

    -- === Obsidian UI ===
    local Library      = loadstring(game:HttpGet(_G.ObsidianRepoBase .. "Library.lua"), "@ObsidianLibrary.lua")()
    local ThemeManager = loadstring(game:HttpGet(_G.ObsidianRepoBase .. "addons/ThemeManager.lua"), "@ObsidianTheme.lua")()
    local SaveManager  = loadstring(game:HttpGet(_G.ObsidianRepoBase .. "addons/SaveManager.lua"), "@ObsidianSave.lua")()

    Library.ForceCheckbox = false
    Library.ShowToggleFrameInKeybinds = true

    local Window = Library:CreateWindow({
        Title = "R🐀TWARE",
        Footer = "Youtube.com/@RATWARE | Version: 1.0 | Made in Mumbai, India",
        Size = UDim2.fromOffset(500, 600),
        Icon = 115235675063771,
        NotifySide = "Right",
        ShowCustomCursor = false,
    })

    local Tabs = {
        Main = Window:AddTab("Main", "grip"),
	    Automation = Window:AddTab("Automation", "bot"),
	    Visual = Window:AddTab("Visual", "glasses"),
        EXP = Window:AddTab("EXP", "tractor"),
    	Dupe = Window:AddTab("Dupe", "dollar-sign"),
        Visuals = Window:AddTab("Visuals", "eye"),
        Misc = Window:AddTab("Misc", "dice-4"),
        Debug = Window:AddTab("Debug", "bug-off"),
        Settings = Window:AddTab("Settings", "settings"),
    }

    local Options = Library.Options
    local Toggles = Library.Toggles

    local MenuGroup = Tabs.Settings:AddLeftGroupbox("Menu", "layout-dashboard")
    MenuGroup:AddToggle("KeybindMenuOpen", {
        Default = Library.KeybindFrame.Visible,
        Text = "Open Keybind Menu",
        Callback = function(visibleState)
            Library.KeybindFrame.Visible = visibleState
        end,
    })
    MenuGroup:AddToggle("ShowCustomCursor", {
        Text = "Custom Cursor",
        Default = false,
        Callback = function(enabledState)
            Library.ShowCustomCursor = enabledState
        end,
    })
    MenuGroup:AddDropdown("NotificationSide", {
        Values = { "Left", "Right" },
        Default = "Right",
        Text = "Notification Side",
        Callback = function(sideValue)
            Library:SetNotifySide(sideValue)
        end,
    })
    MenuGroup:AddDropdown("DPIDropdown", {
        Values = { "50%", "75%", "100%", "125%", "150%", "175%", "200%" },
        Default = "100%",
        Text = "DPI Scale",
        Callback = function(percentText)
            percentText = percentText:gsub("%%", "")
            local dpiValue = tonumber(percentText)
            Library:SetDPIScale(dpiValue)
        end,
    })
    MenuGroup:AddDivider()
    MenuGroup:AddLabel("Menu Bind")
        :AddKeyPicker("MenuKeybind", { Default = "Backquote", NoUI = true, Text = "Menu Keybind" })

    local mountedModules = {}

    local function ReenableAllConnections(signalObject)
        local callSucceeded, connectionsList = pcall(getconnections, signalObject)
        if not callSucceeded or not connectionsList then return end
        for connectionIndex = 1, #connectionsList do
            local connectionObject = connectionsList[connectionIndex]
            pcall(function()
                if connectionObject and connectionObject.Enable then
                    connectionObject:Enable()
                end
            end)
        end
    end

    local function GlobalUnload()
        -- Ask each mounted module to stop & clean
        for moduleIndex = #mountedModules, 1, -1 do
            local moduleRecord = mountedModules[moduleIndex]
            if moduleRecord and moduleRecord.Stop then
                pcall(function() moduleRecord.Stop() end)
            end
            mountedModules[moduleIndex] = nil
        end

        -- Re-enable console/logging connections (parity with your monolith)
        pcall(function() ReenableAllConnections(RbxService.LogService.MessageOut) end)
        pcall(function()
            local withStack = RbxService.LogService.MessageOutWithStack or RbxService.LogService.MessageOutWithStackTrace
            if withStack then ReenableAllConnections(withStack) end
        end)
        pcall(function() ReenableAllConnections(RbxService.LogService.HttpResultOut) end)
        pcall(function() ReenableAllConnections(RbxService.ScriptContext.Warning) end)
        pcall(function() ReenableAllConnections(RbxService.ScriptContext.Error) end)

        task.defer(function()
            pcall(function() if Library and Library.Unload then Library:Unload() end end)
        end)
    end

    MenuGroup:AddButton("Unload", GlobalUnload)
    Library.ToggleKeybind = Options.MenuKeybind
    ThemeManager:SetLibrary(Library)
    SaveManager:SetLibrary(Library)
    SaveManager:IgnoreThemeSettings()
    SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
    ThemeManager:SetFolder("RATWARE_V1")
    SaveManager:SetFolder("RATWARE_V1/Universal")
    SaveManager:SetSubFolder("Save")
    SaveManager:BuildConfigSection(Tabs.Settings)
    ThemeManager:ApplyToTab(Tabs.Settings)
    SaveManager:LoadAutoloadConfig()

    -- Simple API exported to main.lua
    local Api = {}

    function Api.GetUI()
        return { Library = Library, Tabs = Tabs, Options = Options, Toggles = Toggles }
    end

    function Api.MountModule(path)
        local factory = LoadText(path)  -- factory(UI) -> { Name, Stop? }
        local uiContext = Api.GetUI()
        local moduleApi = factory(uiContext) or {}
        table.insert(mountedModules, moduleApi)
    end

    function Api.Unload()
        GlobalUnload()
    end

    return Api
end
