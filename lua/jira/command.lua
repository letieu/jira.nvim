---@class Jira.Command
local M = {}

---@type string[]
M.SUBCOMMANDS = { "info", "edit", "create" }

---@param args string
function M.execute(args)
  local parts = {}
  for part in args:gmatch("%S+") do
    table.insert(parts, part)
  end

  local cmd = parts[1]

  if cmd == "info" then
    local key = parts[2]
    local tab_or_extra = parts[3]

    if not key then
      vim.notify("Usage: :Jira info <issue-key> [comment|description]", vim.log.levels.ERROR)
      return
    end

    local issue_view = require("jira.issue")

    local tab = "description"
    if tab_or_extra and (tab_or_extra == "comment" or tab_or_extra == "comments") then
      tab = "comments"
    end

    issue_view.open(key:upper(), tab)
    return
  end

  if cmd == "edit" then
    local key = parts[2]

    if not key then
      vim.notify("Usage: :Jira edit <issue-key> [comment|description]", vim.log.levels.ERROR)
      return
    end

    local issue_edit = require("jira.edit")
    issue_edit.open(key:upper())
    return
  end

  if cmd == "create" then
    local project_key = parts[2]
    if project_key then
      project_key = project_key:upper()
    end
    require("jira.create").open(project_key)
    return
  end

  -- Default: Open Board
  -- Usage: :Jira [project-key]
  local project_key = parts[1]
  if project_key then
    project_key = project_key:upper()
  end
  require("jira.board").open(project_key)
end

return M
-- vim: set ts=2 sts=2 sw=2 et ai si sta:
