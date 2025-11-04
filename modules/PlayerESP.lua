-- modules/PlayerESP.lua
-- Converted from lua-2.txt into a loader-compatible module for this repo.
-- Exposes Stop() for the loader to call on unload.

return function(...)
    ------------------------------------------------------------------------
    -- Resolve UI context (supports either a single UI table or 4 params)
    ------------------------------------------------------------------------
    local arg1, arg2, arg3, arg4 = ...
    local UI = (type(arg1) == "table" and (arg1.Library or arg1.Tabs or arg1.Options or arg1.Toggles))
        and arg1
        or { Library = arg1, Tabs = arg2, Options = arg3, Toggles = arg4 }

    local Library, Tabs, Options, Toggles = UI.Library, UI.Tabs or {}, UI.Options or {}, UI.Toggles or {}

    ------------------------------------------------------------------------
    -- Globals / dependencies
    ------------------------------------------------------------------------
    local GlobalEnv = (getgenv and getgenv()) or _G
    local RepoBase = GlobalEnv.RepoBase or "https://raw.githubusercontent.com/ratware-exe/repo/main/"

    local function requireRemote(path, chunkname)
        local src, err = game:HttpGet(RepoBase .. path)
        if not src or src == "" then
            error(("[PlayerESP] failed to fetch %s: %s"):format(path, tostring(err)), 2)
        end
        local fn, cerr = loadstring(src, "@" .. (chunkname or path))
        if not fn then
            error(("[PlayerESP] loadstring error for %s: %s"):format(path, tostring(cerr)), 2)
        end
        return fn()
    end

    -- Repo shared deps
    local Services = requireRemote("dependency/Services.lua", "dependency/Services.lua")
    local Maid     = requireRemote("dependency/Maid.lua",     "dependency/Maid.lua")
    -- Signal is not strictly required here, but consistent with other modules:
    local Signal   = requireRemote("dependency/Signal.lua",   "dependency/Signal.lua")

    local Rbx = Services
    local Players, RunService, Workspace = Rbx.Players, Rbx.RunService, Rbx.Workspace

    -- Drawing availability (executor-provided)
    local hasDrawing = (type(Drawing) == "table" and type(Drawing.new) == "function")

    ------------------------------------------------------------------------
    -- Variables & runtime state (adapted from lua-2.txt)
    ------------------------------------------------------------------------
    local Variables = {
        -- UI label refs for statistics
        PlayerESPUILabels = { Status = nil, PlayerCount = nil, FPS = nil },

        -- Settings
        PlayerESPSettings = {
            Enabled = false,  -- master toggle
            -- Core Visuals
            Box = false,
            BoxFilled = false,
            BoxRounded = false, -- reserved (no UI)
            BoxThickness = 2,
            BoxWidth = 80,
            BoxHeight = 120,
            BoxFillTransparency = 0.1,
            -- Text & Bars
            Name = false, NameSize = 16, DisplayName = true,
            Health = false, HealthSize = 14,
            HealthBar = false, HealthBarWidth = 3, HealthBarStyle = "Vertical", -- Vertical | Horizontal
            ArmorBar = false, ArmorBarWidth = 3,
            Stud = false, StudSize = 14,
            -- Extra Visuals
            Skeleton = false, SkeletonThickness = 2,
            Highlight = false, HighlightTransparency = 0.5,
            Tracer = false, TracerFrom = "Bottom", TracerThickness = 1,
            LookTracer = false, LookTracerThickness = 2,
            Chams = false, ChamsTransparency = 0.5,
            OutOfView = false, OutOfViewSize = 15,
            Arrow = false, ArrowSize = 20, -- kept for completeness
            Weapon = false, WeaponSize = 14,
            Flags = false, FlagsSize = 12,
            SnapLines = false,      -- kept for completeness
            HeadDot = false, HeadDotSize = 8,
            -- Colors
            BoxColor = Color3.fromRGB(255, 0, 0),
            BoxFillColor = Color3.fromRGB(255, 0, 0),
            NameColor = Color3.fromRGB(255, 255, 255),
            HealthColor = Color3.fromRGB(0, 255, 0),
            HealthBarColorLow = Color3.fromRGB(255, 0, 0),
            HealthBarColorMid = Color3.fromRGB(255, 255, 0),
            HealthBarColorHigh = Color3.fromRGB(0, 255, 0),
            ArmorBarColor = Color3.fromRGB(0, 150, 255),
            StudColor = Color3.fromRGB(255, 255, 0),
            SkeletonColor = Color3.fromRGB(255, 255, 255),
            HighlightColor = Color3.fromRGB(255, 0, 255),
            TracerColor = Color3.fromRGB(0, 255, 255),
            LookTracerColor = Color3.fromRGB(255, 100, 0),
            ArrowColor = Color3.fromRGB(255, 0, 0),
            ChamsColor = Color3.fromRGB(255, 0, 255),
            OutOfViewColor = Color3.fromRGB(255, 0, 0),
            WeaponColor = Color3.fromRGB(255, 200, 0),
            FlagsColor = Color3.fromRGB(255, 255, 255),
            HeadDotColor = Color3.fromRGB(255, 0, 0),
            -- Behavior
            Transparency = 1,
            TeamCheck = false,
            TeamColor = false,
            MaxDistance = 5000,
            ShowOffscreen = true,
            UseDistanceFade = true,
            FadeStart = 3000,
            RainbowMode = false,
            RainbowSpeed = 1,
            PerformanceMode = false,
            UpdateRate = 60,
            ShowLocalTeam = false,
        },

        -- Runtime
        Maids = { PlayerESP = Maid.new() },
        WeakMaids = setmetatable({}, { __mode = "k" }),
        PlayerESPVisualsByPlayer = {}, -- [Player] -> drawables/instances
        PlayerESPPlayerData = {},      -- [Player] -> { LastPosition, Velocity, Speed }
        PlayerESPRainbowHue = 0,
        PlayerESPLastUpdateTimestamp = 0,
        PlayerESPUpdateIntervalSeconds = 1 / 60,
        PlayerESPModule = nil,
    }

    -- Weak-maid auto buckets (per key)
    local function weakMaidFor(key)
        if key == nil then return nil end
        local m = Variables.WeakMaids[key]
        if m then return m end
        m = Maid.new()
        Variables.WeakMaids[key] = m
        if typeof(key) == "Instance" then
            local conn
            if key.Destroying then
                conn = key.Destroying:Connect(function()
                    pcall(function() m:DoCleaning() end)
                    Variables.WeakMaids[key] = nil
                end)
            else
                conn = key.AncestryChanged:Connect(function(child, parent)
                    local still = false
                    pcall(function() still = child:IsDescendantOf(game) end)
                    if not still then
                        pcall(function() m:DoCleaning() end)
                        Variables.WeakMaids[key] = nil
                    end
                end)
            end
            m:GiveTask(conn)
        end
        return m
    end

    ------------------------------------------------------------------------
    -- Helpers (color/visibility/flags/etc.)
    ------------------------------------------------------------------------
    local function getRainbow()
        Variables.PlayerESPRainbowHue = (Variables.PlayerESPRainbowHue + Variables.PlayerESPSettings.RainbowSpeed * 0.001) % 1
        return Color3.fromHSV(Variables.PlayerESPRainbowHue, 1, 1)
    end

    local function distanceFade(distance)
        local cfg = Variables.PlayerESPSettings
        if not cfg.UseDistanceFade then return cfg.Transparency end
        if distance < cfg.FadeStart then return cfg.Transparency end
        local span = math.max(1, cfg.MaxDistance - cfg.FadeStart)
        local f = (cfg.MaxDistance - distance) / span
        return math.max(0.2, f) * cfg.Transparency
    end

    local function getTeamColor(p)
        return (p and p.Team and p.Team.TeamColor and p.Team.TeamColor.Color) or Color3.fromRGB(255,255,255)
    end

    local function getWeaponName(character)
        if not character then return "None" end
        for _, child in ipairs(character:GetChildren()) do
            if child:IsA("Tool") then return child.Name end
        end
        return "None"
    end

    local function flagsText(player, character)
        local flags, humanoid = {}, character and character:FindFirstChild("Humanoid")
        if humanoid then
            if humanoid.Sit           then flags[#flags+1] = "SIT"  end
            if humanoid.PlatformStand then flags[#flags+1] = "STUN" end
            if humanoid.Jump          then flags[#flags+1] = "JUMP" end
        end
        if character and character:FindFirstChildOfClass("ForceField") then
            flags[#flags+1] = "FF"
        end
        return table.concat(flags, " | ")
    end

    local function characterVisible(character)
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if not root then return false end
        local cam = Workspace.CurrentCamera
        local dist = (cam.CFrame.Position - root.Position).Magnitude
        if dist > Variables.PlayerESPSettings.MaxDistance then return false end
        local _, onScreen = cam:WorldToViewportPoint(root.Position)
        return onScreen or Variables.PlayerESPSettings.ShowOffscreen
    end

    local function updatePlayerKinematics(player)
        local entry = Variables.PlayerESPPlayerData[player]
        if not entry then
            entry = { LastPosition = nil, Velocity = Vector3.new(), Speed = 0 }
            Variables.PlayerESPPlayerData[player] = entry
        end
        local char = player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then
            if entry.LastPosition then
                local delta = root.Position - entry.LastPosition
                entry.Velocity = delta
                entry.Speed = delta.Magnitude
            end
            entry.LastPosition = root.Position
        end
    end

    ------------------------------------------------------------------------
    -- Visuals lifecycle (create/destroy/update)
    ------------------------------------------------------------------------
    local function destroyPlayerVisuals(player)
        local visuals = Variables.PlayerESPVisualsByPlayer[player]
        if visuals then
            for key, obj in pairs(visuals) do
                if key == "Skeleton" then
                    for _, seg in pairs(obj) do pcall(function() seg.line:Remove() end) end
                elseif key == "Highlight" or key == "Chams" then
                    pcall(function() obj:Destroy() end)
                else
                    pcall(function() obj:Remove() end)
                end
            end
        end
        Variables.PlayerESPVisualsByPlayer[player] = nil
        Variables.PlayerESPPlayerData[player] = nil

        local pm = Variables.WeakMaids[player]
        if pm then pcall(function() pm:DoCleaning() end) end
    end

    local function createPlayerVisuals(player)
        if player == Players.LocalPlayer then return end
        if not hasDrawing and not Variables.PlayerESPSettings.Highlight and not Variables.PlayerESPSettings.Chams then
            -- No Drawing API and no instance-based highlights requested—nothing to draw
            return
        end

        local char = player.Character
        if not char then return end
        local humanoid = char:FindFirstChild("Humanoid")
        local rootPart = char:FindFirstChild("HumanoidRootPart")
        if not humanoid or not rootPart then return end

        if Variables.PlayerESPVisualsByPlayer[player] then
            destroyPlayerVisuals(player)
        end

        local visuals = {}
        Variables.PlayerESPVisualsByPlayer[player] = visuals

        local cfg = Variables.PlayerESPSettings

        -- Filled box
        if hasDrawing and cfg.BoxFilled then
            local sq = Drawing.new("Square")
            sq.Filled = true
            sq.Thickness = 1
            sq.Color = cfg.BoxFillColor
            sq.Transparency = cfg.BoxFillTransparency
            sq.Visible = false
            visuals.BoxFill = sq
        end

        -- Box outline
        if hasDrawing and cfg.Box then
            local sq = Drawing.new("Square")
            sq.Filled = false
            sq.Thickness = cfg.BoxThickness
            sq.Transparency = cfg.Transparency
            sq.Color = cfg.BoxColor
            sq.Visible = false
            visuals.Box = sq
        end

        -- Name
        if hasDrawing and cfg.Name then
            local t = Drawing.new("Text")
            t.Size, t.Center, t.Outline = cfg.NameSize, true, true
            t.Color = cfg.NameColor
            t.Text = (cfg.DisplayName and player.DisplayName) or player.Name
            t.Visible = false
            visuals.Name = t
        end

        -- Health text
        if hasDrawing and cfg.Health then
            local t = Drawing.new("Text")
            t.Size, t.Center, t.Outline = cfg.HealthSize, true, true
            t.Color = cfg.HealthColor
            t.Visible = false
            visuals.Health = t
        end

        -- Health bar
        if hasDrawing and cfg.HealthBar then
            local bg = Drawing.new("Square")
            bg.Filled, bg.Color, bg.Transparency, bg.Visible = true, Color3.fromRGB(0,0,0), 0.5, false
            visuals.HealthBarBg = bg

            local b = Drawing.new("Square")
            b.Filled, b.Transparency, b.Visible = true, cfg.Transparency, false
            visuals.HealthBar = b
        end

        -- Armor bar
        if hasDrawing and cfg.ArmorBar then
            local bg = Drawing.new("Square")
            bg.Filled, bg.Color, bg.Transparency, bg.Visible = true, Color3.fromRGB(0,0,0), 0.5, false
            visuals.ArmorBarBg = bg

            local b = Drawing.new("Square")
            b.Filled, b.Transparency, b.Visible = true, cfg.Transparency, false
            visuals.ArmorBar = b
        end

        -- Distance
        if hasDrawing and cfg.Stud then
            local t = Drawing.new("Text")
            t.Size, t.Center, t.Outline = cfg.StudSize, true, true
            t.Color = cfg.StudColor
            t.Visible = false
            visuals.Stud = t
        end

        -- Weapon
        if hasDrawing and cfg.Weapon then
            local t = Drawing.new("Text")
            t.Size, t.Center, t.Outline = cfg.WeaponSize, true, true
            t.Color = cfg.WeaponColor
            t.Visible = false
            visuals.Weapon = t
        end

        -- Flags
        if hasDrawing and cfg.Flags then
            local t = Drawing.new("Text")
            t.Size, t.Center, t.Outline = cfg.FlagsSize, true, true
            t.Color = cfg.FlagsColor
            t.Visible = false
            visuals.Flags = t
        end

        -- Head dot
        if hasDrawing and cfg.HeadDot then
            local c = Drawing.new("Circle")
            c.Filled = true
            c.Transparency = cfg.Transparency
            c.Visible = false
            visuals.HeadDot = c
        end

        -- Skeleton
        if hasDrawing and cfg.Skeleton then
            visuals.Skeleton = {}
            local pairsList = {
                {"Head","UpperTorso"}, {"UpperTorso","LowerTorso"},
                {"LowerTorso","LeftUpperLeg"}, {"LeftUpperLeg","LeftLowerLeg"}, {"LeftLowerLeg","LeftFoot"},
                {"LowerTorso","RightUpperLeg"}, {"RightUpperLeg","RightLowerLeg"}, {"RightLowerLeg","RightFoot"},
                {"UpperTorso","LeftUpperArm"}, {"LeftUpperArm","LeftLowerArm"}, {"LeftLowerArm","LeftHand"},
                {"UpperTorso","RightUpperArm"}, {"RightUpperArm","RightLowerArm"}, {"RightLowerArm","RightHand"},
            }
            for i = 1, #pairsList do
                local line = Drawing.new("Line")
                line.Visible = false
                visuals.Skeleton[i] = { bones = pairsList[i], line = line }
            end
        end

        -- Highlight (AlwaysOnTop)
        if cfg.Highlight then
            local hl = Instance.new("Highlight")
            hl.Adornee = char
            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            hl.FillColor = cfg.HighlightColor
            hl.FillTransparency = cfg.HighlightTransparency
            hl.OutlineColor = cfg.HighlightColor
            hl.Parent = char
            visuals.Highlight = hl
        end

        -- Chams (Occluded) if Highlight not enabled
        if cfg.Chams and not cfg.Highlight then
            local ch = Instance.new("Highlight")
            ch.Adornee = char
            ch.DepthMode = Enum.HighlightDepthMode.Occluded
            ch.FillColor = cfg.ChamsColor
            ch.FillTransparency = cfg.ChamsTransparency
            ch.OutlineColor = cfg.ChamsColor
            ch.Parent = char
            visuals.Chams = ch
        end

        -- Tracer
        if hasDrawing and cfg.Tracer then
            local l = Drawing.new("Line")
            l.Transparency = cfg.Transparency
            l.Visible = false
            visuals.Tracer = l
        end

        -- Look tracer
        if hasDrawing and cfg.LookTracer then
            local l = Drawing.new("Line")
            l.Transparency = cfg.Transparency
            l.Visible = false
            visuals.LookTracer = l
        end

        -- Off-screen arrow
        if hasDrawing and cfg.OutOfView then
            local tri = Drawing.new("Triangle")
            tri.Filled = true
            tri.Transparency = cfg.Transparency
            tri.Visible = false
            visuals.Arrow = tri
        end

        -- Optional snap line
        if hasDrawing and cfg.SnapLines then
            local l = Drawing.new("Line")
            l.Visible = false
            visuals.SnapLine = l
        end
    end

    local function updateAll()
        local cfg = Variables.PlayerESPSettings

        if not cfg.Enabled then
            for p in pairs(Variables.PlayerESPVisualsByPlayer) do
                destroyPlayerVisuals(p)
            end
            return
        end

        -- perf gate
        local now = tick()
        if cfg.PerformanceMode and (now - Variables.PlayerESPLastUpdateTimestamp) < Variables.PlayerESPUpdateIntervalSeconds then
            return
        end
        Variables.PlayerESPLastUpdateTimestamp = now

        local cam = Workspace.CurrentCamera
        local viewport = cam and cam.ViewportSize or Vector2.new(1920, 1080)
        local me = Players.LocalPlayer
        local myRoot = me.Character and me.Character:FindFirstChild("HumanoidRootPart")

        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= me then
                updatePlayerKinematics(p)

                local char = p.Character
                local root = char and char:FindFirstChild("HumanoidRootPart")
                local humanoid = char and char:FindFirstChild("Humanoid")
                local head = char and char:FindFirstChild("Head")

                if char and root and humanoid and humanoid.Health > 0 then
                    -- team filter
                    if cfg.TeamCheck and (p.Team == me.Team) and not cfg.ShowLocalTeam then
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
                        goto continue
                    end

                    if not Variables.PlayerESPVisualsByPlayer[p] then
                        createPlayerVisuals(p)
                    end

                    if not characterVisible(char) and not cfg.OutOfView then
                        local visuals = Variables.PlayerESPVisualsByPlayer[p]
                        if visuals then
                            for key, v in pairs(visuals) do
                                if key == "Skeleton" then
                                    for _, seg in pairs(v) do pcall(function() seg.line.Visible = false end) end
                                elseif key ~= "Highlight" and key ~= "Chams" and key ~= "Arrow" then
                                    pcall(function() v.Visible = false end)
                                end
                            end
                        end
                        goto continue
                    end

                    local screenPos, onScreen = cam:WorldToViewportPoint(root.Position)
                    local dist = 0
                    if myRoot then dist = (myRoot.Position - root.Position).Magnitude end
                    local alpha = distanceFade(dist)

                    local baseColor =
                        (cfg.RainbowMode and getRainbow())
                        or (cfg.TeamColor and getTeamColor(p))
                        or cfg.BoxColor

                    local w, h = cfg.BoxWidth, cfg.BoxHeight
                    local tl = Vector2.new(screenPos.X - w/2, screenPos.Y - h/2)
                    local visuals = Variables.PlayerESPVisualsByPlayer[p]

                    -- Box fill
                    if visuals and visuals.BoxFill then
                        visuals.BoxFill.Position = tl
                        visuals.BoxFill.Size = Vector2.new(w, h)
                        visuals.BoxFill.Color = cfg.RainbowMode and getRainbow() or cfg.BoxFillColor
                        visuals.BoxFill.Transparency = cfg.BoxFillTransparency
                        visuals.BoxFill.Visible = onScreen
                    end

                    -- Box outline
                    if visuals and visuals.Box then
                        visuals.Box.Position = tl
                        visuals.Box.Size = Vector2.new(w, h)
                        visuals.Box.Color = baseColor
                        visuals.Box.Thickness = cfg.BoxThickness
                        visuals.Box.Transparency = alpha
                        visuals.Box.Visible = onScreen
                    end

                    -- Name
                    if visuals and visuals.Name then
                        visuals.Name.Position = Vector2.new(screenPos.X, tl.Y - cfg.NameSize - 2)
                        visuals.Name.Color = (cfg.RainbowMode and getRainbow()) or cfg.NameColor
                        visuals.Name.Size = cfg.NameSize
                        visuals.Name.Text = (cfg.DisplayName and p.DisplayName) or p.Name
                        visuals.Name.Transparency = alpha
                        visuals.Name.Visible = onScreen
                    end

                    -- Stack under box
                    local yOff = 2

                    -- Health text
                    if visuals and visuals.Health then
                        visuals.Health.Text = string.format("%d/%d HP", math.floor(humanoid.Health), math.floor(humanoid.MaxHealth))
                        visuals.Health.Position = Vector2.new(screenPos.X, tl.Y + h + yOff)
                        visuals.Health.Color = cfg.HealthColor
                        visuals.Health.Size = cfg.HealthSize
                        visuals.Health.Transparency = alpha
                        visuals.Health.Visible = onScreen
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
                            visuals.HealthBarBg.Visible  = onScreen

                            visuals.HealthBar.Position   = Vector2.new(barX, tl.Y + (h - barH))
                            visuals.HealthBar.Size       = Vector2.new(cfg.HealthBarWidth, barH)
                        else
                            local full, filled = w, w * hpPct
                            local barY = tl.Y + h + yOff
                            visuals.HealthBarBg.Position = Vector2.new(tl.X, barY)
                            visuals.HealthBarBg.Size     = Vector2.new(full, cfg.HealthBarWidth)
                            visuals.HealthBarBg.Visible  = onScreen

                            visuals.HealthBar.Position   = visuals.HealthBarBg.Position
                            visuals.HealthBar.Size       = Vector2.new(filled, cfg.HealthBarWidth)
                            yOff = yOff + cfg.HealthBarWidth + 2
                        end

                        local hpColor
                        if hpPct > 0.5 then
                            hpColor = cfg.HealthBarColorMid:lerp(cfg.HealthBarColorHigh, (hpPct - 0.5) * 2)
                        else
                            hpColor = cfg.HealthBarColorLow:lerp(cfg.HealthBarColorMid, hpPct * 2)
                        end
                        visuals.HealthBar.Color = hpColor
                        visuals.HealthBar.Transparency = alpha
                        visuals.HealthBar.Visible = onScreen
                    end

                    -- Armor bar (experimental — assumes >100 overfill)
                    if visuals and visuals.ArmorBar and visuals.ArmorBarBg then
                        local baseMax = 100
                        local armorMax = math.max(0, math.floor(humanoid.MaxHealth - baseMax))
                        local armorCur = math.max(0, math.floor(humanoid.Health - baseMax))
                        local armorPct = (armorMax > 0) and math.clamp(armorCur / armorMax, 0, 1) or 0

                        local armorX = tl.X - (cfg.HealthBarWidth + 2) - (cfg.ArmorBarWidth + 2)
                        visuals.ArmorBarBg.Position = Vector2.new(armorX, tl.Y)
                        visuals.ArmorBarBg.Size     = Vector2.new(cfg.ArmorBarWidth, h)
                        visuals.ArmorBarBg.Visible  = onScreen

                        visuals.ArmorBar.Position   = Vector2.new(armorX, tl.Y + (h - (h * armorPct)))
                        visuals.ArmorBar.Size       = Vector2.new(cfg.ArmorBarWidth, h * armorPct)
                        visuals.ArmorBar.Color      = cfg.ArmorBarColor
                        visuals.ArmorBar.Transparency = alpha
                        visuals.ArmorBar.Visible    = onScreen and armorCur > 0
                    end

                    -- Distance
                    if visuals and visuals.Stud then
                        visuals.Stud.Text = string.format("%.0f studs", dist)
                        visuals.Stud.Position = Vector2.new(screenPos.X, tl.Y + h + yOff)
                        visuals.Stud.Color = cfg.StudColor
                        visuals.Stud.Size  = cfg.StudSize
                        visuals.Stud.Transparency = alpha
                        visuals.Stud.Visible = onScreen
                        yOff = yOff + cfg.StudSize + 2
                    end

                    -- Weapon
                    if visuals and visuals.Weapon then
                        visuals.Weapon.Text = getWeaponName(char)
                        visuals.Weapon.Position = Vector2.new(screenPos.X, tl.Y + h + yOff)
                        visuals.Weapon.Color = cfg.WeaponColor
                        visuals.Weapon.Size  = cfg.WeaponSize
                        visuals.Weapon.Transparency = alpha
                        visuals.Weapon.Visible = onScreen
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
                            visuals.Flags.Visible = onScreen
                        else
                            visuals.Flags.Visible = false
                        end
                    end

                    -- Head dot
                    if visuals and visuals.HeadDot and head then
                        local hp, hon = cam:WorldToViewportPoint(head.Position)
                        if hon then
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
                                if aon and bon then
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

                    -- Highlight / Chams live color update
                    if visuals and visuals.Highlight then
                        local c = (cfg.RainbowMode and getRainbow()) or cfg.HighlightColor
                        visuals.Highlight.FillColor = c
                        visuals.Highlight.OutlineColor = c
                        visuals.Highlight.FillTransparency = cfg.HighlightTransparency
                    end
                    if visuals and visuals.Chams and not cfg.Highlight then
                        local c = (cfg.RainbowMode and getRainbow()) or cfg.ChamsColor
                        visuals.Chams.FillColor = c
                        visuals.Chams.OutlineColor = c
                        visuals.Chams.FillTransparency = cfg.ChamsTransparency
                    end

                    -- Tracer
                    if visuals and visuals.Tracer then
                        local fromVec =
                            (cfg.TracerFrom == "Bottom" and Vector2.new(viewport.X/2, viewport.Y))
                            or (cfg.TracerFrom == "Center" and Vector2.new(viewport.X/2, viewport.Y/2))
                            or Vector2.new(viewport.X/2, 0)
                        visuals.Tracer.From  = fromVec
                        visuals.Tracer.To    = Vector2.new(screenPos.X, tl.Y + h)
                        visuals.Tracer.Color =
                            (cfg.RainbowMode and getRainbow()) or cfg.TracerColor
                        visuals.Tracer.Thickness = cfg.TracerThickness
                        visuals.Tracer.Transparency = alpha
                        visuals.Tracer.Visible = onScreen
                    end

                    -- Look tracer
                    if visuals and visuals.LookTracer and head then
                        local hp, hon = cam:WorldToViewportPoint(head.Position)
                        if hon then
                            local ep, eon = cam:WorldToViewportPoint(head.Position + head.CFrame.LookVector * 50)
                            if eon then
                                visuals.LookTracer.From = Vector2.new(hp.X, hp.Y)
                                visuals.LookTracer.To   = Vector2.new(ep.X, ep.Y)
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

                    -- Off-screen arrow
                    if visuals and visuals.Arrow and not onScreen then
                        local center = Vector2.new(viewport.X/2, viewport.Y/2)
                        local dir = (Vector2.new(screenPos.X, screenPos.Y) - center).Unit
                        local angle = math.atan2(dir.Y, dir.X)
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
                        if visuals and visuals.Arrow then visuals.Arrow.Visible = false end
                    end

                    -- Snap line
                    if visuals and visuals.SnapLine then
                        visuals.SnapLine.From = Vector2.new(viewport.X/2, viewport.Y/2)
                        visuals.SnapLine.To   = Vector2.new(screenPos.X, screenPos.Y)
                        visuals.SnapLine.Color = baseColor
                        visuals.SnapLine.Thickness = 1
                        visuals.SnapLine.Transparency = alpha
                        visuals.SnapLine.Visible = onScreen
                    end
                else
                    destroyPlayerVisuals(p)
                end

                ::continue::
            end
        end
    end

    ------------------------------------------------------------------------
    -- Module API (Start/Stop/Refresh/Clear/SetUpdateRate/Stats)
    ------------------------------------------------------------------------
    local Module = {}

    function Module.Start()
        -- reset/renew maid
        if Variables.Maids.PlayerESP then
            Variables.Maids.PlayerESP:DoCleaning()
            Variables.Maids.PlayerESP = nil
        end
        Variables.Maids.PlayerESP = Maid.new()

        Variables.PlayerESPSettings.Enabled = true
        Variables.PlayerESPUpdateIntervalSeconds = 1 / math.max(1, tonumber(Variables.PlayerESPSettings.UpdateRate) or 60)

        -- frame update
        Variables.Maids.PlayerESP.RenderConn = RunService.RenderStepped:Connect(updateAll)

        -- track current players
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= Players.LocalPlayer then
                local pm = weakMaidFor(p)
                pm:GiveTask(p.CharacterAdded:Connect(function()
                    task.wait(0.1)
                    if Variables.PlayerESPSettings.Enabled then createPlayerVisuals(p) end
                end))
                pm:GiveTask(p.CharacterRemoving:Connect(function()
                    destroyPlayerVisuals(p)
                end))
                if p.Character then createPlayerVisuals(p) end
            end
        end

        -- roster connections
        Variables.Maids.PlayerESP:GiveTask(Players.PlayerAdded:Connect(function(p)
            if p ~= Players.LocalPlayer then
                local pm = weakMaidFor(p)
                pm:GiveTask(p.CharacterAdded:Connect(function()
                    task.wait(0.1)
                    if Variables.PlayerESPSettings.Enabled then createPlayerVisuals(p) end
                end))
                pm:GiveTask(p.CharacterRemoving:Connect(function() destroyPlayerVisuals(p) end))
            end
        end))
        Variables.Maids.PlayerESP:GiveTask(Players.PlayerRemoving:Connect(function(p)
            destroyPlayerVisuals(p)
        end))

        Module.AttachStatsUpdater()

        -- finalize on maid destroy
        Variables.Maids.PlayerESP:GiveTask(function()
            Variables.PlayerESPSettings.Enabled = false
            for tracked in pairs(Variables.PlayerESPVisualsByPlayer) do
                destroyPlayerVisuals(tracked)
            end
        end)
    end

    function Module.Stop()
        Variables.PlayerESPSettings.Enabled = false

        if Variables.Maids.PlayerESP then
            Variables.Maids.PlayerESP:DoCleaning()
            Variables.Maids.PlayerESP = nil
        end
        if Variables.Maids.PlayerESPStats then
            Variables.Maids.PlayerESPStats:DoCleaning()
            Variables.Maids.PlayerESPStats = nil
        end

        for tracked in pairs(Variables.PlayerESPVisualsByPlayer) do
            destroyPlayerVisuals(tracked)
        end
        for key, m in pairs(Variables.WeakMaids) do
            pcall(function() m:DoCleaning() end)
            Variables.WeakMaids[key] = nil
        end
    end

    function Module.RefreshAll()
        for tracked in pairs(Variables.PlayerESPVisualsByPlayer) do
            destroyPlayerVisuals(tracked)
        end
        if Variables.PlayerESPSettings.Enabled then
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= Players.LocalPlayer and p.Character then
                    createPlayerVisuals(p)
                end
            end
        end
    end

    function Module.ClearAll()
        for tracked in pairs(Variables.PlayerESPVisualsByPlayer) do
            destroyPlayerVisuals(tracked)
        end
    end

    function Module.SetUpdateRate(hz)
        Variables.PlayerESPSettings.UpdateRate = tonumber(hz) or Variables.PlayerESPSettings.UpdateRate
        Variables.PlayerESPUpdateIntervalSeconds = 1 / math.max(1, tonumber(Variables.PlayerESPSettings.UpdateRate) or 60)
    end

    function Module.AttachStatsUpdater()
        if Variables.Maids.PlayerESPStats then return end
        Variables.Maids.PlayerESPStats = Maid.new()

        local last = tick()
        local frames = 0
        Variables.Maids.PlayerESPStats.FPS = RunService.RenderStepped:Connect(function()
            frames += 1
            local now = tick()
            if now - last >= 1 then
                local fps = frames; frames = 0; last = now
                local ui = Variables.PlayerESPUILabels
                if ui and ui.FPS and ui.FPS.SetText then
                    ui.FPS:SetText("FPS: " .. tostring(fps))
                end
                local visible = 0
                for _, visuals in pairs(Variables.PlayerESPVisualsByPlayer) do
                    if visuals and visuals.Box and visuals.Box.Visible then visible += 1 end
                end
                local total = math.max(0, #Players:GetPlayers() - 1)
                if ui and ui.PlayerCount and ui.PlayerCount.SetText then
                    ui.PlayerCount:SetText(("Players Visible: %d/%d"):format(visible, total))
                end
                if ui and ui.Status and ui.Status.SetText then
                    ui.Status:SetText(Variables.PlayerESPSettings.Enabled and "ESP Status: Active" or "ESP Status: Inactive")
                end
            end
        end)
    end

    Variables.PlayerESPModule = Module

    ------------------------------------------------------------------------
    -- UI (Visuals tab)
    ------------------------------------------------------------------------
    local VisualsTab = Tabs.Visuals
    if not VisualsTab then
        warn("[PlayerESP] Tabs.Visuals not found; UI will not be created (feature still functional).")
    else
        local CoreLeft       = VisualsTab:AddLeftGroupbox("Core ESP", "eye")
        local ExtraRight     = VisualsTab:AddRightGroupbox("Additional ESP", "layers")
        local AppearanceLeft = VisualsTab:AddLeftGroupbox("Appearance", "palette")
        local SizeRight      = VisualsTab:AddRightGroupbox("Size Settings", "move-diagonal")
        local FiltersLeft    = VisualsTab:AddLeftGroupbox("Filters", "filter")
        local PerfRight      = VisualsTab:AddRightGroupbox("Performance", "gauge")

        -- Master toggle
        CoreLeft:AddToggle("ESPEnabled", { Text = "Enable ESP", Default = Variables.PlayerESPSettings.Enabled })

        -- Core (with colors)
        CoreLeft:AddToggle("ESPBox", { Text = "Box ESP", Default = Variables.PlayerESPSettings.Box })
            :AddColorPicker("BoxColor", { Title = "Box Color", Default = Variables.PlayerESPSettings.BoxColor })

        CoreLeft:AddToggle("BoxFilled", { Text = "Filled Box", Default = Variables.PlayerESPSettings.BoxFilled })
            :AddColorPicker("BoxFillColor",{ Title = "Fill Color", Default = Variables.PlayerESPSettings.BoxFillColor })

        CoreLeft:AddToggle("ESPName",{ Text = "Name ESP", Default = Variables.PlayerESPSettings.Name })
            :AddColorPicker("NameColor",{ Title = "Name Color", Default = Variables.PlayerESPSettings.NameColor })

        CoreLeft:AddToggle("ESPHealth",{ Text = "Health Text", Default = Variables.PlayerESPSettings.Health })
            :AddColorPicker("HealthColor",{ Title = "Health Color", Default = Variables.PlayerESPSettings.HealthColor })

        CoreLeft:AddToggle("ESPHealthBar",{ Text = "Health Bar", Default = Variables.PlayerESPSettings.HealthBar })
            :AddColorPicker("HealthBarHigh", { Title = "HP High", Default = Variables.PlayerESPSettings.HealthBarColorHigh })
            :AddColorPicker("HealthBarMid",  { Title = "HP Mid",  Default = Variables.PlayerESPSettings.HealthBarColorMid })
            :AddColorPicker("HealthBarLow",  { Title = "HP Low",  Default = Variables.PlayerESPSettings.HealthBarColorLow })

        CoreLeft:AddDropdown("HealthBarStyle", {
            Text = "Health Bar Style", Values = { "Vertical", "Horizontal" },
            Default = Variables.PlayerESPSettings.HealthBarStyle or "Vertical"
        })

        CoreLeft:AddToggle("ESPStud",{ Text = "Distance ESP", Default = Variables.PlayerESPSettings.Stud })
            :AddColorPicker("StudColor",{ Title = "Distance Color", Default = Variables.PlayerESPSettings.StudColor })

        CoreLeft:AddToggle("DisplayName",{ Text = "Show Display Name", Default = Variables.PlayerESPSettings.DisplayName ~= false })

        -- Extra
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
        AppearanceLeft:AddSlider("RainbowSpeed",{ Text = "Rainbow Speed", Default = Variables.PlayerESPSettings.RainbowSpeed or 1, Min = 0.1, Max = 5, Rounding = 1 })
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
        PerfRight:AddButton({ Text = "Refresh All ESP", Func = function() if Variables.PlayerESPModule and Variables.PlayerESPModule.RefreshAll then Variables.PlayerESPModule.RefreshAll() end; if Library and Library.Notify then Library:Notify("ESP Refreshed!", 3) end end })
        PerfRight:AddButton({ Text = "Clear All ESP",   Func = function() if Variables.PlayerESPModule and Variables.PlayerESPModule.ClearAll   then Variables.PlayerESPModule.ClearAll()   end; if Library and Library.Notify then Library:Notify("All ESP Cleared!", 3) end end })

        -- Statistics
        local StatsLeft = VisualsTab:AddLeftGroupbox("Statistics", "bar-chart-3")
        Variables.PlayerESPUILabels.Status      = StatsLeft:AddLabel("ESP Status: Inactive")
        Variables.PlayerESPUILabels.PlayerCount = StatsLeft:AddLabel("Players Visible: 0/0")
        Variables.PlayerESPUILabels.FPS         = StatsLeft:AddLabel("FPS: 0")
        if Variables.PlayerESPModule and Variables.PlayerESPModule.AttachStatsUpdater then
            Variables.PlayerESPModule.AttachStatsUpdater()
        end
    end

    ------------------------------------------------------------------------
    -- UI bindings (OnChanged)
    ------------------------------------------------------------------------
    -- Master toggle start/stop
    if Toggles and Toggles.ESPEnabled and Toggles.ESPEnabled.OnChanged then
        Toggles.ESPEnabled:OnChanged(function(v)
            Variables.PlayerESPSettings.Enabled = v
            local ui = Variables.PlayerESPUILabels
            if ui and ui.Status and ui.Status.SetText then
                ui.Status:SetText(v and "ESP Status: Active" or "ESP Status: Inactive")
            end
            if v then Module.Start() else Module.Stop() end
        end)
    end

    -- UpdateRate binding
    if Options and Options.UpdateRate and Options.UpdateRate.OnChanged then
        Options.UpdateRate:OnChanged(function(value)
            Variables.PlayerESPSettings.UpdateRate = value
            Variables.PlayerESPUpdateIntervalSeconds = 1 / math.max(1, tonumber(value) or 60)
            Module.SetUpdateRate(value)
        end)
    end

    -- Rebuild-required toggles
    local rebuildIds = { "ESPBox","BoxFilled","ESPName","ESPHealth","ESPHealthBar","ArmorBar",
                         "ESPStud","ESPSkeleton","ESPHighlight","ESPChams","ESPTracer","LookTracer",
                         "OutOfView","ESPWeapon","ESPFlags","HeadDot" }
    for _, id in ipairs(rebuildIds) do
        local t = Toggles and Toggles[id]
        if t and t.OnChanged then
            t:OnChanged(function(val)
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
                    id -- BoxFilled/ArmorBar map 1:1
                Variables.PlayerESPSettings[key] = val
                if Variables.PlayerESPSettings.Enabled then Module.RefreshAll() end
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
    for _, pair in ipairs(simple) do
        local id, key = pair[1], pair[2]
        local t = Toggles and Toggles[id]
        if t and t.OnChanged then
            t:OnChanged(function(val) Variables.PlayerESPSettings[key] = val end)
        end
    end

    -- Value options (sliders/dropdowns)
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
    for _, pair in ipairs(optMap) do
        local id, key = pair[1], pair[2]
        local o = Options and Options[id]
        if o and o.OnChanged then
            o:OnChanged(function(val)
                Variables.PlayerESPSettings[key] = val
                if id == "UpdateRate" then Module.SetUpdateRate(val) end
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
    for _, pair in ipairs(colorMap) do
        local id, key = pair[1], pair[2]
        local o = Options and Options[id]
        if o and o.OnChanged then
            o:OnChanged(function(colorVal) Variables.PlayerESPSettings[key] = colorVal end)
        end
    end

    ------------------------------------------------------------------------
    -- Return minimal interface for the loader (Stop is required)
    ------------------------------------------------------------------------
    return {
        Name = "PlayerESP",
        Stop = Module.Stop,
    }
end
