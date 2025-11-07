-- "modules/universal/travel/teleportcframe.lua",
do
    return function(UI)
        -- [1] LOAD DEPENDENCIES
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv = (getgenv and getgenv()) or _G
        local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        -- [2] MODULE STATE
        local ModuleName = "TeleportCFrame"
        local Variables = {
            Maids = { [ModuleName] = Maid.new() },
            TeleportCFrameInputString = "0, 0, 0",
            NotifyFunc = nil, -- Placeholder for notifier
        }

        -- [3] CORE LOGIC
        local function notify(msg)
            if Variables.NotifyFunc then
                pcall(Variables.NotifyFunc, msg)
            else
                print(msg) -- Fallback
            end
        end
        
        local function Teleport_ApplyFromInputString()
            local teleportInput = tostring(Variables.TeleportCFrameInputString or "")

            local xStr, yStr, zStr = string.match(
                teleportInput,
                "^%s*([%-%.%d]+)%s*,%s*([%-%.%d]+)%s*,%s*([%-%.%d]+)%s*$"
            )
            if not (xStr and yStr and zStr) then
                notify("Teleport: invalid format. Use: X, Y, Z")
                return
            end

            local xNum = tonumber(xStr)
            local yNum = tonumber(yStr)
            local zNum = tonumber(zStr)
            if not (xNum and yNum and zNum) then
                notify("Teleport: could not parse numbers.")
                return
            end
            
            local LocalPlayer = RbxService.Players.LocalPlayer
            if not (LocalPlayer and LocalPlayer.Character) then
                notify("Teleport: character not ready.")
                return
            end

            local teleportHumanoidRootPart = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if not teleportHumanoidRootPart then
                notify("Teleport: HumanoidRootPart not found.")
                return
            end

            teleportHumanoidRootPart.CFrame = CFrame.new(xNum, yNum, zNum)
            notify(("Teleported to: %.3f, %.3f, %.3f"):format(xNum, yNum, zNum))
        end

        -- This module isn't a toggle, so Start/Stop are minimal
        local function Start() end
        local function Stop()
            Variables.Maids[ModuleName]:DoCleaning()
        end

        -- [4] UI CREATION
        local TeleportGroupBox = UI.Tabs.Main:AddRightGroupbox("Teleport", "door-open")
		TeleportGroupBox:AddInput("TeleportcFrame", {
			Default = "Format: X, Y, Z",
			Numeric = false, 
			Finished = false, 
			ClearTextOnFocus = true, 
			Text = "Input cFrame Coordinates:", 
			Tooltip = "Use the format [X, Y, Z]. Example: 0, 1000, 0",
			Placeholder = "0, 0, 0", 
		})
		local cFrameCoordinateTPButton = TeleportGroupBox:AddButton({
				Text = "Teleport",
	    		Func = function() end, -- Wired below
				DoubleClick = true,
				Tooltip = "Click to teleport to the inputted cFrame coordinates.",
			})
        
        -- [5] UI WIRING
        
        -- Keep variable in sync with input
        UI.Options.TeleportcFrame:OnChanged(function(value)
            Variables.TeleportCFrameInputString = tostring(value or "")
        end)
        Variables.TeleportCFrameInputString = tostring(UI.Options.TeleportcFrame.Value or "0, 0, 0")
        
        -- Wire button
        local function Teleport_ButtonCallback()
            -- always read current UI value
            Variables.TeleportCFrameInputString = tostring(UI.Options.TeleportcFrame.Value or "")
            Teleport_ApplyFromInputString()
        end

        if cFrameCoordinateTPButton.SetCallback then
            cFrameCoordinateTPButton:SetCallback(Teleport_ButtonCallback)
        else
            cFrameCoordinateTPButton.Func = Teleport_ButtonCallback
        end
        
        Variables.Maids[ModuleName]:GiveTask(function()
             if cFrameCoordinateTPButton.SetCallback then
                 cFrameCoordinateTPButton:SetCallback(function() end)
             else
                 cFrameCoordinateTPButton.Func = function() end
             end
        end)


        -- [6] RETURN MODULE
        return { Name = ModuleName, Stop = Stop }
    end
end
