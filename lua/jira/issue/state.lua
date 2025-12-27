---@class Jira.Issue.State
---@field issue? table
---@field buf? integer
---@field win? integer
---@field prev_win? integer
---@field loading boolean
---@field active_tab "description"|"comments"|"help"
---@field comments table
---@field comment_ranges table<{id: string, start_line: number, end_line: number}>
---@field attachment_ranges table<{url: string, start_line: number, end_line: number}>
---@field cache table<string, {issue: table, comments: table, timestamp: number}>
local M = {
  comments = {},
  comment_ranges = {},
  attachment_ranges = {},
  active_tab = "description", -- "description" or "comments"
  loading = false,
  cache = {}, -- Cache for issue data: {[issue_key] = {issue, comments, timestamp}}
}

return M
-- vim: set ts=2 sts=2 sw=2 et ai si sta:
