local obj = {}

-- use logger.d("log message")
local logger = hs.logger.new('PowerWatch', 'debug')

local function is_mute_event(event)
  return event == hs.caffeinate.watcher.systemWillPowerOff or event == hs.caffeinate.watcher.systemWillSleep
end

function obj:start()
  obj.watcher = hs.caffeinate.watcher.new(function(event)
    if hs.audiodevice.defaultOutputDevice():inUse() then
      return
    end
    if is_mute_event(event) then
      hs.audiodevice.defaultOutputDevice():setVolume(0)
    end
  end)
  obj.watcher:start()
end

return obj
