-- main.lua
do
    local GlobalEnv = (getgenv and getgenv()) or _G
    GlobalEnv.RepoBase = "https://raw.githubusercontent.com/ratware-exe/repo/main/"
    GlobalEnv.ObsidianRepoBase = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"

    -- (Keep _G in sync just in case)
    _G.RepoBase = GlobalEnv.RepoBase
    _G.ObsidianRepoBase = GlobalEnv.ObsidianRepoBase

    local loader = loadstring(game:HttpGet(GlobalEnv.RepoBase .. "loader.lua"), "@loader.lua")()

    local featurePaths = {
        -- If you split Shield out earlier, put it first:
        "modules/Shield.lua",
        "modules/VIPServerCommands.lua",
        "modules/InfZoom.lua",
        "modules/AntiAFK.lua",
        "modules/Optimization.lua",
    }

    for i = 1, #featurePaths do
        loader.MountModule(featurePaths[i])
    end
end
