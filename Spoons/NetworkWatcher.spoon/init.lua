local MINIMUM_REACHABLE_FLAG = 1
local NIL_TRACE = {
  colo = nil,
  ip = nil,
  loc = nil,
}
local LOW_ALPHA = 0.3

local obj = {
  prev_menubar_data = {},
  prev_trace = NIL_TRACE,
  use_dhcp_dns = false,
}

local logger = hs.logger.new('NetWatcher', 'debug')
menubar = hs.menubar.new()

function obj:menubar_data()
  local trace = obj.prev_trace
  menubar_data = {
    canvas_text_1 = string.format("%s", trace.loc or '✕'),
    canvas_text_2 = obj:is_external_dns() and 'EXT' or 'DHCP',
    menu_1_title = string.format("IP %s %s", trace.ip, trace.colo),
    menu_2_title = string.format("DNS %s", obj:get_dns_server()),
    menu_3_checked = obj.use_dhcp_dns == true,
  }
  return menubar_data
end

function obj:update_menubar()
  local menubar_data = obj:menubar_data()
  if hs.json.encode(menubar_data) ~= hs.json.encode(obj.prev_menubar_data) then
    -- logger.d(menubar_data.menu_1_title)
    obj:render_menubar(menubar_data)
  end
end

function obj:has_ip()
  return obj.prev_trace.ip ~= nil
end

function obj:render_menubar(menubar_data)
  local rect = hs.geometry.rect(0, 0, 30, 22) -- 24 is max height
  local canvas = hs.canvas.new(rect)
  canvas[1] = {
    text = hs.styledtext.new(
      menubar_data.canvas_text_1,
      {
        font = { name = 'SF Pro', size = 16 },
        color = { alpha = (obj:has_ip() and 0.9) or LOW_ALPHA, white = 1 },
        paragraphStyle = { alignment = "center", lineBreak = "clip", maximumLineHeight = 17 }
      }
    ),
    type = "text"
  }
  canvas[2] = {
    text = hs.styledtext.new(
      menubar_data.canvas_text_2,
      {
        font = { name = 'SF Pro', size = 8 },
        color = { alpha = (obj:has_ip() and 0.6) or LOW_ALPHA, white = 1 },
        paragraphStyle = { alignment = "center", lineBreak = "clip", minimumLineHeight = 23 }
      }
    ),
    type = "text"
  }
  -- menubar:returnToMenuBar()
  menubar:setIcon(canvas:imageFromCanvas())
  -- https://www.gitmemory.com/issue/Hammerspoon/hammerspoon/2741/792564885
  local canvas = nil

  menubar:setMenu({
    { title = menubar_data.menu_1_title, disabled = true },
    { title = menubar_data.menu_2_title, disabled = true },
    { title = "Use DHCP DNS", checked = menubar_data.menu_3_checked, fn = function() obj:toggle_dhcp_dns() end },
  })
  
  obj.prev_menubar_data = menubar_data
end

function obj:get_dns_server()
  return hs.execute('scutil --dns | grep "nameserver\\[0\\]" | head -1 | sed "s/.*: \\(.*\\)/\\1/"')
end

function obj:toggle_dhcp_dns()
  obj.use_dhcp_dns = not obj.use_dhcp_dns
  if obj.use_dhcp_dns then
    obj:set_dhcp_dns()
  else
    obj:set_external_dns()
  end
  obj:update_menubar()
end

function obj:notify(trace)
  local text = string.format(
    "%s %s » %s %s\n%s » %s",
    obj.prev_trace.loc,
    obj.prev_trace.colo,
    trace.loc,
    trace.colo,
    obj.prev_trace.ip,
    trace.ip
  )
  local notification = hs.notify.new({
    title = string.format("%s connection", trace.loc),
    informativeText = text,
    withdrawAfter = 10
  })
  local alert_text = string.format(
    "%s » %s",
    obj.prev_trace.loc,
    trace.loc
  )
  hs.alert.show(alert_text, nil, nil, 3)
  notification:send()
end

function obj:is_external_dns()
  local found = hs.execute('networksetup -getdnsservers Wi-Fi'):find('1.1.1.1')
  -- logger.d(found)
  return found ~= nil
end

function obj:check_external_dns_accessible(upgrade)
  --'/usr/bin/dig @1.1.1.1 +retry=0 +short +time=1 google.com; echo $?'
  hs.task.new(
    '/usr/bin/dig',
    function(exit_code, stdout, stderr)
      local is_external_dns_accessible = exit_code == 0
      -- logger.d(obj.is_external_dns_accessible)
      if not obj.use_dhcp_dns then
        if not is_external_dns_accessible then
          hs.notify.new({
            title = 'Switching to DHCP DNS',
            informativeText = 'External DNS inaccessible',
            withdrawAfter = 10
          }):send()
          obj:toggle_dhcp_dns()
        elseif upgrade then
          obj:set_external_dns()
        end
      end
    end,
    { '@1.1.1.1', '+retry=0', '+short', '+time=1', 'google.com' }
  ):start()
end

function obj:set_dhcp_dns()
  if obj:is_external_dns() then
    hs.execute('sudo /usr/local/bin/wifi_dns_dhcp.sh')
    return true
  else
    return false
  end
end

function obj:set_external_dns(force)
  if force or not obj:is_external_dns() then
    hs.execute('sudo /usr/local/bin/wifi_dns_spec.sh')
    return true
  else
    return false
  end
end

function obj:is_network_reachable(status)
  status = status or hs.network.reachability.internet():status()
  return status >= MINIMUM_REACHABLE_FLAG
end

function obj:refresh_trace()
  -- logger.d('refresh_trace')
  hs.http.asyncGet(
    'https://cloudflare.com/cdn-cgi/trace',
    nil,
    function(status, body_str, headers)
      -- logger.d(status)
      local trace = {}
      if (status == 200) then
        local lines = hs.fnutils.split(body_str, "\n")
        for line_no, line in ipairs(lines) do
          local kv = hs.fnutils.split(line, "=")
          if (kv[1]) then trace[kv[1]] = kv[2] end
        end
      else
        trace = NIL_TRACE
      end
      if (trace.ip ~= obj.prev_trace.ip or trace.loc ~= obj.prev_trace.loc) then
        obj:notify(trace)
      end
      obj.prev_trace = trace
      obj:update_menubar()
    end
  )
end

function obj:reachability_callback(reach_obj, flags)
  reach_obj = reach_obj or hs.network.reachability.internet()
  -- logger.d(reach_obj)
  if obj:is_network_reachable(reach_obj:status()) then
    obj.trace_timer = hs.timer.doEvery(10, obj.refresh_trace)
  else
    if obj.trace_timer then obj.trace_timer:stop() end
  end
end

function obj:start()
  obj:check_external_dns_accessible(true)
  obj:refresh_trace()
  obj.dns_timer = hs.timer.doEvery(10, obj.check_external_dns_accessible)
  obj.trace_timer = hs.timer.doEvery(10, obj.refresh_trace)
  -- obj.reachability = hs.network.reachability.internet():setCallback(obj.reachability_callback):start()
  -- obj:reachability_callback()
end

return obj
