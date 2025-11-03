-- main.lua
-- Hub bootstrap: builds the main UI, wires module loading via /deps/loader.lua,
-- provides shared RbxService/Variables/Maid/Signal, and enforces strict cleanup.

-- =========================
-- 0) User-configurable base
-- =========================
-- IMPORTANT: Change this to your hosting root (must end with a "/")
local BaseUrl = "https://your.cdn/repo/"

-- Optional: switch UI library here if you use a different one
local ObsidianUrlBase = "https://raw.githubusercontent.com/WFYBGG/Obsidian/main/"

-- =========================
-- 1) Services (no aliases)
-- =========================
local RbxService = {
    Players = game:GetService("Players"),
    RunService = game:GetService("RunService"),
    ReplicatedStorage = game:GetService("ReplicatedStorage"),
    Lighting = game:GetService("Lighting"),
    TweenService = game:GetService("TweenService"),
    StarterGui = game:GetService("StarterGui"),
    TextChatService = game:GetService("TextChatService"),
    SoundService = game:GetService("SoundService"),
    Workspace = game:GetService("Workspace"),
    LogService = game:GetService("LogService"),
    ScriptContext = game:GetService("ScriptContext"),
    CoreGui = game:GetService("CoreGui"),
}

-- =========================
-- 2) Global state container
-- =========================
local Variables = {
    Maids = {},                                -- per-feature maids (by name)
    WeakMaids = setmetatable({}, { __mode = "k" }), -- universal weak map for instance-scoped maids
    Version = "4.0",
    Branding = {
        Title = "WFYB.GG",
        Footer = "Youtube.com/@WFYBExploits | Version: 4.0 | Made in Mumbai, India",
        IconAssetId = 115235675063771
    },
}

-- Make available to other modules if they want to reference directly
do
    local GlobalTable = (getgenv and getgenv()) or _G
    GlobalTable.WFYB_RbxService = RbxService
    GlobalTable.WFYB_Variables = Variables
end

-- =========================
-- 3) Import loader + deps
-- =========================
local Loader = (loadstring(game:HttpGet(BaseUrl .. "deps/loader.lua"), "@loader") )()
local Maid   = Loader.Import("Maid",   BaseUrl .. "deps/maid.lua")
local Signal = Loader.Import("Signal", BaseUrl .. "deps/signal.lua")

-- Export a universal cleanup helper (strict)
local function CleanupAllMaids()
    for featureName, maidObject in pairs(Variables.Maids) do
        pcall(function()
            if maidObject and maidObject.DoCleaning then
                maidObject:DoCleaning()
            end
        end)
        Variables.Maids[featureName] = nil
    end
end
Variables.CleanupAllMaids = CleanupAllMaids

-- =========================
-- 4) UI Library bootstrap
-- =========================
local Library      = loadstring(game:HttpGet(ObsidianUrlBase .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(ObsidianUrlBase .. "addons/ThemeManager.lua"))()
local SaveManager  = loadstring(game:HttpGet(ObsidianUrlBase .. "addons/SaveManager.lua"))()

-- Window
local MainWindow = Library:CreateWindow({
    Title = Variables.Branding.Title,
    Footer = Variables.Branding.Footer,
    Size = UDim2.fromOffset(500, 600),
    Icon = Variables.Branding.IconAssetId,
    NotifySide = "Right",
    ShowCustomCursor = false,
})

-- Tabs (modules should use these to attach their own UI)
local Tabs = {
    Misc = MainWindow:AddTab("Misc", "dice-4"),
    Settings = MainWindow:AddTab("Settings", "settings"),
}

-- Settings pane (kept in main)
do
    local MenuGroupbox = Tabs.Settings:AddLeftGroupbox("Menu", "layout-dashboard")

    MenuGroupbox:AddToggle("WFYB_ShowCustomCursor", {
        Text = "Custom Cursor",
        Default = false,
        Callback = function(isEnabled)
            Library.ShowCustomCursor = isEnabled
        end
    })

    MenuGroupbox:AddButton("Unload", function()
        Variables.CleanupAllMaids()
        pcall(function()
            if Library and Library.Unload then
                Library:Unload()
            end
        end)
    end)

    ThemeManager:SetLibrary(Library)
    SaveManager:SetLibrary(Library)
    SaveManager:IgnoreThemeSettings()

    ThemeManager:SetFolder("WFYB_V4")
    SaveManager:SetFolder("WFYB_V4/WhateverFloatsYourBoat")
    SaveManager:SetSubFolder("Current")

    SaveManager:BuildConfigSection(Tabs.Settings)
    ThemeManager:ApplyToTab(Tabs.Settings)

    -- Attempt autoload if present
    pcall(function()
        SaveManager:LoadAutoloadConfig()
    end)
end

-- =========================
-- 5) Module registry
-- =========================
-- Structure matches your repo:
-- repo/
--   deps/
--   modules/
--     universal/*.lua   -- runs for all experiences
--     wfyb/*.lua        -- WFYB-specific features
--
-- Add or rename entries here to match your files.
local ModuleGroups = {
    universal = {
        "Shield",          -- example: telemetry/anti-hook protections; optional
    },
    wfyb = {
        "UltraAFK",
        "InfZoom",
        "AntiAFK",
        "VIPServerCommands",
    }
}

local function moduleUrl(categoryName, moduleName)
    return BaseUrl .. "modules/" .. categoryName .. "/" .. moduleName .. ".lua"
end

-- =========================
-- 6) Module load pipeline
-- =========================
-- Each module may export one or more of the following:
--   Init(env)        - receives {RbxService, Variables, Maid, Signal, Library}
--   BuildUI(tabs)    - add its own groupboxes/toggles/buttons
--   Start() / Stop() - lifecycle (often wired to toggles inside BuildUI)
--   Run(...)         - fire-and-forget once (e.g., Shield)
--
-- One Maid per feature is created here if not present.

local LoadedModules = {}

local function ensureFeatureMaid(featureName)
    if not Variables.Maids[featureName] then
        Variables.Maids[featureName] = Maid.new()
    end
    return Variables.Maids[featureName]
end

local function tryInvoke(target, methodName, ...)
    if type(target) == "table" and type(target[methodName]) == "function" then
        local ok, errOrReturn = pcall(target[methodName], ...)
        if not ok then
            warn("[WFYB] Module " .. tostring(methodName) .. " failed: " .. tostring(errOrReturn))
        end
        return ok, errOrReturn
    end
    return false, nil
end

for categoryName, moduleList in pairs(ModuleGroups) do
    for _, moduleName in ipairs(moduleList) do
        local importName = categoryName .. "/" .. moduleName
        local sourceUrl = moduleUrl(categoryName, moduleName)

        local factoryOrTable
        local importOk, importErr = pcall(function()
            factoryOrTable = Loader.Import(importName, sourceUrl)
        end)
        if not importOk then
            warn("[WFYB] Import failed for " .. importName .. ": " .. tostring(importErr))
        else
            local moduleInstance = (type(factoryOrTable) == "function") and factoryOrTable() or factoryOrTable

            -- Ensure per-feature maid exists
            ensureFeatureMaid(moduleName)

            -- Inject environment
            tryInvoke(moduleInstance, "Init", {
                RbxService = RbxService,
                Variables = Variables,
                Maid = Maid,
                Signal = Signal,
                Library = Library,
            })

            -- Let the module attach its UI to our tabs
            tryInvoke(moduleInstance, "BuildUI", Tabs, Library)

            -- Allow a module to self-start (e.g., Shield)
            tryInvoke(moduleInstance, "Run", RbxService, Variables, Library)

            LoadedModules[moduleName] = moduleInstance
        end
    end
end

-- =========================
-- 7) Safety: auto-clean on CoreGui reset (rare)
-- =========================
do
    local function onAncestryChanged(instance, parent)
        if instance == RbxService.CoreGui and parent == nil then
            Variables.CleanupAllMaids()
        end
    end
    local CoreGuiMaid = Maid.new()
    CoreGuiMaid:GiveTask(RbxService.CoreGui.AncestryChanged:Connect(onAncestryChanged))
    Variables.Maids.CoreGuiGuard = CoreGuiMaid
end

-- Ready.
