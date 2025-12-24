-- imported from https://github.com/echasnovski/mini.nvim
local Helpers = {}

-- Add extra expectations
Helpers.expect = vim.deepcopy(MiniTest.expect)

local function error_message(str, pattern)
  return string.format("Pattern: %s\nObserved string: %s", vim.inspect(pattern), str)
end

Helpers.expect.match = MiniTest.new_expectation("string matching", function(str, pattern)
  return str:find(pattern) ~= nil
end, error_message)

Helpers.expect.no_match = MiniTest.new_expectation("no string matching", function(str, pattern)
  return str:find(pattern) == nil
end, error_message)

-- Monkey-patch `MiniTest.new_child_neovim` with helpful wrappers
Helpers.new_child_neovim = function()
  local child = MiniTest.new_child_neovim()

  local prevent_hanging = function(method)
    if not child.is_blocked() then
      return
    end

    local msg =
        string.format("Can not use `child.%s` because child process is blocked.", method)
    error(msg)
  end

  child.wait = function(ms)
    child.loop.sleep(ms or 10)
  end

  child.setup = function()
    child.restart({ "-u", "scripts/minimal_init.lua" })

    -- Change initial buffer to be readonly. This not only increases execution
    -- speed, but more closely resembles manually opened Neovim.
    child.bo.readonly = false
  end

  child.get_current_win = function()
    return child.lua_get("vim.api.nvim_get_current_win()")
  end

  child.set_lines = function(arr, start, finish)
    prevent_hanging("set_lines")

    if type(arr) == "string" then
      arr = vim.split(arr, "\n")
    end

    child.api.nvim_buf_set_lines(0, start or 0, finish or -1, false, arr)
  end

  child.get_lines = function(start, finish)
    prevent_hanging("get_lines")

    return child.api.nvim_buf_get_lines(0, start or 0, finish or -1, false)
  end

  child.set_cursor = function(line, column, win_id)
    prevent_hanging("set_cursor")

    child.api.nvim_win_set_cursor(win_id or 0, { line, column })
  end

  child.get_cursor = function(win_id)
    prevent_hanging("get_cursor")

    return child.api.nvim_win_get_cursor(win_id or 0)
  end

  return child
end

return Helpers
