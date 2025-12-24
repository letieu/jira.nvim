-- sprint.lua: Sprint queries and task grouping
local api = require("jira.jira-api.api")
local config = require("jira.common.config")
local M = {}

-- Helper to safely check if a value is not nil/vim.NIL
local function is_valid(value)
  return value ~= nil and type(value) ~= "userdata"
end

-- Helper to safely get nested table value
local function safe_get(obj, key, subkey)
  if not is_valid(obj) then
    return nil
  end
  local val = obj[key]
  if subkey then
    if not is_valid(val) then
      return nil
    end
    return val[subkey]
  end
  return val
end

local function fetch_issues_recursive(project, jql, callback)
  local all_issues = {}
  local p_config = config.get_project_config(project)
  local story_point_field = p_config.story_point_field
  local limit = config.options.jira.limit or 200

  local function fetch_page(page_token)
    api.search_issues(jql, page_token, 100, nil, function(result, err)
      if err then
        if callback then
          callback(nil, err)
        end
        return
      end

      if not result or not result.issues then
        if callback then
          callback(all_issues, nil)
        end
        return
      end

      for _, issue in ipairs(result.issues) do
        local fields = issue.fields

        local status = safe_get(fields, "status", "name") or "Unknown"
        local parent_key = safe_get(fields, "parent", "key")
        local priority = safe_get(fields, "priority", "name") or "None"
        local assignee = safe_get(fields, "assignee", "displayName") or "Unassigned"
        local issue_type = safe_get(fields, "issuetype", "name") or "Task"

        local time_spent = nil
        local time_estimate = nil

        if is_valid(fields.timespent) then
          time_spent = fields.timespent
        end

        if is_valid(fields.timeoriginalestimate) then
          time_estimate = fields.timeoriginalestimate
        end

        local story_points = safe_get(fields, story_point_field)

        table.insert(all_issues, {
          key = issue.key,
          summary = fields.summary or "",
          status = status,
          parent = parent_key,
          priority = priority,
          assignee = assignee,
          time_spent = time_spent,
          time_estimate = time_estimate,
          type = issue_type,
          story_points = story_points,
        })
      end

      if not result.nextPageToken or #all_issues >= limit then
        if callback then
          callback(all_issues, nil)
        end
      else
        fetch_page(result.nextPageToken)
      end
    end, project)
  end

  fetch_page("")
end

-- Get current active sprint issues
function M.get_active_sprint_issues(project, callback)
  if not project then
    if callback then
      callback(nil, "Project Key is required")
    end
    return
  end

  local jql = string.format("project = '%s' AND sprint in openSprints() ORDER BY Rank ASC", project)

  fetch_issues_recursive(project, jql, callback)
end

-- Get backlog issues
function M.get_backlog_issues(project, callback)
  if not project then
    if callback then
      callback(nil, "Project Key is required")
    end
    return
  end

  local jql = string.format(
    "project = '%s' AND (sprint is EMPTY OR sprint not in openSprints()) AND issuetype not in (Epic) AND statusCategory != Done ORDER BY Rank ASC",
    project
  )

  fetch_issues_recursive(project, jql, callback)
end

-- Get issues by custom JQL
function M.get_issues_by_jql(project, jql, callback)
  if not project then
    if callback then
      callback(nil, "Project Key is required")
    end
    return
  end

  fetch_issues_recursive(project, jql, callback)
end

return M
-- vim: set ts=2 sts=2 sw=2 et ai si sta:
