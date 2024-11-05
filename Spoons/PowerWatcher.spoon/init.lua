local obj = {}

-- use logger.d("log message")
local logger = hs.logger.new('PowerWatch', 'debug')

function obj:start()
  obj.watcher = hs.caffeinate.watcher.new(function(event)
    -- logger.d(hs.caffeinate.watcher[event])
    local is_device_idle = not hs.audiodevice.defaultOutputDevice():inUse()
    local is_mute_event = event == hs.caffeinate.watcher.screensDidLock
    if is_device_idle and is_mute_event then
      hs.audiodevice.defaultOutputDevice():setVolume(0)
    end
  end)
  obj.watcher:start()
end

return obj
