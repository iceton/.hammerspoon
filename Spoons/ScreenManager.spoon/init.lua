local obj = {}

local logger = hs.logger.new('ScreenMgr', 'debug')

function obj:lock_screen()
  hs.caffeinate.lockScreen()
end

function obj:reposition_windows(screens, all_screens_config)
  hs.fnutils.each(
    screens,
    function(screen)
      local frame = screen:frame()
      local screen_config = all_screens_config[screen:getUUID()]
      for name, coords in pairs(screen_config) do
        local app = hs.application.get(name)
        if app and app.allWindows then
          hs.fnutils.each(
            app:allWindows(),
            function(window)
              local rect = hs.geometry.rect(coords[1], coords[2], coords[3], coords[4])
              window:setFrame(rect)
            end
          )
        end
      end
    end
  )
end

function obj:screens_updated()
  local screens = hs.screen.allScreens()
  local uuid_table = hs.fnutils.map(
    screens,
    function(screen)
      return screen:getUUID()
    end
  )
  local uuids = table.concat(uuid_table, ",")
  logger.d(uuids)
  local config_filename = string.format(
    "~/.hammerspoon/Spoons/ScreenManager.spoon/%s.json",
    uuids
  )
  local screen_config = hs.json.read(config_filename)
  if screen_config then obj:reposition_windows(screens, screen_config) end
end

function obj:show_plex()
  hs.osascript.javascript([[
    (function() {
      var chrome = Application('Google Chrome');
      chrome.activate();

      for (win of chrome.windows()) {
        var tabIndex =
          win.tabs().findIndex(tab => tab.url().match(/app.plex.tv/));

        if (tabIndex != -1) {
          win.activeTabIndex = (tabIndex + 1);
          win.index = 1;
        }
      }
    })();
  ]])
end

function obj:delayed_screens_updated()
  hs.timer.doAfter(2, obj.screens_updated)
end

function obj:start()
  obj:screens_updated()
  hs.screen.watcher.new(obj.delayed_screens_updated)
  hs.hotkey.bind("alt cmd ctrl shift", "\\", "Plex", obj.show_plex)
  hs.hotkey.bind("alt cmd ctrl shift", "l", obj.lock_screen)
  hs.hotkey.bind("alt cmd ctrl shift", "m", "Repositioning windows", obj.screens_updated)
end

return obj
