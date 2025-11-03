-- dependency/Signal.lua
do
    local Signal = {}
    Signal.__index = Signal
    Signal.ClassName = "Signal"

    function Signal.new()
        local newSignal = setmetatable({}, Signal)
        newSignal.SignalBindableEvent = Instance.new("BindableEvent")
        newSignal.SignalArgData = nil
        newSignal.SignalArgCount = nil
        return newSignal
    end

    function Signal.isSignal(object)
        return typeof(object) == "table" and getmetatable(object) == Signal
    end

    function Signal:Fire(...)
        self.SignalArgData = { ... }
        self.SignalArgCount = select("#", ...)
        self.SignalBindableEvent:Fire()
        self.SignalArgData = nil
        self.SignalArgCount = nil
    end

    function Signal:Connect(handler)
        if not self.SignalBindableEvent then
            error("Signal has been destroyed")
        end
        if type(handler) ~= "function" then
            error(("connect(%s)"):format(typeof(handler)), 2)
        end
        return self.SignalBindableEvent.Event:Connect(function()
            handler(table.unpack(self.SignalArgData, 1, self.SignalArgCount))
        end)
    end

    function Signal:Wait()
        self.SignalBindableEvent.Event:Wait()
        assert(self.SignalArgData, "Missing arg data")
        return table.unpack(self.SignalArgData, 1, self.SignalArgCount)
    end

    function Signal:Destroy()
        if self.SignalBindableEvent then
            self.SignalBindableEvent:Destroy()
            self.SignalBindableEvent = nil
        end
        self.SignalArgData = nil
        self.SignalArgCount = nil
    end

    return Signal
end
