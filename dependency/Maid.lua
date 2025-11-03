-- dependency/Maid.lua
do
    local GlobalEnv = (getgenv and getgenv()) or _G

    -- Prefer an existing Signal from either environment
    local Signal = rawget(GlobalEnv, "Signal") or rawget(_G, "Signal")
    if not Signal then
        -- Accept RepoBase from either environment
        local repoBase = rawget(GlobalEnv, "RepoBase") or rawget(_G, "RepoBase")
        assert(type(repoBase) == "string" and #repoBase > 0,
            "Set _G.RepoBase or getgenv().RepoBase before loading Maid.lua")
        Signal = loadstring(game:HttpGet(repoBase .. "dependency/Signal.lua"), "@Signal.lua")()
        GlobalEnv.Signal = Signal -- cache for subsequent loads
    end

    local Maid = {}
    Maid.ClassName = "Maid"

    function Maid.new()
        return setmetatable({ MaidTasks = {} }, Maid)
    end

    function Maid.isMaid(value)
        return type(value) == "table" and value.ClassName == "Maid"
    end

    function Maid.__index(self, index)
        if Maid[index] ~= nil then
            return Maid[index]
        end
        return self.MaidTasks[index]
    end

    function Maid:__newindex(index, newTask)
        if Maid[index] ~= nil then
            error(("'%s' is reserved"):format(tostring(index)), 2)
        end
        local tasksTable = self.MaidTasks
        local oldTask = tasksTable[index]
        if oldTask == newTask then return end
        tasksTable[index] = newTask
        if oldTask then
            if type(oldTask) == "function" then
                oldTask()
            elseif typeof(oldTask) == "RBXScriptConnection" then
                oldTask:Disconnect()
            elseif type(oldTask) == "table" and oldTask.Remove then
                oldTask:Remove()
            elseif Signal.isSignal(oldTask) then
                oldTask:Destroy()
            elseif typeof(oldTask) == "thread" then
                task.cancel(oldTask)
            elseif oldTask.Destroy then
                oldTask:Destroy()
            end
        end
    end

    function Maid:GiveTask(taskObject)
        if not taskObject then
            error("Task cannot be false or nil", 2)
        end
        local taskId = #self.MaidTasks + 1
        self[taskId] = taskObject
        return taskId
    end

    function Maid:DoCleaning()
        local tasksTable = self.MaidTasks
        for key, conn in pairs(tasksTable) do
            if typeof(conn) == "RBXScriptConnection" then
                tasksTable[key] = nil
                conn:Disconnect()
            end
        end
        local nextKey, nextTask = next(tasksTable)
        while nextTask ~= nil do
            tasksTable[nextKey] = nil
            if type(nextTask) == "function" then
                nextTask()
            elseif typeof(nextTask) == "RBXScriptConnection" then
                nextTask:Disconnect()
            elseif type(nextTask) == "table" and nextTask.Remove then
                nextTask:Remove()
            elseif Signal.isSignal(nextTask) then
                nextTask:Destroy()
            elseif typeof(nextTask) == "thread" then
                task.cancel(nextTask)
            elseif nextTask.Destroy then
                nextTask:Destroy()
            end
            nextKey, nextTask = next(tasksTable)
        end
    end

    Maid.Destroy = Maid.DoCleaning
    return Maid
end
