---@class Jira
local M = {}

local config = require("jira.common.config")
local command = require("jira.command")

---@param cmd_line string
local function complete(_, cmd_line, _)
  local args = vim.split(cmd_line, "%s+", { trimempty = true })
  if #args <= 1 then
    return command.SUBCOMMANDS
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
