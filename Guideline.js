You are converting/creating a Roblox Lua script as a module for my repo. Follow these rules exactly.

ARCHITECTURE (READ FIRST)
• Entry: main.lua sets _G.RepoBase and _G.ObsidianRepoBase, fetches loader.lua, then mounts modules under /modules in order.
• UI: loader.lua constructs an Obsidian window + Tabs and passes a UI context into every mounted module:
  UI = { Library, Tabs, Options, Toggles }.
• Global UI Registry: modules/_ui_registry.lua is mounted FIRST. It wraps Obsidian "Add*" calls to:
  – store every created element globally; 
  – deduplicate per session by ID (or Text for some types); 
  – if an element already exists, return the existing instance and append any new callbacks.
  – The registry is MULTI‑SESSION: each execution has its own session.
• Global accessors exposed:
  getgenv().Options  -- Obsidian Options registry
  getgenv().Toggles  -- Obsidian Toggles registry
  getgenv().Tabs     -- Tabs table from loader
  getgenv().Library  -- Obsidian library instance
  getgenv().UIShared -- Active session registry { Elements, ButtonSignals, Find(kind, key) }
  getgenv().UISharedManager -- { Sessions[sessionId] = UIShared, Active = sessionId }
  getgenv().UISharedSessionId -- ID of the current session
• Dependencies (load remotely from _G.RepoBase):
  Services = loadstring(game:HttpGet(_G.RepoBase.."dependency/Services.lua"))()
  Maid     = loadstring(game:HttpGet(_G.RepoBase.."dependency/Maid.lua"))()
  Signal   = loadstring(game:HttpGet(_G.RepoBase.."dependency/Signal.lua"))()

HARD REQUIREMENTS
1) Do NOT change how Obsidian elements are created. Call sites MUST remain exactly like the docs:
   Groupbox:AddToggle("MyToggle", { Text = "...", Default = false, Callback = function(v) ... end })
   Groupbox:AddSlider("MySlider",  { ... })
   Groupbox:AddDropdown("MyDrop",  { ... })
   Groupbox:AddInput("MyInput",    { ... })
   Groupbox:AddButton("Label", function() ... end)  -- or AddButton({ Text="...", Func=function() ... end })
   ToggleOrLabel:AddKeyPicker("MyBind", { ... })
   ToggleOrLabel:AddColorPicker("MyColor", { ... })
   etc.
   The registry wraps these at runtime. You must NOT implement your own dedupe layer.
2) CLEANUP: Every connection, thread, instance, callback, and temporary state MUST be registered with a Maid and torn down in Stop().
3) NO global pollution (other than reading getgenv() values above). Use locals; return a small API.
4) SAFETY: Do not add ToS‑violating or exploitative behavior. If an executor‑specific API is optional, feature‑detect gracefully.

MODULE FILE SHAPE (MANDATORY)
• Location: modules/<lower_snake_or_lowercase_name>.lua
• Exact wrapper:
do
  return function(UI)
    local Services = loadstring(game:HttpGet(_G.RepoBase.."dependency/Services.lua"), "@Services.lua")()
    local Maid     = loadstring(game:HttpGet(_G.RepoBase.."dependency/Maid.lua"), "@Maid.lua")()
    -- (Signal only if needed)
    local Vars = {
      Maids   = { Main = Maid.new() },
      Enabled = false,
      -- put feature state/backups here
    }

    -- Start(): establish connections, guards, and apply effects
    local function Start()
      if Vars.Enabled then return end
      Vars.Enabled = true
      -- connect events; store all in Vars.Maids.Main via :GiveTask(...)
      -- apply properties and store backups for restoration in Stop()
    end

    -- Stop(): disconnect & restore EVERYTHING
    local function Stop()
      if not Vars.Enabled then return end
      Vars.Enabled = false
      Vars.Maids.Main:DoCleaning()
      -- restore any changed properties to backups
    end

    -- Build UI under an existing tab (UI.Tabs.EXP, .Dupe, .Visuals, .Misc, .Debug, .Settings)
    local group = UI.Tabs.Misc:AddLeftGroupbox("<Readable Title>")
    -- Create controls with STABLE IDs so other modules can reuse them:
    --  (If the same ID is used elsewhere in THIS session, registry returns the same instance and
    --   adds this module's Callback via OnChanged/OnClick automatically.)
    local Toggle = group:AddToggle("my_feature_enabled", {
      Text = "Enable My Feature",
      Default = false,
      Callback = function(on)
        if on then Start() else Stop() end
      end,
    })

    -- (Add more controls as needed, always with stable IDs.)

    return { Name = "<ModuleName>", Stop = Stop }
  end
end

UI & REGISTRY USAGE RULES (VERY IMPORTANT)
• Stable IDs: For any element that accepts an ID (toggle/checkbox/input/slider/dropdown/keybind/colorpicker/viewport/image/video/ui‑passthrough), choose a short, stable, unique string (e.g., "modname_feature_toggle").
• Buttons & Labels dedupe by Text when no ID is available; use consistent Text if you intend reuse.
• Reusing an element from another module is automatic:
  – Simply call the same Add* with the SAME ID (or SAME Text for Button/Label) and pass your Callback.
  – The registry will return the existing element and append your Callback using the element’s documented .OnChanged/.OnClick hook.
• Reading/writing existing elements without re‑creating:
  local Toggles = getgenv().Toggles
  local Options = getgenv().Options
  if Toggles and Toggles.my_feature_enabled then
    Toggles.my_feature_enabled:SetValue(true)
  end
  -- Or use the active session registry for arbitrary lookups:
  local UIShared = getgenv().UIShared
  local dd = UIShared and UIShared:Find("dropdown", "my_drop_id")
• Multi‑session semantics:
  – Each run gets a new session. Reuse/dedupe happens only within the CURRENT session.
  – getgenv().UIShared points to the active session for THIS run; all your lookups/creations should assume the current session.
  – Do NOT retain references across unloads/reruns; reacquire via getgenv().UIShared, Toggles, or Options during Start().

CLEANUP PATTERN (MANDATORY)
• Register every connection / coroutine / task with Vars.Maids.Main:GiveTask(...)
  Examples to register:
  - RBXScriptConnections (e.g., RunService.Heartbeat:Connect)
  - Temporary Instances (call :Destroy in a wrapper)
  - Signals and custom callbacks (disconnect/Destroy)
  - Any hooked state that must be reverted
• In Stop(): Vars.Maids.Main:DoCleaning() and restore all changed properties (camera, humanoid, lighting, sounds, materials, etc.).
• Avoid hard waits in hot paths. Use RunService (Heartbeat/RenderStepped) and guard logic.

EXECUTOR‑AWARENESS (IF NEEDED)
• If you rely on optional executor APIs (e.g., hookfunction, getconnections), feature‑detect:
  if typeof(hookfunction) ~= "function" then warn("hookfunction unavailable; disabling X"); return end
• Always degrade gracefully without errors.

PERFORMANCE & UX
• Prefer O(1) work per frame; chunk heavy traversals across multiple frames if needed.
• Debounce/guard expensive callbacks.
• Use Obsidian notifications/settings sparingly and respect its keybind menu toggle.

DELIVERABLES
1) The final module file (modules/<name>.lua) following the required shape.
2) The module must:
   - Use _G.RepoBase to load Services/Maid (and Signal only if needed).
   - Build UI using UI.Tabs.* and Groupbox:Add* calls with stable IDs.
   - Use the Callback on controls to start/stop or update live state.
   - Clean up everything via Maid in Stop().
   - Return { Name = "<ModuleName>", Stop = Stop }.
3) DO NOT modify loader.lua or modules/_ui_registry.lua or how existing modules call Obsidian.

OPTIONAL EXAMPLES YOU MAY USE
• Attach to an existing toggle created elsewhere (same ID):
  group:AddToggle("my_feature_enabled", {
    Text = "Enable My Feature",
    Callback = function(on) if on then Start() else Stop() end end,
  })
  -- If the toggle already exists in this session, the registry returns it and appends this Callback.

• Use an existing Option directly:
  local Options = getgenv().Options
  if Options and Options.speed_mult then
    Options.speed_mult:SetValue(2)
  end

QUALITY CHECKLIST (AUTHOR MUST SELF‑VERIFY)
[ ] File shape: do return function(UI) ... return {Name, Stop} end end
[ ] Imports Services + Maid (Signal only if needed)
[ ] Uses stable IDs for all elements; relies on automatic dedupe via registry
[ ] No custom global state; no edits to Obsidian or loader
[ ] Start/Stop present; all resources registered to Maid and cleaned
[ ] Works across reruns (multi‑session); does not hold stale references
[ ] Graceful degradation if optional APIs are missing
[ ] No ToS‑violating behavior added
