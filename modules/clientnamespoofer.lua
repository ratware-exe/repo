-- modules/clientnamespoofer.lua
-- Exact spoofing logic & hooks preserved from original script.
-- Repo style: RbxService, GlobalEnv.Signal, Maid, Variables { Maids, RunFlag, Backup }, Start/Stop, Misc groupbox.

do
    return function(UI)
        -- === Services / Deps (match repo style like infinitezoom.lua) ======
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv  = (getgenv and getgenv()) or _G
        GlobalEnv.Signal = GlobalEnv.Signal or loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()
        local Maid       = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local Players   = RbxService.Players
        local TweenService = RbxService.TweenService
        local UserInputService = RbxService.UserInputService
        local RunService = RbxService.RunService
        local CoreGui   = RbxService.CoreGui

        local lp = Players.LocalPlayer

        -- === State ==========================================================
        GlobalEnv.NameSpoofConfig = GlobalEnv.NameSpoofConfig or {
            FakeDisplayName     = "NameSpoof",
            FakeName            = "NameSpoof",
            FakeId              = 0,
            BlankProfilePicture = true,
        }

        local Variables = {
            Maids = { NameSpoofer = Maid.new() },
            RunFlag = false,

            -- Player field backup
            Backup = nil, -- { Name, DisplayName, UserId, CharacterAppearanceId }

            -- Per-instance original snapshots (weak keys)
            Snapshots = {
                Text  = setmetatable({}, { __mode = "k" }),
                Image = setmetatable({}, { __mode = "k" }),
            },

            Config = GlobalEnv.NameSpoofConfig,
        }

        local BLANKS = {
            "rbxasset://textures/ui/GuiImagePlaceholder.png",
            "rbxassetid://0",
            "http://www.roblox.com/asset/?id=0",
        }

        -- We tag our own Obsidian inputs so spoofing skips them.
        local OUR_INPUT_ATTR = "CNS_Ignore"

        -- === Utils (original semantics) ====================================
        local function esc(s) s = tostring(s or ""); return (s:gsub("(%W)","%%%1")) end

        local function killOldStandaloneUi()
            local old = CoreGui:FindFirstChild("NameSpoofUI")
            if old then old:Destroy() end
        end

        local function ensureBackup()
            if Variables.Backup or not lp then return end
            pcall(function()
                Variables.Backup = {
                    Name        = lp.Name,
                    DisplayName = lp.DisplayName,
                    UserId      = lp.UserId,
                    CharacterAppearanceId = lp.CharacterAppearanceId or lp.UserId,
                }
            end)
        end

        local function applyPlayerFields()
            pcall(function() lp.DisplayName = Variables.Config.FakeDisplayName end)
            pcall(function() lp.CharacterAppearanceId = tonumber(Variables.Config.FakeId) or Variables.Config.FakeId end)
        end

        local function restorePlayerFields()
            if not Variables.Backup then return end
            pcall(function() lp.DisplayName = Variables.Backup.DisplayName end)
            pcall(function() lp.CharacterAppearanceId = Variables.Backup.CharacterAppearanceId end)
        end

        -- === Original replace functions (kept exactly) ======================
        local function replaceTextInObject(obj)
            if not obj or not obj.Parent then return end
            if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
                -- don't ever touch *our* Obsidian inputs
                if obj:GetAttribute(OUR_INPUT_ATTR) then return end

                -- Prevent duplicate processing (original behavior)
                if obj:GetAttribute("TextReplaced") then return end
                obj:SetAttribute("TextReplaced", true)

                -- snapshot original text (for proper restore)
                if Variables.Snapshots.Text[obj] == nil then
                    Variables.Snapshots.Text[obj] = tostring(obj.Text or "")
                end

                local text = tostring(obj.Text or "")
                if string.find(text, Variables.Backup.Name, 1, true) then
                    obj.Text = (text:gsub(esc(Variables.Backup.Name), Variables.Config.FakeName))
                elseif string.find(text, Variables.Backup.DisplayName, 1, true) then
                    obj.Text = (text:gsub(esc(Variables.Backup.DisplayName), Variables.Config.FakeDisplayName))
                elseif string.find(text, tostring(Variables.Backup.UserId), 1, true) then
                    obj.Text = (text:gsub(esc(tostring(Variables.Backup.UserId)), tostring(Variables.Config.FakeId)))
                end

                -- keep spoofing on changes (original shape, with tiny delay)
                local conn = obj:GetPropertyChangedSignal("Text"):Connect(function()
                    task.wait()
                    local newText = tostring(obj.Text or "")

                    -- If the new text contains any *original* values, update baseline snapshot
                    if string.find(newText, Variables.Backup.Name, 1, true)
                    or string.find(newText, Variables.Backup.DisplayName, 1, true)
                    or string.find(newText, tostring(Variables.Backup.UserId), 1, true) then
                        Variables.Snapshots.Text[obj] = newText
                    end

                    -- Re-apply spoof exactly the same way
                    if string.find(newText, Variables.Backup.Name, 1, true) then
                        obj.Text = (newText:gsub(esc(Variables.Backup.Name), Variables.Config.FakeName))
                    elseif string.find(newText, Variables.Backup.DisplayName, 1, true) then
                        obj.Text = (newText:gsub(esc(Variables.Backup.DisplayName), Variables.Config.FakeDisplayName))
                    elseif string.find(newText, tostring(Variables.Backup.UserId), 1, true) then
                        obj.Text = (newText:gsub(esc(tostring(Variables.Backup.UserId)), tostring(Variables.Config.FakeId)))
                    end
                end)
                Variables.Maids.NameSpoofer:GiveTask(conn)
            end
        end

        local function replaceImageInObject(obj)
            if not obj or not obj.Parent then return end
            if obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
                -- Prevent duplicate processing (original behavior)
                if obj:GetAttribute("ImageReplaced") then return end
                obj:SetAttribute("ImageReplaced", true)

                -- snapshot original image (for restore)
                if Variables.Snapshots.Image[obj] == nil then
                    Variables.Snapshots.Image[obj] = obj.Image
                end

                local image = tostring(obj.Image or "")
                if Variables.Config.BlankProfilePicture then
                    if string.find(image, tostring(Variables.Backup.UserId), 1, true) or string.find(image, Variables.Backup.Name, 1, true) then
                        obj.Image = BLANKS[1]
                    end
                end

                local conn = obj:GetPropertyChangedSignal("Image"):Connect(function()
                    task.wait()
                    local newImage = tostring(obj.Image or "")
                    if Variables.Config.BlankProfilePicture then
                        if string.find(newImage, tostring(Variables.Backup.UserId), 1, true) or string.find(newImage, Variables.Backup.Name, 1, true) then
                            obj.Image = BLANKS[1]
                        end
                    end
                end)
                Variables.Maids.NameSpoofer:GiveTask(conn)
            end
        end

        -- === Hooks (kept from original) =====================================
        local function setupGlobalHook()
            -- Clear attributes so we can reprocess everything
            for _, obj in pairs(game:GetDescendants()) do
                if obj:GetAttribute("TextReplaced") then obj:SetAttribute("TextReplaced", nil) end
                if obj:GetAttribute("ImageReplaced") then obj:SetAttribute("ImageReplaced", nil) end
                replaceTextInObject(obj)
                replaceImageInObject(obj)
            end

            local conn = game.DescendantAdded:Connect(function(obj)
                if not Variables.RunFlag then return end
                replaceTextInObject(obj)
                replaceImageInObject(obj)
            end)
            Variables.Maids.NameSpoofer:GiveTask(conn)
        end

        local function hookPlayerList()
            local function processPlayerList()
                local playerList = CoreGui:FindFirstChild("PlayerList")
                if playerList then
                    for _, obj in ipairs(playerList:GetDescendants()) do
                        if obj:GetAttribute("TextReplaced") then obj:SetAttribute("TextReplaced", nil) end
                        if obj:GetAttribute("ImageReplaced") then obj:SetAttribute("ImageReplaced", nil) end
                        replaceTextInObject(obj)
                        replaceImageInObject(obj)
                    end
                    local conn = playerList.DescendantAdded:Connect(function(obj)
                        if not Variables.RunFlag then return end
                        replaceTextInObject(obj)
                        replaceImageInObject(obj)
                    end)
                    Variables.Maids.NameSpoofer:GiveTask(conn)
                end
            end
            processPlayerList()
        end

        local function hookCoreGui()
            for _, obj in pairs(CoreGui:GetDescendants()) do
                if obj:GetAttribute("TextReplaced") then obj:SetAttribute("TextReplaced", nil) end
                if obj:GetAttribute("ImageReplaced") then obj:SetAttribute("ImageReplaced", nil) end
                replaceTextInObject(obj)
                replaceImageInObject(obj)
            end
            local conn = CoreGui.DescendantAdded:Connect(function(obj)
                if not Variables.RunFlag then return end
                replaceTextInObject(obj)
                replaceImageInObject(obj)
            end)
            Variables.Maids.NameSpoofer:GiveTask(conn)
        end

        -- === Lifecycle ======================================================
        local function Start()
            if Variables.RunFlag then
                -- re-apply with latest config
                for obj, base in pairs(Variables.Snapshots.Text) do
                    if obj and obj.Parent then
                        -- recompute from stored baseline using original rules
                        local t = base
                        if string.find(t, Variables.Backup.Name, 1, true) then
                            obj.Text = (t:gsub(esc(Variables.Backup.Name), Variables.Config.FakeName))
                        elseif string.find(t, Variables.Backup.DisplayName, 1, true) then
                            obj.Text = (t:gsub(esc(Variables.Backup.DisplayName), Variables.Config.FakeDisplayName))
                        elseif string.find(t, tostring(Variables.Backup.UserId), 1, true) then
                            obj.Text = (t:gsub(esc(tostring(Variables.Backup.UserId)), tostring(Variables.Config.FakeId)))
                        end
                    end
                end
                applyPlayerFields()
                return
            end

            Variables.RunFlag = true
            killOldStandaloneUi()
            ensureBackup()

            -- initial sweep + hooks (exact scope preserved)
            setupGlobalHook()
            hookPlayerList()
            hookCoreGui()

            applyPlayerFields()

            Variables.Maids.NameSpoofer:GiveTask(function() Variables.RunFlag = false end)
        end

        local function Stop()
            if not Variables.RunFlag then return end
            Variables.RunFlag = false

            -- disconnect all watchers
            Variables.Maids.NameSpoofer:DoCleaning()

            -- restore texts/images from snapshots and clear attributes
            for obj, base in pairs(Variables.Snapshots.Text) do
                if obj and obj.Parent then
                    pcall(function()
                        obj.Text = base
                        if obj:GetAttribute("TextReplaced") then obj:SetAttribute("TextReplaced", nil) end
                    end)
                end
                Variables.Snapshots.Text[obj] = nil
            end
            for obj, baseIm in pairs(Variables.Snapshots.Image) do
                if obj and obj.Parent then
                    pcall(function()
                        obj.Image = baseIm
                        if obj:GetAttribute("ImageReplaced") then obj:SetAttribute("ImageReplaced", nil) end
                    end)
                end
                Variables.Snapshots.Image[obj] = nil
            end

            -- restore player fields
            restorePlayerFields()
        end

        -- === UI (Misc) ======================================================
        local groupbox = UI.Tabs.Misc:AddLeftGroupbox("Client Name Spoofer", "user")

        groupbox:AddInput("CNS_DisplayName", {
            Text = "Fake Display Name",
            Default = tostring(Variables.Config.FakeDisplayName or ""),
            Finished = false,          -- live update while typing
            Placeholder = "Display name...",
        })
        groupbox:AddInput("CNS_Username", {
            Text = "Fake Username",
            Default = tostring(Variables.Config.FakeName or ""),
            Finished = false,
            Placeholder = "Username...",
        })
        groupbox:AddInput("CNS_UserId", {
            Text = "Fake UserId",
            Default = tostring(Variables.Config.FakeId or 0),
            Numeric = true,
            Finished = false,
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

        -- Mark our inputs so spoofing never touches them + avoid clear-on-focus
        pcall(function()
            if UI.Options.CNS_DisplayName.Textbox then
                UI.Options.CNS_DisplayName.Textbox:SetAttribute(OUR_INPUT_ATTR, true)
                UI.Options.CNS_DisplayName.Textbox.ClearTextOnFocus = false
            end
            if UI.Options.CNS_Username.Textbox then
                UI.Options.CNS_Username.Textbox:SetAttribute(OUR_INPUT_ATTR, true)
                UI.Options.CNS_Username.Textbox.ClearTextOnFocus = false
            end
            if UI.Options.CNS_UserId.Textbox then
                UI.Options.CNS_UserId.Textbox:SetAttribute(OUR_INPUT_ATTR, true)
                UI.Options.CNS_UserId.Textbox.ClearTextOnFocus = false
            end
        end)

        -- Inputs: live update & reapply if running
        UI.Options.CNS_DisplayName:OnChanged(function(v)
            Variables.Config.FakeDisplayName = v
            if Variables.RunFlag then Start() end
        end)
        UI.Options.CNS_Username:OnChanged(function(v)
            Variables.Config.FakeName = v
            if Variables.RunFlag then Start() end
        end))
        UI.Options.CNS_UserId:OnChanged(function(v)
            local n = tonumber(v)
            if n then Variables.Config.FakeId = n end
            if Variables.RunFlag then Start() end
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
