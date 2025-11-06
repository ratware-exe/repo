-- modules/wfyb/autoflame.lua
do
  return function(UI)
    local Services = loadstring(game:HttpGet(_G.RepoBase.."dependency/Services.lua"), "@Services.lua")()
    local Maid     = loadstring(game:HttpGet(_G.RepoBase.."dependency/Maid.lua"), "@Maid.lua")()

    local Vars = {
      Maids   = { Main = Maid.new() },
      Enabled = false,

      MaxTriggerDistance = 800,
      MaxViewDistance    = 1200,
      LeewayDistance     = 40,
      FireRateHertz      = 15,

      Patched = false,
      WatchedAttachments = {},
      LastPulseTime = 0,
      Accumulated = 0,

      Nevermore = nil,
      ClientBinders = nil,
      LastTrigger = nil,
    }

    local function GetLoader()
      local mod = Services.ReplicatedStorage:FindFirstChild("Nevermore") or Services.ReplicatedStorage:WaitForChild("Nevermore")
      local ok, loader = pcall(require, mod)
      if ok then return loader end
      return nil
    end

    local function EnsureClientBinders()
      if Vars.ClientBinders then return Vars.ClientBinders end
      local L = GetLoader() ; if not L then return nil end
      local ok, binders = pcall(function() return L("ClientBinders") end)
      if ok and binders then Vars.ClientBinders = binders return binders end
      return nil
    end

    local function PatchTriggerConstants()
      local L = GetLoader() ; if not L then return end
      local ok, C = pcall(function() return L("TriggerConstants") end)
      if not (ok and type(C)=="table") then return end
      C.MAX_TRIGGER_DISTANCE = Vars.MaxTriggerDistance
      C.MAX_VIEW_DISTANCE = Vars.MaxViewDistance
      C.LEEWAY_DISTANCE = Vars.LeewayDistance
    end

    local function PatchCooldownStack()
      if Vars.Patched then return end
      local L = GetLoader() ; if not L then return end

      local okS, TCS = pcall(function() return L("TriggerCooldownService") end)
      if okS and TCS then
        local origIs   = TCS.IsGlobalCoolingDown
        local origMark = TCS.MarkGlobalCooldown
        TCS.IsGlobalCoolingDown = function(...) return false end
        TCS.MarkGlobalCooldown  = function(...) end
        Vars.Maids.Main:GiveTask(function()
          TCS.IsGlobalCoolingDown = origIs
          TCS.MarkGlobalCooldown  = origMark
        end)
      end

      local okH, CH = pcall(function() return L("CooldownHelper") end)
      if okH and CH and type(CH.getCooldown)=="function" then
        local origGet = CH.getCooldown
        CH.getCooldown = function(...) return false end
        Vars.Maids.Main:GiveTask(function() CH.getCooldown = origGet end)
      end

      Vars.Patched = true
    end

    local function GetTriggerBinder()
      local L = GetLoader() ; if not L then return nil end
      local ok, binders = pcall(function() return L("ClientBinders") end)
      if not (ok and binders and binders.Trigger) then return nil end
      return binders.Trigger
    end

    local function GetWrappedAttachment(TriggerObject)
      return rawget(TriggerObject, "_obj")
        or rawget(TriggerObject, "Instance")
        or rawget(TriggerObject, "_instance")
        or (typeof(TriggerObject.GetObject) == "function" and TriggerObject:GetObject())
        or nil
    end

    local function IsFlamethrowerTrigger(TriggerObject)
      local attachment = GetWrappedAttachment(TriggerObject)
      if not (attachment and attachment:IsA("Attachment")) then return false end
      local L = GetLoader() ; if not L then return false end
      local ok, C = pcall(function() return L("TriggerConstants") end)
      if not (ok and C) then return false end
      local binders = EnsureClientBinders()
      if not binders or not binders.Flamethrower then return false end

      for _, child in ipairs(attachment:GetChildren()) do
        if child:IsA("ObjectValue") and child.Name == C.TARGET_OBJECT_VALUE_NAME and child.Value then
          local okGet, b = pcall(function() return binders.Flamethrower:Get(child.Value) end)
          if okGet and b then return true end
        end
      end
      return false
    end

    local function NeutralizeCooldown(obj)
      if not obj or not obj.Parent then return end
      if obj.Name ~= "Cooldown" then return end
      task.defer(function()
        if obj and obj.Parent and obj.Name=="Cooldown" then
          obj.Name = "CooldownDisabled"
          pcall(function() obj:SetAttribute("Disabled", true) end)
        end
      end)
    end

    local function WatchAndNeutralize(TriggerObject)
      if not IsFlamethrowerTrigger(TriggerObject) then return end
      local attachment = GetWrappedAttachment(TriggerObject)
      if not (attachment and attachment:IsA("Attachment")) then return end
      if Vars.WatchedAttachments[attachment] then return end

      for _, c in ipairs(attachment:GetChildren()) do
        if c.Name == "Cooldown" then NeutralizeCooldown(c) end
      end
      local conn = attachment.ChildAdded:Connect(function(nc)
        if nc and nc.Name=="Cooldown" then NeutralizeCooldown(nc) end
      end)
      Vars.WatchedAttachments[attachment] = conn
      Vars.Maids.Main:GiveTask(conn)
    end

    local function RefreshTriggers()
      local binder = GetTriggerBinder() ; if not binder then return end
      local ok, list = pcall(function() return binder:GetAll() end)
      if not (ok and type(list)=="table") then return end
      for _, t in ipairs(list) do
        WatchAndNeutralize(t)
      end
    end

    local function SelectFlameTrigger()
      local binder = GetTriggerBinder() ; if not binder then return nil end
      local ok, list = pcall(function() return binder:GetAll() end)
      if not (ok and type(list)=="table") then return nil end

      local flames, preferred = {}, nil
      for _, t in ipairs(list) do
        if IsFlamethrowerTrigger(t) then
          table.insert(flames, t)
          local okP, pref = pcall(function() return t.Preferred and t.Preferred.Value end)
          if okP and pref then preferred = t end
        end
      end
      if #flames == 0 then return nil end
      if Vars.LastTrigger then
        for _, t in ipairs(flames) do
          if t == Vars.LastTrigger then return t end
        end
      end
      return preferred or flames[1]
    end

    local function OnHeartbeat(dt)
      PatchTriggerConstants()
      PatchCooldownStack()

      Vars.Accumulated += dt
      if Vars.Accumulated >= 0.2 then
        Vars.Accumulated = 0
        RefreshTriggers()
      end
      if not Vars.Enabled then return end

      local now = time()
      local minInterval = 1 / math.max(1, Vars.FireRateHertz)
      if now - Vars.LastPulseTime < minInterval then return end
      Vars.LastPulseTime = now

      local trigger = SelectFlameTrigger()
      if trigger then
        Vars.LastTrigger = trigger
        pcall(function() trigger:Activate() end)
      end
    end

    local function Start()
      if Vars.Enabled then return end
      Vars.Enabled = true
      PatchTriggerConstants()
      PatchCooldownStack()
      RefreshTriggers()
      local hb = Services.RunService.Heartbeat:Connect(OnHeartbeat)
      Vars.Maids.Main:GiveTask(hb)
    end

    local function Stop()
      if not Vars.Enabled then return end
      Vars.Enabled = false
      for att, conn in pairs(Vars.WatchedAttachments) do
        if typeof(conn)=="RBXScriptConnection" then pcall(function() conn:Disconnect() end) end
        Vars.WatchedAttachments[att] = nil
      end
      Vars.WatchedAttachments = {}
      Vars.LastTrigger = nil
      Vars.Maids.Main:DoCleaning()
    end

    -- UI
    local group = UI.Tabs.EXP:AddLeftGroupbox("Single Flame")
    group:AddToggle("auto_flame_enabled", {
      Text = "Enable Single Flame",
      Default = false,
      Callback = function(on) if on then Start() else Stop() end end,
    })
    group:AddSlider("auto_flame_rate", {
      Text = "Fire Rate (Hz)",
      Default = Vars.FireRateHertz, Min = 1, Max = 60, Rounding = 0,
      Callback = function(v) Vars.FireRateHertz = math.floor(tonumber(v) or Vars.FireRateHertz) end
    })

    return { Name = "AutoFlame", Stop = Stop }
  end
end
