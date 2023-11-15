local FONT_NAME = 'SF Pro'
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
  use_dhcp_dns = true, -- prev nil to allow ext upgrade, now true because tailscale dns more or less overrides this
}

-- use logger.d("log message")
local logger = hs.logger.new('NetWatcher', 'debug')
local menubar = hs.menubar.new()

function obj:menubar_data()
  local trace = obj.prev_trace
  menubar_data = {
    canvas_text_1 = string.format("%s", trace.loc or '✕'),
    canvas_text_2 = obj:is_external_dns() and 'EXT' or 'DHCP',
    menu_1_ip = trace.ip,
    menu_2_title = string.format("DNS %s", obj:get_dns_server()),
    menu_3_checked = obj.use_dhcp_dns == true,
  }
  return menubar_data
end

function obj:update_menubar()
  local menubar_data = obj:menubar_data()
  -- rerender only if data has changed
  if hs.json.encode(menubar_data) ~= hs.json.encode(obj.prev_menubar_data) then
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
        font = { name = FONT_NAME, size = 16 },
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
        font = { name = FONT_NAME, size = 8 },
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

  local ip = menubar_data.menu_1_ip
  menubar:setMenu({
    { title = string.format("IP %s %s", ip, obj.prev_trace.colo), fn = function() hs.pasteboard.setContents(ip) end },
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
  local prev_trace = obj.prev_trace
  local text = string.format(
    "%s %s » %s %s\n%s » %s",
    prev_trace.loc,
    prev_trace.colo,
    trace.loc,
    trace.colo,
    prev_trace.ip,
    trace.ip
  )
  local withdrawAfter = 2
  if trace.loc ~= prev_trace.loc then
    local alert_text = string.format(
      "%s » %s",
      prev_trace.loc,
      trace.loc
    )
    hs.alert.show(alert_text, nil, nil, 3)
    withdrawAfter = 10
  end
  hs.notify.new({
    title = string.format("%s connection", trace.loc),
    informativeText = text,
    withdrawAfter = withdrawAfter
  }):send()
end

function obj:is_external_dns()
  local found = hs.execute('networksetup -getdnsservers Wi-Fi'):find('1.1.1.1')
  -- logger.d(found)
  return found ~= nil
end

function obj:check_external_dns_accessible()
  -- logger.d('check_external_dns_accessible')
  --'/usr/bin/dig @1.1.1.1 +retry=0 +short +time=1 google.com; echo $?'
  hs.task.new(
    '/usr/bin/dig',
    function(exit_code, stdout, stderr)
      local is_external_dns_accessible = exit_code == 0
      -- logger.d(obj.is_external_dns_accessible)
      if obj.use_dhcp_dns ~= true then
        if not is_external_dns_accessible then
          hs.notify.new({
            title = 'Switching to DHCP DNS',
            informativeText = 'External DNS inaccessible',
            withdrawAfter = 10
          }):send()
          obj:toggle_dhcp_dns()
        elseif obj.use_dhcp_dns == nil then
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

function obj:is_network_reachable(reach_status)
  -- logger.d(reach_status)
  return reach_status >= MINIMUM_REACHABLE_FLAG
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

function obj:refresh_trace()
  -- use curl because asyncget sometimes uses a different route than the user
  hs.task.new(
    '/usr/bin/curl',
    function(exit_code, stdout, stderr)
      local trace = {}
      if exit_code == 0 then
        local lines = hs.fnutils.split(stdout, "\n")
        for line_no, line in ipairs(lines) do
          local kv = hs.fnutils.split(line, "=")
          if (kv[1]) then trace[kv[1]] = kv[2] end
        end
      else
        trace = NIL_TRACE
      end
      if not obj:is_ip_similar(trace.ip, obj.prev_trace.ip) or trace.loc ~= obj.prev_trace.loc then
        obj:notify(trace)
      end
      obj.prev_trace = trace
      obj:update_menubar()
    end,
    { '-f', 'https://cloudflare.com/cdn-cgi/trace' }
  ):start()
end

function obj:reach_callback(reach_obj, flags)
  if obj:is_network_reachable(reach_obj) then
    obj.dns_timer:start():fire()
    obj.trace_timer:start():fire()
  else
    obj.dns_timer:stop()
    obj.trace_timer:stop()
  end
end

function obj:start()
  obj.update_menubar()
  obj.dns_timer = hs.timer.new(10, obj.check_external_dns_accessible)
  obj.trace_timer = hs.timer.new(10, obj.refresh_trace)
  obj.reach_listener = hs.network.reachability.internet():setCallback(obj.reach_callback):start()
  obj:reach_callback(hs.network.reachability.internet():status())
end

return obj
