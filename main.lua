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
    "modules/universal/errorsuppressor.lua",
    -- converted modules from prompt.lua:
    "modules/universal/speedhack.lua",
    "modules/universal/flight.lua",
    "modules/universal/noclip.lua",
    "modules/wfyb/infinitestamina.lua",
    "modules/universal/attachtoback.lua",
    "modules/wfyb/teleport.lua",
    "modules/wfyb/gyroscope.lua",
    "modules/wfyb/playeresp.lua",
    "modules/wfyb/proximityarrows.lua",
    "modules/wfyb/boatesp.lua",
    "modules/universal/fullbright.lua",
    "modules/universal/nosky.lua",
    "modules/universal/nofog.lua",

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
    "modules/universal/playeresp.lua",
    "modules/wfyb/vipservercommands.lua",
    "modules/universal/infinitezoom.lua",
    "modules/universal/antiafk.lua",
    "modules/universal/optimization.lua",
    "modules/universal/clientnamespoofer.lua",
    "modules/universal/debugtools.lua",
}

    for i = 1, #featurePaths do
        loader.MountModule(featurePaths[i])
    end
end
