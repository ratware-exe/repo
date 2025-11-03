-- maid.lua
-- Quenty-style Maid with Aztup-compatible behaviors:
-- - __index / __newindex to treat Maid[key] as managed tasks
-- - :GiveTask(), :Remove(), :DoCleaning(), Destroy alias
-- - Cleans: functions(), RBXScriptConnection:Disconnect(), tables:Remove(),
--           threads via task.cancel(), anything with :Destroy()
-- - Includes :GiveSignal() and :LinkToInstance() helpers
-- MIT-style, no external deps.

local Maid = {}
Maid.__index = Maid
Maid.ClassName = "Maid"

-- Internal helper: best-effort Signal detection without importing
local function isLikelySignal(obj)
    return type(obj) == "table"
       and ((obj.ClassName == "Signal") or (type(obj.Connect) == "function" and type(obj.Destroy) == "function"))
end

--- Construct a new Maid
function Maid.new()
    return setmetatable({
        MaidTasks = {} -- key → task
    }, Maid)
end

--- Static type guard
function Maid.isMaid(value)
    return type(value) == "table" and value.ClassName == "Maid"
end

--- Expose maid tasks via indexing
function Maid:__index(index)
    if Maid[index] ~= nil then
        return Maid[index]
    else
        return rawget(self, "MaidTasks")[index]
    end
end

--- Assigning Maid[key] manages the lifecycle of that key
function Maid:__newindex(index, newTask)
    if Maid[index] ~= nil then
        error(("'%s' is reserved"):format(tostring(index)), 2)
    end

    local tasks = rawget(self, "MaidTasks")
    local oldTask = tasks[index]
    if oldTask == newTask then
        return
    end

    tasks[index] = newTask

    -- Cleanup the old task (Aztup ordering & coverage)
    if oldTask then
        if type(oldTask) == "function" then
            oldTask()
        elseif typeof(oldTask) == "RBXScriptConnection" then
            oldTask:Disconnect()
        elseif type(oldTask) == "table" and type(oldTask.Remove) == "function" then
            oldTask:Remove()
        elseif isLikelySignal(oldTask) then
            oldTask:Destroy()
        elseif typeof(oldTask) == "thread" then
            task.cancel(oldTask)
        elseif type(oldTask) == "table" and type(oldTask.Destroy) == "function" then
            oldTask:Destroy()
        end
    end
end

--- Push a task with an auto-incremented numeric key
-- @return taskId (number)
function Maid:GiveTask(task)
    if task == nil then
        error("Task cannot be false or nil", 2)
    end
    local id = #self.MaidTasks + 1
    self[id] = task -- routes through __newindex
    return id
end

--- Add a signal connection as a task (RBXScriptSignal or custom with :Connect)
function Maid:GiveSignal(rbxsig)
    assert(rbxsig and rbxsig.Connect, "Maid:GiveSignal expects a signal with :Connect")
    local connection = rbxsig:Connect(function() end)
    return self:GiveTask(connection)
end

--- Remove a task without cleaning it; returns the task (or nil)
function Maid:Remove(index)
    local tasks = self.MaidTasks
    local task = tasks[index]
    if task ~= nil then
        tasks[index] = nil
    end
    return task
end

--- Compact out nils (useful if you Remove() frequently)
function Maid:Sweep()
    local newTasks = {}
    for k, v in pairs(self.MaidTasks) do
        if v ~= nil then
            newTasks[k] = v
        end
    end
    self.MaidTasks = newTasks
end

--- Link cleanup to an Instance’s lifetime
-- When the instance leaves the tree, the Maid is cleaned.
-- If allowMultiple is false, the instance’s key is replaced on re-link.
function Maid:LinkToInstance(instance, allowMultiple)
    assert(typeof(instance) == "Instance", "Maid:LinkToInstance expects Instance")
    local connection
    connection = instance.AncestryChanged:Connect(function(_, parent)
        if parent == nil then
            if connection then connection:Disconnect() end
            self:DoCleaning()
        end
    end)
    if allowMultiple then
        return self:GiveTask(connection)
    else
        self[instance] = connection
        return connection
    end
end

--- Clean all tasks (Aztup’s two-phase approach: disconnect connections first)
function Maid:DoCleaning()
    local tasks = self.MaidTasks

    -- Phase 1: disconnect connections first (known safe)
    for index, task in pairs(tasks) do
        if typeof(task) == "RBXScriptConnection" then
            tasks[index] = nil
            task:Disconnect()
        end
    end

    -- Phase 2: everything else
    local index, taskData = next(tasks)
    while taskData ~= nil do
        tasks[index] = nil
        if type(taskData) == "function" then
            taskData()
        elseif type(taskData) == "table" and type(taskData.Remove) == "function" then
            taskData:Remove()
        elseif typeof(taskData) == "thread" then
            task.cancel(taskData)
        elseif isLikelySignal(taskData) then
            taskData:Destroy()
        elseif type(taskData) == "table" and type(taskData.Destroy) == "function" then
            taskData:Destroy()
        end
        index, taskData = next(tasks)
    end
end

-- Alias (Quenty/Aztup convention)
Maid.Destroy = Maid.DoCleaning

return Maid
