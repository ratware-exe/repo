-- "dependency/UIRegistry.lua",
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
    -- Top-Level Window Patcher
    ---------------------------------------------------------------------------

    -- Note: Watermark is not session-managed, just patched for completeness.
    if type(UserInterface.AddWatermark) == "function" then
      local OriginalFunction = UserInterface.AddWatermark
      -- We don't need to register/dedupe watermarks, just restore the function.
      CleanupMaid:GiveTask(function() UserInterface.AddWatermark = OriginalFunction end)
    end

    -- Note: Notify is not session-managed, just patched for completeness.
    if type(UserInterface.Notify) == "function" then
      local OriginalFunction = UserInterface.Notify
      CleanupMaid:GiveTask(function() UserInterface.Notify = OriginalFunction end)
    end

    -- Note: Confirm is not session-managed, just patched for completeness.
    if type(UserInterface.Confirm) == "function" then
      local OriginalFunction = UserInterface.Confirm
      CleanupMaid:GiveTask(function() UserInterface.Confirm = OriginalFunction end)
    end

    -- Note: Prompt is not session-managed, just patched for completeness.
    if type(UserInterface.Prompt) == "function" then
      local OriginalFunction = UserInterface.Prompt
      CleanupMaid:GiveTask(function() UserInterface.Prompt = OriginalFunction end)
    end

    -- Hook Destroy to ensure our Stop function is called for cleanup
    if type(UserInterface.Destroy) == "function" then
      local OriginalFunction = UserInterface.Destroy
      UserInterface.Destroy = function(...)
        Stop() -- Call our session cleanup
        return OriginalFunction(...) -- Call the original destroy
      end
      CleanupMaid:GiveTask(function() UserInterface.Destroy = OriginalFunction end)
    end

    -- Hook Tab methods to ensure they are patched
    if type(UserInterface.AddTab) == "function" then
      local OriginalFunction = UserInterface.AddTab
      UserInterface.AddTab = function(self, Name, ...)
        local NewTab = OriginalFunction(self, Name, ...)
        if type(NewTab) == "table" then
          patch_tab(NewTab, Name) -- Patch the newly created tab
        end
        return NewTab
      end
      CleanupMaid:GiveTask(function() UserInterface.AddTab = OriginalFunction end)
    end

    if type(UserInterface.GetTab) == "function" then
      local OriginalFunction = UserInterface.GetTab
      UserInterface.GetTab = function(self, Name, ...)
        local ExistingTab = OriginalFunction(self, Name, ...)
        if type(ExistingTab) == "table" then
          patch_tab(ExistingTab, Name) -- Patch the retrieved tab (idempotent)
        end
        return ExistingTab
      end
      CleanupMaid:GiveTask(function() UserInterface.GetTab = OriginalFunction end)
    end

    -- SelectTab doesn't return a tab, so just needs to be restored.
    if type(UserInterface.SelectTab) == "function" then
      local OriginalFunction = UserInterface.SelectTab
      -- We don't need to register/dedupe this, just restore the function.
      CleanupMaid:GiveTask(function() UserInterface.SelectTab = OriginalFunction end)
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

      -- Patch host methods directly on the groupbox
      -- This single block replaces ~120 lines of duplicated code
      patch_button_host(Groupbox)
      patch_keypicker_host(Groupbox) -- This now handles AddKeybind
      patch_colorpicker_host(Groupbox)

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
      -- (This is now handled by patch_button_host(Groupbox) above)

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
          local DividerElement = OriginalFunction(self, ...)
          -- Dividers are anonymous and cannot be de-duplicated.
          -- Do not call remember() on them.
          -- local Guid = Services.HttpService and Services.HttpService:GenerateGUID(false) or tostring(DividerElement)
          -- remember("divider", Guid, DividerElement)
          return DividerElement
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

      -- KeyPicker (and alias AddKeybind)
      -- (This is now handled by patch_keypicker_host(Groupbox) above)

      -- ColorPicker
      -- (This is now handled by patch_colorpicker_host(Groupbox) above)

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

      -- AddGroupbox(title, icon?) -- ALIAS FOR AddLeftGroupbox
      if type(TabObject.AddGroupbox) == "function" then
        local OriginalFunction = TabObject.AddGroupbox
        TabObject.AddGroupbox = function(self, Title, Icon, ...)
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
        CleanupMaid:GiveTask(function() TabObject.AddGroupbox = OriginalFunction end)
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

      -- AddTabbox(title, icon?) -- ALIAS FOR AddLeftTabbox
      if type(TabObject.AddTabbox) == "function" then
        local OriginalFunction = TabObject.AddTabbox
        TabObject.AddTabbox = function(self, Title, Icon, ...)
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
        CleanupMaid:GiveTask(function() TabObject.AddTabbox = OriginalFunction end)
      end

      if type(Name) == "string" and Name ~= "" then
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
