-- main.lua
do
    _G.RepoBase = "https://raw.githubusercontent.com/YourUser/YourRepo/main/"
    _G.ObsidianRepoBase = "https://raw.githubusercontent.com/WFYBGG/Obsidian/main/"

    local loader = loadstring(game:HttpGet(_G.RepoBase .. "loader.lua"), "@loader.lua")()

    local featurePaths = {
        "modules/VIPServerCommands.lua",
        "modules/InfZoom.lua",
        "modules/AntiAFK.lua",
        "modules/UltraAFK.lua",
    }

    for pathIndex = 1, #featurePaths do
        loader.MountModule(featurePaths[pathIndex])
    end
end
