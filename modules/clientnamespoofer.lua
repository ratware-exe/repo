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
                NameSpoof   = Maid.new(), -- label tracking + listeners
                Avatar      = Maid.new(), -- image tracking + listeners
            },

            -- Name spoofing
            RunFlag   = false, -- name spoof enable flag
            Originals = setmetatable({}, { __mode = "k" }), -- [TextLabel/TextButton] = raw server text
            Guards    = setmetatable({}, { __mode = "k" }), -- write guards per label
            Spoof = {
                DisplayName = nil, -- set in Start() from UI default (LocalPlayer.DisplayName)
                Username    = nil, -- set in Start() from UI default (LocalPlayer.Name)
            },
            CopyBackup = nil, -- used to restore spoof values when copy mode is turned off

            -- Avatar spoofing (profile picture)
            Avatar = {
                IsRunning   = false,      -- image tracking is active if either Blank or Copy is enabled
                EnabledBlank= false,      -- blanking toggle
                EnabledCopy = false,      -- copy toggle
                CopyUserId  = nil,        -- target user id to copy (for images)
                Originals   = setmetatable({}, { __mode = "k" }), -- [ImageLabel/ImageButton] = {Image, ImageTransparency}
                Guards      = setmetatable({}, { __mode = "k" }), -- write guards per image
            },
        }

        local Players      = RbxService.Players
        local RunService   = RbxService.RunService
        local UserService  = RbxService.UserService or game:GetService("UserService")

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

        local function isAvatarImage(inst)
            return typeof(inst) == "Instance" and (inst:IsA("ImageLabel") or inst:IsA("ImageButton"))
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

        -- Heuristic: does the Image content likely show the given userId's avatar thumbnail?
        local function imageShowsUserId(image, userId)
            if type(image) ~= "string" or image == "" or not userId then return false end
            local uid = tostring(userId)
            -- Common patterns:
            -- rbxthumb://type=AvatarHeadShot&id=USERID&w=420&h=420
            -- rbxthumb://type=AvatarBust&id=USERID&...
            -- https://www.roblox.com/headshot-thumbnail/image?userId=USERID&...
            if image:find("rbxthumb://", 1, true) then
                if image:find("id=" .. uid, 1, true) then return true end
                if image:find("userId=" .. uid, 1, true) then return true end
            elseif image:find("roblox%.com") then
                if image:find("userId=" .. uid, 1, true) then return true end
            end
            return false
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

        ----------------------------------------------------------------------
        -- Name labels: track/apply
        ----------------------------------------------------------------------
        local function applyToLabel(lbl, lp)
            if not (lbl and lbl.Parent) then return end
            local raw = Variables.Originals[lbl]
            if raw == nil then
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

        local function scanAllLabels(lp)
            for _, inst in ipairs(game:GetDescendants()) do
                trackLabel(inst, lp)
            end
        end

        ----------------------------------------------------------------------
        -- Avatar images: track/apply
        ----------------------------------------------------------------------
        local function applyAvatarToImage(img, lp)
            if not (img and img.Parent) then return end
            local avatar = Variables.Avatar

            -- Capture original on first touch
            if avatar.Originals[img] == nil then
                avatar.Originals[img] = {
                    Image = img.Image,
                    ImageTransparency = img.ImageTransparency,
                }
            end

            avatar.Guards[img] = true
            local ok, err = pcall(function()
                if avatar.EnabledCopy and avatar.CopyUserId then
                    -- Copy target's headshot
                    local thumb, _ = Players:GetUserThumbnailAsync(avatar.CopyUserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
                    if thumb and thumb ~= "" then
                        img.Image = thumb
                        img.ImageTransparency = 0
                    end
                elseif avatar.EnabledBlank then
                    -- Blank out (make fully transparent)
                    img.ImageTransparency = 1
                else
                    -- Restore original
                    local orig = avatar.Originals[img]
                    if orig then
                        img.Image = orig.Image
                        img.ImageTransparency = orig.ImageTransparency
                    end
                end
            end)
            avatar.Guards[img] = nil

            if not ok then warn("[NameSpoofer] avatar apply error:", err) end
        end

        local function untrackAvatarImage(img)
            Variables.Avatar.Originals[img] = nil
            Variables.Avatar.Guards[img]    = nil
        end

        local function trackAvatarImage(inst, lp)
            if not isAvatarImage(inst) then return end

            -- Only track images that are very likely to be the LocalPlayer's avatar headshot/bust
            -- (We still re-check on change, in case UI swaps later.)
            local function eligible(nowImg)
                return imageShowsUserId(nowImg, lp and lp.UserId)
            end

            local currentImage = inst.Image
            if not eligible(currentImage) then
                -- Lightweight watcher: if later becomes our avatar, switch to full tracking
                local maybeConn
                maybeConn = inst:GetPropertyChangedSignal("Image"):Connect(function()
                    if Variables.Avatar.Guards[inst] then return end
                    if eligible(inst.Image) then
                        if maybeConn then maybeConn:Disconnect() end
                        trackAvatarImage(inst, lp)
                    end
                end)
                Variables.Maids.Avatar:GiveTask(maybeConn)
                return
            end

            -- Capture original and immediately apply if feature is active
            Variables.Avatar.Originals[inst] = {
                Image = inst.Image,
                ImageTransparency = inst.ImageTransparency,
            }
            if Variables.Avatar.EnabledBlank or Variables.Avatar.EnabledCopy then
                applyAvatarToImage(inst, lp)
            end

            -- Keep raw (original) in sync with server updates; re-apply active mode
            local imgConn = inst:GetPropertyChangedSignal("Image"):Connect(function()
                if Variables.Avatar.Guards[inst] then return end
                Variables.Avatar.Originals[inst] = {
                    Image = inst.Image,
                    ImageTransparency = inst.ImageTransparency,
                }
                if Variables.Avatar.EnabledBlank or Variables.Avatar.EnabledCopy then
                    applyAvatarToImage(inst, lp)
                end
            end)

            local ancestryConn = inst.AncestryChanged:Connect(function(_, parent)
                if parent == nil then
                    untrackAvatarImage(inst)
                end
            end)

            Variables.Maids.Avatar:GiveTask(imgConn)
            Variables.Maids.Avatar:GiveTask(ancestryConn)
        end

        local function scanAllAvatarImages(lp)
            for _, inst in ipairs(game:GetDescendants()) do
                trackAvatarImage(inst, lp)
            end
        end

        local function ensureAvatarRunning()
            local avatar = Variables.Avatar
            if avatar.IsRunning then return end
            if not (avatar.EnabledBlank or avatar.EnabledCopy) then return end
            avatar.IsRunning = true

            local lp = Players.LocalPlayer
            if not lp then
                avatar.IsRunning = false
                return
            end

            -- Initial sweep
            scanAllAvatarImages(lp)

            -- Track new descendants
            local addConn = game.DescendantAdded:Connect(function(inst)
                if not avatar.IsRunning then return end
                if isAvatarImage(inst) then
                    trackAvatarImage(inst, lp)
                    if avatar.IsRunning and avatar.Originals[inst] ~= nil then
                        applyAvatarToImage(inst, lp)
                    end
                end
            end)
            Variables.Maids.Avatar:GiveTask(addConn)

            -- Defensive refresh (cheap) against aggressive UI
            local stepConn = RunService.RenderStepped:Connect(function()
                if not avatar.IsRunning then return end
                for img, _ in pairs(avatar.Originals) do
                    if typeof(img) == "Instance" and img.Parent and isAvatarImage(img) then
                        applyAvatarToImage(img, lp)
                    end
                end
            end)
            Variables.Maids.Avatar:GiveTask(stepConn)
        end

        local function ensureAvatarStopped()
            local avatar = Variables.Avatar
            if not avatar.IsRunning then return end
            avatar.IsRunning = false

            -- Disconnect all avatar tasks first
            Variables.Maids.Avatar:DoCleaning()

            -- Restore all images we have touched/tracked
            for img, orig in pairs(avatar.Originals) do
                if typeof(img) == "Instance" and img.Parent and isAvatarImage(img) and orig then
                    avatar.Guards[img] = true
                    pcall(function()
                        img.Image = orig.Image
                        img.ImageTransparency = orig.ImageTransparency
                    end)
                    avatar.Guards[img] = nil
                end
            end

            -- Clear caches
            for k in pairs(avatar.Originals) do avatar.Originals[k] = nil end
            for k in pairs(avatar.Guards)    do avatar.Guards[k]    = nil end
        end

        local function refreshAllAvatarImages()
            local lp = Players.LocalPlayer
            if not lp then return end
            for img, _ in pairs(Variables.Avatar.Originals) do
                if typeof(img) == "Instance" and img.Parent and isAvatarImage(img) then
                    applyAvatarToImage(img, lp)
                end
            end
        end

        ----------------------------------------------------------------------
        -- Name Spoof Start / Stop
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
            scanAllLabels(lp)

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
            if Variables.RunFlag then
                Variables.RunFlag = false

                -- Disconnect everything first so restores don't get intercepted by our listeners
                Variables.Maids.NameSpoof:DoCleaning()

                -- Restore all originals (labels)
                for lbl, raw in pairs(Variables.Originals) do
                    if typeof(lbl) == "Instance" and lbl.Parent and isNameLabel(lbl) then
                        Variables.Guards[lbl] = true
                        pcall(function()
                            lbl.Text = raw
                        end)
                        Variables.Guards[lbl] = nil
                    end
                end

                -- Clear name caches
                for k in pairs(Variables.Originals) do Variables.Originals[k] = nil end
                for k in pairs(Variables.Guards)    do Variables.Guards[k]    = nil end
            end

            -- Also fully stop avatar features (so module Stop always restores everything)
            ensureAvatarStopped()
            Variables.Avatar.EnabledBlank = false
            Variables.Avatar.EnabledCopy  = false
            Variables.Avatar.CopyUserId   = nil

            -- Restore spoof values if copy mode had changed them
            if Variables.CopyBackup then
                Variables.Spoof.DisplayName = Variables.CopyBackup.DisplayName
                Variables.Spoof.Username    = Variables.CopyBackup.Username
                Variables.CopyBackup = nil
            end
        end

        ----------------------------------------------------------------------
        -- Resolve target user (username or userId) for copy feature
        ----------------------------------------------------------------------
        local function trim(s)
            return (s and s:gsub("^%s+", ""):gsub("%s+$", "")) or s
        end

        local function resolveTargetUserId(input)
            input = trim(input or "")
            if not input or input == "" then return nil end

            -- Strip leading "@" if provided
            if input:sub(1,1) == "@" then
                input = input:sub(2)
            end

            local asNum = tonumber(input)
            if asNum and asNum > 0 then
                return math.floor(asNum + 0.5)
            end

            -- Username -> userId
            local ok, uid = pcall(function()
                return Players:GetUserIdFromNameAsync(input)
            end)
            if ok and uid then return uid end
            return nil
        end

        local function getNamesForUserId(uid)
            local username, displayName

            -- Try to get Player instance first (in-server gives most accurate display name)
            local plr = Players:GetPlayerByUserId(uid)
            if plr then
                username    = plr.Name
                displayName = plr.DisplayName
                return username, displayName
            end

            -- Fallbacks
            local okU, nameFromId = pcall(function()
                return Players:GetNameFromUserIdAsync(uid)
            end)
            if okU and nameFromId then
                username = nameFromId
            end

            local okD, infos = pcall(function()
                return UserService:GetUserInfosByUserIdsAsync({ uid })
            end)
            if okD and type(infos) == "table" and infos[1] then
                displayName = infos[1].DisplayName or infos[1].displayName
                username    = username or infos[1].Username or infos[1].username
            end

            -- Final fallback: if no display name, mirror the username
            displayName = displayName or username
            return username, displayName
        end

        local function applyCopyProfile(uid)
            if not uid then return false end

            local username, displayName = getNamesForUserId(uid)
            if not username and not displayName then
                return false
            end

            local lp = Players.LocalPlayer
            if not lp then return false end

            -- Backup current spoof values (only once per copy session)
            if not Variables.CopyBackup then
                Variables.CopyBackup = {
                    DisplayName = Variables.Spoof.DisplayName or (lp and lp.DisplayName) or "",
                    Username    = Variables.Spoof.Username    or (lp and lp.Name)        or "",
                }
            end

            -- Update spoof targets
            Variables.Avatar.CopyUserId  = uid
            Variables.Spoof.Username     = username or (lp and lp.Name)
            Variables.Spoof.DisplayName  = displayName or (lp and lp.DisplayName)

            -- Reflect into UI inputs if supported (safe pcall)
            pcall(function()
                if UI.Options and UI.Options.NS_Display and UI.Options.NS_Display.SetValue then
                    UI.Options.NS_Display:SetValue(Variables.Spoof.DisplayName)
                end
                if UI.Options and UI.Options.NS_User and UI.Options.NS_User.SetValue then
                    UI.Options.NS_User:SetValue(Variables.Spoof.Username)
                end
            end)

            -- If name spoofing is enabled, push changes to all tracked labels
            if Variables.RunFlag then
                for lbl, _ in pairs(Variables.Originals) do
                    if typeof(lbl) == "Instance" and lbl.Parent and isNameLabel(lbl) then
                        applyToLabel(lbl, lp)
                    end
                end
            end

            -- For avatar images, enable Copy mode and refresh
            Variables.Avatar.EnabledCopy = true
            ensureAvatarRunning()
            refreshAllAvatarImages()

            return true
        end

        ----------------------------------------------------------------------
        -- UI (using repo’s UI contract passed as `UI`)
        ----------------------------------------------------------------------
        -- Name spoof controls
        local nameBox = UI.Tabs.Misc:AddLeftGroupbox("Name Spoofer", "user")
        nameBox:AddToggle("NameSpoofToggle", {
            Text    = "Enable Name Spoofer",
            Tooltip = "Spoofs your Display Name and @username locally (reversible).",
            Default = false,
        })

        -- Two live inputs
        nameBox:AddInput("NS_Display", {
            Text        = "Spoof Display Name",
            Placeholder = Players.LocalPlayer and Players.LocalPlayer.DisplayName or "DisplayName",
            Default     = Players.LocalPlayer and Players.LocalPlayer.DisplayName or "",
            ClearTextOnFocus = false,
            Tooltip     = "Shown on the PlayerList/leaderboard.",
        })

        nameBox:AddInput("NS_User", {
            Text        = "Spoof Username",
            Placeholder = Players.LocalPlayer and Players.LocalPlayer.Name or "Username",
            Default     = Players.LocalPlayer and Players.LocalPlayer.Name or "",
            ClearTextOnFocus = false,
            Tooltip     = "Used in places like @username.",
        })

        -- Avatar tools
        local avatarBox = UI.Tabs.Misc:AddLeftGroupbox("Avatar Tools", "image")
        avatarBox:AddToggle("AvatarBlankToggle", {
            Text    = "Blank Profile Picture",
            Tooltip = "Hides your avatar headshot in UI elements (reversible).",
            Default = false,
        })
        avatarBox:AddToggle("AvatarCopyToggle", {
            Text    = "Copy Profile (PFP + Names)",
            Tooltip = "Copies another player's avatar picture and names (enter target below).",
            Default = false,
        })
        avatarBox:AddInput("AvatarCopyTarget", {
            Text        = "Target Username or UserId",
            Placeholder = "name or 123456",
            Default     = "",
            ClearTextOnFocus = false,
            Tooltip     = "Type a username (with or without @) or a numeric userId.",
        })

        ----------------------------------------------------------------------
        -- Wire name spoof controls
        ----------------------------------------------------------------------
        UI.Toggles.NameSpoofToggle:OnChanged(function(state)
            if state then
                Start()
            else
                Stop()
            end
        end)

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
        -- Wire avatar tools
        ----------------------------------------------------------------------
        -- Blank toggle
        UI.Toggles.AvatarBlankToggle:OnChanged(function(state)
            Variables.Avatar.EnabledBlank = state
            if state then
                ensureAvatarRunning()
                refreshAllAvatarImages()
            else
                -- If copy is still enabled, keep running; otherwise stop & restore
                if not Variables.Avatar.EnabledCopy then
                    ensureAvatarStopped()
                else
                    refreshAllAvatarImages()
                end
            end
        end)

        -- Copy toggle
        UI.Toggles.AvatarCopyToggle:OnChanged(function(state)
            if state then
                local rawTarget = ""
                pcall(function()
                    rawTarget = UI.Options.AvatarCopyTarget and UI.Options.AvatarCopyTarget.Value or ""
                end)

                local uid = resolveTargetUserId(rawTarget)
                if not uid then
                    warn("[NameSpoofer] Invalid copy target. Enter username or userId.")
                    -- Disable copy toggle gracefully if target invalid
                    Variables.Avatar.EnabledCopy = false
                    -- Keep blank state unchanged
                    if not Variables.Avatar.EnabledBlank then
                        ensureAvatarStopped()
                    end
                    return
                end

                Variables.Avatar.EnabledCopy = true
                ensureAvatarRunning()
                applyCopyProfile(uid) -- sets spoof names + avatar copy

            else
                -- Turn off copy: restore spoof values and (if no blank) stop avatar tracking
                Variables.Avatar.EnabledCopy = false
                Variables.Avatar.CopyUserId  = nil

                -- Restore spoof values if we have a backup
                if Variables.CopyBackup then
                    Variables.Spoof.DisplayName = Variables.CopyBackup.DisplayName
                    Variables.Spoof.Username    = Variables.CopyBackup.Username
                    Variables.CopyBackup = nil

                    local lp = Players.LocalPlayer
                    if Variables.RunFlag and lp then
                        for lbl, _ in pairs(Variables.Originals) do
                            if typeof(lbl) == "Instance" and lbl.Parent and isNameLabel(lbl) then
                                applyToLabel(lbl, lp)
                            end
                        end
                    end

                    -- Reflect into UI inputs if supported
                    pcall(function()
                        if UI.Options and UI.Options.NS_Display and UI.Options.NS_Display.SetValue then
                            UI.Options.NS_Display:SetValue(Variables.Spoof.DisplayName)
                        end
                        if UI.Options and UI.Options.NS_User and UI.Options.NS_User.SetValue then
                            UI.Options.NS_User:SetValue(Variables.Spoof.Username)
                        end
                    end)
                end

                if not Variables.Avatar.EnabledBlank then
                    ensureAvatarStopped()
                else
                    refreshAllAvatarImages()
                end
            end
        end)

        -- Copy target input (live re-apply when copy toggle is ON)
        UI.Options.AvatarCopyTarget:OnChanged(function(newValue)
            if not Variables.Avatar.EnabledCopy then return end
            local uid = resolveTargetUserId(newValue)
            if not uid then return end
            applyCopyProfile(uid)
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
