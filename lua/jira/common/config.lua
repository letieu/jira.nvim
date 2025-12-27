---@class Jira.Common.Config
local M = {}

local FALLBACKS = {
  story_point_field = "customfield_10035",
  custom_fields = {
    -- { key = "customfield_10016", label = "Acceptance Criteria" }
  },
}

---@class JiraAuthOptions
---@field base string URL of your Jira instance (e.g. https://your-domain.atlassian.net)
---@field email? string Your Jira email (required if auth_type is "basic")
---@field token string Your Jira API token or bearer token
---@field auth_type? "basic"|"bearer" Authentication type (default: "basic")
---@field use_jql_post? boolean Use POST /search/jql endpoint instead of POST /search (default: true)
---@field resolve_current_user? boolean Replace currentUser() with accountId in JQL (default: false)
---@field debug? boolean Enable debug logging for API calls (default: false)
---@field limit? number Global limit of tasks when calling API

---@class JiraConfig
---@field jira JiraAuthOptions
---@field projects? table<string, table> Project-specific overrides
---@field queries? table<string, string> Saved JQL queries
M.defaults = {
  jira = {
    base = "",
    email = "",
    token = "",
    auth_type = "basic",
    use_jql_post = true,
    resolve_current_user = false,
    debug = false,
    limit = 200,
  },
  projects = {},
  queries = {
    ["Next sprint"] = "project = '%s' AND sprint in futureSprints() ORDER BY Rank ASC",
    ["Backlog"] = "project = '%s' AND (issuetype IN standardIssueTypes() OR issuetype = Sub-task) AND (sprint IS EMPTY OR sprint NOT IN openSprints()) AND statusCategory != Done ORDER BY Rank ASC",
    ["My Tasks"] = "assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC",
  },
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
-- vim: set ts=2 sts=2 sw=2 et ai si sta:
