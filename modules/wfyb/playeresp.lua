-- modules/universal/playeresp.lua
do
    return function(ui)
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local maid = Maid.new()
        local player_maids = setmetatable({}, { __mode = "k" })
        local drawings_by_player = {}
        local render_conn

        local name_size, health_size = 12, 12
        local health_bar_w, health_bar_h = 50, 5
        local highlight_outline_t = 0
        local buffer, y_offset = 4, 30

        local function add_drawing_cleanup(m, obj)
            m:GiveTask(function()
                pcall(function()
                    if obj and obj.Remove then obj:Remove() end
                end)
            end)
            return obj
        end

        local function get_player_maid(plr)
            local m = player_maids[plr]
            if not m then m = Maid.new(); player_maids[plr] = m end
            return m
        end

        local function create_drawing(t, props)
            local d = Drawing.new(t)
            for k, v in pairs(props) do d[k] = v end
            return d
        end

        local function add_highlight(plr, color, transp)
            if plr == services.Players.LocalPlayer then return end
            local char = plr.Character
            if not char then return end
            local hl = char:FindFirstChild("Player_ESP")
            if not hl then
                hl = Instance.new("Highlight")
                hl.Name = "Player_ESP"
                hl.FillColor = color
                hl.FillTransparency = transp
                hl.OutlineTransparency = highlight_outline_t
                get_player_maid(plr):GiveTask(hl)
                hl.Parent = char
            else
                hl.FillColor = color
                hl.FillTransparency = transp
            end
        end

        local function remove_highlight(plr)
            local char = plr and plr.Character
            if not char then return end
            local hl = char:FindFirstChild("Player_ESP")
            if hl then hl:Destroy() end
        end

        local function ensure_esp(plr)
            if plr == services.Players.LocalPlayer then return end
            if drawings_by_player[plr] then return end
            local m = get_player_maid(plr)
            drawings_by_player[plr] = {
                name = add_drawing_cleanup(m, create_drawing("Text",   { Size=name_size, Center=true,  Outline=true,  Visible=false })),
                htxt = add_drawing_cleanup(m, create_drawing("Text",   { Size=health_size, Center=true, Outline=true, Visible=false })),
                hbg  = add_drawing_cleanup(m, create_drawing("Square", { Filled=true, Color=Color3.new(0,0,0), Visible=false })),
                hfg  = add_drawing_cleanup(m, create_drawing("Square", { Filled=true, Color=Color3.fromRGB(0,255,0), Visible=false })),
                box  = {
                    add_drawing_cleanup(m, create_drawing("Line", {Thickness=1, Visible=false})),
                    add_drawing_cleanup(m, create_drawing("Line", {Thickness=1, Visible=false})),
                    add_drawing_cleanup(m, create_drawing("Line", {Thickness=1, Visible=false})),
                    add_drawing_cleanup(m, create_drawing("Line", {Thickness=1, Visible=false})),
                },
                tracer = add_drawing_cleanup(m, create_drawing("Line", {Thickness=1, Visible=false}))
            }
        end

        local function clear_esp(plr)
            local d = drawings_by_player[plr]
            if d then
                for _, v in pairs(d) do
                    if typeof(v) == "table" then
                        for _, l in ipairs(v) do pcall(function() l.Visible = false end) end
                    else
                        pcall(function() v.Visible = false end)
                    end
                end
                drawings_by_player[plr] = nil
            end
        end

        local function any_enabled()
            return ui.Toggles.PlayerESPHighlightToggle and ui.Toggles.PlayerESPHighlightToggle.Value
                or ui.Toggles.PlayerESPNameDistanceToggle and ui.Toggles.PlayerESPNameDistanceToggle.Value
                or ui.Toggles.PlayerESPHealthBarToggle and ui.Toggles.PlayerESPHealthBarToggle.Value
                or ui.Toggles.PlayerESPHealthTextToggle and ui.Toggles.PlayerESPHealthTextToggle.Value
                or ui.Toggles.PlayerESPTracerToggle and ui.Toggles.PlayerESPTracerToggle.Value
                or ui.Toggles.PlayerESPBoxToggle and ui.Toggles.PlayerESPBoxToggle.Value
        end

        local function render_step()
            local cam = services.Workspace.CurrentCamera
            if not cam then return end
            local vp = cam.ViewportSize

            for _, plr in ipairs(services.Players:GetPlayers()) do
                if plr ~= services.Players.LocalPlayer then
                    local char = plr.Character
                    local hrp = char and char:FindFirstChild("HumanoidRootPart")
                    local hum = char and char:FindFirstChildOfClass("Humanoid")
                    local d = drawings_by_player[plr]
                    if not (char and hrp and hum) then
                        if d then
                            -- hide all if missing
                            clear_esp(plr)
                        end
                    else
                        ensure_esp(plr)
                        d = drawings_by_player[plr]
                        local pos, on_screen = cam:WorldToViewportPoint(hrp.Position)
                        local head = char:FindFirstChild("Head")
                        local tl, _ = cam:WorldToViewportPoint((hrp.CFrame * CFrame.new(-2, 3, 0)).Position)
                        local br, _ = cam:WorldToViewportPoint((hrp.CFrame * CFrame.new(2, -3, 0)).Position)

                        -- Name + distance
                        if ui.Toggles.PlayerESPNameDistanceToggle and ui.Toggles.PlayerESPNameDistanceToggle.Value and on_screen then
                            local dist = (cam.CFrame.Position - hrp.Position).Magnitude
                            d.name.Text = string.format("%s [%.0f]", plr.Name, dist)
                            d.name.Color = ui.Options.PlayerESPNameDistanceColorpicker and ui.Options.PlayerESPNameDistanceColorpicker.Value or Color3.new(1,1,1)
                            d.name.Position = Vector2.new(pos.X, pos.Y - y_offset)
                            d.name.Visible = true
                        else
                            d.name.Visible = false
                        end

                        -- Health bar + text
                        if ui.Toggles.PlayerESPHealthBarToggle and ui.Toggles.PlayerESPHealthBarToggle.Value and on_screen then
                            local hp = math.clamp(hum.Health, 0, hum.MaxHealth)
                            local ratio = hum.MaxHealth > 0 and (hp / hum.MaxHealth) or 0
                            local w = health_bar_w
                            local h = health_bar_h
                            local x = pos.X - w/2
                            local y = pos.Y - y_offset + 12
                            d.hbg.Position = Vector2.new(x, y)
                            d.hbg.Size = Vector2.new(w, h)
                            d.hbg.Visible = true

                            d.hfg.Position = Vector2.new(x, y)
                            d.hfg.Size = Vector2.new(w * ratio, h)
                            d.hfg.Visible = true

                            if ui.Toggles.PlayerESPHealthTextToggle and ui.Toggles.PlayerESPHealthTextToggle.Value then
                                d.htxt.Text = string.format("%d/%d", hp, hum.MaxHealth)
                                d.htxt.Position = Vector2.new(pos.X, y + h + 10)
                                d.htxt.Visible = true
                            else
                                d.htxt.Visible = false
                            end
                        else
                            d.hbg.Visible = false
                            d.hfg.Visible = false
                            d.htxt.Visible = false
                        end

                        -- Box
                        if ui.Toggles.PlayerESPBoxToggle and ui.Toggles.PlayerESPBoxToggle.Value and on_screen then
                            local c = ui.Options.PlayerESPBoxColorpicker and ui.Options.PlayerESPBoxColorpicker.Value or Color3.new(1,1,1)
                            d.box[1].From = Vector2.new(tl.X, tl.Y); d.box[1].To = Vector2.new(br.X, tl.Y); d.box[1].Color = c; d.box[1].Visible = true
                            d.box[2].From = Vector2.new(br.X, tl.Y); d.box[2].To = Vector2.new(br.X, br.Y); d.box[2].Color = c; d.box[2].Visible = true
                            d.box[3].From = Vector2.new(br.X, br.Y); d.box[3].To = Vector2.new(tl.X, br.Y); d.box[3].Color = c; d.box[3].Visible = true
                            d.box[4].From = Vector2.new(tl.X, br.Y); d.box[4].To = Vector2.new(tl.X, tl.Y); d.box[4].Color = c; d.box[4].Visible = true
                        else
                            for _, ln in ipairs(d.box) do ln.Visible = false end
                        end

                        -- Tracer
                        if ui.Toggles.PlayerESPTracerToggle and ui.Toggles.PlayerESPTracerToggle.Value and on_screen then
                            local c = ui.Options.PlayerESPTracerColorpicker and ui.Options.PlayerESPTracerColorpicker.Value or Color3.new(1,1,1)
                            d.tracer.From = Vector2.new(vp.X/2, vp.Y - 2)
                            d.tracer.To   = Vector2.new((tl.X + br.X)/2, br.Y)
                            d.tracer.Color = c
                            d.tracer.Visible = true
                        else
                            d.tracer.Visible = false
                        end
                    end
                end
            end
        end

        local function start_render()
            if render_conn or not any_enabled() then return end
            render_conn = services.RunService.RenderStepped:Connect(render_step)
            maid:GiveTask(render_conn)
        end

        local function stop_render()
            if render_conn then
                pcall(function() render_conn:Disconnect() end)
                render_conn = nil
            end
        end

        -- UI: Visual → Player ESP (exact keys from prompt.lua)
        local tab = ui.Tabs.Visual or ui.Tabs["Visual"] or (ui.Tabs.Main or ui.Tabs.Misc)
        local group = tab:AddLeftGroupbox("Player ESP", "scan-eye")

        local t = group:AddToggle("PlayerESPHighlightToggle", { Text = "Highlights", Default = false })
        t:AddColorPicker("PlayerESPHighlightColorpicker", { Default = Color3.fromRGB(255, 0, 0), Title = "Highlight Color", Transparency = 0.5 })

        local n = group:AddToggle("PlayerESPNameDistanceToggle", { Text = "Name & Distance", Default = false })
        n:AddColorPicker("PlayerESPNameDistanceColorpicker", { Default = Color3.fromRGB(255, 255, 255), Title = "Name Color", Transparency = 0 })

        local b = group:AddToggle("PlayerESPBoxToggle", { Text = "Boxes", Default = false })
        b:AddColorPicker("PlayerESPBoxColorpicker", { Default = Color3.fromRGB(255, 255, 255), Title = "Box Color", Transparency = 0 })

        local tr = group:AddToggle("PlayerESPTracerToggle", { Text = "Tracers", Default = false })
        tr:AddColorPicker("PlayerESPTracerColorpicker", { Default = Color3.fromRGB(255, 255, 255), Title = "Tracer Color", Transparency = 0 })

        group:AddToggle("PlayerESPHealthBarToggle", { Text = "Show Health Bar", Default = false })
        group:AddToggle("PlayerESPHealthTextToggle", { Text = "Show Health", Default = false })

        -- Reactivity: highlight color live update
        if ui.Options.PlayerESPHighlightColorpicker then
            ui.Options.PlayerESPHighlightColorpicker:OnChanged(function()
                local color = ui.Options.PlayerESPHighlightColorpicker.Value
                local trn   = ui.Options.PlayerESPHighlightColorpicker.Transparency
                for _, plr in ipairs(services.Players:GetPlayers()) do
                    if ui.Toggles.PlayerESPHighlightToggle.Value then
                        add_highlight(plr, color, trn)
                    end
                end
            end)
        end

        -- Toggle wiring
        local function recheck()
            -- highlights
            if ui.Toggles.PlayerESPHighlightToggle and ui.Toggles.PlayerESPHighlightToggle.Value then
                local color = ui.Options.PlayerESPHighlightColorpicker and ui.Options.PlayerESPHighlightColorpicker.Value or Color3.new(1,0,0)
                local trn = ui.Options.PlayerESPHighlightColorpicker and ui.Options.PlayerESPHighlightColorpicker.Transparency or 0.5
                for _, p in ipairs(services.Players:GetPlayers()) do add_highlight(p, color, trn) end
            else
                for _, p in ipairs(services.Players:GetPlayers()) do remove_highlight(p) end
            end
            -- drawings
            if any_enabled() then start_render() else stop_render(); for plr in pairs(drawings_by_player) do clear_esp(plr) end end
        end

        for _, key in ipairs({
            "PlayerESPHighlightToggle","PlayerESPNameDistanceToggle","PlayerESPHealthBarToggle",
            "PlayerESPHealthTextToggle","PlayerESPTracerToggle","PlayerESPBoxToggle"
        }) do
            if ui.Toggles[key] then ui.Toggles[key]:OnChanged(recheck) end
        end

        -- lifecycle for players
        maid:GiveTask(services.Players.PlayerAdded:Connect(function(plr)
            if plr == services.Players.LocalPlayer then return end
            ensure_esp(plr)
            if ui.Toggles.PlayerESPHighlightToggle and ui.Toggles.PlayerESPHighlightToggle.Value then
                local color = ui.Options.PlayerESPHighlightColorpicker and ui.Options.PlayerESPHighlightColorpicker.Value or Color3.new(1,0,0)
                local trn = ui.Options.PlayerESPHighlightColorpicker and ui.Options.PlayerESPHighlightColorpicker.Transparency or 0.5
                add_highlight(plr, color, trn)
            end
        end))
        maid:GiveTask(services.Players.PlayerRemoving:Connect(function(plr)
            clear_esp(plr)
            remove_highlight(plr)
            local m = player_maids[plr]
            if m then m:DoCleaning(); player_maids[plr] = nil end
        end))

        -- seed
        for _, plr in ipairs(services.Players:GetPlayers()) do
            if plr ~= services.Players.LocalPlayer then ensure_esp(plr) end
        end
        recheck()

        return { Name = "PlayerESP", Stop = function()
            stop_render()
            for plr, _ in pairs(drawings_by_player) do clear_esp(plr) end
            for _, plr in ipairs(services.Players:GetPlayers()) do remove_highlight(plr) end
            maid:DoCleaning()
        end }
    end
end
