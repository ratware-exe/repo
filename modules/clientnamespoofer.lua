-- modules/clientnamespoofer.lua
-- Ports ClientNameSpoofer.lua into the repo's module pattern and Obsidian UI.
-- Requires: dependency/Services.lua, dependency/Maid.lua, dependency/Signal.lua
-- Tabs.Misc groupbox with Inputs + Toggle + Apply/Reset buttons.

do
    return function(UI)
        -- === Imports & shared env ===========================================
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

        local S        = Import("dependency/Services.lua")   -- services map
        local Maid     = Import("dependency/Maid.lua")
        local Players  = S.Players
        local CoreGui  = S.CoreGui

        local Library, Tabs, Options, Toggles = UI.Library, UI.Tabs, UI.Options, UI.Toggles

        -- === Config / State =================================================
        local lp = Players.LocalPlayer

        -- Namespaced config so we don't collide with other modules that also use "Config"
        GlobalEnv.NameSpoofConfig = GlobalEnv.NameSpoofConfig or {
            FakeDisplayName     = "NameSpoof",
            FakeName            = "NameSpoof",
            FakeId              = 0,
            BlankProfilePicture = true,
        }
        local Config = GlobalEnv.NameSpoofConfig

        -- Keep originals for restore across reloads
        GlobalEnv.NameSpoofOriginal = GlobalEnv.NameSpoofOriginal or {
            Name        = lp.Name,
            DisplayName = lp.DisplayName,
            UserId      = lp.UserId,
        }
        local Original = GlobalEnv.NameSpoofOriginal

        local maid = Maid.new()

        -- Small helper to register connections/instances into our Maid
        local function track(x)
            if x then maid:GiveTask(x) end
            return x
        end

        -- === Core spoofing logic (ported) ===================================
        local blankImageIds = {
            "rbxasset://textures/ui/GuiImagePlaceholder.png",
            "rbxassetid://0",
            "http://www.roblox.com/asset/?id=0",
        }

        local function replaceTextInObject(obj)
            if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
                if obj:GetAttribute("TextReplaced") then return end
                obj:SetAttribute("TextReplaced", true)

                local text = obj.Text
                if string.find(text, Original.Name) then
                    obj.Text = string.gsub(text, Original.Name, Config.FakeName)
                elseif string.find(text, Original.DisplayName) then
                    obj.Text = string.gsub(text, Original.DisplayName, Config.FakeDisplayName)
                elseif string.find(text, tostring(Original.UserId)) then
                    obj.Text = string.gsub(text, tostring(Original.UserId), tostring(Config.FakeId))
                end

                track(obj:GetPropertyChangedSignal("Text"):Connect(function()
                    task.wait()
                    local newText = obj.Text
                    if string.find(newText, Original.Name) then
                        obj.Text = string.gsub(newText, Original.Name, Config.FakeName)
                    elseif string.find(newText, Original.DisplayName) then
                        obj.Text = string.gsub(newText, Original.DisplayName, Config.FakeDisplayName)
                    elseif string.find(newText, tostring(Original.UserId)) then
                        obj.Text = string.gsub(newText, tostring(Original.UserId), tostring(Config.FakeId))
                    end
                end))
            end
        end

        local function replaceImageInObject(obj)
            if Config.BlankProfilePicture and (obj:IsA("ImageLabel") or obj:IsA("ImageButton")) then
                if obj:GetAttribute("ImageReplaced") then return end
                obj:SetAttribute("ImageReplaced", true)

                local image = obj.Image
                if string.find(image or "", tostring(Original.UserId)) or string.find(image or "", Original.Name) then
                    obj.Image = blankImageIds[1]
                end

                track(obj:GetPropertyChangedSignal("Image"):Connect(function()
                    task.wait()
                    local newImage = obj.Image
                    if string.find(newImage or "", tostring(Original.UserId)) or string.find(newImage or "", Original.Name) then
                        obj.Image = blankImageIds[1]
                    end
                end))
            end
        end

        local function scan(container)
            for _, obj in ipairs(container:GetDescendants()) do
                if obj:GetAttribute("TextReplaced") then obj:SetAttribute("TextReplaced", nil) end
                if obj:GetAttribute("ImageReplaced") then obj:SetAttribute("ImageReplaced", nil) end
                replaceTextInObject(obj)
                replaceImageInObject(obj)
            end
        end

        local function setupGlobalHook()
            scan(game)
            track(game.DescendantAdded:Connect(function(obj)
                replaceTextInObject(obj)
                replaceImageInObject(obj)
            end))
        end

        local function hookPlayerList()
            local playerList = CoreGui:FindFirstChild("PlayerList")
            if not playerList then return end
            scan(playerList)
            track(playerList.DescendantAdded:Connect(function(obj)
                replaceTextInObject(obj)
                replaceImageInObject(obj)
            end))
        end

        local function hookCoreGui()
            scan(CoreGui)
            track(CoreGui.DescendantAdded:Connect(function(obj)
                replaceTextInObject(obj)
                replaceImageInObject(obj)
            end))
        end

        local function killOldStandaloneUi()
            -- If the old standalone "NameSpoofUI" exists from the original script, remove it.
            local old = CoreGui:FindFirstChild("NameSpoofUI")
            if old then old:Destroy() end
        end

        local function applyPlayerFields()
            -- These may be protected in some environments; wrap in pcall.
            pcall(function() lp.DisplayName = Config.FakeDisplayName end)
            pcall(function() lp.CharacterAppearanceId = tonumber(Config.FakeId) or Config.FakeId end)
        end

        local function Start()
            maid:DoCleaning()                -- full cleanup before applying
            killOldStandaloneUi()
            setupGlobalHook()
            hookPlayerList()
            hookCoreGui()
            applyPlayerFields()
            if Library and Library.Notify then
                Library:Notify("Name spoof applied.", 3)
            end
        end

        local function Restore()
            -- Best-effort revert of player-facing fields and remove hooks.
            maid:DoCleaning()
            pcall(function() lp.DisplayName = Original.DisplayName end)
            pcall(function() lp.CharacterAppearanceId = Original.UserId end)
            if Library and Library.Notify then
                Library:Notify("Name spoof reset.", 3)
            end
        end

        -- === Obsidian UI (Misc tab → groupbox) ==============================
        -- Per Obsidian docs: Groupbox:AddInput(id, {Text, Default, Numeric, Finished, Placeholder, Callback, ...})
        -- and Groupbox:AddToggle(id, {Text, Default, Callback, ...}). :contentReference[oaicite:2]{index=2}
        local MiscTab = (Tabs and (Tabs.Misc or Tabs["Misc"])) or (Tabs and Tabs.Settings) or UI.ActiveTab or nil
        if not MiscTab then error("[ClientNameSpoofer] Could not find a suitable tab to attach UI.") end

        local Box = MiscTab:AddLeftGroupbox("Client Name Spoofer")

        Box:AddInput("Spoof_DisplayName", {
            Text = "Fake Display Name",
            Default = tostring(Config.FakeDisplayName or ""),
            Finished = true,
            Placeholder = "Display name...",
        })

        Box:AddInput("Spoof_Username", {
            Text = "Fake Username",
            Default = tostring(Config.FakeName or ""),
            Finished = true,
            Placeholder = "Username...",
        })

        Box:AddInput("Spoof_UserId", {
            Text = "Fake UserId",
            Default = tostring(Config.FakeId or 0),
            Numeric = true,
            Finished = true,
            Placeholder = "123456",
        })

        local ToggleBlank = Box:AddToggle("Spoof_BlankPfp", {
            Text = "Blank Profile Picture",
            Default = Config.BlankProfilePicture == true,
        })

        Box:AddDivider()

        Box:AddButton({
            Text = "Apply Spoof",
            Func = function()
                -- Pull latest values from Obsidian registries
                Config.FakeDisplayName     = (Options and Options.Spoof_DisplayName and Options.Spoof_DisplayName.Value) or Config.FakeDisplayName
                Config.FakeName            = (Options and Options.Spoof_Username and Options.Spoof_Username.Value) or Config.FakeName
                local rawId                = (Options and Options.Spoof_UserId and Options.Spoof_UserId.Value) or tostring(Config.FakeId)
                Config.FakeId              = tonumber(rawId) or Config.FakeId
                Config.BlankProfilePicture = (Toggles and Toggles.Spoof_BlankPfp and Toggles.Spoof_BlankPfp.Value) or false
                Start()
            end
        })

        Box:AddButton({
            Text = "Reset / Unload",
            Risky = true,
            DoubleClick = true,
            Func = function()
                Restore()
            end
        })

        -- Keep live in sync if user edits the inputs before pressing "Apply"
        if Options and Options.Spoof_DisplayName then
            Options.Spoof_DisplayName:OnChanged(function(v) Config.FakeDisplayName = v end)
        end
        if Options and Options.Spoof_Username then
            Options.Spoof_Username:OnChanged(function(v) Config.FakeName = v end)
        end
        if Options and Options.Spoof_UserId then
            Options.Spoof_UserId:OnChanged(function(v) Config.FakeId = tonumber(v) or Config.FakeId end)
        end
        if ToggleBlank and ToggleBlank.OnChanged then
            ToggleBlank:OnChanged(function(v) Config.BlankProfilePicture = v end)
        end

        -- === Module API =====================================================
        local Module = { Name = "ClientNameSpoofer" }
        function Module.Stop()
            Restore()
        end

        -- Optional: auto-apply once on mount (comment out if you prefer manual apply)
        -- Start()

        return Module
    end
end
