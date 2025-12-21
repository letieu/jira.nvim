-- sprint.lua: Sprint queries and task grouping
local api = require("jira.jira-api.api")
local config = require("jira.state").config
local M = {}

-- Cache for sprint data
local cache = {
  data = nil,
  timestamp = 0,
  ttl = 60, -- 60 seconds cache
}

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

-- Get current active sprint issues
function M.get_active_sprint_issues()
  local now = os.time()
  if cache.data and (now - cache.timestamp) < cache.ttl then
    return cache.data, nil
  end

  local project = config.jira.project
  if not project then
    return nil, "JIRA_PROJECT not set"
  end

  local jql = string.format(
    "project = %s AND sprint in openSprints() ORDER BY Rank ASC",
    project
  )

  local all_issues = {}
  local next_page_token = ""
  local max_results = 100

  while true do
    local result, err = api.search_issues(jql, next_page_token, max_results)
    if err then
      return nil, err
    end

    if not result or not result.issues then
      break
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

      if is_valid(fields.timeestimate) then
        time_estimate = fields.timeestimate
      end

      local story_point_field = config.jira.story_point_field
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

    if result.isLast == true then
      break
    end

    next_page_token = result.nextPageToken
  end

  cache.data = all_issues
  cache.timestamp = now

  return all_issues, nil
end

-- Clear cache
function M.clear_cache()
  cache.data = nil
  cache.timestamp = 0
end

return M
