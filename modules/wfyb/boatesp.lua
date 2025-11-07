-- modules/universal/boatesp.lua
-- ESP for boats in workspace.Boats (WFYB). Drawing if available; highlight + name/tracer otherwise.
do
    return function(ui)
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
        local maid     = Maid.new()

        local drawing_ok = type(Drawing) == "table" and type(Drawing.new) == "function"
        local camera = workspace.CurrentCamera
        local boat_bundles = {} -- model -> {maid=..., highlight, bb, name, tracer, box}

        local function get_boats_folder() return workspace:FindFirstChild("Boats") end

        local function new_bundle(model)
            local b = { maid = Maid.new(), highlight=nil, bb=nil, name=nil, tracer=nil, box=nil }
            local highlight = Instance.new("Highlight")
            highlight.FillTransparency = 1
            highlight.OutlineTransparency = 0
            highlight.Adornee = model
            highlight.Parent = model
            b.highlight = highlight
            b.maid:GiveTask(highlight)

            local pv = model:GetPivot()
            local anchor = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
            local head = anchor or Instance.new("Part")
            if not anchor then b.maid:GiveTask(head) end

            local bb = Instance.new("BillboardGui")
            bb.Size = UDim2.new(0, 200, 0, 22)
            bb.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
            bb.Adornee = head
            bb.AlwaysOnTop = true
            bb.Parent = model
            b.bb = bb
            b.maid:GiveTask(bb)

            local text = Instance.new("TextLabel")
            text.BackgroundTransparency = 1
            text.Size = UDim2.new(1,0,1,0)
            text.Font = Enum.Font.Code
            text.TextSize = 12
            text.TextColor3 = Color3.new(1,1,1)
            text.Text = model.Name
            text.Parent = bb
            b.name = text

            if drawing_ok then
                local line = Drawing.new("Line")
                line.Thickness = 1.5
                line.Visible = false
                b.tracer = line
                b.maid:GiveTask(function() if line and line.Remove then line:Remove() end end)

                local rect = Drawing.new("Square")
                rect.Filled = false
                rect.Thickness = 1
                rect.Visible = false
                b.box = rect
                b.maid:GiveTask(function() if rect and rect.Remove then rect:Remove() end end)
            end

            maid:GiveTask(b.maid)
            return b
        end

        local function ensure_bundle(model)
            if not boat_bundles[model] then
                boat_bundles[model] = new_bundle(model)
                local c = model:GetPropertyChangedSignal("Parent"):Connect(function()
                    if not model.Parent then
                        local b = boat_bundles[model]
                        boat_bundles[model] = nil
                        if b and b.maid then pcall(function() b.maid:DoCleaning() end) end
                    end
                end)
                boat_bundles[model].maid:GiveTask(c)
            end
            return boat_bundles[model]
        end

        local function update_bundle(model, bundle)
            camera = workspace.CurrentCamera
            local folder = get_boats_folder()
            if not (folder and model.Parent == folder) then return end

            local lp = services.Players.LocalPlayer
            local my_hrp = lp and lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
            local pv = model:GetPivot()
            local dist = my_hrp and (pv.Position - my_hrp.Position).Magnitude or 0

            local max_dist = tonumber(ui.Options.BoatESPDistanceSlider and ui.Options.BoatESPDistanceSlider.Value) or 2000
            local show_highlight = ui.Toggles.BoatESPHighlightToggle and ui.Toggles.BoatESPHighlightToggle.Value
            local show_name = ui.Toggles.BoatESPNameDistanceToggle and ui.Toggles.BoatESPNameDistanceToggle.Value
            local show_box = ui.Toggles.BoatESPBoxToggle and ui.Toggles.BoatESPBoxToggle.Value
            local show_tracer = ui.Toggles.BoatESPTracerToggle and ui.Toggles.BoatESPTracerToggle.Value

            local in_range = dist <= max_dist + 1

            -- highlight
            if show_highlight and in_range then
                bundle.highlight.OutlineColor = (ui.Options.BoatESPHighlightColorpicker and ui.Options.BoatESPHighlightColorpicker.Value) or Color3.new(1,1,0)
                bundle.highlight.Enabled = true
            else
                bundle.highlight.Enabled = false
            end

            -- name
            if show_name and in_range then
                bundle.name.Text = string.format("%s (%.0f)", model.Name, dist)
                bundle.name.TextColor3 = (ui.Options.BoatESPNameDistanceColorpicker and ui.Options.BoatESPNameDistanceColorpicker.Value) or Color3.new(1,1,1)
                bundle.bb.Enabled = true
            else
                bundle.bb.Enabled = false
            end

            if drawing_ok then
                local vp = select(1, camera:WorldToViewportPoint(pv.Position))
                local center = Vector2.new(camera.ViewportSize.X/2, camera.ViewportSize.Y)
                if show_tracer and in_range and bundle.tracer then
                    bundle.tracer.Visible = true
                    bundle.tracer.Color = (ui.Options.BoatESPTracerColorpicker and ui.Options.BoatESPTracerColorpicker.Value) or Color3.new(1,1,1)
                    bundle.tracer.From = center
                    bundle.tracer.To = Vector2.new(vp.X, vp.Y)
                else
                    if bundle.tracer then bundle.tracer.Visible = false end
                end
                if show_box and in_range and bundle.box then
                    bundle.box.Visible = true
                    bundle.box.Color = (ui.Options.BoatESPBoxColorpicker and ui.Options.BoatESPBoxColorpicker.Value) or Color3.new(1,1,1)
                    bundle.box.Size = Vector2.new(120, 80)
                    bundle.box.Position = Vector2.new(vp.X - 60, vp.Y - 40)
                else
                    if bundle.box then bundle.box.Visible = false end
                end
            end
        end

        local function step()
            local folder = get_boats_folder()
            if not folder then return end
            for _, model in ipairs(folder:GetChildren()) do
                if model:IsA("Model") then
                    local b = ensure_bundle(model)
                    update_bundle(model, b)
                end
            end
        end

        -- UI (Boat ESP block)
        local group = ui.Tabs.Visual:AddRightGroupbox("Boat ESP", "ship")
        group:AddSlider("BoatESPDistanceSlider", { Text="Max Distance", Default=2000, Min=50, Max=10000, Rounding=0 })

        group:AddToggle("BoatESPHighlightToggle", { Text="Highlight", Default=false })
            :AddColorPicker("BoatESPHighlightColorpicker", { Title="Highlight Color", Default=Color3.fromRGB(255,255,64) })

        group:AddToggle("BoatESPNameDistanceToggle", { Text="Name + Distance", Default=false })
            :AddColorPicker("BoatESPNameDistanceColorpicker", { Title="Name Color", Default=Color3.fromRGB(255,255,255) })

        group:AddToggle("BoatESPBoxToggle", { Text="2D Box (Drawing)", Default=false })
            :AddColorPicker("BoatESPBoxColorpicker", { Title="Box Color", Default=Color3.fromRGB(255,255,255) })

        group:AddToggle("BoatESPTracerToggle", { Text="Tracer (Drawing)", Default=false })
            :AddColorPicker("BoatESPTracerColorpicker", { Title="Tracer Color", Default=Color3.fromRGB(255,255,255) })

        local rs = services.RunService.RenderStepped:Connect(step)
        maid:GiveTask(rs)

        local function stop()
            for m, b in pairs(boat_bundles) do
                if b and b.maid then pcall(function() b.maid:DoCleaning() end) end
                boat_bundles[m] = nil
            end
            maid:DoCleaning()
        end

        return { Name = "BoatESP", Stop = stop }
    end
end
