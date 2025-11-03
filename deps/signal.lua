-- signal.lua
-- Quenty-style Signal with Aztup-quality safety checks.
-- - Arguments are stored & replayed to avoid Roblox deep-copy issues.
-- - :Connect() guard if destroyed (prevents respawn/UI-inject races).
-- - :Once(), :Wait(), :Destroy() included.
-- MIT-style, no external deps.

local Signal = {}
Signal.__index = Signal
Signal.ClassName = "Signal"

--- Constructs a new signal
function Signal.new()
    local self = setmetatable({}, Signal)
    self.SignalBindableEvent = Instance.new("BindableEvent")
    self.SignalArgData = nil
    self.SignalArgCount = nil -- Prevent edge case of :Fire("A", nil) → "A"
    return self
end

--- Type guard compatible with Maid
function Signal.isSignal(object)
    return type(object) == "table" and getmetatable(object) == Signal
end

--- Fire the event with the given arguments. All handlers will be invoked.
function Signal:Fire(...)
    -- Reuse arg array to avoid allocation churn
    self.SignalArgData = table.pack(...)
    self.SignalArgCount = self.SignalArgData.n
    -- Fire without args; listeners read stored args (prevents deep copy of tables)
    if self.SignalBindableEvent then
        self.SignalBindableEvent:Fire()
    end
end

--- Connect a handler
function Signal:Connect(handler)
    -- Aztup fix: guard connects after Destroy to avoid edge cases on respawn
    if not self.SignalBindableEvent then
        return error("Signal has been destroyed; cannot Connect()", 2)
    end
    if type(handler) ~= "function" then
        error(("Connect(%s)"):format(typeof(handler)), 2)
    end
    return self.SignalBindableEvent.Event:Connect(function()
        -- Replay last fired args
        handler(table.unpack(self.SignalArgData, 1, self.SignalArgCount))
    end)
end

--- Connect once
function Signal:Once(handler)
    if type(handler) ~= "function" then
        error(("Once(%s)"):format(typeof(handler)), 2)
    end
    local connection; connection = self:Connect(function(...)
        if connection then connection:Disconnect() end
        handler(...)
    end)
    return connection
end

--- Wait for :Fire(), return the arguments it was given
function Signal:Wait()
    -- Wait for the bindable to fire
    if not self.SignalBindableEvent then
        error("Signal has been destroyed; cannot Wait()", 2)
    end
    self.SignalBindableEvent.Event:Wait()
    -- Mirror Aztup’s guard against TweenSize/TweenPosition thread ref corruption
    assert(self.SignalArgData, "Missing arg data (Tween* may have corrupted thread refs)")
    return table.unpack(self.SignalArgData, 1, self.SignalArgCount)
end

--- Disconnect all listeners and void the signal
function Signal:Destroy()
    if self.SignalBindableEvent then
        self.SignalBindableEvent:Destroy()
        self.SignalBindableEvent = nil
    end
    self.SignalArgData = nil
    self.SignalArgCount = nil
end

return Signal
