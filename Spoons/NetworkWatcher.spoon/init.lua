local CF4 = '1.1.1.1'
local CF6 = '2606:4700:4700::1111'
local CURL4_ARGS = { '-4', '-f', '-m 10', 'https://cloudflare.com/cdn-cgi/trace' }
local CURL6_ARGS = { '-6', '-f', '-m 10', 'https://cloudflare.com/cdn-cgi/trace' }
local NIL_TRACE = {
  colo = nil,
  ip = nil,
  loc = nil,
}

local obj = {
  prev_menubar_data = {},
  prev_trace4 = NIL_TRACE,
  prev_trace6 = NIL_TRACE,
}

-- use logger.d("log message")
local logger = hs.logger.new('NetWatcher', 'debug')
local menubar = hs.menubar.new()

function obj:update_menubar(trace4, trace6)
  local dns = obj:get_dns_server()
  -- table keys needed for encoding, fails as unkeyed arr
  local menubar_data = {
    dns = dns,
    trace4 = trace4,
    trace6 = trace6,
  }
  -- rerender only if data has changed
  if hs.json.encode(menubar_data) ~= hs.json.encode(obj.prev_menubar_data) then
    obj:render_menubar(trace4, trace6, dns)
    obj.prev_menubar_data = menubar_data
  end
end

function obj:has_ip(trace4, trace6)
  trace4 = trace4 or obj.prev_trace4
  trace6 = trace6 or obj.prev_trace6
  return trace4.ip ~= nil or trace6.ip ~= nil
end

function obj:render_menubar(trace4, trace6, dns)
  local rect = hs.geometry.rect(0, 0, 30, 16) -- 24 may be max height
  local canvas = hs.canvas.new(rect)
  local is_loc_mismatch = trace4.loc and trace6.loc and trace4.loc ~= trace6.loc
  local display_loc = (is_loc_mismatch and '‼️') or trace4.loc or trace6.loc or '✕'
  canvas[1] = {
    text = hs.styledtext.new(
      display_loc,
      {
        font = { name = 'SF Pro Display', size = 20,  },
        color = { alpha = (obj:has_ip(trace4, trace6) and HIGH_ALPHA) or LOW_ALPHA, white = 1 },
        paragraphStyle = { alignment = "center", lineBreak = "clip", maximumLineHeight = 20 }
      }
    ),
    type = "text"
  }
  -- menubar:returnToMenuBar()
  menubar:setIcon(canvas:imageFromCanvas())
  -- https://www.gitmemory.com/issue/Hammerspoon/hammerspoon/2741/792564885
  canvas = nil

  menubar:setMenu({
    { title = string.format("%s %s %s", trace4.loc, trace4.colo, trace4.ip), disabled = not trace4.ip, fn = function() hs.pasteboard.setContents(trace4.ip) end },
    { title = string.format("%s %s %s", trace6.loc, trace6.colo, trace6.ip), disabled = not trace6.ip, fn = function() hs.pasteboard.setContents(trace6.ip) end },
    { title = string.format("DNS %s", dns), disabled = true },
    { title = string.format("%.1f W", hs.battery.watts()), disabled = true },
  })
end

function obj:get_dns_server()
  return hs.execute('scutil --dns | grep "nameserver\\[0\\]" | head -1 | sed "s/.*: \\(.*\\)/\\1/"')
end

function obj:notify(trace4, trace6, prev4, prev6)
  if obj:has_ip(trace4, trace6) then
    local is_loc_new = prev4.loc ~= trace4.loc or prev6.loc ~= trace6.loc
    if is_loc_new then
      local alert_text = string.format("4 6: %s %s » %s %s", prev4.loc, prev6.loc, trace4.loc, trace6.loc)
      hs.alert.show(alert_text, nil, nil, 3)
    elseif not obj:is_ip_similar(prev4.ip, trace4.ip) or not obj:is_ip_similar(prev6.ip, trace6.ip) then
      local title = (is_loc_new and string.format("%s connection", trace4.loc or trace6.loc)) or nil
      local diff4 = (prev4.colo ~= trace4.colo and string.format("%s » %s", prev4.colo, trace4.colo)) or (prev4.ip ~= trace4.ip and string.format("%s » %s", prev4.ip, trace4.ip)) or nil
      local diff6 = (prev6.colo ~= trace6.colo and string.format("%s » %s", prev6.colo, trace6.colo)) or (prev6.ip ~= trace6.ip and string.format("%s » %s", prev6.ip, trace6.ip)) or nil
      local text = ""
      if diff4 then text = text .. "4: " .. diff4 end
      if diff6 then text = text .. "6: " .. diff6 end
      hs.notify.new({
        title = title,
        informativeText = text,
        withdrawAfter = 3
      }):send()
    end
    obj.prev_trace4 = trace4
    obj.prev_trace6 = trace6
  else
    obj.trace_timer:setNextTrigger(5)
  end
  obj:update_menubar(trace4, trace6)
end

-- compare first 4 parts of ip to ignore local ipv6 changes
function obj:is_ip_similar(str1, str2)
  if str1 == str2 then return true end
  if not str1 or not str2 then return false end
  local common_str = ""
  for i = 1, #str1 do
    if str1:sub(i, i) ~= str2:sub(i, i) then
      common_str = str1:sub(1, i - 1)
      break
    end
  end
  local t = {}
  for hex in string.gmatch(common_str, "%x+") do table.insert(t, hex) end
  return #t >= 4
end

function obj:trace_to_table(str)
  local trace = {}
  local lines = hs.fnutils.split(str, "\n")
  for line_no, line in ipairs(lines) do
    local kv = hs.fnutils.split(line, "=")
    if (kv[1]) then trace[kv[1]] = kv[2] end
  end
  return trace
end

function obj:curl_trace(curl_args, callback)
  hs.task.new(
    '/usr/bin/curl',
    function(exit_code, stdout, stderr)
      local trace = (exit_code == 0 and obj:trace_to_table(stdout)) or NIL_TRACE
      callback(trace)
    end,
    curl_args
  ):start()
end

-- pass from trace4 to trace6 then menu
function obj:refresh_trace4()
  if not is_reachable(CF4) then
    return obj:refresh_trace6(NIL_TRACE)
  end
  obj:curl_trace(
    CURL4_ARGS,
    function(trace4)
      obj:refresh_trace6(trace4)
    end
  )
end

function obj:refresh_trace6(trace4)
  if not is_reachable(CF6) then
    return obj:notify(trace4, NIL_TRACE, obj.prev_trace4, obj.prev_trace6)
  end
  obj:curl_trace(
    CURL6_ARGS,
    function(trace6)
      obj:notify(trace4, trace6, obj.prev_trace4, obj.prev_trace6)
    end
  )
end

function obj:reach_callback(reach_obj, flags)
  obj.trace_timer:setNextTrigger(1)
end

function obj:start()
  obj.trace_timer = hs.timer.new(60, obj.refresh_trace4)
  obj.trace_timer:start():fire()
  obj.reach_listener = hs.network.reachability.internet():setCallback(obj.reach_callback):start()
end

return obj
