---@class Error
---@field source Future The future that was rejected
---@field cause string  The error message
---@field data table?   Arbitrary data that can be included with a rejection
local Error = {}
Error.__index = Error
Error.__metatable = 0

---@param source Future
---@param cause string
---@param data table?
---@return Error
function Error.new(source, cause, data)
  local o = {
    source = source,
    cause = cause,
    data = data,
  }
  setmetatable(o, Error)
  return o
end

return Error
