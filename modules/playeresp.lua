-- modules/playeresp.lua
do
    return function(UI)
        --------------------------------------------------------------------
        -- Imports (match Shield.lua style)
        --------------------------------------------------------------------
        local GlobalEnv = (getgenv and getgenv()) or _G
        local RepoBase = GlobalEnv.RepoBase or "https://raw.githubusercontent.com/ratware-exe/repo/main/"

        local RbxService = loadstring(game:HttpGet(RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        GlobalEnv.Signal  = GlobalEnv.Signal or loadstring(game:HttpGet(RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()
        local Maid        = loadstring(game:HttpGet(RepoBase .. "dependency/Maid.lua"),     "@Maid.lua")()

        local Players      = RbxService.Players
        local RunService   = RbxService.RunService
        local Workspace    = RbxService.Workspace

        -- Executor feature detection
        local hasDrawing = (typeof(Drawing) == "table" and typeof(Drawing.new) == "function")

        --------------------------------------------------------------------
        -- Variables (settings + state). Defaults mirror the source script.  :contentReference[oaicite:2]{index=2}
        --------------------------------------------------------------------
        local Variables = {
            Maids = { PlayerESP = Maid.new() },

            -- UI Labels (for stats)
            PlayerESPUILabels = {
                Status = nil,
                PlayerCount = nil,
                FPS = nil,
            },

            -- Settings
            PlayerESPSettings = {
                Enabled = false,
                -- Core
                Box = false, BoxFilled = false, BoxThickness = 2,
                BoxWidth = 80, BoxHeight = 120, BoxFillTransparency = 0.10,
                -- Text & Bars
                Name = false, NameSize = 16, DisplayName = true,
                Health = false, HealthSize = 14,
                HealthBar = false, HealthBarWidth = 3, HealthBarStyle = "Vertical",
                ArmorBar = false, ArmorBarWidth = 3,
                Stud = false, StudSize = 14,
                -- Extra
                Skeleton = false, SkeletonThickness = 2,
                Highlight = false, HighlightTransparency = 0.5,
                Tracer = false, TracerFrom = "Bottom", TracerThickness = 1,
                LookTracer = false, LookTracerThickness = 2,
                Chams = false, ChamsTransparency = 0.5,
                OutOfView = false, OutOfViewSize = 15,
                Weapon = false, WeaponSize = 14,
                Flags = false, FlagsSize = 12,
                SnapLines = false,
                HeadDot = false, HeadDotSize = 8,
                -- Colors
                BoxColor = Color3.fromRGB(255, 0, 0),
                BoxFillColor = Color3.fromRGB(255, 0, 0),
                NameColor = Color3.fromRGB(255, 255, 255),
                HealthColor = Color3.fromRGB(0, 255, 0),
                HealthBarColorLow  = Color3.fromRGB(255, 0, 0),
                HealthBarColorMid  = Color3.fromRGB(255, 255, 0),
                HealthBarColorHigh = Color3.fromRGB(0, 255, 0),
                ArmorBarColor = Color3.fromRGB(0, 150, 255),
                StudColor    = Color3.fromRGB(255, 255, 0),
                SkeletonColor= Color3.fromRGB(255, 255, 255),
                HighlightColor=Color3.fromRGB(255, 0, 255),
                TracerColor  = Color3.fromRGB(0, 255, 255),
                LookTracerColor = Color3.fromRGB(255, 100, 0),
                ChamsColor   = Color3.fromRGB(255, 0, 255),
                OutOfViewColor=Color3.fromRGB(255, 0, 0),
                WeaponColor  = Color3.fromRGB(255, 200, 0),
                FlagsColor   = Color3.fromRGB(255, 255, 255),
                HeadDotColor = Color3.fromRGB(255, 0, 0),
                -- Behavior
                Transparency = 1,
                TeamCheck = false, TeamColor = false, ShowLocalTeam = false,
                MaxDistance = 5000, ShowOffscreen = true,
                UseDistanceFade = true, FadeStart = 3000,
                RainbowMode = false, RainbowSpeed = 1,
                PerformanceMode = false, UpdateRate = 60,
            },

            -- Runtime
            PlayerESPVisualsByPlayer = {},  -- [Player] -> { drawing/instances }
            PlayerESPPlayerData      = {},  -- [Player] -> { LastPosition, Velocity, Speed }
            PlayerESPRainbowHue = 0,
            PlayerESPLastUpdateTimestamp = 0,
            PlayerESPUpdateIntervalSeconds = 1/60,
        }

        --------------------------------------------------------------------
        -- Helpers (no Luau-only syntax)
        --------------------------------------------------------------------
        local function colorLerp(a, b, t)
            return Color3.new(
                a.R + (b.R - a.R) * t,
                a.G + (b.G - a.G) * t,
                a.B + (b.B - a.B) * t
            )
        end

        local function getRainbow()
            Variables.PlayerESPRainbowHue = (Variables.PlayerESPRainbowHue + Variables.PlayerESPSettings.RainbowSpeed * 0.001) % 1
            return Color3.fromHSV(Variables.PlayerESPRainbowHue, 1, 1)
        end

        local function distanceFade(distance)
            local cfg = Variables.PlayerESPSettings
            if not cfg.UseDistanceFade then return 1 end
            if distance < cfg.FadeStart then return 1 end
            local span = math.max(1, cfg.MaxDistance - cfg.FadeStart)
            local f = (cfg.MaxDistance - distance) / span
            return math.max(0.2, f)
        end

        local function teamColor(p)
            if p and p.Team and p.Team.TeamColor then
                return p.Team.TeamColor.Color
            end
            return Color3.fromRGB(255,255,255)
        end

        local function weaponName(character)
            if character then
                local children = character:GetChildren()
                for i = 1, #children do
                    local c = children[i]
                    if c:IsA("Tool") then return c.Name end
                end
            end
            return "None"
        end

        local function flagsText(player, character)
            local t, humanoid = {}, character and character:FindFirstChild("Humanoid")
            if humanoid then
                if humanoid.Sit           then t[#t+1] = "SIT"  end
                if humanoid.PlatformStand then t[#t+1] = "STUN" end
                if humanoid.Jump          then t[#t+1] = "JUMP" end
            end
            if character and character:FindFirstChildOfClass("ForceField") then
                t[#t+1] = "FF"
            end
            return table.concat(t, " | ")
        end

        local function isVisible(character)
            local root = character and character:FindFirstChild("HumanoidRootPart")
            if not root then return false end
            local cam = Workspace.CurrentCamera
            local dist = (cam.CFrame.Position - root.Position).Magnitude
            if dist > Variables.PlayerESPSettings.MaxDistance then return false end
            local _, onScreen = cam:WorldToViewportPoint(root.Position)
            return onScreen or Variables.PlayerESPSettings.ShowOffscreen
        end

        local function updateKinematics(player)
            local bucket = Variables.PlayerESPPlayerData[player]
            if not bucket then
                bucket = { LastPosition = nil, Velocity = Vector3.new(), Speed = 0 }
                Variables.PlayerESPPlayerData[player] = bucket
            end
            local char = player.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if root then
                if bucket.LastPosition then
                    local delta = root.Position - bucket.LastPosition
                    bucket.Velocity = delta
                    bucket.Speed = delta.Magnitude
                end
                bucket.LastPosition = root.Position
            end
        end

        local function removeDrawing(obj)
            local ok = pcall(function()
                if obj and obj.Remove then obj:Remove()
                elseif obj and obj.Destroy then obj:Destroy()
                end
            end)
            return ok
        end

        local function destroyForPlayer(player)
            local visuals = Variables.PlayerESPVisualsByPlayer[player]
            if visuals then
                for key, v in pairs(visuals) do
                    if key == "Skeleton" then
                        for _, seg in pairs(v) do pcall(function() seg.line:Remove() end) end
                    else
                        removeDrawing(v)
                    end
                end
                Variables.PlayerESPVisualsByPlayer[player] = nil
            end
            Variables.PlayerESPPlayerData[player] = nil
        end

        local function createForPlayer(player)
            if player == Players.LocalPlayer then return end
            local char = player.Character
            if not char then return end
            local humanoid = char:FindFirstChild("Humanoid")
            local rootPart = char:FindFirstChild("HumanoidRootPart")
            if not humanoid or not rootPart then return end

            -- nuke any previous visuals
            if Variables.PlayerESPVisualsByPlayer[player] then
                destroyForPlayer(player)
            end

            local cfg = Variables.PlayerESPSettings
            local visuals = {}
            Variables.PlayerESPVisualsByPlayer[player] = visuals

            -- Drawing-based visuals (guard when Drawing is absent)
            if hasDrawing then
                if cfg.BoxFilled then
                    local sq = Drawing.new("Square")
                    sq.Filled = true
                    sq.Thickness = 1
                    sq.Color = cfg.BoxFillColor
                    sq.Transparency = cfg.BoxFillTransparency
                    sq.Visible = false
                    visuals.BoxFill = sq
                end
                if cfg.Box then
                    local sq = Drawing.new("Square")
                    sq.Filled = false
                    sq.Thickness = cfg.BoxThickness
                    sq.Transparency = cfg.Transparency
                    sq.Color = cfg.BoxColor
                    sq.Visible = false
                    visuals.Box = sq
                end
                if cfg.Name then
                    local t = Drawing.new("Text")
                    t.Size, t.Center, t.Outline = cfg.NameSize, true, true
                    t.Color = cfg.NameColor
                    t.Visible = false
                    visuals.Name = t
                end
                if cfg.Health then
                    local t = Drawing.new("Text")
                    t.Size, t.Center, t.Outline = cfg.HealthSize, true, true
                    t.Color = cfg.HealthColor
                    t.Visible = false
                    visuals.Health = t
                end
                if cfg.HealthBar then
                    local bg = Drawing.new("Square")
                    bg.Filled = true
                    bg.Color = Color3.fromRGB(0,0,0)
                    bg.Transparency = 0.5
                    bg.Visible = false
                    visuals.HealthBarBg = bg

                    local b = Drawing.new("Square")
                    b.Filled = true
                    b.Transparency = cfg.Transparency
                    b.Visible = false
                    visuals.HealthBar = b
                end
                if cfg.ArmorBar then
                    local bg = Drawing.new("Square")
                    bg.Filled = true
                    bg.Color = Color3.fromRGB(0,0,0)
                    bg.Transparency = 0.5
                    bg.Visible = false
                    visuals.ArmorBarBg = bg

                    local b = Drawing.new("Square")
                    b.Filled = true
                    b.Transparency = cfg.Transparency
                    b.Visible = false
                    visuals.ArmorBar = b
                end
                if cfg.Stud then
                    local t = Drawing.new("Text")
                    t.Size, t.Center, t.Outline = cfg.StudSize, true, true
                    t.Color = cfg.StudColor
                    t.Visible = false
                    visuals.Stud = t
                end
                if cfg.Weapon then
                    local t = Drawing.new("Text")
                    t.Size, t.Center, t.Outline = cfg.WeaponSize, true, true
                    t.Color = cfg.WeaponColor
                    t.Visible = false
                    visuals.Weapon = t
                end
                if cfg.Flags then
                    local t = Drawing.new("Text")
                    t.Size, t.Center, t.Outline = cfg.FlagsSize, true, true
                    t.Color = cfg.FlagsColor
                    t.Visible = false
                    visuals.Flags = t
                end
                if cfg.HeadDot then
                    local c = Drawing.new("Circle")
                    c.Filled = true
                    c.Transparency = cfg.Transparency
                    c.Visible = false
                    visuals.HeadDot = c
                end
                if cfg.Skeleton then
                    visuals.Skeleton = {}
                    local bonePairs = {
                        {"Head","UpperTorso"}, {"UpperTorso","LowerTorso"},
                        {"LowerTorso","LeftUpperLeg"}, {"LeftUpperLeg","LeftLowerLeg"}, {"LeftLowerLeg","LeftFoot"},
                        {"LowerTorso","RightUpperLeg"},{"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"},
                        {"UpperTorso","LeftUpperArm"},{"LeftUpperArm","LeftLowerArm"},{"LeftLowerArm","LeftHand"},
                        {"UpperTorso","RightUpperArm"},{"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},
                    }
                    for i = 1, #bonePairs do
                        local line = Drawing.new("Line")
                        line.Visible = false
                        visuals.Skeleton[i] = { bones = bonePairs[i], line = line }
                    end
                end
                if cfg.Tracer then
                    local l = Drawing.new("Line")
                    l.Transparency = cfg.Transparency
                    l.Visible = false
                    visuals.Tracer = l
                end
                if cfg.LookTracer then
                    local l = Drawing.new("Line")
                    l.Transparency = cfg.Transparency
                    l.Visible = false
                    visuals.LookTracer = l
                end
                if cfg.OutOfView then
                    local tri = Drawing.new("Triangle")
                    tri.Filled = true
                    tri.Transparency = cfg.Transparency
                    tri.Visible = false
                    visuals.Arrow = tri
                end
                if cfg.SnapLines then
                    local l = Drawing.new("Line")
                    l.Visible = false
                    visuals.SnapLine = l
                end
            end

            -- Instance-based visuals
            if cfg.Highlight then
                local hl = Instance.new("Highlight")
                hl.Adornee = char
                hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                hl.FillColor = cfg.HighlightColor
                hl.FillTransparency = cfg.HighlightTransparency
                hl.OutlineColor = cfg.HighlightColor
                hl.Parent = char
                visuals.Highlight = hl
            elseif cfg.Chams then
                local ch = Instance.new("Highlight")
                ch.Adornee = char
                ch.DepthMode = Enum.HighlightDepthMode.Occluded
                ch.FillColor = cfg.ChamsColor
                ch.FillTransparency = cfg.ChamsTransparency
                ch.OutlineColor = cfg.ChamsColor
                ch.Parent = char
                visuals.Chams = ch
            end
        end

        local function updateAll()
            local cfg = Variables.PlayerESPSettings

            if not cfg.Enabled then
                -- full clear when disabled
                for p, _ in pairs(Variables.PlayerESPVisualsByPlayer) do
                    destroyForPlayer(p)
                end
                return
            end

            -- perf gate
            local now = tick()
            if cfg.PerformanceMode then
                if (now - Variables.PlayerESPLastUpdateTimestamp) < Variables.PlayerESPUpdateIntervalSeconds then
                    return
                end
            end
            Variables.PlayerESPLastUpdateTimestamp = now

            local cam = Workspace.CurrentCamera
            if not cam then return end
            local viewport = cam.ViewportSize
            local me = Players.LocalPlayer
            local myRoot = me.Character and me.Character:FindFirstChild("HumanoidRootPart")

            local playerList = Players:GetPlayers()
            for i = 1, #playerList do
                local p = playerList[i]
                if p ~= me then
                    updateKinematics(p)
                    local char = p.Character
                    local root = char and char:FindFirstChild("HumanoidRootPart")
                    local humanoid = char and char:FindFirstChild("Humanoid")
                    local head = char and char:FindFirstChild("Head")

                    if not (char and root and humanoid and humanoid.Health > 0) then
                        destroyForPlayer(p)
                    else
                        -- Team filter
                        if cfg.TeamCheck and p.Team == me.Team and not cfg.ShowLocalTeam then
                            -- hide drawings (keep highlights/chams alive so instance parenting stays stable)
                            local visuals = Variables.PlayerESPVisualsByPlayer[p]
                            if visuals then
                                for key, v in pairs(visuals) do
                                    if key == "Skeleton" then
                                        for _, seg in pairs(v) do pcall(function() seg.line.Visible = false end) end
                                    elseif key ~= "Highlight" and key ~= "Chams" then
                                        pcall(function() v.Visible = false end)
                                    end
                                end
                            end
                        else
                            -- ensure visuals exist if we’ll display
                            if not Variables.PlayerESPVisualsByPlayer[p] then
                                createForPlayer(p)
                            end

                            local okToShow = isVisible(char)
                            local screenPos, onScreen = cam:WorldToViewportPoint(root.Position)
                            local dist = 0
                            if myRoot then dist = (myRoot.Position - root.Position).Magnitude end
                            local alpha = distanceFade(dist) * cfg.Transparency

                            local baseColor =
                                (cfg.RainbowMode and getRainbow())
                                or (cfg.TeamColor and teamColor(p))
                                or cfg.BoxColor

                            local w, h = cfg.BoxWidth, cfg.BoxHeight
                            local tl = Vector2.new(screenPos.X - w/2, screenPos.Y - h/2)
                            local visuals = Variables.PlayerESPVisualsByPlayer[p]

                            -- If offscreen not allowed and target isn’t on screen, hide everything but offscreen arrow
                            local showDrawn = okToShow and onScreen

                            -- Box fill
                            if visuals and visuals.BoxFill then
                                visuals.BoxFill.Position = tl
                                visuals.BoxFill.Size = Vector2.new(w, h)
                                visuals.BoxFill.Color = cfg.BoxFillColor
                                visuals.BoxFill.Transparency = cfg.BoxFillTransparency
                                visuals.BoxFill.Visible = showDrawn
                            end

                            -- Box
                            if visuals and visuals.Box then
                                visuals.Box.Position = tl
                                visuals.Box.Size = Vector2.new(w, h)
                                visuals.Box.Color = baseColor
                                visuals.Box.Thickness = cfg.BoxThickness
                                visuals.Box.Transparency = alpha
                                visuals.Box.Visible = showDrawn
                            end

                            -- Name
                            if visuals and visuals.Name then
                                visuals.Name.Position = Vector2.new(screenPos.X, tl.Y - cfg.NameSize - 2)
                                visuals.Name.Color = (cfg.RainbowMode and getRainbow()) or cfg.NameColor
                                visuals.Name.Size = cfg.NameSize
                                visuals.Name.Text = (cfg.DisplayName and p.DisplayName) or p.Name
                                visuals.Name.Transparency = alpha
                                visuals.Name.Visible = showDrawn
                            end

                            -- under‑box stack
                            local yOff = 2

                            -- Health text
                            if visuals and visuals.Health then
                                visuals.Health.Text = string.format("%d/%d HP", math.floor(humanoid.Health), math.floor(humanoid.MaxHealth))
                                visuals.Health.Position = Vector2.new(screenPos.X, tl.Y + h + yOff)
                                visuals.Health.Color = cfg.HealthColor
                                visuals.Health.Size = cfg.HealthSize
                                visuals.Health.Transparency = alpha
                                visuals.Health.Visible = showDrawn
                                yOff = yOff + cfg.HealthSize + 2
                            end

                            -- Health bar
                            if visuals and visuals.HealthBar and visuals.HealthBarBg then
                                local hpPct = math.clamp(humanoid.Health / math.max(1, humanoid.MaxHealth), 0, 1)
                                if cfg.HealthBarStyle == "Vertical" then
                                    local barX = tl.X - cfg.HealthBarWidth - 2
                                    local barH = h * hpPct
                                    visuals.HealthBarBg.Position = Vector2.new(barX, tl.Y)
                                    visuals.HealthBarBg.Size     = Vector2.new(cfg.HealthBarWidth, h)
                                    visuals.HealthBarBg.Visible  = showDrawn

                                    visuals.HealthBar.Position   = Vector2.new(barX, tl.Y + (h - barH))
                                    visuals.HealthBar.Size       = Vector2.new(cfg.HealthBarWidth, barH)
                                else
                                    local full, filled = w, w * hpPct
                                    local barY = tl.Y + h + yOff
                                    visuals.HealthBarBg.Position = Vector2.new(tl.X, barY)
                                    visuals.HealthBarBg.Size     = Vector2.new(full, cfg.HealthBarWidth)
                                    visuals.HealthBarBg.Visible  = showDrawn

                                    visuals.HealthBar.Position   = visuals.HealthBarBg.Position
                                    visuals.HealthBar.Size       = Vector2.new(filled, cfg.HealthBarWidth)
                                    yOff = yOff + cfg.HealthBarWidth + 2
                                end

                                local hpColor
                                if hpPct > 0.5 then
                                    hpColor = colorLerp(cfg.HealthBarColorMid,  cfg.HealthBarColorHigh, (hpPct - 0.5) * 2)
                                else
                                    hpColor = colorLerp(cfg.HealthBarColorLow,  cfg.HealthBarColorMid,  hpPct * 2)
                                end
                                visuals.HealthBar.Color = hpColor
                                visuals.HealthBar.Transparency = alpha
                                visuals.HealthBar.Visible = showDrawn
                            end

                            -- Armor bar (experimental)
                            if visuals and visuals.ArmorBar and visuals.ArmorBarBg then
                                local baseMax = 100
                                local armorMax = math.max(0, math.floor(humanoid.MaxHealth - baseMax))
                                local armorCur = math.max(0, math.floor(humanoid.Health - baseMax))
                                local armorPct = (armorMax > 0) and math.clamp(armorCur / armorMax, 0, 1) or 0

                                local armorX = tl.X - (cfg.HealthBarWidth + 2) - (cfg.ArmorBarWidth + 2)
                                visuals.ArmorBarBg.Position = Vector2.new(armorX, tl.Y)
                                visuals.ArmorBarBg.Size     = Vector2.new(cfg.ArmorBarWidth, h)
                                visuals.ArmorBarBg.Visible  = showDrawn

                                visuals.ArmorBar.Position   = Vector2.new(armorX, tl.Y + (h - (h * armorPct)))
                                visuals.ArmorBar.Size       = Vector2.new(cfg.ArmorBarWidth, h * armorPct)
                                visuals.ArmorBar.Color      = cfg.ArmorBarColor
                                visuals.ArmorBar.Transparency = alpha
                                visuals.ArmorBar.Visible    = showDrawn and armorCur > 0
                            end

                            -- Distance
                            if visuals and visuals.Stud then
                                visuals.Stud.Text = string.format("%.0f studs", dist)
                                visuals.Stud.Position = Vector2.new(screenPos.X, tl.Y + h + yOff)
                                visuals.Stud.Color = cfg.StudColor
                                visuals.Stud.Size  = cfg.StudSize
                                visuals.Stud.Transparency = alpha
                                visuals.Stud.Visible = showDrawn
                                yOff = yOff + cfg.StudSize + 2
                            end

                            -- Weapon
                            if visuals and visuals.Weapon then
                                visuals.Weapon.Text = weaponName(char)
                                visuals.Weapon.Position = Vector2.new(screenPos.X, tl.Y + h + yOff)
                                visuals.Weapon.Color = cfg.WeaponColor
                                visuals.Weapon.Size  = cfg.WeaponSize
                                visuals.Weapon.Transparency = alpha
                                visuals.Weapon.Visible = showDrawn
                                yOff = yOff + cfg.WeaponSize + 2
                            end

                            -- Flags
                            if visuals and visuals.Flags then
                                local ftxt = flagsText(p, char)
                                if ftxt ~= "" then
                                    visuals.Flags.Text = ftxt
                                    visuals.Flags.Position = Vector2.new(screenPos.X, tl.Y + h + yOff)
                                    visuals.Flags.Color = cfg.FlagsColor
                                    visuals.Flags.Size  = cfg.FlagsSize
                                    visuals.Flags.Transparency = alpha
                                    visuals.Flags.Visible = showDrawn
                                else
                                    visuals.Flags.Visible = false
                                end
                            end

                            -- Head dot
                            if visuals and visuals.HeadDot and head then
                                local hp, hon = cam:WorldToViewportPoint(head.Position)
                                if showDrawn and hon then
                                    visuals.HeadDot.Position = Vector2.new(hp.X, hp.Y)
                                    visuals.HeadDot.Radius = cfg.HeadDotSize
                                    visuals.HeadDot.Color = (cfg.RainbowMode and getRainbow()) or cfg.HeadDotColor
                                    visuals.HeadDot.Transparency = alpha
                                    visuals.HeadDot.Visible = true
                                else
                                    visuals.HeadDot.Visible = false
                                end
                            end

                            -- Skeleton
                            if visuals and visuals.Skeleton then
                                for _, seg in pairs(visuals.Skeleton) do
                                    local a = char:FindFirstChild(seg.bones[1])
                                    local b = char:FindFirstChild(seg.bones[2])
                                    if a and b then
                                        local pa, aon = cam:WorldToViewportPoint(a.Position)
                                        local pb, bon = cam:WorldToViewportPoint(b.Position)
                                        if showDrawn and aon and bon then
                                            seg.line.From = Vector2.new(pa.X, pa.Y)
                                            seg.line.To   = Vector2.new(pb.X, pb.Y)
                                            seg.line.Color = (cfg.RainbowMode and getRainbow()) or cfg.SkeletonColor
                                            seg.line.Thickness = cfg.SkeletonThickness
                                            seg.line.Transparency = alpha
                                            seg.line.Visible = true
                                        else
                                            seg.line.Visible = false
                                        end
                                    else
                                        seg.line.Visible = false
                                    end
                                end
                            end

                            -- Highlights / Chams (instance)
                            if visuals and visuals.Highlight then
                                local c = (cfg.RainbowMode and getRainbow()) or cfg.HighlightColor
                                visuals.Highlight.FillColor = c
                                visuals.Highlight.OutlineColor = c
                                visuals.Highlight.FillTransparency = cfg.HighlightTransparency
                            elseif visuals and visuals.Chams then
                                local c = (cfg.RainbowMode and getRainbow()) or cfg.ChamsColor
                                visuals.Chams.FillColor = c
                                visuals.Chams.OutlineColor = c
                                visuals.Chams.FillTransparency = cfg.ChamsTransparency
                            end

                            -- Tracer
                            if visuals and visuals.Tracer then
                                local fromVec
                                if     cfg.TracerFrom == "Bottom" then fromVec = Vector2.new(viewport.X/2, viewport.Y)
                                elseif cfg.TracerFrom == "Center" then fromVec = Vector2.new(viewport.X/2, viewport.Y/2)
                                else                                   fromVec = Vector2.new(viewport.X/2, 0) end
                                visuals.Tracer.From  = fromVec
                                visuals.Tracer.To    = Vector2.new(screenPos.X, tl.Y + h)
                                visuals.Tracer.Color = (cfg.RainbowMode and getRainbow()) or cfg.TracerColor
                                visuals.Tracer.Thickness = cfg.TracerThickness
                                visuals.Tracer.Transparency = alpha
                                visuals.Tracer.Visible = showDrawn
                            end

                            -- Look tracer
                            if visuals and visuals.LookTracer and head then
                                local hp, hon = cam:WorldToViewportPoint(head.Position)
                                if showDrawn and hon then
                                    local endPos, eon = cam:WorldToViewportPoint(head.Position + head.CFrame.LookVector * 50)
                                    if eon then
                                        visuals.LookTracer.From = Vector2.new(hp.X, hp.Y)
                                        visuals.LookTracer.To   = Vector2.new(endPos.X, endPos.Y)
                                        visuals.LookTracer.Color = cfg.LookTracerColor
                                        visuals.LookTracer.Thickness = cfg.LookTracerThickness
                                        visuals.LookTracer.Transparency = alpha
                                        visuals.LookTracer.Visible = true
                                    else
                                        visuals.LookTracer.Visible = false
                                    end
                                else
                                    visuals.LookTracer.Visible = false
                                end
                            end

                            -- Off‑screen arrow
                            if visuals and visuals.Arrow then
                                if (not onScreen) and okToShow then
                                    local center = Vector2.new(viewport.X/2, viewport.Y/2)
                                    local dir = (Vector2.new(screenPos.X, screenPos.Y) - center)
                                    if dir.Magnitude > 0 then
                                        dir = dir.Unit
                                        local atan2 = math.atan2 or math.atan -- Luau supports both; Lua 5.1 uses atan(y, x) in Roblox
                                        local angle = atan2(dir.Y, dir.X)
                                        local edge = 50
                                        local pos = center + dir * (math.min(viewport.X, viewport.Y)/2 - edge)
                                        local size = cfg.OutOfViewSize
                                        local p1 = pos + Vector2.new(math.cos(angle) * size, math.sin(angle) * size)
                                        local p2 = pos + Vector2.new(math.cos(angle + 2.5) * size * 0.6, math.sin(angle + 2.5) * size * 0.6)
                                        local p3 = pos + Vector2.new(math.cos(angle - 2.5) * size * 0.6, math.sin(angle - 2.5) * size * 0.6)
                                        visuals.Arrow.PointA, visuals.Arrow.PointB, visuals.Arrow.PointC = p1, p2, p3
                                        visuals.Arrow.Color = (cfg.RainbowMode and getRainbow()) or cfg.OutOfViewColor
                                        visuals.Arrow.Transparency = alpha
                                        visuals.Arrow.Visible = true
                                    else
                                        visuals.Arrow.Visible = false
                                    end
                                else
                                    visuals.Arrow.Visible = false
                                end
                            end

                            -- Snap line
                            if visuals and visuals.SnapLine then
                                visuals.SnapLine.From = Vector2.new(viewport.X/2, viewport.Y/2)
                                visuals.SnapLine.To   = Vector2.new(screenPos.X, screenPos.Y)
                                visuals.SnapLine.Color = baseColor
                                visuals.SnapLine.Thickness = 1
                                visuals.SnapLine.Transparency = alpha
                                visuals.SnapLine.Visible = showDrawn
                            end
                        end
                    end
                end
            end
        end

        --------------------------------------------------------------------
        -- Public API (Start/Stop/Refresh/Stats), using ONE Maid (module's)
        --------------------------------------------------------------------
        local function Start()
            local maid = Variables.Maids.PlayerESP
            maid:DoCleaning()                    -- reset
            Variables.Maids.PlayerESP = Maid.new()
            maid = Variables.Maids.PlayerESP

            Variables.PlayerESPSettings.Enabled = true
            Variables.PlayerESPUpdateIntervalSeconds = 1 / math.max(1, tonumber(Variables.PlayerESPSettings.UpdateRate) or 60)

            -- frame update
            maid:GiveTask(RunService.RenderStepped:Connect(updateAll))

            -- current roster hooks
            local function attachFor(p)
                if p == Players.LocalPlayer then return end
                maid:GiveTask(p.CharacterAdded:Connect(function()
                    task.wait(0.1)
                    if Variables.PlayerESPSettings.Enabled then createForPlayer(p) end
                end))
                maid:GiveTask(p.CharacterRemoving:Connect(function()
                    destroyForPlayer(p)
                end))
                if p.Character then createForPlayer(p) end
            end

            local existing = Players:GetPlayers()
            for i = 1, #existing do attachFor(existing[i]) end

            maid:GiveTask(Players.PlayerAdded:Connect(attachFor))
            maid:GiveTask(Players.PlayerRemoving:Connect(function(p)
                destroyForPlayer(p)
            end))

            -- tidy finalizer (called when maid is cleaned)
            maid:GiveTask(function()
                Variables.PlayerESPSettings.Enabled = false
                for p in pairs(Variables.PlayerESPVisualsByPlayer) do
                    destroyForPlayer(p)
                end
            end)
        end

        local function Stop()
            local maid = Variables.Maids.PlayerESP
            if maid then
                maid:DoCleaning()
            end
            -- Ensure visuals are gone even if maid missed anything
            for p in pairs(Variables.PlayerESPVisualsByPlayer) do
                destroyForPlayer(p)
            end
            Variables.PlayerESPSettings.Enabled = false
        end

        local function RefreshAll()
            for p in pairs(Variables.PlayerESPVisualsByPlayer) do
                destroyForPlayer(p)
            end
            if Variables.PlayerESPSettings.Enabled then
                local list = Players:GetPlayers()
                for i = 1, #list do
                    local plr = list[i]
                    if plr ~= Players.LocalPlayer and plr.Character then
                        createForPlayer(plr)
                    end
                end
            end
        end

        local function SetUpdateRate(hz)
            Variables.PlayerESPSettings.UpdateRate = tonumber(hz) or Variables.PlayerESPSettings.UpdateRate
            Variables.PlayerESPUpdateIntervalSeconds = 1 / math.max(1, tonumber(Variables.PlayerESPSettings.UpdateRate) or 60)
        end

        local function AttachStatsUpdater()
            if Variables.Maids.PlayerESPStats then return end
            Variables.Maids.PlayerESPStats = Maid.new()
            local maid = Variables.Maids.PlayerESPStats

            local last = tick()
            local frames = 0
            maid:GiveTask(RunService.RenderStepped:Connect(function()
                frames = frames + 1
                local now = tick()
                if now - last >= 1 then
                    local fps = frames; frames = 0; last = now

                    local ui = Variables.PlayerESPUILabels
                    if ui and ui.FPS and ui.FPS.SetText then
                        ui.FPS:SetText("FPS: " .. tostring(fps))
                    end

                    local visible = 0
                    for _, visuals in pairs(Variables.PlayerESPVisualsByPlayer) do
                        if visuals and visuals.Box and visuals.Box.Visible then
                            visible = visible + 1
                        end
                    end
                    local total = math.max(0, #Players:GetPlayers() - 1)
                    if ui and ui.PlayerCount and ui.PlayerCount.SetText then
                        ui.PlayerCount:SetText(("Players Visible: %d/%d"):format(visible, total))
                    end
                    if ui and ui.Status and ui.Status.SetText then
                        ui.Status:SetText(Variables.PlayerESPSettings.Enabled and "ESP Status: Active" or "ESP Status: Inactive")
                    end
                end
            end))

            -- clean label updater when stats maid is cleaned
            maid:GiveTask(function()
                -- no-op; labels persist in UI
            end)
        end

        --------------------------------------------------------------------
        -- UI (Visuals tab) — matches your existing groupbox layout.  :contentReference[oaicite:3]{index=3}
        --------------------------------------------------------------------
        local VisualsTab = UI.Tabs and UI.Tabs.Visuals
        if VisualsTab then
            local CoreLeft       = VisualsTab:AddLeftGroupbox("Core ESP", "eye")
            local ExtraRight     = VisualsTab:AddRightGroupbox("Additional ESP", "layers")
            local AppearanceLeft = VisualsTab:AddLeftGroupbox("Appearance", "palette")
            local SizeRight      = VisualsTab:AddRightGroupbox("Size Settings", "move-diagonal")
            local FiltersLeft    = VisualsTab:AddLeftGroupbox("Filters", "filter")
            local PerfRight      = VisualsTab:AddRightGroupbox("Performance", "gauge")

            -- Master
            CoreLeft:AddToggle("ESPEnabled", { Text = "Enable ESP", Default = Variables.PlayerESPSettings.Enabled })

            -- Core + inline colors
            CoreLeft:AddToggle("ESPBox",{ Text = "Box ESP", Default = Variables.PlayerESPSettings.Box })
                :AddColorPicker("BoxColor",{ Title = "Box Color", Default = Variables.PlayerESPSettings.BoxColor })
            CoreLeft:AddToggle("BoxFilled",{ Text = "Filled Box", Default = Variables.PlayerESPSettings.BoxFilled })
                :AddColorPicker("BoxFillColor",{ Title = "Fill Color", Default = Variables.PlayerESPSettings.BoxFillColor })
            CoreLeft:AddToggle("ESPName",{ Text = "Name ESP", Default = Variables.PlayerESPSettings.Name })
                :AddColorPicker("NameColor",{ Title = "Name Color", Default = Variables.PlayerESPSettings.NameColor })
            CoreLeft:AddToggle("ESPHealth",{ Text = "Health Text", Default = Variables.PlayerESPSettings.Health })
                :AddColorPicker("HealthColor",{ Title = "Health Color", Default = Variables.PlayerESPSettings.HealthColor })
            CoreLeft:AddToggle("ESPHealthBar",{ Text = "Health Bar", Default = Variables.PlayerESPSettings.HealthBar })
                :AddColorPicker("HealthBarHigh",{ Title = "HP High", Default = Variables.PlayerESPSettings.HealthBarColorHigh })
                :AddColorPicker("HealthBarMid",{  Title = "HP Mid",  Default = Variables.PlayerESPSettings.HealthBarColorMid })
                :AddColorPicker("HealthBarLow",{  Title = "HP Low",  Default = Variables.PlayerESPSettings.HealthBarColorLow })
            CoreLeft:AddDropdown("HealthBarStyle", {
                Text = "Health Bar Style", Values = { "Vertical", "Horizontal" },
                Default = Variables.PlayerESPSettings.HealthBarStyle or "Vertical"
            })
            CoreLeft:AddToggle("ESPStud",{ Text = "Distance ESP", Default = Variables.PlayerESPSettings.Stud })
                :AddColorPicker("StudColor",{ Title = "Distance Color", Default = Variables.PlayerESPSettings.StudColor })
            CoreLeft:AddToggle("DisplayName",{ Text = "Show Display Name", Default = Variables.PlayerESPSettings.DisplayName ~= false })

            -- Additional
            ExtraRight:AddToggle("ESPSkeleton",{ Text = "Skeleton ESP", Default = Variables.PlayerESPSettings.Skeleton })
                :AddColorPicker("SkeletonColor",{ Title = "Skeleton Color", Default = Variables.PlayerESPSettings.SkeletonColor })
            ExtraRight:AddToggle("ESPHighlight",{ Text = "Highlight ESP", Default = Variables.PlayerESPSettings.Highlight })
                :AddColorPicker("HighlightColor",{ Title = "Highlight Color", Default = Variables.PlayerESPSettings.HighlightColor })
            ExtraRight:AddToggle("ESPChams",{ Text = "Chams (Wallhack)", Default = Variables.PlayerESPSettings.Chams })
                :AddColorPicker("ChamsColor",{ Title = "Chams Color", Default = Variables.PlayerESPSettings.ChamsColor })
            ExtraRight:AddToggle("ESPTracer",{ Text = "Tracer ESP", Default = Variables.PlayerESPSettings.Tracer })
                :AddColorPicker("TracerColor",{ Title = "Tracer Color", Default = Variables.PlayerESPSettings.TracerColor })
            ExtraRight:AddToggle("LookTracer",{ Text = "Look Direction", Default = Variables.PlayerESPSettings.LookTracer })
                :AddColorPicker("LookTracerColor",{ Title = "Look Tracer Color", Default = Variables.PlayerESPSettings.LookTracerColor })
            ExtraRight:AddToggle("HeadDot",{ Text = "Head Dot", Default = Variables.PlayerESPSettings.HeadDot })
                :AddColorPicker("HeadDotColor",{ Title = "Head Dot Color", Default = Variables.PlayerESPSettings.HeadDotColor })
            ExtraRight:AddToggle("OutOfView",{ Text = "Off-Screen Arrows", Default = Variables.PlayerESPSettings.OutOfView })
                :AddColorPicker("OutOfViewColor",{ Title = "Arrow Color", Default = Variables.PlayerESPSettings.OutOfViewColor })
            ExtraRight:AddToggle("ESPWeapon",{ Text = "Weapon Display", Default = Variables.PlayerESPSettings.Weapon })
                :AddColorPicker("WeaponColor",{ Title = "Weapon Color", Default = Variables.PlayerESPSettings.WeaponColor })
            ExtraRight:AddToggle("ESPFlags",{ Text = "Status Flags", Default = Variables.PlayerESPSettings.Flags })
                :AddColorPicker("FlagsColor",{ Title = "Flags Color", Default = Variables.PlayerESPSettings.FlagsColor })
            ExtraRight:AddToggle("ArmorBar",{ Text = "Armor Bar (Experimental)", Default = Variables.PlayerESPSettings.ArmorBar })
                :AddColorPicker("ArmorBarColor",{ Title = "Armor Color", Default = Variables.PlayerESPSettings.ArmorBarColor })

            -- Appearance
            AppearanceLeft:AddToggle("RainbowMode",{ Text = "Rainbow Mode", Default = Variables.PlayerESPSettings.RainbowMode })
            AppearanceLeft:AddSlider("RainbowSpeed",{ Text = "Rainbow Speed", Default = Variables.PlayerESPSettings.RainbowSpeed, Min = 0.1, Max = 5, Rounding = 1 })
            AppearanceLeft:AddToggle("TeamColor",{ Text = "Use Team Colors", Default = Variables.PlayerESPSettings.TeamColor })
            AppearanceLeft:AddSlider("ESPTransparency",{ Text = "ESP Transparency", Default = Variables.PlayerESPSettings.Transparency, Min = 0, Max = 1, Rounding = 2 })
            AppearanceLeft:AddSlider("BoxFillTransparency",{ Text = "Fill Transparency", Default = Variables.PlayerESPSettings.BoxFillTransparency, Min = 0, Max = 1, Rounding = 2 })
            AppearanceLeft:AddSlider("HighlightTransparency",{ Text = "Highlight Transparency", Default = Variables.PlayerESPSettings.HighlightTransparency, Min = 0, Max = 1, Rounding = 2 })
            AppearanceLeft:AddSlider("ChamsTransparency",{ Text = "Chams Transparency", Default = Variables.PlayerESPSettings.ChamsTransparency, Min = 0, Max = 1, Rounding = 2 })

            -- Sizes
            SizeRight:AddSlider("BoxWidth",{ Text = "Box Width", Default = Variables.PlayerESPSettings.BoxWidth, Min = 40, Max = 200, Rounding = 0 })
            SizeRight:AddSlider("BoxHeight",{ Text = "Box Height", Default = Variables.PlayerESPSettings.BoxHeight, Min = 60, Max = 300, Rounding = 0 })
            SizeRight:AddSlider("BoxThickness",{ Text = "Box Thickness", Default = Variables.PlayerESPSettings.BoxThickness, Min = 1, Max = 6, Rounding = 0 })
            SizeRight:AddSlider("NameSize",{ Text = "Name Size", Default = Variables.PlayerESPSettings.NameSize, Min = 8, Max = 32, Rounding = 0 })
            SizeRight:AddSlider("HealthSize",{ Text = "Health Text Size", Default = Variables.PlayerESPSettings.HealthSize, Min = 8, Max = 24, Rounding = 0 })
            SizeRight:AddSlider("HealthBarWidth",{ Text = "Health Bar Width", Default = Variables.PlayerESPSettings.HealthBarWidth, Min = 2, Max = 10, Rounding = 0 })
            SizeRight:AddSlider("ArmorBarWidth",{ Text = "Armor Bar Width", Default = Variables.PlayerESPSettings.ArmorBarWidth, Min = 2, Max = 10, Rounding = 0 })
            SizeRight:AddSlider("StudSize",{ Text = "Distance Size", Default = Variables.PlayerESPSettings.StudSize, Min = 8, Max = 24, Rounding = 0 })
            SizeRight:AddSlider("WeaponSize",{ Text = "Weapon Size", Default = Variables.PlayerESPSettings.WeaponSize, Min = 8, Max = 22, Rounding = 0 })
            SizeRight:AddSlider("FlagsSize",{ Text = "Flags Size", Default = Variables.PlayerESPSettings.FlagsSize, Min = 8, Max = 20, Rounding = 0 })
            SizeRight:AddSlider("SkeletonThickness",{ Text = "Skeleton Thickness", Default = Variables.PlayerESPSettings.SkeletonThickness, Min = 1, Max = 5, Rounding = 0 })
            SizeRight:AddSlider("TracerThickness",{ Text = "Tracer Thickness", Default = Variables.PlayerESPSettings.TracerThickness, Min = 1, Max = 6, Rounding = 0 })
            SizeRight:AddSlider("LookTracerThickness",{ Text = "Look Tracer Thickness", Default = Variables.PlayerESPSettings.LookTracerThickness, Min = 1, Max = 5, Rounding = 0 })
            SizeRight:AddSlider("HeadDotSize",{ Text = "Head Dot Size", Default = Variables.PlayerESPSettings.HeadDotSize, Min = 4, Max = 20, Rounding = 0 })
            SizeRight:AddSlider("OutOfViewSize",{ Text = "Off-Screen Arrow Size", Default = Variables.PlayerESPSettings.OutOfViewSize, Min = 10, Max = 30, Rounding = 0 })

            -- Filters
            FiltersLeft:AddToggle("TeamCheck",{ Text = "Team Check", Default = Variables.PlayerESPSettings.TeamCheck })
            FiltersLeft:AddToggle("ShowLocalTeam",{ Text = "Show Teammates", Default = Variables.PlayerESPSettings.ShowLocalTeam })
            FiltersLeft:AddToggle("ShowOffscreen",{ Text = "Show Offscreen", Default = Variables.PlayerESPSettings.ShowOffscreen })
            FiltersLeft:AddSlider("MaxDistance",{ Text = "Max Distance", Default = Variables.PlayerESPSettings.MaxDistance, Min = 500, Max = 15000, Rounding = 0, Suffix = " studs" })
            FiltersLeft:AddToggle("UseDistanceFade",{ Text = "Distance Fade", Default = Variables.PlayerESPSettings.UseDistanceFade })
            FiltersLeft:AddSlider("FadeStart",{ Text = "Fade Start Distance", Default = Variables.PlayerESPSettings.FadeStart, Min = 300, Max = 10000, Rounding = 0, Suffix = " studs" })
            FiltersLeft:AddDropdown("TracerFrom",{ Text = "Tracer From", Values = { "Bottom", "Center", "Top" }, Default = Variables.PlayerESPSettings.TracerFrom or "Bottom" })

            -- Performance
            PerfRight:AddToggle("PerformanceMode",{ Text = "Performance Mode", Default = Variables.PlayerESPSettings.PerformanceMode })
            PerfRight:AddSlider("UpdateRate",{ Text = "Update Rate (FPS)", Default = Variables.PlayerESPSettings.UpdateRate, Min = 15, Max = 144, Rounding = 0, Suffix = " FPS" })
            PerfRight:AddLabel("Performance Info")
            PerfRight:AddLabel("Lower update rate = better performance")
            PerfRight:AddLabel("Disable unused features for FPS boost")
            PerfRight:AddButton({ Text = "Refresh All ESP", Func = function() RefreshAll(); if UI.Library and UI.Library.Notify then UI.Library:Notify("ESP Refreshed!", 3) end end })
            PerfRight:AddButton({ Text = "Clear All ESP",   Func = function()
                for p in pairs(Variables.PlayerESPVisualsByPlayer) do destroyForPlayer(p) end
                if UI.Library and UI.Library.Notify then UI.Library:Notify("All ESP Cleared!", 3) end
            end })

            -- Stats
            local StatsLeft = VisualsTab:AddLeftGroupbox("Statistics", "bar-chart-3")
            Variables.PlayerESPUILabels.Status      = StatsLeft:AddLabel("ESP Status: Inactive")
            Variables.PlayerESPUILabels.PlayerCount = StatsLeft:AddLabel("Players Visible: 0/0")
            Variables.PlayerESPUILabels.FPS         = StatsLeft:AddLabel("FPS: 0")
            AttachStatsUpdater()
        end

        --------------------------------------------------------------------
        -- UI bindings (OnChanged), no Luau-only syntax
        --------------------------------------------------------------------
        if UI.Toggles and UI.Toggles.ESPEnabled and UI.Toggles.ESPEnabled.OnChanged then
            UI.Toggles.ESPEnabled:OnChanged(function(enabled)
                Variables.PlayerESPSettings.Enabled = enabled
                local ui = Variables.PlayerESPUILabels
                if ui and ui.Status and ui.Status.SetText then
                    ui.Status:SetText(enabled and "ESP Status: Active" or "ESP Status: Inactive")
                end
                if enabled then Start() else Stop() end
            end)
        end

        -- Rebuild-required toggles
        local rebuildIds = {
            "ESPBox","BoxFilled","ESPName","ESPHealth","ESPHealthBar","ArmorBar",
            "ESPStud","ESPSkeleton","ESPHighlight","ESPChams","ESPTracer","LookTracer",
            "OutOfView","ESPWeapon","ESPFlags","HeadDot"
        }
        for i = 1, #rebuildIds do
            local id = rebuildIds[i]
            local t = UI.Toggles and UI.Toggles[id]
            if t and t.OnChanged then
                t:OnChanged(function(value)
                    local key =
                        (id == "ESPBox" and "Box") or
                        (id == "ESPName" and "Name") or
                        (id == "ESPHealth" and "Health") or
                        (id == "ESPHealthBar" and "HealthBar") or
                        (id == "ESPStud" and "Stud") or
                        (id == "ESPSkeleton" and "Skeleton") or
                        (id == "ESPHighlight" and "Highlight") or
                        (id == "ESPChams" and "Chams") or
                        (id == "ESPTracer" and "Tracer") or
                        (id == "LookTracer" and "LookTracer") or
                        (id == "OutOfView" and "OutOfView") or
                        (id == "ESPWeapon" and "Weapon") or
                        (id == "ESPFlags" and "Flags") or
                        (id == "HeadDot" and "HeadDot") or
                        id
                    Variables.PlayerESPSettings[key] = value
                    if Variables.PlayerESPSettings.Enabled then RefreshAll() end
                end)
            end
        end

        -- Simple toggles (no rebuild)
        local simple = {
            {"DisplayName","DisplayName"},
            {"RainbowMode","RainbowMode"},
            {"TeamColor","TeamColor"},
            {"TeamCheck","TeamCheck"},
            {"ShowOffscreen","ShowOffscreen"},
            {"UseDistanceFade","UseDistanceFade"},
            {"PerformanceMode","PerformanceMode"},
            {"ShowLocalTeam","ShowLocalTeam"},
        }
        for i = 0, #simple do
            local pair = simple[i]
            if pair then
                local id, key = pair[1], pair[2]
                local t = UI.Toggles and UI.Toggles[id]
                if t and t.OnChanged then
                    t:OnChanged(function(value) Variables.PlayerESPSettings[key] = value end)
                end
            end
        end

        -- Value options
        local optMap = {
            {"BoxWidth","BoxWidth"}, {"BoxHeight","BoxHeight"}, {"BoxThickness","BoxThickness"},
            {"NameSize","NameSize"}, {"HealthSize","HealthSize"}, {"HealthBarWidth","HealthBarWidth"},
            {"ArmorBarWidth","ArmorBarWidth"}, {"StudSize","StudSize"}, {"WeaponSize","WeaponSize"},
            {"FlagsSize","FlagsSize"}, {"SkeletonThickness","SkeletonThickness"},
            {"TracerThickness","TracerThickness"}, {"LookTracerThickness","LookTracerThickness"},
            {"HeadDotSize","HeadDotSize"}, {"OutOfViewSize","OutOfViewSize"},
            {"ESPTransparency","Transparency"}, {"BoxFillTransparency","BoxFillTransparency"},
            {"HighlightTransparency","HighlightTransparency"}, {"ChamsTransparency","ChamsTransparency"},
            {"FadeStart","FadeStart"}, {"MaxDistance","MaxDistance"},
            {"RainbowSpeed","RainbowSpeed"}, {"TracerFrom","TracerFrom"},
            {"UpdateRate","UpdateRate"}, {"HealthBarStyle","HealthBarStyle"},
        }
        for i = 1, #optMap do
            local id, key = optMap[i][1], optMap[i][2]
            local o = UI.Options and UI.Options[id]
            if o and o.OnChanged then
                o:OnChanged(function(value)
                    Variables.PlayerESPSettings[key] = value
                    if id == "UpdateRate" then SetUpdateRate(value) end
                end)
            end
        end

        -- Color pickers
        local colorMap = {
            {"BoxColor","BoxColor"},
            {"BoxFillColor","BoxFillColor"},
            {"NameColor","NameColor"},
            {"HealthColor","HealthColor"},
            {"HealthBarLow","HealthBarColorLow"},
            {"HealthBarMid","HealthBarColorMid"},
            {"HealthBarHigh","HealthBarColorHigh"},
            {"ArmorBarColor","ArmorBarColor"},
            {"StudColor","StudColor"},
            {"SkeletonColor","SkeletonColor"},
            {"HighlightColor","HighlightColor"},
            {"TracerColor","TracerColor"},
            {"LookTracerColor","LookTracerColor"},
            {"OutOfViewColor","OutOfViewColor"},
            {"WeaponColor","WeaponColor"},
            {"FlagsColor","FlagsColor"},
            {"HeadDotColor","HeadDotColor"},
            {"ChamsColor","ChamsColor"},
        }
        for i = 1, #colorMap do
            local id, key = colorMap[i][1], colorMap[i][2]
            local o = UI.Options and UI.Options[id]
            if o and o.OnChanged then
                o:OnChanged(function(colorVal) Variables.PlayerESPSettings[key] = colorVal end)
            end
        end

        --------------------------------------------------------------------
        -- Stop hook for loader (exactly like Shield.lua)
        --------------------------------------------------------------------
        local function ModuleStop()
            if UI.Toggles and UI.Toggles.ESPEnabled then
                UI.Toggles.ESPEnabled:SetValue(false)
            end
            Stop()
        end

        return { Name = "PlayerESP", Stop = ModuleStop }
    end
end
