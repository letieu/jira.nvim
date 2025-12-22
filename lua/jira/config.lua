local M = {}

local FALLBACKS = {
  story_point_field = "customfield_10035",
  acceptance_criteria_field = "customfield_10016",
}

---@class JiraConfig
---@field jira JiraAuthOptions
---@field projects? table<string, table> Project-specific overrides

---@class JiraAuthOptions
---@field base string URL of your Jira instance (e.g. https://your-domain.atlassian.net)
---@field email string Your Jira email
---@field token string Your Jira API token
---@field limit? number Global limit of tasks when calling API

---@type JiraConfig
M.defaults = {
  jira = {
    base = "",
    email = "",
    token = "",
    limit = 500,
  },
  projects = {}
}

---@type JiraConfig
M.options = vim.deepcopy(M.defaults)

---@param opts JiraConfig
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

---@param project_key string|nil
---@return table
function M.get_project_config(project_key)
  local projects = M.options.projects or {}
  local p_config = projects[project_key] or {}

  return {
    story_point_field = p_config.story_point_field or FALLBACKS.story_point_field,
    acceptance_criteria_field = p_config.acceptance_criteria_field or FALLBACKS.acceptance_criteria_field,
  }
end

return M
