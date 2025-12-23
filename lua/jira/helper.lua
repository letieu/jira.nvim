local state = require('jira.state')

local M = {}

M.get_node_at_cursor = function()
  local cursor = vim.api.nvim_win_get_cursor(state.win)
  local row = cursor[1] - 1
  local node = state.line_map[row]
  return node
end

M.get_cache_key = function(project_key, view_name)
  local key = project_key .. ":" .. view_name
  if view_name == "JQL" then
    key = key .. ":" .. (state.current_query or "Custom JQL")
    if state.current_query == "Custom JQL" then
      key = key .. ":" .. (state.custom_jql or "")
    end
  end
  return key
end

return M
