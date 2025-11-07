-- "depedency/UIRegistry.lua",
do
  return function(UserInterface)
    -- Shared deps (your system)
    local Services   = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
    local Maid       = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
    local Signal     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()

    local CleanupMaid = Maid.new()
    local GlobalEnvironment = (getgenv and getgenv()) or _G

    -- Expose Obsidian registries for this run (session-local convenience)
    GlobalEnvironment.Toggles = UserInterface.Toggles
    GlobalEnvironment.Options = UserInterface.Options
    GlobalEnvironment.Library = UserInterface.Library

    ---------------------------------------------------------------------------
    -- Multi-session manager
    ---------------------------------------------------------------------------
    local Manager = rawget(GlobalEnvironment, "UISharedManager")
    if not Manager then
      Manager = { Sessions = {}, Active = nil }
      rawset(GlobalEnvironment, "UISharedManager", Manager)
    end

    local function NewGuid()
      local UniqueId
      if Services and Services.HttpService then
        pcall(function() UniqueId = Services.HttpService:GenerateGUID(false) end)
      end
      return UniqueId or ("sess_" .. tostring(math.random()) .. "_" .. tostring(os.clock()))
    end

    -- Back-compat upgrade
    if rawget(GlobalEnvironment, "UIShared") and not Manager.__upgraded then
      local LegacySharedData = GlobalEnvironment.UIShared
      if type(LegacySharedData) == "table" and not Manager.Sessions.legacy then
        Manager.Sessions.legacy = LegacySharedData
      end
      Manager.__upgraded = true
    end

    local SessionId = NewGuid()

    -- Per-session state (dedupe per run)
    local function NewSession(Identifier)
      local Session = {
        Id = Identifier,
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
          groupbox    = {}, -- "__name__:Title" → Groupbox
          tabbox      = {}, -- "__name__:Title" → Tabbox
          tab         = {}, -- "__name__:Name"  → Tab
        },
        ButtonSignals = {},
        -- Canonical maps
        _canonicalTabs   = {},
        _perTab = {
          groupboxes = setmetatable({}, { __mode = "k" }),
          tabboxes   = setmetatable({}, { __mode = "k" }),
        },
        _tabboxTabs = setmetatable({}, { __mode = "k" }),
        _patched = {
          tabs       = setmetatable({}, { __mode = "k" }),
          tabboxes   = setmetatable({}, { __mode = "k" }),
          groupboxes = setmetatable({}, { __mode = "k" }),
          hosts      = setmetatable({}, { __mode = "k" }),
        },
        Find = function(self, ElementKind, StorageKey)
          ElementKind = string.lower(ElementKind)
          local Bucket = self.Elements[ElementKind]
          return Bucket and Bucket[StorageKey] or nil
        end,
      }
      return Session
    end

    local SharedSessionState = NewSession(SessionId)
    Manager.Sessions[SessionId] = SharedSessionState
    Manager.Active = SessionId
    GlobalEnvironment.UIShared = SharedSessionState
    GlobalEnvironment.UISharedSessionId = SessionId

    ---------------------------------------------------------------------------
    -- Utilities
    ---------------------------------------------------------------------------
    local function clone(TableToClone)
      if type(TableToClone) ~= "table" then return TableToClone end
      local NewTable = {}; for key, value in pairs(TableToClone) do NewTable[key] = value end; return NewTable
    end

    local function IdOrTextKey(ElementKind, Identifier, Configuration, TextFallback)
      if type(Identifier) == "string" and Identifier ~= "" then return Identifier end
      local FallbackText = TextFallback or (type(Configuration) == "table" and Configuration.Text)
      if type(FallbackText) == "string" and FallbackText ~= "" then return "__name__:" .. FallbackText end
      return nil
    end

    local function remember(ElementKind, StorageKey, ElementReference)
      if not StorageKey then return end
      SharedSessionState.Elements[ElementKind][StorageKey] = ElementReference
      CleanupMaid:GiveTask(function()
        if SharedSessionState.Elements[ElementKind][StorageKey] == ElementReference then
          SharedSessionState.Elements[ElementKind][StorageKey] = nil
        end
      end)
    end

    local function attach_OnChanged(ElementReference, CallbackFunction)
      if type(CallbackFunction) ~= "function" or type(ElementReference) ~= "table" then return end
      if type(ElementReference.OnChanged) == "function" then
        local Success, Connection = pcall(function() return ElementReference:OnChanged(CallbackFunction) end)
        if Success and Connection then CleanupMaid:GiveTask(Connection) end
      end
    end

    local function was_host_method_patched(HostObject, MethodName)
      local PatchedMethodsMap = SharedSessionState._patched.hosts[HostObject]
      if PatchedMethodsMap and PatchedMethodsMap[MethodName] then return true end
      PatchedMethodsMap = PatchedMethodsMap or {}; PatchedMethodsMap[MethodName] = true
      SharedSessionState._patched.hosts[HostObject] = PatchedMethodsMap
      return false
    end

    ---------------------------------------------------------------------------
    -- Host patchers (KeyPicker / ColorPicker / Button)
    ---------------------------------------------------------------------------
    local function patch_keypicker_host(HostObject)
      if type(HostObject) ~= "table" or type(HostObject.AddKeyPicker) ~= "function" or was_host_method_patched(HostObject, "AddKeyPicker") then
        return
      end
      local OriginalFunction = HostObject.AddKeyPicker
      HostObject.AddKeyPicker = function(self, Identifier, Configuration)
        Configuration = Configuration or {}
        local StorageKey = IdOrTextKey("keybind", Identifier, Configuration, Configuration.Text)
        if StorageKey and SharedSessionState.Elements.keybind[StorageKey] then
          local ExistingElement = SharedSessionState.Elements.keybind[StorageKey]
          if type(Configuration.Callback) == "function" and ExistingElement.OnClick then
            local Success1, Connection1 = pcall(function() return ExistingElement:OnClick(Configuration.Callback) end)
            if Success1 and Connection1 then CleanupMaid:GiveTask(Connection1) end
          end
          if type(Configuration.ChangedCallback) == "function" and ExistingElement.OnChanged then
            local Success2, Connection2 = pcall(function() return ExistingElement:OnChanged(Configuration.ChangedCallback) end)
            if Success2 and Connection2 then CleanupMaid:GiveTask(Connection2) end
          end
          if type(Configuration.Clicked) == "function" and ExistingElement.OnClick then
            local Success3, Connection3 = pcall(function() return ExistingElement:OnClick(Configuration.Clicked) end)
            if Success3 and Connection3 then CleanupMaid:GiveTask(Connection3) end
          end
          return ExistingElement
        end
        local KeybindElement = OriginalFunction(self, Identifier, Configuration)
        if StorageKey then remember("keybind", StorageKey, KeybindElement) end
        return KeybindElement
      end
      CleanupMaid:GiveTask(function() HostObject.AddKeyPicker = OriginalFunction end)
    end

    local function patch_colorpicker_host(HostObject)
      if type(HostObject) ~= "table" or type(HostObject.AddColorPicker) ~= "function" or was_host_method_patched(HostObject, "AddColorPicker") then
        return
      end
      local OriginalFunction = HostObject.AddColorPicker
      HostObject.AddColorPicker = function(self, Identifier, Configuration)
        Configuration = Configuration or {}
        local StorageKey = IdOrTextKey("colorpicker", Identifier, Configuration, Configuration.Title)
        if StorageKey and SharedSessionState.Elements.colorpicker[StorageKey] then
          attach_OnChanged(SharedSessionState.Elements.colorpicker[StorageKey], (Configuration.Callback or Configuration.Changed))
          return SharedSessionState.Elements.colorpicker[StorageKey]
        end
        local ColorpickerElement = OriginalFunction(self, Identifier, Configuration)
        if StorageKey then remember("colorpicker", StorageKey, ColorpickerElement) end
        return ColorpickerElement
      end
      CleanupMaid:GiveTask(function() HostObject.AddColorPicker = OriginalFunction end)
    end

    local function patch_button_host(HostObject)
      if type(HostObject) ~= "table" or type(HostObject.AddButton) ~= "function" or was_host_method_patched(HostObject, "AddButton") then
        return
      end
      local OriginalFunction = HostObject.AddButton
      HostObject.AddButton = function(self, Argument1, Argument2)
        local Configuration, ButtonText, ButtonFunction
        if type(Argument1) == "table" then
          Configuration = clone(Argument1); ButtonText, ButtonFunction = Configuration.Text, Configuration.Func
        else
          ButtonText, ButtonFunction = Argument1, Argument2
        end
        local StorageKey = IdOrTextKey("button", nil, Configuration, ButtonText)
        if StorageKey and SharedSessionState.Elements.button[StorageKey] then
          if type(ButtonFunction) == "function" then
            local SignalInstance = SharedSessionState.ButtonSignals[StorageKey]
            if SignalInstance then
              local Success, Connection = pcall(function() return SignalInstance:Connect(ButtonFunction) end)
              if Success and Connection then CleanupMaid:GiveTask(Connection) end
            end
          end
          return SharedSessionState.Elements.button[StorageKey]
        end
        local SignalInstance = Signal.new()
        SharedSessionState.ButtonSignals[StorageKey or ("__btn__:" .. tostring(self))] = SignalInstance
        CleanupMaid:GiveTask(function()
          SignalInstance:Destroy()
          SharedSessionState.ButtonSignals[StorageKey or ("__btn__:" .. tostring(self))] = nil
        end)
        if type(ButtonFunction) == "function" then
          local Success, Connection = pcall(function() return SignalInstance:Connect(ButtonFunction) end)
          if Success and Connection then CleanupMaid:GiveTask(Connection) end
        end
        local function EventAggregator(...)
          local Arguments = table.pack(...)
          local Success, ErrorMessage = pcall(function()
            SignalInstance:Fire(table.unpack(Arguments, 1, Arguments.n))
          end)
          if not Success then warn(ErrorMessage) end
        end
        local NewElement
        if Configuration then
          Configuration.Func = EventAggregator
          NewElement = OriginalFunction(self, Configuration)
        else
          NewElement = OriginalFunction(self, ButtonText, EventAggregator)
        end
        if StorageKey then remember("button", StorageKey, NewElement) end
        patch_button_host(NewElement) -- nested buttons
        return NewElement
      end
      CleanupMaid:GiveTask(function() HostObject.AddButton = OriginalFunction end)
    end

    ---------------------------------------------------------------------------
    -- Groupbox patcher: wrap ALL adders per docs (and index by title)
    ---------------------------------------------------------------------------
    local function already_patched_groupbox(Groupbox)
      if SharedSessionState._patched.groupboxes[Groupbox] then return true end
      SharedSessionState._patched.groupboxes[Groupbox] = true
      return false
    end

    local function patch_groupbox(Groupbox)
      if type(Groupbox) ~= "table" or already_patched_groupbox(Groupbox) then return end

      -- Label
      if type(Groupbox.AddLabel) == "function" then
        local OriginalFunction = Groupbox.AddLabel
        Groupbox.AddLabel = function(self, Argument1, Argument2)
          local Identifier, Configuration, LabelText
          if type(Argument1) == "string" and type(Argument2) == "table" then
            Identifier, Configuration, LabelText = Argument1, Argument2, Argument2.Text
          elseif type(Argument1) == "table" then
            Identifier, Configuration, LabelText = nil, Argument1, Argument1.Text
          else
            Identifier, Configuration, LabelText = nil, { Text = Argument1, DoesWrap = Argument2 }, Argument1
          end
          local StorageKey = IdOrTextKey("label", Identifier, Configuration, LabelText)
          if StorageKey and SharedSessionState.Elements.label[StorageKey] then
            return SharedSessionState.Elements.label[StorageKey]
          end
          local NewElement = OriginalFunction(self, Argument1, Argument2)
          if StorageKey then remember("label", StorageKey, NewElement) end
          patch_keypicker_host(NewElement)
          patch_colorpicker_host(NewElement)
          return NewElement
        end
        CleanupMaid:GiveTask(function() Groupbox.AddLabel = OriginalFunction end)
      end

      -- Button
      if type(Groupbox.AddButton) == "function" then
        local OriginalFunction = Groupbox.AddButton
        Groupbox.AddButton = function(self, Argument1, Argument2)
          local Configuration, ButtonText, ButtonFunction
          if type(Argument1) == "table" then
            Configuration = clone(Argument1); ButtonText, ButtonFunction = Configuration.Text, Configuration.Func
          else
            ButtonText, ButtonFunction = Argument1, Argument2
          end
          local StorageKey = IdOrTextKey("button", nil, Configuration, ButtonText)
          if StorageKey and SharedSessionState.Elements.button[StorageKey] then
            if type(ButtonFunction) == "function" then
              local SignalInstance = SharedSessionState.ButtonSignals[StorageKey]
              if SignalInstance then
                local Success, Connection = pcall(function() return SignalInstance:Connect(ButtonFunction) end)
                if Success and Connection then CleanupMaid:GiveTask(Connection) end
              end
            end
            return SharedSessionState.Elements.button[StorageKey]
          end
          local SignalInstance = Signal.new()
          SharedSessionState.ButtonSignals[StorageKey or ("__btn__:" .. tostring(self))] = SignalInstance
          CleanupMaid:GiveTask(function()
            SignalInstance:Destroy()
            SharedSessionState.ButtonSignals[StorageKey or ("__btn__:" .. tostring(self))] = nil
          end)
          if type(ButtonFunction) == "function" then
            local Success, Connection = pcall(function() return SignalInstance:Connect(ButtonFunction) end)
            if Success and Connection then CleanupMaid:GiveTask(Connection) end
          end
          local function EventAggregator(...)
            local Arguments = table.pack(...)
            local Success, ErrorMessage = pcall(function()
              SignalInstance:Fire(table.unpack(Arguments, 1, Arguments.n))
            end)
            if not Success then warn(ErrorMessage) end
          end
          local NewElement
          if Configuration then
            Configuration.Func = EventAggregator
            NewElement = OriginalFunction(self, Configuration)
          else
            NewElement = OriginalFunction(self, ButtonText, EventAggregator)
          end
          if StorageKey then remember("button", StorageKey, NewElement) end
          patch_button_host(NewElement)
          return NewElement
        end
        CleanupMaid:GiveTask(function() Groupbox.AddButton = OriginalFunction end)
      end

      -- Toggle
      if type(Groupbox.AddToggle) == "function" then
        local OriginalFunction = Groupbox.AddToggle
        Groupbox.AddToggle = function(self, Identifier, Configuration)
          Configuration = Configuration or {}
          local StorageKey = IdOrTextKey("toggle", Identifier, Configuration, Configuration.Text)
          if StorageKey and SharedSessionState.Elements.toggle[StorageKey] then
            attach_OnChanged(SharedSessionState.Elements.toggle[StorageKey], Configuration.Callback)
            return SharedSessionState.Elements.toggle[StorageKey]
          end
          local NewElement = OriginalFunction(self, Identifier, Configuration)
          if StorageKey then remember("toggle", StorageKey, NewElement) end
          patch_keypicker_host(NewElement)
          patch_colorpicker_host(NewElement)
          return NewElement
        end
        CleanupMaid:GiveTask(function() Groupbox.AddToggle = OriginalFunction end)
      end

      -- Checkbox
      if type(Groupbox.AddCheckbox) == "function" then
        local OriginalFunction = Groupbox.AddCheckbox
        Groupbox.AddCheckbox = function(self, Identifier, Configuration)
          Configuration = Configuration or {}
          local StorageKey = IdOrTextKey("checkbox", Identifier, Configuration, Configuration.Text)
          if StorageKey and SharedSessionState.Elements.checkbox[StorageKey] then
            attach_OnChanged(SharedSessionState.Elements.checkbox[StorageKey], Configuration.Callback)
            return SharedSessionState.Elements.checkbox[StorageKey]
          end
          local NewElement = OriginalFunction(self, Identifier, Configuration)
          if StorageKey then remember("checkbox", StorageKey, NewElement) end
          patch_keypicker_host(NewElement)
          patch_colorpicker_host(NewElement)
          return NewElement
        end
        CleanupMaid:GiveTask(function() Groupbox.AddCheckbox = OriginalFunction end)
      end

      -- Input
      if type(Groupbox.AddInput) == "function" then
        local OriginalFunction = Groupbox.AddInput
        Groupbox.AddInput = function(self, Identifier, Configuration)
          Configuration = Configuration or {}
          local StorageKey = IdOrTextKey("input", Identifier, Configuration, Configuration.Text)
          if StorageKey and SharedSessionState.Elements.input[StorageKey] then
            attach_OnChanged(SharedSessionState.Elements.input[StorageKey], Configuration.Callback)
            return SharedSessionState.Elements.input[StorageKey]
          end
          local NewElement = OriginalFunction(self, Identifier, Configuration)
          if StorageKey then remember("input", StorageKey, NewElement) end
          return NewElement
        end
        CleanupMaid:GiveTask(function() Groupbox.AddInput = OriginalFunction end)
      end

      -- Slider
      if type(Groupbox.AddSlider) == "function" then
        local OriginalFunction = Groupbox.AddSlider
        Groupbox.AddSlider = function(self, Identifier, Configuration)
          Configuration = Configuration or {}
          local StorageKey = IdOrTextKey("slider", Identifier, Configuration, Configuration.Text)
          if StorageKey and SharedSessionState.Elements.slider[StorageKey] then
            attach_OnChanged(SharedSessionState.Elements.slider[StorageKey], Configuration.Callback)
            return SharedSessionState.Elements.slider[StorageKey]
          end
          local NewElement = OriginalFunction(self, Identifier, Configuration)
          if StorageKey then remember("slider", StorageKey, NewElement) end
          return NewElement
        end
        CleanupMaid:GiveTask(function() Groupbox.AddSlider = OriginalFunction end)
      end

      -- Dropdown
      if type(Groupbox.AddDropdown) == "function" then
        local OriginalFunction = Groupbox.AddDropdown
        Groupbox.AddDropdown = function(self, Identifier, Configuration)
          Configuration = Configuration or {}
          local StorageKey = IdOrTextKey("dropdown", Identifier, Configuration, Configuration.Text)
          if StorageKey and SharedSessionState.Elements.dropdown[StorageKey] then
            attach_OnChanged(SharedSessionState.Elements.dropdown[StorageKey], Configuration.Callback)
            return SharedSessionState.Elements.dropdown[StorageKey]
          end
          local NewElement = OriginalFunction(self, Identifier, Configuration)
          if StorageKey then remember("dropdown", StorageKey, NewElement) end
          return NewElement
        end
        CleanupMaid:GiveTask(function() Groupbox.AddDropdown = OriginalFunction end)
      end

      -- Divider
      if type(Groupbox.AddDivider) == "function" then
        local OriginalFunction = Groupbox.AddDivider
        Groupbox.AddDivider = function(self, ...)
          local NewElement = OriginalFunction(self, ...)
          local UniqueId = Services.HttpService and Services.HttpService:GenerateGUID(false) or tostring(NewElement)
          remember("divider", UniqueId, NewElement)
          return NewElement
        end
        CleanupMaid:GiveTask(function() Groupbox.AddDivider = OriginalFunction end)
      end

      -- Viewport
      if type(Groupbox.AddViewport) == "function" then
        local OriginalFunction = Groupbox.AddViewport
        Groupbox.AddViewport = function(self, Identifier, Configuration)
          Configuration = Configuration or {}
          local StorageKey = IdOrTextKey("viewport", Identifier, Configuration, Configuration.Title)
          if StorageKey and SharedSessionState.Elements.viewport[StorageKey] then
            return SharedSessionState.Elements.viewport[StorageKey]
          end
          local NewElement = OriginalFunction(self, Identifier, Configuration)
          if StorageKey then remember("viewport", StorageKey, NewElement) end
          return NewElement
        end
        CleanupMaid:GiveTask(function() Groupbox.AddViewport = OriginalFunction end)
      end

      -- Image
      if type(Groupbox.AddImage) == "function" then
        local OriginalFunction = Groupbox.AddImage
        Groupbox.AddImage = function(self, Identifier, Configuration)
          Configuration = Configuration or {}
          local StorageKey = IdOrTextKey("image", Identifier, Configuration, Configuration.Text)
          if StorageKey and SharedSessionState.Elements.image[StorageKey] then
            return SharedSessionState.Elements.image[StorageKey]
          end
          local NewElement = OriginalFunction(self, Identifier, Configuration)
          if StorageKey then remember("image", StorageKey, NewElement) end
          return NewElement
        end
        CleanupMaid:GiveTask(function() Groupbox.AddImage = OriginalFunction end)
      end

      -- Video
      if type(Groupbox.AddVideo) == "function" then
        local OriginalFunction = Groupbox.AddVideo
        Groupbox.AddVideo = function(self, Identifier, Configuration)
          Configuration = Configuration or {}
          local StorageKey = IdOrTextKey("video", Identifier, Configuration, Configuration.Text)
          if StorageKey and SharedSessionState.Elements.video[StorageKey] then
            return SharedSessionState.Elements.video[StorageKey]
          end
          local NewElement = OriginalFunction(self, Identifier, Configuration)
          if StorageKey then remember("video", StorageKey, NewElement) end
          return NewElement
        end
        CleanupMaid:GiveTask(function() Groupbox.AddVideo = OriginalFunction end)
      end

      -- UI Passthrough
      if type(Groupbox.AddUIPassthrough) == "function" then
        local OriginalFunction = Groupbox.AddUIPassthrough
        Groupbox.AddUIPassthrough = function(self, Identifier, Configuration)
          Configuration = Configuration or {}
          local StorageKey = IdOrTextKey("uipass", Identifier, Configuration, Configuration.Title)
          if StorageKey and SharedSessionState.Elements.uipass[StorageKey] then
            return SharedSessionState.Elements.uipass[StorageKey]
          end
          local NewElement = OriginalFunction(self, Identifier, Configuration)
          if StorageKey then remember("uipass", StorageKey, NewElement) end
          return NewElement
        end
        CleanupMaid:GiveTask(function() Groupbox.AddUIPassthrough = OriginalFunction end)
      end

      -- Index by title
      if type(Groupbox.Title) == "string" and Groupbox.Title ~= "" then
        remember("groupbox", "__name__:" .. Groupbox.Title, Groupbox)
      end
    end

    ---------------------------------------------------------------------------
    -- Tabbox patcher (AddTab dedupe → Groupbox)
    ---------------------------------------------------------------------------
    local function already_patched_tabbox(Tabbox)
      if SharedSessionState._patched.tabboxes[Tabbox] then return true end
      SharedSessionState._patched.tabboxes[Tabbox] = true
      return false
    end

    local function patch_tabbox(Tabbox)
      if type(Tabbox) ~= "table" or already_patched_tabbox(Tabbox) then return end

      if type(Tabbox.AddTab) == "function" then
        local OriginalFunction = Tabbox.AddTab
        Tabbox.AddTab = function(self, Title)
          local TabMap = SharedSessionState._tabboxTabs[self]
          if not TabMap then TabMap = {}; SharedSessionState._tabboxTabs[self] = TabMap end

          if type(Title) == "string" and Title ~= "" then
            local ExistingElement = TabMap[Title]
            if ExistingElement then
              patch_groupbox(ExistingElement)
              return ExistingElement
            end
          end

          local GroupboxElement = OriginalFunction(self, Title)
          patch_groupbox(GroupboxElement)

          if type(Title) == "string" and Title ~= "" then
            TabMap[Title] = GroupboxElement
            if not SharedSessionState.Elements.groupbox["__name__:" .. Title] then
              remember("groupbox", "__name__:" .. Title, GroupboxElement)
            end
          end
          return GroupboxElement
        end
        CleanupMaid:GiveTask(function() Tabbox.AddTab = OriginalFunction end)
      end

      if type(Tabbox.Title) == "string" and Tabbox.Title ~= "" then
        remember("tabbox", "__name__:" .. Tabbox.Title, Tabbox)
      end
    end

    ---------------------------------------------------------------------------
    -- Tabs patchers (via CANONICAL proxy)
    ---------------------------------------------------------------------------
    local function already_patched_tab(TabObject)
      if SharedSessionState._patched.tabs[TabObject] then return true end
      SharedSessionState._patched.tabs[TabObject] = true
      return false
    end

    local function per_tab_maps(TabObject)
      local GroupboxMap = SharedSessionState._perTab.groupboxes[TabObject]
      if not GroupboxMap then GroupboxMap = {}; SharedSessionState._perTab.groupboxes[TabObject] = GroupboxMap end
      local TabboxMap = SharedSessionState._perTab.tabboxes[TabObject]
      if not TabboxMap then TabboxMap = {}; SharedSessionState._perTab.tabboxes[TabObject] = TabboxMap end
      return GroupboxMap, TabboxMap
    end

    local function patch_tab(TabObject, TabName)
      if type(TabObject) ~= "table" or already_patched_tab(TabObject) then return end
      local GroupboxMap, TabboxMap = per_tab_maps(TabObject)

      -- AddLeftGroupbox(title, icon?)
      if type(TabObject.AddLeftGroupbox) == "function" then
        local OriginalFunction = TabObject.AddLeftGroupbox
        TabObject.AddLeftGroupbox = function(self, Title, Icon, ...)
          if type(Title) == "string" and Title ~= "" then
            local ExistingElement = GroupboxMap[Title]
            if ExistingElement then
              patch_groupbox(ExistingElement)
              return ExistingElement
            end
          end
          local GroupboxElement = OriginalFunction(self, Title, Icon, ...)
          patch_groupbox(GroupboxElement)
          if type(Title) == "string" and Title ~= "" then
            GroupboxMap[Title] = GroupboxElement
            if not SharedSessionState.Elements.groupbox["__name__:" .. Title] then
              remember("groupbox", "__name__:" .. Title, GroupboxElement)
            end
          end
          return GroupboxElement
        end
        CleanupMaid:GiveTask(function() TabObject.AddLeftGroupbox = OriginalFunction end)
      end

      -- AddRightGroupbox(title, icon?)
      if type(TabObject.AddRightGroupbox) == "function" then
        local OriginalFunction = TabObject.AddRightGroupbox
        TabObject.AddRightGroupbox = function(self, Title, Icon, ...)
          if type(Title) == "string" and Title ~= "" then
            local ExistingElement = GroupboxMap[Title]
            if ExistingElement then
              patch_groupbox(ExistingElement)
              return ExistingElement
            end
          end
          local GroupboxElement = OriginalFunction(self, Title, Icon, ...)
          patch_groupbox(GroupboxElement)
          if type(Title) == "string" and Title ~= "" then
            GroupboxMap[Title] = GroupboxElement
            if not SharedSessionState.Elements.groupbox["__name__:" .. Title] then
              remember("groupbox", "__name__:" .. Title, GroupboxElement)
            end
          end
          return GroupboxElement
        end
        CleanupMaid:GiveTask(function() TabObject.AddRightGroupbox = OriginalFunction end)
      end

      -- AddLeftTabbox(title, icon?)
      if type(TabObject.AddLeftTabbox) == "function" then
        local OriginalFunction = TabObject.AddLeftTabbox
        TabObject.AddLeftTabbox = function(self, Title, Icon, ...)
          if type(Title) == "string" and Title ~= "" then
            local ExistingElement = TabboxMap[Title]
            if ExistingElement then
              patch_tabbox(ExistingElement)
              return ExistingElement
            end
          end
          local TabboxElement = OriginalFunction(self, Title, Icon, ...)
          patch_tabbox(TabboxElement)
          if type(Title) == "string" and Title ~= "" then
            TabboxMap[Title] = TabboxElement
            if not SharedSessionState.Elements.tabbox["__name__:" .. Title] then
              remember("tabbox", "__name__:" .. Title, TabboxElement)
            end
          end
          return TabboxElement
        end
        CleanupMaid:GiveTask(function() TabObject.AddLeftTabbox = OriginalFunction end)
      end

      -- AddRightTabbox(title, icon?)
      if type(TabObject.AddRightTabbox) == "function" then
        local OriginalFunction = TabObject.AddRightTabbox
        TabObject.AddRightTabbox = function(self, Title, Icon, ...)
          if type(Title) == "string" and Title ~= "" then
            local ExistingElement = TabboxMap[Title]
            if ExistingElement then
              patch_tabbox(ExistingElement)
              return ExistingElement
            end
          end
          local TabboxElement = OriginalFunction(self, Title, Icon, ...)
          patch_tabbox(TabboxElement)
          if type(Title) == "string" and Title ~= "" then
            TabboxMap[Title] = TabboxElement
            if not SharedSessionState.Elements.tabbox["__name__:" .. Title] then
              remember("tabbox", "__name__:" .. Title, TabboxElement)
            end
          end
          return TabboxElement
        end
        CleanupMaid:GiveTask(function() TabObject.AddRightTabbox = OriginalFunction end)
      end

      if type(TabName) == "string" and TabName ~= "" then
        remember("tab", "__name__:" .. TabName, TabObject)
      end
    end

    -- === Canonical Tabs Proxy ===
    local RawTabs = UserInterface.Tabs
    local CanonicalTabs = {}
    local CanonicalMetatable = {}

    CanonicalMetatable.__index = function(_, Key)
      local CachedElement = SharedSessionState._canonicalTabs[Key]
      if CachedElement then return CachedElement end
      local RawElement = RawTabs and RawTabs[Key]
      if RawElement == nil then return nil end
      if type(RawElement) == "table" then
        patch_tab(RawElement, Key)
      end
      SharedSessionState._canonicalTabs[Key] = RawElement
      return RawElement
    end

    CanonicalMetatable.__pairs = function()
      local KeyList = {}
      for Key in pairs(RawTabs or {}) do table.insert(KeyList, Key) end
      local Index = 0
      return function()
        Index = Index + 1
        local Key = KeyList[Index]
        if not Key then return end
        return Key, CanonicalTabs[Key]
      end
    end

    CanonicalMetatable.__len = function()
      local Count = 0
      for _ in pairs(RawTabs or {}) do Count = Count + 1 end
      return Count
    end

    setmetatable(CanonicalTabs, CanonicalMetatable)

    -- swap tabs reference to the canonical proxy
    local OriginalTabs = UserInterface.Tabs
    UserInterface.Tabs = CanonicalTabs
    GlobalEnvironment.Tabs  = CanonicalTabs

    -- touch each existing key once to patch & cache
    for TabName in pairs(OriginalTabs or {}) do
      local _ = CanonicalTabs[TabName]
    end

    ---------------------------------------------------------------------------
    -- Session Stop (unload)
    ---------------------------------------------------------------------------
    local function Stop()
      UserInterface.Tabs = OriginalTabs
      GlobalEnvironment.Tabs  = UserInterface.Tabs
      CleanupMaid:DoCleaning()
      local ManagerInstance = rawget(GlobalEnvironment, "UISharedManager")
      if ManagerInstance and ManagerInstance.Sessions then
        ManagerInstance.Sessions[SessionId] = nil
        if ManagerInstance.Active == SessionId then
          local NextSessionId
          for LoopSessionId, _ in pairs(ManagerInstance.Sessions) do NextSessionId = LoopSessionId; break end
          ManagerInstance.Active = NextSessionId
          GlobalEnvironment.UIShared = NextSessionId and ManagerInstance.Sessions[NextSessionId] or nil
          GlobalEnvironment.UISharedSessionId = NextSessionId
        end
      end
    end

    return { Name = "UIRegistry", Stop = Stop }
  end
end
