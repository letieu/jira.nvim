---@class Jira
local M = {}

local config = require("jira.common.config")
local command = require("jira.command")

---@param cmd_line string
local function complete(_, cmd_line, _)
  local args = vim.split(cmd_line, "%s+", { trimempty = true })
  local has_trailing_space = cmd_line:match("%s$")

  -- args[1] is "Jira"
  
  -- Typing the first argument (subcommand)
  if #args == 1 and not has_trailing_space then
    return command.SUBCOMMANDS
  elseif #args == 1 and has_trailing_space then
    -- Sugggest subcommands if we just finished typing "Jira "
    return command.SUBCOMMANDS
  elseif #args == 2 and not has_trailing_space then
    -- Typing the first argument (subcommand)
    return command.SUBCOMMANDS
  end

  -- Typing the second argument (sub-subcommand)
  if args[2] == "auth" then
    local auth_subcommands = { "login", "info", "logout" }
    if #args == 2 and has_trailing_space then
      return auth_subcommands
    elseif #args == 3 and not has_trailing_space then
      return auth_subcommands
    end
  end

  return {}
end

---@param opts JiraConfig
function M.setup(opts)
  config.setup(opts)

  vim.api.nvim_create_user_command("Jira", function(ctx)
    command.execute(ctx.args)
  end, {
    nargs = "*",
    bang = true,
    complete = complete,
    desc = "Jira view: :Jira [<PROJECT_KEY>] | info <ISSUE_KEY> | create [<PROJECT_KEY>]",
  })
end

M.open = command.execute

return M
-- vim: set ts=2 sts=2 sw=2 et ai si sta:
