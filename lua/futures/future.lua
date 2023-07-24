local Status = require("futures.status")
local Error = require("futures.error")

local next_id = 0
local function free_id()
  local id = next_id
  next_id = next_id + 1
  return id
end

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

---@return Future
function Future.new(fn)
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

function Future:reject(cause, message)
  self.status = Status.Rejected
  self.result = Error.new(self, cause, message)
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
  return Future.new(function(reject)
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
  return Future.new(function(reject)
    local status, result = self:await()
    if status == Status.Rejected then
      return fn(result)
    else
      reject(result)
      return result
    end
  end)
end

return Future
