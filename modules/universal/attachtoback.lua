-- modules/universal/attachtoback.lua
do
    return function(ui)
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
        local maid     = Maid.new()

        local state = {
            enabled = false,
            target_name = "",
            offset = Vector3.new(0, 0, 2),
            weld = nil,
        }

        local function get_player_by_name(name)
            if not name or name == "" then return nil end
            for _, p in ipairs(services.Players:GetPlayers()) do
                if string.lower(p.Name) == string.lower(name) then return p end
            end
            return nil
        end

        local function attach()
            if state.weld then return end
            local local_player = services.Players.LocalPlayer
            local character = local_player and local_player.Character
            local target_player = get_player_by_name(state.target_name)
            local target_char = target_player and target_player.Character
            if not (character and target_char) then return end

            local my_hrp = character:FindFirstChild("HumanoidRootPart")
            local their_hrp = target_char:FindFirstChild("HumanoidRootPart")
            if not (my_hrp and their_hrp) then return end

            -- create an attachment-based constraint for smoothness
            local a0 = Instance.new("Attachment"); a0.Name = "ATB_YourAttachment"; a0.Parent = my_hrp
            local a1 = Instance.new("Attachment"); a1.Name = "ATB_TargetAttachment"; a1.Parent = their_hrp
            a0.Position = Vector3.zero
            a1.Position = Vector3.new(0, 0, 0)

            local align_pos = Instance.new("AlignPosition")
            align_pos.MaxForce = 1e6
            align_pos.Responsiveness = 200
            align_pos.Attachment0 = a0
            align_pos.Attachment1 = a1
            align_pos.Parent = my_hrp

            local align_ori = Instance.new("AlignOrientation")
            align_ori.MaxAngularVelocity = math.huge
            align_ori.Responsiveness = 200
            align_ori.Attachment0 = a0
            align_ori.Attachment1 = a1
            align_ori.Parent = my_hrp

            state.weld = { a0 = a0, a1 = a1, pos = align_pos, ori = align_ori, their_hrp = their_hrp }

            local rs = services.RunService.RenderStepped:Connect(function()
                if not state.enabled or not state.weld then return end
                if state.weld.their_hrp then
                    -- keep behind target by offset in target HRP-object space
                    local desired = state.weld.their_hrp.CFrame * CFrame.new(state.offset.X, state.offset.Y, state.offset.Z)
                    state.weld.pos.Position = desired.Position
                    state.weld.ori.CFrame = CFrame.lookAt(desired.Position, state.weld.their_hrp.Position)
                end
            end)
            maid:GiveTask(rs)
        end

        local function detach()
            if not state.weld then return end
            pcall(function()
                if state.weld.pos then state.weld.pos:Destroy() end
                if state.weld.ori then state.weld.ori:Destroy() end
                if state.weld.a0 then state.weld.a0:Destroy() end
                if state.weld.a1 then state.weld.a1:Destroy() end
            end)
            state.weld = nil
        end

        local function start()
            if state.enabled then return end
            state.enabled = true
            attach()
            maid:GiveTask(function() state.enabled = false; detach() end)
        end

        local function stop()
            if not state.enabled then return end
            state.enabled = false
            maid:DoCleaning()
            detach()
        end

        -- UI: Attach To Back group (dropdown + toggle/keybind + XYZ sliders) from prompt.lua.
        local group = ui.Tabs.Main:AddRightGroupbox("Attach To Back", "person-standing")
        group:AddDropdown("AttachToBackDropdown", {
            Values = (function()
                local values = {}
                for _, p in ipairs(services.Players:GetPlayers()) do
                    if p ~= services.Players.LocalPlayer then table.insert(values, p.Name) end
                end
                return values
            end)(),
            Default = "",
            Text = "Target Player",
            Tooltip = "Select a player to attach behind.",
        })

        group:AddToggle("AttachToBackToggle", {
            Text = "Attach To Back",
            Tooltip = "Attach behind the selected player.",
            Default = false,
        }):AddKeyPicker("AttachToBackKeybind", { Text="Attach To Back Toggle", Default = "G", Mode="Toggle", NoUI=true })

        group:AddSlider("AttachToBackXSlider", { Text="Offset X", Default=0, Min=-10, Max=10, Rounding=2 })
        group:AddSlider("AttachToBackYSlider", { Text="Offset Y", Default=0, Min=-10, Max=10, Rounding=2 })
        group:AddSlider("AttachToBackZSlider", { Text="Offset Z", Default=2, Min=-10, Max=10, Rounding=2 })

        -- Wiring
        if ui.Options.AttachToBackDropdown and ui.Options.AttachToBackDropdown.OnChanged then
            ui.Options.AttachToBackDropdown:OnChanged(function(value)
                if type(value) == "string" then
                    state.target_name = value
                    if state.enabled then
                        maid:DoCleaning()
                        detach()
                        start()
                    end
                end
            end)
        end

        local function apply_offset()
            local x = tonumber(ui.Options.AttachToBackXSlider and ui.Options.AttachToBackXSlider.Value) or state.offset.X
            local y = tonumber(ui.Options.AttachToBackYSlider and ui.Options.AttachToBackYSlider.Value) or state.offset.Y
            local z = tonumber(ui.Options.AttachToBackZSlider and ui.Options.AttachToBackZSlider.Value) or state.offset.Z
            state.offset = Vector3.new(x,y,z)
        end
        for _, id in ipairs({ "AttachToBackXSlider", "AttachToBackYSlider", "AttachToBackZSlider" }) do
            local opt = ui.Options[id]
            if opt and opt.OnChanged then
                opt:OnChanged(function() apply_offset() end)
            end
        end
        apply_offset()

        ui.Toggles.AttachToBackToggle:OnChanged(function(v)
            if v then start() else stop() end
        end)

        -- live update player list
        local function refresh_players()
            local values = {}
            for _, p in ipairs(services.Players:GetPlayers()) do
                if p ~= services.Players.LocalPlayer then table.insert(values, p.Name) end
            end
            local dd = ui.Options.AttachToBackDropdown
            if dd and dd.SetValues then dd:SetValues(values) end
        end
        maid:GiveTask(services.Players.PlayerAdded:Connect(refresh_players))
        maid:GiveTask(services.Players.PlayerRemoving:Connect(refresh_players))

        return { Name = "AttachToBack", Stop = stop }
    end
end
