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
-- local job = require("futures.job")
-- job({ "git", "status", "--porcelain" }):await(function(status, data)
--   vim.print(data.stdout)
-- end)

local Future = require("futures.future")

return {
  async = function(fn)
    return Future.new(fn)
  end,
  Future = require("futures.future"),
  Scheduler = require("futures.scheduler"),
  channel = require("futures.channel"),
  job = require("futures.job"),
  Queue = require("futures.queue"),
  Status = require("futures.status"),
  Error = require("futures.error"),
}
