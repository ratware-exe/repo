-- modules/universal/proximityarrows.lua
do
    return function(UI)
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
        local maid     = Maid.new()

        local Variables = {
            ProximityArrows = "ProximityArrowsToggle",
            ProximityRange  = "ProximityDistanceSlider",

            RadarCircleThickness = 2,
            RadarCircleNumSides  = 64,
            ArrowRadius          = 160,
            ArrowColor           = Color3.fromRGB(255, 255, 255),

            ArrowShape = { size = 18 }, -- head width in original calc
            PA_arrows = {},
        }

        local function drawArrow(tip, angle, size)
            local arrow = Drawing.new("Triangle")
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

        Variables.PA_radarCircle = (function()
            local circ = Drawing.new("Circle")
            circ.Thickness = Variables.RadarCircleThickness
            circ.NumSides = Variables.RadarCircleNumSides
            circ.Radius = Variables.ArrowRadius
            circ.Color = Variables.ArrowColor
            circ.Filled = false
            circ.Visible = false
            return circ
        end)()

        local function ensureArrow(player)
            local lp = services.Players.LocalPlayer
            if player ~= lp and not Variables.PA_arrows[player] then
                Variables.PA_arrows[player] = Drawing.new("Triangle")
                Variables.PA_arrows[player].Visible = false
            end
        end
        local function removeArrow(player)
            if Variables.PA_arrows[player] then
                Variables.PA_arrows[player]:Remove()
                Variables.PA_arrows[player] = nil
            end
        end

        maid:GiveTask(services.Players.PlayerAdded:Connect(ensureArrow))
        maid:GiveTask(services.Players.PlayerRemoving:Connect(removeArrow))
        for _, plr in ipairs(services.Players:GetPlayers()) do ensureArrow(plr) end

        local function renderArrows()
            local t = UI.Toggles and UI.Toggles[Variables.ProximityArrows]
            if not (t and t.Value) then
                Variables.PA_radarCircle.Visible = false
                for _, arrow in pairs(Variables.PA_arrows) do arrow.Visible = false end
                return
            end

            local camera = services.Workspace.CurrentCamera
            local anyVisible = false
            local screenCenter = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
            local maxDist = (UI.Options and UI.Options[Variables.ProximityRange] and UI.Options[Variables.ProximityRange].Value) or 8000

            for player, arrow in pairs(Variables.PA_arrows) do
                local char = player.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local dist = (hrp.Position - camera.CFrame.Position).Magnitude
                    if dist <= maxDist then
                        local _, onScreen = camera:WorldToViewportPoint(hrp.Position)
                        if not onScreen then
                            anyVisible = true

                            local lp = services.Players.LocalPlayer
                            local myhrp = lp and lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
                            if myhrp then
                                local lpPos = myhrp.Position
                                local targetPos = hrp.Position
                                local dir = Vector2.new(targetPos.X - lpPos.X, targetPos.Z - lpPos.Z)

                                local worldAngle = math.atan2(dir.Y, dir.X)
                                local camYaw = math.atan2(camera.CFrame.LookVector.Z, camera.CFrame.LookVector.X)
                                local relAngle = worldAngle - camYaw - math.pi/2

                                local ratio = math.clamp(dist / maxDist, 0, 1)
                                local color = Color3.fromRGB(
                                    math.floor(255 - 255 * ratio),
                                    math.floor(255 * ratio),
                                    0
                                )

                                local radius = Variables.ArrowRadius
                                local tip = Vector2.new(
                                    screenCenter.X + math.cos(relAngle) * radius,
                                    screenCenter.Y + math.sin(relAngle) * radius
                                )

                                arrow.PointA = tip
                                arrow.PointB = Vector2.new(
                                    tip.X + math.cos(relAngle + math.pi * 0.75) * Variables.ArrowShape.size,
                                    tip.Y + math.sin(relAngle + math.pi * 0.75) * Variables.ArrowShape.size
                                )
                                arrow.PointC = Vector2.new(
                                    tip.X + math.cos(relAngle - math.pi * 0.75) * Variables.ArrowShape.size,
                                    tip.Y + math.sin(relAngle - math.pi * 0.75) * Variables.ArrowShape.size
                                )
                                arrow.Color = color
                                arrow.Visible = true
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

            Variables.PA_radarCircle.Visible = anyVisible
            Variables.PA_radarCircle.Position = screenCenter
        end

        maid:GiveTask(services.RunService.RenderStepped:Connect(renderArrows))

        -- UI (Visual)
        do
            local tab = UI.Tabs.Visual or UI.Tabs.Misc
            local group = tab:AddLeftGroupbox("Player Proximity", "radar")
            group:AddSlider("ProximityDistanceSlider", {
                Text = "Max Distance",
                Default = 2000, Min = 0, Max = 20000, Rounding = 0, Compact = false,
            })
            group:AddToggle("ProximityArrowsToggle", { Text = "Arrows", Default = false })
            group:AddToggle("ProximityCircleToggle", { Text = "Show Radar Circle", Default = false })
        end

        local function Stop()
            for _, a in pairs(Variables.PA_arrows) do pcall(function() a:Remove() end) end
            Variables.PA_arrows = {}
            pcall(function() Variables.PA_radarCircle:Remove() end)
            maid:DoCleaning()
        end

        return { Name = "ProximityArrows", Stop = Stop }
    end
end
