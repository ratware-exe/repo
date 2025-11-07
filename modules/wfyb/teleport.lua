-- modules/universal/teleport.lua
do
    return function(ui)
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local maid = Maid.new()
        local input_string = "0, 0, 0"
        local selected_player_name = ""
        local selected_boat_label = "" -- label from UniversalBoatDropdown values

        local function local_root()
            local player = services.Players.LocalPlayer
            local character = player and player.Character
            return character and character:FindFirstChild("HumanoidRootPart")
        end

        local function parse_xyz(text)
            local x, y, z = string.match(tostring(text), "(-?%d+%.?%d*)%s*,%s*(-?%d+%.?%d*)%s*,%s*(-?%d+%.?%d*)")
            x, y, z = tonumber(x), tonumber(y), tonumber(z)
            if x and y and z then return Vector3.new(x, y, z) end
            return nil
        end

        local function tp_to_cframe()
            local v = parse_xyz(input_string)
            local root = local_root()
            if root and v then
                root.CFrame = CFrame.new(v)
            end
        end

        local function tp_to_player()
            if not selected_player_name or selected_player_name == "" then return end
            local target = services.Players:FindFirstChild(selected_player_name)
            local tchar = target and target.Character
            local troot = tchar and tchar:FindFirstChild("HumanoidRootPart")
            local root  = local_root()
            if root and troot then
                root.CFrame = troot.CFrame + Vector3.new(0, 5, 0)
            end
        end

        local function is_boat_model(inst)
            if not (typeof(inst) == "Instance" and inst:IsA("Model")) then return false end
            if inst:FindFirstChild("BoatData") then return true end
            if string.find(string.lower(inst.Name), "boat") then return true end
            return false
        end

        local function boat_label_for_model(m)
            local data = m:FindFirstChild("BoatData")
            local owner = nil
            local name  = nil
            if data then
                local o = data:FindFirstChild("Owner")
                local n = data:FindFirstChild("UnfilteredBoatName")
                if o and o:IsA("ObjectValue") and o.Value and o.Value.Name then owner = o.Value.Name end
                if n and n:IsA("StringValue") then name = n.Value end
            end
            local pieces = {}
            if name then table.insert(pieces, tostring(name)) end
            if owner then table.insert(pieces, "(" .. tostring(owner) .. ")") end
            return #pieces > 0 and table.concat(pieces, " ") or m.Name
        end

        local function find_boat_by_label(label)
            local boats = services.Workspace:FindFirstChild("Boats")
            if not boats then return nil end
            for _, m in ipairs(boats:GetChildren()) do
                if is_boat_model(m) then
                    if boat_label_for_model(m) == label then
                        return m
                    end
                end
            end
            return nil
        end

        local function tp_to_boat()
            if not selected_boat_label or selected_boat_label == "" then return end
            local m = find_boat_by_label(selected_boat_label)
            local root = local_root()
            if not (m and root) then return end
            local pivot = nil
            pcall(function() pivot = m:GetPivot() end)
            if not pivot then
                local primary = m.PrimaryPart
                pivot = primary and primary.CFrame or nil
            end
            if pivot then
                root.CFrame = pivot + Vector3.new(0, 8, 0)
            end
        end

        -- UI
        local right = (ui.Tabs.Main or ui.Tabs.Misc):AddRightGroupbox("Teleport", "door-open")
        right:AddInput("TeleportcFrame", {
            Default = "Format: X, Y, Z",
            Numeric = false, Finished = false, ClearTextOnFocus = true,
            Text = "Input cFrame Coordinates:", Placeholder = "0, 0, 0",
            Tooltip = "Use the format [X, Y, Z]. Example: 0, 1000, 0",
        })
        local go_btn = right:AddButton({ Text = "Teleport", Func = function() end, DoubleClick = true,
            Tooltip = "Click to teleport to the inputted cFrame coordinates.", Disabled = false })

        local tbox = (ui.Tabs.Main or ui.Tabs.Misc):AddRightTabbox()
        local ptab = tbox:AddTab("Player TP")
        ptab:AddDropdown("PlayerTPDropdown", {
            SpecialType = "Player", ExcludeLocalPlayer = true, Text = "Select Player:",
            Tooltip = "Select player to tp to.",
        })
        local ptp = ptab:AddButton({ Text = "Teleport To Player", Func = function() end, DoubleClick = true })

        local btab = tbox:AddTab("Boat TP")
        btab:AddDropdown("UniversalBoatDropdown", {
            Values = {}, Text = "Search or Select Boat:", Multi = false, Searchable = true,
            Tooltip = "Click on target & close dropdown to confirm selection.", Disabled = false, Visible = true,
        })
        local btp = btab:AddButton({ Text = "Teleport To Boat", Func = function() end, DoubleClick = true })

        -- Wiring
        if ui.Options.TeleportcFrame then
            ui.Options.TeleportcFrame:OnChanged(function(value)
                input_string = tostring(value or "")
            end)
        end
        if go_btn then
            if go_btn.SetCallback then go_btn:SetCallback(tp_to_cframe) else go_btn.Func = tp_to_cframe end
        end

        if ui.Options.PlayerTPDropdown then
            ui.Options.PlayerTPDropdown:OnChanged(function(v)
                if typeof(v) == "Instance" and v:IsA("Player") then
                    selected_player_name = v.Name
                elseif type(v) == "string" then
                    selected_player_name = v
                end
            end)
        end
        if ptp then
            if ptp.SetCallback then ptp:SetCallback(tp_to_player) else ptp.Func = tp_to_player end
        end

        if ui.Options.UniversalBoatDropdown then
            ui.Options.UniversalBoatDropdown:OnChanged(function(v)
                if type(v) == "string" then selected_boat_label = v end
            end)
        end
        if btp then
            if btp.SetCallback then btp:SetCallback(tp_to_boat) else btp.Func = tp_to_boat end
        end

        return { Name = "Teleport", Stop = function() maid:DoCleaning() end }
    end
end
