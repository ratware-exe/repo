-- modules/universal/attachtoback.lua
do
    return function(ui)
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local maid = Maid.new()
        local running = false
        local xoff, yoff, zoff = 0, 0, 2
        local current_align_pos, current_align_ori, current_attachment, target_name

        local function clear_constraints()
            if current_align_pos then current_align_pos:Destroy() current_align_pos = nil end
            if current_align_ori then current_align_ori:Destroy() current_align_ori = nil end
            if current_attachment then current_attachment:Destroy() current_attachment = nil end
        end

        local function get_target_parts()
            local player = services.Players.LocalPlayer
            local character = player and player.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            if not root then return nil end

            if not target_name or target_name == "" then return nil end
            local target = services.Players:FindFirstChild(target_name)
            local tchar = target and target.Character
            local troot = tchar and tchar:FindFirstChild("HumanoidRootPart")
            return root, troot
        end

        local function apply()
            clear_constraints()
            local root, troot = get_target_parts()
            if not (root and troot) then return end

            current_attachment = Instance.new("Attachment")
            current_attachment.Parent = troot

            local alignpos = Instance.new("AlignPosition")
            alignpos.Mode = Enum.PositionAlignmentMode.OneAttachment
            alignpos.Attachment0 = current_attachment
            alignpos.MaxForce = 1e9
            alignpos.Responsiveness = 200
            alignpos.Position = (troot.CFrame * CFrame.new(xoff, yoff, zoff)).Position
            alignpos.Parent = root

            local alignori = Instance.new("AlignOrientation")
            alignori.Mode = Enum.OrientationAlignmentMode.OneAttachment
            alignori.Attachment0 = current_attachment
            alignori.MaxTorque = 1e9
            alignori.Responsiveness = 200
            alignori.CFrame = troot.CFrame
            alignori.Parent = root

            current_align_pos, current_align_ori = alignpos, alignori
        end

        local function refresh_position()
            if not current_align_pos then return end
            local _, troot = get_target_parts()
            if not troot then return end
            current_align_pos.Position = (troot.CFrame * CFrame.new(xoff, yoff, zoff)).Position
            current_align_ori.CFrame   = troot.CFrame
        end

        local function start()
            if running then return end
            running = true
            apply()
            local rs = services.RunService.RenderStepped:Connect(refresh_position)
            maid:GiveTask(rs)
            maid:GiveTask(function() running = false end)
        end

        local function stop()
            if not running then return end
            running = false
            maid:DoCleaning()
            clear_constraints()
        end

        -- UI
        local tab = ui.Tabs.Main
        local group = tab:AddLeftGroupbox("Attach To Back", "paperclip")
        group:AddDropdown("AttachToBackDropdown", {
            SpecialType = "Player",
            ExcludeLocalPlayer = true,
            Text = "Select Target:",
            Tooltip = "Select attach to back target player.",
        })
        group:AddToggle("AttachToBackToggle", {
            Text = "Enable",
            Tooltip = "Turns attach to back [ON]/[OFF].",
            Default = false,
        })
        ui.Toggles.AttachToBackToggle:AddKeyPicker("AttachToBackKeybind", {
            Text = "Attach To Back",
            SyncToggleState = true,
            Mode = "Toggle", NoUI = false,
        })
        group:AddSlider("AttachToBackToggleXSlider", {
            Text = "[X] Distance", Default = 0, Min = -250, Max = 250, Rounding = 1, Compact = true,
        })
        group:AddSlider("AttachToBackToggleYSlider", {
            Text = "[Y] Distance", Default = 0, Min = -250, Max = 250, Rounding = 1, Compact = true,
        })
        group:AddSlider("AttachToBackToggleZSlider", {
            Text = "[Z] Distance", Default = 2, Min = -250, Max = 250, Rounding = 1, Compact = true,
        })

        if ui.Options.AttachToBackDropdown then
            ui.Options.AttachToBackDropdown:OnChanged(function(v)
                if typeof(v) == "Instance" and v:IsA("Player") then
                    target_name = v.Name
                elseif type(v) == "string" then
                    target_name = v
                end
                if running then apply() end
            end)
        end
        if ui.Options.AttachToBackToggleXSlider then
            ui.Options.AttachToBackToggleXSlider:OnChanged(function(n) xoff = tonumber(n) or xoff; refresh_position() end)
            xoff = tonumber(ui.Options.AttachToBackToggleXSlider.Value) or xoff
        end
        if ui.Options.AttachToBackToggleYSlider then
            ui.Options.AttachToBackToggleYSlider:OnChanged(function(n) yoff = tonumber(n) or yoff; refresh_position() end)
            yoff = tonumber(ui.Options.AttachToBackToggleYSlider.Value) or yoff
        end
        if ui.Options.AttachToBackToggleZSlider then
            ui.Options.AttachToBackToggleZSlider:OnChanged(function(n) zoff = tonumber(n) or zoff; refresh_position() end)
            zoff = tonumber(ui.Options.AttachToBackToggleZSlider.Value) or zoff
        end

        ui.Toggles.AttachToBackToggle:OnChanged(function(enabled)
            if enabled then start() else stop() end
        end)

        return { Name = "AttachToBack", Stop = stop }
    end
end
