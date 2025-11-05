do
    return function(UI)
        ----------------------------------------------------------------------
        -- Dependencies (from repo base)
        ----------------------------------------------------------------------
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv  = (getgenv and getgenv()) or _G
        GlobalEnv.Signal = GlobalEnv.Signal or loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()
        local Maid       = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        ----------------------------------------------------------------------
        -- State
        ----------------------------------------------------------------------
        local Variables = {
            Maids = {
                NameSpoof = Maid.new(),  -- whole module lifecycle
            },
            RunFlag = false,
            Originals = setmetatable({}, { __mode = "k" }), -- [TextLabel] = raw server text
            Guards    = setmetatable({}, { __mode = "k" }), -- write guards per label
            Spoof = {
                DisplayName = nil, -- set in Start() from UI default (LocalPlayer.DisplayName)
                Username    = nil, -- set in Start() from UI default (LocalPlayer.Name)
            },
        }

        local Players    = RbxService.Players
        local RunService = RbxService.RunService

        ----------------------------------------------------------------------
        -- Utils
        ----------------------------------------------------------------------
        local function escapePattern(s)
            if not s then return "" end
            return (s:gsub("(%W)", "%%%1"))
        end

        local function isNameLabel(inst)
            -- We primarily target TextLabel, but TextButton sometimes gets used for names in custom UIs.
            return typeof(inst) == "Instance" and (inst:IsA("TextLabel") or inst:IsA("TextButton"))
        end

        local function containsOurName(inst, lp)
            if not isNameLabel(inst) then return false end
            local t = inst.Text
            if not t or t == "" then return false end
            if not lp then return false end
            -- Match display name, @username, and bare username
            return t:find(lp.DisplayName, 1, true)
                or t:find("@" .. lp.Name, 1, true)
                or t:find(lp.Name, 1, true)
        end

        local function replaceNames(rawText, lp)
            if not Variables.RunFlag or not lp or not rawText then
                return rawText
            end

            local spoofDisplay = Variables.Spoof.DisplayName or lp.DisplayName
            local spoofUser    = Variables.Spoof.Username or lp.Name

            local result = rawText

            -- Replace DisplayName first (leaderboard shows this), then @username, then bare username.
            result = result:gsub(escapePattern(lp.DisplayName), spoofDisplay)
            result = result:gsub(escapePattern("@" .. lp.Name), "@" .. spoofUser)
            result = result:gsub(escapePattern(lp.Name), spoofUser)

            return result
        end

        local function applyToLabel(lbl, lp)
            if not (lbl and lbl.Parent) then return end
            local raw = Variables.Originals[lbl]
            if raw == nil then
                -- First time seeing this label: capture current server-provided text as "raw".
                raw = lbl.Text
                Variables.Originals[lbl] = raw
            end
            Variables.Guards[lbl] = true
            local ok, err = pcall(function()
                lbl.Text = replaceNames(raw, lp)
            end)
            Variables.Guards[lbl] = nil
            if not ok then warn("[NameSpoofer] apply error:", err) end
        end

        local function untrackLabel(lbl)
            Variables.Originals[lbl] = nil
            Variables.Guards[lbl]    = nil
        end

        local function trackLabel(inst, lp)
            if not isNameLabel(inst) then return end
            if not containsOurName(inst, lp) then
                -- Lightweight watcher: if it ever *becomes* relevant, re-track with full hooks
                local maybeConn
                maybeConn = inst:GetPropertyChangedSignal("Text"):Connect(function()
                    if Variables.Guards[inst] then return end
                    if containsOurName(inst, lp) then
                        if maybeConn then maybeConn:Disconnect() end
                        -- Now set full tracking hooks below
                        trackLabel(inst, lp)
                    end
                end)
                Variables.Maids.NameSpoof:GiveTask(maybeConn)
                return
            end

            -- Capture initial raw and apply if enabled
            Variables.Originals[inst] = inst.Text
            if Variables.RunFlag then
                applyToLabel(inst, lp)
            end

            -- Keep raw in sync with server updates; re-apply spoof while enabled
            local textConn = inst:GetPropertyChangedSignal("Text"):Connect(function()
                if Variables.Guards[inst] then return end
                Variables.Originals[inst] = inst.Text
                if Variables.RunFlag then
                    applyToLabel(inst, lp)
                end
            end)

            -- Cleanup if destroyed
            local ancestryConn = inst.AncestryChanged:Connect(function(_, parent)
                if parent == nil then
                    untrackLabel(inst)
                end
            end)

            Variables.Maids.NameSpoof:GiveTask(textConn)
            Variables.Maids.NameSpoof:GiveTask(ancestryConn)
        end

        local function scanAll(lp)
            for _, inst in ipairs(game:GetDescendants()) do
                trackLabel(inst, lp)
            end
        end

        ----------------------------------------------------------------------
        -- Start / Stop
        ----------------------------------------------------------------------
        local function Start()
            if Variables.RunFlag then return end
            Variables.RunFlag = true

            local lp = Players.LocalPlayer
            if not lp then
                Variables.RunFlag = false
                return
            end

            -- Initialize spoof text from UI defaults (fallback to real values if empty)
            Variables.Spoof.DisplayName = Variables.Spoof.DisplayName or lp.DisplayName
            Variables.Spoof.Username    = Variables.Spoof.Username    or lp.Name

            -- Initial sweep
            scanAll(lp)

            -- Keep tracking new UI (covers CoreGui PlayerList/leaderboard and custom UIs)
            local addConn = game.DescendantAdded:Connect(function(inst)
                if not Variables.RunFlag then return end
                if isNameLabel(inst) then
                    trackLabel(inst, lp)
                    if Variables.RunFlag and Variables.Originals[inst] ~= nil then
                        applyToLabel(inst, lp)
                    end
                end
            end)

            Variables.Maids.NameSpoof:GiveTask(addConn)

            -- Defensive re-application each render (cheap check; helps against very aggressive UI scripts)
            local stepConn = RunService.RenderStepped:Connect(function()
                if not Variables.RunFlag then return end
                for lbl, _ in pairs(Variables.Originals) do
                    if typeof(lbl) == "Instance" and lbl.Parent and isNameLabel(lbl) then
                        applyToLabel(lbl, lp)
                    end
                end
            end)
            Variables.Maids.NameSpoof:GiveTask(stepConn)
        end

        local function Stop()
            if not Variables.RunFlag then return end
            Variables.RunFlag = false

            -- Disconnect everything first so restores don't get intercepted by our listeners
            Variables.Maids.NameSpoof:DoCleaning()

            -- Restore all originals
            for lbl, raw in pairs(Variables.Originals) do
                if typeof(lbl) == "Instance" and lbl.Parent and isNameLabel(lbl) then
                    Variables.Guards[lbl] = true
                    pcall(function()
                        lbl.Text = raw
                    end)
                    Variables.Guards[lbl] = nil
                end
            end

            -- Clear caches
            for k in pairs(Variables.Originals) do Variables.Originals[k] = nil end
            for k in pairs(Variables.Guards)    do Variables.Guards[k]    = nil end
        end

        ----------------------------------------------------------------------
        -- UI (using repo’s UI contract passed as `UI`)
        ----------------------------------------------------------------------
        local groupbox = UI.Tabs.Misc:AddLeftGroupbox("Name Spoofer", "user")
        groupbox:AddToggle("NameSpoofToggle", {
            Text    = "Enable Name Spoofer",
            Tooltip = "Spoofs your Display Name and @username locally (reversible).",
            Default = false,
        })

        -- Two live inputs
        groupbox:AddInput("NS_Display", {
            Text        = "Spoof Display Name",
            Placeholder = Players.LocalPlayer and Players.LocalPlayer.DisplayName or "DisplayName",
            Default     = Players.LocalPlayer and Players.LocalPlayer.DisplayName or "",
            ClearTextOnFocus = false,
            Tooltip     = "Shown on the PlayerList/leaderboard.",
        })

        groupbox:AddInput("NS_User", {
            Text        = "Spoof Username",
            Placeholder = Players.LocalPlayer and Players.LocalPlayer.Name or "Username",
            Default     = Players.LocalPlayer and Players.LocalPlayer.Name or "",
            ClearTextOnFocus = false,
            Tooltip     = "Used in places like @username.",
        })

        -- Wire toggle
        UI.Toggles.NameSpoofToggle:OnChanged(function(state)
            if state then
                Start()
            else
                Stop()
            end
        end)

        -- Wire inputs
        UI.Options.NS_Display:OnChanged(function(newDisplay)
            local lp = Players.LocalPlayer
            Variables.Spoof.DisplayName = (newDisplay and #newDisplay > 0) and newDisplay or (lp and lp.DisplayName or "DisplayName")
            if Variables.RunFlag then
                for lbl, _ in pairs(Variables.Originals) do
                    if typeof(lbl) == "Instance" and lbl.Parent and isNameLabel(lbl) then
                        applyToLabel(lbl, lp)
                    end
                end
            end
        end)

        UI.Options.NS_User:OnChanged(function(newUser)
            local lp = Players.LocalPlayer
            Variables.Spoof.Username = (newUser and #newUser > 0) and newUser or (lp and lp.Name or "Username")
            if Variables.RunFlag then
                for lbl, _ in pairs(Variables.Originals) do
                    if typeof(lbl) == "Instance" and lbl.Parent and isNameLabel(lbl) then
                        applyToLabel(lbl, lp)
                    end
                end
            end
        end)

        ----------------------------------------------------------------------
        -- Module contract
        ----------------------------------------------------------------------
        return {
            Name = "NameSpoofer",
            Stop = Stop
        }
    end
end
