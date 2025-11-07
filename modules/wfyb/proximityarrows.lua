-- modules/universal/proximityarrows.lua
-- Minimal, executor-friendly proximity visuals (arrows towards nearby players).
do
    return function(ui)
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
        local maid     = Maid.new()

        local drawing_ok = type(Drawing) == "table" and type(Drawing.new) == "function"
        local arrows = {} -- player -> drawing line
        local circle = nil

        local function ensure_circle()
            if circle or not drawing_ok then return end
            local c = Drawing.new("Circle")
            c.NumSides = 64
            c.Radius = 120
            c.Thickness = 1
            c.Filled = false
            c.Visible = false
            circle = c
            maid:GiveTask(function() if circle and circle.Remove then circle:Remove() end; circle = nil end)
        end

        local function get_my_hrp()
            local lp = services.Players.LocalPlayer
            local c = lp and lp.Character
            return c and c:FindFirstChild("HumanoidRootPart")
        end

        local function step()
            local cam = workspace.CurrentCamera; if not cam then return end
            local hrp = get_my_hrp(); if not hrp then return end
            local max_dist = tonumber(ui.Options.ProximityDistanceSlider and ui.Options.ProximityDistanceSlider.Value) or 1500
            local show_arrows = ui.Toggles.ProximityArrowsToggle and ui.Toggles.ProximityArrowsToggle.Value
            local show_circle = ui.Toggles.ProximityCircleToggle and ui.Toggles.ProximityCircleToggle.Value

            if drawing_ok then
                ensure_circle()
                if circle then
                    circle.Visible = show_circle
                    circle.Position = Vector2.new(cam.ViewportSize.X/2, cam.ViewportSize.Y/2)
                end
            end

            for _, plr in ipairs(services.Players:GetPlayers()) do
                if plr ~= services.Players.LocalPlayer then
                    local ch = plr.Character
                    local th = ch and ch:FindFirstChild("HumanoidRootPart")
                    local line = arrows[plr]
                    if show_arrows and drawing_ok and th then
                        local dist = (th.Position - hrp.Position).Magnitude
                        if dist <= max_dist then
                            if not line then
                                line = Drawing.new("Line")
                                line.Thickness = 2
                                arrows[plr] = line
                                maid:GiveTask(function() if line and line.Remove then line:Remove() end; arrows[plr] = nil end)
                            end
                            local vp, on = cam:WorldToViewportPoint(th.Position)
                            local center = Vector2.new(cam.ViewportSize.X/2, cam.ViewportSize.Y/2)
                            local direction = Vector2.new(vp.X, vp.Y) - center
                            if direction.Magnitude > 0 then
                                direction = direction.Unit * 120
                            end
                            line.Visible = true
                            line.From = center
                            line.To = center + direction
                        else
                            if line then line.Visible = false end
                        end
                    else
                        if line then line.Visible = false end
                    end
                end
            end
        end

        -- UI
        local group = ui.Tabs.Visual:AddLeftGroupbox("Proximity", "radar")
        group:AddSlider("ProximityDistanceSlider", { Text="Max Distance", Default=1500, Min=50, Max=10000, Rounding=0 })
        group:AddToggle("ProximityArrowsToggle", { Text="Arrows (Drawing)", Default=false })
        group:AddToggle("ProximityCircleToggle", { Text="Center Circle (Drawing)", Default=false })

        local rs = services.RunService.RenderStepped:Connect(step)
        maid:GiveTask(rs)

        local function stop()
            maid:DoCleaning()
        end

        return { Name = "ProximityArrows", Stop = stop }
    end
end
