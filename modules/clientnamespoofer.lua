-- modules/clientnamespoofer.lua
-- Style-aligned with other modules (see infinitezoom.lua):
-- - Variables = { Maids = { NameSpoofer = Maid.new() }, RunFlag, Backup }
-- - Start/Stop lifecycle with Maid cleanup
-- - Master toggle in Misc
-- - Inputs update live while enabled (no clearing), and are respected on next enable

do
    return function(UI)
        -- === Services / Deps (match style) =================================
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv  = (getgenv and getgenv()) or _G
        GlobalEnv.Signal = GlobalEnv.Signal or loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()
        local Maid       = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local Players   = RbxService.Players
        local CoreGui   = RbxService.CoreGui
        local lp        = Players.LocalPlayer

        -- === State ==========================================================
        local Variables = {
            Maids = { NameSpoofer = Maid.new() },
            RunFlag = false,
            Backup = nil, -- { DisplayName, UserId, CharacterAppearanceId }
            ImagesBackup = setmetatable({}, { __mode = "k" }), -- original Image per object
            Config = GlobalEnv.NameSpoofConfig or {
                FakeDisplayName     = "NameSpoof",
                FakeName            = "NameSpoof",
                FakeId              = 0,
                BlankProfilePicture = true,
            },
        }
        GlobalEnv.NameSpoofConfig = Variables.Config -- persist across modules/reloads

        -- === Utils ==========================================================
        local function esc(s) -- escape Lua pattern characters
            s = tostring(s or "")
            return (s:gsub("(%W)","%%%1"))
        end

        local BLANKS = {
            "rbxasset://textures/ui/GuiImagePlaceholder.png",
            "rbxassetid://0",
            "http://www.roblox.com/asset/?id=0",
        }

        local function isUnderCoreGui(inst)
            return inst and inst.Parent and inst:IsDescendantOf(CoreGui)
        end

        local function untransformText(text)
            -- Revert fakes -> originals using placeholders to avoid overlap
            if not Variables.Backup then return text end
            local P, C = Variables.Backup, Variables.Config
            local t = tostring(text or "")

            -- Mark fakes
            if C.FakeDisplayName and C.FakeDisplayName ~= "" then
                t = t:gsub(esc(C.FakeDisplayName), "\0DN\0")
            end
            if C.FakeName and C.FakeName ~= "" then
                t = t:gsub(esc(C.FakeName), "\0UN\0")
            end
            if C.FakeId and tostring(C.FakeId) ~= "" then
                t = t:gsub(esc(tostring(C.FakeId)), "\0ID\0")
            end

            -- Replace placeholders with originals
            t = t:gsub("\0DN\0", tostring(P.DisplayName or ""))
            t = t:gsub("\0UN\0", tostring(lp and lp.Name or ""))
            t = t:gsub("\0ID\0", tostring(P.UserId or ""))

            return t
        end

        local function transformText(text)
            -- Apply originals -> fakes using placeholders to avoid cross-writes
            if not Variables.Backup then return text end
            local P, C = Variables.Backup, Variables.Config
            local t = tostring(text or "")

            -- Mark originals
            if P.DisplayName and P.DisplayName ~= "" then
                t = t:gsub(esc(P.DisplayName), "\0DN\0")
            end
            if lp and lp.Name and lp.Name ~= "" then
                t = t:gsub(esc(lp.Name), "\0UN\0")
            end
            if P.UserId then
                t = t:gsub(esc(tostring(P.UserId)), "\0ID\0")
            end

            -- Placeholders -> fakes
            t = t:gsub("\0DN\0", tostring(C.FakeDisplayName or ""))
            t = t:gsub("\0UN\0", tostring(C.FakeName or ""))
            t = t:gsub("\0ID\0", tostring(C.FakeId or ""))

            return t
        end

        local function applyText(obj)
            -- Only affect labels/buttons (never TextBox to avoid input clearing)
            if not obj or not obj.Parent then return end
            local cls = obj.ClassName
            if cls ~= "TextLabel" and cls ~= "TextButton" then return end
            if isUnderCoreGui(obj) then
                -- Skip CoreGui entirely to avoid touching Obsidian UI & Roblox topbar
                return
            end
            -- Always compute from an unspoofed baseline, then apply
            local base = untransformText(obj.Text)
            local spoofed = transformText(base)
            if spoofed ~= obj.Text then
                local guard = true
                local ok = pcall(function() obj.Text = spoofed end)
                guard = false
                return ok
            end
        end

        local function applyImage(obj)
            if not obj or not obj.Parent then return end
            local cls = obj.ClassName
            if cls ~= "ImageLabel" and cls ~= "ImageButton" then return end

            -- Save original once
            if not Variables.ImagesBackup[obj] then
                Variables.ImagesBackup[obj] = obj.Image
            end

            if Variables.Config.BlankProfilePicture and Variables.Backup then
                local P = Variables.Backup
                local im = tostring(obj.Image or "")
                if im:find(tostring(P.UserId or ""), 1, true) or (lp and im:find(lp.Name or "", 1, true)) then
                    if obj.Image ~= BLANKS[1] then
                        pcall(function() obj.Image = BLANKS[1] end)
                    end
                end
            end
        end

        local function scan(root)
            for _, obj in ipairs(root:GetDescendants()) do
                applyText(obj)
                applyImage(obj)
            end
        end

        -- === Lifecycle ======================================================
        local function Start()
            if Variables.RunFlag then
                -- Live reapply with current inputs
                scan(game)
                pcall(function()
                    if lp then
                        lp.DisplayName = Variables.Config.FakeDisplayName
                        lp.CharacterAppearanceId = tonumber(Variables.Config.FakeId) or Variables.Config.FakeId
                    end
                end)
                return
            end

            Variables.RunFlag = true

            -- Backup player fields once
            if not Variables.Backup and lp then
                pcall(function()
                    Variables.Backup = {
                        DisplayName = lp.DisplayName,
                        UserId = lp.UserId,
                        CharacterAppearanceId = lp.CharacterAppearanceId or lp.UserId
                    }
                end)
            end

            -- Initial apply
            scan(game)
            pcall(function()
                if lp then
                    lp.DisplayName = Variables.Config.FakeDisplayName
                    lp.CharacterAppearanceId = tonumber(Variables.Config.FakeId) or Variables.Config.FakeId
                end
            end)

            -- Live wiring
            local d1 = game.DescendantAdded:Connect(function(obj)
                if not Variables.RunFlag then return end
                applyText(obj)
                applyImage(obj)
                -- Property guards while enabled
                if obj:IsA("TextLabel") or obj:IsA("TextButton") then
                    Variables.Maids.NameSpoofer:GiveTask(obj:GetPropertyChangedSignal("Text"):Connect(function()
                        if not Variables.RunFlag then return end
                        applyText(obj)
                    end))
                elseif obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
                    Variables.Maids.NameSpoofer:GiveTask(obj:GetPropertyChangedSignal("Image"):Connect(function()
                        if not Variables.RunFlag then return end
                        applyImage(obj)
                    end))
                end
            end)
            Variables.Maids.NameSpoofer:GiveTask(d1)
            Variables.Maids.NameSpoofer:GiveTask(function() Variables.RunFlag = false end)
        end

        local function Stop()
            if not Variables.RunFlag then return end
            Variables.RunFlag = false

            -- Stop watchers
            Variables.Maids.NameSpoofer:DoCleaning()

            -- Unspoof all texts (labels/buttons only)
            for _, obj in ipairs(game:GetDescendants()) do
                if obj and obj.Parent then
                    local cls = obj.ClassName
                    if (cls == "TextLabel" or cls == "TextButton") and not isUnderCoreGui(obj) then
                        local base = untransformText(obj.Text)
                        if base ~= obj.Text then
                            pcall(function() obj.Text = base end)
                        end
                    end
                end
            end

            -- Restore images we touched
            for obj, original in pairs(Variables.ImagesBackup) do
                if obj and obj.Parent then
                    pcall(function() obj.Image = original end)
                end
                Variables.ImagesBackup[obj] = nil
            end

            -- Restore player fields
            if Variables.Backup and lp then
                pcall(function()
                    lp.DisplayName = Variables.Backup.DisplayName
                    lp.CharacterAppearanceId = Variables.Backup.CharacterAppearanceId
                end)
            end
        end

        -- === UI (Misc) ======================================================
        local groupbox = UI.Tabs.Misc:AddLeftGroupbox("Client Name Spoofer", "user")
        groupbox:AddInput("CNS_DisplayName", {
            Text = "Fake Display Name",
            Default = tostring(Variables.Config.FakeDisplayName or ""),
            Finished = true,
            Placeholder = "Display name...",
        })
        groupbox:AddInput("CNS_Username", {
            Text = "Fake Username",
            Default = tostring(Variables.Config.FakeName or ""),
            Finished = true,
            Placeholder = "Username...",
        })
        groupbox:AddInput("CNS_UserId", {
            Text = "Fake UserId",
            Default = tostring(Variables.Config.FakeId or 0),
            Numeric = true,
            Finished = true,
            Placeholder = "123456",
        })
        groupbox:AddToggle("CNS_BlankPfp", {
            Text = "Blank Profile Picture",
            Default = Variables.Config.BlankProfilePicture == true,
        })
        groupbox:AddToggle("CNS_Enable", {
            Text = "Enable Name Spoofer",
            Default = false,
        })

        -- Wire inputs (auto-update while enabled; never touch TextBox contents)
        UI.Options.CNS_DisplayName:OnChanged(function(v)
            Variables.Config.FakeDisplayName = v
            if Variables.RunFlag then Start() end
        end)
        UI.Options.CNS_Username:OnChanged(function(v)
            Variables.Config.FakeName = v
            if Variables.RunFlag then Start() end
        end)
        UI.Options.CNS_UserId:OnChanged(function(v)
            local n = tonumber(v)
            if n then
                Variables.Config.FakeId = n
                if Variables.RunFlag then Start() end
            end
        end)
        UI.Toggles.CNS_BlankPfp:OnChanged(function(val)
            Variables.Config.BlankProfilePicture = val and true or false
            if Variables.RunFlag then Start() end
        end)
        UI.Toggles.CNS_Enable:OnChanged(function(enabledState)
            if enabledState then Start() else Stop() end
        end)

        -- === Module API =====================================================
        return { Name = "ClientNameSpoofer", Stop = Stop }
    end
end
