-- modules/wfyb/blockpopup.lua
do
    return function(ui)
        local rbxservice = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local maidclass  = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()

        local state = {
            maid = maidclass.new(),
            run_flag = false,
            nevermore = nil,
            patched = false,
            patched_targets = {}, -- { {module=, key=, original=}... }
        }

        local function ensure_nevermore()
            if not state.nevermore then
                state.nevermore = require(rbxservice.ReplicatedStorage:WaitForChild("Nevermore"))
            end
        end

        local function try_load(name)
            ensure_nevermore()
            local ok, mod = pcall(function() return state.nevermore(name) end)
            if ok and mod then return mod end
            return nil
        end

        local function patch_method(mod, key)
            if not (mod and type(mod) == "table") then return false end
            local original = mod[key]
            if type(original) ~= "function" then return false end
            table.insert(state.patched_targets, { module = mod, key = key, original = original })
            mod[key] = function() end
            state.maid:GiveTask(function()
                if mod and mod[key] ~= nil then mod[key] = original end
            end)
            return true
        end

        local function apply_patches_once()
            if state.patched then return end

            local exp_notifier   = try_load("ExperienceChangeNotifier")
            if exp_notifier   then patch_method(exp_notifier, "_showExperienceGain") end

            local level_notifier = try_load("LevelUpNotifier")
            if level_notifier then patch_method(level_notifier, "_showLevelUpNotification") end

            local money_notifier = try_load("MoneyChangeNotifier")
            if money_notifier then
                patch_method(money_notifier, "_showMoneyGain")
                patch_method(money_notifier, "_showMoneyLoss")
            end

            local level_bar = try_load("LevelBar")
            if level_bar then
                patch_method(level_bar, "_updateValue")
                patch_method(level_bar, "_handleExperienceValueChanged")
                patch_method(level_bar, "_animateUpToLevel")
                patch_method(level_bar, "_animateLevelsImprove")
            end

            local stat_row = try_load("StatRow")
            if stat_row then
                patch_method(stat_row, "_startUpdate")
                patch_method(stat_row, "_update")
            end

            state.patched = true
            state.maid:GiveTask(function()
                state.patched = false
                state.patched_targets = {}
            end)
        end

        local function start()
            if state.run_flag then return end
            state.run_flag = true
            apply_patches_once()
            state.maid:GiveTask(function() state.run_flag = false end)
        end

        local function stop()
            state.run_flag = false
            for i = #state.patched_targets, 1, -1 do
                local entry = state.patched_targets[i]
                if entry and entry.module and entry.key and entry.original then
                    pcall(function() entry.module[entry.key] = entry.original end)
                end
                state.patched_targets[i] = nil
            end
            state.patched = false
            state.maid:DoCleaning()
        end

        local group = ui.Tabs.EXP:AddLeftGroupbox("EXP Farm", "arrow-right-left")
        group:AddToggle("AutoPopupToggle", {
            Text = "Remove Popup",
            Tooltip = "Turn Feature [ON/OFF].",
            Default = false,
        })
        ui.Toggles.AutoPopupToggle:OnChanged(function(v)
            if v then start() else stop() end
        end)

        return { Name = "BlockPopup", Stop = stop }
    end
end
