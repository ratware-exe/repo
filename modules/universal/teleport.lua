-- modules/universal/teleport.lua
do
    return function(ui)
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
        local maid     = Maid.new()

        local function get_hrp()
            local p = services.Players.LocalPlayer
            local c = p and p.Character
            return c and c:FindFirstChild("HumanoidRootPart")
        end

        local function parse_xyz(text)
            if type(text) ~= "string" then return nil end
            local x,y,z = string.match(text, "(-?[%d%.]+)%s*,%s*(-?[%d%.]+)%s*,%s*(-?[%d%.]+)")
            x,y,z = tonumber(x), tonumber(y), tonumber(z)
            if not (x and y and z) then return nil end
            return Vector3.new(x,y,z)
        end

        local function find_player_by_name(name)
            if not name or name=="" then return nil end
            for _, plr in ipairs(services.Players:GetPlayers()) do
                if string.lower(plr.Name)==string.lower(name) then return plr end
            end
            return nil
        end

        local function get_boats_folder()
            return workspace:FindFirstChild("Boats")
        end

        local function find_boat_by_name(name)
            local folder = get_boats_folder()
            if not folder or not name or name=="" then return nil end
            for _, m in ipairs(folder:GetChildren()) do
                if m:IsA("Model") and string.lower(m.Name)==string.lower(name) then return m end
            end
            return nil
        end

        -- UI
        local group = ui.Tabs.Main:AddRightGroupbox("Teleport", "move-3d")

        group:AddInput("TeleportcFrame", {
            Default = "0, 0, 0",
            Numeric = false,
            Finished = false,
            Text = "CFrame (x, y, z)",
            Tooltip = "Enter coordinates like: 10, 8, -25",
        })
        group:AddButton("Teleport to CFrame", function()
            local hrp = get_hrp(); if not hrp then return end
            local v3 = parse_xyz(ui.Options.TeleportcFrame and ui.Options.TeleportcFrame.Value)
            if v3 then pcall(function() hrp.CFrame = CFrame.new(v3) end) end
        end)

        local tabbox = group:AddTabbox("TeleportBox", "map")
        local tab_player = tabbox:AddTab("Player")
        local tab_boat   = tabbox:AddTab("Boat")

        tab_player:AddDropdown("PlayerTPDropdown", {
            Values = (function()
                local values = {}
                for _, p in ipairs(services.Players:GetPlayers()) do
                    if p ~= services.Players.LocalPlayer then table.insert(values, p.Name) end
                end
                return values
            end)(),
            Default = "",
            Text = "Player",
        })
        tab_player:AddButton("Teleport to Player", function()
            local hrp = get_hrp(); if not hrp then return end
            local name = ui.Options.PlayerTPDropdown and ui.Options.PlayerTPDropdown.Value
            local target = find_player_by_name(name)
            local target_hrp = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
            if target_hrp then
                pcall(function() hrp.CFrame = target_hrp.CFrame * CFrame.new(0, 0, -2) end)
            end
        end)

        tab_boat:AddDropdown("UniversalBoatDropdown", {
            Values = (function()
                local values = {}
                local folder = get_boats_folder()
                if folder then
                    for _, m in ipairs(folder:GetChildren()) do
                        if m:IsA("Model") then table.insert(values, m.Name) end
                    end
                end
                return values
            end)(),
            Default = "",
            Text = "Boat",
        })
        tab_boat:AddButton("Teleport to Boat", function()
            local hrp = get_hrp(); if not hrp then return end
            local name = ui.Options.UniversalBoatDropdown and ui.Options.UniversalBoatDropdown.Value
            local boat = find_boat_by_name(name)
            if boat then
                local pv = boat:GetPivot()
                pcall(function() hrp.CFrame = pv * CFrame.new(0, 4, 0) end)
            end
        end)

        -- live refresh
        local function refresh_player_list()
            local values = {}
            for _, p in ipairs(services.Players:GetPlayers()) do
                if p ~= services.Players.LocalPlayer then table.insert(values, p.Name) end
            end
            local dd = ui.Options.PlayerTPDropdown
            if dd and dd.SetValues then dd:SetValues(values) end
        end
        maid:GiveTask(services.Players.PlayerAdded:Connect(refresh_player_list))
        maid:GiveTask(services.Players.PlayerRemoving:Connect(refresh_player_list))

        local function refresh_boats_list()
            local dd = ui.Options.UniversalBoatDropdown
            local folder = get_boats_folder()
            if dd and dd.SetValues then
                local values = {}
                if folder then
                    for _, m in ipairs(folder:GetChildren()) do
                        if m:IsA("Model") then table.insert(values, m.Name) end
                    end
                end
                dd:SetValues(values)
            end
        end
        local folder = get_boats_folder()
        if folder then
            maid:GiveTask(folder.ChildAdded:Connect(refresh_boats_list))
            maid:GiveTask(folder.ChildRemoved:Connect(refresh_boats_list))
        end

        local function stop()
            maid:DoCleaning()
        end

        return { Name = "Teleport", Stop = stop }
    end
end
