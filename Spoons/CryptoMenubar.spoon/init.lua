local ETH_GAS_URL = 'https://api.etherscan.io/api?module=gastracker&action=gasoracle&apikey='
local ETH_PRICE_URL = 'https://api.etherscan.io/api?module=stats&action=ethprice&apikey='
local FONT_NAME = 'SFMono-Regular'
local MONOSPACE = { font = { name = FONT_NAME, size = 12 } }

-- use logger.d("log message")
local logger = hs.logger.new('CryptoMenu', 'debug')
local menubar = hs.menubar.new()

local obj = {}
obj.btc_eth = 0
obj.btc_usd = 0
obj.eth_btc = 0
obj.eth_usd = 0
obj.gas_low = 0
obj.gas_med = 0
obj.gas_hi = 0
obj.fetch_times = { [ETH_GAS_URL] = 0, [ETH_PRICE_URL] = 0 }

-- make less opaque if earliest fetch time isn't recent
local get_alpha = function ()
  local now = hs.timer.secondsSinceEpoch()
  local earliest = now
  for _url, time in pairs(obj.fetch_times) do
    if earliest > time then earliest = time end
  end
  local is_current = now - earliest < 60 * 10
  return (is_current and HIGH_ALPHA) or LOW_ALPHA
end

local update_menubar = function ()
  local alpha = get_alpha()
  local rect = hs.geometry.rect(0, 0, 50, 22) -- 24 is max height
  local canvas = hs.canvas.new(rect)
  local st1 = hs.styledtext.new(
    string.format("%.0f %.1f\n", obj.btc_usd / 100, obj.btc_eth),
    { font = { name = FONT_NAME, size = 9 }, color = { alpha = alpha, white = 1 }, paragraphStyle = { alignment = "left", lineBreak = "clip", maximumLineHeight = 12 } }
  )
  local canvas_text = getmetatable(st1).__concat(st1, hs.styledtext.new(
    string.format("%.0f %.0f", obj.eth_usd,  obj.gas_med),
    { font = { name = FONT_NAME, size = 9 }, color = { alpha = alpha, white = 1 }, paragraphStyle = { alignment = "left", lineBreak = "clip", maximumLineHeight = 10 } }
  ))
  canvas[1] = {
    text = canvas_text,
    type = "text"
  }
  menubar:setIcon(canvas:imageFromCanvas())
  -- https://www.gitmemory.com/issue/Hammerspoon/hammerspoon/2741/792564885
  canvas = nil
  local gas = string.format("%.0f %.0f %.0f", obj.gas_low, obj.gas_med, obj.gas_hi)
  menubar:setMenu({
    { title = hs.styledtext.new(string.format("BTC% 7.0f", obj.btc_usd), MONOSPACE), fn = function() hs.urlevent.openURL('https://www.google.com/finance/quote/BTC-USD?window=5D') end },
    { title = hs.styledtext.new(string.format("ETH% 7.0f", obj.eth_usd), MONOSPACE), fn = function() hs.urlevent.openURL('https://www.google.com/finance/quote/ETH-USD?window=5D') end },
    { title = '-' },
    { title = hs.styledtext.new(gas, MONOSPACE), fn = function() hs.urlevent.openURL('https://etherscan.io/gastracker') end },
    { title = hs.styledtext.new(string.format("%.04f", obj.btc_eth), MONOSPACE), fn = function() hs.urlevent.openURL('https://www.google.com/finance/quote/BTC-ETH?window=1M') end },
    { title = hs.styledtext.new(string.format("%.05f", obj.eth_btc), MONOSPACE), fn = function() hs.urlevent.openURL('https://www.google.com/finance/quote/ETH-BTC?window=1M') end },
  })
end

local update_fetch_time = function (url)
  obj.fetch_times[url] = hs.timer.secondsSinceEpoch()
end

local refresh_data = function ()
  if not is_reachable() then
    return update_menubar()
  end

  hs.http.asyncGet(
    ETH_PRICE_URL .. obj.config.etherscan_api_key,
    nil,
    function(status, body_json, headers)
      if (status == 200) then
        local body = hs.json.decode(body_json)
        obj.eth_btc = body.result.ethbtc
        obj.eth_usd = body.result.ethusd
        obj.btc_eth = 1 / obj.eth_btc
        obj.btc_usd = obj.eth_usd / obj.eth_btc
        update_fetch_time(ETH_PRICE_URL)
        update_menubar()
      end
    end
  )
  hs.http.asyncGet(
    ETH_GAS_URL .. obj.config.etherscan_api_key,
    nil,
    function(status, body_json, headers)
      if (status == 200) then
        local body = hs.json.decode(body_json)
        obj.gas_low = body.result.SafeGasPrice
        obj.gas_med = body.result.ProposeGasPrice
        obj.gas_hi = body.result.FastGasPrice
        update_fetch_time(ETH_GAS_URL)
        update_menubar()
      end
    end
  )
end

function obj:start(config)
  obj.config = config
  update_menubar()
  obj.timer = hs.timer.doEvery(60, refresh_data):fire()
  obj.reach_listener = hs.network.reachability.internet():setCallback(
    function ()
      obj.timer:fire()
    end
  ):start()
end

return obj
