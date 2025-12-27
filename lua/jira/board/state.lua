---@class JiraState
---@field buf integer|nil            -- main buffer handle
---@field win integer|nil            -- main window handle
---@field dim_win integer|nil        -- dim/background window handle
---@field ns integer                 -- namespace id for highlights/extmarks
---@field status_hls table<string,string> -- map: status -> highlight group
---@field tree JiraIssueNode[]                 -- Jira issue tree
---@field line_map table<number, JiraIssueNode> -- map: line number -> node / issue metadata
---@field project_key string|nil     -- Jira project key (e.g. "ABC")
---@field current_view string|nil    -- current UI view (board, sprint, issue, etc.)
---@field current_query string|nil   -- active JQL or query name
---@field custom_jql string|nil      -- user-defined JQL override
---@field cache table                -- cached API results
---@field sprint_cache table<string, {sprint_id: number, board_id: number, timestamp: number}> -- project -> sprint mapping
---@field query_map table<string,string> -- named queries -> JQL
---@field jql_line integer|nil       -- buffer line containing editable JQL

---@type JiraState
local state = {
  buf = nil,
  win = nil,
  dim_win = nil,
  ns = vim.api.nvim_create_namespace("Jira"),
  status_hls = {},
  tree = {},
  line_map = {},
  project_key = nil,
  current_view = nil,
  current_query = nil,
  custom_jql = nil,
  cache = {},
  sprint_cache = {},
  query_map = {},
  jql_line = nil,
}

return state
-- vim: set ts=2 sts=2 sw=2 et ai si sta:
