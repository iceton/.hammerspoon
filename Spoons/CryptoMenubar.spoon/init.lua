local obj = {}

local logger = hs.logger.new('CryptoMenu', 'debug')
local menubar = hs.menubar.new()
local monospace = { font = { name = 'SFMono-Regular', size = 12 } }

local eth_gas_url = 'https://api.etherscan.io/api?module=gastracker&action=gasoracle&apikey='
local eth_price_url = 'https://api.etherscan.io/api?module=stats&action=ethprice&apikey='
local ldo_url = 'https://api.coinmarketcap.com/data-api/v3/cryptocurrency/market-pairs/latest?slug=lido-dao&start=1&limit=1&category=spot'

obj.btc_usd = 0
obj.eth_btc = 0
obj.eth_usd = 0
obj.ldo_eth = 0
obj.ldo_usd = 0
obj.gas_low = 0
obj.gas_med = 0
obj.gas_hi = 0
obj.fetch_times = { [eth_gas_url] = 0, [eth_price_url] = 0, [ldo_url] = 0 }

function obj:update_menubar()
  local alpha = obj:get_alpha()
  local rect = hs.geometry.rect(0, 0, 55, 22) -- 24 is max height
  local canvas = hs.canvas.new(rect)
  local st1 = hs.styledtext.new(
    string.format("%.0f %.0f\n", obj.eth_usd, obj.btc_usd),
    { font = { name = 'SFMono-Regular', size = 9 }, color = { alpha = alpha, white = 1 }, paragraphStyle = { alignment = "left", lineBreak = "clip", maximumLineHeight = 12 } }
  )
  local canvas_text = getmetatable(st1).__concat(st1, hs.styledtext.new(
    string.format("%.05f %s", obj.ldo_eth, obj.gas_med):sub(2),
    { font = { name = 'SFMono-Regular', size = 9 }, color = { alpha = alpha, white = 1 }, paragraphStyle = { alignment = "left", lineBreak = "clip", maximumLineHeight = 10 } }
  ))
  canvas[1] = {
    text = canvas_text,
    type = "text"
  }
  menubar:setIcon(canvas:imageFromCanvas())
  -- https://www.gitmemory.com/issue/Hammerspoon/hammerspoon/2741/792564885
  canvas = nil
  local gas = string.format("%s %s %s", obj.gas_low, obj.gas_med, obj.gas_hi)
  menubar:setMenu({
    { title = hs.styledtext.new(string.format("BTC% 9.02f", obj.btc_usd), monospace), fn = function() hs.urlevent.openURL('https://www.google.com/finance/quote/BTC-USD?window=5D') end },
    { title = hs.styledtext.new(string.format("ETH% 9.02f", obj.eth_usd), monospace), fn = function() hs.urlevent.openURL('https://www.google.com/finance/quote/ETH-USD?window=5D') end },
    { title = hs.styledtext.new(string.format("LDO% 9.02f", obj.ldo_usd), monospace), fn = function() hs.urlevent.openURL('https://www.coingecko.com/en/coins/lido-dao') end },
    { title = '-' },
    { title = hs.styledtext.new(gas, monospace), fn = function() hs.urlevent.openURL('https://etherscan.io/gastracker') end },
    { title = hs.styledtext.new(string.format("%.05f", obj.eth_btc), monospace), fn = function() hs.urlevent.openURL('https://livdir.com/ethgaspricechart/') end },
  })
end

function obj:update_fetch_time(url)
  obj.fetch_times[url] = hs.timer.secondsSinceEpoch()
end

function obj:get_alpha()
  local now = hs.timer.secondsSinceEpoch()
  local earliest = now
  for k, v in pairs(obj.fetch_times) do
    if earliest > v then earliest = v end
  end
  local is_current = now - earliest < 60 * 10
  return (is_current and 0.9) or 0.3
end

function obj:refresh_data()
  -- logger.d('refresh_data')
  hs.http.asyncGet(
    eth_price_url .. obj.config.etherscan_api_key,
    nil,
    function(status, body_json, headers)
      if (status == 200) then
        local body = hs.json.decode(body_json)
        obj.eth_usd = body.result.ethusd or 0
        obj.eth_btc = body.result.ethbtc or 0
        obj.btc_usd = obj.eth_usd / obj.eth_btc
        obj:update_fetch_time(eth_price_url)
        obj:update_menubar()
      end
    end
  )
  hs.http.asyncGet(
    eth_gas_url .. obj.config.etherscan_api_key,
    nil,
    function(status, body_json, headers)
      if (status == 200) then
        local body = hs.json.decode(body_json)
        obj.gas_low = body.result.SafeGasPrice
        obj.gas_med = body.result.ProposeGasPrice
        obj.gas_hi = body.result.FastGasPrice
        obj:update_fetch_time(eth_gas_url)
        obj:update_menubar()
      end
    end
  )
  hs.http.asyncGet(
    ldo_url,
    nil,
    function(status, body_json, headers)
      if (status == 200) then
        local body = hs.json.decode(body_json)
        obj.ldo_usd = body.data.marketPairs[1].price
        if obj.eth_usd then
          obj.ldo_eth = obj.ldo_usd / obj.eth_usd
        end
        obj:update_fetch_time(ldo_url)
        obj:update_menubar()
      end
    end
  )
  obj:update_menubar()
end

function obj:start(config)
  obj.config = config
  obj:update_menubar()
  obj:refresh_data()
  obj.crypto_timer = hs.timer.doEvery(10, obj.refresh_data)
end

return obj
