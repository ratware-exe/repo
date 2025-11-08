-- main.lua
do
    local GlobalEnv = (getgenv and getgenv()) or _G
    GlobalEnv.RepoBase = "https://raw.githubusercontent.com/ratware-exe/repo/main/"
    --GlobalEnv.ObsidianRepoBase = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
    GlobalEnv.ObsidianRepoBase = "https://raw.githubusercontent.com/WFYBGG/Obsidian/main/"

    -- (Keep _G in sync just in case)
    _G.RepoBase = GlobalEnv.RepoBase
    _G.ObsidianRepoBase = GlobalEnv.ObsidianRepoBase

    local loader = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "loader.lua"), "@loader.lua")()

local featurePaths = {
    "dependency/UIRegistry.lua",
    "modules/universal/debug/errorsuppressor.lua",
    "modules/wfyb/acbypass/sightoverseer.lua",
    "modules/wfyb/acbypass/lighting.lua",
    -- Movement / Bypass / Teleport / Vehicle tools
    "modules/universal/movement/speedhack.lua",
    "modules/universal/movement/fly.lua",
    "modules/universal/movement/noclip.lua",
    "modules/wfyb/bypass/infinitestamina.lua",
    "modules/wfyb/bypass/underwater.lua",
    "modules/wfyb/bypass/fireanyangle.lua",
    "modules/wfyb/bypass/firethroughwalls.lua",
    "modules/universal/rage/attachtoback.lua",
    "modules/universal/travel/teleportcframe.lua",
    "modules/universal/travel/teleportplayer.lua",
    "modules/wfyb/teleportboat.lua",
    "modules/wfyb/gyroscope.lua",
    "modules/universal/notifier/moderatordetection.lua",
    
    -- ESP & Visuals
    "modules/backup/playeresp.lua",
    "modules/backup/proximityarrows.lua",
    "modules/wfyb/boatesp.lua",
    "modules/universal/visual/fullbright.lua",
    "modules/universal/visual/nosky.lua",
    "modules/universal/visual/nofog.lua",
        
    -- your existing WFYB-specific and universal modules:
    "modules/wfyb/shield.lua",
    "modules/wfyb/propexp.lua",
    "modules/wfyb/autoflame.lua",
    "modules/wfyb/repairall.lua",
    "modules/wfyb/repairself.lua",
    "modules/wfyb/repairteam.lua",
    "modules/wfyb/blockpopup.lua",
    "modules/wfyb/transfermoney.lua",
    "modules/wfyb/crashserver.lua",
    "modules/universal/visual/playeresp.lua",
    "modules/wfyb/vipservercommands.lua",
    "modules/universal/miscellaneous/infinitezoom.lua",
    "modules/universal/miscellaneous/antiafk.lua",
    "modules/universal/miscellaneous/optimization.lua",
    "modules/universal/miscellaneous/clientnamespoofer.lua",
    "modules/universal/debug/debugtools.lua",
}

    for i = 1, #featurePaths do
        loader.MountModule(featurePaths[i])
    end
end
