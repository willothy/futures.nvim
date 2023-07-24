local Queue = require("futures.queue")
local Future = require("futures.future")

local function mpsc()
  local queue = Queue:new()

  function tx(data)
    queue:enqueue(data)
  end

  local rx = Future.new(function()
    while queue:is_empty() do
      coroutine.yield()
    end
    return queue:dequeue()
  end)

  return tx, rx
end

local function oneshot()
  local data

  local function tx(d)
    if not data then
      data = d
    end
  end

  local rx = Future.new(function()
    while not data do
      coroutine.yield()
    end
    return data
  end)

  return tx, rx
end

return {
  mpsc = mpsc,
  oneshot = oneshot,
}
