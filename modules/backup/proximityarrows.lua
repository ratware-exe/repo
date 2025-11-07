-- modules/backup/proximityarrows.lua
do
    return function(UI)
        -- [1] LOAD DEPENDENCIES
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv = (getgenv and getgenv()) or _G
        local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        -- [2] MODULE STATE
        local ModuleName = "ProximityArrows"
        local Variables = {
            Maids = { [ModuleName] = Maid.new() },
            
            ArrowSize = 28,
            ArrowRadius = 240,
            MinArrowTransparency = 0.9,
            ArrowThickness = 1,
            RadarCircleThickness = 1,
            RadarCircleNumSides = 64,
            RadarCircleColor = Color3.fromRGB(255, 255, 255),
            
            ProximityArrows = "ProximityArrowsToggle",
            ProximityArrowCircle = "ProximityCircleToggle",
            ProximityRange = "ProximityDistanceSlider",
            
            PA_arrows = {}, -- [player] = Drawing
            PA_radarCircle = nil,
        }

        -- [3] CORE LOGIC
        local function T(key) return UI.Toggles[key] end
        local function O(key) return UI.Options[key] end
        
        local function CreateArrow(center, angle, size, radius, color)
            local arrow = Drawing.new("Triangle")
            arrow.Filled = true
            arrow.Thickness = Variables.ArrowThickness
            arrow.Color = color

            local tip = Vector2.new(
                center.X + math.cos(angle) * (radius + size),
                center.Y + math.sin(angle) * (radius + size)
            )
            local base1 = Vector2.new(
                tip.X + math.cos(angle + math.pi * 0.75) * size,
                tip.Y + math.sin(angle + math.pi * 0.75) * size
            )
            local base2 = Vector2.new(
                tip.X + math.cos(angle - math.pi * 0.75) * size,
                tip.Y + math.sin(angle - math.pi * 0.75) * size
            )

            arrow.PointA = tip
            arrow.PointB = base1
            arrow.PointC = base2
            arrow.Visible = true
            return arrow
        end

        local function ensureArrow(player)
            local LocalPlayer = RbxService.Players.LocalPlayer
            if player ~= LocalPlayer and not Variables.PA_arrows[player] then
                Variables.PA_arrows[player] = Drawing.new("Triangle")
                Variables.PA_arrows[player].Visible = false
                -- Add to module maid for cleanup
                Variables.Maids[ModuleName]:GiveTask(function()
                    if Variables.PA_arrows[player] then
                        pcall(Variables.PA_arrows[player].Remove, Variables.PA_arrows[player])
                        Variables.PA_arrows[player] = nil
                    end
                end)
            end
        end

        local function removeArrow(player)
            if Variables.PA_arrows[player] then
                Variables.PA_arrows[player]:Remove()
                Variables.PA_arrows[player] = nil
            end
        end

        local function renderArrows()
            local Camera = RbxService.Workspace.CurrentCamera
            local LocalPlayer = RbxService.Players.LocalPlayer
            if not Camera or not LocalPlayer then return end

            if not T(Variables.ProximityArrows).Value then
                Variables.PA_radarCircle.Visible = false
                for _, arrow in pairs(Variables.PA_arrows) do arrow.Visible = false end
                return
            end
        
            local anyVisible = false
            local screenCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
            local maxDist = O(Variables.ProximityRange).Value
        
            for player, arrow in pairs(Variables.PA_arrows) do
                local char = player.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local dist = (hrp.Position - Camera.CFrame.Position).Magnitude
                    if dist <= maxDist then
                        local _, onScreen = Camera:WorldToViewportPoint(hrp.Position)
                        if not onScreen then
                            anyVisible = true
        
                            local lpPosObj = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                            if lpPosObj then
                                local lpPos = lpPosObj.Position
                                local targetPos = hrp.Position
                                local dir = Vector2.new(targetPos.X - lpPos.X, targetPos.Z - lpPos.Z)
        
                                local worldAngle = math.atan2(dir.Y, dir.X) 
                                local camYaw = math.atan2(Camera.CFrame.LookVector.Z, Camera.CFrame.LookVector.X)
                                local relAngle = worldAngle - camYaw - math.pi/2 
        
                                local ratio = math.clamp(dist / maxDist, 0, 1)
                                local color = Color3.fromRGB(
                                    math.floor(255 - 255 * ratio),
                                    math.floor(255 * ratio),
                                    0
                                )
        
                                local tri = CreateArrow(screenCenter, relAngle, Variables.ArrowSize, Variables.ArrowRadius, color)
                                tri.Transparency = math.max(Variables.MinArrowTransparency, ratio)
        
                                arrow.PointA = tri.PointA
                                arrow.PointB = tri.PointB
                                arrow.PointC = tri.PointC
                                arrow.Color = tri.Color
                                arrow.Transparency = tri.Transparency
                                arrow.Visible = true
                                tri:Remove()
                            end
                        else
                            arrow.Visible = false
                        end
                    else
                        arrow.Visible = false
                    end
                else
                    arrow.Visible = false
                end
            end
        
            Variables.PA_radarCircle.Position = screenCenter
            if T(Variables.ProximityArrowCircle).Value then
                Variables.PA_radarCircle.Visible = anyVisible
            else
                Variables.PA_radarCircle.Visible = false
            end
        end
        
        -- Start/Stop are not used by the original logic, it's all in OnChanged
        local function Start() end 
        local function Stop()
            Variables.Maids[ModuleName]:DoCleaning()
            if Variables.PA_radarCircle then
                pcall(Variables.PA_radarCircle.Remove, Variables.PA_radarCircle)
            end
            for p, arrow in pairs(Variables.PA_arrows) do
                pcall(arrow.Remove, arrow)
            end
            Variables.PA_arrows = {}
        end
        
        -- [4] UI CREATION
        local ProximityGroupBox = UI.Tabs.Visual:AddLeftGroupbox("Player Proximity", "radar")
		ProximityGroupBox:AddSlider("ProximityDistanceSlider", {
			Text = "Detection Radius",
			Default = 250,
			Min = 0,
			Max = 1000,
			Rounding = 1,
			Compact = true,
			Tooltip = "Changes the max detection distance for player proximity.", 
		})
		local ProximityArrowsToggle = ProximityGroupBox:AddToggle("ProximityArrowsToggle", {
			Text = "Proximity Arrows",
			Tooltip = "Show nearby players offscreen direction using arrows.", 
			Default = false, 
		})
		local ProximityCircleToggle = ProximityGroupBox:AddToggle("ProximityCircleToggle", {
			Text = "FOV Circle",
			Tooltip = "Shows FOV circle to indicate players offscreen nearby.", 
			Default = false, 
		})

        -- [5] UI WIRING & INIT (Verbatim from prompt.lua)
        Variables.PA_radarCircle = (function()
            local circ = Drawing.new("Circle")
            circ.Thickness = Variables.RadarCircleThickness
            circ.NumSides = Variables.RadarCircleNumSides
            circ.Radius = Variables.ArrowRadius
            circ.Color = Variables.RadarCircleColor
            circ.Filled = false
            circ.Visible = false
            Variables.Maids[ModuleName]:GiveTask(function() pcall(function() circ:Remove() end) end)
            return circ
        end)()
        
        Variables.Maids[ModuleName]:GiveTask(RbxService.Players.PlayerAdded:Connect(ensureArrow))
        Variables.Maids[ModuleName]:GiveTask(RbxService.Players.PlayerRemoving:Connect(removeArrow))
        for _, plr in ipairs(RbxService.Players:GetPlayers()) do
            ensureArrow(plr)
        end
        
        Toggles[Variables.ProximityArrows]:OnChanged(function(val)
            local maid = Variables.Maids[ModuleName]
            if val then
                if not maid["Render"] then
                    maid["Render"] = RbxService.RunService.RenderStepped:Connect(renderArrows)
                end
            else
                maid["Render"] = nil 
                Variables.PA_radarCircle.Visible = false
                for _, a in pairs(Variables.PA_arrows) do a.Visible = false end
            end
        end)
        
        Toggles[Variables.ProximityArrowCircle]:OnChanged(function(val)
            if not val then
                Variables.PA_radarCircle.Visible = false
            else
                renderArrows()
            end
        end)
        
        -- Start if already enabled
        if Toggles[Variables.ProximityArrows].Value then
            Variables.Maids[ModuleName]["Render"] = RbxService.RunService.RenderStepped:Connect(renderArrows)
        end

        -- [6] RETURN MODULE
        return { Name = ModuleName, Stop = Stop }
    end
end
