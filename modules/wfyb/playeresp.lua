-- modules/universal/playeresp.lua
do
    return function(UI)
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local Variables = {
            Maids = { PlayerESP = Maid.new() },
            PlayerMaids = setmetatable({}, { __mode = "k" }),

            NameTextSize      = 12,
            HealthTextSize    = 12,
            NameTextCenter    = true,
            NameTextOutline   = true,
            HealthTextCenter  = true,
            HealthTextOutline = true,
            HealthBarWidth    = 50,
            HealthBarHeight   = 5,
            HealthBarBGColor  = Color3.fromRGB(0, 0, 0),
            HighlightOutlineTransparency = 0,
            Buffer            = 4,
            VerticalOffset    = 30,

            PlayerESP            = "PlayerESPHighlightToggle",
            PlayerESPName        = "PlayerESPNameDistanceToggle",
            PlayerESPHealthbar   = "PlayerESPHealthBarToggle",
            PlayerESPHealthText  = "PlayerESPHealthTextToggle",
            PlayerESPTracer      = "PlayerESPTracerToggle",
            PlayerESPBox         = "PlayerESPBoxToggle",

            PlayerESPColor       = "PlayerESPHighlightColorpicker",
            PlayerESPNameColor   = "PlayerESPNameDistanceColorpicker",
            PlayerESPBoxColor    = "PlayerESPBoxColorpicker",
            PlayerESPTracerColor = "PlayerESPTracerColorpicker",

            PlayerESPDistanceSlider = "PlayerESPDistanceSlider",
        }

        local function GetPlayerMaid(plr)
            local m = Variables.PlayerMaids[plr]
            if not m then m = Maid.new(); Variables.PlayerMaids[plr] = m end
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

        -- ESP builder (verbatim behaviors)
        local function createESP(plr)
            local pm = GetPlayerMaid(plr)
            pm:DoCleaning()

            local highlight = Instance.new("Highlight")
            highlight.FillTransparency = 1
            highlight.OutlineTransparency = Variables.HighlightOutlineTransparency
            highlight.Parent = services.CoreGui
            pm:GiveTask(highlight)

            local nameText   = AddDrawingCleanup(pm, Drawing.new("Text"))
            local distanceText = AddDrawingCleanup(pm, Drawing.new("Text"))
            local boxLineTop    = AddDrawingCleanup(pm, Drawing.new("Line"))
            local boxLineBottom = AddDrawingCleanup(pm, Drawing.new("Line"))
            local boxLineLeft   = AddDrawingCleanup(pm, Drawing.new("Line"))
            local boxLineRight  = AddDrawingCleanup(pm, Drawing.new("Line"))
            local tracer        = AddDrawingCleanup(pm, Drawing.new("Line"))
            local healthBarBG   = AddDrawingCleanup(pm, Drawing.new("Square"))
            local healthBarFG   = AddDrawingCleanup(pm, Drawing.new("Square"))

            local function onRenderStep()
                local camera = services.Workspace.CurrentCamera
                local char   = plr.Character
                local hrp    = char and char:FindFirstChild("HumanoidRootPart")
                local hum    = char and char:FindFirstChildOfClass("Humanoid")

                local dist = math.huge
                if camera and hrp then
                    dist = (camera.CFrame.Position - hrp.Position).Magnitude
                end

                local maxDistOpt = UI.Options and UI.Options[Variables.PlayerESPDistanceSlider] and UI.Options[Variables.PlayerESPDistanceSlider].Value
                local maxDist = tonumber(maxDistOpt) or 8000

                -- highlight on/off
                local showHL = UI.Toggles and UI.Toggles[Variables.PlayerESP] and UI.Toggles[Variables.PlayerESP].Value and dist <= maxDist
                highlight.Adornee = showHL and char or nil

                -- name + distance text
                local showName = UI.Toggles and UI.Toggles[Variables.PlayerESPName] and UI.Toggles[Variables.PlayerESPName].Value and dist <= maxDist
                if camera and hrp and showName then
                    local screenPos, onScreen = camera:WorldToViewportPoint(hrp.Position + Vector3.new(0, Variables.VerticalOffset, 0))
                    if onScreen then
                        nameText.Visible = true
                        nameText.Center = Variables.NameTextCenter
                        nameText.Outline = Variables.NameTextOutline
                        nameText.Size = Variables.NameTextSize
                        local cOpt = UI.Options and UI.Options[Variables.PlayerESPNameColor]
                        local col = (cOpt and cOpt.Value) or Color3.new(1, 1, 1)
                        nameText.Color = col
                        nameText.Position = Vector2.new(screenPos.X, screenPos.Y)
                        local label = plr.DisplayName or plr.Name
                        distanceText.Visible = true
                        distanceText.Center = Variables.HealthTextCenter
                        distanceText.Outline = Variables.HealthTextOutline
                        distanceText.Size = Variables.HealthTextSize
                        distanceText.Color = col
                        distanceText.Position = Vector2.new(screenPos.X, screenPos.Y + 12)
                        distanceText.Text = string.format("%.0f", dist)
                        nameText.Text = label
                    else
                        nameText.Visible = false
                        distanceText.Visible = false
                    end
                else
                    nameText.Visible = false
                    distanceText.Visible = false
                end

                -- box (top/bottom/left/right)
                local showBox = UI.Toggles and UI.Toggles[Variables.PlayerESPBox] and UI.Toggles[Variables.PlayerESPBox].Value and dist <= maxDist
                if camera and hrp and showBox then
                    local cOpt = UI.Options and UI.Options[Variables.PlayerESPBoxColor]
                    local col = (cOpt and cOpt.Value) or Color3.new(1, 1, 1)

                    local cf = hrp.CFrame
                    local size = Vector2.new(60, 80)
                    local p = camera:WorldToViewportPoint(cf.Position)
                    local tl = Vector2.new(p.X - size.X/2, p.Y - size.Y/2)
                    local tr = Vector2.new(p.X + size.X/2, p.Y - size.Y/2)
                    local bl = Vector2.new(p.X - size.X/2, p.Y + size.Y/2)
                    local br = Vector2.new(p.X + size.X/2, p.Y + size.Y/2)

                    local lines = { boxLineTop, boxLineBottom, boxLineLeft, boxLineRight }
                    for i=1,4 do lines[i].Visible = true end

                    boxLineTop.From = tl; boxLineTop.To = tr; boxLineTop.Color = col
                    boxLineBottom.From = bl; boxLineBottom.To = br; boxLineBottom.Color = col
                    boxLineLeft.From = tl; boxLineLeft.To = bl; boxLineLeft.Color = col
                    boxLineRight.From = tr; boxLineRight.To = br; boxLineRight.Color = col
                else
                    boxLineTop.Visible = false
                    boxLineBottom.Visible = false
                    boxLineLeft.Visible = false
                    boxLineRight.Visible = false
                end

                -- tracer
                local showTracer = UI.Toggles and UI.Toggles[Variables.PlayerESPTracer] and UI.Toggles[Variables.PlayerESPTracer].Value and dist <= maxDist
                if camera and hrp and showTracer then
                    local cOpt = UI.Options and UI.Options[Variables.PlayerESPTracerColor]
                    local col = (cOpt and cOpt.Value) or Color3.new(1, 1, 1)
                    local p = camera:WorldToViewportPoint(hrp.Position)
                    local bottom = Vector2.new(camera.ViewportSize.X/2, camera.ViewportSize.Y)
                    tracer.Visible = true
                    tracer.From = bottom
                    tracer.To = Vector2.new(p.X, p.Y)
                    tracer.Color = col
                else
                    tracer.Visible = false
                end

                -- healthbar + text
                local showHB = UI.Toggles and UI.Toggles[Variables.PlayerESPHealthbar] and UI.Toggles[Variables.PlayerESPHealthbar].Value and dist <= maxDist
                local showHT = UI.Toggles and UI.Toggles[Variables.PlayerESPHealthText] and UI.Toggles[Variables.PlayerESPHealthText].Value and dist <= maxDist
                if hum and camera and hrp and (showHB or showHT) then
                    local p = camera:WorldToViewportPoint(hrp.Position)
                    local x = p.X - 30
                    local y = p.Y + 42
                    local w = Variables.HealthBarWidth
                    local h = Variables.HealthBarHeight
                    local pct = math.clamp((hum.Health / math.max(1, hum.MaxHealth)), 0, 1)

                    if showHB then
                        healthBarBG.Visible = true
                        healthBarFG.Visible = true
                        healthBarBG.Position = Vector2.new(x, y)
                        healthBarBG.Size = Vector2.new(w, h)
                        healthBarBG.Filled = true
                        healthBarBG.Color = Variables.HealthBarBGColor

                        healthBarFG.Position = Vector2.new(x, y)
                        healthBarFG.Size = Vector2.new(w * pct, h)
                        healthBarFG.Filled = true
                        healthBarFG.Color = Color3.fromRGB(0, 235, 0)
                    else
                        healthBarBG.Visible = false
                        healthBarFG.Visible = false
                    end

                    if showHT then
                        distanceText.Visible = true
                        distanceText.Size = Variables.HealthTextSize
                        distanceText.Center = true
                        distanceText.Outline = true
                        distanceText.Text = string.format("%d / %d", hum.Health, hum.MaxHealth)
                        distanceText.Position = Vector2.new(x + w/2, y + h + 10)
                    end
                end
            end

            Variables.Maids.PlayerESP:GiveTask(services.RunService.RenderStepped:Connect(onRenderStep))
        end

        -- UI (Visual → Player ESP; verbatim group/keys)
        do
            local tab = UI.Tabs.Visual or UI.Tabs.Misc
            local group = tab:AddLeftGroupbox("Player ESP", "user")
            group:AddSlider("PlayerESPDistanceSlider", {
                Text = "Max Distance",
                Default = 8000, Min = 0, Max = 20000, Rounding = 0, Compact = false,
            })
            group:AddToggle("PlayerESPHighlightToggle", { Text = "Highlight", Default = false })
                :AddColorPicker("PlayerESPHighlightColorpicker")
            group:AddToggle("PlayerESPNameDistanceToggle", { Text = "Name + Distance", Default = false })
                :AddColorPicker("PlayerESPNameDistanceColorpicker")
            group:AddToggle("PlayerESPBoxToggle", { Text = "Boxes", Default = false })
                :AddColorPicker("PlayerESPBoxColorpicker")
            group:AddToggle("PlayerESPTracerToggle", { Text = "Tracers", Default = false })
                :AddColorPicker("PlayerESPTracerColorpicker")
            group:AddToggle("PlayerESPHealthBarToggle", { Text = "Health Bar", Default = false })
            group:AddToggle("PlayerESPHealthTextToggle", { Text = "Health Text", Default = false })
        end

        local function Stop()
            Variables.Maids.PlayerESP:DoCleaning()
            for k, m in pairs(Variables.PlayerMaids) do pcall(function() m:DoCleaning() end); Variables.PlayerMaids[k] = nil end
        end

        return { Name = "PlayerESP", Stop = Stop }
    end
end
