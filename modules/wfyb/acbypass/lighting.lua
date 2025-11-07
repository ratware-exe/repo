-- "modules/wfyb/acbypass/lighting.lua",
do
    return function(UI)
        -- [1] LOAD DEPENDENCIES
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local GlobalEnv = (getgenv and getgenv()) or _G
        local Maid = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
        
        -- [2] MODULE STATE
        local ModuleName = "ACBypassLighting"
        local Variables = {
            Maids = { [ModuleName] = Maid.new() },
        }

        -- [3] CORE LOGIC
        -- This is a run-once module, so logic goes in the main body.
        
        pcall(function()
            getgenv().WFYB = getgenv().WFYB or {}
            local cleanupMaid = Variables.Maids[ModuleName]
            
            local function noSkyEnabled()
                -- Check if the NoSky module is loaded and enabled
                local noSkyToggle = UI.Toggles.RemoveSkyToggle
                return noSkyToggle and noSkyToggle.Value or false
            end
            
            local function removeSkies()
                if not noSkyEnabled() then return end
                for _, child in ipairs(RbxService.Lighting:GetChildren()) do
                    if child:IsA("Sky") then child:Destroy() end
                end
            end
            
            local function ensureSky()
                if noSkyEnabled() then return end -- Don't ensure if we want it gone
                local sky = RbxService.Lighting:FindFirstChildOfClass("Sky")
                if not sky then
                    sky = Instance.new("Sky")
                    sky.Name = "WFYBSky"
                    sky.Parent = RbxService.Lighting
                end
            end
            
            local function tryRequire(moduleInstance)
                if typeof(moduleInstance) == "Instance" and moduleInstance:IsA("ModuleScript") then
                    local success, value = pcall(require, moduleInstance)
                    if success and type(value) == "table" then return value end
                end
            end
            
            local function takeLightingSnapshot()
                local lighting = RbxService.Lighting
                return {
                    Brightness = lighting.Brightness, Ambient = lighting.Ambient, ClockTime = lighting.ClockTime,
                    ExposureCompensation = lighting.ExposureCompensation, GlobalShadows = lighting.GlobalShadows,
                }
            end
            
            local function restoreLightingSnapshot(snapshot)
                if not snapshot then return end
                local lighting = RbxService.Lighting
                pcall(function()
                    lighting.Brightness = snapshot.Brightness
                    lighting.Ambient = snapshot.Ambient
                    lighting.ClockTime = snapshot.ClockTime
                    lighting.ExposureCompensation = snapshot.ExposureCompensation
                    lighting.GlobalShadows = snapshot.GlobalShadows
                end)
            end
            
            local function patchLightingProfileUtils(moduleTable)
                if type(moduleTable) ~= "table" or moduleTable.WFYBPatched then return end
                moduleTable.WFYBPatched = true
                local originalSetSkybox = moduleTable.setSkybox
                local originalApply = moduleTable.apply
                
                moduleTable.setSkybox = function(templates, profile)
                    if noSkyEnabled() then removeSkies(); return end
                    if type(originalSetSkybox) == "function" then
                        if pcall(originalSetSkybox, templates, profile) then return end
                    end
                    ensureSky()
                end
                
                moduleTable.apply = function(templates, profile)
                    if noSkyEnabled() then removeSkies(); return end
                    local snap = takeLightingSnapshot()
                    if type(originalApply) == "function" then
                        pcall(originalApply, templates, profile)
                    end
                    restoreLightingSnapshot(snap)
                    ensureSky()
                end
                
                getgenv().WFYB.LPUObject  = moduleTable
                getgenv().WFYB.LPUIsReady = true
            end
            
            local function patchLightingUpdater(moduleTable)
                if type(moduleTable) ~= "table" or moduleTable.WFYBPatched then return end
                moduleTable.WFYBPatched = true
                for key, value in pairs(moduleTable) do
                    if type(value) == "function" then
                        local originalFunction = value
                        moduleTable[key] = function(selfRef, ...)
                            local success, result = pcall(originalFunction, selfRef, ...)
                            if noSkyEnabled() then removeSkies() end
                            if not success and tostring(result):find("Skybox", 1, true) then
                                ensureSky()
                                return nil
                            end
                            return result
                        end
                    end
                end
            end
            
            do
                local folder =
                    RbxService.ReplicatedStorage:FindFirstChild("_replicationFolder")
                    or RbxService.ReplicatedStorage:WaitForChild("_replicationFolder", 10)
                if folder then
                    local lpu = folder:FindFirstChild("LightingProfileUtils", true)
                    if lpu then patchLightingProfileUtils(tryRequire(lpu)) end
                    local upd = folder:FindFirstChild("LightingUpdater", true)
                    if upd then patchLightingUpdater(tryRequire(upd)) end
                end
                local okNevermore, nevermore = pcall(require, RbxService.ReplicatedStorage:FindFirstChild("Nevermore"))
                if okNevermore and type(nevermore) == "function" then
                    local okLpu, lpuTable = pcall(nevermore, "LightingProfileUtils")
                    if okLpu and type(lpuTable) == "table" then patchLightingProfileUtils(lpuTable) end
                    local okUpd, updTable = pcall(nevermore, "LightingUpdater")
                    if okUpd and type(updTable) == "table" then patchLightingUpdater(updTable) end
                end
            end
            
            do
                local environment = (getrenv and getrenv()) or nil
                if environment and environment.require and not environment.WFYBRequireHook then
                    environment.WFYBRequireHook = true
                    local originalRequire = environment.require
                    cleanupMaid:GiveTask(function() 
                        if environment.require == originalRequire then return end
                        environment.require = originalRequire 
                        environment.WFYBRequireHook = false
                    end)
                    
                    environment.require = function(moduleInstance, ...)
                        local returned = originalRequire(moduleInstance, ...)
                        if typeof(moduleInstance) == "Instance" and moduleInstance:IsA("ModuleScript") and type(returned) == "table" then
                            if moduleInstance.Name == "LightingProfileUtils" then
                                patchLightingProfileUtils(returned)
                            elseif moduleInstance.Name == "LightingUpdater" then
                                patchLightingUpdater(returned)
                            end
                        end
                        return returned
                    end
                end
            end
            
            do
                local folder =
                    RbxService.ReplicatedStorage:FindFirstChild("_replicationFolder")
                    or RbxService.ReplicatedStorage:WaitForChild("_replicationFolder", 10)
                if folder then
                    cleanupMaid:GiveTask(folder.DescendantAdded:Connect(function(instance)
                        if not instance:IsA("ModuleScript") then return end
                        if instance.Name == "LightingProfileUtils" then
                            patchLightingProfileUtils(tryRequire(instance))
                        elseif instance.Name == "LightingUpdater" then
                            patchLightingUpdater(tryRequire(instance))
                        end
                    end))
                end
            end
            
            getgenv().WFYB.LPUReady = function()
                return getgenv().WFYB.LPUIsReady and type(getgenv().WFYB.LPUObject) == "table"
            end
            
            getgenv().WFYB.SetSkyboxSafe = function(...)
                if noSkyEnabled() then removeSkies(); return end
                if not getgenv().WFYB.LPUReady() then return end
                local lpu = getgenv().WFYB.LPUObject
                if not pcall(lpu.setSkybox, ...) then ensureSky() end
            end
            
            getgenv().WFYB.ApplyLightingSafe = function(templates, profile)
                if noSkyEnabled() then removeSkies(); return end
                if not getgenv().WFYB.LPUReady() then return end
                local snap = takeLightingSnapshot()
                local lpu = getgenv().WFYB.LPUObject
                pcall(lpu.apply, templates, profile)
                restoreLightingSnapshot(snap)
            end
        end)
        
        -- [4] UI CREATION
        -- No UI for this module
        
        -- [5] RETURN MODULE
        local function Stop()
            -- This cleans up the require hook and DescendantAdded connection
            Variables.Maids[ModuleName]:DoCleaning()
        end
        
        return { Name = ModuleName, Stop = Stop }
    end
end
