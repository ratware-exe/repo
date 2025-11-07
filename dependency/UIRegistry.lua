-- "depedency/UIRegistry.lua",
do
  return function(userinterface)
    -- Shared deps (your system)
    local Services   = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Services.lua"), "@Services.lua")()
    local Maid       = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Maid.lua"), "@Maid.lua")()
    local Signal     = loadstring(game:HttpGet(_G.RepoBase .. "dependency/Signal.lua"), "@Signal.lua")()

    local cleanupmaid = Maid.new()
    local globalenvironment = (getgenv and getgenv()) or _G

    -- Expose Obsidian registries for this run (session-local convenience)
    globalenvironment.Toggles = userinterface.Toggles
    globalenvironment.Options = userinterface.Options
    globalenvironment.Library = userinterface.Library

    ---------------------------------------------------------------------------
    -- Multi-session manager
    ---------------------------------------------------------------------------
    local manager = rawget(globalenvironment, "UISharedManager")
    if not manager then
      manager = { Sessions = {}, Active = nil }
      rawset(globalenvironment, "UISharedManager", manager)
    end

    local function new_guid()
      local uniqueid
      if Services and Services.HttpService then
        pcall(function() uniqueid = Services.HttpService:GenerateGUID(false) end)
      end
      return uniqueid or ("sess_" .. tostring(math.random()) .. "_" .. tostring(os.clock()))
    end

    -- Back-compat upgrade
    if rawget(globalenvironment, "UIShared") and not manager.__upgraded then
      local legacyshareddata = globalenvironment.UIShared
      if type(legacyshareddata) == "table" and not manager.Sessions.legacy then
        manager.Sessions.legacy = legacyshareddata
      end
      manager.__upgraded = true
    end

    local sessionid = new_guid()

    -- Per-session state (dedupe per run)
    local function new_session(identifier)
      local session = {
        Id = identifier,
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
        Find = function(self, elementkind, storagekey)
          elementkind = string.lower(elementkind)
          local bucket = self.Elements[elementkind]
          return bucket and bucket[storagekey] or nil
        end,
      }
      return session
    end

    local sharedsessionstate = new_session(sessionid)
    manager.Sessions[sessionid] = sharedsessionstate
    manager.Active = sessionid
    globalenvironment.UIShared = sharedsessionstate
    globalenvironment.UISharedSessionId = sessionid

    ---------------------------------------------------------------------------
    -- Utilities
    ---------------------------------------------------------------------------
    local function clone(tabletoclone)
      if type(tabletoclone) ~= "table" then return tabletoclone end
      local newtable = {}; for key, value in pairs(tabletoclone) do newtable[key] = value end; return newtable
    end

    local function id_or_text_key(elementkind, identifier, configuration, textfallback)
      if type(identifier) == "string" and identifier ~= "" then return identifier end
      local fallbacktext = textfallback or (type(configuration) == "table" and configuration.Text)
      if type(fallbacktext) == "string" and fallbacktext ~= "" then return "__name__:" .. fallbacktext end
      return nil
    end

    local function remember(elementkind, storagekey, elementreference)
      if not storagekey then return end
      sharedsessionstate.Elements[elementkind][storagekey] = elementreference
      cleanupmaid:GiveTask(function()
        if sharedsessionstate.Elements[elementkind][storagekey] == elementreference then
          sharedsessionstate.Elements[elementkind][storagekey] = nil
        end
      end)
    end

    local function attach_OnChanged(elementreference, callbackfunction)
      if type(callbackfunction) ~= "function" or type(elementreference) ~= "table" then return end
      if type(elementreference.OnChanged) == "function" then
        local success, connection = pcall(function() return elementreference:OnChanged(callbackfunction) end)
        if success and connection then cleanupmaid:GiveTask(connection) end
      end
    end

    local function was_host_method_patched(hostobject, methodname)
      local patchedmethodsmap = sharedsessionstate._patched.hosts[hostobject]
      if patchedmethodsmap and patchedmethodsmap[methodname] then return true end
      patchedmethodsmap = patchedmethodsmap or {}; patchedmethodsmap[methodname] = true
      sharedsessionstate._patched.hosts[hostobject] = patchedmethodsmap
      return false
    end

    ---------------------------------------------------------------------------
    -- Host patchers (KeyPicker / ColorPicker / Button)
    ---------------------------------------------------------------------------
    local function patch_keypicker_host(hostobject)
      if type(hostobject) ~= "table" or type(hostobject.AddKeyPicker) ~= "function" or was_host_method_patched(hostobject, "AddKeyPicker") then
        return
      end
      local originalfunction = hostobject.AddKeyPicker
      hostobject.AddKeyPicker = function(self, identifier, configuration)
        configuration = configuration or {}
        local storagekey = id_or_text_key("keybind", identifier, configuration, configuration.Text)
        if storagekey and sharedsessionstate.Elements.keybind[storagekey] then
          local existingelement = sharedsessionstate.Elements.keybind[storagekey]
          if type(configuration.Callback) == "function" and existingelement.OnClick then
            local success1, connection1 = pcall(function() return existingelement:OnClick(configuration.Callback) end)
            if success1 and connection1 then cleanupmaid:GiveTask(connection1) end
          end
          if type(configuration.ChangedCallback) == "function" and existingelement.OnChanged then
            local success2, connection2 = pcall(function() return existingelement:OnChanged(configuration.ChangedCallback) end)
            if success2 and connection2 then cleanupmaid:GiveTask(connection2) end
          end
          if type(configuration.Clicked) == "function" and existingelement.OnClick then
            local success3, connection3 = pcall(function() return existingelement:OnClick(configuration.Clicked) end)
            if success3 and connection3 then cleanupmaid:GiveTask(connection3) end
          end
          return existingelement
        end
        local keybindelement = originalfunction(self, identifier, configuration)
        if storagekey then remember("keybind", storagekey, keybindelement) end
        return keybindelement
      end
      cleanupmaid:GiveTask(function() hostobject.AddKeyPicker = originalfunction end)
    end

    local function patch_colorpicker_host(hostobject)
      if type(hostobject) ~= "table" or type(hostobject.AddColorPicker) ~= "function" or was_host_method_patched(hostobject, "AddColorPicker") then
        return
      end
      local originalfunction = hostobject.AddColorPicker
      hostobject.AddColorPicker = function(self, identifier, configuration)
        configuration = configuration or {}
        local storagekey = id_or_text_key("colorpicker", identifier, configuration, configuration.Title)
        if storagekey and sharedsessionstate.Elements.colorpicker[storagekey] then
          attach_OnChanged(sharedsessionstate.Elements.colorpicker[storagekey], (configuration.Callback or configuration.Changed))
          return sharedsessionstate.Elements.colorpicker[storagekey]
        end
        local colorpickerelement = originalfunction(self, identifier, configuration)
        if storagekey then remember("colorpicker", storagekey, colorpickerelement) end
        return colorpickerelement
      end
      cleanupmaid:GiveTask(function() hostobject.AddColorPicker = originalfunction end)
    end

    local function patch_button_host(hostobject)
      if type(hostobject) ~= "table" or type(hostobject.AddButton) ~= "function" or was_host_method_patched(hostobject, "AddButton") then
        return
      end
      local originalfunction = hostobject.AddButton
      hostobject.AddButton = function(self, argument1, argument2)
        local configuration, buttontext, buttonfunction
        if type(argument1) == "table" then
          configuration = clone(argument1); buttontext, buttonfunction = configuration.Text, configuration.Func
        else
          buttontext, buttonfunction = argument1, argument2
        end
        local storagekey = id_or_text_key("button", nil, configuration, buttontext)
        if storagekey and sharedsessionstate.Elements.button[storagekey] then
          if type(buttonfunction) == "function" then
            local signalinstance = sharedsessionstate.ButtonSignals[storagekey]
            if signalinstance then
              local success, connection = pcall(function() return signalinstance:Connect(buttonfunction) end)
              if success and connection then cleanupmaid:GiveTask(connection) end
            end
          end
          return sharedsessionstate.Elements.button[storagekey]
        end
        local signalinstance = Signal.new()
        sharedsessionstate.ButtonSignals[storagekey or ("__btn__:" .. tostring(self))] = signalinstance
        cleanupmaid:GiveTask(function()
          signalinstance:Destroy()
          sharedsessionstate.ButtonSignals[storagekey or ("__btn__:" .. tostring(self))] = nil
        end)
        if type(buttonfunction) == "function" then
          local success, connection = pcall(function() return signalinstance:Connect(buttonfunction) end)
          if success and connection then cleanupmaid:GiveTask(connection) end
        end
        local function eventaggregator(...)
          local arguments = table.pack(...)
          local success, errormessage = pcall(function()
            signalinstance:Fire(table.unpack(arguments, 1, arguments.n))
          end)
          if not success then warn(errormessage) end
        end
        local newelement
        if configuration then
          configuration.Func = eventaggregator
          newelement = originalfunction(self, configuration)
        else
          newelement = originalfunction(self, buttontext, eventaggregator)
        end
        if storagekey then remember("button", storagekey, newelement) end
        patch_button_host(newelement) -- nested buttons
        return newelement
      end
      cleanupmaid:GiveTask(function() hostobject.AddButton = originalfunction end)
    end

    ---------------------------------------------------------------------------
    -- Groupbox patcher: wrap ALL adders per docs (and index by title)
    ---------------------------------------------------------------------------
    local function already_patched_groupbox(groupbox)
      if sharedsessionstate._patched.groupboxes[groupbox] then return true end
      sharedsessionstate._patched.groupboxes[groupbox] = true
      return false
    end

    local function patch_groupbox(groupbox)
      if type(groupbox) ~= "table" or already_patched_groupbox(groupbox) then return end

      -- Label
      if type(groupbox.AddLabel) == "function" then
        local originalfunction = groupbox.AddLabel
        groupbox.AddLabel = function(self, argument1, argument2)
          local identifier, configuration, labeltext
          if type(argument1) == "string" and type(argument2) == "table" then
            identifier, configuration, labeltext = argument1, argument2, argument2.Text
          elseif type(argument1) == "table" then
            identifier, configuration, labeltext = nil, argument1, argument1.Text
          else
            identifier, configuration, labeltext = nil, { Text = argument1, DoesWrap = argument2 }, argument1
          end
          local storagekey = id_or_text_key("label", identifier, configuration, labeltext)
          if storagekey and sharedsessionstate.Elements.label[storagekey] then
            return sharedsessionstate.Elements.label[storagekey]
          end
          local newelement = originalfunction(self, argument1, argument2)
          if storagekey then remember("label", storagekey, newelement) end
          patch_keypicker_host(newelement)
          patch_colorpicker_host(newelement)
          return newelement
        end
        cleanupmaid:GiveTask(function() groupbox.AddLabel = originalfunction end)
      end

      -- Button
      if type(groupbox.AddButton) == "function" then
        local originalfunction = groupbox.AddButton
        groupbox.AddButton = function(self, argument1, argument2)
          local configuration, buttontext, buttonfunction
          if type(argument1) == "table" then
            configuration = clone(argument1); buttontext, buttonfunction = configuration.Text, configuration.Func
          else
            buttontext, buttonfunction = argument1, argument2
          end
          local storagekey = id_or_text_key("button", nil, configuration, buttontext)
          if storagekey and sharedsessionstate.Elements.button[storagekey] then
            if type(buttonfunction) == "function" then
              local signalinstance = sharedsessionstate.ButtonSignals[storagekey]
              if signalinstance then
                local success, connection = pcall(function() return signalinstance:Connect(buttonfunction) end)
                if success and connection then cleanupmaid:GiveTask(connection) end
              end
            end
            return sharedsessionstate.Elements.button[storagekey]
          end
          local signalinstance = Signal.new()
          sharedsessionstate.ButtonSignals[storagekey or ("__btn__:" .. tostring(self))] = signalinstance
          cleanupmaid:GiveTask(function()
            signalinstance:Destroy()
            sharedsessionstate.ButtonSignals[storagekey or ("__btn__:" .. tostring(self))] = nil
          end)
          if type(buttonfunction) == "function" then
            local success, connection = pcall(function() return signalinstance:Connect(buttonfunction) end)
            if success and connection then cleanupmaid:GiveTask(connection) end
          end
          local function eventaggregator(...)
            local arguments = table.pack(...)
            local success, errormessage = pcall(function()
              signalinstance:Fire(table.unpack(arguments, 1, arguments.n))
            end)
            if not success then warn(errormessage) end
          end
          local newelement
          if configuration then
            configuration.Func = eventaggregator
            newelement = originalfunction(self, configuration)
          else
            newelement = originalfunction(self, buttontext, eventaggregator)
          end
          if storagekey then remember("button", storagekey, newelement) end
          patch_button_host(newelement)
          return newelement
        end
        cleanupmaid:GiveTask(function() groupbox.AddButton = originalfunction end)
      end

      -- Toggle
      if type(groupbox.AddToggle) == "function" then
        local originalfunction = groupbox.AddToggle
        groupbox.AddToggle = function(self, identifier, configuration)
          configuration = configuration or {}
          local storagekey = id_or_text_key("toggle", identifier, configuration, configuration.Text)
          if storagekey and sharedsessionstate.Elements.toggle[storagekey] then
            attach_OnChanged(sharedsessionstate.Elements.toggle[storagekey], configuration.Callback)
            return sharedsessionstate.Elements.toggle[storagekey]
          end
          local newelement = originalfunction(self, identifier, configuration)
          if storagekey then remember("toggle", storagekey, newelement) end
          patch_keypicker_host(newelement)
          patch_colorpicker_host(newelement)
          return newelement
        end
        cleanupmaid:GiveTask(function() groupbox.AddToggle = originalfunction end)
      end

      -- Checkbox
      if type(groupbox.AddCheckbox) == "function" then
        local originalfunction = groupbox.AddCheckbox
        groupbox.AddCheckbox = function(self, identifier, configuration)
          configuration = configuration or {}
          local storagekey = id_or_text_key("checkbox", identifier, configuration, configuration.Text)
          if storagekey and sharedsessionstate.Elements.checkbox[storagekey] then
            attach_OnChanged(sharedsessionstate.Elements.checkbox[storagekey], configuration.Callback)
            return sharedsessionstate.Elements.checkbox[storagekey]
          end
          local newelement = originalfunction(self, identifier, configuration)
          if storagekey then remember("checkbox", storagekey, newelement) end
          patch_keypicker_host(newelement)
          patch_colorpicker_host(newelement)
          return newelement
        end
        cleanupmaid:GiveTask(function() groupbox.AddCheckbox = originalfunction end)
      end

      -- Input
      if type(groupbox.AddInput) == "function" then
        local originalfunction = groupbox.AddInput
        groupbox.AddInput = function(self, identifier, configuration)
          configuration = configuration or {}
          local storagekey = id_or_text_key("input", identifier, configuration, configuration.Text)
          if storagekey and sharedsessionstate.Elements.input[storagekey] then
            attach_OnChanged(sharedsessionstate.Elements.input[storagekey], configuration.Callback)
            return sharedsessionstate.Elements.input[storagekey]
          end
          local newelement = originalfunction(self, identifier, configuration)
          if storagekey then remember("input", storagekey, newelement) end
          return newelement
        end
        cleanupmaid:GiveTask(function() groupbox.AddInput = originalfunction end)
      end

      -- Slider
      if type(groupbox.AddSlider) == "function" then
        local originalfunction = groupbox.AddSlider
        groupbox.AddSlider = function(self, identifier, configuration)
          configuration = configuration or {}
          local storagekey = id_or_text_key("slider", identifier, configuration, configuration.Text)
          if storagekey and sharedsessionstate.Elements.slider[storagekey] then
            attach_OnChanged(sharedsessionstate.Elements.slider[storagekey], configuration.Callback)
            return sharedsessionstate.Elements.slider[storagekey]
          end
          local newelement = originalfunction(self, identifier, configuration)
          if storagekey then remember("slider", storagekey, newelement) end
          return newelement
        end
        cleanupmaid:GiveTask(function() groupbox.AddSlider = originalfunction end)
      end

      -- Dropdown
      if type(groupbox.AddDropdown) == "function" then
        local originalfunction = groupbox.AddDropdown
        groupbox.AddDropdown = function(self, identifier, configuration)
          configuration = configuration or {}
          local storagekey = id_or_text_key("dropdown", identifier, configuration, configuration.Text)
          if storagekey and sharedsessionstate.Elements.dropdown[storagekey] then
            attach_OnChanged(sharedsessionstate.Elements.dropdown[storagekey], configuration.Callback)
            return sharedsessionstate.Elements.dropdown[storagekey]
          end
          local newelement = originalfunction(self, identifier, configuration)
          if storagekey then remember("dropdown", storagekey, newelement) end
          return newelement
        end
        cleanupmaid:GiveTask(function() groupbox.AddDropdown = originalfunction end)
      end

      -- Divider
      if type(groupbox.AddDivider) == "function" then
        local originalfunction = groupbox.AddDivider
        groupbox.AddDivider = function(self, ...)
          local newelement = originalfunction(self, ...)
          local uniqueid = Services.HttpService and Services.HttpService:GenerateGUID(false) or tostring(newelement)
          remember("divider", uniqueid, newelement)
          return newelement
        end
        cleanupmaid:GiveTask(function() groupbox.AddDivider = originalfunction end)
      end

      -- Viewport
      if type(groupbox.AddViewport) == "function" then
        local originalfunction = groupbox.AddViewport
        groupbox.AddViewport = function(self, identifier, configuration)
          configuration = configuration or {}
          local storagekey = id_or_text_key("viewport", identifier, configuration, configuration.Title)
          if storagekey and sharedsessionstate.Elements.viewport[storagekey] then
            return sharedsessionstate.Elements.viewport[storagekey]
          end
          local newelement = originalfunction(self, identifier, configuration)
          if storagekey then remember("viewport", storagekey, newelement) end
          return newelement
        end
        cleanupmaid:GiveTask(function() groupbox.AddViewport = originalfunction end)
      end

      -- Image
      if type(groupbox.AddImage) == "function" then
        local originalfunction = groupbox.AddImage
        groupbox.AddImage = function(self, identifier, configuration)
          configuration = configuration or {}
          local storagekey = id_or_text_key("image", identifier, configuration, configuration.Text)
          if storagekey and sharedsessionstate.Elements.image[storagekey] then
            return sharedsessionstate.Elements.image[storagekey]
          end
          local newelement = originalfunction(self, identifier, configuration)
          if storagekey then remember("image", storagekey, newelement) end
          return newelement
        end
        cleanupmaid:GiveTask(function() groupbox.AddImage = originalfunction end)
      end

      -- Video
      if type(groupbox.AddVideo) == "function" then
        local originalfunction = groupbox.AddVideo
        groupbox.AddVideo = function(self, identifier, configuration)
          configuration = configuration or {}
          local storagekey = id_or_text_key("video", identifier, configuration, configuration.Text)
          if storagekey and sharedsessionstate.Elements.video[storagekey] then
            return sharedsessionstate.Elements.video[storagekey]
          end
          local newelement = originalfunction(self, identifier, configuration)
          if storagekey then remember("video", storagekey, newelement) end
          return newelement
        end
        cleanupmaid:GiveTask(function() groupbox.AddVideo = originalfunction end)
      end

      -- UI Passthrough
      if type(groupbox.AddUIPassthrough) == "function" then
        local originalfunction = groupbox.AddUIPassthrough
        groupbox.AddUIPassthrough = function(self, identifier, configuration)
          configuration = configuration or {}
          local storagekey = id_or_text_key("uipass", identifier, configuration, configuration.Title)
          if storagekey and sharedsessionstate.Elements.uipass[storagekey] then
            return sharedsessionstate.Elements.uipass[storagekey]
          end
          local newelement = originalfunction(self, identifier, configuration)
          if storagekey then remember("uipass", storagekey, newelement) end
          return newelement
        end
        cleanupmaid:GiveTask(function() groupbox.AddUIPassthrough = originalfunction end)
      end

      -- Index by title
      if type(groupbox.Title) == "string" and groupbox.Title ~= "" then
        remember("groupbox", "__name__:" .. groupbox.Title, groupbox)
      end
    end

    ---------------------------------------------------------------------------
    -- Tabbox patcher (AddTab dedupe → Groupbox)
    ---------------------------------------------------------------------------
    local function already_patched_tabbox(tabbox)
      if sharedsessionstate._patched.tabboxes[tabbox] then return true end
      sharedsessionstate._patched.tabboxes[tabbox] = true
      return false
    end

    local function patch_tabbox(tabbox)
      if type(tabbox) ~= "table" or already_patched_tabbox(tabbox) then return end

      if type(tabbox.AddTab) == "function" then
        local originalfunction = tabbox.AddTab
        tabbox.AddTab = function(self, title)
          local tabmap = sharedsessionstate._tabboxTabs[self]
          if not tabmap then tabmap = {}; sharedsessionstate._tabboxTabs[self] = tabmap end

          if type(title) == "string" and title ~= "" then
            local existingelement = tabmap[title]
            if existingelement then
              patch_groupbox(existingelement)
              return existingelement
            end
          end

          local groupboxelement = originalfunction(self, title)
          patch_groupbox(groupboxelement)

          if type(title) == "string" and title ~= "" then
            tabmap[title] = groupboxelement
            if not sharedsessionstate.Elements.groupbox["__name__:" .. title] then
              remember("groupbox", "__name__:" .. title, groupboxelement)
            end
          end
          return groupboxelement
        end
        cleanupmaid:GiveTask(function() tabbox.AddTab = originalfunction end)
      end

      if type(tabbox.Title) == "string" and tabbox.Title ~= "" then
        remember("tabbox", "__name__:" .. tabbox.Title, tabbox)
      end
    end

    ---------------------------------------------------------------------------
    -- Tabs patchers (via CANONICAL proxy)
    ---------------------------------------------------------------------------
    local function already_patched_tab(tabobject)
      if sharedsessionstate._patched.tabs[tabobject] then return true end
      sharedsessionstate._patched.tabs[tabobject] = true
      return false
    end

    local function per_tab_maps(tabobject)
      local groupboxmap = sharedsessionstate._perTab.groupboxes[tabobject]
      if not groupboxmap then groupboxmap = {}; sharedsessionstate._perTab.groupboxes[tabobject] = groupboxmap end
      local tabboxmap = sharedsessionstate._perTab.tabboxes[tabobject]
      if not tabboxmap then tabboxmap = {}; sharedsessionstate._perTab.tabboxes[tabobject] = tabboxmap end
      return groupboxmap, tabboxmap
    end

    local function patch_tab(tabobject, tabname)
      if type(tabobject) ~= "table" or already_patched_tab(tabobject) then return end
      local groupboxmap, tabboxmap = per_tab_maps(tabobject)

      -- AddLeftGroupbox(title, icon?)
      if type(tabobject.AddLeftGroupbox) == "function" then
        local originalfunction = tabobject.AddLeftGroupbox
        tabobject.AddLeftGroupbox = function(self, title, icon, ...)
          if type(title) == "string" and title ~= "" then
            local existingelement = groupboxmap[title]
            if existingelement then
              patch_groupbox(existingelement)
              return existingelement
            end
          end
          local groupboxelement = originalfunction(self, title, icon, ...)
          patch_groupbox(groupboxelement)
          if type(title) == "string" and title ~= "" then
            groupboxmap[title] = groupboxelement
            if not sharedsessionstate.Elements.groupbox["__name__:" .. title] then
              remember("groupbox", "__name__:" .. title, groupboxelement)
            end
          end
          return groupboxelement
        end
        cleanupmaid:GiveTask(function() tabobject.AddLeftGroupbox = originalfunction end)
      end

      -- AddRightGroupbox(title, icon?)
      if type(tabobject.AddRightGroupbox) == "function" then
        local originalfunction = tabobject.AddRightGroupbox
        tabobject.AddRightGroupbox = function(self, title, icon, ...)
          if type(title) == "string" and title ~= "" then
            local existingelement = groupboxmap[title]
            if existingelement then
              patch_groupbox(existingelement)
              return existingelement
            end
          end
          local groupboxelement = originalfunction(self, title, icon, ...)
          patch_groupbox(groupboxelement)
          if type(title) == "string" and title ~= "" then
            groupboxmap[title] = groupboxelement
            if not sharedsessionstate.Elements.groupbox["__name__:" .. title] then
              remember("groupbox", "__name__:" .. title, groupboxelement)
            end
          end
          return groupboxelement
        end
        cleanupmaid:GiveTask(function() tabobject.AddRightGroupbox = originalfunction end)
      end

      -- AddLeftTabbox(title, icon?)
      if type(tabobject.AddLeftTabbox) == "function" then
        local originalfunction = tabobject.AddLeftTabbox
        tabobject.AddLeftTabbox = function(self, title, icon, ...)
          if type(title) == "string" and title ~= "" then
            local existingelement = tabboxmap[title]
            if existingelement then
              patch_tabbox(existingelement)
              return existingelement
            end
          end
          local tabboxelement = originalfunction(self, title, icon, ...)
          patch_tabbox(tabboxelement)
          if type(title) == "string" and title ~= "" then
            tabboxmap[title] = tabboxelement
            if not sharedsessionstate.Elements.tabbox["__name__:" .. title] then
              remember("tabbox", "__name__:" .. title, tabboxelement)
            end
          end
          return tabboxelement
        end
        cleanupmaid:GiveTask(function() tabobject.AddLeftTabbox = originalfunction end)
      end

      -- AddRightTabbox(title, icon?)
      if type(tabobject.AddRightTabbox) == "function" then
        local originalfunction = tabobject.AddRightTabbox
        tabobject.AddRightTabbox = function(self, title, icon, ...)
          if type(title) == "string" and title ~= "" then
            local existingelement = tabboxmap[title]
            if existingelement then
              patch_tabbox(existingelement)
              return existingelement
            end
          end
          local tabboxelement = originalfunction(self, title, icon, ...)
          patch_tabbox(tabboxelement)
          if type(title) == "string" and title ~= "" then
            tabboxmap[title] = tabboxelement
            if not sharedsessionstate.Elements.tabbox["__name__:" .. title] then
              remember("tabbox", "__name__:" .. title, tabboxelement)
            end
          end
          return tabboxelement
        end
        cleanupmaid:GiveTask(function() tabobject.AddRightTabbox = originalfunction end)
      end

      if type(tabname) == "string" and tabname ~= "" then
        remember("tab", "__name__:" .. tabname, tabobject)
      end
    end

    -- === Canonical Tabs Proxy ===
    local rawtabs = userinterface.Tabs
    local canonicaltabs = {}
    local canonicalmetatable = {}

    canonicalmetatable.__index = function(_, key)
      local cachedelement = sharedsessionstate._canonicalTabs[key]
      if cachedelement then return cachedelement end
      local rawelement = rawtabs and rawtabs[key]
      if rawelement == nil then return nil end
      if type(rawelement) == "table" then
        patch_tab(rawelement, key)
      end
      sharedsessionstate._canonicalTabs[key] = rawelement
      return rawelement
    end

    canonicalmetatable.__pairs = function()
      local keylist = {}
      for key in pairs(rawtabs or {}) do table.insert(keylist, key) end
      local index = 0
      return function()
        index = index + 1
        local key = keylist[index]
        if not key then return end
        return key, canonicaltabs[key]
      end
    end

    canonicalmetatable.__len = function()
      local count = 0
      for _ in pairs(rawtabs or {}) do count = count + 1 end
      return count
    end

    setmetatable(canonicaltabs, canonicalmetatable)

    -- swap tabs reference to the canonical proxy
    local originaltabs = userinterface.Tabs
    userinterface.Tabs = canonicaltabs
    globalenvironment.Tabs  = canonicaltabs

    -- touch each existing key once to patch & cache
    for tabname in pairs(originaltabs or {}) do
      local _ = canonicaltabs[tabname]
    end

    ---------------------------------------------------------------------------
    -- Session Stop (unload)
    ---------------------------------------------------------------------------
    local function Stop()
      userinterface.Tabs = originaltabs
      globalenvironment.Tabs  = userinterface.Tabs
      cleanupmaid:DoCleaning()
      local managerinstance = rawget(globalenvironment, "UISharedManager")
      if managerinstance and managerinstance.Sessions then
        managerinstance.Sessions[sessionid] = nil
        if managerinstance.Active == sessionid then
          local nextsessionid
          for loopsessionid, _ in pairs(managerinstance.Sessions) do nextsessionid = loopsessionid; break end
          managerinstance.Active = nextsessionid
          globalenvironment.UIShared = nextsessionid and managerinstance.Sessions[nextsessionid] or nil
          globalenvironment.UISharedSessionId = nextsessionid
        end
      end
    end

    return { Name = "UIRegistry", Stop = Stop }
  end
end
