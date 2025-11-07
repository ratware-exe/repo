-- modules/universal/attachtoback.lua
do
    return function(UI)
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local Variables = {
            Maids = { AttachToBack = Maid.new() },
            AttachToBackEnabled     = false,
            AttachToBackTargetName  = "",
            AttachToBackOffsetX     = 0,
            AttachToBackOffsetY     = 0,
            AttachToBackOffsetZ     = 2,
            AttachToBackCurrentWeld = nil,
        }

        local function ATB_DestroyWeld()
            if Variables.AttachToBackCurrentWeld then
                pcall(function() Variables.AttachToBackCurrentWeld:Destroy() end)
                Variables.AttachToBackCurrentWeld = nil
            end
        end

        -- heartbeat loop verbatim
        Variables.Maids.AttachToBack.ATB_Heartbeat =
            services.RunService.Heartbeat:Connect(function()
                if not Variables.AttachToBackEnabled then
                    ATB_DestroyWeld()
                    return
                end

                local lp = services.Players.LocalPlayer
                if not lp then ATB_DestroyWeld() return end

                if not (type(Variables.AttachToBackTargetName) == "string" and Variables.AttachToBackTargetName ~= "") then
                    ATB_DestroyWeld()
                    return
                end

                local targetPlayer = services.Players:FindFirstChild(Variables.AttachToBackTargetName)
                if not targetPlayer then ATB_DestroyWeld() return end

                if not (lp.Character
                    and targetPlayer.Character
                    and lp.Character:FindFirstChild("HumanoidRootPart")
                    and targetPlayer.Character:FindFirstChild("HumanoidRootPart")) then
                    ATB_DestroyWeld()
                    return
                end

                local offset = CFrame.new(
                    tonumber(Variables.AttachToBackOffsetX) or 0,
                    tonumber(Variables.AttachToBackOffsetY) or 0,
                    tonumber(Variables.AttachToBackOffsetZ) or 2
                )

                if not Variables.AttachToBackCurrentWeld then
                    -- initial snap (verbatim)
                    lp.Character:FindFirstChild("HumanoidRootPart").CFrame =
                        targetPlayer.Character:FindFirstChild("HumanoidRootPart").CFrame * offset

                    local newWeld = Instance.new("Weld")
                    newWeld.Name  = "HummanoidRootBody"
                    newWeld.Part0 = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
                    newWeld.Part1 = lp.Character:FindFirstChild("HumanoidRootPart")
                    newWeld.C0    = offset
                    newWeld.C1    = CFrame.new()
                    newWeld.Parent = lp.Character:FindFirstChild("HumanoidRootPart")
                    Variables.AttachToBackCurrentWeld = newWeld

                    -- cleanup on either character despawn (verbatim)
                    Variables.Maids.AttachToBack.ATB_LocalCharRemoving =
                        lp.CharacterRemoving:Connect(function()
                            ATB_DestroyWeld()
                        end)
                    Variables.Maids.AttachToBack.ATB_TargetCharRemoving =
                        targetPlayer.CharacterRemoving:Connect(function()
                            ATB_DestroyWeld()
                        end)
                else
                    -- live offset updates
                    Variables.AttachToBackCurrentWeld.C0 = offset
                end
            end)

        Variables.Maids.AttachToBack.ATB_Cleanup = ATB_DestroyWeld

        -- UI (verbatim IDs)
        do
            local tab = UI.Tabs.Main or UI.Tabs.Misc
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
                DisabledTooltip = "Feature Disabled!",
                Default = false,
                Disabled = false,
                Visible = true,
                Risky = false,
            })
            UI.Toggles.AttachToBackToggle:AddKeyPicker("AttachToBackKeybind", {
                Text = "Attach To Back",
                SyncToggleState = true,
                Mode = "Toggle",
                NoUI = false,
            })
            group:AddSlider("AttachToBackToggleXSlider", {
                Text = "[X] Distance",
                Default = 0, Min = -250, Max = 250, Rounding = 1, Compact = true,
                Tooltip = "Changes attach to back [X] axis distance.",
                DisabledTooltip = "Feature Disabled!",
                Disabled = false, Visible = true,
            })
            group:AddSlider("AttachToBackToggleYSlider", {
                Text = "[Y] Distance",
                Default = 0, Min = -250, Max = 250, Rounding = 1, Compact = true,
                Tooltip = "Changes attach to back [Y] axis distance.",
                DisabledTooltip = "Feature Disabled!",
                Disabled = false, Visible = true,
            })
            group:AddSlider("AttachToBackToggleZSlider", {
                Text = "[Z] Distance",
                Default = 0, Min = -250, Max = 250, Rounding = 1, Compact = true,
                Tooltip = "Changes attach to back [Z] axis distance.",
                DisabledTooltip = "Feature Disabled!",
                Disabled = false, Visible = true,
            })
        end

        -- OnChanged (verbatim hookups)
        do
            if UI.Toggles and UI.Toggles.AttachToBackToggle and UI.Toggles.AttachToBackToggle.OnChanged then
                Variables.Maids.AttachToBack.ATB_ToggleConn =
                    UI.Toggles.AttachToBackToggle:OnChanged(function(state)
                        Variables.AttachToBackEnabled = state and true or false
                        if not Variables.AttachToBackEnabled then
                            local cleanup = Variables.Maids.AttachToBack.ATB_Cleanup
                            if cleanup then pcall(cleanup) end
                        end
                    end)
                Variables.AttachToBackEnabled = UI.Toggles.AttachToBackToggle.Value and true or false
            end

            if UI.Options and UI.Options.AttachToBackDropdown and UI.Options.AttachToBackDropdown.OnChanged then
                Variables.Maids.AttachToBack.ATB_TargetConn =
                    UI.Options.AttachToBackDropdown:OnChanged(function(value)
                        if typeof(value) == "Instance" and value:IsA("Player") then
                            Variables.AttachToBackTargetName = value.Name
                        elseif type(value) == "string" then
                            Variables.AttachToBackTargetName = value
                        else
                            Variables.AttachToBackTargetName = ""
                        end
                        local cleanup = Variables.Maids.AttachToBack.ATB_Cleanup
                        if cleanup then pcall(cleanup) end
                    end)
                -- initialize current dropdown value
                do
                    local v = UI.Options.AttachToBackDropdown.Value
                    if typeof(v) == "Instance" and v:IsA("Player") then
                        Variables.AttachToBackTargetName = v.Name
                    elseif type(v) == "string" then
                        Variables.AttachToBackTargetName = v
                    else
                        Variables.AttachToBackTargetName = ""
                    end
                end
            end

            if UI.Options and UI.Options.AttachToBackToggleXSlider and UI.Options.AttachToBackToggleXSlider.OnChanged then
                Variables.Maids.AttachToBack.ATB_XConn =
                    UI.Options.AttachToBackToggleXSlider:OnChanged(function(n)
                        Variables.AttachToBackOffsetX = tonumber(n) or Variables.AttachToBackOffsetX
                    end)
                Variables.AttachToBackOffsetX = tonumber(UI.Options.AttachToBackToggleXSlider.Value) or Variables.AttachToBackOffsetX
            end

            if UI.Options and UI.Options.AttachToBackToggleYSlider and UI.Options.AttachToBackToggleYSlider.OnChanged then
                Variables.Maids.AttachToBack.ATB_YConn =
                    UI.Options.AttachToBackToggleYSlider:OnChanged(function(n)
                        Variables.AttachToBackOffsetY = tonumber(n) or Variables.AttachToBackOffsetY
                    end)
                Variables.AttachToBackOffsetY = tonumber(UI.Options.AttachToBackToggleYSlider.Value) or Variables.AttachToBackOffsetY
            end

            if UI.Options and UI.Options.AttachToBackToggleZSlider and UI.Options.AttachToBackToggleZSlider.OnChanged then
                Variables.Maids.AttachToBack.ATB_ZConn =
                    UI.Options.AttachToBackToggleZSlider:OnChanged(function(n)
                        Variables.AttachToBackOffsetZ = tonumber(n) or Variables.AttachToBackOffsetZ
                    end)
                Variables.AttachToBackOffsetZ = tonumber(UI.Options.AttachToBackToggleZSlider.Value) or Variables.AttachToBackOffsetZ
            end
        end

        local function Stop()
            Variables.AttachToBackEnabled = false
            Variables.Maids.AttachToBack:DoCleaning()
            ATB_DestroyWeld()
        end

        return { Name = "AttachToBack", Stop = Stop }
    end
end
