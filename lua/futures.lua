-- Author: Will Hopkins
-- License: MIT
-- Lua Futures / scheduler for Neovim
--
--
-- TODO:
-- - [ ] add tests
-- - [ ] priority queue
-- - [ ] benchmark to find ideal poll timing
-- - [ ] add ways of joining / selecting from multiple futures
-- - [ ] add "incremental" futures for long-running tasks that can steadily produce data
--

local iter = vim.iter

---@class Queue
local Queue = {}
Queue.__index = Queue
Queue.__metatable = 0

function Queue:new()
  local o = {
    _buffer = {},
    _len = 0,
  }
  setmetatable(o, Queue)
  return o
end

function Queue:enqueue(value)
  table.insert(self._buffer, value)
  self._len = self._len + 1
end

function Queue:dequeue()
  if self._len > 0 then
    local value = table.remove(self._buffer, 1)
    self._len = self._len - 1
    return value
  end
end

function Queue:rotate()
  if self._len > 0 then
    local value = table.remove(self._buffer, 1)
    table.insert(self._buffer, value)
  end
end

function Queue:clear()
  self._buffer = {}
  self._len = 0
end

function Queue:is_empty()
  return self._len == 0
end

function Queue:len()
  return self._len
end

function Queue:__tostring()
  return vim.inspect(self._buffer)
end

---@enum Status
local Status = {
  Pending = "pending",
  Resolved = "resolved",
  Rejected = "rejected",
}

---@class Rejection
---@field source any
---@field data any
---@field cause string
---@field message string
local Rejection = {
  source = nil,
  cause = nil,
  data = nil,
  message = "error in future execution",
}
Rejection.__index = Rejection
Rejection.__metatable = 0

---@generic T
---@class Future<T>
---@field status Status
---@field task thread
---@field result T | error
---@field start_time integer
---@field poll_count integer
---@field id integer
local Future = {
  status = Status.Pending,
  task = nil,
}
Future.__index = Future
Future.__metatable = Future

local next_id = 0
local function free_id()
  local id = next_id
  next_id = next_id + 1
  return id
end

local function async(fn)
  local co
  if type(fn) == "function" then
    co = coroutine.create(fn)
  elseif type(fn) == "thread" then
    co = fn
  else
    error("async expects a function or coroutine")
  end

  local future = setmetatable({
    task = co,
    id = free_id(),
    status = Status.Pending,
    poll_count = 0,
    start_time = vim.loop.now(),
  }, Future)

  return future
end

local function poll(future)
  if future.status == Status.Pending then
    return future:poll()
  else
    return future.status, future.result
  end
end

function Future:reject(cause, message)
  self.status = Status.Rejected
  local o = {
    cause = cause,
  }
  if message then
    o.message = message
  end
  self.result = setmetatable(o, Rejection)
end

function Future:poll()
  if self.status == Status.Pending then
    local function reject(cause)
      self:reject(cause)
      error(cause)
    end
    local ok, result = coroutine.resume(self.task, reject)
    if not ok then
      self:reject(result)
    elseif coroutine.status(self.task) == "dead" then
      self.status = Status.Resolved
      self.result = result
    end
  end
  return self.status, self.result
end

--- @param callback function Only used if called from a non-async context
function Future:await(callback)
  -- selene: allow(incorrect_standard_library_use)
  if coroutine.isyieldable() then
    while self:poll() == Status.Pending do
      if coroutine.isyieldable() then
        coroutine.yield()
      end
    end
  elseif callback == nil then
    error(
      "Future:await must be called from an async context or with a callback"
    )
  else
    local status, result = self:poll()
    if status == Status.Pending then
      vim.defer_fn(function()
        self:await(callback)
      end, 50)
    else
      callback(status, result)
    end
  end
  return self.status, self.result
end

function Future:then_call(fn)
  return async(function(reject)
    local status, result = self:await()
    if status == Status.Resolved then
      return fn(result)
    else
      reject(result)
      return result
    end
  end)
end

function Future:or_else(fn)
  return async(function(reject)
    local status, result = self:await()
    if status == Status.Rejected then
      return fn(result)
    else
      reject(result)
      return result
    end
  end)
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
    self.loop:stop()
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
      for f in iter(future) do
        if checked[f] then
          error("Scheduler:spawn cannot be called with duplicate futures")
        end
        self:spawn(f)
        checked[f] = true
      end
      return async(function(reject)
        local results = {}
        local resolved
        repeat
          resolved = true
          for f in iter(future) do
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

local function mpsc()
  local queue = Queue:new()

  function tx(data)
    queue:enqueue(data)
  end

  local rx = async(function()
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

  local rx = async(function()
    while not data do
      coroutine.yield()
    end
    return data
  end)

  return tx, rx
end

local function job(cmd)
  if type(cmd) == "string" then
    cmd = { cmd }
  end

  return async(function(reject)
    local val
    vim.system(cmd, { text = true }, function(obj)
      local code, signal, stdout, stderr =
        obj.code, obj.signal, obj.stdout, obj.stderr

      if code == 0 then
        val = obj
        return
      else
        reject({
          cause = stderr,
          code = code,
          signal = signal,
          stdout = stdout,
        })
      end
    end)
    while not val do
      coroutine.yield()
    end
    return val
  end)
end

local function with_scheduler(fn)
  local sc = Scheduler:new()
  fn(sc)
  sc:cleanup()
end

---------------------------------------------------
--                                               --
------------------ Testing stuff ------------------
--
-- local tx, rx = mpsc()
--
-- local function sleep(ms)
--   return async(function()
--     local start = vim.loop.now()
--     while vim.loop.now() - start < ms do
--       coroutine.yield()
--     end
--     tx(ms)
--   end)
-- end
--
-- with_scheduler(function(s)
--   s:spawn(job({ "git", "status" })):await(function(status, result)
--     if status == Status.Resolved then
--       vim.notify(result.stdout)
--     else
--       vim.notify(result.cause, vim.log.levels.ERROR)
--     end
--   end)
-- end)
--
-- vim.print(job({ "git", "status" }))

return {
  with_scheduler = with_scheduler,
  async = async,
  Future = Future,
  Scheduler = Scheduler,
  mpsc = mpsc,
  oneshot = oneshot,
  job = job,
  Queue = Queue,
  Status = Status,
  Rejection = Rejection,
}
