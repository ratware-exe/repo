-- modules/wfyb/teleport.lua
do
    return function(UserInterface)
        local Services = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
        local CleanupMaid = Maid.new()

        -- Module-specific state
        local ModuleState = {
            TeleportCFrameInputString = "0, 0, 0",
            PlayerTPTargetName = "",
            BoatTPSelectedDisplay = "",
            BoatTPSelectedModelName = "",
            UniversalBoatList = {},  -- values filled live
            UniversalBoatRenameInterval = 3,
        }

        -- Utilities from prompt.lua (verbatim)
        local function GetBoatsFolder()
            return Services.Workspace:FindFirstChild("Boats")
        end

        local function GetAnyBasePartFromModel(Model)
            -- This is the version from prompt.lua
            for DescendantIndex, Descendant in ipairs(Model:GetDescendants()) do
                if Descendant:IsA("BasePart") then
                    return Descendant
                end
            end
            return nil
        end

        local function ResolveOwnerDisplayName(OwnerValueObject)
            -- This is the version from prompt.lua
            local OwnerValue = OwnerValueObject and OwnerValueObject.Value
            if OwnerValue == nil then
                return "UnknownPlayer"
            end
            local ValueType = typeof(OwnerValue)
            if ValueType == "number" then
                local GotName, UserName = pcall(Services.Players.GetNameFromUserIdAsync, Services.Players, OwnerValue)
                return GotName and UserName or tostring(OwnerValue)
            elseif ValueType == "Instance" and OwnerValue.Name then
                return OwnerValue.Name
            end
            return tostring(OwnerValue)
        end
        
        local function ParseDropdownDisplay(DisplayString)
            -- This is the version from prompt.lua
            if type(DisplayString) ~= "string" then
                return nil, nil, nil
            end
            -- "[Owner, BoatName] [ModelName]"
            local OwnerName, BoatName, ModelName =
                DisplayString:match("^%[([^%]]-),%s*([^%]]-)%]%s*%[([^%]]-)%]%s*$")
            if OwnerName and BoatName and ModelName then
                return OwnerName, BoatName, ModelName
            end
            -- fallback: treat trailing [ModelName] as selection
            local TrailingModelName = DisplayString:match("%[(.-)%]%s*$")
            return nil, nil, TrailingModelName
        end

        local function FindTargetBoatModel(BoatsFolder, TargetOwnerName, TargetBoatName, TargetModelName)
            -- This is the version from prompt.lua
            if not BoatsFolder then return nil end

            -- 1) Exact model name match first
            if TargetModelName and TargetModelName ~= "" then
                local ExactModel = BoatsFolder:FindFirstChild(TargetModelName) or BoatsFolder:FindFirstChild(TargetModelName, true)
                if ExactModel and ExactModel:IsA("Model") then
                    return ExactModel
                end
            end

            -- 2) Fallback: match by BoatData
            local LocalPlayer = Services.Players.LocalPlayer
            local LocalCharacter = LocalPlayer and LocalPlayer.Character
            local LocalHumanoidRoot = LocalCharacter and LocalCharacter:FindFirstChild("HumanoidRootPart")

            local ClosestModel = nil
            local ClosestDistance = nil

            for DescendantIndex, DescendantModel in ipairs(BoatsFolder:GetDescendants()) do
                if DescendantModel:IsA("Model") then
                    local BoatDataFolder = DescendantModel:FindFirstChild("BoatData") or DescendantModel:FindFirstChild("BoatData", true)
                    if BoatDataFolder then
                        local OwnerValueObject = BoatDataFolder:FindFirstChild("Owner")
                        local UnfilteredNameValueObject = BoatDataFolder:FindFirstChild("UnfilteredBoatName")

                        local OwnerMatches = true
                        local BoatNameMatches = true

                        if TargetOwnerName and TargetOwnerName ~= "" then
                            OwnerMatches = (ResolveOwnerDisplayName(OwnerValueObject) == TargetOwnerName)
                        end
                        if TargetBoatName and TargetBoatName ~= "" then
                            BoatNameMatches = (UnfilteredNameValueObject and tostring(UnfilteredNameValueObject.Value) == TargetBoatName)
                        end

                        if OwnerMatches and BoatNameMatches then
                            if not LocalHumanoidRoot then
                                return DescendantModel
                            end
                            local ModelPosition
                            local PivotOk, PivotCFrame = pcall(DescendantModel.GetPivot, DescendantModel)
                            if PivotOk and PivotCFrame then
                                ModelPosition = PivotCFrame.Position
                            else
                                local AnyBasePart = GetAnyBasePartFromModel(DescendantModel)
                                ModelPosition = AnyBasePart and AnyBasePart.Position or nil
                            end
                            if ModelPosition then
                                local DistanceToPlayer = (ModelPosition - LocalHumanoidRoot.Position).Magnitude
                                if not ClosestDistance or DistanceToPlayer < ClosestDistance then
                                    ClosestModel = DescendantModel
                                    ClosestDistance = DistanceToPlayer
                                end
                            end
                        end
                    end
                end
            end
            return ClosestModel
        end

        -- CFrame TP Logic (from prompt.lua)
        local function ApplyCFrameTeleport()
            local TeleportInput = tostring(ModuleState.TeleportCFrameInputString or "")
            local XString, YString, ZString = string.match(
                TeleportInput,
                "^%s*([%-%.%d]+)%s*,%s*([%-%.%d]+)%s*,%s*([%-%.%d]+)%s*$"
            )
            if not (XString and YString and ZString) then
                if ModuleState.notify then ModuleState.notify("Teleport: invalid format. Use: X, Y, Z") end
                return
            end
            local XNumber = tonumber(XString); local YNumber = tonumber(YString); local ZNumber = tonumber(ZString)
            if not (XNumber and YNumber and ZNumber) then
                if ModuleState.notify then ModuleState.notify("Teleport: could not parse numbers.") end
                return
            end
            local LocalPlayer = Services.Players.LocalPlayer
            local Character = LocalPlayer and LocalPlayer.Character
            if not Character then
                if ModuleState.notify then ModuleState.notify("Teleport: character not ready.") end
                return
            end
            local HumanoidRootPart = Character:FindFirstChild("HumanoidRootPart")
            if not HumanoidRootPart then
                if ModuleState.notify then ModuleState.notify("Teleport: HumanoidRootPart not found.") end
                return
            end
            HumanoidRootPart.CFrame = CFrame.new(XNumber, YNumber, ZNumber)
        end

        -- Player TP Logic (from prompt.lua)
        local function ExecutePlayerTeleport()
            local ChosenTargetName = ModuleState.PlayerTPTargetName
            if UserInterface.Options and UserInterface.Options.PlayerTPDropdown and UserInterface.Options.PlayerTPDropdown.Value ~= nil then
                local DropdownValue = UserInterface.Options.PlayerTPDropdown.Value
                if typeof(DropdownValue) == "Instance" and DropdownValue:IsA("Player") then
                    ChosenTargetName = DropdownValue.Name
                elseif type(DropdownValue) == "string" and DropdownValue ~= "" then
                    ChosenTargetName = DropdownValue
                end
            end

            if type(ChosenTargetName) ~= "string" or ChosenTargetName == "" then
                if ModuleState.notify then ModuleState.notify("Player TP: Please Select Target!") end
                return
            end

            local TargetPlayer = Services.Players:FindFirstChild(ChosenTargetName)
            if not TargetPlayer then
                if ModuleState.notify then ModuleState.notify("Player TP: Target Not Found!") end
                return
            end

            local LocalPlayer = Services.Players.LocalPlayer
            local Character = LocalPlayer and LocalPlayer.Character
            if not Character then
                 if ModuleState.notify then ModuleState.notify("Player TP: You're Not Spawned In!.") end
                return
            end

            local TargetCharacter = TargetPlayer.Character
            if not TargetCharacter then
                if ModuleState.notify then ModuleState.notify("Player TP: Character Missing!") end
                return
            end

            local LocalHumanoidRootPart  = Character:FindFirstChild("HumanoidRootPart")
            local TargetHumanoidRootPart = TargetCharacter:FindFirstChild("HumanoidRootPart")
            if not (LocalHumanoidRootPart and TargetHumanoidRootPart) then
                if ModuleState.notify then ModuleState.notify("Player TP: Target Not Found!") end
                return
            end

            LocalHumanoidRootPart.CFrame = TargetHumanoidRootPart.CFrame
        end

        -- Boat TP Logic (from prompt.lua)
        local function ExecuteBoatTeleport()
            local LocalPlayer  = Services.Players.LocalPlayer
            local Character  = LocalPlayer and LocalPlayer.Character
            local HumanoidRootPart = Character and Character:FindFirstChild("HumanoidRootPart")
            if not HumanoidRootPart then
                if ModuleState.notify then ModuleState.notify("Boat TP: Character not ready.") end
                return
            end

            local SelectedDisplayString = ModuleState.BoatTPSelectedDisplay
            if UserInterface.Options and UserInterface.Options.UniversalBoatDropdown then
                SelectedDisplayString = tostring(UserInterface.Options.UniversalBoatDropdown.Value or SelectedDisplayString)
            end
            ModuleState.BoatTPSelectedDisplay = SelectedDisplayString

            local OwnerName, BoatName, ModelName = ParseDropdownDisplay(SelectedDisplayString)
            ModuleState.BoatTPSelectedModelName = ModelName or ""

            if (not OwnerName and not ModelName) or (ModelName == "" and (not BoatName or BoatName == "")) then
                if ModuleState.notify then ModuleState.notify("Boat TP: Please select a boat.") end
                return
            end

            local BoatsFolder = GetBoatsFolder()
            if not BoatsFolder then
                if ModuleState.notify then ModuleState.notify("Boat TP: Boats folder not set.") end
                return
            end

            local TargetBoatModel = FindTargetBoatModel(BoatsFolder, OwnerName, BoatName, ModelName)
            if not TargetBoatModel then
                if ModuleState.notify then ModuleState.notify("Boat TP: Target boat not found.") end
                return
            end

            local TargetCFrame
            local GotPivot, BoatPivot = pcall(TargetBoatModel.GetPivot, TargetBoatModel)
            if GotPivot and BoatPivot then
                TargetCFrame = BoatPivot
            else
                local BasePart = GetAnyBasePartFromModel(TargetBoatModel)
                TargetCFrame = BasePart and BasePart.CFrame or nil
            end

            if not TargetCFrame then
                if ModuleState.notify then ModuleState.notify("Boat TP: Could not resolve boat position.") end
                return
            end

            HumanoidRootPart.CFrame = TargetCFrame
        end

        -- Universal Boat Dropdown List Module (from prompt.lua)
        do
            local function SetDropdownValues(OptionObject, ValueList)
                if not OptionObject then return end
                if OptionObject.SetValues then
                    OptionObject:SetValues(ValueList)
                else
                    OptionObject.Values = ValueList
                end
                if #ValueList > 0 and OptionObject.SetValue and (not OptionObject.Value or OptionObject.Value == "") then
                    OptionObject:SetValue(ValueList[1])
                end
            end

            local UniversalBoatsFolderReference = GetBoatsFolder()

            local function IsBoatModel(ModelInstance)
                return ModelInstance
                   and ModelInstance:IsA("Model")
                   and ModelInstance:FindFirstChild("BoatData") ~= nil
            end

            local function ResolveBoatDisplayName(BoatDataFolder)
                local UnfilteredNameValueObject = BoatDataFolder and BoatDataFolder:FindFirstChild("UnfilteredBoatName")
                return (UnfilteredNameValueObject and tostring(UnfilteredNameValueObject.Value)) or "UnknownBoat"
            end

            local function RebuildUniversalBoatList()
                if not UniversalBoatsFolderReference then return end

                local DisplayEntries = {}
                for ChildIndex, ChildModel in ipairs(UniversalBoatsFolderReference:GetChildren()) do
                    if IsBoatModel(ChildModel) then
                        local BoatDataFolder         = ChildModel:FindFirstChild("BoatData")
                        local OwnerValueObject       = BoatDataFolder and BoatDataFolder:FindFirstChild("Owner")
                        local OwnerDisplayName       = ResolveOwnerDisplayName(OwnerValueObject)
                        local BoatDisplayName        = ResolveBoatDisplayName(BoatDataFolder)
                        local DropdownDisplayString  = string.format("[%s, %s] [%s]", OwnerDisplayName, BoatDisplayName, ChildModel.Name)
                        table.insert(DisplayEntries, DropdownDisplayString)
                    end
                end

                table.sort(DisplayEntries, function(LeftString, RightString)
                    return LeftString:lower() < RightString:lower()
                end)

                table.clear(ModuleState.UniversalBoatList)
                for ListIndex = 1, #DisplayEntries do
                    ModuleState.UniversalBoatList[ListIndex] = DisplayEntries[ListIndex]
                end

                SetDropdownValues(UserInterface.Options and UserInterface.Options.UniversalBoatDropdown, ModuleState.UniversalBoatList)
            end

            if UniversalBoatsFolderReference then
                CleanupMaid:GiveTask(UniversalBoatsFolderReference.ChildAdded:Connect(RebuildUniversalBoatList))
                CleanupMaid:GiveTask(UniversalBoatsFolderReference.ChildRemoved:Connect(RebuildUniversalBoatList))

                for ChildIndex, ChildModel in ipairs(UniversalBoatsFolderReference:GetChildren()) do
                    if ChildModel:IsA("Model") then
                        CleanupMaid:GiveTask(ChildModel:GetPropertyChangedSignal("Name"):Connect(RebuildUniversalBoatList))
                        local BoatDataFolder = ChildModel:FindFirstChild("BoatData")
                        if BoatDataFolder then
                            local OwnerValueObject = BoatDataFolder:FindFirstChild("Owner")
                            local UnfilteredNameValueObject = BoatDataFolder:FindFirstChild("UnfilteredBoatName")
                            if OwnerValueObject then
                                CleanupMaid:GiveTask(OwnerValueObject:GetPropertyChangedSignal("Value"):Connect(RebuildUniversalBoatList))
                            end
                            if UnfilteredNameValueObject then
                                CleanupMaid:GiveTask(UnfilteredNameValueObject:GetPropertyChangedSignal("Value"):Connect(RebuildUniversalBoatList))
                            end
                        end
                    end
                end

                local RenamerThread = task.spawn(function()
                    while true do
                        local RefreshSeconds = tonumber(ModuleState.UniversalBoatRenameInterval) or 3
                        if RefreshSeconds <= 0 then RefreshSeconds = 0.1 end
                        RebuildUniversalBoatList()
                        task.wait(RefreshSeconds)
                    end
                end)
                CleanupMaid:GiveTask(RenamerThread)

                RebuildUniversalBoatList()
                task.defer(function()
                    if UserInterface.Options and UserInterface.Options.UniversalBoatDropdown then
                        SetDropdownValues(UserInterface.Options.UniversalBoatDropdown, ModuleState.UniversalBoatList)
                    end
                end)
            end
        end


        -- UI (from teleport_fixed.lua, with corrected layout)
        do
            local Tab = UserInterface.Tabs.Main or UserInterface.Tabs.Misc
            
            local CFrameGroup = Tab:AddRightGroupbox("Teleport", "door-open")

            CFrameGroup:AddInput("TeleportcFrame", {
                Default = "Format: X, Y, Z",
                Numeric = false,
                Finished = false,
                ClearTextOnFocus = true,
                Text = "Input cFrame Coordinates:",
                Tooltip = "Use the format [X, Y, Z]. Example: 0, 1000, 0",
                Placeholder = "0, 0, 0",
            })
            local CFrameCoordinateTeleportButton = CFrameGroup:AddButton({
                Text = "Teleport",
                Func = ApplyCFrameTeleport, -- Wired to correct function
                DoubleClick = true,
                Tooltip = "Double click to teleport to the inputted cFrame coordinates.",
                DisabledTooltip = "Feature Disabled",
                Disabled = false,
            })

            local PlayerBoatTabbox = Tab:AddRightTabbox("Player/Boat TP")
            
            local PlayerTab = PlayerBoatTabbox:AddTab("Player TP")
            PlayerTab:AddDropdown("PlayerTPDropdown", {
                SpecialType = "Player",
                ExcludeLocalPlayer = true,
                Text = "Select Player:",
                Tooltip = "Click player & close dropdown to confirm selection.",
            })
            local PlayerTeleportButton = PlayerTab:AddButton({
                Text = "Teleport To Player",
                Func = ExecutePlayerTeleport, -- Wired to correct function
                DoubleClick = true,
                Tooltip = "Double click to teleport to player.",
                DisabledTooltip = "Feature Disabled",
                Disabled = false,
            })

            local BoatTab = PlayerBoatTabbox:AddTab("Boat TP")
            BoatTab:AddDropdown("UniversalBoatDropdown", {
                Values = ModuleState.UniversalBoatList,
                Text = "Search or Select Boat:",
                Multi = false,
                Tooltip = "Click on target & close dropdown to confirm selection.",
                DisabledTooltip = "Feature Disabled!",
                Searchable = true,
                Disabled = false,
                Visible = true,
            })
            local BoatTeleportButton = BoatTab:AddButton({
                Text = "Teleport To Boat",
                Func = ExecuteBoatTeleport, -- Wired to correct function
                DoubleClick = true,
                Tooltip = "Double click to teleport to boat.",
                DisabledTooltip = "Feature Disabled",
                Disabled = false,
            })
        end

        -- UI Wiring (from prompt.lua)
        do
            -- CFrame Input
            if UserInterface.Options and UserInterface.Options.TeleportcFrame and UserInterface.Options.TeleportcFrame.OnChanged then
                CleanupMaid:GiveTask(UserInterface.Options.TeleportcFrame:OnChanged(function(Text)
                    ModuleState.TeleportCFrameInputString = tostring(Text or "")
                end))
            end

            -- Player TP Dropdown
            if UserInterface.Options and UserInterface.Options.PlayerTPDropdown and UserInterface.Options.PlayerTPDropdown.OnChanged then
                 CleanupMaid:GiveTask(UserInterface.Options.PlayerTPDropdown:OnChanged(function(PlayerTeleportDropdownValue)
                    if typeof(PlayerTeleportDropdownValue) == "Instance" and PlayerTeleportDropdownValue:IsA("Player") then
                        ModuleState.PlayerTPTargetName = PlayerTeleportDropdownValue.Name
                    elseif type(PlayerTeleportDropdownValue) == "string" then
                        ModuleState.PlayerTPTargetName = PlayerTeleportDropdownValue
                    else
                        ModuleState.PlayerTPTargetName = ""
                    end
                end))
            end
            
            -- Boat TP Dropdown
            local DropdownOption = UserInterface.Options and UserInterface.Options.UniversalBoatDropdown
            if DropdownOption then
                local function OnDropdownChanged(NewValue)
                    local AsString = tostring(NewValue or "")
                    ModuleState.BoatTPSelectedDisplay = AsString
                    local _, _, ParsedModelName = ParseDropdownDisplay(AsString)
                    ModuleState.BoatTPSelectedModelName = ParsedModelName or ""
                end

                if DropdownOption.OnChanged then
                    CleanupMaid:GiveTask(DropdownOption:OnChanged(OnDropdownChanged))
                end
                OnDropdownChanged(DropdownOption.Value) -- Set initial value
            end
        end
        
        local function Stop()
            CleanupMaid:DoCleaning()
        end

        return { Name = "Teleport", Stop = Stop }
    end
end
