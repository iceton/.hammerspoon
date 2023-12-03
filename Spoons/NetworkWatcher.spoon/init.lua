local MINIMUM_REACHABLE_FLAG = 1
local NIL_TRACE = {
  colo = nil,
  ip = nil,
  loc = nil,
}
local LOW_ALPHA = 0.3

local obj = {
  prev_menubar_data = {},
  prev_trace4 = NIL_TRACE,
  prev_trace6 = NIL_TRACE,
  use_dhcp_dns = true, -- prev nil to allow ext upgrade, now true because tailscale dns more or less overrides this
}

-- use logger.d("log message")
local logger = hs.logger.new('NetWatcher', 'debug')
local menubar = hs.menubar.new()

function obj:update_menubar()
  local trace4 = obj.prev_trace4
  local trace6 = obj.prev_trace6
  -- table keys needed for encoding, fails as unkeyed arr
  local menubar_data = {
    t4c = trace4.colo,
    t4i = trace4.ip,
    t4l = trace4.loc,
    t6c = trace6.colo,
    t6i = trace6.ip,
    t6l = trace6.loc,
    ds = obj:get_dns_server(),
    ud = obj.use_dhcp_dns
  }
  -- rerender only if data has changed
  if hs.json.encode(menubar_data) ~= hs.json.encode(obj.prev_menubar_data) then
    obj:render_menubar()
    obj.prev_menubar_data = menubar_data
  end
end

function obj:has_ip()
  return obj.prev_trace4.ip ~= nil
end

function obj:render_menubar()
  local rect = hs.geometry.rect(0, 0, 30, 22) -- 24 is max height
  local canvas = hs.canvas.new(rect)
  local trace4 = obj.prev_trace4
  local trace6 = obj.prev_trace6
  local display_loc = (trace6.loc and trace4.loc ~= trace6.loc and '‼️') or trace4.loc or '✕'
  canvas[1] = {
    text = hs.styledtext.new(
      display_loc,
      {
        font = { name = 'SF Compact Display', size = 20 },
        color = { alpha = (obj:has_ip() and 0.9) or LOW_ALPHA, white = 1 },
        paragraphStyle = { alignment = "center", lineBreak = "clip", maximumLineHeight = 22 }
      }
    ),
    type = "text"
  }
  -- menubar:returnToMenuBar()
  menubar:setIcon(canvas:imageFromCanvas())
  -- https://www.gitmemory.com/issue/Hammerspoon/hammerspoon/2741/792564885
  local canvas = nil

  local ip4 = trace4.ip
  local ip6 = trace6.ip
  menubar:setMenu({
    { title = string.format("%s %s %s", trace4.loc, trace4.colo, ip4), disabled = not ip4, fn = function() hs.pasteboard.setContents(ip4) end },
    { title = string.format("%s %s %s", trace6.loc, trace6.colo, ip6), disabled = not ip6, fn = function() hs.pasteboard.setContents(ip6) end },
    { title = string.format("DNS %s", obj:get_dns_server()), disabled = true },
    { title = "Use DHCP DNS", checked = obj.use_dhcp_dns == true, fn = function() obj:toggle_dhcp_dns() end },
  })
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

function obj:notify(trace4, trace6)
  local prev4 = obj.prev_trace4
  local prev6 = obj.prev_trace6
  local loc = trace4.loc or trace6.loc
  local prev_loc = prev4.loc or prev6.loc
  if loc ~= prev_loc then
    local alert_text = string.format("%s » %s", prev_loc, loc)
    hs.alert.show(alert_text, nil, nil, 3)
  else
    hs.notify.new({
      title = string.format("%s connection", loc),
      informativeText = string.format("%s » %s", prev4.colo or prev6.colo, trace4.colo or trace6.colo),
      withdrawAfter = 3
    }):send()
  end
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

function obj:trace_to_table(str)
  local trace = {}
  local lines = hs.fnutils.split(str, "\n")
  for line_no, line in ipairs(lines) do
    local kv = hs.fnutils.split(line, "=")
    if (kv[1]) then trace[kv[1]] = kv[2] end
  end
  return trace
end

function obj:refresh_trace()
  -- use curl because asyncget sometimes uses a different route than the user
  hs.task.new(
    '/usr/bin/curl',
    function(exit_code, stdout, stderr)
      local trace = (exit_code == 0 and obj:trace_to_table(stdout)) or NIL_TRACE
      if not obj:is_ip_similar(trace.ip, obj.prev_trace4.ip) or trace.loc ~= obj.prev_trace4.loc then
        obj:notify(trace, obj.prev_trace6)
      end
      obj.prev_trace4 = trace
      obj:update_menubar()
    end,
    { '-4', '-f', 'https://cloudflare.com/cdn-cgi/trace' }
  ):start()
  hs.task.new(
    '/usr/bin/curl',
    function(exit_code, stdout, stderr)
      local trace = (exit_code == 0 and obj:trace_to_table(stdout)) or NIL_TRACE
      if not obj:is_ip_similar(trace.ip, obj.prev_trace6.ip) or trace.loc ~= obj.prev_trace6.loc then
        obj:notify(obj.prev_trace4, trace)
      end
      obj.prev_trace6 = trace
      obj:update_menubar()
    end,
    { '-6', '-f', 'https://cloudflare.com/cdn-cgi/trace' }
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
