-- modules/universal/proximityarrows.lua
do
    return function(ui)
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local maid = Maid.new()
        local arrows_by_player = {}
        local circle
        local render_conn

        local arrow_size = 28
        local arrow_radius = 240
        local arrow_thickness = 1
        local circle_sides = 64
        local circle_color = Color3.fromRGB(255, 255, 255)

        local function ensure_circle()
            if circle then return end
            circle = Drawing.new("Circle")
            circle.Thickness = 1
            circle.NumSides = circle_sides
            circle.Radius = arrow_radius
            circle.Color = circle_color
            circle.Filled = false
            circle.Visible = false
            maid:GiveTask(function() if circle then circle:Remove() end end)
        end

        local function ensure_arrow(plr)
            if plr == services.Players.LocalPlayer then return end
            if arrows_by_player[plr] then return end
            local tri = Drawing.new("Triangle")
            tri.Filled = true
            tri.Thickness = arrow_thickness
            tri.Color = Color3.fromRGB(255, 255, 255)
            tri.Visible = false
            arrows_by_player[plr] = tri
            maid:GiveTask(function() if arrows_by_player[plr] then arrows_by_player[plr]:Remove(); arrows_by_player[plr]=nil end end)
        end

        local function remove_arrow(plr)
            if arrows_by_player[plr] then arrows_by_player[plr]:Remove(); arrows_by_player[plr] = nil end
        end

        local function render()
            local cam = services.Workspace.CurrentCamera
            if not cam then return end
            local vp = cam.ViewportSize
            local center = Vector2.new(vp.X/2, vp.Y/2)

            if ui.Toggles.ProximityCircleToggle and ui.Toggles.ProximityCircleToggle.Value then
                ensure_circle()
                circle.Position = center
                circle.Visible = true
            elseif circle then
                circle.Visible = false
            end

            local max_dist = (ui.Options.ProximityDistanceSlider and tonumber(ui.Options.ProximityDistanceSlider.Value)) or 250

            for _, plr in ipairs(services.Players:GetPlayers()) do
                if plr ~= services.Players.LocalPlayer then
                    ensure_arrow(plr)
                    local tri = arrows_by_player[plr]
                    local char = plr.Character
                    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
                    local lchar = services.Players.LocalPlayer.Character
                    local lhrp = lchar and lchar:FindFirstChild("HumanoidRootPart")

                    if not (tri and hrp and lhrp) then
                        if tri then tri.Visible = false end
                    else
                        local offset = hrp.Position - lhrp.Position
                        local dist = offset.Magnitude
                        local screenpos, on_screen = cam:WorldToViewportPoint(hrp.Position)
                        if on_screen or dist > max_dist then
                            tri.Visible = false
                        else
                            -- angle in screen space from center toward player projected position
                            local angle = math.atan2(screenpos.Y - center.Y, screenpos.X - center.X)
                            local tip = Vector2.new(
                                center.X + math.cos(angle) * (arrow_radius + arrow_size),
                                center.Y + math.sin(angle) * (arrow_radius + arrow_size)
                            )
                            local base1 = Vector2.new(
                                tip.X + math.cos(angle + math.pi * 0.75) * arrow_size,
                                tip.Y + math.sin(angle + math.pi * 0.75) * arrow_size
                            )
                            local base2 = Vector2.new(
                                tip.X + math.cos(angle - math.pi * 0.75) * arrow_size,
                                tip.Y + math.sin(angle - math.pi * 0.75) * arrow_size
                            )
                            tri.PointA = tip
                            tri.PointB = base1
                            tri.PointC = base2
                            tri.Visible = true
                        end
                    end
                end
            end
        end

        local function start()
            if render_conn then return end
            render_conn = services.RunService.RenderStepped:Connect(render)
            maid:GiveTask(render_conn)
        end

        local function stop()
            if render_conn then pcall(function() render_conn:Disconnect() end); render_conn = nil end
            if circle then circle.Visible = false end
            for _, a in pairs(arrows_by_player) do a.Visible = false end
        end

        -- UI (Visual → Player Proximity)
        local tab = ui.Tabs.Visual or ui.Tabs["Visual"] or ui.Tabs.Main
        local group = tab:AddLeftGroupbox("Player Proximity", "radar")
        group:AddSlider("ProximityDistanceSlider", {
            Text = "Detection Radius", Default = 250, Min = 0, Max = 1000, Rounding = 1, Compact = true,
        })
        group:AddToggle("ProximityArrowsToggle", { Text = "Proximity Arrows", Default = false })
        group:AddToggle("ProximityCircleToggle", { Text = "FOV Circle", Default = false })

        ui.Toggles.ProximityArrowsToggle:OnChanged(function(v) if v then start() else stop() end end)
        ui.Toggles.ProximityCircleToggle:OnChanged(function() render() end)

        maid:GiveTask(services.Players.PlayerAdded:Connect(ensure_arrow))
        maid:GiveTask(services.Players.PlayerRemoving:Connect(remove_arrow))
        for _, plr in ipairs(services.Players:GetPlayers()) do ensure_arrow(plr) end

        return { Name = "ProximityArrows", Stop = function() stop(); maid:DoCleaning() end }
    end
end
