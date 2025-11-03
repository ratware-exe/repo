-- modules/Shield.lua
do
    return function(UI)
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid       = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local Variables = {
            Maids = { Shield = Maid.new() },
            ShieldActive = false,
            OriginalFireServer = nil,
            FireServerMethodRef = nil,
        }

        local TelemetryPatterns = { "GA", "Report", "Log", "Analytics", "Telemetry", "Error" }

        local function IsTelemetryRemote(remoteName)
            if type(remoteName) ~= "string" then return false end
            for index = 1, #TelemetryPatterns do
                local pattern = TelemetryPatterns[index]
                if string.find(remoteName, pattern, 1, true) then
                    return true
                end
            end
            return false
        end

        local function EnsureMethodReference()
            if Variables.FireServerMethodRef then return Variables.FireServerMethodRef end

            -- Prefer an existing RemoteEvent under ReplicatedStorage/RemoteEvents
            local remoteEventsFolder = RbxService.ReplicatedStorage:FindFirstChild("RemoteEvents")
            local sampleRemote = remoteEventsFolder and remoteEventsFolder:FindFirstChildOfClass("RemoteEvent")

            -- Fallback: scan ReplicatedStorage
            if not sampleRemote then
                local descendants = RbxService.ReplicatedStorage:GetDescendants()
                for index = 1, #descendants do
                    local instanceObject = descendants[index]
                    if instanceObject:IsA("RemoteEvent") then
                        sampleRemote = instanceObject
                        break
                    end
                end
            end

            -- Last resort: create a dummy RemoteEvent to access its method pointer
            if not sampleRemote then
                sampleRemote = Instance.new("RemoteEvent")
            end

            Variables.FireServerMethodRef = sampleRemote.FireServer
            return Variables.FireServerMethodRef
        end

        local function Start()
            if Variables.ShieldActive then return end
            if not hookfunction then
                warn("[Shield] hookfunction not supported by this executor; telemetry block unavailable.")
                return
            end

            local methodRef = EnsureMethodReference()
            if not methodRef then
                warn("[Shield] Could not resolve RemoteEvent.FireServer method.")
                return
            end

            local original = hookfunction(methodRef, function(self, ...)
                if self and self:IsA("RemoteEvent") and IsTelemetryRemote(self.Name) then
                    -- Block telemetry-ish remotes
                    return
                end
                return original(self, ...)
            end)

            Variables.OriginalFireServer = original
            Variables.ShieldActive = true

            -- Track future RemoteEvents (keeps a valid methodRef if the tree is rebuilt)
            local watchConnection = RbxService.ReplicatedStorage.DescendantAdded:Connect(function(instanceObject)
                if not Variables.ShieldActive then return end
                if Variables.FireServerMethodRef then return end
                if instanceObject:IsA("RemoteEvent") then
                    Variables.FireServerMethodRef = instanceObject.FireServer
                end
            end)
            Variables.Maids.Shield:GiveTask(watchConnection)
        end

        local function Stop()
            if not Variables.ShieldActive then return end
            Variables.ShieldActive = false

            if hookfunction and Variables.FireServerMethodRef and Variables.OriginalFireServer then
                pcall(function()
                    hookfunction(Variables.FireServerMethodRef, Variables.OriginalFireServer)
                end)
            end

            Variables.Maids.Shield:DoCleaning()
            Variables.OriginalFireServer = nil
            -- Keep FireServerMethodRef cached; it is still valid for re-enable.
        end

        -- Minimal UI: Settings → Shield
        local groupbox = UI.Tabs.Settings:AddRightGroupbox("Shield", "shield")
        groupbox:AddToggle("ShieldToggle", {
            Text = "Block telemetry remotes",
            Tooltip = "Hooks RemoteEvent:FireServer to block names matching GA/Report/Log/Analytics/Telemetry/Error.",
            Default = true,
        })
        UI.Toggles.ShieldToggle:OnChanged(function(enabled)
            if enabled then Start() else Stop() end
        end)

        -- Auto-enable on mount
        if UI.Toggles.ShieldToggle.Value then
            Start()
        end

        local function ModuleStop()
            if UI.Toggles.ShieldToggle then
                UI.Toggles.ShieldToggle:SetValue(false)
            end
            Stop()
        end

        return { Name = "Shield", Stop = ModuleStop }
    end
end
