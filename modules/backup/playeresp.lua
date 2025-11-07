-- "modules/backup/playeresp.lua",
do
    return function(UI)
        -- [1] LOAD DEPENDENCIES
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv = (getgenv and getgenv()) or _G
        local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        -- [2] MODULE STATE
        local ModuleName = "PlayerESP"
        
        -- Need weak tables for Player Maids
        local PlayerMaids = setmetatable({}, { __mode = "k" })
        local function GetPlayerMaid(plr)
            local m = PlayerMaids[plr]
            if not m then m = Maid.new(); PlayerMaids[plr] = m end
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
            
            NameTextSize = 12,
            HealthTextSize = 12,
            NameTextCenter = true,
            NameTextOutline = true,
            HealthTextCenter = true,
            HealthTextOutline = true,
            HealthBarWidth = 50,
            HealthBarHeight = 5,
            HealthBarBGColor = Color3.fromRGB(0, 0, 0),
            HighlightOutlineTransparency = 0,
            Buffer = 4,
            VerticalOffset = 30,
            
            PlayerESP = "PlayerESPHighlightToggle",
            PlayerESPName = "PlayerESPNameDistanceToggle",
            PlayerESPHealthbar = "PlayerESPHealthBarToggle",
            PlayerESPHealthText = "PlayerESPHealthTextToggle",
            PlayerESPTracer = "PlayerESPTracerToggle",
            PlayerESPBox = "PlayerESPBoxToggle",
            PlayerESPColor = "PlayerESPHighlightColorpicker",
            PlayerESPNameColor = "PlayerESPNameDistanceColorpicker",
            PlayerESPTracerColor = "PlayerESPTracerColorpicker",
            PlayerESPBoxColor = "PlayerESPBoxColorpicker",
            MaxPlayerESPDistance = "PlayerESPDistanceSlider",
            
            espData = {}, -- [player] = { ... drawings ... }
        }

        -- [3] CORE LOGIC
        local function T(key) return UI.Toggles[key] end
        local function O(key) return UI.Options[key] end
        
        local function anyEspEnabled()
            return (T(Variables.PlayerESP).Value
                or T(Variables.PlayerESPName).Value
                or T(Variables.PlayerESPHealthbar).Value
                or T(Variables.PlayerESPHealthText).Value
                or T(Variables.PlayerESPTracer).Value
                or T(Variables.PlayerESPBox).Value)
        end

        local function createDrawing(type, props)
            local obj = Drawing.new(type)
            for k, v in pairs(props) do obj[k] = v end
            return obj
        end

        local function addHighlight(player)
            local LocalPlayer = RbxService.Players.LocalPlayer
            if player == LocalPlayer then return end
            
            local char = player.Character
            if not char then return end

            local hl = char:FindFirstChild("Player_ESP")
            if not hl then
                local highlight = Instance.new("Highlight")
                highlight.Name = "Player_ESP"
                highlight.FillColor = O(Variables.PlayerESPColor).Value
                highlight.FillTransparency = O(Variables.PlayerESPColor).Transparency
                highlight.OutlineTransparency = Variables.HighlightOutlineTransparency
                GetPlayerMaid(player):GiveTask(highlight) -- Use player's maid
                highlight.Parent = char
            else
                hl.FillColor = O(Variables.PlayerESPColor).Value
                hl.FillTransparency = O(Variables.PlayerESPColor).Transparency
            end
        end

        local function removeHighlight(player)
            local char = player and player.Character
            if not char then return end
            local hl = char:FindFirstChild("Player_ESP")
            if hl then hl:Destroy() end
        end

        local function createESP(player)
            local LocalPlayer = RbxService.Players.LocalPlayer
            if player == LocalPlayer then return end
            if Variables.espData[player] then return end
            
            local m = GetPlayerMaid(player)
            Variables.espData[player] = {
                NameText = AddDrawingCleanup(m, createDrawing("Text", { Size = Variables.NameTextSize, Center = Variables.NameTextCenter, Outline = Variables.NameTextOutline, Visible = false })),
                HealthText = AddDrawingCleanup(m, createDrawing("Text", { Size = Variables.HealthTextSize, Center = Variables.HealthTextCenter, Outline = Variables.HealthTextOutline, Visible = false })),
                HealthBarBG = AddDrawingCleanup(m, createDrawing("Square", { Filled = true, Color = Variables.HealthBarBGColor, Visible = false })),
                HealthBarFill = AddDrawingCleanup(m, createDrawing("Square", { Filled = true, Color = Color3.fromRGB(0, 255, 0), Visible = false })),
                HealthBarWidth = Variables.HealthBarWidth,
                HealthBarHeight = Variables.HealthBarHeight,
                BoxLines = {
                    AddDrawingCleanup(m, createDrawing("Line", { Thickness = 1, Visible = false })),
                    AddDrawingCleanup(m, createDrawing("Line", { Thickness = 1, Visible = false })),
                    AddDrawingCleanup(m, createDrawing("Line", { Thickness = 1, Visible = false })),
                    AddDrawingCleanup(m, createDrawing("Line", { Thickness = 1, Visible = false })),
                },
                TracerLine = AddDrawingCleanup(m, createDrawing("Line", { Thickness = 1, Visible = false })),
            }
        end

        local function removeESP(player)
            local pack = Variables.espData[player]
            if not pack then return end
            
            -- The drawings are in the PlayerMaid,
            -- which will be cleaned up automatically.
            -- We just need to remove the reference.
            Variables.espData[player] = nil
        end

        local function clearAllESP()
            for player in pairs(Variables.espData) do
                removeESP(player)
                removeHighlight(player)
            end
            for plr, maid in pairs(PlayerMaids) do
                maid:DoCleaning()
            end
            PlayerMaids = setmetatable({}, { __mode = "k" })
            Variables.espData = {}
        end

        local function getBoundingBox2D(char)
            local Camera = RbxService.Workspace.CurrentCamera
            if not Camera then return nil end

            local minX, minY = math.huge, math.huge
            local maxX, maxY = -math.huge, -math.huge
            local anyOn = false

            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    local cf = part.CFrame
                    local sx, sy, sz = part.Size.X * 0.5, part.Size.Y * 0.5, part.Size.Z * 0.5
                    local corners = {
                        cf * Vector3.new(sx, sy, sz), cf * Vector3.new(sx, sy, -sz),
                        cf * Vector3.new(sx, -sy, sz), cf * Vector3.new(sx, -sy, -sz),
                        cf * Vector3.new(-sx, sy, sz), cf * Vector3.new(-sx, sy, -sz),
                        cf * Vector3.new(-sx, -sy, sz), cf * Vector3.new(-sx, -sy, -sz),
                    }
                    for i = 1, 8 do
                        local v, on = Camera:WorldToViewportPoint(corners[i])
                        if on then
                            anyOn = true
                            if v.X < minX then minX = v.X end
                            if v.Y < minY then minY = v.Y end
                            if v.X > maxX then maxX = v.X end
                            if v.Y > maxY then maxY = v.Y end
                        end
                    end
                end
            end
            if not anyOn then return nil end
            return minX, minY, maxX, maxY
        end

        local function onRenderStep()
            pcall(function()
                if not anyEspEnabled() then return end
                
                local LocalPlayer = RbxService.Players.LocalPlayer
                local Camera = RbxService.Workspace.CurrentCamera
                if not LocalPlayer or not Camera then return end

                for player, drawings in pairs(Variables.espData) do
                    if player == LocalPlayer then
                        -- (Handled by createESP check)
                    else
                        local char = player.Character
                        local head = char and char:FindFirstChild("Head")
                        local humanoid = char and char:FindFirstChildOfClass("Humanoid")

                        if not char or not head or not humanoid or humanoid.Health <= 0 then
                            drawings.NameText.Visible = false
                            drawings.HealthBarBG.Visible = false
                            drawings.HealthBarFill.Visible = false
                            drawings.HealthText.Visible = false
                            for _, ln in ipairs(drawings.BoxLines) do ln.Visible = false end
                            drawings.TracerLine.Visible = false
                            local _hl = char and char:FindFirstChild("Player_ESP")
                            if _hl then _hl.Enabled = false end
                        else
                            local pos2D, onScreen = Camera:WorldToViewportPoint(head.Position)
                            if not onScreen then
                                drawings.NameText.Visible = false
                                drawings.HealthBarBG.Visible = false
                                drawings.HealthBarFill.Visible = false
                                drawings.HealthText.Visible = false
                                for _, ln in ipairs(drawings.BoxLines) do ln.Visible = false end
                                drawings.TracerLine.Visible = false
                                local _hl = char and char:FindFirstChild("Player_ESP")
                                if _hl then _hl.Enabled = false end
                            else
                                local Buffer = Variables.Buffer
                                local usernameHeight = drawings.NameText.TextBounds.Y
                                local healthTextHeight = drawings.HealthText.TextBounds.Y
                                local totalHeight = usernameHeight + Buffer + drawings.HealthBarHeight + Buffer + healthTextHeight
                                local VerticalOffset = Variables.VerticalOffset

                                local health = tonumber(humanoid.Health) or 0
                                local maxHealth = tonumber(humanoid.MaxHealth) or 100
                                if maxHealth <= 0 then maxHealth = 100 end
                                local ratio = math.clamp(maxHealth > 0 and (health / maxHealth) or 0, 0, 1)
                                local dist = (head.Position - Camera.CFrame.Position).Magnitude

                                local hl = char:FindFirstChild("Player_ESP")
                                if hl then
                                    local maxShowDist = (O(Variables.MaxPlayerESPDistance) and O(Variables.MaxPlayerESPDistance).Value) or math.huge
                                    hl.Enabled = T(Variables.PlayerESP).Value and (dist <= maxShowDist)
                                    hl.FillColor = O(Variables.PlayerESPColor).Value
                                    hl.FillTransparency = O(Variables.PlayerESPColor).Transparency
                                    hl.OutlineTransparency = Variables.HighlightOutlineTransparency
                                end

                                local maxShowDist = O(Variables.MaxPlayerESPDistance) and O(Variables.MaxPlayerESPDistance).Value or math.huge
                                if dist > maxShowDist then
                                    drawings.NameText.Visible = false
                                    drawings.HealthBarBG.Visible = false
                                    drawings.HealthBarFill.Visible = false
                                    drawings.HealthText.Visible = false
                                    for _, ln in ipairs(drawings.BoxLines) do ln.Visible = false end
                                    drawings.TracerLine.Visible = false
                                else
                                    if T(Variables.PlayerESPName).Value then
                                        drawings.NameText.Text = string.format("[%s] [%dm]", player.Name, math.floor(dist))
                                        drawings.NameText.Position = Vector2.new(pos2D.X, pos2D.Y - totalHeight / 2 - VerticalOffset)
                                        drawings.NameText.Color = O(Variables.PlayerESPNameColor).Value
                                        drawings.NameText.Visible = true
                                    else
                                        drawings.NameText.Visible = false
                                    end

                                    if T(Variables.PlayerESPHealthbar).Value then
                                        local safeMaxHealth = humanoid.MaxHealth > 0 and humanoid.MaxHealth or 1
                                        local safeHealth = math.clamp(humanoid.Health, 0, safeMaxHealth)
                                        local ratio2 = safeHealth / safeMaxHealth
                                        drawings.HealthBarBG.Position = Vector2.new(pos2D.X - drawings.HealthBarWidth / 2, pos2D.Y - totalHeight / 2 + usernameHeight + Buffer - VerticalOffset)
                                        drawings.HealthBarBG.Size = Vector2.new(drawings.HealthBarWidth, drawings.HealthBarHeight)
                                        drawings.HealthBarBG.Visible = true
                                        drawings.HealthBarFill.Position = drawings.HealthBarBG.Position
                                        drawings.HealthBarFill.Size = Vector2.new(drawings.HealthBarWidth * ratio2, drawings.HealthBarHeight)
                                        drawings.HealthBarFill.Color = Color3.fromRGB(math.floor(255 - 255 * ratio2), math.floor(255 * ratio2), 0)
                                        drawings.HealthBarFill.Visible = true
                                    else
                                        drawings.HealthBarBG.Visible = false
                                        drawings.HealthBarFill.Visible = false
                                    end

                                    if T(Variables.PlayerESPHealthText).Value then
                                        drawings.HealthText.Text = string.format("[%d/%d]", math.floor(health), math.floor(maxHealth))
                                        drawings.HealthText.Position = Vector2.new(pos2D.X, pos2D.Y - totalHeight / 2 + usernameHeight + Buffer + drawings.HealthBarHeight + Buffer - VerticalOffset)
                                        drawings.HealthText.Color = Color3.fromRGB(math.floor(255 - 255 * ratio), math.floor(255 * ratio), 0)
                                        drawings.HealthText.Visible = true
                                    else
                                        drawings.HealthText.Visible = false
                                    end

                                    if T(Variables.PlayerESPBox).Value then
                                        local minX, minY, maxX, maxY = getBoundingBox2D(char)
                                        if minX then
                                            local col = O(Variables.PlayerESPBoxColor).Value
                                            local p1, p2, p3, p4 = Vector2.new(minX, minY), Vector2.new(maxX, minY), Vector2.new(maxX, maxY), Vector2.new(minX, maxY)
                                            local bl = drawings.BoxLines
                                            bl[1].From, bl[1].To, bl[1].Color, bl[1].Visible = p1, p2, col, true
                                            bl[2].From, bl[2].To, bl[2].Color, bl[2].Visible = p2, p3, col, true
                                            bl[3].From, bl[3].To, bl[3].Color, bl[3].Visible = p3, p4, col, true
                                            bl[4].From, bl[4].To, bl[4].Color, bl[4].Visible = p4, p1, col, true
                                        else
                                            for _, ln in ipairs(drawings.BoxLines) do ln.Visible = false end
                                        end
                                    else
                                        for _, ln in ipairs(drawings.BoxLines) do ln.Visible = false end
                                    end

                                    if T(Variables.PlayerESPTracer).Value then
                                        local minX, minY, maxX, maxY = getBoundingBox2D(char)
                                        if minX then
                                            local vp = Camera.ViewportSize
                                            local origin = Vector2.new(vp.X / 2, vp.Y - 2)
                                            local target = Vector2.new((minX + maxX) / 2, maxY)
                                            local tline = drawings.TracerLine
                                            tline.From, tline.To, tline.Color, tline.Visible = origin, target, O(Variables.PlayerESPTracerColor).Value, true
                                        else
                                            drawings.TracerLine.Visible = false
                                        end
                                    else
                                        drawings.TracerLine.Visible = false
                                    end
                                end
                            end
                        end
                    end
                end
            end)
        end
        
        -- Start/Stop functions for the RenderStepped connection (verbatim from prompt.lua)
        local function startRender()
            local maid = Variables.Maids[ModuleName]
            if maid["Render"] or not anyEspEnabled() then return end
            maid["Render"] = RbxService.RunService.RenderStepped:Connect(onRenderStep)
        end
        
        local function stopRender()
            Variables.Maids[ModuleName]["Render"] = nil 
        end
        
        local function checkAllToggles()
    		if anyEspEnabled() then
    			startRender()
    		else
    			stopRender()
    			clearAllESP()
    		end
    	end

        local function monitorCharacter(player)
            local m = GetPlayerMaid(player)
            m.CharAdded = nil
            m.CharAdded = player.CharacterAdded:Connect(function()
                if T(Variables.PlayerESP).Value then
                    addHighlight(player)
                end
                if anyEspEnabled() then
                    createESP(player)
                end
            end)
        end

        -- [4] UI CREATION
        local PlayerESPGroupBox = UI.Tabs.Visual:AddLeftGroupbox("Player ESP", "user-pen")
		PlayerESPGroupBox:AddSlider("PlayerESPDistanceSlider", {
			Text = "Player ESP Distance",
			Default = 12500,
			Min = 0,
			Max = 25000,
			Rounding = 1,
			Compact = true,
			Tooltip = "Changes the max detection distance for player esp features.", 
		})
		local PlayerESPHighlightToggle = PlayerESPGroupBox:AddToggle("PlayerESPHighlightToggle", {
			Text = "Highlights",
			Tooltip = "Turn player ESP highlights [On]/[Off].", 
			Default = false, 
		})
		PlayerESPHighlightToggle:AddColorPicker("PlayerESPHighlightColorpicker", {
			Default = Color3.fromRGB(0, 0, 0),
			Title = "Highlight Color", 
			Transparency = 0.5, 
		})
		local PlayerESPNameDistanceToggle = PlayerESPGroupBox:AddToggle("PlayerESPNameDistanceToggle", {
			Text = "Username & Distance",
			Tooltip = "Turn player ESP name distance [On]/[Off].", 
			Default = false, 
		})
		PlayerESPNameDistanceToggle:AddColorPicker("PlayerESPNameDistanceColorpicker", {
			Default = Color3.fromRGB(255, 255, 255),
			Title = "Name & Distance Color", 
			Transparency = 0, 
		})
		local PlayerESPBoxToggle = PlayerESPGroupBox:AddToggle("PlayerESPBoxToggle", {
			Text = "Show Boxes",
			Tooltip = "Shows a box around players onscreen.", 
			Default = false, 
		})
		PlayerESPBoxToggle:AddColorPicker("PlayerESPBoxColorpicker", {
			Default = Color3.fromRGB(255, 255, 255),
			Title = "Box Color", 
			Transparency = 0, 
		})
		local PlayerESPTracerToggle = PlayerESPGroupBox:AddToggle("PlayerESPTracerToggle", {
			Text = "Tracers",
			Tooltip = "Show tracers for players onscreen.", 
			Default = false, 
		})
		PlayerESPTracerToggle:AddColorPicker("PlayerESPTracerColorpicker", {
			Default = Color3.fromRGB(255, 255, 255),
			Title = "Tracer Color", 
			Transparency = 0, 
		})
		local PlayerESPHealthBarToggle = PlayerESPGroupBox:AddToggle("PlayerESPHealthBarToggle", {
			Text = "Show Health Bar",
			Tooltip = "Shows a healthbar above player's head.", 
			Default = false, 
		})
		local PlayerESPHealthTextToggle = PlayerESPGroupBox:AddToggle("PlayerESPHealthTextToggle", {
			Text = "Show Health",
			Tooltip = "Shows player's health ratio.", 
			Default = false, 
		})
        
        -- [5] UI WIRING & INIT (Verbatim)
        local maid = Variables.Maids[ModuleName]
        local LocalPlayer = RbxService.Players.LocalPlayer
        
        O(Variables.PlayerESPColor):OnChanged(function()
            for _, p in ipairs(RbxService.Players:GetPlayers()) do
                local char = p.Character
                if char then
                    local hl = char:FindFirstChild("Player_ESP")
                    if hl then
                        hl.FillColor = O(Variables.PlayerESPColor).Value
                        hl.FillTransparency = O(Variables.PlayerESPColor).Transparency
                    end
                end
            end
        end)
        
        T(Variables.PlayerESP):OnChanged(function(val)
            if val then
                for _, p in ipairs(RbxService.Players:GetPlayers()) do addHighlight(p) end
            else
                for _, p in ipairs(RbxService.Players:GetPlayers()) do removeHighlight(p) end
            end
            checkAllToggles()
        end)

        for _, toggleId in ipairs({Variables.PlayerESPName, Variables.PlayerESPHealthbar, Variables.PlayerESPHealthText, Variables.PlayerESPTracer, Variables.PlayerESPBox}) do
	        T(toggleId):OnChanged(function(val)
		        for _, p in ipairs(RbxService.Players:GetPlayers()) do
			        local data = Variables.espData[p]
			        if val then
				        if not data then
					        createESP(p)
					        data = Variables.espData[p]
				        end
			        else
				        if data then
					        if toggleId == Variables.PlayerESPName then
						        data.NameText.Visible = false
					        elseif toggleId == Variables.PlayerESPHealthbar then
						        data.HealthBarBG.Visible = false
						        data.HealthBarFill.Visible = false
					        elseif toggleId == Variables.PlayerESPHealthText then
						        data.HealthText.Visible = false
					        elseif toggleId == Variables.PlayerESPTracer then
						        data.TracerLine.Visible = false
					        elseif toggleId == Variables.PlayerESPBox then
						        for _, ln in ipairs(data.BoxLines) do ln.Visible = false end
					        end
				        end
			        end
		        end
		        checkAllToggles()
	        end)
        end

        -- Player listeners
        maid:GiveTask(RbxService.Players.PlayerAdded:Connect(function(plr)
            if plr == LocalPlayer then return end
            createESP(plr)
            monitorCharacter(plr)
            if T(Variables.PlayerESP).Value then addHighlight(plr) end
        end))
        
        maid:GiveTask(RbxService.Players.PlayerRemoving:Connect(function(plr)
            removeESP(plr)
            removeHighlight(plr)
            local m = PlayerMaids[plr]
            if m then m:DoCleaning(); PlayerMaids[plr] = nil end
        end))

        -- Init for existing players
        for _, plr in ipairs(RbxService.Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                createESP(plr)
                monitorCharacter(plr)
                if T(Variables.PlayerESP).Value then addHighlight(plr) end
            end
        end
        
        checkAllToggles() -- Initial check to start render loop if needed
        maid:GiveTask(clearAllESP) -- Final cleanup

        -- [6] RETURN MODULE
        local function Stop()
            stopRender()
            clearAllESP()
            Variables.Maids[ModuleName]:DoCleaning()
            for plr, maid in pairs(PlayerMaids) do
                maid:DoCleaning()
            end
            PlayerMaids = setmetatable({}, { __mode = "k" })
        end
        return { Name = ModuleName, Stop = Stop }
    end
end
