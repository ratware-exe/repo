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
        -- If you split Shield out earlier, put it first:
        "modules/shield.lua",
        "modules/propexp.lua",
        "modules/autoflame.lua",
        "modules/multiflame.lua",
        "modules/repairall.lua",
        "modules/repairself.lua",
        "modules/repairteam.lua",
        "modules/pvpmode.lua",
        "modules/blockpopup.lua",
        "modules/transfermoney.lua",
        "modules/crashserver.lua",
        "modules/debugtools.lua",
        "modules/playeresp.lua",
        "modules/vipservercommands.lua",
        "modules/infinitezoom.lua",
        "modules/antiafk.lua",
        "modules/optimization.lua",
        "modules/clientnamespoofer.lua",
    }

    for i = 1, #featurePaths do
        loader.MountModule(featurePaths[i])
    end
end
