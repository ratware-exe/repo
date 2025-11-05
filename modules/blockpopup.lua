
-- modules/block_popup.lua
do
    return function(UI)
        -- Dependencies
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv  = (getgenv and getgenv()) or _G
        GlobalEnv.Signal = GlobalEnv.Signal or loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()
        local Maid       = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()


        local Variables = {
            Maids = { BlockPopup = Maid.new() },
            RunFlag = false,
        }

        local function Patch()
            -- Disable modal popups by intercepting CoreGui notifications / custom popups in descendants
            local con = game.DescendantAdded:Connect(function(inst)
                if not Variables.RunFlag then return end
                if inst:IsA("BillboardGui") or inst:IsA("ScreenGui") or inst:IsA("Frame") then
                    pcall(function()
                        if inst.Name:lower():find("popup") or inst.Name:lower():find("dialog") then
                            inst.Visible = false
                            inst.Enabled = false
                        end
                    end)
                end
            end)
            Variables.Maids.BlockPopup:GiveTask(con)
        end

        local Module = {}
        function Module.Start()
            if Variables.RunFlag then return end
            Variables.RunFlag = true
            Patch()
            Variables.Maids.BlockPopup:GiveTask(function() Variables.RunFlag = false end)
        end
        function Module.Stop()
            if not Variables.RunFlag then return end
            Variables.RunFlag = false
            Variables.Maids.BlockPopup:DoCleaning()
        end

        local box = UI.Tabs.EXP:AddRightGroupbox("Block Popup", "ban")
        box:AddToggle("BlockPopupToggle", { Text = "Remove Popup", Default = false, Tooltip = "Blocks modal popups / dialogs client-side." })
        UI.Toggles.BlockPopupToggle:OnChanged(function(b) if b then Module.Start() else Module.Stop() end end)

        local ModuleContract = { Name = "BlockPopup", Stop = Module.Stop }

        return ModuleContract
    end
end
