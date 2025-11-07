-- modules/wfyb/teleport.lua
do
    return function(UI)
        local services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
        local maid     = Maid.new()

        local Variables = {
            TeleportCFrameInputString = "0, 0, 0",
            BoatTPSelectedDisplay = "",
            BoatTPSelectedModelName = "",
            UniversalBoatList = {},  -- values filled live
        }

        -- Utilities used verbatim by boat tp section
        local function GetBoatsFolder()
            return services.Workspace:FindFirstChild("Boats")
        end
        local function GetAnyBasePartFromModel(model)
            local pp = model.PrimaryPart
            if pp and pp:IsA("BasePart") then return pp end
            local ok, parts = pcall(function() return model:GetDescendants() end)
            if ok and parts then
                for _, d in ipairs(parts) do
                    if d:IsA("BasePart") then return d end
                end
            end
            return nil
        end
        local function ResolveOwnerDisplayName(ownerValueObject)
            if not ownerValueObject then return nil end
            local v = ownerValueObject.Value
            if typeof(v) == "Instance" and v:IsA("Player") then
                return v.DisplayName or v.Name
            end
            return nil
        end
        local function ParseDropdownDisplay(displayString)
            -- Supports: "owner • BoatName • ModelName"  OR "ModelName"
            displayString = tostring(displayString or "")
            local owner, boat, model = string.match(displayString, "^([^•]+)%s*•%s*([^•]+)%s*•%s*(.+)$")
            if owner and boat and model then
                owner = string.gsub(owner, "^%s*(.-)%s*$", "%1")
                boat  = string.gsub(boat,  "^%s*(.-)%s*$", "%1")
                model = string.gsub(model, "^%s*(.-)%s*$", "%1")
                return owner, boat, model
            else
                model = string.gsub(displayString, "^%s*(.-)%s*$", "%1")
                return nil, nil, model
            end
        end
        local function FindTargetBoatModel(boatsFolder, targetOwnerName, targetBoatName, targetModelName)
            if not boatsFolder then return nil end
            local lp = services.Players.LocalPlayer
            local ch = lp and lp.Character
            local hrp = ch and ch:FindFirstChild("HumanoidRootPart")

            local closestModel, closestDistance = nil, nil
            for _, model in ipairs(boatsFolder:GetDescendants()) do
                if model:IsA("Model") then
                    local boatData = model:FindFirstChild("BoatData") or model:FindFirstChild("BoatData", true)
                    if boatData then
                        local ownerVO = boatData:FindFirstChild("Owner")
                        local nameVO  = boatData:FindFirstChild("UnfilteredBoatName")
                        local ownerMatches = true
                        local nameMatches = true

                        if targetOwnerName and targetOwnerName ~= "" then
                            ownerMatches = (ResolveOwnerDisplayName(ownerVO) == targetOwnerName)
                        end
                        if targetBoatName and targetBoatName ~= "" then
                            nameMatches = (nameVO and tostring(nameVO.Value) == targetBoatName)
                        end

                        local modelMatches = (not targetModelName or targetModelName == "" or model.Name == targetModelName)

                        if ownerMatches and nameMatches and modelMatches then
                            if not hrp then
                                return model
                            end
                            local pivotOk, pivot = pcall(model.GetPivot, model)
                            local pos = pivotOk and pivot and pivot.Position or (GetAnyBasePartFromModel(model) and GetAnyBasePartFromModel(model).Position)
                            if pos then
                                local dist = (pos - hrp.Position).Magnitude
                                if not closestDistance or dist < closestDistance then
                                    closestModel = model
                                    closestDistance = dist
                                end
                            end
                        end
                    end
                end
            end
            return closestModel
        end

        -- CFrame TP (verbatim)
        local function Teleport_ApplyFromInputString()
            local txt = tostring(Variables.TeleportCFrameInputString or "")
            local xs, ys, zs = string.match(txt, "^%s*([%-%.%d]+)%s*,%s*([%-%.%d]+)%s*,%s*([%-%.%d]+)%s*$")
            if not (xs and ys and zs) then
                if Variables.notify then Variables.notify("Teleport: invalid format. Use: X, Y, Z") end
                return
            end
            local x = tonumber(xs); local y = tonumber(ys); local z = tonumber(zs)
            if not (x and y and z) then
                if Variables.notify then Variables.notify("Teleport: could not parse numbers.") end
                return
            end
            local lp = services.Players.LocalPlayer
            local ch = lp and lp.Character
            if not ch then
                if Variables.notify then Variables.notify("Teleport: character not ready.") end
                return
            end
            local hrp = ch:FindFirstChild("HumanoidRootPart")
            if not hrp then
                if Variables.notify then Variables.notify("Teleport: HumanoidRootPart not found.") end
                return
            end
            hrp.CFrame = CFrame.new(x, y, z)
        end

        local function ExecuteBoatTeleport()
            local lp  = services.Players.LocalPlayer
            local ch  = lp and lp.Character
            local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
            if not hrp then
                if Variables.notify then Variables.notify("Boat TP: Character not ready.") end
                return
            end

            local selectedDisplayString = Variables.BoatTPSelectedDisplay
            if UI.Options and UI.Options.UniversalBoatDropdown then
                selectedDisplayString = tostring(UI.Options.UniversalBoatDropdown.Value or selectedDisplayString)
            end
            Variables.BoatTPSelectedDisplay = selectedDisplayString

            local ownerName, boatName, modelName = ParseDropdownDisplay(selectedDisplayString)
            Variables.BoatTPSelectedModelName = modelName or ""

            if (not ownerName and not modelName) or (modelName == "" and (not boatName or boatName == "")) then
                if Variables.notify then Variables.notify("Boat TP: Please select a boat.") end
                return
            end

            local boatsFolder = GetBoatsFolder()
            if not boatsFolder then
                if Variables.notify then Variables.notify("Boat TP: Boats folder not set.") end
                return
            end

            local targetBoatModel = FindTargetBoatModel(boatsFolder, ownerName, boatName, modelName)
            if not targetBoatModel then
                if Variables.notify then Variables.notify("Boat TP: Target boat not found.") end
                return
            end

            local targetCFrame
            local gotPivot, boatPivot = pcall(targetBoatModel.GetPivot, targetBoatModel)
            if gotPivot and boatPivot then
                targetCFrame = boatPivot
            else
                local basePart = GetAnyBasePartFromModel(targetBoatModel)
                targetCFrame = basePart and basePart.CFrame or nil
            end

            if not targetCFrame then
                if Variables.notify then Variables.notify("Boat TP: Could not resolve boat position.") end
                return
            end

            hrp.CFrame = targetCFrame
            if Variables.notify then Variables.notify("Teleported to boat: " .. (targetBoatModel.Name or "?")) end
        end

        -- build/refresh boat dropdown values (simple: model names)
        local function RebuildUniversalBoatList()
            local list = {}
            local boatsFolder = GetBoatsFolder()
            if boatsFolder then
                for _, model in ipairs(boatsFolder:GetChildren()) do
                    if model:IsA("Model") then
                        table.insert(list, model.Name)
                    end
                end
            end
            Variables.UniversalBoatList = list
            if UI.Options and UI.Options.UniversalBoatDropdown then
                if UI.Options.UniversalBoatDropdown.SetValues then
                    UI.Options.UniversalBoatDropdown:SetValues(list)
                else
                    UI.Options.UniversalBoatDropdown.Values = list
                end
            end
        end

        -- UI
        do
            local tab = UI.Tabs.Main or UI.Tabs.Misc
            
            -- Renamed 'group' to 'CFrameGroup' for clarity
            local CFrameGroup = tab:AddRightGroupbox("Teleport", "door-open")

            CFrameGroup:AddInput("TeleportcFrame", {
                Default = "Format: X, Y, Z",
                Numeric = false,
                Finished = false,
                ClearTextOnFocus = true,
                Text = "Input cFrame Coordinates:",
                Tooltip = "Use the format [X, Y, Z]. Example: 0, 1000, 0",
                Placeholder = "0, 0, 0",
            })
            CFrameGroup:AddButton({
                Text = "Teleport",
                Func = function() Teleport_ApplyFromInputString() end,
                DoubleClick = true,
                Tooltip = "Double click to teleport to the inputted cFrame coordinates.",
                DisabledTooltip = "Feature Disabled",
                Disabled = false,
            })

            -- FIX: Add the Tabbox to the 'tab' object, not the 'group' object
            -- A Tabbox cannot be inside a Groupbox.
            -- I've added a title here for clarity, and used AddRightTabbox to match the groupbox.
            local PlayerBoatTabbox = tab:AddRightTabbox("Player/Boat TP")
            
            local playerTab = PlayerBoatTabbox:AddTab("Player TP")
            playerTab:AddDropdown("PlayerTPDropdown", {
                SpecialType = "Player",
                ExcludeLocalPlayer = true,
                Text = "Select Player:",
                Tooltip = "Click player & close dropdown to confirm selection.",
            })
            playerTab:AddButton({
                Text = "Teleport To Player",
                Func = function()
                    local target = UI.Options and UI.Options.PlayerTPDropdown and UI.Options.PlayerTPDropdown.Value
                    if typeof(target) == "Instance" and target:IsA("Player") then
                        local lp = services.Players.LocalPlayer
                        local ch = lp and lp.Character
                        local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
                        local tch = target.Character
                        local thrp = tch and tch:FindFirstChild("HumanoidRootPart")
                        if hrp and thrp then hrp.CFrame = thrp.CFrame end
                    end
                end,
                DoubleClick = true,
                Tooltip = "Double click to teleport to player.",
                DisabledTooltip = "Feature Disabled",
                Disabled = false,
            })

            local boatTab = PlayerBoatTabbox:AddTab("Boat TP")
            boatTab:AddDropdown("UniversalBoatDropdown", {
                Values = Variables.UniversalBoatList,
                Text = "Search or Select Boat:",
                Multi = false,
                Tooltip = "Click on target & close dropdown to confirm selection.",
                DisabledTooltip = "Feature Disabled!",
                Searchable = true,
                Disabled = false,
                Visible = true,
            })
            boatTab:AddButton({
                Text = "Teleport To Boat",
                Func = ExecuteBoatTeleport,
                DoubleClick = true,
                Tooltip = "Double click to teleport to boat.",
                DisabledTooltip = "Feature Disabled",
                Disabled = false,
            })
        end

        -- hook UI (input change)
        if UI.Options and UI.Options.TeleportcFrame and UI.Options.TeleportcFrame.OnChanged then
            UI.Options.TeleportcFrame:OnChanged(function(text)
                Variables.TeleportCFrameInputString = tostring(text or "")
            end)
        end

        -- refresh boat list periodically
        local refreshConn = services.RunService.Heartbeat:Connect(function(step)
            -- very light once per ~2s
            if not Variables._acc then Variables._acc = 0 end
            Variables._acc = Variables._acc + step
            if Variables._acc >= 2 then
                Variables._acc = 0
                RebuildUniversalBoatList()
            end
        end)
        maid:GiveTask(refreshConn)

        local function Stop()
            maid:DoCleaning()
        end

        return { Name = "Teleport", Stop = Stop }
    end
end
