-- store config values in ~/.hammerspoon/config.json
local config = hs.json.read('config.json') or {}

hs.spoons.use('CryptoMenubar')
spoon.CryptoMenubar:start(config.crypto_menubar)

hs.spoons.use('NetworkWatcher')
spoon.NetworkWatcher:start()

hs.spoons.use('ScreenManager')
spoon.ScreenManager:start()

hs.spoons.use('LoadAlert')
spoon.LoadAlert:start()

hs.spoons.use('PowerWatcher')
spoon.PowerWatcher:start()

-- Store timers on obj, otherwise I see them stop after ~3 min
