-- modules/universal/boatesp.lua
do
    return function(UI)
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local Variables = {
            Maids = { BoatESP = Maid.new() },
            BoatMaids = setmetatable({}, { __mode = "k" }),
            BoatESPDistanceSlider = "BoatESPDistanceSlider",
        }

        local function GetBoatMaid(model)
            local m = Variables.BoatMaids[model]
            if not m then m = Maid.new(); Variables.BoatMaids[model] = m end
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

        local function createForBoat(model)
            local bm = GetBoatMaid(model)
            bm:DoCleaning()

            local highlight = Instance.new("Highlight")
            highlight.FillTransparency = 1
            highlight.OutlineTransparency = 0
            highlight.Parent = services.CoreGui
            bm:GiveTask(highlight)

            local nameText = AddDrawingCleanup(bm, Drawing.new("Text"))
            local tracer   = AddDrawingCleanup(bm, Drawing.new("Line"))
            local boxLineTop    = AddDrawingCleanup(bm, Drawing.new("Line"))
            local boxLineBottom = AddDrawingCleanup(bm, Drawing.new("Line"))
            local boxLineLeft   = AddDrawingCleanup(bm, Drawing.new("Line"))
            local boxLineRight  = AddDrawingCleanup(bm, Drawing.new("Line"))

            local function step()
                local camera = services.Workspace.CurrentCamera
                local hrp = services.Players.LocalPlayer and services.Players.LocalPlayer.Character and services.Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                local maxDistOpt = UI.Options and UI.Options[Variables.BoatESPDistanceSlider] and UI.Options[Variables.BoatESPDistanceSlider].Value
                local maxDist = tonumber(maxDistOpt) or 8000

                if not camera or not hrp or not model or not model.Parent then
                    highlight.Adornee = nil
                    nameText.Visible = false
                    tracer.Visible = false
                    boxLineTop.Visible = false
                    boxLineBottom.Visible = false
                    boxLineLeft.Visible = false
                    boxLineRight.Visible = false
                    return
                end

                local pivotOk, pivot = pcall(model.GetPivot, model)
                local pos = pivotOk and pivot.Position or (model.PrimaryPart and model.PrimaryPart.Position)
                if not pos then
                    highlight.Adornee = nil
                    nameText.Visible = false
                    tracer.Visible = false
                    boxLineTop.Visible = false
                    boxLineBottom.Visible = false
                    boxLineLeft.Visible = false
                    boxLineRight.Visible = false
                    return
                end

                local dist = (camera.CFrame.Position - pos).Magnitude
                local within = dist <= maxDist

                -- highlight toggle
                local showHL = UI.Toggles and UI.Toggles.BoatESPHighlightToggle and UI.Toggles.BoatESPHighlightToggle.Value and within
                highlight.Adornee = showHL and model or nil
                do
                    local cp = UI.Options and UI.Options.BoatESPHighlightColorpicker
                    if cp then highlight.OutlineColor = cp.Value end
                end

                -- name+dist
                local showName = UI.Toggles and UI.Toggles.BoatESPNameDistanceToggle and UI.Toggles.BoatESPNameDistanceToggle.Value and within
                if showName then
                    local p, on = camera:WorldToViewportPoint(pos + Vector3.new(0, 15, 0))
                    if on then
                        local col = (UI.Options and UI.Options.BoatESPNameDistanceColorpicker and UI.Options.BoatESPNameDistanceColorpicker.Value) or Color3.new(1,1,1)
                        nameText.Visible = true
                        nameText.Center = true
                        nameText.Outline = true
                        nameText.Size = 12
                        nameText.Position = Vector2.new(p.X, p.Y)
                        nameText.Color = col
                        nameText.Text = string.format("%s  [%.0f]", model.Name or "Boat", dist)
                    else
                        nameText.Visible = false
                    end
                else
                    nameText.Visible = false
                end

                -- tracer
                local showTracer = UI.Toggles and UI.Toggles.BoatESPTracerToggle and UI.Toggles.BoatESPTracerToggle.Value and within
                if showTracer then
                    local col = (UI.Options and UI.Options.BoatESPTracerColorpicker and UI.Options.BoatESPTracerColorpicker.Value) or Color3.new(1,1,1)
                    local p = camera:WorldToViewportPoint(pos)
                    local bottom = Vector2.new(camera.ViewportSize.X/2, camera.ViewportSize.Y)
                    tracer.Visible = true
                    tracer.From = bottom
                    tracer.To = Vector2.new(p.X, p.Y)
                    tracer.Color = col
                else
                    tracer.Visible = false
                end

                -- box
                local showBox = UI.Toggles and UI.Toggles.BoatESPBoxToggle and UI.Toggles.BoatESPBoxToggle.Value and within
                if showBox then
                    local col = (UI.Options and UI.Options.BoatESPBoxColorpicker and UI.Options.BoatESPBoxColorpicker.Value) or Color3.new(1,1,1)
                    local p = camera:WorldToViewportPoint(pos)
                    local size = Vector2.new(100, 60)
                    local tl = Vector2.new(p.X - size.X/2, p.Y - size.Y/2)
                    local tr = Vector2.new(p.X + size.X/2, p.Y - size.Y/2)
                    local bl = Vector2.new(p.X - size.X/2, p.Y + size.Y/2)
                    local br = Vector2.new(p.X + size.X/2, p.Y + size.Y/2)
                    local lines = { boxLineTop, boxLineBottom, boxLineLeft, boxLineRight }
                    for i=1,4 do lines[i].Visible = true; lines[i].Color = col end
                    boxLineTop.From = tl; boxLineTop.To = tr
                    boxLineBottom.From = bl; boxLineBottom.To = br
                    boxLineLeft.From = tl; boxLineLeft.To = bl
                    boxLineRight.From = tr; boxLineRight.To = br
                else
                    boxLineTop.Visible = false
                    boxLineBottom.Visible = false
                    boxLineLeft.Visible = false
                    boxLineRight.Visible = false
                end
            end

            Variables.Maids.BoatESP:GiveTask(services.RunService.RenderStepped:Connect(step))
        end

        -- UI (Visual → Boat ESP; verbatim IDs)
        do
            local tab = UI.Tabs.Visual or UI.Tabs.Misc
            local group = tab:AddRightGroupbox("Boat ESP", "ship")
            group:AddSlider("BoatESPDistanceSlider", {
                Text = "Max Distance",
                Default = 8000, Min = 0, Max = 20000, Rounding = 0, Compact = false,
            })
            group:AddToggle("BoatESPHighlightToggle", { Text = "Highlight", Default = false })
                :AddColorPicker("BoatESPHighlightColorpicker")
            group:AddToggle("BoatESPNameDistanceToggle", { Text = "Name + Distance", Default = false })
                :AddColorPicker("BoatESPNameDistanceColorpicker")
            group:AddToggle("BoatESPBoxToggle", { Text = "Boxes", Default = false })
                :AddColorPicker("BoatESPBoxColorpicker")
            group:AddToggle("BoatESPTracerToggle", { Text = "Tracers", Default = false })
                :AddColorPicker("BoatESPTracerColorpicker")
        end

        local function Stop()
            Variables.Maids.BoatESP:DoCleaning()
            for k, m in pairs(Variables.BoatMaids) do pcall(function() m:DoCleaning() end); Variables.BoatMaids[k] = nil end
        end

        return { Name = "BoatESP", Stop = Stop }
    end
end
