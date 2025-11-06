-- dependency/UIRegistry.lua
print('new test')
do
  return function(UI)
    -- Shared deps (your system)
    local Services   = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
    local Maid       = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
    local Signal     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()

    local M = Maid.new()
    local G = (getgenv and getgenv()) or _G

    -- Expose Obsidian registries for this run (session-local convenience)
    G.Toggles = UI.Toggles
    G.Options = UI.Options
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

    -- Back-compat upgrade
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
          label       = {},
          button      = {},
          toggle      = {},
          checkbox    = {},
          input       = {},
          slider      = {},
          dropdown    = {},
          keybind     = {},
          colorpicker = {},
          divider     = {},
          viewport    = {},
          image       = {},
          video       = {},
          uipass      = {},
          groupbox    = {}, -- "__name__:Title" → Groupbox (first seen; for Find convenience)
          tabbox      = {}, -- "__name__:Title" → Tabbox
          tab         = {}, -- "__name__:Name"  → Tab
        },
        ButtonSignals = {},
        -- Canonical maps
        _canonicalTabs   = {}, -- name → canonical tab wrapper (stable)
        _perTab = {
          groupboxes = setmetatable({}, { __mode = "k" }), -- tab → { [title]=groupbox }
          tabboxes   = setmetatable({}, { __mode = "k" }), -- tab → { [title]=tabbox }
        },
        _tabboxTabs = setmetatable({}, { __mode = "k" }),  -- tabbox → { [title]=groupbox }
        _patched = {
          tabs       = setmetatable({}, { __mode = "k" }),
          tabboxes   = setmetatable({}, { __mode = "k" }),
          groupboxes = setmetatable({}, { __mode = "k" }),
          hosts      = setmetatable({}, { __mode = "k" }),
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
    G.UIShared = Shared
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

    local function attach_OnChanged(ref, fn)
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
    -- Host patchers (KeyPicker / ColorPicker / Button)
    ---------------------------------------------------------------------------
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

    local function patch_colorpicker_host(host)
      if type(host) ~= "table" or type(host.AddColorPicker) ~= "function" or was_host_method_patched(host, "AddColorPicker") then
        return
      end
      local orig = host.AddColorPicker
      host.AddColorPicker = function(self, id, cfg)
        cfg = cfg or {}
        local key = id_or_text_key("colorpicker", id, cfg, cfg.Title)
        if key and Shared.Elements.colorpicker[key] then
          attach_OnChanged(Shared.Elements.colorpicker[key], (cfg.Callback or cfg.Changed))
          return Shared.Elements.colorpicker[key]
        end
        local cp = orig(self, id, cfg)
        if key then remember("colorpicker", key, cp) end
        return cp
      end
      M:GiveTask(function() host.AddColorPicker = orig end)
    end

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
        local function aggregator(...)
          local ok, err = pcall(function() sig:Fire(...) end)
          if not ok then warn(err) end
        end
        local el
        if cfg then cfg.Func = aggregator; el = orig(self, cfg) else el = orig(self, text, aggregator) end
        if key then remember("button", key, el) end
        patch_button_host(el) -- nested buttons
        return el
      end
      M:GiveTask(function() host.AddButton = orig end)
    end

    ---------------------------------------------------------------------------
    -- Groupbox patcher: wrap ALL adders per docs (and index by title)
    ---------------------------------------------------------------------------
    local function already_patched_groupbox(box)
      if Shared._patched.groupboxes[box] then return true end
      Shared._patched.groupboxes[box] = true
      return false
    end

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
          patch_keypicker_host(el)
          patch_colorpicker_host(el)
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
          local function aggregator(...) local ok, err = pcall(function() sig:Fire(...) end); if not ok then warn(err) end end
          local el
          if cfg then cfg.Func = aggregator; el = orig(self, cfg) else el = orig(self, text, aggregator) end
          if key then remember("button", key, el) end
          patch_button_host(el)
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

      -- Divider
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

      -- Index by title
      if type(box.Title) == "string" and box.Title ~= "" then
        remember("groupbox", "__name__:" .. box.Title, box)
      end
    end

    ---------------------------------------------------------------------------
    -- Tabbox patcher (AddTab dedupe → Groupbox)
    ---------------------------------------------------------------------------
    local function already_patched_tabbox(tb)
      if Shared._patched.tabboxes[tb] then return true end
      Shared._patched.tabboxes[tb] = true
      return false
    end

    local function patch_tabbox(tb)
      if type(tb) ~= "table" or already_patched_tabbox(tb) then return end

      if type(tb.AddTab) == "function" then
        local orig = tb.AddTab
        tb.AddTab = function(self, title)
          local map = Shared._tabboxTabs[self]
          if not map then map = {}; Shared._tabboxTabs[self] = map end

          if type(title) == "string" and title ~= "" then
            local existing = map[title]
            if existing then
              patch_groupbox(existing)
              return existing
            end
          end

          local gb = orig(self, title)
          patch_groupbox(gb)

          if type(title) == "string" and title ~= "" then
            map[title] = gb
            if not Shared.Elements.groupbox["__name__:" .. title] then
              remember("groupbox", "__name__:" .. title, gb)
            end
          end
          return gb
        end
        M:GiveTask(function() tb.AddTab = orig end)
      end

      if type(tb.Title) == "string" and tb.Title ~= "" then
        remember("tabbox", "__name__:" .. tb.Title, tb)
      end
    end

    ---------------------------------------------------------------------------
    -- Tabs patchers (via CANONICAL proxy)
    ---------------------------------------------------------------------------
    local function already_patched_tab(tab)
      if Shared._patched.tabs[tab] then return true end
      Shared._patched.tabs[tab] = true
      return false
    end

    local function per_tab_maps(tab)
      local gmap = Shared._perTab.groupboxes[tab]
      if not gmap then gmap = {}; Shared._perTab.groupboxes[tab] = gmap end
      local tbmap = Shared._perTab.tabboxes[tab]
      if not tbmap then tbmap = {}; Shared._perTab.tabboxes[tab] = tbmap end
      return gmap, tbmap
    end

    local function patch_tab(tab, name)
      if type(tab) ~= "table" or already_patched_tab(tab) then return end
      local gbmap, tbmap = per_tab_maps(tab)

      -- AddLeftGroupbox(title, icon?)
      if type(tab.AddLeftGroupbox) == "function" then
        local orig = tab.AddLeftGroupbox
        tab.AddLeftGroupbox = function(self, title, icon, ...)
          if type(title) == "string" and title ~= "" then
            local existing = gbmap[title]
            if existing then
              patch_groupbox(existing)
              return existing
            end
          end
          -- forward icon (and any future extra args) to preserve Lucide support
          local gb = orig(self, title, icon, ...)
          patch_groupbox(gb)
          if type(title) == "string" and title ~= "" then
            gbmap[title] = gb
            if not Shared.Elements.groupbox["__name__:" .. title] then
              remember("groupbox", "__name__:" .. title, gb)
            end
          end
          return gb
        end
        M:GiveTask(function() tab.AddLeftGroupbox = orig end)
      end

      -- AddRightGroupbox(title, icon?)
      if type(tab.AddRightGroupbox) == "function" then
        local orig = tab.AddRightGroupbox
        tab.AddRightGroupbox = function(self, title, icon, ...)
          if type(title) == "string" and title ~= "" then
            local existing = gbmap[title]
            if existing then
              patch_groupbox(existing)
              return existing
            end
          end
          local gb = orig(self, title, icon, ...)
          patch_groupbox(gb)
          if type(title) == "string" and title ~= "" then
            gbmap[title] = gb
            if not Shared.Elements.groupbox["__name__:" .. title] then
              remember("groupbox", "__name__:" .. title, gb)
            end
          end
          return gb
        end
        M:GiveTask(function() tab.AddRightGroupbox = orig end)
      end

      -- AddLeftTabbox(title, icon?)
      if type(tab.AddLeftTabbox) == "function" then
        local orig = tab.AddLeftTabbox
        tab.AddLeftTabbox = function(self, title, icon, ...)
          if type(title) == "string" and title ~= "" then
            local existing = tbmap[title]
            if existing then
              patch_tabbox(existing)
              return existing
            end
          end
          local tb = orig(self, title, icon, ...)
          patch_tabbox(tb)
          if type(title) == "string" and title ~= "" then
            tbmap[title] = tb
            if not Shared.Elements.tabbox["__name__:" .. title] then
              remember("tabbox", "__name__:" .. title, tb)
            end
          end
          return tb
        end
        M:GiveTask(function() tab.AddLeftTabbox = orig end)
      end

      -- AddRightTabbox(title, icon?)
      if type(tab.AddRightTabbox) == "function" then
        local orig = tab.AddRightTabbox
        tab.AddRightTabbox = function(self, title, icon, ...)
          if type(title) == "string" and title ~= "" then
            local existing = tbmap[title]
            if existing then
              patch_tabbox(existing)
              return existing
            end
          end
          local tb = orig(self, title, icon, ...)
          patch_tabbox(tb)
          if type(title) == "string" and title ~= "" then
            tbmap[title] = tb
            if not Shared.Elements.tabbox["__name__:" .. title] then
              remember("tabbox", "__name__:" .. title, tb)
            end
          end
          return tb
        end
        M:GiveTask(function() tab.AddRightTabbox = orig end)
      end

      if type(name) == "string" and name ~= "" then
        remember("tab", "__name__:" .. name, tab)
      end
    end

    -- === Canonical Tabs Proxy ===
    local RawTabs = UI.Tabs
    local CanonTabs = {}
    local canon_mt = {}

    canon_mt.__index = function(_, k)
      -- return cached canonical instance if present
      local cached = Shared._canonicalTabs[k]
      if cached then return cached end

      -- pull one wrapper from the raw table
      local raw = RawTabs and RawTabs[k]
      if raw == nil then return nil end

      -- Patch the pulled wrapper and cache as canonical for this key
      if type(raw) == "table" then
        patch_tab(raw, k)
      end
      Shared._canonicalTabs[k] = raw
      return raw
    end

    -- iterate yielding canonical wrappers (important for modules that do pairs(UI.Tabs))
    canon_mt.__pairs = function()
      local keys = {}
      for k in pairs(RawTabs or {}) do table.insert(keys, k) end
      local i = 0
      return function()
        i = i + 1
        local k = keys[i]
        if not k then return end
        return k, CanonTabs[k] -- triggers __index to return canonical
      end
    end

    -- safety: preserve length semantics if used
    canon_mt.__len = function()
      local n = 0
      for _ in pairs(RawTabs or {}) do n = n + 1 end
      return n
    end

    setmetatable(CanonTabs, canon_mt)

    -- swap tabs reference to the canonical proxy
    local OriginalTabs = UI.Tabs
    UI.Tabs = CanonTabs
    G.Tabs  = CanonTabs

    -- touch each existing key once to patch & cache
    for name in pairs(OriginalTabs or {}) do
      local _ = CanonTabs[name]
    end

    ---------------------------------------------------------------------------
    -- Session Stop (unload)
    ---------------------------------------------------------------------------
    local function Stop()
      -- restore tabs table to original for safety (this session only)
      UI.Tabs = OriginalTabs
      G.Tabs  = UI.Tabs

      -- restore patched methods and disconnect handlers for THIS session
      M:DoCleaning()

      -- remove this session from the manager
      local mgr = rawget(G, "UISharedManager")
      if mgr and mgr.Sessions then
        mgr.Sessions[SessionId] = nil
        if mgr.Active == SessionId then
          local nextId
          for id, _ in pairs(mgr.Sessions) do nextId = id; break end
          mgr.Active = nextId
          G.UIShared = nextId and mgr.Sessions[nextId] or nil
          G.UISharedSessionId = nextId
        end
      end
    end

    return { Name = "UIRegistry", Stop = Stop }
  end
end
