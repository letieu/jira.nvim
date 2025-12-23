local M = {}

local FALLBACKS = {
  story_point_field = "customfield_10035",
  custom_fields = {
    -- { key = "customfield_10016", label = "Acceptance Criteria" }
  },
}

---@class JiraConfig
---@field jira JiraAuthOptions
---@field projects? table<string, table> Project-specific overrides
---@field queries? table<string, string> Saved JQL queries

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
    limit = 200,
  },
  projects = {},
  queries = {
    ["Backlog"] =
    "project = '%s' AND (sprint is EMPTY OR sprint not in openSprints()) AND statusCategory != Done ORDER BY Rank ASC",
    ["My Tasks"] = "assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC",
  }
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
    custom_fields = p_config.custom_fields or FALLBACKS.custom_fields,
  }
end

return M
