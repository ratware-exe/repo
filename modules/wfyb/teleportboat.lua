-- modules/wfyb/teleport_boat.lua
do
    return function(UI)
        -- [1] LOAD DEPENDENCIES
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv = (getgenv and getgenv()) or _G
        local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        -- [2] MODULE STATE
        local ModuleName = "TeleportBoat"
        local Variables = {
            Maids = { [ModuleName] = Maid.new() },
            NotifyFunc = nil,
            
            -- TP Logic
            BoatTPSelectedDisplay = "",
            BoatTPSelectedModelName = "",
            
            -- Dropdown Logic
            UniversalBoatList = {},
            UniversalBoatRenameInterval = 3,
            UniversalBoatsFolderRef = (RbxService.Workspace:FindFirstChild("Boats") or RbxService.Workspace:FindFirstChild("boat") or RbxService.Workspace:WaitForChild("Boats")),
        }

        -- [3] CORE LOGIC
        
        -- == Helper Functions ==
        local function notify(msg)
            if Variables.NotifyFunc then
                pcall(Variables.NotifyFunc, msg)
            else
                print(msg) -- Fallback
            end
        end
        
        local function IsBoatModel(modelInstance)
            return modelInstance
               and modelInstance:IsA("Model")
               and modelInstance:FindFirstChild("BoatData") ~= nil
        end
        
        local function ResolveOwnerDisplayName(ownerValueObject)
            local ownerValue = ownerValueObject and ownerValueObject.Value
            if ownerValue == nil then return "UnknownPlayer" end
            local valueType = typeof(ownerValue)
            if valueType == "number" then
                local gotName, userName = pcall(RbxService.Players.GetNameFromUserIdAsync, RbxService.Players, ownerValue)
                return gotName and userName or tostring(ownerValue)
            elseif valueType == "Instance" and ownerValue.Name then
                return ownerValue.Name
            end
            return tostring(ownerValue)
        end

        local function ResolveBoatDisplayName(boatDataFolder)
            local unfilteredNameValueObject = boatDataFolder and boatDataFolder:FindFirstChild("UnfilteredBoatName")
            return (unfilteredNameValueObject and tostring(unfilteredNameValueObject.Value)) or "UnknownBoat"
        end

        local function GetAnyBasePartFromModel(modelInstance)
            for descendantIndex, descendant in ipairs(modelInstance:GetDescendants()) do
                if descendant:IsA("BasePart") then
                    return descendant
                end
            end
            return nil
        end
        
        -- == Dropdown Populator Logic ==
        local function SetDropdownValues(optionObject, valueList)
            if not optionObject then return end
            if optionObject.SetValues then
                optionObject:SetValues(valueList)
            else
                optionObject.Values = valueList -- Fallback
            end
        end

        local function RebuildUniversalBoatList()
            if not Variables.UniversalBoatsFolderRef then
                notify("Boats folder not set.")
                return
            end

            local displayEntries = {}
            for childIndex, childModel in ipairs(Variables.UniversalBoatsFolderRef:GetChildren()) do
                if IsBoatModel(childModel) then
                    local boatDataFolder = childModel:FindFirstChild("BoatData")
                    local ownerValueObject = boatDataFolder and boatDataFolder:FindFirstChild("Owner")
                    local ownerDisplayName = ResolveOwnerDisplayName(ownerValueObject)
                    local boatDisplayName = ResolveBoatDisplayName(boatDataFolder)
                    local dropdownDisplayString = string.format("[%s, %s] [%s]", ownerDisplayName, boatDisplayName, childModel.Name)
                    table.insert(displayEntries, dropdownDisplayString)
                end
            end

            table.sort(displayEntries, function(leftString, rightString)
                return leftString:lower() < rightString:lower()
            end)

            table.clear(Variables.UniversalBoatList)
            for listIndex = 1, #displayEntries do
                Variables.UniversalBoatList[listIndex] = displayEntries[listIndex]
            end

            SetDropdownValues(UI.Options and UI.Options.UniversalBoatDropdown, Variables.UniversalBoatList)
        end
        
        -- == Teleport Logic ==
        local function ParseDropdownDisplay(displayString)
            if type(displayString) ~= "string" then return nil, nil, nil end
            local ownerName, boatName, modelName =
                displayString:match("^%[([^%]]-),%s*([^%]]-)%]%s*%[([^%]]-)%]%s*$")
            if ownerName and boatName and modelName then
                return ownerName, boatName, modelName
            end
            local trailingModelName = displayString:match("%[(.-)%]%s*$")
            return nil, nil, trailingModelName
        end

        local function FindTargetBoatModel(boatsFolder, targetOwnerName, targetBoatName, targetModelName)
            if not boatsFolder then return nil end

            if targetModelName and targetModelName ~= "" then
                local exactModel = boatsFolder:FindFirstChild(targetModelName) or boatsFolder:FindFirstChild(targetModelName, true)
                if exactModel and exactModel:IsA("Model") then
                    return exactModel
                end
            end

            local LocalPlayer = RbxService.Players.LocalPlayer
            local localHumanoidRoot = LocalPlayer and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            local closestModel = nil
            local closestDistance = nil

            for descendantIndex, descendantModel in ipairs(boatsFolder:GetDescendants()) do
                if descendantModel:IsA("Model") then
                    local boatDataFolder = descendantModel:FindFirstChild("BoatData") or descendantModel:FindFirstChild("BoatData", true)
                    if boatDataFolder then
                        local ownerValueObject = boatDataFolder:FindFirstChild("Owner")
                        local unfilteredNameValueObject = boatDataFolder:FindFirstChild("UnfilteredBoatName")
                        local ownerMatches = true
                        local boatNameMatches = true

                        if targetOwnerName and targetOwnerName ~= "" then
                            ownerMatches = (ResolveOwnerDisplayName(ownerValueObject) == targetOwnerName)
                        end
                        if targetBoatName and targetBoatName ~= "" then
                            boatNameMatches = (unfilteredNameValueObject and tostring(unfilteredNameValueObject.Value) == targetBoatName)
                        end

                        if ownerMatches and boatNameMatches then
                            if not localHumanoidRoot then return descendantModel end
                            
                            local modelPosition
                            local pivotOk, pivotCFrame = pcall(descendantModel.GetPivot, descendantModel)
                            if pivotOk and pivotCFrame then
                                modelPosition = pivotCFrame.Position
                            else
                                local anyBasePart = GetAnyBasePartFromModel(descendantModel)
                                modelPosition = anyBasePart and anyBasePart.Position or nil
                            end
                            if modelPosition then
                                local distanceToPlayer = (modelPosition - localHumanoidRoot.Position).Magnitude
                                if not closestDistance or distanceToPlayer < closestDistance then
                                    closestModel = descendantModel
                                    closestDistance = distanceToPlayer
                                end
                            end
                        end
                    end
                end
            end
            return closestModel
        end

        local function ExecuteBoatTeleport()
            local LocalPlayer = RbxService.Players.LocalPlayer
            local localHumanoidRoot = LocalPlayer and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if not localHumanoidRoot then
                notify("Boat TP: Character not ready.")
                return
            end

            local selectedDisplayString = tostring(UI.Options.UniversalBoatDropdown.Value or Variables.BoatTPSelectedDisplay)
            Variables.BoatTPSelectedDisplay = selectedDisplayString

            local selectedOwnerName, selectedBoatName, selectedModelName = ParseDropdownDisplay(selectedDisplayString)
            Variables.BoatTPSelectedModelName = selectedModelName or ""

            if (not selectedOwnerName and not selectedModelName) or (selectedModelName == "" and (not selectedBoatName or selectedBoatName == "")) then
                notify("Boat TP: Please select a boat.")
                return
            end

            local boatsFolder = Variables.UniversalBoatsFolderRef
            if not boatsFolder then
                notify("Boat TP: Boats folder not set.")
                return
            end

            local targetBoatModel = FindTargetBoatModel(boatsFolder, selectedOwnerName, selectedBoatName, selectedModelName)
            if not targetBoatModel then
                notify("Boat TP: Target boat not found.")
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
                notify("Boat TP: Could not resolve boat position.")
                return
            end

            localHumanoidRoot.CFrame = targetCFrame
            notify("Teleported to boat: " .. (targetBoatModel.Name or "?"))
        end

        -- This module just provides a feature, no main loop
        local function Start()
            -- This function wires up the dropdown populator
            if not Variables.UniversalBoatsFolderRef then return end
            
            local maid = Variables.Maids[ModuleName]
            
            maid:GiveTask(Variables.UniversalBoatsFolderRef.ChildAdded:Connect(RebuildUniversalBoatList))
            maid:GiveTask(Variables.UniversalBoatsFolderRef.ChildRemoved:Connect(RebuildUniversalBoatList))

            for childIndex, childModel in ipairs(Variables.UniversalBoatsFolderRef:GetChildren()) do
                if childModel:IsA("Model") then
                    maid:GiveTask(childModel:GetPropertyChangedSignal("Name"):Connect(RebuildUniversalBoatList))
                    local boatDataFolder = childModel:FindFirstChild("BoatData")
                    if boatDataFolder then
                        local ownerValueObject = boatDataFolder:FindFirstChild("Owner")
                        local unfilteredNameValueObject = boatDataFolder:FindFirstChild("UnfilteredBoatName")
                        if ownerValueObject then
                            maid:GiveTask(ownerValueObject:GetPropertyChangedSignal("Value"):Connect(RebuildUniversalBoatList))
                        end
                        if unfilteredNameValueObject then
                            maid:GiveTask(unfilteredNameValueObject:GetPropertyChangedSignal("Value"):Connect(RebuildUniversalBoatList))
                        end
                    end
                end
            end

            maid:GiveTask(task.spawn(function()
                while true do -- The loop will be killed when the maid is cleaned
                    local refreshSeconds = tonumber(Variables.UniversalBoatRenameInterval) or 3
                    if refreshSeconds <= 0 then refreshSeconds = 0.1 end
                    RebuildUniversalBoatList()
                    task.wait(refreshSeconds)
                end
            end))
            
            RebuildUniversalBoatList() -- Initial fill
        end
        
        local function Stop()
            Variables.Maids[ModuleName]:DoCleaning()
        end

        -- [4] UI CREATION
        local TeleportBox = UI.Tabs.Main:AddRightTabbox()
        local BoatTPTabBox = TeleportBox:AddTab("Boat TP")
        BoatTPTabBox:AddDropdown("UniversalBoatDropdown", {
            Values = Variables.UniversalBoatList,
            Text = "Search or Select Boat:",
            Multi = false,
            Tooltip = "Click on target & close dropdown to confirm selection.",
            Searchable = true,
        })
        local BoatTPButton = BoatTPTabBox:AddButton({
            Text = "Teleport To Boat",
            Func = function() end, -- Wired below
            DoubleClick = true,
            Tooltip = "Double click to teleport to boat.",
        })
        
        -- [5] UI WIRING
        local function OnDropdownChanged(newValue)
            local asString = tostring(newValue or "")
            Variables.BoatTPSelectedDisplay = asString
            local _, _, parsedModelName = asString:match("^%[([^%]]-),%s*([^%]]-)%]%s*%[([^%]]-)%]%s*$")
            Variables.BoatTPSelectedModelName = parsedModelName or (asString:match("%[(.-)%]%s*$") or "")
        end
        
        UI.Options.UniversalBoatDropdown:OnChanged(OnDropdownChanged)
        OnDropdownChanged(UI.Options.UniversalBoatDropdown.Value) -- Seed
        
        local function OnBoatTPButtonClicked()
            ExecuteBoatTeleport()
        end
        
        if BoatTPButton.SetCallback then
            BoatTPButton:SetCallback(OnBoatTPButtonClicked)
        else
            BoatTPButton.Func = OnBoatTPButtonClicked
        end

        Variables.Maids[ModuleName]:GiveTask(function()
            if BoatTPButton.SetCallback then
                BoatTPButton:SetCallback(function() end)
            else
                BoatTPButton.Func = function() end
            end
        end)
        
        -- Start the dropdown populator
        Start()

        -- [6] RETURN MODULE
        return { Name = ModuleName, Stop = Stop }
    end
end
