-- modules/universal/playeresp.lua
-- Supports: highlight, name+distance, health bar/text, tracer, box.
-- Uses Drawing if available; otherwise falls back to Highlight + BillboardGuis.
do
    return function(ui)
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
        local maid     = Maid.new()

        local drawing_ok = type(Drawing) == "table" and type(Drawing.new) == "function"
        local camera = workspace.CurrentCamera

        local function get_head(hrp)
            local ch = hrp and hrp.Parent
            return ch and ch:FindFirstChild("Head")
        end

        local function get_humanoid(ch)
            return ch and ch:FindFirstChildOfClass("Humanoid")
        end

        -- --- Per-player bundle
        local function new_bundle(character)
            local bundle = { maid = Maid.new(), highlight=nil, bb=nil, name=nil, health=nil, box=nil, tracer=nil }
            -- highlight
            bundle.highlight = Instance.new("Highlight")
            bundle.highlight.FillTransparency = 1
            bundle.highlight.OutlineTransparency = 0
            bundle.highlight.Adornee = character
            bundle.highlight.Parent = character
            bundle.maid:GiveTask(bundle.highlight)

            -- billboard for text/health
            local head = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
            local bb = Instance.new("BillboardGui")
            bb.Name = "ESP_BB"
            bb.Adornee = head
            bb.Size = UDim2.new(0, 200, 0, 60)
            bb.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
            bb.AlwaysOnTop = true
            bb.Parent = head
            bundle.maid:GiveTask(bb)
            bundle.bb = bb

            local name = Instance.new("TextLabel")
            name.Name = "NameDistance"
            name.BackgroundTransparency = 1
            name.Size = UDim2.new(1,0,0,20)
            name.Position = UDim2.new(0,0,0,0)
            name.Font = Enum.Font.Code
            name.TextScaled = false
            name.TextSize = 12
            name.TextColor3 = Color3.new(1,1,1)
            name.TextStrokeTransparency = 0.5
            name.Parent = bb
            bundle.name = name

            local health = Instance.new("TextLabel")
            health.Name = "HealthText"
            health.BackgroundTransparency = 1
            health.Size = UDim2.new(1,0,0,18)
            health.Position = UDim2.new(0,0,0,18)
            health.Font = Enum.Font.Code
            health.TextScaled = false
            health.TextSize = 12
            health.TextColor3 = Color3.new(0,1,0)
            health.TextStrokeTransparency = 0.5
            health.Parent = bb
            bundle.health = health

            if drawing_ok then
                local line = Drawing.new("Line")
                line.Thickness = 1.5
                line.Visible = false
                bundle.tracer = line
                bundle.maid:GiveTask(function() if line and line.Remove then line:Remove() end end)

                local rect = Drawing.new("Square")
                rect.Thickness = 1
                rect.Filled = false
                rect.Visible = false
                bundle.box = rect
                bundle.maid:GiveTask(function() if rect and rect.Remove then rect:Remove() end end)
            end

            -- cleanup
            maid:GiveTask(bundle.maid)
            return bundle
        end

        local bundles = {} -- character -> bundle

        local function get_distance(a, b)
            if not (a and b) then return 0 end
            return (a.Position - b.Position).Magnitude
        end

        local function color_from_option(opt)
            local c = Color3.new(1,1,1)
            if opt and opt.Value then c = opt.Value end
            return c
        end

        local function update_bundle(plr, ch, bundle)
            if not (camera and ch and ch.Parent) then return end
            local hrp = ch:FindFirstChild("HumanoidRootPart")
            local hum = get_humanoid(ch)
            if not hrp then return end

            local root_pos = hrp.Position
            local head = get_head(hrp)
            local lp = services.Players.LocalPlayer
            local my_hrp = lp and lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
            local dist = my_hrp and get_distance(hrp, my_hrp) or 0

            -- visibility toggles from UI
            local max_dist = tonumber(ui.Options.PlayerESPDistanceSlider and ui.Options.PlayerESPDistanceSlider.Value) or 1500
            local show_highlight = ui.Toggles.PlayerESPHighlightToggle and ui.Toggles.PlayerESPHighlightToggle.Value
            local show_name = ui.Toggles.PlayerESPNameDistanceToggle and ui.Toggles.PlayerESPNameDistanceToggle.Value
            local show_box = ui.Toggles.PlayerESPBoxToggle and ui.Toggles.PlayerESPBoxToggle.Value
            local show_tracer = ui.Toggles.PlayerESPTracerToggle and ui.Toggles.PlayerESPTracerToggle.Value
            local show_hbar = ui.Toggles.PlayerESPHealthBarToggle and ui.Toggles.PlayerESPHealthBarToggle.Value
            local show_htext = ui.Toggles.PlayerESPHealthTextToggle and ui.Toggles.PlayerESPHealthTextToggle.Value

            local in_range = dist <= max_dist + 1

            -- highlight color
            if show_highlight and in_range then
                local outline = color_from_option(ui.Options.PlayerESPHighlightColorpicker)
                bundle.highlight.OutlineColor = outline
                bundle.highlight.Enabled = true
            else
                bundle.highlight.Enabled = false
            end

            -- name + distance
            do
                bundle.bb.Enabled = show_name or show_hbar or show_htext
                if show_name and in_range then
                    local name_color = color_from_option(ui.Options.PlayerESPNameDistanceColorpicker)
                    bundle.name.Text = string.format("%s  (%.0f)", plr.Name, dist)
                    bundle.name.TextColor3 = name_color
                    bundle.name.Visible = true
                else
                    bundle.name.Visible = false
                end

                local hp = hum and hum.Health or 0
                local mh = hum and hum.MaxHealth or 100
                if show_htext and in_range then
                    bundle.health.Text = string.format("HP: %d / %d", math.floor(hp), math.floor(mh))
                    bundle.health.TextColor3 = Color3.new(0,1,0)
                    bundle.health.Visible = true
                else
                    bundle.health.Visible = false
                end
            end

            if drawing_ok then
                -- 2D positions
                local hrp2d, on1 = camera:WorldToViewportPoint(root_pos)
                local head2d = head and select(1, camera:WorldToViewportPoint(head.Position)) or hrp2d
                local bottom2d = select(1, camera:WorldToViewportPoint(root_pos - Vector3.new(0, -3, 0)))
                local screen_center = Vector2.new(camera.ViewportSize.X/2, camera.ViewportSize.Y)

                if show_tracer and in_range then
                    local line = bundle.tracer
                    line.Visible = on1
                    line.Color = color_from_option(ui.Options.PlayerESPTracerColorpicker)
                    line.From = screen_center
                    line.To = Vector2.new(hrp2d.X, hrp2d.Y)
                else
                    if bundle.tracer then bundle.tracer.Visible = false end
                end

                if show_box and in_range then
                    local rect = bundle.box
                    rect.Visible = on1
                    rect.Color = color_from_option(ui.Options.PlayerESPBoxColorpicker)
                    local height = math.abs(head2d.Y - bottom2d.Y)
                    local width = height * 0.6
                    rect.Size = Vector2.new(width, height)
                    rect.Position = Vector2.new(hrp2d.X - width/2, head2d.Y)
                else
                    if bundle.box then bundle.box.Visible = false end
                end
            end
        end

        -- attach for all enemies (all players except local)
        local function ensure_bundle(plr)
            local ch = plr.Character
            if not ch then return end
            if not bundles[ch] then
                bundles[ch] = new_bundle(ch)
                local con_added = ch:GetPropertyChangedSignal("Parent"):Connect(function()
                    if not ch.Parent then
                        local b = bundles[ch]
                        bundles[ch] = nil
                        if b and b.maid then pcall(function() b.maid:DoCleaning() end) end
                    end
                end)
                bundles[ch].maid:GiveTask(con_added)
            end
        end

        -- UI
        local group = ui.Tabs.Visual:AddLeftGroupbox("Player ESP", "binoculars")
        group:AddSlider("PlayerESPDistanceSlider", { Text="Max Distance", Default=1500, Min=50, Max=10000, Rounding=0 })

        group:AddToggle("PlayerESPHighlightToggle", { Text="Highlight", Default=false })
            :AddColorPicker("PlayerESPHighlightColorpicker", { Title="Highlight Color", Default = Color3.fromRGB(255, 64, 64) })

        group:AddToggle("PlayerESPNameDistanceToggle", { Text="Name + Distance", Default=false })
            :AddColorPicker("PlayerESPNameDistanceColorpicker", { Title="Name Color", Default = Color3.fromRGB(255,255,255) })

        group:AddToggle("PlayerESPBoxToggle", { Text="2D Box (Drawing)", Default=false })
            :AddColorPicker("PlayerESPBoxColorpicker", { Title="Box Color", Default = Color3.fromRGB(255,255,255) })

        group:AddToggle("PlayerESPTracerToggle", { Text="Tracer (Drawing)", Default=false })
            :AddColorPicker("PlayerESPTracerColorpicker", { Title="Tracer Color", Default = Color3.fromRGB(255,255,255) })

        group:AddToggle("PlayerESPHealthBarToggle", { Text="Health Bar", Default=false })
        group:AddToggle("PlayerESPHealthTextToggle", { Text="Health Text", Default=false })

        -- render/update
        local rs = services.RunService.RenderStepped:Connect(function()
            camera = workspace.CurrentCamera
            for _, plr in ipairs(services.Players:GetPlayers()) do
                if plr ~= services.Players.LocalPlayer then
                    ensure_bundle(plr)
                    local ch = plr.Character
                    local b = ch and bundles[ch]
                    if b then update_bundle(plr, ch, b) end
                end
            end
        end)
        maid:GiveTask(rs)

        local function stop()
            for ch, b in pairs(bundles) do
                if b and b.maid then pcall(function() b.maid:DoCleaning() end) end
                bundles[ch] = nil
            end
            maid:DoCleaning()
        end

        return { Name = "PlayerESP", Stop = stop }
    end
end
