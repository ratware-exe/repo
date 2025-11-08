-- "modules/wfyb/build/angleprecision.lua"
do
	return function(UI)
		-- [1] LOAD DEPENDENCIES
		local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
		local GlobalEnv = (getgenv and getgenv()) or _G
		local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
		
		-- Get UI references
		local Library = UI.Library
		local Options = UI.Options
		local Toggles = UI.Toggles
		local Tabs = UI.Tabs
		
		-- [2] MODULE STATE
		local ModuleName = "AnglePrecision"
		local Variables = {
			Maids = { [ModuleName] = Maid.new() },
			AnglePrecisionModes = {
				{ name = "LOW",         deg = 45,    snap = 1,     center = 1.5   },
				{ name = "MEDIUM",      deg = 22.5,  snap = 0.5,   center = 1      },
				{ name = "HIGH",        deg = 11.25, snap = 0.1,   center = 0.1    },
				{ name = "EXTREME",     deg = 5.625, snap = 0.05,  center = 0.05   },
				{ name = "CANNON",      deg = 5,     snap = 0.01,  center = 0.01   },
				{ name = "DOUBLETORCH", deg = 1.25,   snap = 0.005, center = 0.005  },
				{ name = "SMALLEST",    deg = 1,   snap = 0.001, center = 0.001  },
			},  
			AnglePrecisionState = {
				ModuleEnabled = false,
				PatchInstalled = false,
				CustomGui = nil,
				BarFrame = nil,
				DegreeLabel = nil,
				PrecisionLabel = nil,
				ControlsRef = nil,
				TrackedHint = nil,
				GlobalConnections = {},
				PerRootConnections = setmetatable({}, { __mode = "k" }),
				PatchedControls = setmetatable({}, { __mode = "k" }),
				CurrentIndex = 1,
				PCSRef = nil,                    
				OriginalPCS = nil,                     
				OriginalModes = nil,                       
			},
			AnglePrecisionModule = nil,
		}

		-- [3] CORE LOGIC
		do
			local AnglePrecisionModule = {}
			local Players = RbxService.Players
			local ReplicatedStorage = RbxService.ReplicatedStorage
			local Workspace = RbxService.Workspace
			local RunService = RbxService.RunService
			local new = Instance.new
			local fromRGB = Color3.fromRGB
			local fromOffset = UDim2.fromOffset
			local fromScale = UDim2.fromScale
			local newVector2 = Vector2.new
			local newUDim = UDim.new
			local type = type
			local typeof = typeof or function(x) return type(x) end
			local pairs = pairs
			local ipairs = ipairs
			local pcall = pcall
			local tonumber = tonumber
			local tostring = tostring
			local rawget = rawget
			local setmetatable = setmetatable
			local debug_getmetatable = debug.getmetatable 
			local task_defer = task.defer
			local task_wait = task.wait 
			local math_pi = math.pi
			local math_abs = math.abs
			local math_round = math.round
			local UI_SCALE                      = 0.80
			local VERTICAL_OFFSET               = 0
			local BUTTON_BACKGROUND_COLOR       = fromRGB(233, 233, 233)
			local MAIN_BUTTON_BACKGROUND_COLOR  = fromRGB(255, 255, 255)
			local INFO_ICON_BACKGROUND_COLOR    = fromRGB(233, 233, 233)
			local IconAssets = {
				place       = "rbxassetid://90664956520730",
				rotateY     = "rbxassetid://105177593132322",
				rotateZ     = "rbxassetid://81045094074030",
				rotateX     = "rbxassetid://94044313401621",
				precision   = "rbxassetid://88318002113931",
				undo        = "rbxassetid://72713900223746",
				degreeInfo  = "rbxassetid://131351324982678",
				snapInfo    = "rbxassetid://138605241851651",
			}
			local NATIVE_ROOT_NAME = "ActionHint"
			local NATIVE_TARGET_NAMES = {
				ActionHintBarTemplate = true,
				ActionHintBar         = true,
				HintInputTemplate     = true,
				ActionHintTemplate    = true,
			}
			local function DegToRad(d) return (d or 0) * math_pi / 180 end
			local function SafeCall(fn)
				local ok, err = pcall(fn)
				if not ok then
				end
			end
			local function DisconnectAll(list)
				if not list then return end
				for i = 1, #list do
					local c = list[i]
					if c then pcall(function() c:Disconnect() end) end
				end
				table.clear(list)
			end
			local function RestorePatchedInstance(me)
			   if type(me) ~= "table" then return end
			   SafeCall(function()
				   me.__modeIndex = nil
				   me.__lastNativeState = nil
				   if Variables and Variables.AnglePrecisionState and Variables.AnglePrecisionState.OriginalPCS and type(Variables.AnglePrecisionState.OriginalPCS.handle) == "function" then
					   pcall(Variables.AnglePrecisionState.OriginalPCS.handle, me)
				   elseif type(me._handlePrecisionModeChange) == "function" then
					   me:_handlePrecisionModeChange()
				   end
			   end)
			end
			local function RestoreAllPatchedControls()
				if not Variables or not Variables.AnglePrecisionState or not Variables.AnglePrecisionState.PatchedControls then return end
				for inst in pairs(Variables.AnglePrecisionState.PatchedControls) do
					RestorePatchedInstance(inst)
					Variables.AnglePrecisionState.PatchedControls[inst] = nil
				end
			end
			local function UnpatchPlacementControlsClass()
				local st  = Variables.AnglePrecisionState
				local PCS = st.PCSRef
				local o   = st.OriginalPCS
				if not PCS or not o then return end
				SafeCall(function()
					if st.__hooked_handle then pcall(unhookfunction, o.handle) st.__hooked_handle = nil end
					if st.__hooked_getPrec then pcall(unhookfunction, o.getPrec) st.__hooked_getPrec = nil end
					if st.__hooked_setPSD then pcall(unhookfunction, PCS.SetPlacementStateData) st.__hooked_setPSD = nil end
					PCS.new = o.new
					PCS.__APPatched = nil
				end)
				st.PatchInstalled = false
			end
			local function CloneModes(list)
			   local out = {}
			   for i, m in ipairs(list) do
				   out[i] = { name = m.name, deg = m.deg, snap = m.snap, center = m.center }
			   end
			   return out
			end
			local function RestoreNativeBarVisibility(nativeBar)
			   if not (nativeBar and nativeBar.Parent) then return end
			   local function HasActiveHint(bar)
				   for _, d in ipairs(bar:GetDescendants()) do
					   if d:IsA("GuiObject") then
						   local n = d.Name
						   if (n == "ActionHintTemplate" or n == "HintInputTemplate" or n == "ActionHint")
							   and d.Visible and d.AbsoluteSize.X > 0 and d.AbsoluteSize.Y > 0 then
							   return true
						   end
					   end
				   end
				   return false
			   end
			   local want = HasActiveHint(nativeBar)
			   nativeBar.Visible = want
			   task_defer(function()
				   if nativeBar.Parent then nativeBar.Visible = want end
			   end)
			end
			local function GiveTask(task)
				if Variables and Variables.Maids and Variables.Maids[ModuleName] and Variables.Maids[ModuleName].GiveTask then
					 return Variables.Maids[ModuleName]:GiveTask(task)
				else
					return nil
				end
			end
			local function SetLabels(deg, snap)
			   if Variables and Variables.AnglePrecisionState then
				   if Variables.AnglePrecisionState.DegreeLabel then
					   Variables.AnglePrecisionState.DegreeLabel.Text = ("DEGREE: <font color='#55FF55'>%g°</font>"):format(deg or 0)
				   end
				   if Variables.AnglePrecisionState.PrecisionLabel then
					   Variables.AnglePrecisionState.PrecisionLabel.Text = ("PRECISION: <font color='#55FF55'>%s</font>"):format(tostring(snap or "?"))
				   end
			   end
			end
			local function CreateButtonWithBackground(name, iconId, onActivate)
			   local backgroundFrame = new("Frame")
			   backgroundFrame.Name = name .. "Background"
			   backgroundFrame.BackgroundColor3 = MAIN_BUTTON_BACKGROUND_COLOR
			   backgroundFrame.BackgroundTransparency = 0.4
			   backgroundFrame.Size = fromOffset(42 * UI_SCALE, 42 * UI_SCALE)
			   backgroundFrame.ZIndex = 102
			   new("UICorner", backgroundFrame).CornerRadius = newUDim(1, 0)
			   local btn = new("ImageButton")
			   btn.Name = name
			   btn.AutoButtonColor = false
			   btn.BackgroundTransparency = 1
			   btn.Size = fromOffset(30 * UI_SCALE, 30 * UI_SCALE)
			   btn.AnchorPoint = newVector2(0.5, 0.5)
			   btn.Position = fromScale(0.5, 0.5)
			   btn.Image = iconId
			   btn.ImageColor3 = fromRGB(220, 220, 220)
			   btn.ZIndex = backgroundFrame.ZIndex + 1
			   btn.Parent = backgroundFrame
			   if type(onActivate) == "function" then
				   GiveTask(btn.MouseButton1Click:Connect(function() SafeCall(onActivate) end))
			   end
			   return backgroundFrame
			end
			local function CreateKeybindLabel(parentButton, keyText, customSize)
			   local keyFrame = new("Frame")
			   keyFrame.Name = keyText .. "KeybindFrame"
			   keyFrame.BackgroundColor3 = fromRGB(255, 255, 255)
			   keyFrame.BackgroundTransparency = 0
			   keyFrame.Size = customSize or fromOffset(15 * UI_SCALE, 13 * UI_SCALE)
			   keyFrame.AnchorPoint = newVector2(1, 1)
			   keyFrame.Position = UDim2.new(1, 4 * UI_SCALE, 1, 4 * UI_SCALE)
			   keyFrame.ZIndex = parentButton.ZIndex + 2
			   keyFrame.Parent = parentButton
			   new("UICorner", keyFrame).CornerRadius = newUDim(0, 4 * UI_SCALE)
			   local stroke = new("UIStroke", keyFrame)
			   stroke.Color = fromRGB(150, 150, 150)
			   stroke.Thickness = 1 * UI_SCALE
			   local keyLabel = new("TextLabel")
			   keyLabel.Name = "KeyText"
			   keyLabel.Text = keyText
			   keyLabel.Font = Enum.Font.GothamSemibold
			   keyLabel.TextSize = 10 * UI_SCALE
			   keyLabel.TextColor3 = fromRGB(0, 0, 0)
			   keyLabel.BackgroundTransparency = 1
			   keyLabel.Size = UDim2.new(1, 0, 1, 0)
			   keyLabel.TextXAlignment = Enum.TextXAlignment.Center
			   keyLabel.TextYAlignment = Enum.TextYAlignment.Center
			   keyLabel.ZIndex = keyFrame.ZIndex + 1
			   keyLabel.Parent = keyFrame
			end
			local function WithControls(callback)
				local c = (Variables and Variables.AnglePrecisionState and Variables.AnglePrecisionState.ControlsRef) or _G.__PlacementControls
				local isTable = false
				local ok = pcall(function() isTable = type(c) == "table" end)
				if ok and isTable then SafeCall(function() callback(c) end) end
			end
			local function EnsureCustomGui()
			   if not Variables or not Variables.AnglePrecisionState then return nil end
			   if Variables.AnglePrecisionState.CustomGui then
				   return Variables.AnglePrecisionState.CustomGui
			   end
			   local AnglePrecisionScreenGui = new("ScreenGui")
			   AnglePrecisionScreenGui.Name = "CustomPlacementBar"
			   AnglePrecisionScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
			   AnglePrecisionScreenGui.ResetOnSpawn = false
			   AnglePrecisionScreenGui.DisplayOrder = 1000000
			   AnglePrecisionScreenGui.Enabled = false
			   AnglePrecisionScreenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
			   GiveTask(AnglePrecisionScreenGui)
			   local AnglePrecisionBarFrame = new("Frame")
			   AnglePrecisionBarFrame.Name = "Bar"
			   AnglePrecisionBarFrame.AnchorPoint = newVector2(0.5, 0)
			   AnglePrecisionBarFrame.Position = UDim2.new(0.5, 0, 0, 10 * UI_SCALE + VERTICAL_OFFSET)
			   AnglePrecisionBarFrame.Size = UDim2.new(0, 0, 0, 56 * UI_SCALE)
			   AnglePrecisionBarFrame.AutomaticSize = Enum.AutomaticSize.X
			   AnglePrecisionBarFrame.BackgroundColor3 = fromRGB(28, 28, 28)
			   AnglePrecisionBarFrame.BackgroundTransparency = 0.15
			   AnglePrecisionBarFrame.ZIndex = 100
			   AnglePrecisionBarFrame.Parent = AnglePrecisionScreenGui
			   new("UICorner", AnglePrecisionBarFrame).CornerRadius = newUDim(0, 16 * UI_SCALE)
			   local AnglePrecisionBarListLayout = new("UIListLayout")
			   AnglePrecisionBarListLayout.FillDirection = Enum.FillDirection.Horizontal
			   AnglePrecisionBarListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
			   AnglePrecisionBarListLayout.Padding = newUDim(0, 8 * UI_SCALE)
			   AnglePrecisionBarListLayout.Parent = AnglePrecisionBarFrame
			   local AnglePrecisionBarPadding = new("UIPadding")
			   AnglePrecisionBarPadding.PaddingLeft = newUDim(0, 8 * UI_SCALE)
			   AnglePrecisionBarPadding.PaddingRight = newUDim(0, 8 * UI_SCALE)
			   AnglePrecisionBarPadding.Parent = AnglePrecisionBarFrame
			   local containerWidth = 50 * UI_SCALE
			   local function CreateBarButton(name, icon, keyText, keySize, onClick)
					local container = new("Frame")
					container.Name = name .. "Container"
					container.BackgroundTransparency = 1
					container.Size = UDim2.new(0, containerWidth, 1, 0)
					container.Parent = AnglePrecisionBarFrame
					local button = CreateButtonWithBackground(name, icon, onClick)
					button.AnchorPoint = newVector2(0, 0.5)
					button.Position = fromScale(0, 0.5)
					button.Parent = container
					CreateKeybindLabel(button, keyText, keySize)
			   end
			   CreateBarButton("Place", IconAssets.place, "M1", fromOffset(20 * UI_SCALE, 13 * UI_SCALE), function()
				   WithControls(function(c) if c.RequestPlace then c.RequestPlace:Fire() end end)
			   end)
			   CreateBarButton("RotateY", IconAssets.rotateY, "R", nil, function()
				   WithControls(function(c) if c._rotateY then c:_rotateY() end end)
			   end)
			   CreateBarButton("RotateZ", IconAssets.rotateZ, "T", nil, function()
				   WithControls(function(c) if c._rotateZ then c:_rotateZ() end end)
			   end)
			   CreateBarButton("RotateX", IconAssets.rotateX, "Y", nil, function()
				   WithControls(function(c) if c._rotateX then c:_rotateX() end end)
			   end)
			   CreateBarButton("Precision", IconAssets.precision, "CTRL", fromOffset(28 * UI_SCALE, 13 * UI_SCALE), function()
				   WithControls(function(c)
					   if c._handlePrecisionModeChange then
							local currentState
							local ok = pcall(function() currentState = c._precisionModeState and c._precisionModeState.Value end)
							if ok and currentState ~= nil then
								local PCS = Variables.AnglePrecisionState.PCSRef
								local nextState
								if PCS and PCS.PrecisionModeState then
									if currentState == PCS.PrecisionModeState.LOW then nextState = PCS.PrecisionModeState.MEDIUM
									elseif currentState == PCS.PrecisionModeState.MEDIUM then nextState = PCS.PrecisionModeState.HIGH
									else nextState = PCS.PrecisionModeState.LOW end
								end
								if nextState ~= nil and c._precisionModeState then
									pcall(function() c._precisionModeState.Value = nextState end)
								end
							end
					   end
				   end)
			   end)
			   CreateBarButton("Undo", IconAssets.undo, "Z", nil, function()
				   WithControls(function(c)
					   for _, k in ipairs({ "_undoAction", "Undo", "_undo", "UndoAction" }) do
						   if type(c[k]) == "function" then pcall(c[k], c); break end
					   end
				   end)
			   end)
			   do
				   local AnglePrecisionInfoFrame = new("Frame")
				   AnglePrecisionInfoFrame.Name = "Info"
				   AnglePrecisionInfoFrame.BackgroundTransparency = 1
				   AnglePrecisionInfoFrame.Size = fromOffset(160 * UI_SCALE, 56 * UI_SCALE)
				   AnglePrecisionInfoFrame.ZIndex = 101
				   AnglePrecisionInfoFrame.Parent = AnglePrecisionBarFrame
				   local AnglePrecisionVerticalList = new("UIListLayout", AnglePrecisionInfoFrame)
				   AnglePrecisionVerticalList.FillDirection = Enum.FillDirection.Vertical
				   AnglePrecisionVerticalList.VerticalAlignment = Enum.VerticalAlignment.Center
				   AnglePrecisionVerticalList.Padding = newUDim(0, 2 * UI_SCALE)
				   new("UIPadding", AnglePrecisionInfoFrame).PaddingLeft = newUDim(0, 10 * UI_SCALE)
				   local function InfoRow(iconId, labelName, font, size, textColor)
					   local row = new("Frame")
					   row.Name = labelName .. "Row"
					   row.BackgroundTransparency = 1
					   row.Size = UDim2.new(1, 0, 0, ((labelName == "Degree") and 20 or 16) * UI_SCALE)
					   row.Parent = AnglePrecisionInfoFrame
					   local iconBackground = new("Frame")
					   iconBackground.Name = "IconBackground"
					   iconBackground.BackgroundColor3 = INFO_ICON_BACKGROUND_COLOR
					   iconBackground.Size = fromOffset(16 * UI_SCALE, 16 * UI_SCALE)
					   iconBackground.AnchorPoint = newVector2(0, 0.5)
					   iconBackground.Position = UDim2.new(0, 0, 0.5, 0)
					   iconBackground.ZIndex = 102
					   new("UICorner", iconBackground).CornerRadius = newUDim(1, 0)
					   iconBackground.Parent = row
					   local icon = new("ImageLabel")
					   icon.Name = "IconImage"
					   icon.BackgroundTransparency = 1
					   icon.Image = iconId
					   icon.Size = fromOffset(12 * UI_SCALE, 12 * UI_SCALE)
					   icon.AnchorPoint = newVector2(0.5, 0.5)
					   icon.Position = fromScale(0.5, 0.5)
					   icon.ImageColor3 = fromRGB(220, 220, 220)
					   icon.ZIndex = iconBackground.ZIndex + 1
					   icon.Parent = iconBackground
					   local textLabel = new("TextLabel")
					   textLabel.Name = labelName
					   textLabel.RichText = true
					   textLabel.BackgroundTransparency = 1
					   textLabel.Size = UDim2.new(1, -22 * UI_SCALE, 1, 0)
					   textLabel.Position = UDim2.new(0, 22 * UI_SCALE, 0, 0)
					   textLabel.TextXAlignment = Enum.TextXAlignment.Left
					   textLabel.Font = font
					   textLabel.TextSize = math_round(size * UI_SCALE)
					   textLabel.TextColor3 = textColor
					   textLabel.Text = labelName .. ": --"
					   textLabel.ZIndex = 102
					   textLabel.Parent = row
					   return textLabel
				   end
				   if Variables and Variables.AnglePrecisionState then
						Variables.AnglePrecisionState.DegreeLabel =
							InfoRow(IconAssets.degreeInfo, "Degree", Enum.Font.GothamSemibold, 16, fromRGB(230, 230, 230))
						Variables.AnglePrecisionState.PrecisionLabel =
							InfoRow(IconAssets.snapInfo, "Precision", Enum.Font.GothamSemibold, 16, fromRGB(230, 230, 230))
				   end
			   end
			   if Variables and Variables.AnglePrecisionState then
					Variables.AnglePrecisionState.CustomGui = AnglePrecisionScreenGui
					Variables.AnglePrecisionState.BarFrame = AnglePrecisionBarFrame
					local initialMode = Variables.AnglePrecisionModes and Variables.AnglePrecisionModes[((Variables.AnglePrecisionState.CurrentIndex - 1) % #Variables.AnglePrecisionModes) + 1]
					if initialMode then SetLabels(initialMode.deg, initialMode.snap) end
			   end
			   return AnglePrecisionScreenGui
			end
			local function InstallPlacementControlsPatch()
				if not Variables or not Variables.AnglePrecisionState then return end
				if Variables.AnglePrecisionState.PatchInstalled then return end
				local Nevermore_Success, Nevermore = pcall(function() return require(ReplicatedStorage:WaitForChild("Nevermore")) end)
				if not Nevermore_Success or not Nevermore then
					return
				end
				local PCS_Success, PCS = pcall(function() return Nevermore("PlacementControls") end)
				if not PCS_Success or not PCS then
					return
				end
				Variables.AnglePrecisionState.PatchInstalled = true
				Variables.AnglePrecisionState.PCSRef = PCS
				if not Variables.AnglePrecisionState.OriginalPCS then
					Variables.AnglePrecisionState.OriginalPCS = {
						new     = PCS.new,
						handle  = PCS._handlePrecisionModeChange,
						getPrec = PCS._getPrecisionFactor
					}
				end
				if PCS.__APPatched then return end
				PCS.__APPatched = true
				local originalNew = Variables.AnglePrecisionState.OriginalPCS.new
				local originalClassHandle = Variables.AnglePrecisionState.OriginalPCS.handle
				local originalGetPrec = Variables.AnglePrecisionState.OriginalPCS.getPrec
				if type(originalClassHandle) ~= "function" then
					Variables.AnglePrecisionState.PatchInstalled = false
					PCS.__APPatched = nil
					return
				end
				if type(originalGetPrec) ~= "function" then
					 Variables.AnglePrecisionState.PatchInstalled = false
					 PCS.__APPatched = nil
					 return
				end
				local function StateToIndex(st)
					local low = PCS.PrecisionModeState and PCS.PrecisionModeState.LOW or 0
					local idx = (st - low) + 1
					if idx < 1 then idx = 1 end
					 if Variables and Variables.AnglePrecisionModes and idx > #Variables.AnglePrecisionModes then idx = #Variables.AnglePrecisionModes end
					return idx
				end
				local function IndexToState(idx)
					local low = PCS.PrecisionModeState and PCS.PrecisionModeState.LOW or 0
					return (idx - 1) + low
				end
				local function ApplyMode(me)
					if not Variables or not Variables.AnglePrecisionModes or not me or not me.__modeIndex then return end
					local mode = Variables.AnglePrecisionModes[me.__modeIndex]
					if not mode then return end
					 SafeCall(function()
						 local surface = me._propPositioner and me._propPositioner:GetSurfaceCalculator()
						 if surface then
							 if surface.SetSnapAmount       then surface:SetSnapAmount(mode.snap) end
							 if surface.SetCenterSnapAmount then surface:SetCenterSnapAmount(mode.center or mode.snap) end
							 if surface.SetMoveSnap         then surface:SetMoveSnap(mode.snap) end
							 if surface.SetGrid             then surface:SetGrid(mode.snap) end
						 end
					 end)
					 SafeCall(function()
						 local deg  = mode.deg
						 local radv = DegToRad(deg)
						 for _, k in ipairs({"_rotationStepDegrees","rotationStepDegrees","RotationStepDegrees","_rotationStep","rotationStep"}) do
							 if rawget(me, k) ~= nil then me[k] = deg end
						 end
						 for _, k in ipairs({"_rotationStepRadians","rotationStepRadians"}) do
							 if rawget(me, k) ~= nil then me[k] = radv end
						 end
					 end)
					SetLabels(mode.deg, mode.snap)
				end
				local function EnsureIndex(me)
					 if not me or not Variables or not Variables.AnglePrecisionState then return end
					 if me.__modeIndex == nil then
						 me.__modeIndex = Variables.AnglePrecisionState.CurrentIndex
					 end
				end
				local old_handlePrecisionModeChange
				local hook_handle_success, hook_handle_err = pcall(function()
					if not hookfunction then RbxService.Players.LocalPlayer:Kick("Aborting! Hook Functions are NOT supported by this executor. Try another executor!") end
					old_handlePrecisionModeChange = hookfunction(originalClassHandle, function(me, ...)
						EnsureIndex(me)
						local st = me._precisionModeState and me._precisionModeState.Value
						if me.__ap_ignoreNext then
							me.__ap_ignoreNext = nil
							me.__lastNativeState = st
							local result = { pcall(old_handlePrecisionModeChange, me, ...) }
							if not result[1] then end
							ApplyMode(me)
							return unpack(result, 2)
						end
						local first = (me.__lastNativeState == nil)
						if not first and st ~= me.__lastNativeState then
							if Variables and Variables.AnglePrecisionModes and #Variables.AnglePrecisionModes > 0 then
								me.__modeIndex = ((me.__modeIndex or Variables.AnglePrecisionState.CurrentIndex or 1) % #Variables.AnglePrecisionModes) + 1
							else
								me.__modeIndex = 1
							end
							Variables.AnglePrecisionState.CurrentIndex = me.__modeIndex
						end
						me.__lastNativeState = st
						local result = {pcall(old_handlePrecisionModeChange, me, ...)}
						if not result[1] then end
						ApplyMode(me)
						return unpack(result, 2)
					end)
				end)
				if not hook_handle_success then
					 Variables.AnglePrecisionState.PatchInstalled = false
					 PCS.__APPatched = nil
					 return
				end
				Variables.AnglePrecisionState.__hooked_handle = true
				GiveTask(function() if hook_handle_success and unhookfunction then pcall(unhookfunction, originalClassHandle) Variables.AnglePrecisionState.__hooked_handle = nil end end)
				local old_getPrecisionFactor
				local hook_getPrec_success, hook_getPrec_err = pcall(function()
					if not hookfunction then RbxService.Players.LocalPlayer:Kick("Aborting! Hook Functions are NOT supported by this executor. Try another executor!") end
					old_getPrecisionFactor = hookfunction(originalGetPrec, function(me)
						 EnsureIndex(me)
						 local ourResult = 0
						 if Variables and Variables.AnglePrecisionModes and me.__modeIndex and Variables.AnglePrecisionModes[me.__modeIndex] then
							ourResult = DegToRad(Variables.AnglePrecisionModes[me.__modeIndex].deg)
						 end
						 return ourResult
					end)
				end)
				if not hook_getPrec_success then
					if hook_handle_success and unhookfunction then pcall(unhookfunction, originalClassHandle) Variables.AnglePrecisionState.__hooked_handle = nil end
					Variables.AnglePrecisionState.PatchInstalled = false
					PCS.__APPatched = nil
					return
				end
				Variables.AnglePrecisionState.__hooked_getPrec = true
				GiveTask(function() if hook_getPrec_success and unhookfunction then pcall(unhookfunction, originalGetPrec) Variables.AnglePrecisionState.__hooked_getPrec = nil end end)
				local function PatchInstance(self)
					if not self or type(self) ~= "table" then return end
					local isPCSInstance = false
					local ok = pcall(function() isPCSInstance = self._precisionModeState and self._precisionModeState:IsA("IntValue") end)
					if not ok or not isPCSInstance then return end
					if self.__APPInstancePatched then return end
					self.__APPInstancePatched = true
					_G.__PlacementControls = self
					if Variables and Variables.AnglePrecisionState then Variables.AnglePrecisionState.ControlsRef = self end
					if Variables and Variables.AnglePrecisionState then Variables.AnglePrecisionState.PatchedControls[self] = true end
					task_defer(function()
						local stillExists = false
						pcall(function() stillExists = self._precisionModeState and self._precisionModeState.Parent end)
						if not stillExists then return end
						EnsureIndex(self)
						SafeCall(function()
							self.__ap_ignoreNext = true
							self._precisionModeState.Value = IndexToState(self.__modeIndex)
							ApplyMode(self)
						end)
					end)
					if self._maid and self._maid.GiveTask then
						self._maid:GiveTask(function()
							if _G.__PlacementControls == self then _G.__PlacementControls = nil end
							if Variables and Variables.AnglePrecisionState and Variables.AnglePrecisionState.ControlsRef == self then Variables.AnglePrecisionState.ControlsRef = nil end
							if Variables and Variables.AnglePrecisionState and Variables.AnglePrecisionState.PatchedControls then
								Variables.AnglePrecisionState.PatchedControls[self] = nil
							end
						end)
					end
				end
				_G.__AP_PatchPlacementControlsInstance = PatchInstance
				PCS.new = function(...)
					local self = originalNew(...)
					 if Variables and Variables.AnglePrecisionState and Variables.AnglePrecisionState.ModuleEnabled then
						PatchInstance(self)
					end
					return self
				end
				local old_setPlacementStateData
				local hook_setPSD_success, hook_setPSD_err = pcall(function()
					if not hookfunction then RbxService.Players.LocalPlayer:Kick("Aborting! Hook Functions are NOT supported by this executor. Try another executor!") end
					if PCS.SetPlacementStateData then 
						old_setPlacementStateData = hookfunction(PCS.SetPlacementStateData, function(me, data, ...)
							if me then me.__ap_ignoreNext = true end
							return old_setPlacementStateData(me, data, ...)
						end)
					else
						 hook_setPSD_success = false 
					end
				end)
				if not hook_setPSD_success then
					RbxService.Players.LocalPlayer:Kick("Aborting! Hook Functions are NOT supported by this executor. Try another executor!")
				else
					Variables.AnglePrecisionState.__hooked_setPSD = true
					GiveTask(function()
						if unhookfunction and old_setPlacementStateData then
							pcall(unhookfunction, PCS.SetPlacementStateData)
							Variables.AnglePrecisionState.__hooked_setPSD = nil
						end
					end)
				end
				task_defer(function()
					local getgc_func = (getgenv or function() return _G end)()["getgc"]
					local ok, gc = pcall(function() return getgc_func(true) end)
					if not ok or type(gc) ~= "table" then RbxService.Players.LocalPlayer:Kick('Aborting! "getgc" is NOT supported by this executor. Try another executor!') return end
					local PCSPointer = nil 
					local function LooksLikePCS_Robust(t)
						if not PCSPointer then
							local ok, mt = pcall(debug_getmetatable, PCS)
							if ok and type(mt) == "table" then
								PCSPointer = mt
							else
								if type(t) ~= "table" then return false end
								local hasState, stateOK = pcall(function() return rawget(t, "_precisionModeState") and rawget(t, "_precisionModeState"):IsA("IntValue") end)
								local hasHandler, handlerOK = pcall(function() return type(rawget(t, "_handlePrecisionModeChange")) == "function" end)
								return stateOK and handlerOK and hasState and hasHandler
							end
						end
						local success, objectMetatable = pcall(debug_getmetatable, t)
						return success and objectMetatable == PCSPointer
					end
					local foundCount = 0
					for i, obj in ipairs(gc) do
						if i % 50000 == 0 then task_wait() end
						local looksLike, looksLikeOK = pcall(LooksLikePCS_Robust, obj)
						if looksLikeOK and looksLike then
							foundCount = foundCount + 1
							PatchInstance(obj) 
						end
					end
				end)
			end
			GiveTask(function()
				RestoreAllPatchedControls()
				UnpatchPlacementControlsClass()
			end)
			local function IsTargetedNative(inst)
				local isGuiObject = false
				local ok = pcall(function() isGuiObject = inst and inst:IsA("GuiObject") end)
				if not ok or not isGuiObject then return false end
				if not NATIVE_TARGET_NAMES[inst.Name] then return false end
				local p = inst.Parent
				while p do
					 local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
					 if p == playerGui then return false end
					 local isScreenGui = false
					 local ok2 = pcall(function() isScreenGui = p:IsA("ScreenGui") end)
					 if ok2 and isScreenGui and p.Name == NATIVE_ROOT_NAME then return true end
					 p = p.Parent
				end
				return false
			end
			local function TopCenterScore(guiObj)
			   local cam = Workspace.CurrentCamera
			   local vp = cam and cam.ViewportSize or newVector2(1280,720)
			   local midX = vp.X * 0.5
			   local pos, size = guiObj.AbsolutePosition, guiObj.AbsoluteSize
			   local centerX = pos.X + size.X * 0.5
			   local dx = math_abs(centerX - midX)
			   local y  = pos.Y
			   return y * 3 + dx
			end
			local function PickTopCenterBar(root)
			   local best, bestScore = nil, math.huge
			   for _, d in ipairs(root:GetDescendants()) do
				   if IsTargetedNative(d) and (d.Name == "ActionHintBar" or d.Name == "ActionHintBarTemplate") then
					   local cam = Workspace.CurrentCamera
					   if d.AbsolutePosition.Y <= (cam and cam.ViewportSize.Y or 720)/2 then
						   local s = TopCenterScore(d)
						   if s < bestScore then best, bestScore = d, s end
					   end
				   end
			   end
			   return best
			end
			local function LockBarToNative(nativeBar)
			   if not (Variables and Variables.AnglePrecisionState and Variables.AnglePrecisionState.BarFrame and nativeBar) then return end
			   local pos  = nativeBar.AbsolutePosition
			   local size = nativeBar.AbsoluteSize
			   local centerX = pos.X + size.X*0.5
			   Variables.AnglePrecisionState.BarFrame.AnchorPoint = newVector2(0.5, 0)
			   Variables.AnglePrecisionState.BarFrame.Position = fromOffset(centerX, pos.Y + VERTICAL_OFFSET)
			end
			local FeatureConns = {}
			local function BeginTracking(nativeBar)
				if not Variables or not Variables.AnglePrecisionState then return end
				if Variables.AnglePrecisionState.TrackedHint == nativeBar then return end
				DisconnectAll(FeatureConns)
				Variables.AnglePrecisionState.TrackedHint = nativeBar
				if not _G.__PlacementControls then
					local getgc_func = (getgenv or function() return _G end)()["getgc"]
					local ok, gc = pcall(function() return getgc_func(true) end)
					if ok and type(gc) == "table" then
						local function LooksLikePCS_Robust_Tracking(t)
							 if type(t) ~= "table" then return false end
							 local hasState, stateOK = pcall(function() return rawget(t, "_precisionModeState") and rawget(t, "_precisionModeState"):IsA("IntValue") end)
							 local hasHandler, handlerOK = pcall(function() return type(rawget(t, "_handlePrecisionModeChange")) == "function" end)
							 if not (stateOK and handlerOK and hasState and hasHandler) then return false end
							 local g = rawget(t, "_actionHintGroup")
							 local guiLinkOK, guiLinkSuccess = pcall(function()
								 if type(g) == "table" then
									 local gui = rawget(g, "Gui")
									 if gui and gui:IsA("GuiObject") then
										 return nativeBar:IsDescendantOf(gui) or gui:IsAncestorOf(nativeBar)
									 end
								 end
								 return false
							 end)
							 return guiLinkSuccess and guiLinkOK
						end
						for i, obj in ipairs(gc) do
							 if i % 50000 == 0 then task_wait() end
							 local looksLike, looksLikeOK = pcall(LooksLikePCS_Robust_Tracking, obj)
							 if looksLikeOK and looksLike then
								if not obj.__APPInstancePatched and _G.__AP_PatchPlacementControlsInstance then
									pcall(_G.__AP_PatchPlacementControlsInstance, obj)
								end
								_G.__PlacementControls = obj
								Variables.AnglePrecisionState.ControlsRef = obj
								break
							end
						end
					end
				end
				local p = nativeBar.Parent
				while p do
					 local isScreenGui = false
					 local ok = pcall(function() isScreenGui = p:IsA("ScreenGui") end)
					 if ok and isScreenGui then break end
					 p = p.Parent
				end
				if p and Variables.AnglePrecisionState.CustomGui then
					 Variables.AnglePrecisionState.CustomGui.IgnoreGuiInset = p.IgnoreGuiInset
				end
				LockBarToNative(nativeBar)
				local function HasActiveHint()
				   if not nativeBar or not nativeBar.Parent then return false end
				   for _, d in ipairs(nativeBar:GetDescendants()) do
					   if d:IsA("GuiObject") then
						   local n = d.Name
						   if (n == "ActionHintTemplate" or n == "HintInputTemplate" or n == "ActionHint") and d.Visible and d.AbsoluteSize.X > 0 and d.AbsoluteSize.Y > 0 then
							   return true
						   end
					   end
				   end
				   return false
				end
				local function SyncVisibility()
					if not (Variables and Variables.AnglePrecisionState and nativeBar and nativeBar.Parent) then return end
					local want = nativeBar.Visible or HasActiveHint()
					if Variables.AnglePrecisionState.CustomGui and Variables.AnglePrecisionState.CustomGui.Enabled ~= want then
						Variables.AnglePrecisionState.CustomGui.Enabled = want
					end
					if nativeBar.Visible then nativeBar.Visible = false end
				end
				SyncVisibility() 
				table.insert(FeatureConns, nativeBar:GetPropertyChangedSignal("AbsolutePosition"):Connect(function() LockBarToNative(nativeBar) end))
				table.insert(FeatureConns, nativeBar:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() LockBarToNative(nativeBar) end))
				table.insert(FeatureConns, nativeBar:GetPropertyChangedSignal("Visible"):Connect(SyncVisibility))
				table.insert(FeatureConns, nativeBar.AncestryChanged:Connect(function(_, parent)
					if not parent then
						if Variables.AnglePrecisionState.CustomGui then Variables.AnglePrecisionState.CustomGui.Enabled = false end
						Variables.AnglePrecisionState.TrackedHint = nil
						DisconnectAll(FeatureConns)
						Variables.AnglePrecisionState.ControlsRef = nil
					end
				end))
				for _, c in ipairs(FeatureConns) do GiveTask(c) end
			end
			local function AttachToRoot(root)
			   if not Variables or not Variables.AnglePrecisionState then return end
			   local isScreenGui = false
			   local ok = pcall(function() isScreenGui = root and root:IsA("ScreenGui") end)
			   if not ok or not isScreenGui or root.Name ~= NATIVE_ROOT_NAME then return end
			   local bucket = {}
			   Variables.AnglePrecisionState.PerRootConnections[root] = bucket
			   local function AddConn(conn)
				   table.insert(bucket, conn)
				   GiveTask(conn)
			   end
			   local function Rescan()
				   local candidate = PickTopCenterBar(root)
				   if candidate then BeginTracking(candidate) end
			   end
			   Rescan()
			   AddConn(root.DescendantAdded:Connect(function(inst)
				   if IsTargetedNative(inst) then Rescan() end
			   end))
			   AddConn(root.AncestryChanged:Connect(function(_, parent)
				   if not parent then
					   DisconnectAll(bucket)
					   if Variables.AnglePrecisionState then Variables.AnglePrecisionState.PerRootConnections[root] = nil end
					   if Variables.AnglePrecisionState and Variables.AnglePrecisionState.TrackedHint and Variables.AnglePrecisionState.TrackedHint:IsDescendantOf(root) then
						   if Variables.AnglePrecisionState.CustomGui then Variables.AnglePrecisionState.CustomGui.Enabled = false end
						   Variables.AnglePrecisionState.TrackedHint = nil
						   DisconnectAll(FeatureConns)
						   Variables.AnglePrecisionState.ControlsRef = nil
					   end
				   end
			   end))
			end
			local function StartGlobalWatcher()
			   if not Variables or not Variables.AnglePrecisionState then return end
			   if Variables.AnglePrecisionState.GlobalConnections.__started then return end
			   Variables.AnglePrecisionState.GlobalConnections.__started = true
			   local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
			   for _, child in ipairs(playerGui:GetChildren()) do
					local isScreenGui = false
					local ok = pcall(function() isScreenGui = child and child:IsA("ScreenGui") end)
				   if ok and isScreenGui and child.Name == NATIVE_ROOT_NAME then
					   AttachToRoot(child)
				   end
			   end
			   table.insert(Variables.AnglePrecisionState.GlobalConnections,
				   playerGui.ChildAdded:Connect(function(child)
						local isScreenGui = false
						local ok = pcall(function() isScreenGui = child and child:IsA("ScreenGui") end)
					   if ok and isScreenGui and child.Name == NATIVE_ROOT_NAME then
						   AttachToRoot(child)
					   end
				   end)
			   )
			   for _, c in ipairs(Variables.AnglePrecisionState.GlobalConnections) do
				   if type(c) ~= "boolean" then GiveTask(c) end
			   end
			end
			local function ValidateModeTable(t)
			   if type(t) ~= "table" then return false, "Input must be a Lua table." end
			   if type(t.name) ~= "string" or t.name == "" then return false, "Field 'name' must be a non-empty string." end
			   local deg  = tonumber(t.deg)
			   local snap = tonumber(t.snap)
			   local center = t.center ~= nil and tonumber(t.center) or snap
			   if not deg or deg <= 0 then return false, "Field 'deg' must be > 0." end
			   if not snap or snap <= 0 then return false, "Field 'snap' must be > 0." end
			   if not center or center <= 0 then return false, "Field 'center' must be > 0 (or omit to use snap)." end
			   return true, { name = t.name, deg = deg, snap = snap, center = center }
			end
			local function ParseCustomModeText(text)
				text = tostring(text or "")
				local mode = {}
				for key, value in text:gmatch("([%w_]+)%s*=%s*[\"']?([%w_%.%-]+)[\"']?") do
					if key == "name" then
						mode.name = value 
					else
						mode[key] = tonumber(value)
					end
				end
				return ValidateModeTable(mode)
			end
			function AnglePrecisionModule.AddCustomModeFromText(text)
			   local ok, modeOrMsg = ParseCustomModeText(text)
			   if not ok then
				   pcall(function()
						if Library and Library.Notify then Library:Notify("Angle Precision | " .. modeOrMsg, 5)
						else end
				   end)
				   return false, modeOrMsg
			   end
			   if Variables and Variables.AnglePrecisionModes then table.insert(Variables.AnglePrecisionModes, modeOrMsg) end
			   WithControls(function(c)
				   if Variables and Variables.AnglePrecisionModes then c.__modeIndex = #Variables.AnglePrecisionModes end
				   SafeCall(function() c:_handlePrecisionModeChange() end)
			   end)
			   pcall(function()
				   if Library and Library.Notify then Library:Notify("Angle Precision | Added Mode: " .. modeOrMsg.name, 3) end
			   end)
			   return true
			end
			local function WireCustomUI()
				local function assignButtonCallback(obj)
					if not obj then return end
					local func = function()
						local text = (Options and Options.CustomAnglePrecisionInput and Options.CustomAnglePrecisionInput.Value) or ""
						AnglePrecisionModule.AddCustomModeFromText(text)
					end
					if type(obj.SetCallback) == "function" then obj:SetCallback(func) return end
					obj.Func = func
				end
				SafeCall(function() if Options.CustomAnglePrecisionButton then assignButtonCallback(Options.CustomAnglePrecisionButton) end end)
				local function assignResetCallback(obj)
					 if not obj then return end
					 local func = function() AnglePrecisionModule.ResetCustomAnglePrecision() end
					 if type(obj.SetCallback) == "function" then obj:SetCallback(func) return end
					 obj.Func = func
				end
				SafeCall(function() if Options.ResetCustomAnglePrecisionButton then assignResetCallback(Options.ResetCustomAnglePrecisionButton) end end)
			end
			function AnglePrecisionModule.Start()
			   if not Variables or not Variables.AnglePrecisionState then return end
			   Variables.AnglePrecisionState.OriginalModes = Variables.AnglePrecisionState.OriginalModes or CloneModes(Variables.AnglePrecisionModes)
			   if Variables.AnglePrecisionState.ModuleEnabled then return end
			   Variables.AnglePrecisionState.ModuleEnabled = true
			   EnsureCustomGui()
			   InstallPlacementControlsPatch()
			   StartGlobalWatcher()
			   WireCustomUI()
			end
			function AnglePrecisionModule.Stop()
			   if not Variables or not Variables.AnglePrecisionState then return end
			   if not Variables.AnglePrecisionState.ModuleEnabled then return end
			   Variables.AnglePrecisionState.ModuleEnabled = false
			   pcall(function() if Variables.AnglePrecisionState.CustomGui then Variables.AnglePrecisionState.CustomGui.Enabled = false end end)
			   pcall(function() if Variables.Maids and Variables.Maids[ModuleName] then Variables.Maids[ModuleName]:DoCleaning() end end)
			   pcall(function() RestoreNativeBarVisibility(Variables.AnglePrecisionState.TrackedHint) end)
			   RestoreAllPatchedControls()
			   UnpatchPlacementControlsClass()
			   if Variables.AnglePrecisionState.OriginalModes then
					if Variables.AnglePrecisionModes then Variables.AnglePrecisionModes = CloneModes(Variables.AnglePrecisionState.OriginalModes) end
			   end
			   _G.__AP_PatchPlacementControlsInstance = nil
			   _G.__PlacementControls = nil
				if Variables.AnglePrecisionState.PatchedControls then Variables.AnglePrecisionState.PatchedControls = setmetatable({}, { __mode = "k" }) end
			   Variables.AnglePrecisionState.CustomGui = nil
			   Variables.AnglePrecisionState.BarFrame = nil
			   Variables.AnglePrecisionState.DegreeLabel = nil
			   Variables.AnglePrecisionState.PrecisionLabel = nil
			   Variables.AnglePrecisionState.ControlsRef = nil
			   Variables.AnglePrecisionState.TrackedHint = nil
			   if Variables.AnglePrecisionState.GlobalConnections then Variables.AnglePrecisionState.GlobalConnections = {} end
			   if Variables.AnglePrecisionState.PerRootConnections then Variables.AnglePrecisionState.PerRootConnections = setmetatable({}, { __mode = "k" }) end
			end
			function AnglePrecisionModule.ResetCustomAnglePrecision()
			   if not Variables or not Variables.AnglePrecisionState or not Variables.AnglePrecisionModes then return end
			   if Variables.AnglePrecisionState.OriginalModes then
				   Variables.AnglePrecisionModes = CloneModes(Variables.AnglePrecisionState.OriginalModes)
			   else
				   Variables.AnglePrecisionState.OriginalModes = CloneModes(Variables.AnglePrecisionModes)
			   end
			   WithControls(function(c)
				   c.__modeIndex = 1
				   SafeCall(function() c:_handlePrecisionModeChange() end)
			   end)
			   pcall(function()
				   if Library and Library.Notify then Library:Notify("Angle Precision | Reset To Default.", 3) end
			   end)
			end

			if Variables then Variables.AnglePrecisionModule = AnglePrecisionModule end
		end

		-- [4] UI CREATION
		local AnglePrecisionGroupbox = Tabs["Build"]:AddLeftGroupbox("Angle Precision", "drafting-compass")
		local AnglePrecisionToggle = AnglePrecisionGroupbox:AddToggle("AnglePrecisionToggle", {
			Text = "Enabled",
			Tooltip = "Turn Feature [ON/OFF].", 
			DisabledTooltip = "Feature Disabled!", 
			Default = false, 
			Disabled = false, 
			Visible = true, 
			Risky = false, 
		})
		AnglePrecisionGroupbox:AddInput("CustomAnglePrecisionInput", {
			Numeric = false, 
			Finished = false, 
			ClearTextOnFocus = false, 
			Text = "Add Custom Values:",
			Tooltip = "Input custom angle & interval in the following format: { name = 'example', deg = 0.000, snap = 0.000, center = 0.000 }", 
			Default = '{ name = "example", deg = 0.000, snap = 0.000, center = 0.000 }',
			Placeholder = '{ name = "example", deg = 0.000, snap = 0.000, center = 0.000 }',
		})
		-- We must get the button references from Options to wire them
		local CustomAnglePrecisionButton = AnglePrecisionGroupbox:AddButton({
			Text = "Enter Input",
			Func = function() end, -- Will be wired by AnglePrecisionModule.Start()
			DoubleClick = true,
			Tooltip = "Double to input custom angle & precision interval.",
			DisabledTooltip = "Feature Disabled", 
			Disabled = false,
		})
		local ResetCustomAnglePrecisionButton = AnglePrecisionGroupbox:AddButton({
			Text = "Reset",
			Func = function() end, -- Will be wired by AnglePrecisionModule.Start()
			DoubleClick = true,
			Tooltip = "Double to reset custom angle & precision interval.",
			DisabledTooltip = "Feature Disabled", 
			Disabled = false,
		})
		-- Now that the buttons are created, assign them to Options for the logic to find
		Options.CustomAnglePrecisionButton = CustomAnglePrecisionButton
		Options.ResetCustomAnglePrecisionButton = ResetCustomAnglePrecisionButton

		-- [5] UI WIRING
		AnglePrecisionToggle:OnChanged(function(enabledState)
			if enabledState then
				Variables.AnglePrecisionModule.Start()
			else
				Variables.AnglePrecisionModule.Stop()
			end
		end)
		
		-- Apply current state on load
		if AnglePrecisionToggle.Value then
			Variables.AnglePrecisionModule.Start()
		end

		-- [6] RETURN MODULE
		local function Stop()
			if Variables.AnglePrecisionModule and Variables.AnglePrecisionModule.Stop then
				Variables.AnglePrecisionModule.Stop()
			end
			Variables.Maids[ModuleName]:DoCleaning()
		end
		
		return { Name = ModuleName, Stop = Stop }
	end
end
