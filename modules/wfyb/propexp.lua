-- modules/propexp.lua
do
  return function(UI)
    local Services = loadstring(game:HttpGet(_G.RepoBase.."dependency/Services.lua"), "@Services.lua")()
    local Maid     = loadstring(game:HttpGet(_G.RepoBase.."dependency/Maid.lua"), "@Maid.lua")()

    local Vars = {
      Maids   = { Main = Maid.new() },
      Enabled = false,

      -- Config
      IntervalSeconds    = 2.00,
      ResolveTickSeconds = 0.25,
      RetrySeconds       = 0.70,
      RelativeCF         = CFrame.new(0, 1.6, 0),
      BoatSearchTimeout  = 12,
      SpawnYOffset       = 0,

      -- Live
      Nevermore       = nil,
      BoatApi         = nil,
      PropClassProvider = nil,
      ClientBinders   = nil,
      PinkClass       = nil,
      OwnBoatModel    = nil,
    }

    -- === helpers ===
    local function GetOrCreateGroup(tab, side, title)
      local reg = getgenv().UIShared
      local existing = reg and reg.Find and reg:Find("groupbox", title)
      if existing then return existing end
      return (side == "right") and tab:AddRightGroupbox(title) or tab:AddLeftGroupbox(title)
    end

    local function SafeCall(target, methodName, ...)
      local fn = target and target[methodName]
      if type(fn) ~= "function" then return nil end
      local args = { ... }
      local ok, res = pcall(function() return fn(target, table.unpack(args)) end)
      if ok and res ~= nil then return res end
      ok, res = pcall(function() return fn(table.unpack(args)) end)
      if ok and res ~= nil then return res end
      return nil
    end

    local function Round4(n) return math.floor((n or 0) * 10000 + 0.5) / 10000 end
    local function QuantizeCFrame(cf)
      local x,y,z,r00,r01,r02,r10,r11,r12,r20,r21,r22 = cf:GetComponents()
      return CFrame.new(
        Round4(x),Round4(y),Round4(z),
        Round4(r00),Round4(r01),Round4(r02),
        Round4(r10),Round4(r11),Round4(r12),
        Round4(r20),Round4(r21),Round4(r22)
      )
    end

    -- Nevermore
    local function EnsureNevermore()
      if not Vars.Nevermore then
        Vars.Nevermore = require(Services.ReplicatedStorage:WaitForChild("Nevermore"))
      end
      if not Vars.BoatApi then
        Vars.BoatApi = Vars.Nevermore("BoatAPIServiceClient")
      end
      if not Vars.PropClassProvider then
        local okClient, providerClient = pcall(function()
          return Vars.Nevermore("PropClassProviderClient")
        end)
        if okClient and providerClient then
          Vars.PropClassProvider = providerClient
        else
          Vars.PropClassProvider = Vars.Nevermore("PropClassProvider")
        end
      end
      if not Vars.ClientBinders then
        Vars.ClientBinders = Vars.Nevermore("ClientBinders")
      end
    end

    local function BoatsFolder()
      return Services.Workspace:FindFirstChild("Boats")
    end

    local function OwnerUserId(boatModel)
      if not (boatModel and boatModel:IsA("Model")) then return nil end
      local attrs = boatModel:GetAttributes()
      for k, v in pairs(attrs) do
        local l = string.lower(k)
        if l == "owneruserid" or l == "owner" then
          local n = tonumber(v) ; if n then return n end
        end
      end
      local dataFolder = boatModel:FindFirstChild("BoatData")
      if dataFolder then
        for _, c in ipairs(dataFolder:GetChildren()) do
          local l = string.lower(c.Name)
          if c:IsA("IntValue") and string.find(l, "owner") then
            return c.Value
          end
          if c:IsA("ObjectValue") and l == "owner" then
            local plr = c.Value
            if plr and plr.UserId then return plr.UserId end
          end
          if c:IsA("StringValue") and string.find(l, "owner") then
            local n = tonumber(c.Value) ; if n then return n end
          end
        end
      end
      for _, d in ipairs(boatModel:GetDescendants()) do
        if d:IsA("IntValue") and (d.Name == "Owner" or d.Name == "OwnerUserId") then
          return d.Value
        end
      end
      return nil
    end

    local function FindOwnBoat()
      local f = BoatsFolder() ; if not f then return nil end
      for _, m in ipairs(f:GetChildren()) do
        if m:IsA("Model") and OwnerUserId(m) == Services.Players.LocalPlayer.UserId then
          return m
        end
      end
      return nil
    end

    local function SnapshotOwnedBoats(uid)
      local out = {}
      local f = BoatsFolder() ; if not f then return out end
      for _, m in ipairs(f:GetChildren()) do
        if m:IsA("Model") and OwnerUserId(m) == uid then
          out[m] = true
        end
      end
      return out
    end

    local function WaitForNewOwnedBoat(uid, beforeSet, timeout)
      local deadline = time() + (timeout or Vars.BoatSearchTimeout)
      while time() < deadline do
        local f = BoatsFolder()
        if f then
          for _, m in ipairs(f:GetChildren()) do
            if m:IsA("Model") and OwnerUserId(m) == uid and not beforeSet[m] then
              return m
            end
          end
        end
        Services.RunService.Heartbeat:Wait()
      end
      return nil
    end

    local PinkIdCandidates   = { "PinkGyro", "PinkExperimental", "PinkExperimentalBlock", "ExperimentalBlockPink" }
    local PinkTKeyCandidates = { "props.pinkGyro", "props.pinkExperimental", "props.pink_experimental" }

    local function ResolvePinkClass()
      if Vars.PinkClass then return true end
      if not Vars.PropClassProvider then return false end

      for _, id in ipairs(PinkIdCandidates) do
        local class =
          SafeCall(Vars.PropClassProvider, "GetPropClassFromPropId", id) or
          SafeCall(Vars.PropClassProvider, "GetFromPropId", id) or
          SafeCall(Vars.PropClassProvider, "FromPropId", id) or
          SafeCall(Vars.PropClassProvider, "GetPropClass", id) or
          SafeCall(Vars.PropClassProvider, "Get", id)
        if class then Vars.PinkClass = class ; return true end
      end

      for _, tk in ipairs(PinkTKeyCandidates) do
        local class =
          SafeCall(Vars.PropClassProvider, "GetPropClassFromTranslationKey", tk) or
          SafeCall(Vars.PropClassProvider, "GetFromTranslationKey", tk) or
          SafeCall(Vars.PropClassProvider, "FromTranslationKey", tk)
        if class then Vars.PinkClass = class ; return true end
      end
      return false
    end

    local function GetPropBinder(model)
      local ok, binder = pcall(function()
        return Vars.ClientBinders and Vars.ClientBinders.Prop and Vars.ClientBinders.Prop:Get(model)
      end)
      if ok and binder then return binder end
      return nil
    end

    local function ModelWorldCFrame(model)
      local pp = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
      return pp and pp.CFrame or nil
    end

    local function FindNewlyPlacedPink(boatModel, desiredWorld, timeout)
      local deadline = time() + (timeout or 3)
      local bestModel, bestDist = nil, math.huge
      repeat
        for _, child in ipairs(boatModel:GetChildren()) do
          if child:IsA("Model") and GetPropBinder(child) then
            local ln = string.lower(child.Name)
            if string.find(ln, "pink") or string.find(ln, "gyro") or string.find(ln, "experimental") then
              local cf = ModelWorldCFrame(child)
              if cf then
                local d = (cf.Position - desiredWorld.Position).Magnitude
                if d < bestDist then bestModel, bestDist = child, d end
              end
            end
          end
        end
        if bestModel then return bestModel end
        Services.RunService.Heartbeat:Wait()
      until time() > deadline
      return nil
    end

    local function PlaceWithRetry(relativeCF, boatModel)
      local ok = pcall(function()
        Vars.BoatApi:PlacePropOnBoat(Vars.PinkClass, relativeCF, boatModel)
      end)
      if ok then return true end
      task.wait(Vars.RetrySeconds)
      ok = pcall(function()
        Vars.BoatApi:PlacePropOnBoat(Vars.PinkClass, relativeCF, boatModel)
      end)
      return ok or false
    end

    local function EnsureOwnBoat()
      if Vars.OwnBoatModel and Vars.OwnBoatModel.Parent then
        return true
      end

      local existing = FindOwnBoat()
      if existing then
        Vars.OwnBoatModel = existing
        return true
      end

      if not Vars.PinkClass then return false end

      local lp = Services.Players.LocalPlayer
      local character = lp.Character or lp.CharacterAdded:Wait()
      local hrp = character:WaitForChild("HumanoidRootPart")
      local pivot = hrp.CFrame * CFrame.new(0, tonumber(Vars.SpawnYOffset) or 0, 0)

      local beforeSet = SnapshotOwnedBoats(lp.UserId)
      pcall(function()
        Vars.BoatApi:PlaceNewBoat(Vars.PinkClass, pivot)
      end)

      local newBoat = WaitForNewOwnedBoat(lp.UserId, beforeSet, Vars.BoatSearchTimeout)
      if not newBoat then return false end

      local initialProp = FindNewlyPlacedPink(newBoat, pivot, 3)
      if initialProp then pcall(function() Vars.BoatApi:SellProp(initialProp) end) end

      Vars.OwnBoatModel = newBoat
      return true
    end

    local function PlaceAndSellOnce()
      if not (Vars.OwnBoatModel and Vars.PinkClass) then return end
      local relQ = QuantizeCFrame(Vars.RelativeCF or CFrame.new(0, 1.6, 0))
      local desiredWorld = Vars.OwnBoatModel:GetPivot() * relQ

      if not PlaceWithRetry(relQ, Vars.OwnBoatModel) then return end

      local placed = FindNewlyPlacedPink(Vars.OwnBoatModel, desiredWorld, 3)
      if placed then pcall(function() Vars.BoatApi:SellProp(placed) end) end
    end

    -- Lifecycle
    local function Start()
      if Vars.Enabled then return end
      Vars.Enabled = true

      EnsureNevermore()
      if not Vars.PinkClass then ResolvePinkClass() end
      if not Vars.OwnBoatModel then Vars.OwnBoatModel = FindOwnBoat() end

      local th = task.spawn(function()
        while Vars.Enabled do
          if not Vars.PinkClass then
            if not ResolvePinkClass() then
              task.wait(Vars.ResolveTickSeconds)
              continue
            end
          end

          if not EnsureOwnBoat() then
            task.wait(Vars.ResolveTickSeconds)
            continue
          end

          PlaceAndSellOnce()
          task.wait(Vars.IntervalSeconds)
        end
      end)
      Vars.Maids.Main:GiveTask(th)
    end

    local function Stop()
      if not Vars.Enabled then return end
      Vars.Enabled = false
      Vars.Maids.Main:DoCleaning()
    end

    -- === UI (reuse original EXP groupbox) ===
    local group = GetOrCreateGroup(UI.Tabs.EXP, "left", "EXP Farm")

    group:AddToggle("AutoPropEXPToggle", {
      Text = "Prop EXP",
      Default = false,
      Callback = function(on) if on then Start() else Stop() end end,
    })

    -- (extra control; not in original UI)
    group:AddSlider("propexp_interval", {
      Text = "Prop EXP: Interval",
      Default = Vars.IntervalSeconds, Min = 0.2, Max = 5, Rounding = 2, Suffix = "s",
      Callback = function(v) Vars.IntervalSeconds = tonumber(v) or Vars.IntervalSeconds end
    })

    return { Name = "PropEXP", Stop = Stop }
  end
end
