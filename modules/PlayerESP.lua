do return function(UI)
    
local GlobalEnv = (getgenv and getgenv()) or _G
-- Services & Maid from repo
local RbxService = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
GlobalEnv.Signal = GlobalEnv.Signal or loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()
local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

-- Variables Table:
local Variables = {
    -- [Visuals] Player ESP:
	PlayerESPFeatureName                = "PlayerESP", -- Player ESP feature flag
	PlayerESPRunFlag                    = false, -- Player ESP run flag
	PlayerESPUILabels = {  -- UI label references for the player esp statistics section
	    Status      = nil, -- Player ESP status [ON/OFF]
	    PlayerCount = nil, -- Player ESP tracked # of players and # of players shown on ESP
	    FPS         = nil, -- FPS count
	},
	PlayerESPSettings = {  	-- Player ESP settings
	    Enabled = false, -- Master toggle
		-- Core Visuals
	    Box = false, -- Player ESP box outline
	    BoxFilled = false, -- Player ESP box fill
	    BoxRounded = false, -- Player ESP box corner [Sharp or Rounded]. Must SET HERE (No UI element)
	    BoxThickness = 2, -- Player ESP box outline thickness
	    BoxWidth = 80, -- Player ESP box width
	    BoxHeight = 120, -- Player ESP box height
	    BoxFillTransparency = 0.1, -- Player ESP fill transparency
	    -- Text & Bars
	    Name = false,
	    NameSize = 16,
	    DisplayName = true,
	    Health = false,
	    HealthSize = 14,
	    HealthBar = false,
	    HealthBarWidth = 3,
	    HealthBarStyle = "Vertical", -- "Vertical" | "Horizontal"
	    ArmorBar = false,
	    ArmorBarWidth = 3,
	    Stud = false,
	    StudSize = 14,
	    -- Extra Visuals
	    Skeleton = false,
	    SkeletonThickness = 2,
	    Highlight = false,
	    HighlightTransparency = 0.5,
	    Tracer = false,
	    TracerFrom = "Bottom", -- "Top" | "Center" | "Bottom"
	    TracerThickness = 1,
	    LookTracer = false,
	    LookTracerThickness = 2,
	    Chams = false,
	    ChamsTransparency = 0.5,
	    OutOfView = false,
	    OutOfViewSize = 15,
	    Arrow = false,          -- kept for completeness
	    ArrowSize = 20,         -- kept for completeness
	    Weapon = false,
	    WeaponSize = 14,
	    Flags = false,
	    FlagsSize = 12,
	    SnapLines = false,      -- kept for completeness
	    HeadDot = false,
	    HeadDotSize = 8,
	    -- Player ESP Colors
	    BoxColor = Color3.fromRGB(255, 0, 0),
	    BoxFillColor = Color3.fromRGB(255, 0, 0),
	    NameColor = Color3.fromRGB(255, 255, 255),
	    HealthColor = Color3.fromRGB(0, 255, 0),
	    HealthBarColorLow = Color3.fromRGB(255, 0, 0),
	    HealthBarColorMid = Color3.fromRGB(255, 255, 0),
	    HealthBarColorHigh = Color3.fromRGB(0, 255, 0),
	    ArmorBarColor = Color3.fromRGB(0, 150, 255),
	    StudColor = Color3.fromRGB(255, 255, 0),
	    SkeletonColor = Color3.fromRGB(255, 255, 255),
	    HighlightColor = Color3.fromRGB(255, 0, 255),
	    TracerColor = Color3.fromRGB(0, 255, 255),
	    LookTracerColor = Color3.fromRGB(255, 100, 0),
	    ArrowColor = Color3.fromRGB(255, 0, 0),     -- kept
	    ChamsColor = Color3.fromRGB(255, 0, 255),
	    OutOfViewColor = Color3.fromRGB(255, 0, 0),
	    WeaponColor = Color3.fromRGB(255, 200, 0),
	    FlagsColor = Color3.fromRGB(255, 255, 255),
	    HeadDotColor = Color3.fromRGB(255, 0, 0),
	    -- Player ESP Behavior
	    Transparency = 1,
	    TeamCheck = false,
	    TeamColor = false,
	    MaxDistance = 5000,
	    ShowOffscreen = true,
	    UseDistanceFade = true,
	    FadeStart = 3000,
	    RainbowMode = false,
	    RainbowSpeed = 1,
	    PerformanceMode = false,
	    UpdateRate = 60,
	    ShowLocalTeam = false,
	},
		-- Player ESP runtime state
		PlayerESPVisualsByPlayer            = {},   -- [Player] -> drawing/instances created
		PlayerESPPlayerData                 = {},   -- [Player] -> { LastPosition, Velocity, Speed }
		PlayerESPRainbowHue                 = 0,
		PlayerESPLastUpdateTimestamp        = 0,    -- tick()
		PlayerESPUpdateIntervalSeconds      = 1/60, -- derived from UpdateRate at Start()
		PlayerESPModule                     = nil,  -- assigned in Module block
}
-- Minimal per-feature maids (cleanup handled by main Maid; these are just buckets)
Variables.Maids = Variables.Maids or {}
Variables.Maids.PlayerESP = Variables.Maids.PlayerESP or Maid.new()
Variables.Maids.PlayerESPStats = Variables.Maids.PlayerESPStats or Maid.new()

-- Lightweight weak-maid map for per-player buckets (allows garbage collection)
Variables.WeakMaids = Variables.WeakMaids or setmetatable({}, {
    __mode = "k",
    __index = function(t, key)
        if key == nil then return nil end
        local m = rawget(t, key)
        if m then return m end
        m = Maid.new()
        rawset(t, key, m)
        return m
    end
})
    
local Options = (UI and UI.Options) or Library.Options
local Toggles = (UI and UI.Toggles) or Library.Toggles
local Tabs = (UI and UI.Tabs) or {}
if not Tabs.Visuals then error("UI.Tabs.Visuals is required (created by the loader).") end
-- Visuals Tab:
local CoreLeft       = Tabs.Visuals:AddLeftGroupbox("Core ESP", "eye")
local ExtraRight     = Tabs.Visuals:AddRightGroupbox("Additional ESP", "layers")
local AppearanceLeft = Tabs.Visuals:AddLeftGroupbox("Appearance", "palette")
local SizeRight      = Tabs.Visuals:AddRightGroupbox("Size Settings", "move-diagonal")
local FiltersLeft    = Tabs.Visuals:AddLeftGroupbox("Filters", "filter")
local PerfRight      = Tabs.Visuals:AddRightGroupbox("Performance", "gauge")
	-- [Player ESP] MASTER Toggle:
	CoreLeft:AddToggle("ESPEnabled", {
	    Text = "Enable ESP",
	    Default = Variables.PlayerESPSettings.Enabled
	})

	-- CORE (toggle + inline color pickers)
	CoreLeft:AddToggle("ESPBox",      { Text = "Box ESP",      Default = Variables.PlayerESPSettings.Box })
	    :AddColorPicker("BoxColor",   { Title = "Box Color",   Default = Variables.PlayerESPSettings.BoxColor })
	
	CoreLeft:AddToggle("BoxFilled",   { Text = "Filled Box",   Default = Variables.PlayerESPSettings.BoxFilled })
	    :AddColorPicker("BoxFillColor",{ Title = "Fill Color", Default = Variables.PlayerESPSettings.BoxFillColor })
	
	CoreLeft:AddToggle("ESPName",     { Text = "Name ESP",     Default = Variables.PlayerESPSettings.Name })
	    :AddColorPicker("NameColor",  { Title = "Name Color",  Default = Variables.PlayerESPSettings.NameColor })
	
	CoreLeft:AddToggle("ESPHealth",   { Text = "Health Text",  Default = Variables.PlayerESPSettings.Health })
	    :AddColorPicker("HealthColor",{ Title = "Health Color",Default = Variables.PlayerESPSettings.HealthColor })
	
	CoreLeft:AddToggle("ESPHealthBar",{ Text = "Health Bar",   Default = Variables.PlayerESPSettings.HealthBar })
	    :AddColorPicker("HealthBarHigh", { Title = "HP High", Default = Variables.PlayerESPSettings.HealthBarColorHigh })
	    :AddColorPicker("HealthBarMid",  { Title = "HP Mid",  Default = Variables.PlayerESPSettings.HealthBarColorMid })
	    :AddColorPicker("HealthBarLow",  { Title = "HP Low",  Default = Variables.PlayerESPSettings.HealthBarColorLow })
	
	CoreLeft:AddDropdown("HealthBarStyle", {
	    Text = "Health Bar Style",
	    Values = { "Vertical", "Horizontal" },
	    Default = Variables.PlayerESPSettings.HealthBarStyle or "Vertical"
	})
	
	CoreLeft:AddToggle("ESPStud",     { Text = "Distance ESP", Default = Variables.PlayerESPSettings.Stud })
	    :AddColorPicker("StudColor",  { Title = "Distance Color", Default = Variables.PlayerESPSettings.StudColor })
	
	CoreLeft:AddToggle("DisplayName", { Text = "Show Display Name", Default = Variables.PlayerESPSettings.DisplayName ~= false })
	
	-- ADDITIONAL
	ExtraRight:AddToggle("ESPSkeleton", { Text = "Skeleton ESP", Default = Variables.PlayerESPSettings.Skeleton })
	    :AddColorPicker("SkeletonColor", { Title = "Skeleton Color", Default = Variables.PlayerESPSettings.SkeletonColor })
	
	ExtraRight:AddToggle("ESPHighlight",{ Text = "Highlight ESP", Default = Variables.PlayerESPSettings.Highlight })
	    :AddColorPicker("HighlightColor",{ Title = "Highlight Color", Default = Variables.PlayerESPSettings.HighlightColor })
	
	ExtraRight:AddToggle("ESPChams",    { Text = "Chams (Wallhack)", Default = Variables.PlayerESPSettings.Chams })
	    :AddColorPicker("ChamsColor",    { Title = "Chams Color", Default = Variables.PlayerESPSettings.ChamsColor })
	
	ExtraRight:AddToggle("ESPTracer",   { Text = "Tracer ESP", Default = Variables.PlayerESPSettings.Tracer })
	    :AddColorPicker("TracerColor",   { Title = "Tracer Color", Default = Variables.PlayerESPSettings.TracerColor })
	
	ExtraRight:AddToggle("LookTracer",  { Text = "Look Direction", Default = Variables.PlayerESPSettings.LookTracer })
	    :AddColorPicker("LookTracerColor",{ Title = "Look Tracer Color", Default = Variables.PlayerESPSettings.LookTracerColor })
	
	ExtraRight:AddToggle("HeadDot",     { Text = "Head Dot", Default = Variables.PlayerESPSettings.HeadDot })
	    :AddColorPicker("HeadDotColor",  { Title = "Head Dot Color", Default = Variables.PlayerESPSettings.HeadDotColor })
	
	ExtraRight:AddToggle("OutOfView",   { Text = "Off-Screen Arrows", Default = Variables.PlayerESPSettings.OutOfView })
	    :AddColorPicker("OutOfViewColor",{ Title = "Arrow Color", Default = Variables.PlayerESPSettings.OutOfViewColor })
	
	ExtraRight:AddToggle("ESPWeapon",   { Text = "Weapon Display", Default = Variables.PlayerESPSettings.Weapon })
	    :AddColorPicker("WeaponColor",   { Title = "Weapon Color", Default = Variables.PlayerESPSettings.WeaponColor })
	
	ExtraRight:AddToggle("ESPFlags",    { Text = "Status Flags", Default = Variables.PlayerESPSettings.Flags })
	    :AddColorPicker("FlagsColor",    { Title = "Flags Color", Default = Variables.PlayerESPSettings.FlagsColor })
	
	ExtraRight:AddToggle("ArmorBar",    { Text = "Armor Bar (Experimental)", Default = Variables.PlayerESPSettings.ArmorBar })
	    :AddColorPicker("ArmorBarColor", { Title = "Armor Color", Default = Variables.PlayerESPSettings.ArmorBarColor })

	-- APPEARANCE (sliders/toggles)
	AppearanceLeft:AddToggle("RainbowMode", { Text = "Rainbow Mode", Default = Variables.PlayerESPSettings.RainbowMode })
	AppearanceLeft:AddSlider("RainbowSpeed",{
	    Text = "Rainbow Speed", Default = Variables.PlayerESPSettings.RainbowSpeed or 1, Min = 0.1, Max = 5, Rounding = 1
	})
	AppearanceLeft:AddToggle("TeamColor", { Text = "Use Team Colors", Default = Variables.PlayerESPSettings.TeamColor })
	
	AppearanceLeft:AddSlider("ESPTransparency",{
	    Text = "ESP Transparency", Default = Variables.PlayerESPSettings.Transparency, Min = 0, Max = 1, Rounding = 2
	})
	AppearanceLeft:AddSlider("BoxFillTransparency",{
	    Text = "Fill Transparency", Default = Variables.PlayerESPSettings.BoxFillTransparency, Min = 0, Max = 1, Rounding = 2
	})
	AppearanceLeft:AddSlider("HighlightTransparency",{
	    Text = "Highlight Transparency", Default = Variables.PlayerESPSettings.HighlightTransparency, Min = 0, Max = 1, Rounding = 2
	})
	AppearanceLeft:AddSlider("ChamsTransparency",{
	    Text = "Chams Transparency", Default = Variables.PlayerESPSettings.ChamsTransparency, Min = 0, Max = 1, Rounding = 2
	})
	-- SIZE SETTINGS
	SizeRight:AddSlider("BoxWidth",     { Text = "Box Width",   Default = Variables.PlayerESPSettings.BoxWidth,   Min = 40,  Max = 200, Rounding = 0 })
	SizeRight:AddSlider("BoxHeight",    { Text = "Box Height",  Default = Variables.PlayerESPSettings.BoxHeight,  Min = 60,  Max = 300, Rounding = 0 })
	SizeRight:AddSlider("BoxThickness", { Text = "Box Thickness",Default = Variables.PlayerESPSettings.BoxThickness, Min = 1,  Max = 6,   Rounding = 0 })
	SizeRight:AddSlider("NameSize",     { Text = "Name Size",           Default = Variables.PlayerESPSettings.NameSize,       Min = 8,  Max = 32, Rounding = 0 })
	SizeRight:AddSlider("HealthSize",   { Text = "Health Text Size",    Default = Variables.PlayerESPSettings.HealthSize,     Min = 8,  Max = 24, Rounding = 0 })
	SizeRight:AddSlider("HealthBarWidth",{ Text = "Health Bar Width",   Default = Variables.PlayerESPSettings.HealthBarWidth, Min = 2,  Max = 10, Rounding = 0 })
	SizeRight:AddSlider("ArmorBarWidth",{ Text = "Armor Bar Width",     Default = Variables.PlayerESPSettings.ArmorBarWidth,  Min = 2,  Max = 10, Rounding = 0 })
	SizeRight:AddSlider("StudSize",     { Text = "Distance Size",       Default = Variables.PlayerESPSettings.StudSize,       Min = 8,  Max = 24, Rounding = 0 })
	SizeRight:AddSlider("WeaponSize",   { Text = "Weapon Size",         Default = Variables.PlayerESPSettings.WeaponSize,     Min = 8,  Max = 22, Rounding = 0 })
	SizeRight:AddSlider("FlagsSize",    { Text = "Flags Size",          Default = Variables.PlayerESPSettings.FlagsSize,      Min = 8,  Max = 20, Rounding = 0 })
	SizeRight:AddSlider("SkeletonThickness",{ Text = "Skeleton Thickness", Default = Variables.PlayerESPSettings.SkeletonThickness, Min = 1, Max = 5, Rounding = 0 })
	SizeRight:AddSlider("TracerThickness",{ Text = "Tracer Thickness",  Default = Variables.PlayerESPSettings.TracerThickness,Min = 1,  Max = 6, Rounding = 0 })
	SizeRight:AddSlider("LookTracerThickness",{ Text = "Look Tracer Thickness", Default = Variables.PlayerESPSettings.LookTracerThickness, Min = 1, Max = 5, Rounding = 0 })
	SizeRight:AddSlider("HeadDotSize",  { Text = "Head Dot Size",       Default = Variables.PlayerESPSettings.HeadDotSize,    Min = 4,  Max = 20, Rounding = 0 })
	SizeRight:AddSlider("OutOfViewSize",{ Text = "Off-Screen Arrow Size",Default = Variables.PlayerESPSettings.OutOfViewSize,  Min = 10, Max = 30, Rounding = 0 })
-- Player ESP Filters Groupbox
	FiltersLeft:AddToggle("TeamCheck",     { Text = "Team Check",    Default = Variables.PlayerESPSettings.TeamCheck })
	FiltersLeft:AddToggle("ShowLocalTeam", { Text = "Show Teammates", Default = Variables.PlayerESPSettings.ShowLocalTeam })
	FiltersLeft:AddToggle("ShowOffscreen", { Text = "Show Offscreen", Default = Variables.PlayerESPSettings.ShowOffscreen })
	FiltersLeft:AddSlider("MaxDistance",{
	    Text = "Max Distance", Default = Variables.PlayerESPSettings.MaxDistance, Min = 500, Max = 15000, Rounding = 0, Suffix = " studs"
	})
	FiltersLeft:AddToggle("UseDistanceFade",{ Text = "Distance Fade", Default = Variables.PlayerESPSettings.UseDistanceFade })
	FiltersLeft:AddSlider("FadeStart",{
	    Text = "Fade Start Distance", Default = Variables.PlayerESPSettings.FadeStart, Min = 300, Max = 10000, Rounding = 0, Suffix = " studs"
	})
	FiltersLeft:AddDropdown("TracerFrom",{
	    Text = "Tracer From", Values = { "Bottom", "Center", "Top" },
	    Default = Variables.PlayerESPSettings.TracerFrom or "Bottom"
	})
-- Performance Groupbox (RIGHT):
	PerfRight:AddToggle("PerformanceMode", { Text = "Performance Mode", Default = Variables.PlayerESPSettings.PerformanceMode })
	PerfRight:AddSlider("UpdateRate", {
	    Text = "Update Rate (FPS)",
	    Default = Variables.PlayerESPSettings.UpdateRate,
	    Min = 15, Max = 144, Rounding = 0, Suffix = " FPS"
	})
	PerfRight:AddLabel("Performance Info")
	PerfRight:AddLabel("Lower update rate = better performance")
	PerfRight:AddLabel("Disable unused features for FPS boost")
	PerfRight:AddButton({
	    Text = "Refresh All ESP",
	    Func = function()
	        if Variables.PlayerESPModule and Variables.PlayerESPModule.RefreshAll then
	            Variables.PlayerESPModule.RefreshAll()
	        end
	        if Library and Library.Notify then Library:Notify("ESP Refreshed!", 3) end
	    end
	})
	PerfRight:AddButton({
	    Text = "Clear All ESP",
	    Func = function()
	        if Variables.PlayerESPModule and Variables.PlayerESPModule.ClearAll then
	            Variables.PlayerESPModule.ClearAll()
	        end
	        if Library and Library.Notify then Library:Notify("All ESP Cleared!", 3) end
	    end
	})
-- Player ESP Statisics Groupbox (LEFT):
local StatsLeft = Tabs.Visuals:AddLeftGroupbox("Statistics", "bar-chart-3")
	Variables.PlayerESPUILabels.Status      = StatsLeft:AddLabel("ESP Status: Inactive")
	Variables.PlayerESPUILabels.PlayerCount = StatsLeft:AddLabel("Players Visible: 0/0")
	Variables.PlayerESPUILabels.FPS         = StatsLeft:AddLabel("FPS: 0")
		-- Start the stats updater once
		if Variables.PlayerESPModule and Variables.PlayerESPModule.AttachStatsUpdater then
		    Variables.PlayerESPModule.AttachStatsUpdater()
		end

-- EXP Tab:
	local EXPFarmGroupBox = Tabs.EXP:AddLeftGroupbox("EXP Farm", "arrow-right-left")
		local AutoPropEXPToggle = EXPFarmGroupBox:AddToggle("AutoPropEXPToggle", {
			Text = "Prop EXP",
			Tooltip = "Turn Feature [ON/OFF].", 
			DisabledTooltip = "Feature Disabled!", 
			Default = false, 
			Disabled = false, 
			Visible = true, 
			Risky = false, 
		})
		local AutoFlamethrowerToggle = EXPFarmGroupBox:AddToggle("AutoFlamethrowerToggle", {
			Text = "Single Flame",
			Tooltip = "Turn Feature [ON/OFF].", 
			DisabledTooltip = "Feature Disabled!", 
			Default = false, 
			Disabled = false, 
			Visible = true, 
			Risky = false, 
		})
		local AutoMultiFlamethrowerToggle = EXPFarmGroupBox:AddToggle("AutoMultiFlamethrowerToggle", {
			Text = "Multiple Flame",
			Tooltip = "Turn Feature [ON/OFF].", 
			DisabledTooltip = "Feature Disabled!", 
			Default = false, 
			Disabled = false, 
			Visible = true, 
			Risky = false, 
		})
		local AutoRepairAllToggle = EXPFarmGroupBox:AddToggle("AutoRepairAllToggle", {
			Text = "Repair All",
			Tooltip = "Turn Feature [ON/OFF].", 
			DisabledTooltip = "Feature Disabled!", 
			Default = false, 
			Disabled = false, 
			Visible = true, 
			Risky = false, 
		})
		local AutoRepairSelfToggle = EXPFarmGroupBox:AddToggle("AutoRepairSelfToggle", {
			Text = "Repair Self",
			Tooltip = "Turn Feature [ON/OFF].", 
			DisabledTooltip = "Feature Disabled!", 
			Default = false, 
			Disabled = false, 
			Visible = true, 
			Risky = false, 
		})
		local AutoRepairTeamToggle = EXPFarmGroupBox:AddToggle("AutoRepairTeamToggle", {
			Text = "Repair Team",
			Tooltip = "Turn Feature [ON/OFF].", 
			DisabledTooltip = "Feature Disabled!", 
			Default = false, 
			Disabled = false, 
			Visible = true, 
			Risky = false, 
		})
		local AutoPVPModeToggle = EXPFarmGroupBox:AddToggle("AutoPVPModeToggle", {
			Text = "PVP Mode",
			Tooltip = "Turn Feature [ON/OFF].", 
			DisabledTooltip = "Feature Disabled!", 
			Default = false, 
			Disabled = false, 
			Visible = true, 
			Risky = false, 
		})
		local AutoPopupToggle = EXPFarmGroupBox:AddToggle("AutoPopupToggle", {
			Text = "Remove Popup",
			Tooltip = "Turn Feature [ON/OFF].", 
			DisabledTooltip = "Feature Disabled!", 
			Default = false, 
			Disabled = false, 
			Visible = true, 
			Risky = false, 
		})

-- Dupe Tab:
	local DupeStep1GroupBox = Tabs.Dupe:AddLeftGroupbox("Step #1", "arrow-right-left")
		local TransferMoneyToggle = DupeStep1GroupBox:AddToggle("TransferMoneyToggle", {
			Text = "Transfer Money",
			Tooltip = "Turn Feature [ON/OFF].", 
			DisabledTooltip = "Feature Disabled!", 
			Default = false, 
			Disabled = false, 
			Visible = true, 
			Risky = false, 
		})
		Toggles.TransferMoneyToggle:AddKeyPicker("TransferMoneyKeybind", {
			Text = "Transfer Money",
			SyncToggleState = true,
			Mode = "Toggle", 
			NoUI = false, 
		})

	local DupeStep2GroupBox = Tabs.Dupe:AddRightGroupbox("Step #2", "bomb")
		DupeStep2GroupBox:AddDropdown("BoatDropdown", {
			Text = "Save Slot:",
		    Values = Variables.GameServerDatabaseFetchBoatSaveData, 
		    Multi = false, 
		})
		local CrashServerToggle = DupeStep2GroupBox:AddToggle("CrashServerToggle", {
			Text = "Crash Server",
			Tooltip = "Turn Feature [ON/OFF].", 
			DisabledTooltip = "Feature Disabled!", 
			Default = false, 
			Disabled = false, 
			Visible = true, 
			Risky = false, 
		})

	-- Debug Tab:
	local ToolsGroupBox = Tabs.Debug:AddLeftGroupbox("Client Modifiers", "pocket-knife")
		local InfiniteYieldButton = ToolsGroupBox:AddButton({
		    Text = "Load Infinite Yield",
		    Func = function()
		        local _, ok, err = Variables.ensureInfiniteYield(false)
		        if ok then
		            Variables.notify("Infinite Yield Loaded.")
		        else
		            Variables.notify("Failed to load Infinite Yield.\n" .. tostring(err))
		        end
		    end,
		    DoubleClick = true,
		    Tooltip = "Double click to load infinite yield.",
		    DisabledTooltip = "Feature Disabled",
		    Disabled = false,
		})
		local DexExplorerButton = ToolsGroupBox:AddButton({
		    Text = "Load Dex Explorer",
		    Func = function()
		        local _, ok, err = Variables.ensureDexExplorer(false)
		        if ok then
		            Variables.notify("Dex Explorer Loaded.")
		        else
		            Variables.notify("Failed to load Dex Explorer.\n" .. tostring(err))
		        end
		    end,
		    DoubleClick = true,
		    Tooltip = "Double click to load dex explorer.",
		    DisabledTooltip = "Feature Disabled",
		    Disabled = false,
		})
		local DecompilerButton = ToolsGroupBox:AddButton({
		    Text = "Load Decompiler",
		    Func = function()
		        local _, ok, err = Variables.ensureDecompiler(false)
		        if ok then
		            Variables.notify("Decompiler Loaded.")
		        else
		            Variables.notify("Failed to load Decompiler.\n" .. tostring(err))
		        end
		    end,
		    DoubleClick = true,
		    Tooltip = "Double click to load decompiler.",
		    DisabledTooltip = "Feature Disabled",
		    Disabled = false,
		})
		
		local RemoteSpysGroupBox = Tabs.Debug:AddLeftGroupbox("Remote Spys", "hat-glasses")
			local SimpleSpyButton = RemoteSpysGroupBox:AddButton({
			    Text = "Load Simple Spy",
			    Func = function()
			        local _, ok, err = Variables.ensureSimpleSpy(false)
			        if ok then
			            Variables.notify("Simple Spy Loaded.")
			        else
			            Variables.notify("Failed to load Simple Spy.\n" .. tostring(err))
			        end
			    end,
			    DoubleClick = true,
			    Tooltip = "Double click to load simple spy.",
			    DisabledTooltip = "Feature Disabled",
			    Disabled = false,
			})
			local OctoSpyButton = RemoteSpysGroupBox:AddButton({
			    Text = "Load OctoSpy",
			    Func = function()
			        local _, ok, err = Variables.ensureOctoSpy(false)
			        if ok then
			            Variables.notify("OctoSpy Loaded.")
			        else
			            Variables.notify("Failed to load OctoSpy.\n" .. tostring(err))
			        end
			    end,
			    DoubleClick = true,
			    Tooltip = "Double click to load octospy.",
			    DisabledTooltip = "Feature Disabled",
			    Disabled = false,
			})
			local ShitsploitHttpsSpyButton = RemoteSpysGroupBox:AddButton({
			    Text = "Load Https Spy",
			    Func = function()
			        local _, ok, err = Variables.ensureShitsploitHttpsSpy(false)
			        if ok then
			            Variables.notify("Https Spy Loaded.")
			        else
			            Variables.notify("Failed to load Https Spy.\n" .. tostring(err))
			        end
			    end,
			    DoubleClick = true,
			    Tooltip = "Double click to load shitsploit https spy.",
			    DisabledTooltip = "Feature Disabled",
			    Disabled = false,
			})

-- Settings:
local MenuGroup = Tabs["Settings"]:AddLeftGroupbox("Menu", "layout-dashboard")
	MenuGroup:AddToggle("KeybindMenuOpen", {
		Default = Library.KeybindFrame.Visible,
		Text = "Open Keybind Menu",
		Callback = function(value)
			Library.KeybindFrame.Visible = value
		end,
	})
	MenuGroup:AddToggle("ShowCustomCursor", {
		Text = "Custom Cursor",
		Default = false,
		Callback = function(Value)
			Library.ShowCustomCursor = Value
		end,
	})
	MenuGroup:AddDropdown("NotificationSide", {
		Values = { "Left", "Right" },
		Default = "Right",
		Text = "Notification Side",
		Callback = function(Value)
			Library:SetNotifySide(Value)
		end,
	})
	MenuGroup:AddDropdown("DPIDropdown", {
		Values = { "50%", "75%", "100%", "125%", "150%", "175%", "200%" },
		Default = "100%",
		Text = "DPI Scale",
		Callback = function(Value)
			Value = Value:gsub("%%", "")
			local DPI = tonumber(Value)
			Library:SetDPIScale(DPI)
		end,
	})
	MenuGroup:AddDivider()
	MenuGroup:AddLabel("Menu bind")
		:AddKeyPicker("MenuKeybind", { Default = "Backquote", NoUI = true, Text = "Menu Keybind" })
	MenuGroup:AddButton("Unload", function()
		Variables.CleanupAllMaids()
		Library:Unload()
	end)
	Library.ToggleKeybind = Options.MenuKeybind 
	ThemeManager:SetLibrary(Library)
	SaveManager:SetLibrary(Library)
	SaveManager:IgnoreThemeSettings()
	SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
	ThemeManager:SetFolder("WFYBGG_V4")
	SaveManager:SetFolder("WFYBGG_V4/WhateverFloatsYourBoat")
	SaveManager:SetSubFolder("Current") 
	SaveManager:BuildConfigSection(Tabs["Settings"])
	ThemeManager:ApplyToTab(Tabs["Settings"])
	SaveManager:LoadAutoloadConfig()


-- Modules:
	-- [Visuals] Player ESP Module:
-- Module:
do
    -- Helpers kept internal to the module
    local function PlayerESPGetRainbowColor()
        Variables.PlayerESPRainbowHue = (Variables.PlayerESPRainbowHue + Variables.PlayerESPSettings.RainbowSpeed * 0.001) % 1
        return Color3.fromHSV(Variables.PlayerESPRainbowHue, 1, 1)
    end

    local function PlayerESPGetDistanceFade(distance)
        if not Variables.PlayerESPSettings.UseDistanceFade then return 1 end
        if distance < Variables.PlayerESPSettings.FadeStart then return 1 end
        local fadeRange = Variables.PlayerESPSettings.MaxDistance - Variables.PlayerESPSettings.FadeStart
        local fadeAmount = (Variables.PlayerESPSettings.MaxDistance - distance) / math.max(1, fadeRange)
        return math.max(0.2, fadeAmount)
    end

    local function PlayerESPGetTeamColor(player)
        if player and player.Team then
            return player.Team.TeamColor.Color
        end
        return Color3.fromRGB(255, 255, 255)
    end

    local function PlayerESPGetEquippedWeaponName(character)
        if not character then return "None" end
        for _, child in ipairs(character:GetChildren()) do
            if child:IsA("Tool") then return child.Name end
        end
        return "None"
    end

    local function PlayerESPGetFlagsText(player, character)
        local flags, humanoid = {}, character and character:FindFirstChild("Humanoid")
        if humanoid then
            if humanoid.Sit           then flags[#flags+1] = "SIT"  end
            if humanoid.PlatformStand then flags[#flags+1] = "STUN" end
            if humanoid.Jump          then flags[#flags+1] = "JUMP" end
        end
        if character and character:FindFirstChildOfClass("ForceField") then
            flags[#flags+1] = "FF"
        end
        return table.concat(flags, " | ")
    end

    local function PlayerESPIsVisible(character)
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if not root then return false end
        local camera = RbxService.Workspace.CurrentCamera
        local distance = (camera.CFrame.Position - root.Position).Magnitude
        if distance > Variables.PlayerESPSettings.MaxDistance then return false end
        local _, onScreen = camera:WorldToViewportPoint(root.Position)
        return onScreen or Variables.PlayerESPSettings.ShowOffscreen
    end

    local function PlayerESPUpdatePlayerData(player)
        local entry = Variables.PlayerESPPlayerData[player]
        if not entry then
            entry = { LastPosition = nil, Velocity = Vector3.new(), Speed = 0 }
            Variables.PlayerESPPlayerData[player] = entry
        end
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if root then
            if entry.LastPosition then
                local delta = root.Position - entry.LastPosition
                entry.Velocity = delta
                entry.Speed = delta.Magnitude
            end
            entry.LastPosition = root.Position
        end
    end

    local function PlayerESPDestroyForPlayer(player)
        local visuals = Variables.PlayerESPVisualsByPlayer[player]
        if visuals then
            for key, visual in pairs(visuals) do
                if key == "Skeleton" then
                    for _, data in pairs(visual) do
                        pcall(function() data.line:Remove() end)
                    end
                elseif key == "Highlight" or key == "Chams" then
                    pcall(function() visual:Destroy() end)
                else
                    pcall(function() visual:Remove() end)
                end
            end
            Variables.PlayerESPVisualsByPlayer[player] = nil
        end
        Variables.PlayerESPPlayerData[player] = nil
        local perPlayerMaid = Variables.WeakMaids[player]
        if perPlayerMaid then pcall(function() perPlayerMaid:DoCleaning() end) end
    end

    local function PlayerESPCreateForPlayer(player)
        if player == RbxService.Players.LocalPlayer then return end
        local character = player.Character
        if not character then return end
        local humanoid = character:FindFirstChild("Humanoid")
        local rootPart = character:FindFirstChild("HumanoidRootPart")
        if not humanoid or not rootPart then return end

        if Variables.PlayerESPVisualsByPlayer[player] then
            PlayerESPDestroyForPlayer(player)
        end

        local visuals = {}
        Variables.PlayerESPVisualsByPlayer[player] = visuals

        -- Filled box
        if Variables.PlayerESPSettings.BoxFilled then
            local boxFill = Drawing.new("Square")
            boxFill.Filled = true
            boxFill.Thickness = 1
            boxFill.Color = Variables.PlayerESPSettings.BoxFillColor
            boxFill.Transparency = Variables.PlayerESPSettings.BoxFillTransparency
            boxFill.Visible = false
            visuals.BoxFill = boxFill
        end

        -- Box outline
        if Variables.PlayerESPSettings.Box then
            local box = Drawing.new("Square")
            box.Filled = false
            box.Thickness = Variables.PlayerESPSettings.BoxThickness
            box.Transparency = Variables.PlayerESPSettings.Transparency
            box.Color = Variables.PlayerESPSettings.BoxColor
            box.Visible = false
            visuals.Box = box
        end

        -- Name text
        if Variables.PlayerESPSettings.Name then
            local nameText = Drawing.new("Text")
            nameText.Size = Variables.PlayerESPSettings.NameSize
            nameText.Center, nameText.Outline = true, true
            nameText.Color = Variables.PlayerESPSettings.NameColor
            nameText.Text = (Variables.PlayerESPSettings.DisplayName and player.DisplayName) or player.Name
            nameText.Visible = false
            visuals.Name = nameText
        end

        -- Health text
        if Variables.PlayerESPSettings.Health then
            local healthText = Drawing.new("Text")
            healthText.Size = Variables.PlayerESPSettings.HealthSize
            healthText.Center, healthText.Outline = true, true
            healthText.Color = Variables.PlayerESPSettings.HealthColor
            healthText.Visible = false
            visuals.Health = healthText
        end

        -- Health bar
        if Variables.PlayerESPSettings.HealthBar then
            local barBg = Drawing.new("Square")
            barBg.Filled = true
            barBg.Color = Color3.fromRGB(0,0,0)
            barBg.Transparency = 0.5
            barBg.Visible = false
            visuals.HealthBarBg = barBg

            local bar = Drawing.new("Square")
            bar.Filled = true
            bar.Transparency = Variables.PlayerESPSettings.Transparency
            bar.Visible = false
            visuals.HealthBar = bar
        end

        -- Armor bar
        if Variables.PlayerESPSettings.ArmorBar then
            local armorBg = Drawing.new("Square")
            armorBg.Filled = true
            armorBg.Color = Color3.fromRGB(0,0,0)
            armorBg.Transparency = 0.5
            armorBg.Visible = false
            visuals.ArmorBarBg = armorBg

            local armor = Drawing.new("Square")
            armor.Filled = true
            armor.Transparency = Variables.PlayerESPSettings.Transparency
            armor.Visible = false
            visuals.ArmorBar = armor
        end

        -- Distance text
        if Variables.PlayerESPSettings.Stud then
            local studsText = Drawing.new("Text")
            studsText.Size = Variables.PlayerESPSettings.StudSize
            studsText.Center, studsText.Outline = true, true
            studsText.Color = Variables.PlayerESPSettings.StudColor
            studsText.Visible = false
            visuals.Stud = studsText
        end

        -- Weapon text
        if Variables.PlayerESPSettings.Weapon then
            local weaponText = Drawing.new("Text")
            weaponText.Size = Variables.PlayerESPSettings.WeaponSize
            weaponText.Center, weaponText.Outline = true, true
            weaponText.Color = Variables.PlayerESPSettings.WeaponColor
            weaponText.Visible = false
            visuals.Weapon = weaponText
        end

        -- Flags text
        if Variables.PlayerESPSettings.Flags then
            local flagsText = Drawing.new("Text")
            flagsText.Size = Variables.PlayerESPSettings.FlagsSize
            flagsText.Center, flagsText.Outline = true, true
            flagsText.Color = Variables.PlayerESPSettings.FlagsColor
            flagsText.Visible = false
            visuals.Flags = flagsText
        end

        -- Head dot
        if Variables.PlayerESPSettings.HeadDot then
            local headDot = Drawing.new("Circle")
            headDot.Filled = true
            headDot.Transparency = Variables.PlayerESPSettings.Transparency
            headDot.Visible = false
            visuals.HeadDot = headDot
        end

        -- Skeleton
        if Variables.PlayerESPSettings.Skeleton then
            visuals.Skeleton = {}
            local bonePairs = {
                {"Head","UpperTorso"}, {"UpperTorso","LowerTorso"},
                {"LowerTorso","LeftUpperLeg"}, {"LeftUpperLeg","LeftLowerLeg"}, {"LeftLowerLeg","LeftFoot"},
                {"LowerTorso","RightUpperLeg"}, {"RightUpperLeg","RightLowerLeg"}, {"RightLowerLeg","RightFoot"},
                {"UpperTorso","LeftUpperArm"}, {"LeftUpperArm","LeftLowerArm"}, {"LeftLowerArm","LeftHand"},
                {"UpperTorso","RightUpperArm"}, {"RightUpperArm","RightLowerArm"}, {"RightLowerArm","RightHand"},
            }
            for i = 1, #bonePairs do
                local line = Drawing.new("Line")
                line.Visible = false
                visuals.Skeleton[i] = { bones = bonePairs[i], line = line }
            end
        end

        -- Highlight (always-on-top)
        if Variables.PlayerESPSettings.Highlight then
            local highlight = Instance.new("Highlight")
            highlight.Adornee = character
            highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            highlight.FillColor = Variables.PlayerESPSettings.HighlightColor
            highlight.FillTransparency = Variables.PlayerESPSettings.HighlightTransparency
            highlight.OutlineColor = Variables.PlayerESPSettings.HighlightColor
            highlight.Parent = character
            visuals.Highlight = highlight
        end

        -- Chams (only if Highlight is OFF, like original)
        if Variables.PlayerESPSettings.Chams and not Variables.PlayerESPSettings.Highlight then
            local chams = Instance.new("Highlight")
            chams.Adornee = character
            chams.DepthMode = Enum.HighlightDepthMode.Occluded
            chams.FillColor = Variables.PlayerESPSettings.ChamsColor
            chams.FillTransparency = Variables.PlayerESPSettings.ChamsTransparency
            chams.OutlineColor = Variables.PlayerESPSettings.ChamsColor
            chams.Parent = character
            visuals.Chams = chams
        end

        -- Tracer
        if Variables.PlayerESPSettings.Tracer then
            local tracer = Drawing.new("Line")
            tracer.Transparency = Variables.PlayerESPSettings.Transparency
            tracer.Visible = false
            visuals.Tracer = tracer
        end

        -- Look tracer
        if Variables.PlayerESPSettings.LookTracer then
            local lt = Drawing.new("Line")
            lt.Transparency = Variables.PlayerESPSettings.Transparency
            lt.Visible = false
            visuals.LookTracer = lt
        end

        -- Off-screen arrow
        if Variables.PlayerESPSettings.OutOfView then
            local arrow = Drawing.new("Triangle")
            arrow.Filled = true
            arrow.Transparency = Variables.PlayerESPSettings.Transparency
            arrow.Visible = false
            visuals.Arrow = arrow
        end

        -- Optional snapline (kept for completeness)
        if Variables.PlayerESPSettings.SnapLines then
            local snap = Drawing.new("Line")
            snap.Visible = false
            visuals.SnapLine = snap
        end
    end

    local function PlayerESPUpdateAll()
        if not Variables.PlayerESPSettings.Enabled then
            for tracked in pairs(Variables.PlayerESPVisualsByPlayer) do
                PlayerESPDestroyForPlayer(tracked)
            end
            return
        end

        -- perf gate
        local nowTick = tick()
        if Variables.PlayerESPSettings.PerformanceMode then
            if (nowTick - Variables.PlayerESPLastUpdateTimestamp) < Variables.PlayerESPUpdateIntervalSeconds then
                return
            end
        end
        Variables.PlayerESPLastUpdateTimestamp = nowTick

        local camera = RbxService.Workspace.CurrentCamera
        local viewport = camera.ViewportSize
        local localPlayer = RbxService.Players.LocalPlayer
        local localRoot = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")

        for _, player in ipairs(RbxService.Players:GetPlayers()) do
            if player ~= localPlayer then
                PlayerESPUpdatePlayerData(player)

                local character = player.Character
                local rootPart = character and character:FindFirstChild("HumanoidRootPart")
                local humanoid = character and character:FindFirstChild("Humanoid")
                local headPart = character and character:FindFirstChild("Head")

                if character and rootPart and humanoid and humanoid.Health > 0 then
                    -- team filter
                    if Variables.PlayerESPSettings.TeamCheck and (player.Team == localPlayer.Team) and not Variables.PlayerESPSettings.ShowLocalTeam then
                        local visuals = Variables.PlayerESPVisualsByPlayer[player]
                        if visuals then
                            for key, visual in pairs(visuals) do
                                if key ~= "Highlight" and key ~= "Chams" and key ~= "Skeleton" then
                                    pcall(function() visual.Visible = false end)
                                elseif key == "Skeleton" then
                                    for _, data in pairs(visuals.Skeleton) do
                                        pcall(function() data.line.Visible = false end)
                                    end
                                end
                            end
                        end
                        continue
                    end

                    if not Variables.PlayerESPVisualsByPlayer[player] then
                        PlayerESPCreateForPlayer(player)
                    end

                    if not PlayerESPIsVisible(character) and not Variables.PlayerESPSettings.OutOfView then
                        local visuals = Variables.PlayerESPVisualsByPlayer[player]
                        if visuals then
                            for key, visual in pairs(visuals) do
                                if key ~= "Highlight" and key ~= "Chams" and key ~= "Skeleton" and key ~= "Arrow" then
                                    pcall(function() visual.Visible = false end)
                                elseif key == "Skeleton" then
                                    for _, data in pairs(visuals.Skeleton) do
                                        pcall(function() data.line.Visible = false end)
                                    end
                                end
                            end
                        end
                        continue
                    end

                    local screenPos, onScreen = camera:WorldToViewportPoint(rootPart.Position)
                    local distance = 0
                    if localRoot then distance = (localRoot.Position - rootPart.Position).Magnitude end
                    local fadeAlpha = PlayerESPGetDistanceFade(distance) * Variables.PlayerESPSettings.Transparency
                    local dynamicColor =
                        (Variables.PlayerESPSettings.RainbowMode and PlayerESPGetRainbowColor())
                        or (Variables.PlayerESPSettings.TeamColor and PlayerESPGetTeamColor(player))
                        or Variables.PlayerESPSettings.BoxColor

                    local boxWidth  = Variables.PlayerESPSettings.BoxWidth
                    local boxHeight = Variables.PlayerESPSettings.BoxHeight
                    local topLeft   = Vector2.new(screenPos.X - boxWidth/2, screenPos.Y - boxHeight/2)
                    local visuals   = Variables.PlayerESPVisualsByPlayer[player]

                    -- Filled box
                    if Variables.PlayerESPSettings.BoxFilled and visuals.BoxFill then
                        visuals.BoxFill.Position = topLeft
                        visuals.BoxFill.Size = Vector2.new(boxWidth, boxHeight)
                        visuals.BoxFill.Color = dynamicColor
                        visuals.BoxFill.Transparency = Variables.PlayerESPSettings.BoxFillTransparency
                        visuals.BoxFill.Visible = onScreen
                    end

                    -- Box outline
                    if Variables.PlayerESPSettings.Box and visuals.Box then
                        visuals.Box.Position = topLeft
                        visuals.Box.Size = Vector2.new(boxWidth, boxHeight)
                        visuals.Box.Color = dynamicColor
                        visuals.Box.Thickness = Variables.PlayerESPSettings.BoxThickness
                        visuals.Box.Transparency = fadeAlpha
                        visuals.Box.Visible = onScreen
                    end

                    -- Name
                    if Variables.PlayerESPSettings.Name and visuals.Name then
                        visuals.Name.Position = Vector2.new(screenPos.X, topLeft.Y - Variables.PlayerESPSettings.NameSize - 2)
                        visuals.Name.Color = (Variables.PlayerESPSettings.RainbowMode and PlayerESPGetRainbowColor()) or Variables.PlayerESPSettings.NameColor
                        visuals.Name.Size = Variables.PlayerESPSettings.NameSize
                        visuals.Name.Text = (Variables.PlayerESPSettings.DisplayName and player.DisplayName) or player.Name
                        visuals.Name.Transparency = fadeAlpha
                        visuals.Name.Visible = onScreen
                    end

                    -- below-box stack
                    local verticalOffset = 2

                    -- Health text
                    if Variables.PlayerESPSettings.Health and visuals.Health then
                        visuals.Health.Text = string.format("%d/%d HP", math.floor(humanoid.Health), math.floor(humanoid.MaxHealth))
                        visuals.Health.Position = Vector2.new(screenPos.X, topLeft.Y + boxHeight + verticalOffset)
                        visuals.Health.Color = Variables.PlayerESPSettings.HealthColor
                        visuals.Health.Size = Variables.PlayerESPSettings.HealthSize
                        visuals.Health.Transparency = fadeAlpha
                        visuals.Health.Visible = onScreen
                        verticalOffset = verticalOffset + Variables.PlayerESPSettings.HealthSize + 2
                    end

                    -- Health bar
                    if Variables.PlayerESPSettings.HealthBar and visuals.HealthBar and visuals.HealthBarBg then
                        local healthPercent = math.clamp(humanoid.Health / math.max(1, humanoid.MaxHealth), 0, 1)
                        if Variables.PlayerESPSettings.HealthBarStyle == "Vertical" then
                            local barX = topLeft.X - Variables.PlayerESPSettings.HealthBarWidth - 2
                            local barH = boxHeight * healthPercent
                            visuals.HealthBarBg.Position = Vector2.new(barX, topLeft.Y)
                            visuals.HealthBarBg.Size     = Vector2.new(Variables.PlayerESPSettings.HealthBarWidth, boxHeight)
                            visuals.HealthBarBg.Visible  = onScreen

                            visuals.HealthBar.Position   = Vector2.new(barX, topLeft.Y + (boxHeight - barH))
                            visuals.HealthBar.Size       = Vector2.new(Variables.PlayerESPSettings.HealthBarWidth, barH)
                        else
                            local full, filled = boxWidth, boxWidth * healthPercent
                            local barY = topLeft.Y + boxHeight + verticalOffset
                            visuals.HealthBarBg.Position = Vector2.new(topLeft.X, barY)
                            visuals.HealthBarBg.Size     = Vector2.new(full, Variables.PlayerESPSettings.HealthBarWidth)
                            visuals.HealthBarBg.Visible  = onScreen

                            visuals.HealthBar.Position   = visuals.HealthBarBg.Position
                            visuals.HealthBar.Size       = Vector2.new(filled, Variables.PlayerESPSettings.HealthBarWidth)
                            verticalOffset = verticalOffset + Variables.PlayerESPSettings.HealthBarWidth + 2
                        end

                        local hpColor
                        if healthPercent > 0.5 then
                            hpColor = Variables.PlayerESPSettings.HealthBarColorMid:lerp(Variables.PlayerESPSettings.HealthBarColorHigh, (healthPercent - 0.5) * 2)
                        else
                            hpColor = Variables.PlayerESPSettings.HealthBarColorLow:lerp(Variables.PlayerESPSettings.HealthBarColorMid, healthPercent * 2)
                        end
                        visuals.HealthBar.Color = hpColor
                        visuals.HealthBar.Transparency = fadeAlpha
                        visuals.HealthBar.Visible = onScreen
                    end

                    -- Armor bar (same behavior preserved)
                    if Variables.PlayerESPSettings.ArmorBar and visuals.ArmorBar and visuals.ArmorBarBg then
                        local baseMax = 100
                        local armorMax = math.max(0, math.floor(humanoid.MaxHealth - baseMax))
                        local armorCurrent = math.max(0, math.floor(humanoid.Health - baseMax))
                        local armorPercent = (armorMax > 0) and math.clamp(armorCurrent / armorMax, 0, 1) or 0

                        local armorX = topLeft.X - (Variables.PlayerESPSettings.HealthBarWidth + 2) - (Variables.PlayerESPSettings.ArmorBarWidth + 2)
                        visuals.ArmorBarBg.Position = Vector2.new(armorX, topLeft.Y)
                        visuals.ArmorBarBg.Size     = Vector2.new(Variables.PlayerESPSettings.ArmorBarWidth, boxHeight)
                        visuals.ArmorBarBg.Visible  = onScreen

                        visuals.ArmorBar.Position   = Vector2.new(armorX, topLeft.Y + (boxHeight - (boxHeight * armorPercent)))
                        visuals.ArmorBar.Size       = Vector2.new(Variables.PlayerESPSettings.ArmorBarWidth, boxHeight * armorPercent)
                        visuals.ArmorBar.Color      = Variables.PlayerESPSettings.ArmorBarColor
                        visuals.ArmorBar.Transparency = fadeAlpha
                        visuals.ArmorBar.Visible    = onScreen and armorCurrent > 0
                    end

                    -- Distance
                    if Variables.PlayerESPSettings.Stud and visuals.Stud then
                        visuals.Stud.Text = string.format("%.0f studs", distance)
                        visuals.Stud.Position = Vector2.new(screenPos.X, topLeft.Y + boxHeight + verticalOffset)
                        visuals.Stud.Color = Variables.PlayerESPSettings.StudColor
                        visuals.Stud.Size  = Variables.PlayerESPSettings.StudSize
                        visuals.Stud.Transparency = fadeAlpha
                        visuals.Stud.Visible = onScreen
                        verticalOffset = verticalOffset + Variables.PlayerESPSettings.StudSize + 2
                    end

                    -- Weapon
                    if Variables.PlayerESPSettings.Weapon and visuals.Weapon then
                        visuals.Weapon.Text = PlayerESPGetEquippedWeaponName(character)
                        visuals.Weapon.Position = Vector2.new(screenPos.X, topLeft.Y + boxHeight + verticalOffset)
                        visuals.Weapon.Color = Variables.PlayerESPSettings.WeaponColor
                        visuals.Weapon.Size  = Variables.PlayerESPSettings.WeaponSize
                        visuals.Weapon.Transparency = fadeAlpha
                        visuals.Weapon.Visible = onScreen
                        verticalOffset = verticalOffset + Variables.PlayerESPSettings.WeaponSize + 2
                    end

                    -- Flags
                    if Variables.PlayerESPSettings.Flags and visuals.Flags then
                        local flagsText = PlayerESPGetFlagsText(player, character)
                        if flagsText ~= "" then
                            visuals.Flags.Text = flagsText
                            visuals.Flags.Position = Vector2.new(screenPos.X, topLeft.Y + boxHeight + verticalOffset)
                            visuals.Flags.Color = Variables.PlayerESPSettings.FlagsColor
                            visuals.Flags.Size  = Variables.PlayerESPSettings.FlagsSize
                            visuals.Flags.Transparency = fadeAlpha
                            visuals.Flags.Visible = onScreen
                        else
                            visuals.Flags.Visible = false
                        end
                    end

                    -- Head dot
                    if Variables.PlayerESPSettings.HeadDot and visuals.HeadDot and headPart then
                        local headPos, headOn = camera:WorldToViewportPoint(headPart.Position)
                        if headOn then
                            visuals.HeadDot.Position = Vector2.new(headPos.X, headPos.Y)
                            visuals.HeadDot.Radius = Variables.PlayerESPSettings.HeadDotSize
                            visuals.HeadDot.Color =
                                (Variables.PlayerESPSettings.RainbowMode and PlayerESPGetRainbowColor()) or Variables.PlayerESPSettings.HeadDotColor
                            visuals.HeadDot.Transparency = fadeAlpha
                            visuals.HeadDot.Visible = true
                        else
                            visuals.HeadDot.Visible = false
                        end
                    end

                    -- Skeleton
                    if Variables.PlayerESPSettings.Skeleton and visuals.Skeleton then
                        for _, data in pairs(visuals.Skeleton) do
                            local a = character:FindFirstChild(data.bones[1])
                            local b = character:FindFirstChild(data.bones[2])
                            if a and b then
                                local pa, aon = camera:WorldToViewportPoint(a.Position)
                                local pb, bon = camera:WorldToViewportPoint(b.Position)
                                if aon and bon then
                                    data.line.From = Vector2.new(pa.X, pa.Y)
                                    data.line.To   = Vector2.new(pb.X, pb.Y)
                                    data.line.Color =
                                        (Variables.PlayerESPSettings.RainbowMode and PlayerESPGetRainbowColor()) or Variables.PlayerESPSettings.SkeletonColor
                                    data.line.Thickness = Variables.PlayerESPSettings.SkeletonThickness
                                    data.line.Transparency = fadeAlpha
                                    data.line.Visible = true
                                else
                                    data.line.Visible = false
                                end
                            else
                                data.line.Visible = false
                            end
                        end
                    end

                    -- Highlight / Chams
                    if Variables.PlayerESPSettings.Highlight and visuals.Highlight then
                        local c = (Variables.PlayerESPSettings.RainbowMode and PlayerESPGetRainbowColor()) or Variables.PlayerESPSettings.HighlightColor
                        visuals.Highlight.FillColor = c
                        visuals.Highlight.OutlineColor = c
                        visuals.Highlight.FillTransparency = Variables.PlayerESPSettings.HighlightTransparency
                    end
                    if Variables.PlayerESPSettings.Chams and (not Variables.PlayerESPSettings.Highlight) and visuals.Chams then
                        local c = (Variables.PlayerESPSettings.RainbowMode and PlayerESPGetRainbowColor()) or Variables.PlayerESPSettings.ChamsColor
                        visuals.Chams.FillColor = c
                        visuals.Chams.OutlineColor = c
                        visuals.Chams.FillTransparency = Variables.PlayerESPSettings.ChamsTransparency
                    end

                    -- Tracer
                    if Variables.PlayerESPSettings.Tracer and visuals.Tracer then
                        local fromVec =
                            (Variables.PlayerESPSettings.TracerFrom == "Bottom" and Vector2.new(viewport.X/2, viewport.Y))
                            or (Variables.PlayerESPSettings.TracerFrom == "Center" and Vector2.new(viewport.X/2, viewport.Y/2))
                            or Vector2.new(viewport.X/2, 0)
                        visuals.Tracer.From  = fromVec
                        visuals.Tracer.To    = Vector2.new(screenPos.X, topLeft.Y + boxHeight)
                        visuals.Tracer.Color =
                            (Variables.PlayerESPSettings.RainbowMode and PlayerESPGetRainbowColor()) or Variables.PlayerESPSettings.TracerColor
                        visuals.Tracer.Thickness = Variables.PlayerESPSettings.TracerThickness
                        visuals.Tracer.Transparency = fadeAlpha
                        visuals.Tracer.Visible = onScreen
                    end

                    -- Look tracer
                    if Variables.PlayerESPSettings.LookTracer and visuals.LookTracer and headPart then
                        local hp, hon = camera:WorldToViewportPoint(headPart.Position)
                        if hon then
                            local endPos, eon = camera:WorldToViewportPoint(headPart.Position + headPart.CFrame.LookVector * 50)
                            if eon then
                                visuals.LookTracer.From = Vector2.new(hp.X, hp.Y)
                                visuals.LookTracer.To   = Vector2.new(endPos.X, endPos.Y)
                                visuals.LookTracer.Color = Variables.PlayerESPSettings.LookTracerColor
                                visuals.LookTracer.Thickness = Variables.PlayerESPSettings.LookTracerThickness
                                visuals.LookTracer.Transparency = fadeAlpha
                                visuals.LookTracer.Visible = true
                            else
                                visuals.LookTracer.Visible = false
                            end
                        else
                            visuals.LookTracer.Visible = false
                        end
                    end

                    -- Off-screen arrow
                    if Variables.PlayerESPSettings.OutOfView and visuals.Arrow and not onScreen then
                        local center = Vector2.new(viewport.X/2, viewport.Y/2)
                        local dir = (Vector2.new(screenPos.X, screenPos.Y) - center).Unit
                        local angle = math.atan2(dir.Y, dir.X)
                        local edge = 50
                        local pos = center + dir * (math.min(viewport.X, viewport.Y)/2 - edge)
                        local size = Variables.PlayerESPSettings.OutOfViewSize
                        local p1 = pos + Vector2.new(math.cos(angle) * size, math.sin(angle) * size)
                        local p2 = pos + Vector2.new(math.cos(angle + 2.5) * size * 0.6, math.sin(angle + 2.5) * size * 0.6)
                        local p3 = pos + Vector2.new(math.cos(angle - 2.5) * size * 0.6, math.sin(angle - 2.5) * size * 0.6)
                        visuals.Arrow.PointA, visuals.Arrow.PointB, visuals.Arrow.PointC = p1, p2, p3
                        visuals.Arrow.Color =
                            (Variables.PlayerESPSettings.RainbowMode and PlayerESPGetRainbowColor()) or Variables.PlayerESPSettings.OutOfViewColor
                        visuals.Arrow.Transparency = fadeAlpha
                        visuals.Arrow.Visible = true
                    else
                        if visuals.Arrow then visuals.Arrow.Visible = false end
                    end

                    -- Optional snapline
                    if Variables.PlayerESPSettings.SnapLines and visuals.SnapLine then
                        visuals.SnapLine.From = Vector2.new(viewport.X/2, viewport.Y/2)
                        visuals.SnapLine.To   = Vector2.new(screenPos.X, screenPos.Y)
                        visuals.SnapLine.Color = dynamicColor
                        visuals.SnapLine.Thickness = 1
                        visuals.SnapLine.Transparency = fadeAlpha
                        visuals.SnapLine.Visible = onScreen
                    end
                else
                    PlayerESPDestroyForPlayer(player)
                end
            end
        end
    end

    -- Public module
    local PlayerESPModule = {}

    function PlayerESPModule.Start()
        if Variables.Maids.PlayerESP then
            Variables.Maids.PlayerESP:DoCleaning()
            Variables.Maids.PlayerESP = nil
        end
        Variables.Maids.PlayerESP = Maid.new()

        Variables.PlayerESPRunFlag = true
        Variables.PlayerESPSettings.Enabled = true
        Variables.PlayerESPUpdateIntervalSeconds = 1 / math.max(1, tonumber(Variables.PlayerESPSettings.UpdateRate) or 60)

        Variables.Maids.PlayerESP.RenderStepped =
            RbxService.RunService.RenderStepped:Connect(PlayerESPUpdateAll)

        -- roster tracking
        for _, p in ipairs(RbxService.Players:GetPlayers()) do
            if p ~= RbxService.Players.LocalPlayer then
                local perPlayerMaid = Variables.WeakMaids[p]
                perPlayerMaid:GiveTask(p.CharacterAdded:Connect(function()
                    task.wait(0.1)
                    if Variables.PlayerESPSettings.Enabled then
                        PlayerESPCreateForPlayer(p)
                    end
                end))
                perPlayerMaid:GiveTask(p.CharacterRemoving:Connect(function()
                    PlayerESPDestroyForPlayer(p)
                end))
                if p.Character then PlayerESPCreateForPlayer(p) end
            end
        end

        local addedConn   = RbxService.Players.PlayerAdded:Connect(function(p)
            if p ~= RbxService.Players.LocalPlayer then
                local perPlayerMaid = Variables.WeakMaids[p] -- alloc bucket early
                perPlayerMaid:GiveTask(p.CharacterAdded:Connect(function()
                    task.wait(0.1)
                    if Variables.PlayerESPSettings.Enabled then
                        PlayerESPCreateForPlayer(p)
                    end
                end))
                perPlayerMaid:GiveTask(p.CharacterRemoving:Connect(function()
                    PlayerESPDestroyForPlayer(p)
                end))
            end
        end)
        local removingConn = RbxService.Players.PlayerRemoving:Connect(PlayerESPDestroyForPlayer)
        Variables.Maids.PlayerESP:GiveTask(addedConn)
        Variables.Maids.PlayerESP:GiveTask(removingConn)
		PlayerESPModule.AttachStatsUpdater()  -- ensure stats labels tick once the module starts

        -- stop switch cleanup
        Variables.Maids.PlayerESP:GiveTask(function()
            Variables.PlayerESPRunFlag = false
            Variables.PlayerESPSettings.Enabled = false
            for tracked in pairs(Variables.PlayerESPVisualsByPlayer) do
                PlayerESPDestroyForPlayer(tracked)
            end
        end)

        Variables.PlayerESPModule = PlayerESPModule
    end

    function PlayerESPModule.Stop()
        Variables.PlayerESPRunFlag = false
        Variables.PlayerESPSettings.Enabled = false
        if Variables.Maids.PlayerESP then
            Variables.Maids.PlayerESP:DoCleaning()
            Variables.Maids.PlayerESP = nil
        end
        for tracked in pairs(Variables.PlayerESPVisualsByPlayer) do
            PlayerESPDestroyForPlayer(tracked)
        end
    end

    -- Rebuild visuals for all players (used when a “creates drawables” toggle flips)
    function PlayerESPModule.RefreshAll()
        for tracked in pairs(Variables.PlayerESPVisualsByPlayer) do
            PlayerESPDestroyForPlayer(tracked)
        end
        if Variables.PlayerESPSettings.Enabled then
            for _, p in ipairs(RbxService.Players:GetPlayers()) do
                if p ~= RbxService.Players.LocalPlayer and p.Character then
                    PlayerESPCreateForPlayer(p)
                end
            end
        end
    end

    -- Update the perf gate interval at runtime
    function PlayerESPModule.SetUpdateRate(hz)
        Variables.PlayerESPSettings.UpdateRate = tonumber(hz) or Variables.PlayerESPSettings.UpdateRate
        Variables.PlayerESPUpdateIntervalSeconds = 1 / math.max(1, tonumber(Variables.PlayerESPSettings.UpdateRate) or 60)
    end

	-- GOOD (attach to the actual module table that exists)
	function PlayerESPModule.RefreshAll()
	    for tracked in pairs(Variables.PlayerESPVisualsByPlayer) do
	        -- use the local destroy helper defined above
	        PlayerESPDestroyForPlayer(tracked)
	    end
	    if Variables.PlayerESPSettings.Enabled then
	        for _, p in ipairs(RbxService.Players:GetPlayers()) do
	            if p ~= RbxService.Players.LocalPlayer and p.Character then
	                PlayerESPCreateForPlayer(p)  -- use the local create helper
	            end
	        end
	    end
	end
	
	function PlayerESPModule.ClearAll()
	    for tracked in pairs(Variables.PlayerESPVisualsByPlayer) do
	        PlayerESPDestroyForPlayer(tracked)
	    end
	end
	
	function PlayerESPModule.AttachStatsUpdater()
	    if Variables.Maids.PlayerESPStats then return end
	    Variables.Maids.PlayerESPStats = Maid.new()  -- not Variables.MaidClass
	
	    local lastSecond = tick()
	    local frames = 0
	
	    local conn = RbxService.RunService.RenderStepped:Connect(function()
	        frames += 1
	        local now = tick()
	        if now - lastSecond >= 1 then
	            local fps = frames
	            frames = 0
	            lastSecond = now
	
	            local ui = Variables.PlayerESPUILabels
	            if ui and ui.FPS and ui.FPS.SetText then
	                ui.FPS:SetText("FPS: " .. tostring(fps))
	            end
	
	            local visible = 0
	            for _, visuals in pairs(Variables.PlayerESPVisualsByPlayer) do
	                if visuals and visuals.Box and visuals.Box.Visible then
	                    visible += 1
	                end
	            end
	            local total = math.max(0, #RbxService.Players:GetPlayers() - 1)
	            if ui and ui.PlayerCount and ui.PlayerCount.SetText then
	                ui.PlayerCount:SetText(("Players Visible: %d/%d"):format(visible, total))
	            end
	
	            if ui and ui.Status and ui.Status.SetText then
	                ui.Status:SetText(Variables.PlayerESPSettings.Enabled and "ESP Status: Active" or "ESP Status: Inactive")
	            end
	        end
	    end)
	
	    Variables.Maids.PlayerESPStats:GiveTask(conn)
	end

	if Variables.PlayerESPModule and Variables.PlayerESPModule.AttachStatsUpdater then
    	Variables.PlayerESPModule.AttachStatsUpdater()
	end

    Variables.PlayerESPModule = PlayerESPModule
end




-- Toggle Onchanged:

-- Master enable keeps the label in sync + start/stop module (no heavy logic here)
if Toggles and Toggles.ESPEnabled and Toggles.ESPEnabled.OnChanged then
    Toggles.ESPEnabled:OnChanged(function(enabled)
        Variables.PlayerESPSettings.Enabled = enabled
        local labels = Variables.PlayerESPUILabels
        if labels and labels.Status and labels.Status.SetText then
            labels.Status:SetText(enabled and "ESP Status: Active" or "ESP Status: Inactive")
        end
        if enabled then
            Variables.PlayerESPModule.Start()
        else
            Variables.PlayerESPModule.Stop()
        end
    end)
end

-- Keep your UpdateRate binding exactly as requested
if Options and Options.UpdateRate and Options.UpdateRate.OnChanged then
    Options.UpdateRate:OnChanged(function(value)
        Variables.PlayerESPSettings.UpdateRate = value
        Variables.PlayerESPUpdateIntervalSeconds = 1 / math.max(1, tonumber(value) or 60)
    end)
end

-- Feature toggles that CREATE/DESTROY drawables → rebuild visuals
local rebuildToggleIds = {
    "ESPBox","BoxFilled","ESPName","ESPHealth","ESPHealthBar","ArmorBar",
    "ESPStud","ESPSkeleton","ESPHighlight","ESPChams","ESPTracer","LookTracer",
    "OutOfView","ESPWeapon","ESPFlags","HeadDot"
}
for i = 1, #rebuildToggleIds do
    local uiId = rebuildToggleIds[i]
    local toggleObj = Toggles and Toggles[uiId]
    if toggleObj and toggleObj.OnChanged then
        toggleObj:OnChanged(function(value)
            Variables.PlayerESPSettings[
                uiId == "ESPBox" and "Box"
                or uiId == "ESPName" and "Name"
                or uiId == "ESPHealth" and "Health"
                or uiId == "ESPHealthBar" and "HealthBar"
                or uiId == "ESPStud" and "Stud"
                or uiId == "ESPSkeleton" and "Skeleton"
                or uiId == "ESPHighlight" and "Highlight"
                or uiId == "ESPChams" and "Chams"
                or uiId == "ESPTracer" and "Tracer"
                or uiId == "LookTracer" and "LookTracer"
                or uiId == "OutOfView" and "OutOfView"
                or uiId == "ESPWeapon" and "Weapon"
                or uiId == "ESPFlags" and "Flags"
                or uiId == "HeadDot" and "HeadDot"
                or uiId -- BoxFilled / ArmorBar map 1:1
            ] = value

            if Variables.PlayerESPSettings.Enabled then
                Variables.PlayerESPModule.RefreshAll()
            end
        end)
    end
end

-- Simple toggles (no rebuild needed)
local simpleToggles = {
    {"DisplayName","DisplayName"},
    {"RainbowMode","RainbowMode"},
    {"TeamColor","TeamColor"},
    {"TeamCheck","TeamCheck"},
    {"ShowOffscreen","ShowOffscreen"},
    {"UseDistanceFade","UseDistanceFade"},
    {"PerformanceMode","PerformanceMode"},
    {"ShowLocalTeam","ShowLocalTeam"},
}
for i = 1, #simpleToggles do
    local uiId, settingKey = simpleToggles[i][1], simpleToggles[i][2]
    local tObj = Toggles and Toggles[uiId]
    if tObj and tObj.OnChanged then
        tObj:OnChanged(function(value)
            Variables.PlayerESPSettings[settingKey] = value
        end)
    end
end

-- Value options (sliders/dropdowns)
local optionMap = {
    {"BoxWidth","BoxWidth"},
    {"BoxHeight","BoxHeight"},
    {"BoxThickness","BoxThickness"},
    {"NameSize","NameSize"},
    {"HealthSize","HealthSize"},
    {"HealthBarWidth","HealthBarWidth"},
    {"ArmorBarWidth","ArmorBarWidth"},
    {"StudSize","StudSize"},
    {"WeaponSize","WeaponSize"},
    {"FlagsSize","FlagsSize"},
    {"SkeletonThickness","SkeletonThickness"},
    {"TracerThickness","TracerThickness"},
    {"LookTracerThickness","LookTracerThickness"},
    {"HeadDotSize","HeadDotSize"},
    {"OutOfViewSize","OutOfViewSize"},
    {"ESPTransparency","Transparency"},
    {"BoxFillTransparency","BoxFillTransparency"},
    {"HighlightTransparency","HighlightTransparency"},
    {"ChamsTransparency","ChamsTransparency"},
    {"FadeStart","FadeStart"},
    {"MaxDistance","MaxDistance"},
    {"RainbowSpeed","RainbowSpeed"},
    {"TracerFrom","TracerFrom"},
    {"UpdateRate","UpdateRate"},
    {"HealthBarStyle","HealthBarStyle"},
}
for i = 1, #optionMap do
    local uiId, settingKey = optionMap[i][1], optionMap[i][2]
    local optObj = Options and Options[uiId]
    if optObj and optObj.OnChanged then
        optObj:OnChanged(function(value)
            Variables.PlayerESPSettings[settingKey] = value
            if uiId == "UpdateRate" then
                Variables.PlayerESPModule.SetUpdateRate(value)
            end
        end)
    end
end

-- Color pickers
local colorOptions = {
    {"BoxColor","BoxColor"},
    {"BoxFillColor","BoxFillColor"},
    {"NameColor","NameColor"},
    {"HealthColor","HealthColor"},
    {"HealthBarLow","HealthBarColorLow"},
    {"HealthBarMid","HealthBarColorMid"},
    {"HealthBarHigh","HealthBarColorHigh"},
    {"ArmorBarColor","ArmorBarColor"},
    {"StudColor","StudColor"},
    {"SkeletonColor","SkeletonColor"},
    {"HighlightColor","HighlightColor"},
    {"TracerColor","TracerColor"},
    {"LookTracerColor","LookTracerColor"},
    {"OutOfViewColor","OutOfViewColor"},
    {"WeaponColor","WeaponColor"},
    {"FlagsColor","FlagsColor"},
    {"HeadDotColor","HeadDotColor"},
    {"ChamsColor","ChamsColor"},
}
for i = 1, #colorOptions do
    local uiId, settingKey = colorOptions[i][1], colorOptions[i][2]
    local optObj = Options and Options[uiId]
    if optObj and optObj.OnChanged then
        optObj:OnChanged(function(colorValue)
            Variables.PlayerESPSettings[settingKey] = colorValue
        end)
    end
end
    
-- Standard Stop() for loader
local function Stop()
    -- flip off master toggle if present in UI
    pcall(function()
        if Toggles and Toggles.ESPEnabled and typeof(Toggles.ESPEnabled.SetValue) == "function" then
            Toggles.ESPEnabled:SetValue(false)
        end
    end)
    -- best-effort: halt run flags and clean maids
    Variables.PlayerESPSettings.Enabled = false
    pcall(function() if Variables.Maids.PlayerESP then Variables.Maids.PlayerESP:DoCleaning() end end)
    pcall(function() if Variables.Maids.PlayerESPStats then Variables.Maids.PlayerESPStats:DoCleaning() end end)
    -- per-player buckets
    if Variables.WeakMaids then
        for _, m in pairs(Variables.WeakMaids) do
            pcall(function() m:DoCleaning() end)
        end
    end
end

return { Name = "PlayerESP", Stop = Stop }
end end
