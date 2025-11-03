-- modules/universal/Shield.lua
-- Purpose: Lightweight “safety shield” (log silencer / UI guard rails).
-- This is optional and non-invasive. It can be extended later.

return function()
    local RbxService
    local Variables
    local Maid
    local Library

    local Module = {}

    function Module.Init(env)
        RbxService = env.RbxService
        Variables  = env.Variables
        Maid       = env.Maid
        Library    = env.Library
        if not Variables.Maids.Shield then
            Variables.Maids.Shield = Maid.new()
        end
    end

    -- Fire-and-forget. No UI.
    function Module.Run()
        -- 1) Silences noisy, benign engine warnings to keep console clean.
        local LogSilencer = RbxService.LogService.MessageOut:Connect(function(message, messageType)
            -- Filter typical harmless spam; extend list if needed.
            local Lower = string.lower(message or "")
            if string.find(Lower, "infinite yield possible", 1, true) then
                return
            end
            if string.find(Lower, "http 403", 1, true) then
                return
            end
            if string.find(Lower, "luau analyze", 1, true) then
                return
            end
        end)

        Variables.Maids.Shield:GiveTask(LogSilencer)

        -- 2) Guard the CoreGui reset edge case (duplicate safety to main).
        local CoreGuiGuard = RbxService.CoreGui.AncestryChanged:Connect(function(instance, parent)
            if instance == RbxService.CoreGui and parent == nil then
                if Variables and Variables.CleanupAllMaids then
                    Variables.CleanupAllMaids()
                end
            end
        end)
        Variables.Maids.Shield:GiveTask(CoreGuiGuard)
    end

    function Module.BuildUI() end
    function Module.Start() end
    function Module.Stop()
        if Variables.Maids.Shield then
            Variables.Maids.Shield:DoCleaning()
        end
    end

    return Module
end
