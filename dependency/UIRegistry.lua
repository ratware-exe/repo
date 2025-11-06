-- dependency/UIRegistry.lua
do
  return function(UI)
    -- Shared deps (your system)
    local Services   = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
    local Maid       = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
    local Signal     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()

    local M = Maid.new()
    local G = (getgenv and getgenv()) or _G

    -- Expose Obsidian registries for this run (session-local convenience)
    -- Obsidian docs: Toggles/Options are the canonical registries. :contentReference[oaicite:1]{index=1}
    G.Toggles = UI.Toggles
    G.Options = UI.Options
    G.Tabs    = UI.Tabs
    G.Library = UI.Library

    ---------------------------------------------------------------------------
    -- Multi-session manager
    ---------------------------------------------------------------------------
    local Manager = rawget(G, "UISharedManager")
    if not Manager then
      Manager = { Sessions = {}, Active = nil }
      rawset(G, "UISharedManager", Manager)
    end

    local function new_guid()
      local guid
      if Services and Services.HttpService then
        pcall(function() guid = Services.HttpService:GenerateGUID(false) end)
      end
      return guid or ("sess_" .. tostring(math.random()) .. "_" .. tostring(os.clock()))
    end

    -- Backward-compat upgrade: if an old single-session G.UIShared exists but no manager session,
    -- we park it inside Manager.Sessions["legacy"] so older references keep working.
    if rawget(G, "UIShared") and not Manager.__upgraded then
      local legacy = G.UIShared
      if type(legacy) == "table" and not Manager.Sessions.legacy then
        Manager.Sessions.legacy = legacy
      end
      Manager.__upgraded = true
    end

    local SessionId = new_guid()

    -- Per-session state (dedupe per run)
    local function new_session(id)
      local s = {
        Id = id,
        Elements = {
          label       = {}, -- id or "__name__:Text" → Label
          button      = {}, -- "__name__:Text" → Button (+ sub-buttons)
          toggle      = {}, -- id → Toggle
          checkbox    = {}, -- id → Checkbox
          input       = {}, -- id → Input
          slider      = {}, -- id → Slider
          dropdown    = {}, -- id → Dropdown
          keybind     = {}, -- id → Keybind (off Toggle/Label hosts)
          colorpicker = {}, -- id → ColorPicker (off Toggle/Label hosts)
          divider     = {}, -- guid → Divider
          viewport    = {}, -- id → Viewport
          image       = {}, -- id → Image
          video       = {}, -- id → Video
          uipass      = {}, -- id → UIPassthrough
          groupbox    = {}, -- "__name__:Title" → Groupbox
          tabbox      = {}, -- "__name__:Title" → Tabbox
          tab         = {}, -- "__name__:Name"  → Tab
        },
        ButtonSignals = {}, -- "__name__:Text" → Signal aggregator
        _patched = {
          tabs = setmetatable({}, { __mode = "k" }),
          groupboxes = setmetatable({}, { __mode = "k" }),
          hosts = setmetatable({}, { __mode = "k" }), -- per-host method sentinels
        },
        Find = function(self, kind, key)
          kind = string.lower(kind)
          local b = self.Elements[kind]
          return b and b[key] or nil
        end,
      }
      return s
    end

    local Shared = new_session(SessionId)
    Manager.Sessions[SessionId] = Shared
    Manager.Active = SessionId
    G.UIShared = Shared            -- <-- Active session pointer for this run
    G.UISharedSessionId = SessionId

    ---------------------------------------------------------------------------
    -- Utilities
    ---------------------------------------------------------------------------
    local function clone(tbl)
      if type(tbl) ~= "table" then return tbl end
      local t = {}; for k, v in pairs(tbl) do t[k] = v end; return t
    end

    local function id_or_text_key(kind, id, cfg, textFallback)
      if type(id) == "string" and id ~= "" then return id end
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

    local function attach_OnChanged(ref, fn) -- Toggle/Checkbox/Input/Slider/Dropdown/ColorPicker
      if type(fn) ~= "function" or type(ref) ~= "table" then return end
      if type(ref.OnChanged) == "function" then
        local ok, conn = pcall(function() return ref:OnChanged(fn) end)
        if ok and conn then M:GiveTask(conn) end
      end
    end

    local function was_host_method_patched(host, method)
      local map = Shared._patched.hosts[host]
      if map and map[method] then return true end
      map = map or {}; map[method] = true
      Shared._patched.hosts[host] = map
      return false
    end

    ---------------------------------------------------------------------------
    -- Host patchers (Label/Toggle hosts for Keybinds & ColorPickers)
    ---------------------------------------------------------------------------
    -- Keybinds (host:AddKeyPicker) — docs: adders & handlers (OnClick/OnChanged). :contentReference[oaicite:2]{index=2}
    local function patch_keypicker_host(host)
      if type(host) ~= "table" or type(host.AddKeyPicker) ~= "function" or was_host_method_patched(host, "AddKeyPicker") then
        return
      end
      local orig = host.AddKeyPicker
      host.AddKeyPicker = function(self, id, cfg)
        cfg = cfg or {}
        local key = id_or_text_key("keybind", id, cfg, cfg.Text)
        if key and Shared.Elements.keybind[key] then
          local existing = Shared.Elements.keybind[key]
          if type(cfg.Callback) == "function" and existing.OnClick then
            local ok1, c1 = pcall(function() return existing:OnClick(cfg.Callback) end)
            if ok1 and c1 then M:GiveTask(c1) end
          end
          if type(cfg.ChangedCallback) == "function" and existing.OnChanged then
            local ok2, c2 = pcall(function() return existing:OnChanged(cfg.ChangedCallback) end)
            if ok2 and c2 then M:GiveTask(c2) end
          end
          if type(cfg.Clicked) == "function" and existing.OnClick then
            local ok3, c3 = pcall(function() return existing:OnClick(cfg.Clicked) end)
            if ok3 and c3 then M:GiveTask(c3) end
          end
          return existing
        end
        local kb = orig(self, id, cfg)
        if key then remember("keybind", key, kb) end
        return kb
      end
      M:GiveTask(function() host.AddKeyPicker = orig end)
    end

    -- ColorPickers (host:AddColorPicker) — docs: adders + OnChanged. :contentReference[oaicite:3]{index=3}
    local function patch_colorpicker_host(host)
      if type(host) ~= "table" or type(host.AddColorPicker) ~= "function" or was_host_method_patched(host, "AddColorPicker") then
        return
      end
      local orig = host.AddColorPicker
      host.AddColorPicker = function(self, id, cfg)
        cfg = cfg or {}
        local key = id_or_text_key("colorpicker", id, cfg, cfg.Title)
        if key and Shared.Elements.colorpicker[key] then
          attach_OnChanged(Shared.Elements.colorpicker[key], cfg.Callback or cfg.Changed)
          return Shared.Elements.colorpicker[key]
        end
        local cp = orig(self, id, cfg)
        if key then remember("colorpicker", key, cp) end
        return cp
      end
      M:GiveTask(function() host.AddColorPicker = orig end)
    end

    -- Sub-buttons (Button:AddButton) — docs: nested buttons. :contentReference[oaicite:4]{index=4}
    local function patch_button_host(host)
      if type(host) ~= "table" or type(host.AddButton) ~= "function" or was_host_method_patched(host, "AddButton") then
        return
      end
      local orig = host.AddButton
      host.AddButton = function(self, arg1, arg2)
        local cfg, text, func
        if type(arg1) == "table" then
          cfg = clone(arg1); text, func = cfg.Text, cfg.Func
        else
          text, func = arg1, arg2
        end
        local key = id_or_text_key("button", nil, cfg, text) -- dedupe by text
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

    ---------------------------------------------------------------------------
    -- Groupbox patcher: wrap ALL adders per docs
    ---------------------------------------------------------------------------
    local function already_patched_groupbox(box)
      if Shared._patched.groupboxes[box] then return true end
      Shared._patched.groupboxes[box] = true
      return false
    end

    -- Elements pages: Labels, Buttons, Toggles, Checkboxes, Inputs, Sliders, Dropdowns,
    -- Keybinds, Color Pickers, Dividers, Viewports, Images, Videos, UI Passthrough. :contentReference[oaicite:5]{index=5}
    local function patch_groupbox(box)
      if type(box) ~= "table" or already_patched_groupbox(box) then return end

      -- Label
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
          patch_keypicker_host(el)     -- labels can host keybinds
          patch_colorpicker_host(el)   -- labels can host color pickers
          return el
        end
        M:GiveTask(function() box.AddLabel = orig end)
      end

      -- Button
      if type(box.AddButton) == "function" then
        local orig = box.AddButton
        box.AddButton = function(self, arg1, arg2)
          local cfg, text, func
          if type(arg1) == "table" then cfg = clone(arg1); text, func = cfg.Text, cfg.Func else text, func = arg1, arg2 end
          local key = id_or_text_key("button", nil, cfg, text)
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
          patch_button_host(el) -- allow sub-buttons to dedupe/aggregate
          return el
        end
        M:GiveTask(function() box.AddButton = orig end)
      end

      -- Toggle
      if type(box.AddToggle) == "function" then
        local orig = box.AddToggle
        box.AddToggle = function(self, id, cfg)
          cfg = cfg or {}
          local key = id_or_text_key("toggle", id, cfg, cfg.Text)
          if key and Shared.Elements.toggle[key] then
            attach_OnChanged(Shared.Elements.toggle[key], cfg.Callback)
            return Shared.Elements.toggle[key]
          end
          local el = orig(self, id, cfg)
          if key then remember("toggle", key, el) end
          patch_keypicker_host(el)
          patch_colorpicker_host(el)
          return el
        end
        M:GiveTask(function() box.AddToggle = orig end)
      end

      -- Checkbox
      if type(box.AddCheckbox) == "function" then
        local orig = box.AddCheckbox
        box.AddCheckbox = function(self, id, cfg)
          cfg = cfg or {}
          local key = id_or_text_key("checkbox", id, cfg, cfg.Text)
          if key and Shared.Elements.checkbox[key] then
            attach_OnChanged(Shared.Elements.checkbox[key], cfg.Callback)
            return Shared.Elements.checkbox[key]
          end
          local el = orig(self, id, cfg)
          if key then remember("checkbox", key, el) end
          patch_keypicker_host(el)
          patch_colorpicker_host(el)
          return el
        end
        M:GiveTask(function() box.AddCheckbox = orig end)
      end

      -- Input
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

      -- Slider
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

      -- Dropdown
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

      -- Divider (visual; no args)
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

      -- Viewport
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

      -- Image
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

      -- Video
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

      -- UI Passthrough
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

      -- Index groupbox by title for convenience
      if type(box.Title) == "string" and box.Title ~= "" then
        remember("groupbox", "__name__:" .. box.Title, box)
      end
    end

    ---------------------------------------------------------------------------
    -- Tabs / Tabboxes patchers
    ---------------------------------------------------------------------------
    local function already_patched_tab(tab)
      if Shared._patched.tabs[tab] then return true end
      Shared._patched.tabs[tab] = true
      return false
    end

    -- Tabs — patch methods that create groupboxes/tabboxes. :contentReference[oaicite:6]{index=6}
    local function patch_tab(tab, name)
      if type(tab) ~= "table" or already_patched_tab(tab) then return end

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
          -- Patch Tabbox
          if type(tb) == "table" and type(tb.AddTab) == "function" then
            local tb_orig = tb.AddTab
            tb.AddTab = function(self2, title)
              local gb = tb_orig(self2, title)
              patch_groupbox(gb)
              if type(title) == "string" and title ~= "" then
                remember("groupbox", "__name__:" .. title, gb)
              end
              return gb
            end
            M:GiveTask(function() tb.AddTab = tb_orig end)
          end
          if type(tb.Title) == "string" and tb.Title ~= "" then
            remember("tabbox", "__name__:" .. tb.Title, tb)
          end
          return tb
        end
        M:GiveTask(function() tab.AddLeftTabbox = orig end)
      end

      if type(tab.AddRightTabbox) == "function" then
        local orig = tab.AddRightTabbox
        tab.AddRightTabbox = function(self, ...)
          local tb = orig(self, ...)
          if type(tb) == "table" and type(tb.AddTab) == "function" then
            local tb_orig = tb.AddTab
            tb.AddTab = function(self2, title)
              local gb = tb_orig(self2, title)
              patch_groupbox(gb)
              if type(title) == "string" and title ~= "" then
                remember("groupbox", "__name__:" .. title, gb)
              end
              return gb
            end
            M:GiveTask(function() tb.AddTab = tb_orig end)
          end
          if type(tb.Title) == "string" and tb.Title ~= "" then
            remember("tabbox", "__name__:" .. tb.Title, tb)
          end
          return tb
        end
        M:GiveTask(function() tab.AddRightTabbox = orig end)
      end

      if type(name) == "string" and name ~= "" then
        remember("tab", "__name__:" .. name, tab)
      end
    end

    -- Patch all tabs in THIS session's UI context
    for name, tab in pairs(UI.Tabs or {}) do
      patch_tab(tab, name)
    end

    ---------------------------------------------------------------------------
    -- Session Stop (unload)
    ---------------------------------------------------------------------------
    local function Stop()
      -- Restore patched methods and disconnect handlers for THIS session
      M:DoCleaning()

      -- Remove this session from the manager and restore the active pointer sensibly
      local mgr = rawget(G, "UISharedManager")
      if mgr and mgr.Sessions then
        mgr.Sessions[SessionId] = nil
        if mgr.Active == SessionId then
          local nextId
          for id, _ in pairs(mgr.Sessions) do
            nextId = id; break
          end
          mgr.Active = nextId
          G.UIShared = nextId and mgr.Sessions[nextId] or nil
          G.UISharedSessionId = nextId
        end
      end
    end

    return { Name = "UIRegistry", Stop = Stop }
  end
end
