-- dependency/UIRegistry.lua
do
  return function(UI)
    -- Shared deps
    local Services   = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
    local Maid       = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
    local Signal     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()

    local M = Maid.new()
    local G = (getgenv and getgenv()) or _G

    -- Expose Obsidian registries so any script can access existing elements:
    -- (From docs: Toggles & Options are the canonical registries.) :contentReference[oaicite:2]{index=2}
    G.Toggles = UI.Toggles
    G.Options = UI.Options
    -- Optional convenience:
    G.Tabs    = UI.Tabs
    G.Library = UI.Library

    -- Global registry for all elements
    local Shared = rawget(G, "UIShared")
    if not Shared then
      Shared = {
        Elements = {
          -- Core inputs
          label       = {}, -- id or "__name__:Text" → Label
          button      = {}, -- "__name__:Text" → Button (main) ; sub-buttons patched on host
          toggle      = {}, -- id → Toggle
          checkbox    = {}, -- id → Checkbox
          input       = {}, -- id → Input
          slider      = {}, -- id → Slider
          dropdown    = {}, -- id → Dropdown
          keybind     = {}, -- id → Keybind (from Toggle/Label hosts)
          colorpicker = {}, -- id → ColorPicker (from Toggle/Label hosts)
          divider     = {}, -- guid → Divider (visual only)
          viewport    = {}, -- id → Viewport
          image       = {}, -- id → Image
          video       = {}, -- id → Video
          uipass      = {}, -- id → UIPassthrough
          -- Containers
          groupbox    = {}, -- "__name__:Title" → Groupbox
          tabbox      = {}, -- "__name__:Title" → Tabbox
          tab         = {}, -- "__name__:Name"  → Tab
        },
        ButtonSignals = {}, -- "__name__:Text" → Signal (aggregates multiple funcs)
        Find = function(self, kind, key)
          kind = string.lower(kind)
          local bucket = self.Elements[kind]
          return bucket and bucket[key] or nil
        end,
      }
      rawset(G, "UIShared", Shared)
    end

    -- Utils
    local function clone(tbl)
      if type(tbl) ~= "table" then return tbl end
      local t = {}; for k, v in pairs(tbl) do t[k] = v end; return t
    end

    local function id_or_text_key(kind, id, cfg, textFallback)
      -- For ID-based elements, use the ID when provided.
      if type(id) == "string" and id ~= "" then return id end
      -- For text-based elements (Buttons / optional Labels), use a stable text key.
      local tf = textFallback or (type(cfg) == "table" and cfg.Text)
      if type(tf) == "string" and tf ~= "" then return "__name__:" .. tf end
      return nil
    end

    local function remember(kind, key, ref)
      if not key then return end
      Shared.Elements[kind][key] = ref
      M:GiveTask(function()
        if Shared.Elements[kind][key] == ref then
          Shared.Elements[kind][key] = nil
        end
      end)
    end

    local function attach_OnChanged(ref, fn) -- for Toggle/Checkbox/Input/Slider/Dropdown/ColorPicker
      if type(fn) ~= "function" or type(ref) ~= "table" then return end
      if type(ref.OnChanged) == "function" then
        local ok, conn = pcall(function() return ref:OnChanged(fn) end)
        if ok and conn then M:GiveTask(conn) end
      end
    end

    -- Host patchers for nested elements on Labels / Toggles -------------------
    local function patch_keypicker_host(host) -- Keybinds hang off Toggle/Label :contentReference[oaicite:3]{index=3}
      if type(host) ~= "table" or type(host.AddKeyPicker) ~= "function" then return end
      local orig = host.AddKeyPicker
      host.AddKeyPicker = function(self, id, cfg)
        cfg = cfg or {}
        local key = id_or_text_key("keybind", id, cfg, cfg.Text)
        if key and Shared.Elements.keybind[key] then
          local existing = Shared.Elements.keybind[key]
          -- attach any new handlers from this call
          if type(cfg.Callback) == "function" and existing.OnClick then
            local ok1, conn1 = pcall(function() return existing:OnClick(cfg.Callback) end)
            if ok1 and conn1 then M:GiveTask(conn1) end
          end
          if type(cfg.ChangedCallback) == "function" and existing.OnChanged then
            local ok2, conn2 = pcall(function() return existing:OnChanged(cfg.ChangedCallback) end)
            if ok2 and conn2 then M:GiveTask(conn2) end
          end
          if type(cfg.Clicked) == "function" and existing.OnClick then
            local ok3, conn3 = pcall(function() return existing:OnClick(cfg.Clicked) end)
            if ok3 and conn3 then M:GiveTask(conn3) end
          end
          return existing
        end
        local kb = orig(self, id, cfg)
        if key then remember("keybind", key, kb) end
        return kb
      end
      M:GiveTask(function() host.AddKeyPicker = orig end)
    end

    local function patch_colorpicker_host(host) -- ColorPickers on Toggle/Label :contentReference[oaicite:4]{index=4}
      if type(host) ~= "table" or type(host.AddColorPicker) ~= "function" then return end
      local orig = host.AddColorPicker
      host.AddColorPicker = function(self, id, cfg)
        cfg = cfg or {}
        local key = id_or_text_key("colorpicker", id, cfg, cfg.Title)
        if key and Shared.Elements.colorpicker[key] then
          local existing = Shared.Elements.colorpicker[key]
          attach_OnChanged(existing, cfg.Callback or cfg.Changed)
          return existing
        end
        local cp = orig(self, id, cfg)
        if key then remember("colorpicker", key, cp) end
        return cp
      end
      M:GiveTask(function() host.AddColorPicker = orig end)
    end

    local function patch_button_host(host) -- sub-buttons on Button :contentReference[oaicite:5]{index=5}
      if type(host) ~= "table" or type(host.AddButton) ~= "function" then return end
      local orig = host.AddButton
      host.AddButton = function(self, arg1, arg2)
        local cfg, text, func
        if type(arg1) == "table" then
          cfg = clone(arg1); text = cfg.Text; func = cfg.Func
        else
          text = arg1; func = arg2
        end
        local key = id_or_text_key("button", nil, cfg, text) -- sub-buttons dedupe by Text
        if key and Shared.Elements.button[key] then
          if type(func) == "function" then
            local sig = Shared.ButtonSignals[key]
            if sig then
              local ok, conn = pcall(function() return sig:Connect(func) end)
              if ok and conn then M:GiveTask(conn) end
            end
          end
          return Shared.Elements.button[key]
        end

        local sig = Signal.new()
        Shared.ButtonSignals[key or ("__btn__:" .. tostring(self))] = sig
        M:GiveTask(function()
          sig:Destroy()
          Shared.ButtonSignals[key or ("__btn__:" .. tostring(self))] = nil
        end)
        if type(func) == "function" then
          local ok, conn = pcall(function() return sig:Connect(func) end)
          if ok and conn then M:GiveTask(conn) end
        end

        local function aggregator() local ok, err = pcall(function() sig:Fire() end); if not ok then warn(err) end end
        local el
        if cfg then cfg.Func = aggregator; el = orig(self, cfg) else el = orig(self, text, aggregator) end
        if key then remember("button", key, el) end
        return el
      end
      M:GiveTask(function() host.AddButton = orig end)
    end

    -- Groupbox patcher: wrap ALL adders per docs ------------------------------
    local function patch_groupbox(box)
      if type(box) ~= "table" then return end

      -- Labels (ID optional, or positional text) :contentReference[oaicite:6]{index=6}
      if type(box.AddLabel) == "function" then
        local orig = box.AddLabel
        box.AddLabel = function(self, a1, a2)
          local id, cfg, text
          if type(a1) == "string" and type(a2) == "table" then
            id, cfg, text = a1, a2, a2.Text
          elseif type(a1) == "table" then
            id, cfg, text = nil, a1, a1.Text
          else
            id, cfg, text = nil, { Text = a1, DoesWrap = a2 }, a1
          end
          local key = id_or_text_key("label", id, cfg, text)
          if key and Shared.Elements.label[key] then
            return Shared.Elements.label[key]
          end
          local el = orig(self, a1, a2)
          if key then remember("label", key, el) end
          patch_keypicker_host(el)     -- Labels can host Keybinds
          patch_colorpicker_host(el)   -- Labels can host ColorPickers
          return el
        end
        M:GiveTask(function() box.AddLabel = orig end)
      end

      -- Buttons (Text only) :contentReference[oaicite:7]{index=7}
      if type(box.AddButton) == "function" then
        local orig = box.AddButton
        box.AddButton = function(self, arg1, arg2)
          local cfg, text, func
          if type(arg1) == "table" then
            cfg = clone(arg1); text = cfg.Text; func = cfg.Func
          else
            text = arg1; func = arg2
          end
          local key = id_or_text_key("button", nil, cfg, text)
          if key and Shared.Elements.button[key] then
            -- attach additional handler
            if type(func) == "function" then
              local sig = Shared.ButtonSignals[key]
              if sig then
                local ok, conn = pcall(function() return sig:Connect(func) end)
                if ok and conn then M:GiveTask(conn) end
              end
            end
            return Shared.Elements.button[key]
          end

          -- First creator → install aggregator
          local sig = Signal.new()
          Shared.ButtonSignals[key or ("__btn__:" .. tostring(self))] = sig
          M:GiveTask(function()
            sig:Destroy()
            Shared.ButtonSignals[key or ("__btn__:" .. tostring(self))] = nil
          end)
          if type(func) == "function" then
            local ok, conn = pcall(function() return sig:Connect(func) end)
            if ok and conn then M:GiveTask(conn) end
          end
          local function aggregator() local ok, err = pcall(function() sig:Fire() end); if not ok then warn(err) end end
          local el
          if cfg then cfg.Func = aggregator; el = orig(self, cfg) else el = orig(self, text, aggregator) end
          if key then remember("button", key, el) end
          patch_button_host(el) -- enable sub-button dedupe
          return el
        end
        M:GiveTask(function() box.AddButton = orig end)
      end

      -- Toggles (ID) :contentReference[oaicite:8]{index=8}
      if type(box.AddToggle) == "function" then
        local orig = box.AddToggle
        box.AddToggle = function(self, id, cfg)
          cfg = cfg or {}
          local key = id_or_text_key("toggle", id, cfg, cfg.Text)
          if key and Shared.Elements.toggle[key] then
            local existing = Shared.Elements.toggle[key]
            attach_OnChanged(existing, cfg.Callback)
            return existing
          end
          local el = orig(self, id, cfg)
          if key then remember("toggle", key, el) end
          -- Hosts
          patch_keypicker_host(el)
          patch_colorpicker_host(el)
          return el
        end
        M:GiveTask(function() box.AddToggle = orig end)
      end

      -- Checkboxes (ID) :contentReference[oaicite:9]{index=9}
      if type(box.AddCheckbox) == "function" then
        local orig = box.AddCheckbox
        box.AddCheckbox = function(self, id, cfg)
          cfg = cfg or {}
          local key = id_or_text_key("checkbox", id, cfg, cfg.Text)
          if key and Shared.Elements.checkbox[key] then
            local existing = Shared.Elements.checkbox[key]
            attach_OnChanged(existing, cfg.Callback)
            return existing
          end
          local el = orig(self, id, cfg)
          if key then remember("checkbox", key, el) end
          -- Hosts
          patch_keypicker_host(el)
          patch_colorpicker_host(el)
          return el
        end
        M:GiveTask(function() box.AddCheckbox = orig end)
      end

      -- Inputs (ID) :contentReference[oaicite:10]{index=10}
      if type(box.AddInput) == "function" then
        local orig = box.AddInput
        box.AddInput = function(self, id, cfg)
          cfg = cfg or {}
          local key = id_or_text_key("input", id, cfg, cfg.Text)
          if key and Shared.Elements.input[key] then
            attach_OnChanged(Shared.Elements.input[key], cfg.Callback)
            return Shared.Elements.input[key]
          end
          local el = orig(self, id, cfg)
          if key then remember("input", key, el) end
          return el
        end
        M:GiveTask(function() box.AddInput = orig end)
      end

      -- Sliders (ID) :contentReference[oaicite:11]{index=11}
      if type(box.AddSlider) == "function" then
        local orig = box.AddSlider
        box.AddSlider = function(self, id, cfg)
          cfg = cfg or {}
          local key = id_or_text_key("slider", id, cfg, cfg.Text)
          if key and Shared.Elements.slider[key] then
            attach_OnChanged(Shared.Elements.slider[key], cfg.Callback)
            return Shared.Elements.slider[key]
          end
          local el = orig(self, id, cfg)
          if key then remember("slider", key, el) end
          return el
        end
        M:GiveTask(function() box.AddSlider = orig end)
      end

      -- Dropdowns (ID) :contentReference[oaicite:12]{index=12}
      if type(box.AddDropdown) == "function" then
        local orig = box.AddDropdown
        box.AddDropdown = function(self, id, cfg)
          cfg = cfg or {}
          local key = id_or_text_key("dropdown", id, cfg, cfg.Text)
          if key and Shared.Elements.dropdown[key] then
            attach_OnChanged(Shared.Elements.dropdown[key], cfg.Callback)
            return Shared.Elements.dropdown[key]
          end
          local el = orig(self, id, cfg)
          if key then remember("dropdown", key, el) end
          return el
        end
        M:GiveTask(function() box.AddDropdown = orig end)
      end

      -- Dividers (no args; visual only) :contentReference[oaicite:13]{index=13}
      if type(box.AddDivider) == "function" then
        local orig = box.AddDivider
        box.AddDivider = function(self, ...)
          local el = orig(self, ...)
          local guid = Services.HttpService and Services.HttpService:GenerateGUID(false) or tostring(el)
          remember("divider", guid, el)
          return el
        end
        M:GiveTask(function() box.AddDivider = orig end)
      end

      -- Viewports (ID) :contentReference[oaicite:14]{index=14}
      if type(box.AddViewport) == "function" then
        local orig = box.AddViewport
        box.AddViewport = function(self, id, cfg)
          cfg = cfg or {}
          local key = id_or_text_key("viewport", id, cfg, cfg.Title)
          if key and Shared.Elements.viewport[key] then
            return Shared.Elements.viewport[key]
          end
          local el = orig(self, id, cfg)
          if key then remember("viewport", key, el) end
          return el
        end
        M:GiveTask(function() box.AddViewport = orig end)
      end

      -- Images (ID) :contentReference[oaicite:15]{index=15}
      if type(box.AddImage) == "function" then
        local orig = box.AddImage
        box.AddImage = function(self, id, cfg)
          cfg = cfg or {}
          local key = id_or_text_key("image", id, cfg, cfg.Text)
          if key and Shared.Elements.image[key] then
            return Shared.Elements.image[key]
          end
          local el = orig(self, id, cfg)
          if key then remember("image", key, el) end
          return el
        end
        M:GiveTask(function() box.AddImage = orig end)
      end

      -- Videos (ID) :contentReference[oaicite:16]{index=16}
      if type(box.AddVideo) == "function" then
        local orig = box.AddVideo
        box.AddVideo = function(self, id, cfg)
          cfg = cfg or {}
          local key = id_or_text_key("video", id, cfg, cfg.Text)
          if key and Shared.Elements.video[key] then
            return Shared.Elements.video[key]
          end
          local el = orig(self, id, cfg)
          if key then remember("video", key, el) end
          return el
        end
        M:GiveTask(function() box.AddVideo = orig end)
      end

      -- UI Passthrough (ID) :contentReference[oaicite:17]{index=17}
      if type(box.AddUIPassthrough) == "function" then
        local orig = box.AddUIPassthrough
        box.AddUIPassthrough = function(self, id, cfg)
          cfg = cfg or {}
          local key = id_or_text_key("uipass", id, cfg, cfg.Title)
          if key and Shared.Elements.uipass[key] then
            return Shared.Elements.uipass[key]
          end
          local el = orig(self, id, cfg)
          if key then remember("uipass", key, el) end
          return el
        end
        M:GiveTask(function() box.AddUIPassthrough = orig end)
      end

      -- Record the groupbox by title to help cross‑script lookups :contentReference[oaicite:18]{index=18}
      if type(box.Title) == "string" and box.Title ~= "" then
        remember("groupbox", "__name__:" .. box.Title, box)
      end
    end

    -- Tabbox patcher: ensure Tabbox:AddTab(...) returns a patched groupbox :contentReference[oaicite:19]{index=19}
    local function patch_tabbox(tb)
      if type(tb) ~= "table" then return end
      if type(tb.AddTab) == "function" then
        local orig = tb.AddTab
        tb.AddTab = function(self, title)
          local gb = orig(self, title)
          patch_groupbox(gb)
          if type(title) == "string" and title ~= "" then
            remember("groupbox", "__name__:" .. title, gb)
          end
          return gb
        end
        M:GiveTask(function() tb.AddTab = orig end)
      end
      if type(tb.Title) == "string" and tb.Title ~= "" then
        remember("tabbox", "__name__:" .. tb.Title, tb)
      end
    end

    -- Tab patcher: when you add groupboxes/tabboxes on a Tab, patch them. :contentReference[oaicite:20]{index=20}
    local function patch_tab(tab, name)
      if type(tab) ~= "table" then return end

      if type(tab.AddLeftGroupbox) == "function" then
        local orig = tab.AddLeftGroupbox
        tab.AddLeftGroupbox = function(self, ...)
          local gb = orig(self, ...)
          patch_groupbox(gb)
          return gb
        end
        M:GiveTask(function() tab.AddLeftGroupbox = orig end)
      end

      if type(tab.AddRightGroupbox) == "function" then
        local orig = tab.AddRightGroupbox
        tab.AddRightGroupbox = function(self, ...)
          local gb = orig(self, ...)
          patch_groupbox(gb)
          return gb
        end
        M:GiveTask(function() tab.AddRightGroupbox = orig end)
      end

      if type(tab.AddLeftTabbox) == "function" then
        local orig = tab.AddLeftTabbox
        tab.AddLeftTabbox = function(self, ...)
          local tb = orig(self, ...)
          patch_tabbox(tb)
          return tb
        end
        M:GiveTask(function() tab.AddLeftTabbox = orig end)
      end

      if type(tab.AddRightTabbox) == "function" then
        local orig = tab.AddRightTabbox
        tab.AddRightTabbox = function(self, ...)
          local tb = orig(self, ...)
          patch_tabbox(tb)
          return tb
        end
        M:GiveTask(function() tab.AddRightTabbox = orig end)
      end

      if type(name) == "string" and name ~= "" then
        remember("tab", "__name__:" .. name, tab)
      end
    end

    -- Patch all current tabs from the loader’s UI context
    for name, tab in pairs(UI.Tabs or {}) do
      patch_tab(tab, name)
    end

    -- Also patch any groupboxes already created up‑front (rare) by scanning tabs
    -- (Most code creates groupboxes after tabs; this is just defensive.)

    -- Public stop (unload) — everything is under Maid
    local function Stop()
      M:DoCleaning()
      -- Keep G.UIShared alive until Library:Unload() tears down instances
      -- so external scripts can still query while unloading.
    end

    return { Name = "UIRegistry", Stop = Stop }
  end
end
