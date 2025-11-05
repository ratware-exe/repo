-- modules/clientnamespoofer.lua
do
    return function(UI)
        -- === Services / Deps (match repo style like infinitezoom.lua) ======
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv  = (getgenv and getgenv()) or _G
        GlobalEnv.Signal = GlobalEnv.Signal or loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()
        local Maid       = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local Players     = RbxService.Players
        local CoreGui     = RbxService.CoreGui
        local LocalPlayer = Players.LocalPlayer

        -- === Config (global) ===============================================
        GlobalEnv.NameSpoofConfig = GlobalEnv.NameSpoofConfig or {
            FakeDisplayName      = "NameSpoof",
            FakeName             = "NameSpoof",
            FakeId               = 0,
            BlankProfilePicture  = true,
        }

        -- === Backup (once) ==================================================
        local function ensureBackup()
            if GlobalEnv.NameSpoofBackup or not LocalPlayer then return end
            pcall(function()
                GlobalEnv.NameSpoofBackup = {
                    Name                   = LocalPlayer.Name,
                    DisplayName            = LocalPlayer.DisplayName,
                    UserId                 = LocalPlayer.UserId,
                    CharacterAppearanceId  = LocalPlayer.CharacterAppearanceId or LocalPlayer.UserId,
                }
            end)
        end
        ensureBackup()

        -- === State ==========================================================
        local Variables = {
            Maids     = { NameSpoofer = Maid.new() },
            RunFlag   = false,

            Backup    = GlobalEnv.NameSpoofBackup, -- { Name, DisplayName, UserId, CharacterAppearanceId }
            Config    = GlobalEnv.NameSpoofConfig,

            -- Keep track of the *last applied* fakes so we can normalize
            LastFakes = {
                DisplayName = GlobalEnv.NameSpoofConfig.FakeDisplayName,
                Name        = GlobalEnv.NameSpoofConfig.FakeName,
                Id          = GlobalEnv.NameSpoofConfig.FakeId,
            },

            -- Only snapshot images (we truly need their exact original)
            ImageSnapshot = setmetatable({}, { __mode = "k" }),
        }

        local BLANKS = {
            "rbxasset://textures/ui/GuiImagePlaceholder.png",
            "rbxassetid://0",
            "http://www.roblox.com/asset/?id=0",
        }

        -- Tag our own inputs so spoofing skips them
        local OUR_INPUT_ATTR = "CNS_Ignore"

        -- === Utils ==========================================================
        local function esc(s) s = tostring(s or ""); return (s:gsub("(%W)","%%%1")) end

        local function killOldStandaloneUi()
            local old = CoreGui:FindFirstChild("NameSpoofUI")
            if old then old:Destroy() end
        end

        local function applyPlayerFields()
            pcall(function() LocalPlayer.DisplayName = Variables.Config.FakeDisplayName end)
            pcall(function() LocalPlayer.CharacterAppearanceId = tonumber(Variables.Config.FakeId) or Variables.Config.FakeId end)
        end

        local function restorePlayerFields()
            local B = Variables.Backup
            if not B then return end
            pcall(function() LocalPlayer.DisplayName = B.DisplayName end)
            pcall(function() LocalPlayer.CharacterAppearanceId = B.CharacterAppearanceId end)
        end

        -- Convert any *fake* values back to originals (normalize)
        local function normalizeText(s)
            local B = Variables.Backup
            if not B then return s end
            local t = tostring(s or "")

            -- Use both LAST and CURRENT fakes for robust normalization.
            local F_now  = Variables.Config
            local F_last = Variables.LastFakes or {}

            -- DisplayName
            local fdn_now  = F_now.FakeDisplayName
            local fdn_last = F_last.DisplayName
            if fdn_now and fdn_now ~= "" then t = t:gsub(esc(fdn_now),  B.DisplayName or "") end
            if fdn_last and fdn_last ~= "" and fdn_last ~= fdn_now then
                t = t:gsub(esc(fdn_last), B.DisplayName or "")
            end

            -- Username
            local fn_now  = F_now.FakeName
            local fn_last = F_last.Name
            if fn_now and fn_now ~= "" then t = t:gsub(esc(fn_now),  B.Name or "") end
            if fn_last and fn_last ~= "" and fn_last ~= fn_now then
                t = t:gsub(esc(fn_last), B.Name or "")
            end

            -- UserId (coerce to string)
            local fid_now  = tostring(F_now.FakeId or "")
            local fid_last = tostring(F_last.Id or "")
            if fid_now  ~= "" then t = t:gsub(esc(fid_now),  tostring(B.UserId or "")) end
            if fid_last ~= "" and fid_last ~= fid_now then
                t = t:gsub(esc(fid_last), tostring(B.UserId or ""))
            end

            return t
        end

        -- Apply current config (originals -> fakes), using placeholders to avoid overlap
        local function applyFakesFromOriginal(s)
            local B = Variables.Backup
            if not B then return s end
            local C = Variables.Config
            local t = tostring(s or "")

            -- mark originals
            t = B.DisplayName and t:gsub(esc(B.DisplayName), "\1DN\1") or t
            t = B.Name        and t:gsub(esc(B.Name),        "\1UN\1") or t
            t = B.UserId      and t:gsub(esc(tostring(B.UserId)), "\1ID\1") or t

            -- fill with current fakes (empty FakeDisplayName ⇒ replaces with "")
            t = t:gsub("\1DN\1", tostring(C.FakeDisplayName or ""))
            t = t:gsub("\1UN\1", tostring(C.FakeName        or ""))
            t = t:gsub("\1ID\1", tostring(C.FakeId          or ""))

            return t
        end

        -- One-step idempotent rewrite for any text: normalize → apply
        local function rewriteText(s)
            return applyFakesFromOriginal(normalizeText(s))
        end

        -- === Spoofers =======================================================
        local function spoofTextObject(obj)
            if not obj or not obj.Parent or not Variables.Backup then return end
            if obj:GetAttribute(OUR_INPUT_ATTR) then return end
            if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
                local newVal = rewriteText(obj.Text)
                if newVal ~= obj.Text then
                    pcall(function() obj.Text = newVal end)
                end

                -- Keep it rewritten while enabled
                local cn = obj:GetPropertyChangedSignal("Text"):Connect(function()
                    if not Variables.RunFlag then return end
                    local want = rewriteText(obj.Text)
                    if want ~= obj.Text then
                        pcall(function() obj.Text = want end)
                    end
                end)
                Variables.Maids.NameSpoofer:GiveTask(cn)
            end
        end

        local function spoofImageObject(obj)
            if not obj or not obj.Parent or not Variables.Backup then return end
            if obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
                if Variables.ImageSnapshot[obj] == nil then
                    Variables.ImageSnapshot[obj] = obj.Image
                end
                if Variables.Config.BlankProfilePicture then
                    local B = Variables.Backup
                    local im = tostring(obj.Image or "")
                    if im:find(tostring(B.UserId or ""), 1, true) or im:find(B.Name or "", 1, true) then
                        if obj.Image ~= BLANKS[1] then
                            pcall(function() obj.Image = BLANKS[1] end)
                        end
                    end
                end
                local cn = obj:GetPropertyChangedSignal("Image"):Connect(function()
                    if not Variables.RunFlag then return end
                    if not Variables.Config.BlankProfilePicture then return end
                    local B = Variables.Backup
                    local newIm = tostring(obj.Image or "")
                    if newIm:find(tostring(B.UserId or ""), 1, true) or newIm:find(B.Name or "", 1, true) then
                        if obj.Image ~= BLANKS[1] then
                            pcall(function() obj.Image = BLANKS[1] end)
                        end
                    end
                end)
                Variables.Maids.NameSpoofer:GiveTask(cn)
            end
        end

        -- Sweep helpers
        local function sweepExistingTree(root)
            for _, obj in ipairs(root:GetDescendants()) do
                spoofTextObject(obj)
                spoofImageObject(obj)
            end
        end

        -- === Hooks (scope preserved) =======================================
        local function setupGlobalHook()
            sweepExistingTree(game)
            local cn = game.DescendantAdded:Connect(function(obj)
                if not Variables.RunFlag then return end
                spoofTextObject(obj)
                spoofImageObject(obj)
            end)
            Variables.Maids.NameSpoofer:GiveTask(cn)
        end

        local function hookPlayerList()
            local playerList = CoreGui:FindFirstChild("PlayerList")
            if not playerList then return end
            sweepExistingTree(playerList)
            local cn = playerList.DescendantAdded:Connect(function(obj)
                if not Variables.RunFlag then return end
                spoofTextObject(obj)
                spoofImageObject(obj)
            end)
            Variables.Maids.NameSpoofer:GiveTask(cn)
        end

        local function hookCoreGui()
            sweepExistingTree(CoreGui)
            local cn = CoreGui.DescendantAdded:Connect(function(obj)
                if not Variables.RunFlag then return end
                spoofTextObject(obj)
                spoofImageObject(obj)
            end)
            Variables.Maids.NameSpoofer:GiveTask(cn)
        end

        -- Re-apply everything with the *current* config
        local function reapplyAll()
            sweepExistingTree(game)
            applyPlayerFields()
            -- track what we just applied so normalize() can undo it later
            Variables.LastFakes = {
                DisplayName = Variables.Config.FakeDisplayName,
                Name        = Variables.Config.FakeName,
                Id          = Variables.Config.FakeId,
            }
        end

        -- === Lifecycle ======================================================
        local function Start()
            if Variables.RunFlag then
                reapplyAll()
                return
            end
            Variables.RunFlag = true

            killOldStandaloneUi()
            setupGlobalHook()
            hookPlayerList()
            hookCoreGui()
            reapplyAll()

            Variables.Maids.NameSpoofer:GiveTask(function() Variables.RunFlag = false end)
        end

        local function Stop()
            if not Variables.RunFlag then return end
            Variables.RunFlag = false

            -- stop watchers
            Variables.Maids.NameSpoofer:DoCleaning()

            -- Normalize all texts back to originals and clear our attrs
            for _, obj in ipairs(game:GetDescendants()) do
                if obj and obj.Parent and (obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox")) then
                    if not obj:GetAttribute(OUR_INPUT_ATTR) then
                        local orig = normalizeText(obj.Text)
                        if orig ~= obj.Text then
                            pcall(function() obj.Text = orig end)
                        end
                    end
                    if obj:GetAttribute("TextReplaced") then obj:SetAttribute("TextReplaced", nil) end
                elseif obj and obj.Parent and (obj:IsA("ImageLabel") or obj:IsA("ImageButton")) then
                    local snap = Variables.ImageSnapshot[obj]
                    if snap ~= nil then
                        pcall(function() obj.Image = snap end)
                        Variables.ImageSnapshot[obj] = nil
                    end
                    if obj:GetAttribute("ImageReplaced") then obj:SetAttribute("ImageReplaced", nil) end
                end
            end

            restorePlayerFields()
        end

        -- === UI (Misc) ======================================================
        local groupbox = UI.Tabs.Misc:AddLeftGroupbox("Client Name Spoofer", "user")

        groupbox:AddInput("CNS_DisplayName", {
            Text = "Fake Display Name",
            Default = tostring(Variables.Config.FakeDisplayName or ""),
            Finished = false, -- live update while typing
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

        -- Mark inputs so spoofing never touches them + prevent clear-on-focus
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

        -- Inputs → live config (reapply if running)
        UI.Options.CNS_DisplayName:OnChanged(function(v)
            Variables.Config.FakeDisplayName = v or ""
            if Variables.RunFlag then reapplyAll() end
        end)
        UI.Options.CNS_Username:OnChanged(function(v)
            Variables.Config.FakeName = v or ""
            if Variables.RunFlag then reapplyAll() end
        end)
        UI.Options.CNS_UserId:OnChanged(function(v)
            v = v or ""
            local n = tonumber(v)
            if n then
                Variables.Config.FakeId = n
            elseif v == "" then
                Variables.Config.FakeId = 0
            end
            if Variables.RunFlag then reapplyAll() end
        end)
        UI.Toggles.CNS_BlankPfp:OnChanged(function(val)
            Variables.Config.BlankProfilePicture = val and true or false
            if Variables.RunFlag then reapplyAll() end
        end)
        UI.Toggles.CNS_Enable:OnChanged(function(enabledState)
            if enabledState then Start() else Stop() end
        end)

        -- === Module API =====================================================
        return { Name = "ClientNameSpoofer", Stop = Stop }
    end
end
