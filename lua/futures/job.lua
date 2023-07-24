local Future = require("futures.future")

---@async
local function job(cmd)
  if type(cmd) == "string" then
    cmd = { cmd }
  end

  return Future.new(function(reject)
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

return job
