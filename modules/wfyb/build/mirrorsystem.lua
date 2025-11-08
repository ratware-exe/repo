-- "modules/wfyb/build/mirrorsystem.lua",
do
	return function(UI)
		-- [1] LOAD DEPENDENCIES
		local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
		local GlobalEnv = (getgenv and getgenv()) or _G
		local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

		-- [2] MODULE STATE
		local ModuleName = "MirrorSystem"
		local ModuleVariables = {
			Maids = { [ModuleName] = Maid.new() },
			
			-- All MirrorSystem state moved from global scope to here
			MirrorSystemNudgeAwayFromPlane = 0.001, 
			MirrorSystemMirrorAxisUITemplate = nil, 
			MirrorSystemCanvasForceFixedSize = true,
			MirrorSystemSnapCanvasToWholeCells = true,
			MirrorSystemMinPixelsPerCell = 4,
			MirrorSystemGridPixelsPerStud = 32,
			MirrorSystemGridHysteresisPercent = 0.06,
			MirrorSystemMirrorAxisUITemplate = nil,    
			MirrorSystemDoNotMirrorIfAxisAbsLessEqual = 0.05,   
			MirrorSystemNudgeAwayFromPlane = 0.001,  
			MirrorSystemWorldDedupeQuantizeStuds = 0.02,  
			MirrorSystemYUiRotationDegrees = 90,    
			MirrorSystemIncludeCompoundOnTransformsAndActions = true,  
			MirrorSystemDedupeWindowSeconds = 0.18,      
			MirrorSystemPartnerSearchMaxDistance = 0.35,      
			MirrorSystemEnableCompoundReflections = true,     
			MirrorSystemRequireAllXYZForCompound = false,      
			MirrorSystemCanvasForceFixedSize = true,  
			MirrorSystemSnapCanvasToWholeCells = true, 
			MirrorSystemMinPixelsPerCell = 4,     
			MirrorSystemVisualizationEnabled = false,    
			MirrorSystemVisualizationObjectsByAxis = {},       
			MirrorSystemAxisColorByKey = {
				X = Color3.fromRGB(0, 255, 0), 
				Y = Color3.fromRGB(255, 0, 0), 
				Z = Color3.fromRGB(0, 155, 255), 
			},
			MirrorSystemMidlineColor = Color3.fromRGB(0, 0, 0), 
			MirrorSystemMidlineThicknessPx = 3,
			MirrorSystemArrowHeadSizePx = 12,
			MirrorSystemArrowHeadThicknessPx = 2,
			MirrorSystemGridMarginStuds = 2,        
			MirrorSystemGridTargetCellStuds = 2,        
			MirrorSystemGridMinCellsPerSide = 8,        
			MirrorSystemGridMaxLinesPerAxis = 64,
			MirrorSystemGridPixelsPerStud = 32,
			MirrorSystemGridHysteresisPercent = 0.06,  	 
			MirrorSystemVizHeartbeatConnected = false,
			MirrorSystemBoatsWatcherConnected = false,
			MirrorSystemRecentDispatchKeys = {},
			MirrorSystemLastBoatModel = nil,
			MirrorSystemBoatSearchTimeoutSeconds = 3.0,
			MirrorSystemNevermore = nil,
			MirrorSystemBoatAPI = nil,
			MirrorSystemClientBinders = nil,
			MirrorSystemInterceptInstalled = false,
			MirrorSystemActiveHooks = {},
			MirrorSystemRunFlag = false, -- This was the main toggle
			MirrorSystemAxesActive = nil, -- This was the dropdown state
		}

		-- [3] CORE LOGIC
		
		-- All verbatim logic from your script, just modified to use 'ModuleVariables'
		-- instead of 'Variables.MirrorSystem...'
		
		local floor, abs, max, min, clamp = math.floor, math.abs, math.max, math.min, math.clamp
		local format = string.format
		local insert, pack, unpack, concat = table.insert, table.pack, table.unpack, table.concat
		local pairs, ipairs, type, tostring, pcall, require, time = pairs, ipairs, type, tostring, pcall, require, time
		local os_clock = os.clock
		local CFrame_new, Vector3_new, Vector2_new = CFrame.new, Vector3.new, Vector2.new
		local Instance_new = Instance.new
		local Color3_fromRGB, Color3_new = Color3.fromRGB, Color3.new
		local UDim2_fromOffset, UDim2_fromScale, UDim2_new = UDim2.fromOffset, UDim2.fromScale, UDim2.new
		local Enum_NormalId = Enum.NormalId
		local Enum_Font = Enum.Font
		local Enum_TextXAlignment = Enum.TextXAlignment
		local Enum_TextYAlignment = Enum.TextYAlignment
		local Enum_SurfaceGuiSizingMode = Enum.SurfaceGuiSizingMode
	  
		local function MirrorSystemEnsureNevermore()
			if not ModuleVariables.MirrorSystemNevermore then
				ModuleVariables.MirrorSystemNevermore = require(RbxService.ReplicatedStorage:WaitForChild("Nevermore"))
			end
			if not ModuleVariables.MirrorSystemBoatAPI then
				ModuleVariables.MirrorSystemBoatAPI = ModuleVariables.MirrorSystemNevermore("BoatAPIServiceClient")
			end
			if not ModuleVariables.MirrorSystemClientBinders then
				ModuleVariables.MirrorSystemClientBinders = ModuleVariables.MirrorSystemNevermore("ClientBinders")
			end
		end
		
		local function MirrorSystemBoatsFolder()
			return RbxService.Workspace:FindFirstChild("Boats")
		end
		
		local function MirrorSystemBoatOwnerUserId(boatModel)
			if not (boatModel and boatModel:IsA("Model")) then return nil end
			local attributeMap = boatModel:GetAttributes()
			for attributeName, attributeValue in pairs(attributeMap) do
				local lowerKey = string.lower(attributeName)
				if lowerKey == "owneruserid" or lowerKey == "owner" then
					local numericValue = tonumber(attributeValue)
					if numericValue then return numericValue end
				end
			end
			local dataFolder = boatModel:FindFirstChild("BoatData")
			if dataFolder then
				for _, v in ipairs(dataFolder:GetChildren()) do
					local lower = string.lower(v.Name)
					if v:IsA("IntValue") and string.find(lower, "owner") then
						return v.Value
					end
					if v:IsA("ObjectValue") and lower == "owner" then
						local ownerPlayer = v.Value
						if ownerPlayer and ownerPlayer.UserId then return ownerPlayer.UserId end
					end
					if v:IsA("StringValue") and string.find(lower, "owner") then
						local n = tonumber(v.Value)
						if n then return n end
					end
				end
			end
			for _, d in ipairs(boatModel:GetDescendants()) do
				if d:IsA("IntValue") and (d.Name == "Owner" or d.Name == "OwnerUserId") then
					return d.Value
				end
			end
			return nil
		end
		
		local function MirrorSystemFindOwnBoatModel(timeoutSeconds)
			local deadlineTime = os_clock() + (timeoutSeconds or ModuleVariables.MirrorSystemBoatSearchTimeoutSeconds or 3)
			repeat
				local boatsFolder = MirrorSystemBoatsFolder()
				if boatsFolder and RbxService.Players.LocalPlayer then
					local localUserId = RbxService.Players.LocalPlayer.UserId
					for _, candidate in ipairs(boatsFolder:GetChildren()) do
						if candidate:IsA("Model") and MirrorSystemBoatOwnerUserId(candidate) == localUserId then
							return candidate
						end
					end
				end
				RbxService.RunService.Heartbeat:Wait()
			until os_clock() > deadlineTime
			return nil
		end
		
		local function MirrorSystemToCFrame(value)
			if typeof(value) == "CFrame" then return value end
			if type(value) == "table" then
				local count = #value
				if count == 3 then
					return CFrame_new(value[1] or 0, value[2] or 0, value[3] or 0)
				elseif count == 12 then
					local function looksLikeRot(t)
						for i = 1, 9 do
							local n = t[i]
							if type(n) ~= "number" or abs(n) > 1.5 then return false end
						end
						return true
					end
					if looksLikeRot(value) then
						return CFrame_new(
							value[10],value[11],value[12],
							value[1], value[2], value[3],
							value[4], value[5], value[6],
							value[7], value[8], value[9]
						)
					else
						return CFrame_new(
							value[1], value[2], value[3],
							value[4], value[5], value[6],
							value[7], value[8], value[9],
							value[10],value[11],value[12]
						)
					end
				end
			end
			return nil
		end
		
		local function MirrorSystemLocalAxisCoordinate(relativeCFrame, axisKey)
			local localX, localY, localZ = relativeCFrame:GetComponents()
			if axisKey == "X" then return localX end
			if axisKey == "Y" then return localY end
			return localZ
		end
		
		local function MirrorSystemQuantizeNumber(x)
			return floor((x or 0) * 1000 + 0.5) / 1000
		end
		
		local function MirrorSystemKeyForCFrame(cf)
			local x,y,z,
				  r00,r01,r02,
				  r10,r11,r12,
				  r20,r21,r22 = cf:GetComponents()
			return format(
				"%.3f,%.3f,%.3f|%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f",
				MirrorSystemQuantizeNumber(x),  MirrorSystemQuantizeNumber(y),  MirrorSystemQuantizeNumber(z),
				MirrorSystemQuantizeNumber(r00),MirrorSystemQuantizeNumber(r01),MirrorSystemQuantizeNumber(r02),
				MirrorSystemQuantizeNumber(r10),MirrorSystemQuantizeNumber(r11),MirrorSystemQuantizeNumber(r12),
				MirrorSystemQuantizeNumber(r20),MirrorSystemQuantizeNumber(r21),MirrorSystemQuantizeNumber(r22)
			)
		end
		
		local function MirrorSystemMirrorRelativeCFrame(relativeCFrame, axisKey)
			local nudge = ModuleVariables.MirrorSystemNudgeAwayFromPlane or 0.001
			local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = relativeCFrame:GetComponents()
			if axisKey == "X" then
				x = -x + ((x >= 0) and nudge or -nudge)
				r01 = -r01; r02 = -r02; r10 = -r10; r20 = -r20
			elseif axisKey == "Y" then
				y = -y + ((y >= 0) and nudge or -nudge)
				r10 = -r10; r12 = -r12; r01 = -r01; r21 = -r21
			else 
				z = -z + ((z >= 0) and nudge or -nudge)
				r20 = -r20; r21 = -r21; r02 = -r02; r12 = -r12
			end
			return CFrame_new(x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
		end
		
		local function MirrorSystemMirrorRelativeCFrameSequence(relativeCFrame, axisSequence)
			local out = relativeCFrame
			for i = 1, #axisSequence do
				out = MirrorSystemMirrorRelativeCFrame(out, axisSequence[i])
			end
			return out
		end
		
		local function MirrorSystemQuantizeWithStep(x, step)
			step = max(1e-6, step or 0.02)
			return floor((x or 0)/step + 0.5)*step
		end
		
		local function MirrorSystemKeyForWorldCFrame(worldCF, worldStep)
			local p = worldCF.Position
			local rx0,_,_, r10,r11,r12, r20,r21,r22 = (worldCF - worldCF.Position):GetComponents()
			return format("P(%.3f,%.3f,%.3f)|R(%.3f,%.3f,%.3f,%.3f,%.3f,%.3f)",
				MirrorSystemQuantizeWithStep(p.X, worldStep),
				MirrorSystemQuantizeWithStep(p.Y, worldStep),
				MirrorSystemQuantizeWithStep(p.Z, worldStep),
				MirrorSystemQuantizeNumber(rx0),MirrorSystemQuantizeNumber(r10),MirrorSystemQuantizeNumber(r11),
				MirrorSystemQuantizeNumber(r12),MirrorSystemQuantizeNumber(r20),MirrorSystemQuantizeNumber(r21))
		end
		
		local function MirrorSystemCurrentAxisCombinations()
			local axesActive = ModuleVariables.MirrorSystemAxesActive or { X = true, Y = false, Z = false }
			local includeCompound = ModuleVariables.MirrorSystemEnableCompoundReflections ~= false
			local requireAllForCompound = (ModuleVariables.MirrorSystemRequireAllXYZForCompound == true)
			local combos = {}
			if axesActive.X then insert(combos, {"X"}) end
			if axesActive.Y then insert(combos, {"Y"}) end
			if axesActive.Z then insert(combos, {"Z"}) end
			if includeCompound then
				if (not requireAllForCompound) or (axesActive.X and axesActive.Y) then if axesActive.X and axesActive.Y then insert(combos, {"X","Y"}) end end
				if (not requireAllForCompound) or (axesActive.X and axesActive.Z) then if axesActive.X and axesActive.Z then insert(combos, {"X","Z"}) end end
				if (not requireAllForCompound) or (axesActive.Y and axesActive.Z) then if axesActive.Y and axesActive.Z then insert(combos, {"Y","Z"}) end end
				if axesActive.X and axesActive.Y and axesActive.Z then insert(combos, {"X","Y","Z"}) end
			end
			return combos
		end
		
		local function MirrorSystemAxisOnMidline(relativeCFrame, axisKey)
			return abs(MirrorSystemLocalAxisCoordinate(relativeCFrame, axisKey)) <= 1e-4
		end
		
		local function MirrorSystemFilteredAxisCombinations(relativeCFrame)
			local axesActive = ModuleVariables.MirrorSystemAxesActive or {}
			local combos = {}
			local onX = MirrorSystemAxisOnMidline(relativeCFrame, "X")
			local onY = MirrorSystemAxisOnMidline(relativeCFrame, "Y")
			local onZ = MirrorSystemAxisOnMidline(relativeCFrame, "Z")
			if axesActive.X and not onX then insert(combos, {"X"}) end
			if axesActive.Y and not onY then insert(combos, {"Y"}) end
			if axesActive.Z and not onZ then insert(combos, {"Z"}) end
			if ModuleVariables.MirrorSystemEnableCompoundReflections ~= false then
				if axesActive.X and axesActive.Y and not onX and not onY then insert(combos, {"X","Y"}) end
				if axesActive.X and axesActive.Z and not onX and not onZ then insert(combos, {"X","Z"}) end
				if axesActive.Y and axesActive.Z and not onY and not onZ then insert(combos, {"Y","Z"}) end
				if axesActive.X and axesActive.Y and axesActive.Z and not onX and not onY and not onZ then insert(combos, {"X","Y","Z"}) end
			end
			return combos
		end
		
		local function MirrorSystemGetPropBinderIfAny(propModel)
			local ok, binder = pcall(function() return ModuleVariables.MirrorSystemClientBinders.Prop:Get(propModel) end)
			return ok and binder or nil
		end
		
		local function MirrorSystemSamePropClass(modelA, modelB)
			local binderA = MirrorSystemGetPropBinderIfAny(modelA)
			local binderB = MirrorSystemGetPropBinderIfAny(modelB)
			if not binderA or not binderB then return modelA.Name == modelB.Name end
			local classA = (binderA.PropClass and binderA.PropClass) or (binderA.GetPropClass and binderA:GetPropClass())
			local classB = (binderB.PropClass and binderB.PropClass) or (binderB.GetPropClass and binderB:GetPropClass())
			local nameA  = (type(classA) == "table" and (classA.Name or classA._name)) or tostring(classA)
			local nameB  = (type(classB) == "table" and (classB.Name or classB._name)) or tostring(classB)
			return nameA == nameB
		end
		
		local function MirrorSystemMirrorWorldSequence(worldCF, boatPivot, axisSequence)
			local relative = boatPivot:ToObjectSpace(worldCF)
			local mirrored = MirrorSystemMirrorRelativeCFrameSequence(relative, axisSequence)
			return boatPivot * mirrored
		end
		
		local function MirrorSystemFindPartnerForCombination(boatModel, sourceModel, axisSequence)
			local partnerSearchMaxDistance = ModuleVariables.MirrorSystemPartnerSearchMaxDistance or 0.35
			local pivot = boatModel:GetPivot()
			local target = MirrorSystemMirrorWorldSequence(sourceModel:GetPivot(), pivot, axisSequence)
			local best, bestDist = nil, math.huge
			for _, candidate in ipairs(boatModel:GetChildren()) do
				if candidate ~= sourceModel and candidate:IsA("Model") and MirrorSystemGetPropBinderIfAny(candidate) and MirrorSystemSamePropClass(sourceModel, candidate) then
					local d = (candidate:GetPivot().Position - target.Position).Magnitude
					if d < bestDist then best, bestDist = candidate, d end
				end
			end
			if bestDist <= partnerSearchMaxDistance then
				return best
			end
			return nil
		end
		
		local function MirrorSystemCollectPropModelsDeep(pack)
			local out, seen = {}, {}
			local function walk(v)
				if typeof(v) == "Instance" and v:IsA("Model") and MirrorSystemGetPropBinderIfAny(v) then
					insert(out, v)
					return
				end
				if type(v) == "table" then
					if seen[v] then return end
					seen[v] = true
					local bound = rawget(v, "n") or #v
					for i=1,bound do walk(v[i]) end
					for k,val in pairs(v) do if k ~= "n" then walk(val) end end
				end
			end
			for i=1, pack.n do walk(pack[i]) end
			return out
		end
		
		local function MirrorSystemDeepReplaceModel(v, src, dst, seen)
			if v == src then return dst, true end
			if type(v) ~= "table" then return v, false end
			if seen[v] then return v, false end
			seen[v] = true
			local changed = false
			local bound = rawget(v, "n") or #v
			for i=1,bound do
				local nv, ch = MirrorSystemDeepReplaceModel(v[i], src, dst, seen)
				if ch then v[i], changed = nv, true end
			end
			for k,val in pairs(v) do
				if k ~= "n" then
					local nv, ch = MirrorSystemDeepReplaceModel(val, src, dst, seen)
					if ch then v[k], changed = nv, true end
				end
			end
			return v, changed
		end
		
		local function MirrorSystemFirstCFrameArgument(pack)
			for i=1,pack.n do
				local cf = MirrorSystemToCFrame(pack[i])
				if cf then return i, cf end
			end
			return nil, nil
		end
		
		local function MirrorSystemFindBoatFromArguments(pack)
			for i=1, pack.n do
				local v = pack[i]
				if typeof(v) == "Instance" and v:IsA("Model") then
					local uid = MirrorSystemBoatOwnerUserId(v)
					if uid and RbxService.Players.LocalPlayer and uid == RbxService.Players.LocalPlayer.UserId then
						return v
					end
				end
			end
			return ModuleVariables.MirrorSystemLastBoatModel
		end
		
		local function MirrorSystemComputeSquareGridCells(sizeU, sizeV, prevU, prevV)
			local target = max(0.5, ModuleVariables.MirrorSystemGridTargetCellStuds or 2)
			local minC   = max(1,   ModuleVariables.MirrorSystemGridMinCellsPerSide or 8)
			local maxC   = max(minC, ModuleVariables.MirrorSystemGridMaxLinesPerAxis or 64)
			local approxU = max(minC, floor((sizeU/target) + 0.5))
			local approxV = max(minC, floor((sizeV/target) + 0.5))
			local stepU = sizeU / approxU
			local stepV = sizeV / approxV
			local unified = max(0.25, min(stepU, stepV))
			local cellsU = clamp(max(minC, floor((sizeU/unified) + 0.5)), minC, maxC)
			local cellsV = clamp(max(minC, floor((sizeV/unified) + 0.5)), minC, maxC)
			local exactU = sizeU / max(1, cellsU)
			local vByU = clamp(floor((sizeV/exactU) + 0.5), minC, maxC)
			local exactV = sizeV / max(1, cellsV)
			local uByV = clamp(floor((sizeU/exactV) + 0.5), minC, maxC)
			local errU = abs((sizeV / vByU) - exactU)
			local errV = abs((sizeU / uByV) - exactV)
			if errU <= errV then cellsV = vByU else cellsU = uByV end
			local hysteresis = ModuleVariables.MirrorSystemGridHysteresisPercent or 0.06
			if prevU and prevV then
				local prevStepU = sizeU / max(1, prevU)
				local prevStepV = sizeV / max(1, prevV)
				local mismatch = abs(prevStepU - prevStepV)/max(prevStepU, prevStepV)
				local dU = abs(cellsU - prevU)/max(1, prevU)
				local dV = abs(cellsV - prevV)/max(1, prevV)
				if mismatch < 0.015 and dU < hysteresis and dV < hysteresis then
					return prevU, prevV
				end
			end
			return cellsU, cellsV
		end
		
		local function MirrorSystemGetMirrorAxisUITemplate()
			if ModuleVariables.MirrorSystemMirrorAxisUITemplate then
				return ModuleVariables.MirrorSystemMirrorAxisUITemplate
			end
			local root = Instance_new("Frame")
			root.Name = "MirrorAxisUI"
			root.BackgroundTransparency = 1
			root.Size = UDim2_fromScale(1, 1)
			local title = Instance_new("TextLabel")
			title.Name = "Title"
			title.BackgroundTransparency = 1
			title.TextScaled = true
			title.Font = Enum_Font.GothamBold
			title.TextXAlignment = Enum_TextXAlignment.Left
			title.TextYAlignment = Enum_TextYAlignment.Top
			title.Size = UDim2_new(1, 0, 0, 22)
			title.Position = UDim2_fromOffset(6, 2)
			title.Parent = root
			local borders = Instance_new("Folder")
			borders.Name = "Borders"
			borders.Parent = root
			local lines = Instance_new("Folder")
			lines.Name = "Lines"
			lines.Parent = root
			local mid = Instance_new("Folder")
			mid.Name = "Midlines"
			mid.Parent = root
			local arrows = Instance_new("Folder")
			arrows.Name = "Arrows"
			arrows.Parent = root
			ModuleVariables.MirrorSystemMirrorAxisUITemplate = root
			return root
		end
		
		local function MirrorSystemCreateGridGui(basePart, faceId, gridColor, cellsU, cellsV, canvasPixelsU, canvasPixelsV, axisKey)
			local surfaceGui = Instance_new("SurfaceGui")
			surfaceGui.Face = faceId
			surfaceGui.Adornee = basePart
			surfaceGui.LightInfluence = 0
			surfaceGui.AlwaysOnTop = true
			surfaceGui.Parent = basePart
			if ModuleVariables.MirrorSystemCanvasForceFixedSize then
				surfaceGui.SizingMode = Enum_SurfaceGuiSizingMode.FixedSize
				if ModuleVariables.MirrorSystemSnapCanvasToWholeCells then
					surfaceGui.CanvasSize = Vector2_new(
						max(1, floor(canvasPixelsU + 0.5)),
						max(1, floor(canvasPixelsV + 0.5))
					)
				else
					surfaceGui.CanvasSize = Vector2_new(canvasPixelsU, canvasPixelsV)
				end
			else
				surfaceGui.SizingMode = Enum_SurfaceGuiSizingMode.PixelsPerStud
				surfaceGui.PixelsPerStud = ModuleVariables.MirrorSystemGridPixelsPerStud or 32
			end
			local ui = MirrorSystemGetMirrorAxisUITemplate():Clone()
			ui.Parent = surfaceGui
			local cellPixelWidth = canvasPixelsU / max(1, cellsU)
			local dynamicThickness = clamp(floor(cellPixelWidth * 0.08), 1, 3)
			local title = ui:FindFirstChild("Title")
			if title then
				title.TextScaled = false
				title.TextSize = 20
				title.Text = string.upper(axisKey) .. " - Axis Plane"
				title.TextColor3 = gridColor
				local textOutline = Instance_new("UIStroke")
				textOutline.Color = Color3_new(0, 0, 0) 
				textOutline.Thickness = 1
				textOutline.Parent = title
			end
			local function makeBorder(name, pos, size)
				local f = Instance_new("Frame")
				f.Name = name
				f.BackgroundColor3 = gridColor
				f.BorderSizePixel = 0
				f.Position = pos
				f.Size = size
				f.Parent = ui.Borders
			end
			local thick = UDim2_fromOffset(0, dynamicThickness)
			local thickV = UDim2_fromOffset(dynamicThickness, 0)
			makeBorder("Top",    UDim2_new(0,0, 0,0),                  UDim2_new(1,0, 0, thick.Y.Offset))
			makeBorder("Bottom", UDim2_new(0,0, 1, -thick.Y.Offset),   UDim2_new(1,0, 0, thick.Y.Offset))
			makeBorder("Left",   UDim2_new(0,0, 0,0),                  UDim2_new(0, thickV.X.Offset, 1,0))
			makeBorder("Right",  UDim2_new(1, -thickV.X.Offset, 0,0),  UDim2_new(0, thickV.X.Offset, 1,0))
			local function makeLine(name, pos, size)
				local f = Instance_new("Frame")
				f.Name = name
				f.BackgroundColor3 = gridColor
				f.BorderSizePixel = 0
				f.Position = pos
				f.Size = size
				f.BackgroundTransparency = 0.35
				f.Parent = ui.Lines
			end
			for u=1, max(1, cellsU)-1 do
				local x = u / max(1, cellsU)
				makeLine("V"..u, UDim2_new(x,0, 0,0), UDim2_new(0,1, 1,0))
			end
			for v=1, max(1, cellsV)-1 do
				local y = v / max(1, cellsV)
				makeLine("H"..v, UDim2_new(0,0, y,0), UDim2_new(1,0, 0,1))
			end
			local midColor = ModuleVariables.MirrorSystemMidlineColor or Color3_new(0,0,0)
			local midThick = dynamicThickness
			local function midline(name, pos, size)
				local f = Instance_new("Frame")
				f.Name = name
				f.BackgroundColor3 = midColor
				f.BorderSizePixel = 0
				f.Position = pos
				f.Size = size
				f.Parent = ui.Midlines
			end
			midline("CenterH", UDim2_new(0,0, 0.5, -midThick/2), UDim2_new(1,0, 0, midThick))
			midline("CenterV", UDim2_new(0.5, -midThick/2, 0,0), UDim2_new(0, midThick, 1,0))
			local function placeArrow(normX, normY, deg)
				local g = Instance_new("Frame")
					g.Name = "Arrow"
					g.AnchorPoint = Vector2_new(0.5, 0.5)
					g.BackgroundTransparency = 1
					g.Position = UDim2_new(normX,0, normY,0)
					g.Size = UDim2_fromOffset(ModuleVariables.MirrorSystemArrowHeadSizePx or 12, ModuleVariables.MirrorSystemArrowHeadSizePx or 12)
					g.Rotation = deg
					g.Parent = ui.Arrows
				local stem = Instance_new("Frame")
					stem.Name = "Stem"
					stem.AnchorPoint = Vector2_new(0.5, 1.0)
					stem.BackgroundColor3 = gridColor
					stem.BorderSizePixel = 0
					stem.Size = UDim2_new(0, ModuleVariables.MirrorSystemArrowHeadThicknessPx or 2, 1, -((ModuleVariables.MirrorSystemArrowHeadSizePx or 12)-2))
					stem.Position = UDim2_fromScale(0.5, 1)
					stem.Parent = g
				local head = Instance_new("ImageLabel")
					head.Name = "Head"
					head.BackgroundTransparency = 1
					pcall (function()
						head.Image = "rbxassetid://4762528329"
					end)
					head.ImageColor3 = gridColor
					head.AnchorPoint = Vector2_new(0.5, 0.0)
					head.Position = UDim2_fromScale(0.5, 0.0)
					head.Size = UDim2_new(1, 0, 0, ModuleVariables.MirrorSystemArrowHeadSizePx or 12)
					head.Parent = g
				end
				placeArrow(0.5, 0.0,   90)
				placeArrow(0.5, 1.0,  -90)
				placeArrow(0.0, 0.5,  180)
				placeArrow(1.0, 0.5,    0)
			return surfaceGui
		end
		
		local function MirrorSystemComputeCanvasPixels(sizeUStuds, sizeVStuds, cellsU, cellsV)
			local minPx = max(1, ModuleVariables.MirrorSystemMinPixelsPerCell or 1)
			local rawU = max(1, floor((sizeUStuds * (ModuleVariables.MirrorSystemGridPixelsPerStud or 32)) + 0.5))
			local rawV = max(1, floor((sizeVStuds * (ModuleVariables.MirrorSystemGridPixelsPerStud or 32)) + 0.5))
			local stepU = rawU / max(1, cellsU)
			local stepV = rawV / max(1, cellsV)
			local unified = max(minPx, floor(min(stepU, stepV) + 0.5))
			return unified * max(1, cellsU), unified * max(1, cellsV)
		end
		
		local function MirrorSystemBuildGridSurfacesForPart(gridPart, axisKey, cellsU, cellsV, axisColor)
			local list = {}
			local sx, sy, sz = gridPart.Size.X, gridPart.Size.Y, gridPart.Size.Z
			if axisKey == "X" then
				local cu, cv = MirrorSystemComputeCanvasPixels(sz, sy, cellsU, cellsV)
				insert(list, MirrorSystemCreateGridGui(gridPart, Enum_NormalId.Right,  axisColor, cellsU, cellsV, cu, cv, axisKey))
				insert(list, MirrorSystemCreateGridGui(gridPart, Enum_NormalId.Left,   axisColor, cellsU, cellsV, cu, cv, axisKey))
			elseif axisKey == "Y" then
				local cu, cv = MirrorSystemComputeCanvasPixels(sz, sx, cellsU, cellsV)
				insert(list, MirrorSystemCreateGridGui(gridPart, Enum_NormalId.Top,    axisColor, cellsU, cellsV, cu, cv, axisKey))
				insert(list, MirrorSystemCreateGridGui(gridPart, Enum_NormalId.Bottom, axisColor, cellsU, cellsV, cu, cv, axisKey))
			else 
				local cu, cv = MirrorSystemComputeCanvasPixels(sx, sy, cellsU, cellsV)
				insert(list, MirrorSystemCreateGridGui(gridPart, Enum_NormalId.Front,  axisColor, cellsU, cellsV, cu, cv, axisKey))
				insert(list, MirrorSystemCreateGridGui(gridPart, Enum_NormalId.Back,   axisColor, cellsU, cellsV, cu, cv, axisKey))
			end
			return list
		end
		
		local function MirrorSystemDestroyVizForAxis(axisKey)
			ModuleVariables.Maids[ModuleName]["GridPart_" .. axisKey] = nil
			ModuleVariables.MirrorSystemVisualizationObjectsByAxis[axisKey] = nil
		end
		
		local corners_relative = {
			Vector3_new( 1,  1,  1), Vector3_new( 1,  1, -1),
			Vector3_new( 1, -1,  1), Vector3_new( 1, -1, -1),
			Vector3_new(-1,  1,  1), Vector3_new(-1,  1, -1),
			Vector3_new(-1, -1,  1), Vector3_new(-1, -1, -1)
		}
		
		local function MirrorSystemCalculatePivotCenteredBounds(boatModel)
			local pivot = boatModel:GetPivot()
			local bboxCf, bboxSize = boatModel:GetBoundingBox()
			if bboxSize.Magnitude == 0 then
				return Vector3_new(1, 1, 1)
			end
			local pivotInverse = pivot:Inverse()
			local halfSize = bboxSize / 2
			local maxExtents = Vector3_new(0, 0, 0)
			for i = 1, #corners_relative do
				local relativeCornerPos = corners_relative[i] * halfSize
				local worldCornerPos = (bboxCf * CFrame_new(relativeCornerPos)).Position
				local localCornerPos = pivotInverse * worldCornerPos
				maxExtents = Vector3_new(
					max(maxExtents.X, abs(localCornerPos.X)),
					max(maxExtents.Y, abs(localCornerPos.Y)),
					max(maxExtents.Z, abs(localCornerPos.Z))
				)
			end
			return maxExtents * 2
		end
		
		local function MirrorSystemEnsureVizForAxis(axisKey, boatModel)
			MirrorSystemDestroyVizForAxis(axisKey)
			local pivotCenteredSize = MirrorSystemCalculatePivotCenteredBounds(boatModel)
			local pivot = boatModel:GetPivot()
			local extra = max(0, ModuleVariables.MirrorSystemGridMarginStuds or 0)
			local col = ModuleVariables.MirrorSystemAxisColorByKey[axisKey] or Color3_new(1,1,1)
			local part = Instance_new("Part")
			part.Name = "MirrorGrid_"..axisKey
			part.Anchored, part.CanCollide, part.Transparency = true, false, 1
			part.Parent = RbxService.Workspace
			ModuleVariables.Maids[ModuleName]["GridPart_" .. axisKey] = part
			part.CFrame = pivot
			if axisKey == "X" then
				part.Size = Vector3_new(0.05, max(0.5, pivotCenteredSize.Y + 2*extra), max(0.5, pivotCenteredSize.Z + 2*extra))
				local u,v = MirrorSystemComputeSquareGridCells(part.Size.Z, part.Size.Y, nil, nil)
				local guis = MirrorSystemBuildGridSurfacesForPart(part, "X", u, v, col)
				ModuleVariables.MirrorSystemVisualizationObjectsByAxis[axisKey] = { Part = part, SurfaceGuis = guis, Boat = boatModel, LastCellsU = u, LastCellsV = v, LastSize = part.Size }
			elseif axisKey == "Y" then
				part.Size = Vector3_new(max(0.5, pivotCenteredSize.X + 2*extra), 0.05, max(0.5, pivotCenteredSize.Z + 2*extra))
				local u,v = MirrorSystemComputeSquareGridCells(part.Size.Z, part.Size.X, nil, nil)
				local guis = MirrorSystemBuildGridSurfacesForPart(part, "Y", u, v, col)
				ModuleVariables.MirrorSystemVisualizationObjectsByAxis[axisKey] = { Part = part, SurfaceGuis = guis, Boat = boatModel, LastCellsU = u, LastCellsV = v, LastSize = part.Size }
			else 
				part.Size = Vector3_new(max(0.5, pivotCenteredSize.X + 2*extra), max(0.5, pivotCenteredSize.Y + 2*extra), 0.05)
				local u,v = MirrorSystemComputeSquareGridCells(part.Size.X, part.Size.Y, nil, nil)
				local guis = MirrorSystemBuildGridSurfacesForPart(part, "Z", u, v, col)
				ModuleVariables.MirrorSystemVisualizationObjectsByAxis[axisKey] = { Part = part, SurfaceGuis = guis, Boat = boatModel, LastCellsU = u, LastCellsV = v, LastSize = part.Size }
			end
		end
		
		local function MirrorSystemRefreshVizForBoat(boatModel)
			local visualizationEnabled = ModuleVariables.MirrorSystemVisualizationEnabled
			local axesActive = ModuleVariables.MirrorSystemAxesActive or { X = true, Y = false, Z = false }
			if not boatModel or not visualizationEnabled then return end
			ModuleVariables.MirrorSystemLastBoatModel = boatModel
			if axesActive.X then MirrorSystemEnsureVizForAxis("X", boatModel) else MirrorSystemDestroyVizForAxis("X") end
			if axesActive.Y then MirrorSystemEnsureVizForAxis("Y", boatModel) else MirrorSystemDestroyVizForAxis("Y") end
			if axesActive.Z then MirrorSystemEnsureVizForAxis("Z", boatModel) else MirrorSystemDestroyVizForAxis("Z") end
		end
		
		local function MirrorSystemHeartbeatUpdate()
			local visualizationEnabled = ModuleVariables.MirrorSystemVisualizationEnabled
			local gridMarginStuds = ModuleVariables.MirrorSystemGridMarginStuds or 0
			local axisColorByKey = ModuleVariables.MirrorSystemAxisColorByKey
			local visualizationObjectsByAxis = ModuleVariables.MirrorSystemVisualizationObjectsByAxis 
			if not visualizationEnabled then return end
			local currentBoat = ModuleVariables.MirrorSystemLastBoatModel
			if not (currentBoat and currentBoat.Parent) then
				for axisKey, _ in pairs(visualizationObjectsByAxis) do
					MirrorSystemDestroyVizForAxis(axisKey)
				end
				return 
			end
			local pivotCenteredSize = MirrorSystemCalculatePivotCenteredBounds(currentBoat)
			local pivot = currentBoat:GetPivot()
			local extra = max(0, gridMarginStuds)
			for axisKey, record in pairs(visualizationObjectsByAxis) do
				local boat = record.Boat
				if not (boat and boat.Parent and boat == currentBoat) then 
					MirrorSystemDestroyVizForAxis(axisKey)
				else
					local col = axisColorByKey[axisKey] or Color3_new(1,1,1)
					record.Part.CFrame = pivot
					local newSize
					local sizeU, sizeV
					if axisKey == "X" then
						newSize = Vector3_new(0.05, max(0.5, pivotCenteredSize.Y + 2*extra), max(0.5, pivotCenteredSize.Z + 2*extra))
						sizeU, sizeV = newSize.Z, newSize.Y
					elseif axisKey == "Y" then
						newSize = Vector3_new(max(0.5, pivotCenteredSize.X + 2*extra), 0.05, max(0.5, pivotCenteredSize.Z + 2*extra))
						sizeU, sizeV = newSize.Z, newSize.X
					else 
						newSize = Vector3_new(max(0.5, pivotCenteredSize.X + 2*extra), max(0.5, pivotCenteredSize.Y + 2*extra), 0.05)
						sizeU, sizeV = newSize.X, newSize.Y
					end
					record.Part.Size = newSize
					local newU, newV = MirrorSystemComputeSquareGridCells(sizeU, sizeV, record.LastCellsU, record.LastCellsV)
					if newU ~= record.LastCellsU or newV ~= record.LastCellsV or record.LastSize ~= newSize then
						for i=1, #record.SurfaceGuis do record.SurfaceGuis[i]:Destroy() end
						record.SurfaceGuis = MirrorSystemBuildGridSurfacesForPart(record.Part, axisKey, newU, newV, col)
						record.LastCellsU, record.LastCellsV, record.LastSize = newU, newV, newSize
					end
				end
			end
		end
		
		local function MirrorSystemConnectBoatWatcher()
			if ModuleVariables.MirrorSystemBoatsWatcherConnected then return end
			local boatsFolder = MirrorSystemBoatsFolder()
			if not boatsFolder then return end
			local connection = boatsFolder.ChildAdded:Connect(function(newModel)
				if not ModuleVariables.MirrorSystemVisualizationEnabled then return end
				if not (newModel and newModel:IsA("Model")) then return end
				if not RbxService.Players.LocalPlayer then return end
				local deadline = os_clock() + 5.0
				repeat
					local owner = MirrorSystemBoatOwnerUserId(newModel)
					if owner and owner == RbxService.Players.LocalPlayer.UserId then
						MirrorSystemRefreshVizForBoat(newModel)
						return
					end
					RbxService.RunService.Heartbeat:Wait()
				until os_clock() > deadline
			end)
			ModuleVariables.Maids[ModuleName]:GiveTask(connection)
			ModuleVariables.Maids[ModuleName]:GiveTask(function() ModuleVariables.MirrorSystemBoatsWatcherConnected = false end)
			ModuleVariables.MirrorSystemBoatsWatcherConnected = true
		end
		
		local MirrorSystemSafePass = { PlaceNewBoat = true }

		local function MirrorSystemDedupeKey(methodName, boatModel, relativeCFrame)
			local p = relativeCFrame and relativeCFrame.Position or Vector3_new()
			return format("%s|%s|%.3f,%.3f,%.3f",
				tostring(methodName), tostring(boatModel),
				MirrorSystemQuantizeNumber(p.X), MirrorSystemQuantizeNumber(p.Y), MirrorSystemQuantizeNumber(p.Z))
		end
		
		local function MirrorSystemShouldSkip(key)
			local recentDispatchKeys = ModuleVariables.MirrorSystemRecentDispatchKeys
			local dedupeWindowSeconds = ModuleVariables.MirrorSystemDedupeWindowSeconds or 0.18
			local now = time()
			local last = recentDispatchKeys[key]
			if last and (now - last) < dedupeWindowSeconds then
				return true
			end
			recentDispatchKeys[key] = now
			return false
		end
		
		local function MirrorSystemBuildRelativesFromSequences(relativeCFrame, axisSequenceList)
			local out, seen = {}, {}
			for i=1, #axisSequenceList do
				local mirrored = MirrorSystemMirrorRelativeCFrameSequence(relativeCFrame, axisSequenceList[i])
				local k = MirrorSystemKeyForCFrame(mirrored)
				if not seen[k] then seen[k] = true; insert(out, mirrored) end
			end
			return out
		end
		
		local function MirrorSystemDispatch(methodName, originalFunction, selfObject, ...)
			local mirrorSystemRunFlag = ModuleVariables.MirrorSystemRunFlag
			local visualizationEnabled = ModuleVariables.MirrorSystemVisualizationEnabled
			local worldDedupeQuantizeStuds = ModuleVariables.MirrorSystemWorldDedupeQuantizeStuds
			local includeCompoundOnTransforms = ModuleVariables.MirrorSystemIncludeCompoundOnTransformsAndActions ~= false
			if not mirrorSystemRunFlag or MirrorSystemSafePass[methodName] then
				return originalFunction(selfObject, ...)
			end
			local argumentPack = pack(...)
			local boatModel = MirrorSystemFindBoatFromArguments(argumentPack)
			local indexOfCFrame, relativeCFrame = MirrorSystemFirstCFrameArgument(argumentPack)
			local propModelList = MirrorSystemCollectPropModelsDeep(argumentPack)
			if boatModel and visualizationEnabled then
				ModuleVariables.MirrorSystemLastBoatModel = boatModel
				MirrorSystemRefreshVizForBoat(boatModel)
			end
			if boatModel and indexOfCFrame and relativeCFrame and #propModelList == 0 then
				local combosFiltered = MirrorSystemFilteredAxisCombinations(relativeCFrame)
				local seenWorld = {}
				local pivot = boatModel:GetPivot()
				local originalWorld = pivot * relativeCFrame
				seenWorld[ MirrorSystemKeyForWorldCFrame(originalWorld, worldDedupeQuantizeStuds) ] = true
				local result = originalFunction(selfObject, unpack(argumentPack, 1, argumentPack.n))
				local mirroredRelatives = MirrorSystemBuildRelativesFromSequences(relativeCFrame, combosFiltered)
				for i=1, #mirroredRelatives do
					local twinRelative = mirroredRelatives[i]
					local twinWorld = pivot * twinRelative
					local worldKey = MirrorSystemKeyForWorldCFrame(twinWorld, worldDedupeQuantizeStuds)
					if not seenWorld[worldKey] then
						seenWorld[worldKey] = true
						local dedupeKey = MirrorSystemDedupeKey(methodName .. "#mirror", boatModel, twinRelative)
						if not MirrorSystemShouldSkip(dedupeKey) then
							local mirroredPack = pack(unpack(argumentPack, 1, argumentPack.n))
							mirroredPack[indexOfCFrame] = twinRelative
							pcall(originalFunction, selfObject, unpack(mirroredPack, 1, mirroredPack.n))
						end
					end
				end
				return result
			end
			local combosForCall = MirrorSystemCurrentAxisCombinations()
			if boatModel and indexOfCFrame and relativeCFrame and #propModelList > 0 then
				local result = originalFunction(selfObject, unpack(argumentPack, 1, argumentPack.n))
				for s=1, #propModelList do
					local source = propModelList[s]
					local visited = {}
					for c=1, #combosForCall do
						local combo = combosForCall[c]
						if (#combo == 1) or includeCompoundOnTransforms then
							local mirroredRel = MirrorSystemMirrorRelativeCFrameSequence(relativeCFrame, combo)
							local partner = MirrorSystemFindPartnerForCombination(boatModel, source, combo)
							if partner and not visited[partner] then
								visited[partner] = true
								local mirroredPack = pack(unpack(argumentPack, 1, argumentPack.n))
								MirrorSystemDeepReplaceModel(mirroredPack, source, partner, {})
								mirroredPack[indexOfCFrame] = mirroredRel
								local dedupeKey = MirrorSystemDedupeKey(methodName .. "#mirror", boatModel, mirroredRel)
								if not MirrorSystemShouldSkip(dedupeKey) then
									pcall(originalFunction, selfObject, unpack(mirroredPack, 1, mirroredPack.n))
								end
							end
						end
					end
				end
				return result
			end
			if boatModel and (not indexOfCFrame) and #propModelList > 0 then
				local result = originalFunction(selfObject, unpack(argumentPack, 1, argumentPack.n))
				for c = 1, #combosForCall do
					local combo = combosForCall[c]
					if (#combo == 1) or includeCompoundOnTransforms then
						local partnersForThisCombo, seenPartners = {}, {}
						for s = 1, #propModelList do
							local source = propModelList[s]
							local partner = MirrorSystemFindPartnerForCombination(boatModel, source, combo)
							if partner and not seenPartners[partner] then
								seenPartners[partner] = true
								insert(partnersForThisCombo, { source = source, partner = partner })
							end
						end
						if #partnersForThisCombo > 0 then
							local mirroredPack = pack(unpack(argumentPack, 1, argumentPack.n))
							local seenReplacements = {}
							for i = 1, #partnersForThisCombo do
								local entry = partnersForThisCombo[i]
								MirrorSystemDeepReplaceModel(mirroredPack, entry.source, entry.partner, seenReplacements)
							end
							local partnerStrings = {}
							for i = 1, #partnersForThisCombo do
								partnerStrings[i] = tostring(partnersForThisCombo[i].partner) 
							end
							table.sort(partnerStrings) 
							local dedupeKey = format("%s#mirror|%s|%s|%s",
								methodName,
								concat(combo, ""),
								tostring(boatModel), 
								concat(partnerStrings, ",")
							)
							if not MirrorSystemShouldSkip(dedupeKey) then
								pcall(originalFunction, selfObject, unpack(mirroredPack, 1, mirroredPack.n))
							end
						end
					end
				end
				return result
			end
			return originalFunction(selfObject, ...)
		end
		
		local function MirrorSystemSetAxesSelection(selectionObject)
			local axisState = { X = false, Y = false, Z = false }
			if type(selectionObject) == "string" then
				if axisState[selectionObject] ~= nil then axisState[selectionObject] = true end
			elseif type(selectionObject) == "table" then
				local anyArray = false
				for k,v in pairs(selectionObject) do
					if type(k) == "number" then
						anyArray = true
						if axisState[v] ~= nil then axisState[v] = true end
					end
				end
				if not anyArray then
					for axis, val in pairs(selectionObject) do
						if axisState[axis] ~= nil then axisState[axis] = (val == true) end
					end
				end
			end
			ModuleVariables.MirrorSystemAxesActive = axisState
			if ModuleVariables.MirrorSystemVisualizationEnabled and ModuleVariables.MirrorSystemLastBoatModel then
				MirrorSystemRefreshVizForBoat(ModuleVariables.MirrorSystemLastBoatModel)
			end
		end
		
		local function MirrorSystemStop()
			ModuleVariables.MirrorSystemRunFlag = false
			if ModuleVariables.MirrorSystemInterceptInstalled then
				for _, hookedFunction in ipairs(ModuleVariables.MirrorSystemActiveHooks) do
					pcall(unhookfunction, hookedFunction)
				end
				ModuleVariables.MirrorSystemActiveHooks = {}
				ModuleVariables.MirrorSystemInterceptInstalled = false
			end
		end
		
		local function MirrorSystemStart()
			MirrorSystemEnsureNevermore()
			if not ModuleVariables.MirrorSystemInterceptInstalled then
				ModuleVariables.Maids[ModuleName]:GiveTask(MirrorSystemStop)
				local boatAPI = ModuleVariables.MirrorSystemBoatAPI
				if not boatAPI then
					RbxService.Players.LocalPlayer:Kick("Aborting! Error in locating API. Please contact WFYB Exploits!")
					return
				end
				for methodName, functionToHook in pairs(boatAPI) do
					if type(functionToHook) == "function" then
						local original_function 
						local hook_callback = function(selfRef, ...)
							return MirrorSystemDispatch(methodName, original_function, selfRef, ...)
						end
						local success, err = pcall(function()
							original_function = hookfunction(functionToHook, hook_callback)
							insert(ModuleVariables.MirrorSystemActiveHooks, functionToHook)
						end)
						if not success then
							RbxService.Players.LocalPlayer:Kick("Aborting! Hook Functions are NOT supported by this executor. Try another executor!")
						end
					end
				end
				ModuleVariables.MirrorSystemInterceptInstalled = true
			end
			ModuleVariables.MirrorSystemRunFlag = true
			if not ModuleVariables.MirrorSystemAxesActive then
				local ok, selected = pcall(function()
					return UI.Options and UI.Options.MirrorBuildAxisDropdown and UI.Options.MirrorBuildAxisDropdown.Value
				end)
				if ok and selected then
					MirrorSystemSetAxesSelection(selected)
				else
					ModuleVariables.MirrorSystemAxesActive = { X = true, Y = false, Z = false } 
				end
			end
		end
		
		local function MirrorSystemSetVisualizationEnabled(enabled)
			ModuleVariables.MirrorSystemVisualizationEnabled = enabled and true or false
			if ModuleVariables.MirrorSystemVisualizationEnabled then
				local boatNow = MirrorSystemFindOwnBoatModel(ModuleVariables.MirrorSystemBoatSearchTimeoutSeconds)
				if boatNow then MirrorSystemRefreshVizForBoat(boatNow) end
				if not ModuleVariables.MirrorSystemVizHeartbeatConnected then
					ModuleVariables.Maids[ModuleName]:GiveTask(RbxService.RunService.Heartbeat:Connect(MirrorSystemHeartbeatUpdate))
					ModuleVariables.MirrorSystemVizHeartbeatConnected = true
				end
				MirrorSystemConnectBoatWatcher()
			else
				MirrorSystemDestroyVizForAxis("X")
				MirrorSystemDestroyVizForAxis("Y")
				MirrorSystemDestroyVizForAxis("Z")
				pcall(function() ModuleVariables.Maids[ModuleName]:DoCleaning() end)
				ModuleVariables.MirrorSystemVizHeartbeatConnected = false
				ModuleVariables.MirrorSystemBoatsWatcherConnected = false
			end
		end
		
		-- [4] UI CREATION
		local MirrorSystemGroupbox = UI.Tabs.Build:AddRightGroupbox("Mirror System", "flip-horizontal-2")
		
		MirrorSystemGroupbox:AddDropdown("MirrorBuildAxisDropdown", {
			Text = "Mirror Axes:",
			Values = { "X", "Y", "Z" },
			Default = "X",
			Multi = true,
		})
		
		MirrorSystemGroupbox:AddDivider()
		
		local MirrorBuildToggle = MirrorSystemGroupbox:AddToggle("MirrorBuildToggle", {
			Text = "Mirror Build",
			Tooltip = "Turn Feature [ON/OFF].",
			DisabledTooltip = "Feature Disabled!",
			Default = false,
			Disabled = false,
			Visible = true,
			Risky = false,
		})
		
		local MirrorAxisUIToggle = MirrorSystemGroupbox:AddToggle("MirrorAxisUIToggle", {
			Text = "Show Mirror Axes",
			Tooltip = "Turn Feature [ON/OFF].",
			DisabledTooltip = "Feature Disabled!",
			Default = false,
			Disabled = false,
			Visible = true,
			Risky = false,
		})
		
		-- [5] UI WIRING
		MirrorBuildToggle:OnChanged(function(enabledState)
			if enabledState then
				MirrorSystemStart()
				pcall(function()
					MirrorSystemSetAxesSelection(UI.Options.MirrorBuildAxisDropdown.Value)
				end)
			else
				MirrorSystemStop()
			end
		end)
		
		MirrorAxisUIToggle:OnChanged(function(visualizationEnabledState)
			MirrorSystemSetVisualizationEnabled(visualizationEnabledState)
		end)
		
		UI.Options.MirrorBuildAxisDropdown:OnChanged(function(selectedAxesState)
			MirrorSystemSetAxesSelection(selectedAxesState)
		end)

		-- Apply state on load
		if MirrorBuildToggle.Value then
			MirrorSystemStart()
			pcall(function()
				MirrorSystemSetAxesSelection(UI.Options.MirrorBuildAxisDropdown.Value)
			end)
		end
		if MirrorAxisUIToggle.Value then
			MirrorSystemSetVisualizationEnabled(true)
		end

		-- [6] RETURN MODULE
		return { Name = ModuleName, Stop = MirrorSystemStop }
	end
end
