local MINIMUM_REACHABLE_FLAG = 1
local NIL_TRACE = {
  colo4 = nil,
  ip4 = nil,
  loc4 = nil,
  colo6 = nil,
  ip6 = nil,
  loc6 = nil,
}
local LOW_ALPHA = 0.3

local obj = {
  prev_menubar_data = {},
  prev_trace = NIL_TRACE,
}

-- use logger.d("log message")
local logger = hs.logger.new('NetWatcher', 'debug')
local menubar = hs.menubar.new()

function obj:update_menubar()
  local menubar_data = hs.fnutils.copy(obj.prev_trace)
  -- table keys needed for encoding, fails as unkeyed arr
  menubar_data.ds = obj:get_dns_server()
  -- rerender only if data has changed
  if hs.json.encode(menubar_data) ~= hs.json.encode(obj.prev_menubar_data) then
    obj:render_menubar(menubar_data)
    obj.prev_menubar_data = menubar_data
  end
end

function obj:has_ip()
  return obj.prev_trace.ip4 ~= nil or obj.prev_trace.ip6 ~= nil
end

function obj:render_menubar(data)
  local rect = hs.geometry.rect(0, 0, 30, 22) -- 24 is max height
  local canvas = hs.canvas.new(rect)
  local is_loc_mismatch = data.loc4 and data.loc6 and data.loc4 ~= data.loc6
  local display_loc = (is_loc_mismatch and '‼️') or data.loc4 or data.loc6 or '✕'
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
  canvas = nil

  menubar:setMenu({
    { title = string.format("%s %s %s", data.loc4, data.colo4, data.ip4), disabled = not data.ip4, fn = function() hs.pasteboard.setContents(data.ip4) end },
    { title = string.format("%s %s %s", data.loc6, data.colo6, data.ip6), disabled = not data.ip6, fn = function() hs.pasteboard.setContents(data.ip6) end },
    { title = string.format("DNS %s", data.ds), disabled = true },
  })
end

function obj:get_dns_server()
  return hs.execute('scutil --dns | grep "nameserver\\[0\\]" | head -1 | sed "s/.*: \\(.*\\)/\\1/"')
end

-- function obj:toggle_dhcp_dns()
--   obj.use_dhcp_dns = not obj.use_dhcp_dns
--   if obj.use_dhcp_dns then
--     obj:set_dhcp_dns()
--   else
--     obj:set_external_dns()
--   end
--   obj:update_menubar()
-- end

function obj:notify(trace)
  local prev = obj.prev_trace
  
  if trace.loc4 ~= prev.loc4 or trace.loc6 ~= prev.loc6 then
    local alert_text = string.format("4 6: %s %s » %s %s", prev.loc4, prev.loc6, trace.loc4, trace.loc6)
    hs.alert.show(alert_text, nil, nil, 3)
  elseif trace.colo4 ~= prev.colo4 or trace.colo6 ~= prev.colo6 or not obj:is_ip_similar(prev.ip4, trace.ip4) or not obj:is_ip_similar(prev.ip6, trace.ip6) then
    hs.notify.new({
      title = string.format("%s connection", trace.loc4 or trace.loc6),
      informativeText = string.format("4: %s » %s\n6: %s » %s", prev.colo4, trace.colo4, prev.colo6, trace.colo6),
      withdrawAfter = 3
    }):send()
  end
end

-- function obj:is_external_dns()
--   local found = hs.execute('networksetup -getdnsservers Wi-Fi'):find('1.1.1.1')
--   -- logger.d(found)
--   return found ~= nil
-- end

-- function obj:check_external_dns_accessible()
--   -- logger.d('check_external_dns_accessible')
--   --'/usr/bin/dig @1.1.1.1 +retry=0 +short +time=1 google.com; echo $?'
--   hs.task.new(
--     '/usr/bin/dig',
--     function(exit_code, stdout, stderr)
--       local is_external_dns_accessible = exit_code == 0
--       -- logger.d(obj.is_external_dns_accessible)
--       if obj.use_dhcp_dns ~= true then
--         if not is_external_dns_accessible then
--           hs.notify.new({
--             title = 'Switching to DHCP DNS',
--             informativeText = 'External DNS inaccessible',
--             withdrawAfter = 10
--           }):send()
--           obj:toggle_dhcp_dns()
--         elseif obj.use_dhcp_dns == nil then
--           obj:set_external_dns()
--         end
--       end
--     end,
--     { '@1.1.1.1', '+retry=0', '+short', '+time=1', 'google.com' }
--   ):start()
-- end

-- function obj:set_dhcp_dns()
--   if obj:is_external_dns() then
--     hs.execute('sudo /usr/local/bin/wifi_dns_dhcp.sh')
--     return true
--   else
--     return false
--   end
-- end

-- function obj:set_external_dns(force)
--   if force or not obj:is_external_dns() then
--     hs.execute('sudo /usr/local/bin/wifi_dns_spec.sh')
--     return true
--   else
--     return false
--   end
-- end

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

-- pass from trace4 to trace6 then menu
function obj:refresh_trace4()
  hs.task.new(
    '/usr/bin/curl',
    function(exit_code, stdout, stderr)
      local trace4 = (exit_code == 0 and obj:trace_to_table(stdout)) or NIL_TRACE
      local trace = {
        colo4 = trace4.colo,
        ip4 = trace4.ip,
        loc4 = trace4.loc,
      }
      obj:refresh_trace6(trace)
    end,
    { '-4', '-f', 'https://cloudflare.com/cdn-cgi/trace' }
  ):start()
end

function obj:refresh_trace6(trace)
  hs.task.new(
    '/usr/bin/curl',
    function(exit_code, stdout, stderr)
      local trace6 = (exit_code == 0 and obj:trace_to_table(stdout)) or NIL_TRACE
      -- if not obj:is_ip_similar(trace.ip, obj.prev_trace6.ip) or trace.loc ~= obj.prev_trace6.loc then
      --   obj:notify(obj.prev_trace4, trace)
      -- end
      -- obj.prev_trace6 = trace
      trace.colo6 = trace6.colo
      trace.ip6 = trace6.ip
      trace.loc6 = trace6.loc
      obj:notify(trace)
      obj.prev_trace = trace
      obj:update_menubar()
    end,
    { '-6', '-f', 'https://cloudflare.com/cdn-cgi/trace' }
  ):start()
end

function obj:reach_callback(reach_obj, flags)
  if obj:is_network_reachable(reach_obj) then
    obj.trace_timer:start():fire()
  else
    obj.trace_timer:stop()
  end
end

function obj:start()
  obj.update_menubar()
  obj.trace_timer = hs.timer.new(10, obj.refresh_trace4)
  obj.reach_listener = hs.network.reachability.internet():setCallback(obj.reach_callback):start()
  obj:reach_callback(hs.network.reachability.internet():status())
end

return obj
