local Status = require("futures.status")
local Queue = require("futures.queue")
local Future = require("futures.future")

local function poll(future)
  if future.status == Status.Pending then
    return future:poll()
  else
    return future.status, future.result
  end
end

---@class Scheduler
---@field queue Queue
---@field running boolean
---@field loop uv.uv_timer_t
local Scheduler = {}
Scheduler.__index = Scheduler

function Scheduler:new()
  local o = {
    queue = Queue:new(),
    running = false,
    loop = vim.loop.new_timer(),
  }
  setmetatable(o, Scheduler)
  return o
end

function Scheduler:tick()
  if self.queue:is_empty() then
    self:cleanup()
  else
    local to_run = self.queue:dequeue()

    local status = poll(to_run)
    if status == Status.Pending then
      self.queue:enqueue(to_run)
    end
  end
end

function Scheduler:start()
  -- require("savior").utils.progress.start("scheduler running")
  self.running = true
  if not self.loop then
    self.loop = vim.loop.new_timer()
  end
  self.loop:start(
    100,
    100,
    vim.schedule_wrap(function()
      self:tick()
    end)
  )
end

function Scheduler:on_close()
  require("savior").utils.progress.stop("scheduler shutdown")
end

function Scheduler:cleanup()
  if not self.queue:is_empty() then
    vim.defer_fn(function()
      self:cleanup()
    end, 150)
    return
  end
  self.queue:clear()
  self.running = false
  if self.loop:is_active() then
    self.loop:stop()
  end
  if not self.loop:is_closing() then
    self.loop:close(vim.schedule_wrap(function()
      self:on_close()
    end))
  end
  self.loop = nil
end

function Scheduler:spawn(future)
  if getmetatable(future) ~= Future then
    if getmetatable(future[1]) == Future then
      local checked = {}
      for f in vim.iter(future) do
        if checked[f] then
          error("Scheduler:spawn cannot be called with duplicate futures")
        end
        self:spawn(f)
        checked[f] = true
      end
      return Future.new(function(reject)
        local results = {}
        local resolved
        repeat
          resolved = true
          for f in vim.iter(future) do
            local status, result = f:poll()
            if status == Status.Resolved then
              if checked[f] then
                table.insert(results, result)
                checked[f] = false
              end
            elseif status == Status.Rejected then
              reject(result)
            else
              resolved = false
              coroutine.yield()
            end
          end
          coroutine.yield()
        until resolved
        return unpack(results)
      end)
    else
      error(
        "Scheduler:spawn expects a Future or list of futures, found "
          .. type(future)
      )
    end
  end
  self.queue:enqueue(future)
  if not self.running then
    self:start()
  end
  return future
end

---@param fn fun(sc: Scheduler)
---Creates a temporary scheduler and passes it to the provided function.
function Scheduler.with(fn)
  local sc = Scheduler:new()
  fn(sc)
end

return Scheduler
