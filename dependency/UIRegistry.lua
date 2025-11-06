-- modules/UIRegistry.lua
do
    return function(UI)
        -- Shared deps (your Maid/Signal/Services)
        local RbxService = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
        local Maid       = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
        local Signal     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()

        local M = Maid.new()
        local G = (getgenv and getgenv()) or _G

        -- Make Obsidian registries globally visible for any script:
        -- (These are the canonical Obsidian registries documented at docs.mspaint.cc)
        -- Toggles: Library.Toggles; Options: Library.Options
        G.Toggles = UI.Toggles
        G.Options = UI.Options

        -- Global shared UI registry (dedup + lookup)
        local Shared = rawget(G, "UIShared")
        if not Shared then
            Shared = {
                Elements = {
                    toggle   = {},  -- key → toggle
                    slider   = {},  -- key → slider
                    dropdown = {},  -- key → dropdown
                    button   = {},  -- key → button
                    keybind  = {},  -- key → keybind
                },
                ButtonSignals = {}, -- key → Signal (aggregates funcs)
                -- Lookup helpers
                Find = function(self, kind, idOrText)
                    kind = string.lower(kind)
                    local by = self.Elements[kind]
                    if not by then return nil end
                    return by[idOrText]
                end,
            }
            rawset(G, "UIShared", Shared)
        end

        -- Utils
        local function shallow_clone(tbl)
            if type(tbl) ~= "table" then return tbl end
            local out = {}
            for k, v in pairs(tbl) do out[k] = v end
            return out
        end

        local function key_for(kind, id, cfg, textFallback)
            -- Prefer explicit ID; otherwise use visible Text as a best-effort global name
            if type(id) == "string" and id ~= "" then
                return id
            end
            local tf = textFallback or (type(cfg) == "table" and cfg.Text)
            if type(tf) == "string" and tf ~= "" then
                return ("__name__:" .. tf)
            end
            -- No ID, no Text → cannot dedup reliably
            return nil
        end

        -- Keybind shim: ensure Toggle:AddKeyPicker reuses by ID and attaches callbacks
        local function patch_keypicker_host(host, hostIdKey)
            if type(host) ~= "table" or type(host.AddKeyPicker) ~= "function" then
                return
            end
            local orig = host.AddKeyPicker
            host.AddKeyPicker = function(self, id, cfg)
                cfg = cfg or {}
                local key = key_for("keybind", id, cfg, cfg.Text)
                if key and Shared.Elements.keybind[key] then
                    local existing = Shared.Elements.keybind[key]
                    -- Attach any new handlers from this call
                    if type(cfg.Callback) == "function" and existing.OnClick then
                        local ok, conn = pcall(function() return existing:OnClick(cfg.Callback) end)
                        if ok and conn then M:GiveTask(conn) end
                    end
                    if type(cfg.ChangedCallback) == "function" and existing.OnChanged then
                        local ok, conn = pcall(function() return existing:OnChanged(cfg.ChangedCallback) end)
                        if ok and conn then M:GiveTask(conn) end
                    end
                    return existing
                end
                local kb = orig(self, id, cfg)
                if key then
                    Shared.Elements.keybind[key] = kb
                    M:GiveTask(function()
                        if Shared.Elements.keybind[key] == kb then
                            Shared.Elements.keybind[key] = nil
                        end
                    end)
                end
                return kb
            end
            -- restore on cleanup
            M:GiveTask(function() host.AddKeyPicker = orig end)
        end

        -- Groupbox wrappers ----------------------------------------------------
        local function patch_groupbox(box)
            if type(box) ~= "table" then return end

            -- Toggle
            if type(box.AddToggle) == "function" then
                local orig = box.AddToggle
                box.AddToggle = function(self, id, cfg)
                    cfg = cfg or {}
                    local key = key_for("toggle", id, cfg, cfg.Text)
                    if key and Shared.Elements.toggle[key] then
                        local existing = Shared.Elements.toggle[key]
                        -- If a Callback was supplied on a subsequent call, attach it
                        if type(cfg.Callback) == "function" and existing.OnChanged then
                            local ok, conn = pcall(function() return existing:OnChanged(cfg.Callback) end)
                            if ok and conn then M:GiveTask(conn) end
                        end
                        return existing
                    end
                    local el = orig(self, id, cfg)
                    if key then
                        Shared.Elements.toggle[key] = el
                        M:GiveTask(function()
                            if Shared.Elements.toggle[key] == el then
                                Shared.Elements.toggle[key] = nil
                            end
                        end)
                    end
                    -- Allow dedup of future keybinds added to this toggle
                    patch_keypicker_host(el)
                    return el
                end
                M:GiveTask(function() box.AddToggle = orig end)
            end

            -- Slider
            if type(box.AddSlider) == "function" then
                local orig = box.AddSlider
                box.AddSlider = function(self, id, cfg)
                    cfg = cfg or {}
                    local key = key_for("slider", id, cfg, cfg.Text)
                    if key and Shared.Elements.slider[key] then
                        local existing = Shared.Elements.slider[key]
                        if type(cfg.Callback) == "function" and existing.OnChanged then
                            local ok, conn = pcall(function() return existing:OnChanged(cfg.Callback) end)
                            if ok and conn then M:GiveTask(conn) end
                        end
                        return existing
                    end
                    local el = orig(self, id, cfg)
                    if key then
                        Shared.Elements.slider[key] = el
                        M:GiveTask(function()
                            if Shared.Elements.slider[key] == el then
                                Shared.Elements.slider[key] = nil
                            end
                        end)
                    end
                    return el
                end
                M:GiveTask(function() box.AddSlider = orig end)
            end

            -- Dropdown
            if type(box.AddDropdown) == "function" then
                local orig = box.AddDropdown
                box.AddDropdown = function(self, id, cfg)
                    cfg = cfg or {}
                    local key = key_for("dropdown", id, cfg, cfg.Text)
                    if key and Shared.Elements.dropdown[key] then
                        local existing = Shared.Elements.dropdown[key]
                        if type(cfg.Callback) == "function" and existing.OnChanged then
                            local ok, conn = pcall(function() return existing:OnChanged(cfg.Callback) end)
                            if ok and conn then M:GiveTask(conn) end
                        end
                        return existing
                    end
                    local el = orig(self, id, cfg)
                    if key then
                        Shared.Elements.dropdown[key] = el
                        M:GiveTask(function()
                            if Shared.Elements.dropdown[key] == el then
                                Shared.Elements.dropdown[key] = nil
                            end
                        end)
                    end
                    return el
                end
                M:GiveTask(function() box.AddDropdown = orig end)
            end

            -- Button (special: no ID; dedupe by Text and aggregate functions)
            if type(box.AddButton) == "function" then
                local orig = box.AddButton
                box.AddButton = function(self, arg1, arg2)
                    local cfg, text, func
                    if type(arg1) == "table" then
                        cfg = shallow_clone(arg1)
                        text = cfg.Text
                        func = cfg.Func
                    else
                        text = arg1
                        func = arg2
                        cfg = nil
                    end
                    local key = key_for("button", nil, cfg, text)
                    if key and Shared.Elements.button[key] then
                        local existing = Shared.Elements.button[key]
                        -- attach this new function to aggregator, if provided
                        if type(func) == "function" then
                            local sig = Shared.ButtonSignals[key]
                            if sig then
                                local ok, conn = pcall(function() return sig:Connect(func) end)
                                if ok and conn then M:GiveTask(conn) end
                            end
                        end
                        return existing
                    end

                    -- First creation → install aggregator
                    local sig = Signal.new()
                    Shared.ButtonSignals[key or ("__btn__:" .. tostring(existing))] = sig
                    M:GiveTask(function()
                        sig:Destroy()
                        Shared.ButtonSignals[key or ("__btn__:" .. tostring(existing))] = nil
                    end)

                    if type(func) == "function" then
                        local ok, conn = pcall(function() return sig:Connect(func) end)
                        if ok and conn then M:GiveTask(conn) end
                    end

                    local function aggregator()
                        -- Fire all registered handlers safely
                        local ok, err = pcall(function() sig:Fire() end)
                        if not ok then warn("[UIShared] Button '" .. tostring(text) .. "' handler error: " .. tostring(err)) end
                    end

                    local el
                    if cfg then
                        cfg.Func = aggregator
                        el = orig(self, cfg)
                    else
                        el = orig(self, text, aggregator)
                    end

                    if key then
                        Shared.Elements.button[key] = el
                        M:GiveTask(function()
                            if Shared.Elements.button[key] == el then
                                Shared.Elements.button[key] = nil
                            end
                        end)
                    end

                    return el
                end
                M:GiveTask(function() box.AddButton = orig end)
            end
        end

        -- Patch all tabs so every *newly created* groupbox gets our wrappers.
        -- (Obsidian: groupboxes are created via Tab:AddLeftGroupbox / AddRightGroupbox.) :contentReference[oaicite:3]{index=3}
        local function patch_tab(tab)
            if type(tab) ~= "table" then return end

            if type(tab.AddLeftGroupbox) == "function" then
                local orig = tab.AddLeftGroupbox
                tab.AddLeftGroupbox = function(self, ...)
                    local box = orig(self, ...)
                    patch_groupbox(box)
                    return box
                end
                M:GiveTask(function() tab.AddLeftGroupbox = orig end)
            end

            if type(tab.AddRightGroupbox) == "function" then
                local orig = tab.AddRightGroupbox
                tab.AddRightGroupbox = function(self, ...)
                    local box = orig(self, ...)
                    patch_groupbox(box)
                    return box
                end
                M:GiveTask(function() tab.AddRightGroupbox = orig end)
            end
        end

        -- Install on all current tabs
        for _, tab in pairs(UI.Tabs or {}) do
            patch_tab(tab)
        end

        -- Module API for loader’s teardown
        local function Stop()
            M:DoCleaning()
            -- Note: we deliberately do not nil out G.UIShared/Toggles/Options here since
            -- Library:Unload() will handle UI teardown; Shared tables hold weak-ish refs through cleanup above.
        end

        return { Name = "UIRegistry", Stop = Stop }
    end
end
