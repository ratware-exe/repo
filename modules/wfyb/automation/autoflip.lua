-- modules/automation/autoflip.lua
do
    return function(UI)
        -- [1] DEPENDENCIES
        local GlobalEnv = (getgenv and getgenv()) or _G
        local RbxService = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local RunService = RbxService.RunService
        local Workspace  = RbxService.Workspace

        -- [2] STATE
        local ModuleName = "AutoFlip"
        local Variables = {
            Maids = { [ModuleName] = Maid.new() },
            RunFlag = false,
            -- weak keys so destroyed attachments disappear naturally
            AttachWatch = setmetatable({}, { __mode = "k" }), -- [Attachment] = { maid, lastFire, nextCheck }
        }
        local maid = Variables.Maids[ModuleName]

        -- [3] CONSTANTS / HELPERS
        local CHECK_INTERVAL      = 0.25   -- seconds (UI ticks at ~0.25s)
        local FIRE_MIN_INTERVAL   = 0.60   -- seconds (anti-spam)
        local UPRIGHT_TOLERANCE   = 0.19634954084936207 -- ~11.25° in radians

        local function clamp(x, a, b)
            if x < a then return a end
            if x > b then return b end
            return x
        end

        local function getRemote(attach)
            local re = attach:FindFirstChild("BoatFlipperRemoteEvent")
            if re and re:IsA("RemoteEvent") then return re end
            -- fallback: any RemoteEvent whose name contains "flipp"
            for _, c in ipairs(attach:GetChildren()) do
                if c:IsA("RemoteEvent") and string.find(string.lower(c.Name), "flipp", 1, true) then
                    return c
                end
            end
            return nil
        end

        local function isFlipping(attach)
            -- present only while flipper is actively aligning
            return attach:FindFirstChild("BoatFlipperAlignOrientation") ~= nil
        end

        local function isUpright(attach)
            -- same math as game-side code: dot(worldUp, attachUp) -> angle
            local worldUp = Vector3.new(0, 1, 0)

            local axis
            local okAxis, worldAxis = pcall(function() return attach.WorldAxis end)
            if okAxis and worldAxis then
                axis = worldAxis
            else
                local okCF, wcf = pcall(function() return attach.WorldCFrame end)
                axis = okCF and wcf and wcf.UpVector or worldUp
            end

            local d = clamp(axis:Dot(worldUp), -1, 1)
            local angle = math.acos(d)
            return angle <= UPRIGHT_TOLERANCE
        end

        local function ensureAttachmentTracked(attach)
            if not attach or not attach:IsA("Attachment") or attach.Name ~= "BoatFlipper" then return end
            if Variables.AttachWatch[attach] then return end

            local aMaid = Maid.new()
            Variables.AttachWatch[attach] = { maid = aMaid, lastFire = 0, nextCheck = 0 }

            -- Clean up when the attachment dies
            aMaid:GiveTask(attach.Destroying:Connect(function()
                aMaid:DoCleaning()
                Variables.AttachWatch[attach] = nil
            end))

            -- Flip-state toggles should prompt a quick re-check
            aMaid:GiveTask(attach.ChildAdded:Connect(function(ch)
                if ch.Name == "BoatFlipperAlignOrientation" then
                    local rec = Variables.AttachWatch[attach]
                    if rec then rec.nextCheck = 0 end
                end
            end))
            aMaid:GiveTask(attach.ChildRemoved:Connect(function(ch)
                if ch.Name == "BoatFlipperAlignOrientation" then
                    local rec = Variables.AttachWatch[attach]
                    if rec then rec.nextCheck = 0 end
                end
            end))
        end

        local function initialScan()
            for _, inst in ipairs(Workspace:GetDescendants()) do
                if inst:IsA("Attachment") and inst.Name == "BoatFlipper" then
                    ensureAttachmentTracked(inst)
                end
            end
        end

        local function Start()
            if Variables.RunFlag then return end
            Variables.RunFlag = true

            -- Watch for future BoatFlipper attachments anywhere in Workspace
            maid["DescAdded"] = Workspace.DescendantAdded:Connect(function(inst)
                if inst:IsA("Attachment") and inst.Name == "BoatFlipper" then
                    ensureAttachmentTracked(inst)
                end
            end)

            initialScan()

            -- Light polling loop (mirrors ActionHint cadence)
            maid["Heartbeat"] = RunService.Heartbeat:Connect(function()
                if not Variables.RunFlag then return end
                local now = time()

                for attach, rec in pairs(Variables.AttachWatch) do
                    -- Skip if not in workspace anymore (Destroying guard handles normal case)
                    if not attach.Parent or not attach:IsDescendantOf(Workspace) then
                        -- let weak table + Destroying clear it
                    else
                        if now >= rec.nextCheck then
                            rec.nextCheck = now + CHECK_INTERVAL

                            local remote = getRemote(attach)
                            if remote then
                                local flipping = isFlipping(attach)
                                local upright  = isUpright(attach)

                                -- Fire iff the UI would be up AND not already flipping:
                                -- (UI) => not upright OR flipping; gating by not flipping -> not upright AND not flipping
                                if (not upright) and (not flipping) then
                                    if (now - rec.lastFire) >= FIRE_MIN_INTERVAL then
                                        rec.lastFire = now
                                        pcall(function() remote:FireServer() end)
                                    end
                                end
                            end
                        end
                    end
                end
            end)
        end

        privateStop = function()
            maid["Heartbeat"] = nil
            maid["DescAdded"] = nil
            for attach, rec in pairs(Variables.AttachWatch) do
                rec.maid:DoCleaning()
                Variables.AttachWatch[attach] = nil
            end
        end

        local function Stop()
            if not Variables.RunFlag then return end
            Variables.RunFlag = false
            privateStop()
        end

        -- [4] UI (same API but clarifies scope)
        local AutomationTab = UI.Tabs.Automation or UI:AddTab("Automation", "tractor")
        local CombatGroupBox = AutomationTab:AddLeftGroupbox("Combat", "swords")

        local AutoFlipToggle = CombatGroupBox:AddToggle("AutoFlipToggle", {
            Text = "Auto Flip (ALL Seats)",
            Tooltip = "Flips any overturned seat that has a BoatFlipper attachment.",
            Default = false,
            Disabled = false,
            Visible = true,
            Risky = true, -- because it affects others too
        })

        AutoFlipToggle:OnChanged(function(v) if v then Start() else Stop() end end)
        if AutoFlipToggle.Value then Start() end

        return { Name = ModuleName, Stop = Stop }
    end
end
