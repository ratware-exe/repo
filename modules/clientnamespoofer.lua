-- modules/clientnamespoofer.lua
-- ClientNameSpoofer rebuilt to match repo style:
-- - Master Toggle in Misc (no Apply/Reset buttons)
-- - Reversible via Maid + snapshots
-- - Follows factory pattern and Stop() cleanup like other modules

do
    return function(UI)
        -- ========== Imports / Shared Env ===================================
        local GlobalEnv = (getgenv and getgenv()) or _G
        local RepoBase  = GlobalEnv.RepoBase or ""

        local function Import(path)
            local src = game:HttpGet(RepoBase .. path)
            local chunk, err = loadstring(src, "@" .. path)
            if not chunk then error(err) end
            local ok, result = pcall(chunk)
            if not ok then error(result) end
            return result
        end

        local S        = Import("dependency/Services.lua")
        local Maid     = Import("dependency/Maid.lua")

        local Players  = S.Players
        local CoreGui  = S.CoreGui

        local Library, Tabs, Options, Toggles = UI.Library, UI.Tabs, UI.Options, UI.Toggles
        local lp = Players.LocalPlayer

        -- ========== Variables / State ======================================
        local Variables = {
            Maid = Maid.new(),
            Enabled = false,

            -- Weak maps so destroyed instances auto-GC
            Snapshots = {
                Text  = setmetatable({}, { __mode = "k" }),
                Image = setmetatable({}, { __mode = "k" }),
                Player = nil,
                Guard  = setmetatable({}, { __mode = "k" }), -- reentrancy guard per-instance
            },

            Config = {
                FakeDisplayName     = "NameSpoof",
                FakeName            = "NameSpoof",
                FakeId              = 0,
                BlankProfilePicture = true,
            },
        }

        -- Allow cross-module/session persistence if user wants it shared
        GlobalEnv.NameSpoofConfig = GlobalEnv.NameSpoofConfig or Variables.Config
        Variables.Config = GlobalEnv.NameSpoofConfig

        -- ========== Helpers =================================================
        local blankImageIds = {
            "rbxasset://textures/ui/GuiImagePlaceholder.png",
            "rbxassetid://0",
            "http://www.roblox.com/asset/?id=0",
        }

        local function killOldStandaloneUi()
            local old = CoreGui:FindFirstChild("NameSpoofUI")
            if old then old:Destroy() end
        end

        local function snapshotPlayer()
            Variables.Snapshots.Player = Variables.Snapshots.Player or {
                DisplayName = lp.DisplayName,
                UserId      = lp.UserId,
                -- CharacterAppearanceId is mirrored to UserId locally in most cases
                CharacterAppearanceId = pcall(function() return lp.CharacterAppearanceId end) and lp.CharacterAppearanceId or lp.UserId,
            }
        end

        local function restorePlayer()
            local P = Variables.Snapshots.Player
            if not P then return end
            pcall(function() lp.DisplayName = P.DisplayName end)
            pcall(function() lp.CharacterAppearanceId = P.CharacterAppearanceId end)
        end

        local function safeSet(obj, prop, value)
            local ok, err = pcall(function()
                Variables.Snapshots.Guard[obj] = true
                obj[prop] = value
                Variables.Snapshots.Guard[obj] = nil
            end)
            if not ok then
                -- swallow; some props may be protected
            end
        end

        local function shouldSkip(obj)
            return obj == nil or obj.Parent == nil
        end

        local function transformText(text)
            if not text or text == "" then return text end
            local cfg, snapP = Variables.Config, Variables.Snapshots.Player
            if not snapP then return text end

            -- Replace any occurrence of originals with fakes
            local out = text
            out = out:gsub(snapP.DisplayName, cfg.FakeDisplayName)
            out = out:gsub(lp.Name,        cfg.FakeName)
            out = out:gsub(tostring(snapP.UserId), tostring(cfg.FakeId))
            return out
        end

        local function transformImage(image)
            if not image or image == "" then return image end
            local snapP = Variables.Snapshots.Player
            if not snapP then return image end
            if Variables.Config.BlankProfilePicture then
                if image:find(tostring(snapP.UserId)) or image:find(lp.Name) then
                    return blankImageIds[1]
                end
            end
            return image
        end

        local function snapshotIfNeeded(obj)
            local Snap = Variables.Snapshots
            if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
                if Snap.Text[obj] == nil then
                    Snap.Text[obj] = obj.Text
                end
            elseif obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
                if Snap.Image[obj] == nil then
                    Snap.Image[obj] = obj.Image
                end
            end
        end

        local function applyToObj(obj)
            if shouldSkip(obj) then return end
            local Snap = Variables.Snapshots

            if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
                snapshotIfNeeded(obj)
                local newText = transformText(obj.Text)
                if newText ~= obj.Text then
                    safeSet(obj, "Text", newText)
                end

                -- live guard: rewrite on future changes only while enabled
                local conn
                conn = obj:GetPropertyChangedSignal("Text"):Connect(function()
                    if not Variables.Enabled then return end
                    if Snap.Guard[obj] then return end
                    local wanted = transformText(obj.Text)
                    if wanted ~= obj.Text then
                        safeSet(obj, "Text", wanted)
                    end
                end)
                Variables.Maid:GiveTask(conn)

            elseif obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
                snapshotIfNeeded(obj)
                local newImg = transformImage(obj.Image)
                if newImg ~= obj.Image then
                    safeSet(obj, "Image", newImg)
                end

                local conn
                conn = obj:GetPropertyChangedSignal("Image"):Connect(function()
                    if not Variables.Enabled then return end
                    if Snap.Guard[obj] then return end
                    local wanted = transformImage(obj.Image)
                    if wanted ~= obj.Image then
                        safeSet(obj, "Image", wanted)
                    end
                end)
                Variables.Maid:GiveTask(conn)
            end
        end

        local function scan(root)
            for _, obj in ipairs(root:GetDescendants()) do
                applyToObj(obj)
            end
        end

        local function connectAdded(root)
            local conn = root.DescendantAdded:Connect(function(obj)
                if Variables.Enabled then
                    applyToObj(obj)
                end
            end)
            Variables.Maid:GiveTask(conn)
        end

        local function reapplyActive()
            if not Variables.Enabled then return end
            scan(game)
        end

        -- ========== Lifecycle ==============================================
        local function Start()
            if Variables.Enabled then
                -- Reapply with latest config without tearing down all watchers
                reapplyActive()
                -- ensure player fields set
                pcall(function() lp.DisplayName = Variables.Config.FakeDisplayName end)
                pcall(function() lp.CharacterAppearanceId = tonumber(Variables.Config.FakeId) or Variables.Config.FakeId end)
                return
            end

            Variables.Enabled = true
            Variables.Maid:DoCleaning() -- clear any stale watchers

            killOldStandaloneUi()
            snapshotPlayer()

            -- initial pass
            scan(game)

            -- player fields
            pcall(function() lp.DisplayName = Variables.Config.FakeDisplayName end)
            pcall(function() lp.CharacterAppearanceId = tonumber(Variables.Config.FakeId) or Variables.Config.FakeId end)

            -- live hooks while enabled
            connectAdded(game)
            connectAdded(CoreGui)

            if Library and Library.Notify then
                Library:Notify("Client Name Spoofer enabled.", 3)
            end
        end

        local function Stop()
            if not Variables.Enabled then return end
            Variables.Enabled = false

            -- disconnect all watchers and timers
            Variables.Maid:DoCleaning()

            -- restore objects to original snapshots
            for obj, txt in pairs(Variables.Snapshots.Text) do
                if obj and obj.Parent then
                    safeSet(obj, "Text", txt)
                end
            end
            for obj, img in pairs(Variables.Snapshots.Image) do
                if obj and obj.Parent then
                    safeSet(obj, "Image", img)
                end
            end

            -- restore player fields
            restorePlayer()

            -- clear per-run snapshots (keep Player snapshot so a re-enable toggles back cleanly)
            Variables.Snapshots.Text  = setmetatable({}, { __mode = "k" })
            Variables.Snapshots.Image = setmetatable({}, { __mode = "k" })
            Variables.Snapshots.Guard = setmetatable({}, { __mode = "k" })

            if Library and Library.Notify then
                Library:Notify("Client Name Spoofer disabled and restored.", 3)
            end
        end

        -- ========== Obsidian UI (Misc) =====================================
        local MiscTab = (Tabs and (Tabs.Misc or Tabs["Misc"])) or (Tabs and Tabs.Settings) or UI.ActiveTab
        if not MiscTab then
            warn("[ClientNameSpoofer] No suitable tab; UI will not render.")
        else
            local Box = MiscTab:AddLeftGroupbox("Client Name Spoofer")

            Box:AddInput("CNS_DisplayName", {
                Text = "Fake Display Name",
                Default = tostring(Variables.Config.FakeDisplayName or ""),
                Finished = true,
                Placeholder = "Display name...",
            }):OnChanged(function(v)
                Variables.Config.FakeDisplayName = v
                reapplyActive()
            end)

            Box:AddInput("CNS_Username", {
                Text = "Fake Username",
                Default = tostring(Variables.Config.FakeName or ""),
                Finished = true,
                Placeholder = "Username...",
            }):OnChanged(function(v)
                Variables.Config.FakeName = v
                reapplyActive()
            end)

            Box:AddInput("CNS_UserId", {
                Text = "Fake UserId",
                Default = tostring(Variables.Config.FakeId or 0),
                Numeric = true,
                Finished = true,
                Placeholder = "123456",
            }):OnChanged(function(v)
                local n = tonumber(v)
                if n then
                    Variables.Config.FakeId = n
                    reapplyActive()
                end
            end)

            Box:AddToggle("CNS_BlankPfp", {
                Text = "Blank Profile Picture",
                Default = Variables.Config.BlankProfilePicture == true,
            }):OnChanged(function(val)
                Variables.Config.BlankProfilePicture = val and true or false
                reapplyActive()
            end)

            Box:AddDivider()

            Box:AddToggle("CNS_Enable", {
                Text = "Enable Name Spoofer",
                Default = false,
            }):OnChanged(function(val)
                if val then Start() else Stop() end
            end)
        end

        -- ========== Module API =============================================
        local Module = { Name = "ClientNameSpoofer" }
        function Module.Stop()
            Stop()
        end

        return Module
    end
end
