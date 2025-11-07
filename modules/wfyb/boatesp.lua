-- "modules/wfyb/boatesp.lua",
do
    return function(UI)
        -- [1] LOAD DEPENDENCIES
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv = (getgenv and getgenv()) or _G
        local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        -- [2] MODULE STATE
        local ModuleName = "BoatESP"
        
        local BoatMaids = setmetatable({}, { __mode = "k" })
        local function GetBoatMaid(model)
            local m = BoatMaids[model]
            if not m then m = Maid.new(); BoatMaids[model] = m end
            return m
        end
        
        local function AddDrawingCleanup(maid, drawingObj)
            maid:GiveTask(function()
                if drawingObj and drawingObj.Remove then
                    pcall(function() drawingObj:Remove() end)
                end
            end)
            return drawingObj
        end
        
        local Variables = {
            Maids = { [ModuleName] = Maid.new() },
            
            BoatESPDistance = "BoatESPDistanceSlider",
            BoatESPHighlight = "BoatESPHighlightToggle",
            BoatESPHighlightColor = "BoatESPHighlightColorpicker",
            BoatESPNameDistance = "BoatESPNameDistanceToggle",
            BoatESPNameDistanceColor = "BoatESPNameDistanceColorpicker",
            BoatESPBox = "BoatESPBoxToggle",
            BoatESPBoxColor = "BoatESPBoxColorpicker",
            BoatESPTracer = "BoatESPTracerToggle",
            BoatESPTracerColor = "BoatESPTracerColorpicker",
            
            boatEspData = {}, -- [Model] = Draw ESP
            
            -- Copied from PlayerESP
            NameTextSize = 12,
            NameTextCenter = true,
            NameTextOutline = true,
            HighlightOutlineTransparency = 0,
            Buffer = 4,
            VerticalOffset = 30,
            
            BoatsFolder = (RbxService.Workspace:FindFirstChild("Boats") or RbxService.Workspace:FindFirstChild("boat") or RbxService.Workspace:WaitForChild("Boats")),
            BOAT_UPDATE_RATE = 1 / 30,
            boatAccum = 0,
        }

        -- [3] CORE LOGIC
        local function T(key) return UI.Toggles[key] end
        local function O(key) return UI.Options[key] end

        local function isBoatModel(m)
            return m and m:IsA("Model")
                and (m:FindFirstChild("BoatData") or m:FindFirstChild("BoatData", true)) ~= nil
        end

        local function anyBoatEspEnabled()
            return (T(Variables.BoatESPHighlight).Value
                or T(Variables.BoatESPNameDistance).Value
                or T(Variables.BoatESPBox).Value
                or T(Variables.BoatESPTracer).Value)
        end

        local function createDrawing(typeName, props)
            local d = Drawing.new(typeName)
            for k, v in pairs(props or {}) do d[k] = v end
            return d
        end

        local function getBoatDisplayName(model)
            local bd = model:FindFirstChild("BoatData")
            local ubn = bd and bd:FindFirstChild("UnfilteredBoatName")
            return (ubn and ubn.Value ~= nil and tostring(ubn.Value)) or model.Name
        end

        local function getBoatWorldPos(model)
            local ok, pivot = pcall(model.GetPivot, model)
            if ok and pivot then return pivot.Position end
            for _, d in ipairs(model:GetDescendants()) do
                if d:IsA("BasePart") then return d.Position end
            end
            return nil
        end

        local function ensureBoatHighlight(model)
            if not model or not model:IsA("Model") then return end
            local hl = model:FindFirstChild("Boat_ESP")
            if not hl then
                hl = Instance.new("Highlight")
                hl.Name = "Boat_ESP"
                hl.Enabled = false
                hl.Parent = model
                hl.Adornee = nil
                GetBoatMaid(model):GiveTask(hl) -- Use boat's maid
            end
            hl.OutlineTransparency = Variables.HighlightOutlineTransparency
            hl.FillColor = O(Variables.BoatESPHighlightColor).Value
            hl.FillTransparency = O(Variables.BoatESPHighlightColor).Transparency
            return hl
        end

        local function removeBoatHighlight(model)
            if not model or not model:IsA("Model") then return end
            local hl = model:FindFirstChild("Boat_ESP")
            if hl then hl:Destroy() end
        end

        local function createBoatESP(model)
            if Variables.boatEspData[model] then return end
            local BoatESPModel = GetBoatMaid(model)
            Variables.boatEspData[model] = {
                NameText = AddDrawingCleanup(BoatESPModel, createDrawing("Text", { Size = Variables.NameTextSize, Center = Variables.NameTextCenter, Outline = Variables.NameTextOutline, Visible = false })),
                BoxLines = {
                    AddDrawingCleanup(BoatESPModel, createDrawing("Line", { Thickness = 1, Visible = false })),
                    AddDrawingCleanup(BoatESPModel, createDrawing("Line", { Thickness = 1, Visible = false })),
                    AddDrawingCleanup(BoatESPModel, createDrawing("Line", { Thickness = 1, Visible = false })),
                    AddDrawingCleanup(BoatESPModel, createDrawing("Line", { Thickness = 1, Visible = false })),
                },
                TracerLine = AddDrawingCleanup(BoatESPModel, createDrawing("Line", { Thickness = 1, Visible = false })),
            }
        end

        local function removeBoatESP(model)
            local pack = Variables.boatEspData[model]
	        if not pack then return end
	        local function tryRemove(obj)
		        if type(obj) == "table" then
			        for _, v in pairs(obj) do tryRemove(v) end
		        elseif type(obj) == "userdata" and obj.Remove then
			        obj:Remove()
		        end
	        end
	        for _, v in pairs(pack) do tryRemove(v) end
	        Variables.boatEspData[model] = nil
        end

        local function clearAllBoatESP()
            for m in pairs(Variables.boatEspData) do
                removeBoatESP(m)
                removeBoatHighlight(m)
            end
            for m, maid in pairs(BoatMaids) do
                maid:DoCleaning()
            end
            BoatMaids = setmetatable({}, { __mode = "k" })
            Variables.boatEspData = {}
        end

        local function getModelScreenAABB(model)
            local Camera = RbxService.Workspace.CurrentCamera
            if not Camera then return nil end
            
            if typeof(model) ~= "Instance" or not model:IsA("Model") then return nil end
            local ok, cf, size = pcall(model.GetBoundingBox, model)
            if not ok or not cf or not size then return nil end
            local hx, hy, hz = size.X * 0.5, size.Y * 0.5, size.Z * 0.5
            if (hx == 0 and hy == 0 and hz == 0) then return nil end
            local corners = {
                cf * Vector3.new(hx, hy, hz), cf * Vector3.new(hx, hy, -hz),
                cf * Vector3.new(hx, -hy, hz), cf * Vector3.new(hx, -hy, -hz),
                cf * Vector3.new(-hx, hy, hz), cf * Vector3.new(-hx, hy, -hz),
                cf * Vector3.new(-hx, -hy, hz), cf * Vector3.new(-hx, -hy, -hz),
            }
            local minX, minY = math.huge, math.huge
            local maxX, maxY = -math.huge, -math.huge
            local any = false
            for i = 1, #corners do
                local v, on = Camera:WorldToViewportPoint(corners[i])
                if on and v.X == v.X and v.Y == v.Y then
                    any = true
                    if v.X < minX then minX = v.X end
                    if v.Y < minY then minY = v.Y end
                    if v.X > maxX then maxX = v.X end
                    if v.Y > maxY then maxY = v.Y end
                end
            end
            if not any then return nil end
            return minX, minY, maxX, maxY
        end

        local function refreshBoatHighlight(model, hrpPos, maxDist, colOpt, wantHL)
            if not isBoatModel(model) then return end
            if not wantHL then
                local hl = model:FindFirstChild("Boat_ESP")
                if hl then hl.Enabled = false end
                return
            end
            local hl = ensureBoatHighlight(model)
            if not hl then return end

            hl.FillColor = colOpt.Value
            hl.FillTransparency = colOpt.Transparency
            hl.OutlineTransparency = Variables.HighlightOutlineTransparency

            local pos = getBoatWorldPos(model)
            local inRange = (hrpPos and pos and ((pos - hrpPos).Magnitude <= maxDist)) or false
            local onScreen = (getModelScreenAABB(model) ~= nil)
            hl.Enabled = inRange and onScreen
        end

        local function refreshAllBoatHighlights(hrpPos)
            local wantHL = T(Variables.BoatESPHighlight).Value
            local colOpt = O(Variables.BoatESPHighlightColor)
            local maxDist = (O(Variables.BoatESPDistance) and O(Variables.BoatESPDistance).Value) or math.huge
            for _, m in ipairs(Variables.BoatsFolder:GetChildren()) do
                if isBoatModel(m) then
                    refreshBoatHighlight(m, hrpPos, maxDist, colOpt, wantHL)
                end
            end
        end

        local function onBoatRenderStep(dt)
            pcall(function()
                Variables.boatAccum += dt
                if Variables.boatAccum < Variables.BOAT_UPDATE_RATE then return end
                Variables.boatAccum = 0

                if not anyBoatEspEnabled() then return end
                
                local Camera = RbxService.Workspace.CurrentCamera
                local LocalPlayer = RbxService.Players.LocalPlayer
                if not Camera or not LocalPlayer then return end

                do
                    local toCull = table.create(8)
                    for m in pairs(Variables.boatEspData) do
                        if m == nil or typeof(m) ~= "Instance" or not m.Parent then
                            table.insert(toCull, m)
                        end
                    end
                    for i = 1, #toCull do
                        Variables.boatEspData[toCull[i]] = nil
                    end
                end

                local lpChar = LocalPlayer.Character
                local lpHRP = lpChar and lpChar:FindFirstChild("HumanoidRootPart")

                refreshAllBoatHighlights(lpHRP and lpHRP.Position or nil)

                if not lpHRP then
                    for _, d in pairs(Variables.boatEspData) do
                        d.NameText.Visible, d.TracerLine.Visible = false, false
                        for _, ln in ipairs(d.BoxLines) do ln.Visible = false end
                    end
                    return
                end

                local wantName = T(Variables.BoatESPNameDistance).Value
                local wantBox = T(Variables.BoatESPBox).Value
                local wantTr = T(Variables.BoatESPTracer).Value
                local drawFeatures = (wantName or wantBox or wantTr)
                local maxDist = (O(Variables.BoatESPDistance) and O(Variables.BoatESPDistance).Value) or math.huge

                for model, drawings in pairs(Variables.boatEspData) do
                    if not model or not model.Parent then
                        drawings.NameText.Visible, drawings.TracerLine.Visible = false, false
                        for _, ln in ipairs(drawings.BoxLines) do ln.Visible = false end
                    else
                        local boatPos = getBoatWorldPos(model)
                        if not boatPos then
                             drawings.NameText.Visible, drawings.TracerLine.Visible = false, false
                            for _, ln in ipairs(drawings.BoxLines) do ln.Visible = false end
                        else
                            local dist = (boatPos - lpHRP.Position).Magnitude
                            if not drawFeatures or dist > maxDist then
                                drawings.NameText.Visible, drawings.TracerLine.Visible = false, false
                                for _, ln in ipairs(drawings.BoxLines) do ln.Visible = false end
                            else
                                local minX, minY, maxX, maxY = getModelScreenAABB(model)
                                if wantBox and minX then
                                    local col = O(Variables.BoatESPBoxColor).Value
                                    local p1, p2, p3, p4 = Vector2.new(minX, minY), Vector2.new(maxX, minY), Vector2.new(maxX, maxY), Vector2.new(minX, maxY)
                                    local bl = drawings.BoxLines
                                    bl[1].From, bl[1].To, bl[1].Color, bl[1].Visible = p1, p2, col, true
                                    bl[2].From, bl[2].To, bl[2].Color, bl[2].Visible = p2, p3, col, true
                                    bl[3].From, bl[3].To, bl[3].Color, bl[3].Visible = p3, p4, col, true
                                    bl[4].From, bl[4].To, bl[4].Color, bl[4].Visible = p4, p1, col, true
                                else
                                    for _, ln in ipairs(drawings.BoxLines) do ln.Visible = false end
                                end

                                if wantName and minX then
                                    drawings.NameText.Text = string.format("[%s] [%.0fm]", getBoatDisplayName(model), dist / 3.571)
                                    local textH = drawings.NameText.TextBounds.Y
                                    drawings.NameText.Position = Vector2.new((minX + maxX) * 0.5, minY - textH - Variables.Buffer - Variables.VerticalOffset)
                                    drawings.NameText.Color = O(Variables.BoatESPNameDistanceColor).Value
                                    drawings.NameText.Visible = true
                                else
                                    drawings.NameText.Visible = false
                                end

                                if wantTr and minX then
                                    local vp = Camera.ViewportSize
                                    local origin = Vector2.new(vp.X * 0.5, vp.Y - 2)
                                    local target = Vector2.new((minX + maxX) * 0.5, maxY)
                                    local tl = drawings.TracerLine
                                    tl.From, tl.To, tl.Color, tl.Visible = origin, target, O(Variables.BoatESPTracerColor).Value, true
                                else
                                    drawings.TracerLine.Visible = false
                                end
                            end
                        end
                    end
                end
            end)
        end
        
        -- Verbatim Start/Stop from prompt.lua
        local function startBoatRender()
            local maid = Variables.Maids[ModuleName]
	        if maid["Render"] or not anyBoatEspEnabled() then return end
	        maid["Render"] = RbxService.RunService.RenderStepped:Connect(onBoatRenderStep)
	    end

	    local function stopBoatRender()
	        Variables.Maids[ModuleName]["Render"] = nil 
	    end

	    local function boatCheckAllToggles()
	        if anyBoatEspEnabled() then
	            startBoatRender()
	        else
	            stopBoatRender()
	            for _, d in pairs(Variables.boatEspData) do
	                d.NameText.Visible = false
	                for _, ln in ipairs(d.BoxLines) do ln.Visible = false end
	                d.TracerLine.Visible = false
	            end
	        end
	    end
        
        local function ensureBoat(model)
            if not isBoatModel(model) then return end
            if anyBoatEspEnabled() and not Variables.boatEspData[model] then
                createBoatESP(model)
            end
            if T(Variables.BoatESPHighlight).Value then
                ensureBoatHighlight(model)
            end
        end

        local function cleanupBoat(model)
            if not isBoatModel(model) then return end
            removeBoatESP(model)
            removeBoatHighlight(model)
            local bm = BoatMaids[model]
            if bm then bm:DoCleaning(); BoatMaids[model] = nil end
        end

        local function trackBoatModel(m)
            if not (typeof(m) == "Instance" and m:IsA("Model")) then return end
            local _maid = GetBoatMaid(m)

            local function armIfReady()
                if isBoatModel(m) then
                    ensureBoat(m)
                    local hrp = RbxService.Players.LocalPlayer and RbxService.Players.LocalPlayer.Character and RbxService.Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                    refreshAllBoatHighlights(hrp and hrp.Position or nil)
                    _maid:GiveTask(m.AncestryChanged:Connect(function(_, parent)
                        if not parent then cleanupBoat(m) end
                    end))
                    return true
                end
                return false
            end

            if armIfReady() then return end
            _maid:GiveTask(m.DescendantAdded:Connect(function(ch)
                if ch.Name == "BoatData" and armIfReady() then
                   _maid.DescAdded = nil -- Stop listening
                end
            end))
        end
        
        -- [4] UI CREATION
        local BoatESPGroupBox = UI.Tabs.Visual:AddLeftGroupbox("Boat ESP", "sailboat")
		BoatESPGroupBox:AddSlider("BoatESPDistanceSlider", {
			Text = "Boat ESP Distance",
			Default = 12500,
			Min = 0,
			Max = 25000,
			Rounding = 1,
			Compact = true,
			Tooltip = "Changes the max detection distance for boat esp features.", 
		})
		local BoatESPHighlightToggle = BoatESPGroupBox:AddToggle("BoatESPHighlightToggle", {
			Text = "Highlights",
			Tooltip = "Turn boat ESP highlights [On]/[Off].", 
			Default = false, 
		})
		BoatESPHighlightToggle:AddColorPicker("BoatESPHighlightColorpicker", {
			Default = Color3.fromRGB(0, 0, 0),
			Title = "Highlight Color", 
			Transparency = 0.5, 
		})
		local BoatESPNameDistanceToggle = BoatESPGroupBox:AddToggle("BoatESPNameDistanceToggle", {
			Text = "Boat Name & Distance",
			Tooltip = "Turn boat ESP name distance [On]/[Off].", 
			Default = false, 
		})
		BoatESPNameDistanceToggle:AddColorPicker("BoatESPNameDistanceColorpicker", {
			Default = Color3.fromRGB(255, 255, 255),
			Title = "Name & Distance Color", 
			Transparency = 0, 
		})
		local BoatESPBoxToggle = BoatESPGroupBox:AddToggle("BoatESPBoxToggle", {
			Text = "Show Boxes",
			Tooltip = "Shows a box around boats onscreen.", 
			Default = false, 
		})
		BoatESPBoxToggle:AddColorPicker("BoatESPBoxColorpicker", {
			Default = Color3.fromRGB(255, 255, 255),
			Title = "Box Color", 
			Transparency = 0, 
		})
		local BoatESPTracerToggle = BoatESPGroupBox:AddToggle("BoatESPTracerToggle", {
			Text = "Tracers",
			Tooltip = "Show tracers for boats onscreen.", 
			Default = false, 
		})
		BoatESPTracerToggle:AddColorPicker("BoatESPTracerColorpicker", {
			Default = Color3.fromRGB(255, 255, 255),
			Title = "Tracer Color", 
			Transparency = 0, 
		})
        
        -- [5] UI WIRING & INIT (Verbatim)
        local maid = Variables.Maids[ModuleName]
        
        local function _refreshAllHighlightsFromUI()
            local LocalPlayer = RbxService.Players.LocalPlayer
            local hrp = LocalPlayer and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            local pos = hrp and hrp.Position or nil
            refreshAllBoatHighlights(pos)
        end
        
        O(Variables.BoatESPHighlightColor):OnChanged(_refreshAllHighlightsFromUI)
        O(Variables.BoatESPDistance):OnChanged(_refreshAllHighlightsFromUI)
        
        T(Variables.BoatESPHighlight):OnChanged(function()
            _refreshAllHighlightsFromUI()
            boatCheckAllToggles() 
        end)
        
        for _, toggleId in ipairs({Variables.BoatESPNameDistance, Variables.BoatESPBox, Variables.BoatESPTracer}) do
	        T(toggleId):OnChanged(function(val)
		        if val then
			        for _, m in ipairs(Variables.BoatsFolder:GetChildren()) do
				        if isBoatModel(m) and not Variables.boatEspData[m] then
					        createBoatESP(m)
				        end
			        end
		        else
			        for _, d in pairs(Variables.boatEspData) do
				        if toggleId == Variables.BoatESPNameDistance then
					        d.NameText.Visible = false
				        elseif toggleId == Variables.BoatESPBox then
					        for _, ln in ipairs(d.BoxLines) do ln.Visible = false end
				        elseif toggleId == Variables.BoatESPTracer then
					        d.TracerLine.Visible = false
				        end
			        end
		        end
		        boatCheckAllToggles()
	        end)
        end
        
        -- Init boat listeners
        if Variables.BoatsFolder then
            for _, inst in ipairs(Variables.BoatsFolder:GetDescendants()) do
                if inst:IsA("Model") then trackBoatModel(inst) end
            end
            maid:GiveTask(Variables.BoatsFolder.DescendantAdded:Connect(function(inst)
                if inst:IsA("Model") then trackBoatModel(inst) end
            end))
            maid:GiveTask(Variables.BoatsFolder.DescendantRemoving:Connect(function(inst)
                if inst:IsA("Model") and isBoatModel(inst) then cleanupBoat(inst) end
            end))
        end
        
        boatCheckAllToggles()
        maid:GiveTask(clearAllBoatESP) -- Final cleanup

        -- [6] RETURN MODULE
        local function Stop()
            stopBoatRender()
            clearAllBoatESP()
            Variables.Maids[ModuleName]:DoCleaning()
            for m, maid in pairs(BoatMaids) do
                maid:DoCleaning()
            end
            BoatMaids = setmetatable({}, { __mode = "k" })
        end
        return { Name = ModuleName, Stop = Stop }
    end
end
