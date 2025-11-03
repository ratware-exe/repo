-- modules/AntiAFK.lua
do
    return function(UI)
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid       = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local Variables = {
            Maids = { AntiAFK = Maid.new() },
            RunFlag = false,
        }

        local function Start()
            if Variables.RunFlag then return end
            Variables.RunFlag = true

            local localPlayer = RbxService.Players.LocalPlayer
            if not localPlayer then
                Variables.RunFlag = false
                return
            end

            local featureMaid = Variables.Maids.AntiAFK
            pcall(function()
                for connectionIndex, connectionObject in next, getconnections(localPlayer.Idled) do
                    if typeof(connectionObject) == "table" and typeof(connectionObject.Disable) == "function" then
                        connectionObject:Disable()
                        featureMaid:GiveTask(function()
                            if typeof(connectionObject) == "table" and typeof(connectionObject.Enable) == "function" then
                                pcall(function() connectionObject:Enable() end)
                            end
                        end)
                    end
                end
            end)

            featureMaid:GiveTask(function() Variables.RunFlag = false end)
        end

        local function Stop()
            if not Variables.RunFlag then return end
            Variables.RunFlag = false
            Variables.Maids.AntiAFK:DoCleaning()
        end

        -- UI
        local groupbox = UI.Tabs.Misc:AddLeftGroupbox("Anti AFK", "mouse-pointer-2")
        groupbox:AddToggle("AntiAFKToggle", {
            Text = "Anti AFK",
            Tooltip = "Prevents you from being kicked for idling.",
            Default = false,
        })
        UI.Toggles.AntiAFKToggle:OnChanged(function(enabledState)
            if enabledState then Start() else Stop() end
        end)

        return { Name = "AntiAFK", Stop = Stop }
    end
end
