-- dependency/UIRegistry.lua
do
  return function(UI)
    local G = (getgenv and getgenv()) or _G

    --------------------------------------------------------------------------
    -- Global, SIMPLE cache (shared across modules/runs in this session)
    --------------------------------------------------------------------------
    local R = rawget(G, "UIShared")
    if not R then
      R = {
        Tabs        = {}, -- key: winKey(title)         -> Tab
        Groupboxes  = {}, -- key: key(tab, title)       -> Groupbox
        Tabboxes    = {}, -- key: key(tab, title)       -> Tabbox
        TabboxTabs  = {}, -- key: key(tabbox, title)    -> Groupbox (inside tabbox)
        -- Convenience lookup
        Find = function(self, kind, owner, title)
          if kind == "tab" then
            return self.Tabs[(owner and tostring(owner) or "win") .. "\0" .. tostring(title)]
          elseif kind == "groupbox" then
            return self.Groupboxes[tostring(owner) .. "\0" .. tostring(title)]
          elseif kind == "tabbox" then
            return self.Tabboxes[tostring(owner) .. "\0" .. tostring(title)]
          elseif kind == "tabbox_tab" then
            return self.TabboxTabs[tostring(owner) .. "\0" .. tostring(title)]
          end
        end
      }
      rawset(G, "UIShared", R)
    end

    --------------------------------------------------------------------------
    -- Helpers (super small)
    --------------------------------------------------------------------------
    local function title_from_first_arg(...)
      local a1 = ...
      if type(a1) == "table" then
        return a1.Title or a1.Name or a1.Text
      end
      return a1
    end

    local function key(owner, title)
      return tostring(owner) .. "\0" .. tostring(title)
    end

    local function win_key(win, title)
      return (tostring(win) or "win") .. "\0" .. tostring(title)
    end

    --------------------------------------------------------------------------
    -- Interceptors (only wrap adders; forward all args; no element mutation)
    --------------------------------------------------------------------------
    local Restores = {}

    local PatchedTabs     = setmetatable({}, { __mode = "k" })
    local PatchedTabboxes = setmetatable({}, { __mode = "k" })
    local PatchedWindows  = setmetatable({}, { __mode = "k" })

    local function patch_tabbox(tb)
      if type(tb) ~= "table" or PatchedTabboxes[tb] then return end
      PatchedTabboxes[tb] = true

      if type(tb.AddTab) == "function" then
        local orig = tb.AddTab
        tb.AddTab = function(self, ...)
          local t = title_from_first_arg(...)
          if t then
            local k = key(self, t)
            local existing = R.TabboxTabs[k]
            if existing then return existing end
            local gb = orig(self, ...) -- forward icon/extra args untouched
            R.TabboxTabs[k] = gb
            return gb
          end
          return orig(self, ...)
        end
        table.insert(Restores, function() tb.AddTab = orig end)
      end
    end

    local function patch_tab(tab)
      if type(tab) ~= "table" or PatchedTabs[tab] then return end
      PatchedTabs[tab] = true

      -- Groupboxes (Left/Right)
      for _, mname in ipairs({ "AddLeftGroupbox", "AddRightGroupbox" }) do
        local orig = tab[mname]
        if type(orig) == "function" then
          tab[mname] = function(self, ...)
            local t = title_from_first_arg(...)
            if t then
              local k = key(self, t)
              local existing = R.Groupboxes[k]
              if existing then return existing end
              local gb = orig(self, ...) -- forward icon/extra args untouched
              R.Groupboxes[k] = gb
              return gb
            end
            return orig(self, ...)
          end
          table.insert(Restores, function() tab[mname] = orig end)
        end
      end

      -- Tabboxes (Left/Right)
      for _, mname in ipairs({ "AddLeftTabbox", "AddRightTabbox" }) do
        local orig = tab[mname]
        if type(orig) == "function" then
          tab[mname] = function(self, ...)
            local t = title_from_first_arg(...)
            if t then
              local k = key(self, t)
              local existing = R.Tabboxes[k]
              if existing then return existing end
              local tb = orig(self, ...) -- forward icon/extra args untouched
              R.Tabboxes[k] = tb
              patch_tabbox(tb) -- ensure inner AddTab is intercepted
              return tb
            end
            local tb = orig(self, ...)
            patch_tabbox(tb)
            return tb
          end
          table.insert(Restores, function() tab[mname] = orig end)
        end
      end
    end

    local function patch_window(win)
      if type(win) ~= "table" or PatchedWindows[win] then return end
      PatchedWindows[win] = true

      if type(win.AddTab) == "function" then
        local orig = win.AddTab
        win.AddTab = function(self, ...)
          local t = title_from_first_arg(...)
          if t then
            local k = win_key(self, t)
            local existing = R.Tabs[k]
            if existing then return existing end
            local tab = orig(self, ...) -- forward icon/extra args untouched
            R.Tabs[k] = tab
            patch_tab(tab)
            -- Keep UI.Tabs table populated under the same string key if present
            if type(UI.Tabs) == "table" and UI.Tabs[t] == nil then
              UI.Tabs[t] = tab
            end
            return tab
          end
          local tab = orig(self, ...)
          patch_tab(tab)
          return tab
        end
        table.insert(Restores, function() win.AddTab = orig end)
      end
    end

    --------------------------------------------------------------------------
    -- Apply to what's already there, and catch future additions
    --------------------------------------------------------------------------
    -- Patch any existing tabs
    for _, tab in pairs(UI.Tabs or {}) do
      patch_tab(tab)
    end

    -- Try to patch the Window (so future AddTab calls are intercepted)
    local window = rawget(UI, "Window")
                   or (UI.Library and (UI.Library.Window or UI.Library.MainWindow))
    if window then
      patch_window(window)
    end

    -- As a fallback, if new tabs get assigned into UI.Tabs later, intercept them
    if type(UI.Tabs) == "table" then
      local mt = getmetatable(UI.Tabs) or {}
      local prev_newindex = mt.__newindex
      mt.__newindex = function(t, k, v)
        if prev_newindex then prev_newindex(t, k, v) else rawset(t, k, v) end
        if type(v) == "table" then patch_tab(v) end
      end
      setmetatable(UI.Tabs, mt)
      table.insert(Restores, function() mt.__newindex = prev_newindex end)
    end

    --------------------------------------------------------------------------
    -- Minimal module contract
    --------------------------------------------------------------------------
    local function Stop()
      for i = #Restores, 1, -1 do
        local ok, err = pcall(Restores[i])
        if not ok then warn(err) end
      end
    end

    return { Name = "UIRegistry", Stop = Stop }
  end
end
