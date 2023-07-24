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

return Queue
