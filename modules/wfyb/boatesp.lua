-- modules/universal/boatesp.lua
do
    return function(ui)
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local maid = Maid.new()
        local boat_maids = setmetatable({}, { __mode = "k" })
        local esp_data_by_model = {}
        local render_conn

        local function get_boats_folder()
            return services.Workspace:FindFirstChild("Boats")
        end

        local function is_boat_model(inst)
            if not (typeof(inst) == "Instance" and inst:IsA("Model")) then return false end
            if inst:FindFirstChild("BoatData") then return true end
            if string.find(string.lower(inst.Name), "boat") then return true end
            return false
        end

        local function boat_label(m)
            local data = m:FindFirstChild("BoatData")
            local owner, name
            if data then
                local ov = data:FindFirstChild("Owner")
                local nv = data:FindFirstChild("UnfilteredBoatName")
                if ov and ov:IsA("ObjectValue") and ov.Value then owner = ov.Value.Name end
                if nv and nv:IsA("StringValue") then name = nv.Value end
            end
            if name and owner then return string.format("%s (%s)", name, owner) end
            if name then return name end
            return m.Name
        end

        local function add_drawing_cleanup(m, obj)
            m:GiveTask(function() pcall(function() if obj and obj.Remove then obj:Remove() end end) end)
            return obj
        end

        local function ensure_esp(m)
            if esp_data_by_model[m] then return end
            local pm = boat_maids[m]; if not pm then pm = Maid.new(); boat_maids[m] = pm end

            esp_data_by_model[m] = {
                name = add_drawing_cleanup(pm, Drawing.new("Text")),
                box  = {
                    add_drawing_cleanup(pm, Drawing.new("Line")),
                    add_drawing_cleanup(pm, Drawing.new("Line")),
                    add_drawing_cleanup(pm, Drawing.new("Line")),
                    add_drawing_cleanup(pm, Drawing.new("Line")),
                },
                tracer = add_drawing_cleanup(pm, Drawing.new("Line")),
                highlight = nil,
            }
            esp_data_by_model[m].name.Visible = false
            esp_data_by_model[m].tracer.Visible = false
            for _, ln in ipairs(esp_data_by_model[m].box) do ln.Visible = false end
        end

        local function remove_esp(m)
            local d = esp_data_by_model[m]
            if d then
                d.name.Visible = false
                d.tracer.Visible = false
                for _, ln in ipairs(d.box) do ln.Visible = false end
                esp_data_by_model[m] = nil
            end
        end

        local function ensure_highlight(m, color, trn)
            local h = m:FindFirstChild("Boat_ESP")
            if not h then
                h = Instance.new("Highlight")
                h.Name = "Boat_ESP"
                h.OutlineTransparency = 0
                h.Parent = m
            end
            h.FillColor = color
            h.FillTransparency = trn
            return h
        end

        local function remove_highlight(m)
            local h = m:FindFirstChild("Boat_ESP")
            if h then h:Destroy() end
        end

        local function any_enabled()
            return (ui.Toggles.BoatESPNameDistanceToggle and ui.Toggles.BoatESPNameDistanceToggle.Value)
                or (ui.Toggles.BoatESPBoxToggle and ui.Toggles.BoatESPBoxToggle.Value)
                or (ui.Toggles.BoatESPTracerToggle and ui.Toggles.BoatESPTracerToggle.Value)
        end

        local function render()
            local cam = services.Workspace.CurrentCamera
            if not cam then return end
            local vp = cam.ViewportSize
            local maxdist = tonumber(ui.Options.BoatESPDistanceSlider and ui.Options.BoatESPDistanceSlider.Value) or 12500
            local boxcolor = ui.Options.BoatESPBoxColorpicker and ui.Options.BoatESPBoxColorpicker.Value or Color3.new(1,1,1)
            local tracercolor = ui.Options.BoatESPTracerColorpicker and ui.Options.BoatESPTracerColorpicker.Value or Color3.new(1,1,1)
            local namecolor = ui.Options.BoatESPNameDistanceColorpicker and ui.Options.BoatESPNameDistanceColorpicker.Value or Color3.new(1,1,1)

            local lplr = services.Players.LocalPlayer
            local lhrp = lplr and lplr.Character and lplr.Character:FindFirstChild("HumanoidRootPart")

            local boats = get_boats_folder()
            if not boats then return end

            for _, m in ipairs(boats:GetChildren()) do
                if is_boat_model(m) then
                    ensure_esp(m)
                    local d = esp_data_by_model[m]
                    local pivot = nil
                    pcall(function() pivot = m:GetPivot() end)
                    if not pivot then
                        local pp = m.PrimaryPart
                        if pp then pivot = pp.CFrame end
                    end
                    if not pivot then
                        d.name.Visible = false
                        d.tracer.Visible = false
                        for _, ln in ipairs(d.box) do ln.Visible = false end
                    else
                        local pos, onscreen = cam:WorldToViewportPoint(pivot.Position)
                        local dist = lhrp and (pivot.Position - lhrp.Position).Magnitude or 0

                        -- Name distance
                        if ui.Toggles.BoatESPNameDistanceToggle and ui.Toggles.BoatESPNameDistanceToggle.Value and onscreen and dist <= maxdist then
                            d.name.Text = string.format("%s [%.0f]", boat_label(m), dist)
                            d.name.Color = namecolor
                            d.name.Position = Vector2.new(pos.X, pos.Y - 25)
                            d.name.Visible = true
                        else
                            d.name.Visible = false
                        end

                        -- Box (approx)
                        if ui.Toggles.BoatESPBoxToggle and ui.Toggles.BoatESPBoxToggle.Value and onscreen and dist <= maxdist then
                            local tl = cam:WorldToViewportPoint((pivot * CFrame.new(-6, 6, 0)).Position)
                            local br = cam:WorldToViewportPoint((pivot * CFrame.new( 6,-6, 0)).Position)
                            d.box[1].From = Vector2.new(tl.X, tl.Y); d.box[1].To = Vector2.new(br.X, tl.Y); d.box[1].Color = boxcolor; d.box[1].Visible = true
                            d.box[2].From = Vector2.new(br.X, tl.Y); d.box[2].To = Vector2.new(br.X, br.Y); d.box[2].Color = boxcolor; d.box[2].Visible = true
                            d.box[3].From = Vector2.new(br.X, br.Y); d.box[3].To = Vector2.new(tl.X, br.Y); d.box[3].Color = boxcolor; d.box[3].Visible = true
                            d.box[4].From = Vector2.new(tl.X, br.Y); d.box[4].To = Vector2.new(tl.X, tl.Y); d.box[4].Color = boxcolor; d.box[4].Visible = true
                        else
                            for _, ln in ipairs(d.box) do ln.Visible = false end
                        end

                        -- Tracer
                        if ui.Toggles.BoatESPTracerToggle and ui.Toggles.BoatESPTracerToggle.Value and onscreen and dist <= maxdist then
                            d.tracer.From = Vector2.new(vp.X/2, vp.Y - 2)
                            d.tracer.To   = Vector2.new(pos.X, pos.Y)
                            d.tracer.Color = tracercolor
                            d.tracer.Visible = true
                        else
                            d.tracer.Visible = false
                        end
                    end
                end
            end
        end

        local function refresh_all_highlights()
            if not (ui.Toggles.BoatESPHighlightToggle and ui.Toggles.BoatESPHighlightToggle.Value) then
                local boats = get_boats_folder()
                if boats then
                    for _, m in ipairs(boats:GetChildren()) do
                        if is_boat_model(m) then remove_highlight(m) end
                    end
                end
                return
            end
            local color = ui.Options.BoatESPHighlightColorpicker and ui.Options.BoatESPHighlightColorpicker.Value or Color3.new(0,0,0)
            local trn   = ui.Options.BoatESPHighlightColorpicker and ui.Options.BoatESPHighlightColorpicker.Transparency or 0.5
            local boats = get_boats_folder()
            if not boats then return end
            for _, m in ipairs(boats:GetChildren()) do
                if is_boat_model(m) then ensure_highlight(m, color, trn) end
            end
        end

        local function start_render()
            if render_conn or not any_enabled() then return end
            render_conn = services.RunService.RenderStepped:Connect(render)
            maid:GiveTask(render_conn)
        end

        local function stop_render()
            if render_conn then pcall(function() render_conn:Disconnect() end); render_conn = nil end
            for _, d in pairs(esp_data_by_model) do
                d.name.Visible = false
                d.tracer.Visible = false
                for _, l in ipairs(d.box) do l.Visible = false end
            end
        end

        local function recheck()
            if any_enabled() then start_render() else stop_render() end
        end

        -- UI (Visual → Boat ESP)
        local tab = ui.Tabs.Visual or ui.Tabs["Visual"] or ui.Tabs.Main
        local group = tab:AddLeftGroupbox("Boat ESP", "sailboat")
        group:AddSlider("BoatESPDistanceSlider", { Text = "Boat ESP Distance", Default=12500, Min=0, Max=25000, Rounding=1, Compact=true })
        local h = group:AddToggle("BoatESPHighlightToggle", { Text = "Highlights", Default = false })
        h:AddColorPicker("BoatESPHighlightColorpicker", { Default = Color3.fromRGB(0,0,0), Title="Highlight Color", Transparency=0.5 })
        local nd = group:AddToggle("BoatESPNameDistanceToggle", { Text = "Boat Name & Distance", Default = false })
        nd:AddColorPicker("BoatESPNameDistanceColorpicker", { Default = Color3.fromRGB(255,255,255), Title="Name Color", Transparency=0 })
        local bx = group:AddToggle("BoatESPBoxToggle", { Text = "Boxes", Default = false })
        bx:AddColorPicker("BoatESPBoxColorpicker", { Default = Color3.fromRGB(255,255,255), Title="Box Color", Transparency=0 })
        local tr = group:AddToggle("BoatESPTracerToggle", { Text = "Tracers", Default = false })
        tr:AddColorPicker("BoatESPTracerColorpicker", { Default = Color3.fromRGB(255,255,255), Title="Tracer Color", Transparency=0 })

        -- Wiring & folder watchers
        if ui.Options.BoatESPHighlightColorpicker then
            ui.Options.BoatESPHighlightColorpicker:OnChanged(refresh_all_highlights)
        end
        if ui.Toggles.BoatESPHighlightToggle then
            ui.Toggles.BoatESPHighlightToggle:OnChanged(function() refresh_all_highlights(); recheck() end)
        end
        for _, key in ipairs({ "BoatESPNameDistanceToggle", "BoatESPBoxToggle", "BoatESPTracerToggle" }) do
            if ui.Toggles[key] then ui.Toggles[key]:OnChanged(recheck) end
        end
        if ui.Options.BoatESPDistanceSlider then ui.Options.BoatESPDistanceSlider:OnChanged(function() render() end) end

        local boats = get_boats_folder()
        if boats then
            maid:GiveTask(boats.DescendantAdded:Connect(function(inst)
                if inst:IsA("Model") then
                    if is_boat_model(inst) then ensure_esp(inst) end
                end
            end))
            maid:GiveTask(boats.DescendantRemoving:Connect(function(inst)
                if inst:IsA("Model") and is_boat_model(inst) then
                    local bm = boat_maids[inst]; if bm then bm:DoCleaning(); boat_maids[inst] = nil end
                    remove_esp(inst); remove_highlight(inst)
                end
            end))
            for _, inst in ipairs(boats:GetDescendants()) do if inst:IsA("Model") and is_boat_model(inst) then ensure_esp(inst) end end
        end

        refresh_all_highlights(); recheck()

        return { Name = "BoatESP", Stop = function() stop_render(); maid:DoCleaning() end }
    end
end
