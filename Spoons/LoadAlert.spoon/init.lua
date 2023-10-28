local LOAD_MAX = 3

local obj = {}

local logger = hs.logger.new('LoadAlert', 'debug')

local function check_load()
  -- { 1.81 1.43 1.40 }, 2nd num is 5min avg
  local split = hs.fnutils.split(hs.execute('sysctl -n vm.loadavg'), ' ')
  local load1 = tonumber(split[2])
  local load5 = tonumber(split[3])
  -- logger.d(load5)
  if (load1 > LOAD_MAX and load5 > LOAD_MAX) then
    local notification = hs.notify.new({
      title = "High load",
      informativeText = string.format("%s %s %s", load1, load5, split[4]),
      withdrawAfter = 10
    })
    notification:send()
  end
end

function obj:start()
  check_load()
  obj.timer = hs.timer.doEvery(60*3, check_load)
end

return obj
