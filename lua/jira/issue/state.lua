---@class Jira.Issue.State
---@field issue? table
---@field buf? integer
---@field win? integer
---@field loading boolean
---@field active_tab "description"|"comments"|"help"
---@field comments table
---@field comment_ranges table<{id: string, start_line: number, end_line: number}>
local M = {
  comments = {},
  comment_ranges = {},
  active_tab = "description", -- "description" or "comments"
  loading = false,
}

return M
-- vim: set ts=2 sts=2 sw=2 et ai si sta:
