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
                NameSpoof = Maid.new(),
                Avatar    = Maid.new(),
            },

            -- Name spoof
            RunFlag   = false,
            Originals = setmetatable({}, { __mode = "k" }), -- [TextLabel/TextButton] = raw text
            Guards    = setmetatable({}, { __mode = "k" }),
            Spoof = { DisplayName = nil, Username = nil },
            CopyBackup = nil,

            -- Avatar spoof
            Avatar = {
                IsRunning    = false,
                EnabledBlank = false,
                EnabledCopy  = false,
                CopyUserId   = nil,
                Originals    = setmetatable({}, { __mode = "k" }), -- [ImageLabel/ImageButton] = {Image, ImageTransparency}
                Guards       = setmetatable({}, { __mode = "k" }),
            },
        }

        local Players     = RbxService.Players
        local RunService  = RbxService.RunService
        local UserService = RbxService.UserService or game:GetService("UserService")

        ----------------------------------------------------------------------
        -- Helpers: thumbnail parsing / building so copied PFP matches original type & size
        ----------------------------------------------------------------------
        local function tolower(s) return (s and string.lower(s)) or "" end

        local ThumbnailTypeMap = {
            AvatarHeadShot  = Enum.ThumbnailType.HeadShot,
            AvatarBust      = Enum.ThumbnailType.AvatarBust,
            AvatarThumbnail = Enum.ThumbnailType.AvatarThumbnail,
        }

        local function parseThumbMeta(url)
            if type(url) ~= "string" or url == "" then return nil end
            local L = tolower(url)
            local meta = { typ = "AvatarHeadShot", w = 420, h = 420 }

            if string.find(L, "^rbxthumb://", 1, true) then
                local t  = url:match("type=([^&]+)")
                local w  = tonumber(url:match("[?&]w=(%d+)"))
                local h  = tonumber(url:match("[?&]h=(%d+)"))
                if t and ThumbnailTypeMap[t] then meta.typ = t end
                if w then meta.w = w end
                if h then meta.h = h end
                return meta
            end

            if string.find(L, "avatar%-bust") or string.find(L, "type=avatarbust") then
                meta.typ = "AvatarBust"
            elseif string.find(L, "avatar%-thumbnail") or string.find(L, "type=avatarthumbnail") then
                meta.typ = "AvatarThumbnail"
            else
                meta.typ = "AvatarHeadShot"
            end

            meta.w = tonumber(url:match("[?&]w=(%d+)") or url:match("[?&]width=(%d+)")) or meta.w
            meta.h = tonumber(url:match("[?&]h=(%d+)") or url:match("[?&]height=(%d+)")) or meta.h
            return meta
        end

        local function buildRbxThumb(uid, meta)
            local w = tonumber(meta and meta.w) or 420
            local h = tonumber(meta and meta.h) or 420
            local t = (meta and meta.typ) or "AvatarHeadShot"
            return string.format("rbxthumb://type=%s&id=%d&w=%d&h=%d", t, uid, w, h)
        end

        local SizeList = { 420, 352, 180, 150, 100, 60, 48 }
        local SizeEnum = {
            [420] = Enum.ThumbnailSize.Size420x420,
            [352] = Enum.ThumbnailSize.Size352x352,
            [180] = Enum.ThumbnailSize.Size180x180,
            [150] = Enum.ThumbnailSize.Size150x150,
            [100] = Enum.ThumbnailSize.Size100x100,
            [60]  = Enum.ThumbnailSize.Size60x60,
            [48]  = Enum.ThumbnailSize.Size48x48,
        }
        local function nearestSize(n)
            n = tonumber(n) or 420
            local best, d = 420, math.huge
            for _, v in ipairs(SizeList) do
                local dv = math.abs(v - n)
                if dv < d then d = dv; best = v end
            end
            return SizeEnum[best]
        end

        ----------------------------------------------------------------------
        -- Common utilities
        ----------------------------------------------------------------------
        local function escapePattern(s) return (s and s:gsub("(%W)", "%%%1")) or "" end

        local function isNameLabel(inst)
            return typeof(inst) == "Instance" and (inst:IsA("TextLabel") or inst:IsA("TextButton"))
        end
        local function isAvatarImage(inst)
            return typeof(inst) == "Instance" and (inst:IsA("ImageLabel") or inst:IsA("ImageButton"))
        end
        local function containsOurName(inst, lp)
            if not isNameLabel(inst) then return false end
            local t = inst.Text
            if not t or t == "" or not lp then return false end
            return t:find(lp.DisplayName, 1, true) or t:find("@" .. lp.Name, 1, true) or t:find(lp.Name, 1, true)
        end
        local function imageShowsUserId(image, userId)
            if type(image) ~= "string" or image == "" or not userId then return false end
            local uid = tostring(userId)
            if image:find("rbxthumb://", 1, true) then
                return image:find("id=" .. uid, 1, true) or image:find("userId=" .. uid, 1, true) or false
            elseif image:find("roblox%.com") then
                return image:find("userId=" .. uid, 1, true) or false
            end
            return false
        end

        ----------------------------------------------------------------------
        -- Name labels: track/apply
        ----------------------------------------------------------------------
        local function replaceNames(rawText, lp)
            if not Variables.RunFlag or not lp or not rawText then return rawText end
            local spoofDisplay = Variables.Spoof.DisplayName or lp.DisplayName
            local spoofUser    = Variables.Spoof.Username or lp.Name
            local result = rawText
            result = result:gsub(escapePattern(lp.DisplayName), spoofDisplay)
            result = result:gsub(escapePattern("@" .. lp.Name), "@" .. spoofUser)
            result = result:gsub(escapePattern(lp.Name), spoofUser)
            return result
        end

        local function applyToLabel(lbl, lp)
            if not (lbl and lbl.Parent) then return end
            local raw = Variables.Originals[lbl]
            if raw == nil then raw = lbl.Text; Variables.Originals[lbl] = raw end
            Variables.Guards[lbl] = true
            local ok, err = pcall(function() lbl.Text = replaceNames(raw, lp) end)
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

            Variables.Originals[inst] = inst.Text
            if Variables.RunFlag then applyToLabel(inst, lp) end

            local textConn = inst:GetPropertyChangedSignal("Text"):Connect(function()
                if Variables.Guards[inst] then return end
                Variables.Originals[inst] = inst.Text
                if Variables.RunFlag then applyToLabel(inst, lp) end
            end)
            local ancestryConn = inst.AncestryChanged:Connect(function(_, parent)
                if parent == nil then untrackLabel(inst) end
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
        -- Avatar images: track/apply  (uses preserved type/size)
        ----------------------------------------------------------------------
        local function applyAvatarToImage(img, lp)
            if not (img and img.Parent) then return end
            local avatar = Variables.Avatar

            if avatar.Originals[img] == nil then
                avatar.Originals[img] = { Image = img.Image, ImageTransparency = img.ImageTransparency }
            end

            avatar.Guards[img] = true
            local ok, err = pcall(function()
                if avatar.EnabledCopy and avatar.CopyUserId then
                    local src  = avatar.Originals[img] and avatar.Originals[img].Image or img.Image
                    local meta = parseThumbMeta(src)
                    if meta then
                        img.Image = buildRbxThumb(avatar.CopyUserId, meta)
                        img.ImageTransparency = 0
                    else
                        -- fallback: nearest enum size & same general type guess
                        local L = tolower(src or "")
                        local typ = "AvatarHeadShot"
                        if string.find(L, "avatar%-bust") or string.find(L, "type=avatarbust") then
                            typ = "AvatarBust"
                        elseif string.find(L, "avatar%-thumbnail") or string.find(L, "type=avatarthumbnail") then
                            typ = "AvatarThumbnail"
                        end
                        local w = tonumber(src and (src:match("[?&]w=(%d+)") or src:match("[?&]width=(%d+)"))) or 420
                        local thumbType = ThumbnailTypeMap[typ] or Enum.ThumbnailType.HeadShot
                        local sizeEnum  = nearestSize(w)
                        local content, _ = Players:GetUserThumbnailAsync(avatar.CopyUserId, thumbType, sizeEnum)
                        if content and content ~= "" then
                            img.Image = content
                            img.ImageTransparency = 0
                        end
                    end
                elseif avatar.EnabledBlank then
                    img.ImageTransparency = 1
                else
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
            local function eligible(nowImg) return imageShowsUserId(nowImg, lp and lp.UserId) end

            if not eligible(inst.Image) then
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

            Variables.Avatar.Originals[inst] = { Image = inst.Image, ImageTransparency = inst.ImageTransparency }
            if Variables.Avatar.EnabledBlank or Variables.Avatar.EnabledCopy then
                applyAvatarToImage(inst, lp)
            end

            local imgConn = inst:GetPropertyChangedSignal("Image"):Connect(function()
                if Variables.Avatar.Guards[inst] then return end
                Variables.Avatar.Originals[inst] = { Image = inst.Image, ImageTransparency = inst.ImageTransparency }
                if Variables.Avatar.EnabledBlank or Variables.Avatar.EnabledCopy then
                    applyAvatarToImage(inst, lp)
                end
            end)
            local ancestryConn = inst.AncestryChanged:Connect(function(_, parent)
                if parent == nil then untrackAvatarImage(inst) end
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
            if avatar.IsRunning or not (avatar.EnabledBlank or avatar.EnabledCopy) then return end
            avatar.IsRunning = true
            local lp = Players.LocalPlayer
            if not lp then avatar.IsRunning = false; return end
            scanAllAvatarImages(lp)
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
            Variables.Maids.Avatar:DoCleaning()
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
        -- Start / Stop (names) + full restore
        ----------------------------------------------------------------------
        local function Start()
            if Variables.RunFlag then return end
            Variables.RunFlag = true
            local lp = Players.LocalPlayer
            if not lp then Variables.RunFlag = false; return end
            Variables.Spoof.DisplayName = Variables.Spoof.DisplayName or lp.DisplayName
            Variables.Spoof.Username    = Variables.Spoof.Username    or lp.Name
            scanAllLabels(lp)
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
                Variables.Maids.NameSpoof:DoCleaning()
                for lbl, raw in pairs(Variables.Originals) do
                    if typeof(lbl) == "Instance" and lbl.Parent and isNameLabel(lbl) then
                        Variables.Guards[lbl] = true
                        pcall(function() lbl.Text = raw end)
                        Variables.Guards[lbl] = nil
                    end
                end
                for k in pairs(Variables.Originals) do Variables.Originals[k] = nil end
                for k in pairs(Variables.Guards)    do Variables.Guards[k]    = nil end
            end

            ensureAvatarStopped()
            Variables.Avatar.EnabledBlank = false
            Variables.Avatar.EnabledCopy  = false
            Variables.Avatar.CopyUserId   = nil

            if Variables.CopyBackup then
                Variables.Spoof.DisplayName = Variables.CopyBackup.DisplayName
                Variables.Spoof.Username    = Variables.CopyBackup.Username
                Variables.CopyBackup = nil
            end
        end

        ----------------------------------------------------------------------
        -- Resolve/copy profile
        ----------------------------------------------------------------------
        local function trim(s) return (s and s:gsub("^%s+", ""):gsub("%s+$", "")) or s end
        local function resolveTargetUserId(input)
            input = trim(input or ""); if input == "" then return nil end
            if input:sub(1,1) == "@" then input = input:sub(2) end
            local asNum = tonumber(input); if asNum and asNum > 0 then return math.floor(asNum + 0.5) end
            local ok, uid = pcall(function() return Players:GetUserIdFromNameAsync(input) end)
            if ok and uid then return uid end
            return nil
        end
        local function getNamesForUserId(uid)
            local username, displayName
            local plr = Players:GetPlayerByUserId(uid)
            if plr then return plr.Name, plr.DisplayName end
            local okU, nameFromId = pcall(function() return Players:GetNameFromUserIdAsync(uid) end)
            if okU and nameFromId then username = nameFromId end
            local okD, infos = pcall(function() return UserService:GetUserInfosByUserIdsAsync({ uid }) end)
            if okD and type(infos) == "table" and infos[1] then
                displayName = infos[1].DisplayName or infos[1].displayName
                username    = username or infos[1].Username or infos[1].username
            end
            displayName = displayName or username
            return username, displayName
        end
        local function applyCopyProfile(uid)
            if not uid then return false end
            local username, displayName = getNamesForUserId(uid)
            if not username and not displayName then return false end
            local lp = Players.LocalPlayer
            if not lp then return false end
            if not Variables.CopyBackup then
                Variables.CopyBackup = {
                    DisplayName = Variables.Spoof.DisplayName or (lp and lp.DisplayName) or "",
                    Username    = Variables.Spoof.Username    or (lp and lp.Name)        or "",
                }
            end
            Variables.Avatar.CopyUserId = uid
            Variables.Spoof.Username    = username    or (lp and lp.Name)
            Variables.Spoof.DisplayName = displayName or (lp and lp.DisplayName)
            pcall(function()
                if UI.Options and UI.Options.NS_Display and UI.Options.NS_Display.SetValue then
                    UI.Options.NS_Display:SetValue(Variables.Spoof.DisplayName)
                end
                if UI.Options and UI.Options.NS_User and UI.Options.NS_User.SetValue then
                    UI.Options.NS_User:SetValue(Variables.Spoof.Username)
                end
            end)
            if Variables.RunFlag then
                for lbl, _ in pairs(Variables.Originals) do
                    if typeof(lbl) == "Instance" and lbl.Parent and isNameLabel(lbl) then
                        applyToLabel(lbl, lp)
                    end
                end
            end
            Variables.Avatar.EnabledCopy = true
            ensureAvatarRunning()
            refreshAllAvatarImages()
            return true
        end

        ----------------------------------------------------------------------
        -- UI: everything in ONE groupbox
        ----------------------------------------------------------------------
        local groupbox = UI.Tabs.Misc:AddLeftGroupbox("Name & Avatar Spoofer", "user")

        -- Name spoofing
        groupbox:AddToggle("NameSpoofToggle", {
            Text = "Enable Name Spoofer",
            Tooltip = "Spoofs Display Name and @username locally (reversible).",
            Default = false,
        })
        groupbox:AddInput("NS_Display", {
            Text = "Spoof Display Name",
            Placeholder = Players.LocalPlayer and Players.LocalPlayer.DisplayName or "DisplayName",
            Default = Players.LocalPlayer and Players.LocalPlayer.DisplayName or "",
            ClearTextOnFocus = false,
            Tooltip = "Shown on the PlayerList/leaderboard.",
        })
        groupbox:AddInput("NS_User", {
            Text = "Spoof Username",
            Placeholder = Players.LocalPlayer and Players.LocalPlayer.Name or "Username",
            Default = Players.LocalPlayer and Players.LocalPlayer.Name or "",
            ClearTextOnFocus = false,
            Tooltip = "Used in places like @username.",
        })

        -- Avatar tools (same groupbox)
        groupbox:AddToggle("AvatarBlankToggle", {
            Text = "Blank Profile Picture",
            Tooltip = "Hides your avatar headshot in UI elements (reversible).",
            Default = false,
        })
        groupbox:AddToggle("AvatarCopyToggle", {
            Text = "Copy Profile (PFP + Names)",
            Tooltip = "Copies another player's avatar picture and names.",
            Default = false,
        })
        groupbox:AddInput("AvatarCopyTarget", {
            Text = "Target Username or UserId",
            Placeholder = "name or 123456",
            Default = "",
            ClearTextOnFocus = false,
        })

        ----------------------------------------------------------------------
        -- Wire controls
        ----------------------------------------------------------------------
        UI.Toggles.NameSpoofToggle:OnChanged(function(state) if state then Start() else Stop() end end)

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

        UI.Toggles.AvatarBlankToggle:OnChanged(function(state)
            Variables.Avatar.EnabledBlank = state
            if state then
                ensureAvatarRunning()
                refreshAllAvatarImages()
            else
                if not Variables.Avatar.EnabledCopy then
                    ensureAvatarStopped()
                else
                    refreshAllAvatarImages()
                end
            end
        end)

        UI.Toggles.AvatarCopyToggle:OnChanged(function(state)
            if state then
                local rawTarget = ""
                pcall(function()
                    rawTarget = UI.Options.AvatarCopyTarget and UI.Options.AvatarCopyTarget.Value or ""
                end)
                local uid = resolveTargetUserId(rawTarget)
                if not uid then
                    warn("[NameSpoofer] Invalid copy target. Enter username or userId.")
                    Variables.Avatar.EnabledCopy = false
                    if not Variables.Avatar.EnabledBlank then ensureAvatarStopped() end
                    return
                end
                Variables.Avatar.EnabledCopy = true
                ensureAvatarRunning()
                applyCopyProfile(uid)
            else
                Variables.Avatar.EnabledCopy = false
                Variables.Avatar.CopyUserId  = nil

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
                    pcall(function()
                        if UI.Options and UI.Options.NS_Display and UI.Options.NS_Display.SetValue then
                            UI.Options.NS_Display:SetValue(Variables.Spoof.DisplayName)
                        end
                        if UI.Options and UI.Options.NS_User and UI.Options.NS_User.SetValue then
                            UI.Options.NS_User:SetValue(Variables.Spoof.Username)
                        end
                    end)
                end

                if not Variables.Avatar.EnabledBlank then ensureAvatarStopped() else refreshAllAvatarImages() end
            end
        end)

        UI.Options.AvatarCopyTarget:OnChanged(function(newValue)
            if not Variables.Avatar.EnabledCopy then return end
            local uid = resolveTargetUserId(newValue)
            if uid then applyCopyProfile(uid) end
        end)

        ----------------------------------------------------------------------
        return { Name = "NameSpoofer", Stop = Stop }
    end
end
