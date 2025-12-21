-- api.lua: Jira REST API client using curl
local config = require("jira.state").config
local M = {}

-- Get environment variables
local function get_env()
  return config.jira
end

-- Validate environment variables
local function validate_env()
  local env = get_env()
  if not env.base or not env.email or not env.token or not env.project then
    vim.notify(
      "Missing Jira environment variables. Please check your setup.",
      vim.log.levels.ERROR
    )
    return false
  end
  return true
end

-- Execute curl command and parse JSON response
local function curl_request(method, endpoint, data)
  if not validate_env() then
    return nil, "Missing environment variables"
  end

  local env = get_env()
  local url = env.base .. endpoint
  local auth = env.email .. ":" .. env.token

  -- Build curl command
  local cmd = string.format(
    'curl -s -X %s -H "Content-Type: application/json" -H "Accept: application/json" -u "%s" ',
    method,
    auth
  )

  if data then
    local json_data = vim.json.encode(data)
    -- Escape quotes for shell
    json_data = json_data:gsub('"', '\\"')
    cmd = cmd .. string.format('-d "%s" ',
      json_data)
  end

  cmd = cmd .. string.format('"%s"', url)

  -- Execute command
  local handle = io.popen(cmd)
  if not handle then
    return nil, "Failed to execute curl"
  end

  local response = handle:read("*a")
  handle:close()

  if not response or response == "" then
    return nil, "Empty response from Jira"
  end

  -- Parse JSON
  local ok, result = pcall(vim.json.decode, response)
  if not ok then
    return nil, "Failed to parse JSON: " .. tostring(result)
  end

  return result, nil
end

-- Search for issues using JQL
function M.search_issues(jql, page_token, max_results, fields)
  local story_point_field = config.jira.story_point_field
  fields = fields or { "summary", "status", "parent", "priority", "assignee", "timespent", "timeestimate", "issuetype", story_point_field }

  local data = {
    jql = jql,
    fields = fields,
    nextPageToken = page_token or "",
    maxResults = max_results or 100,
  }

  local result, err = curl_request("POST", "/rest/api/3/search/jql", data)
  if err then
    return nil, err
  end

  return result, nil
end

-- Get available transitions for an issue
function M.get_transitions(issue_key)
  local result, err = curl_request("GET", "/rest/api/3/issue/" .. issue_key .. "/transitions")
  if err then
    return nil, err
  end

  return result.transitions or {}, nil
end

-- Transition an issue to a new status
function M.transition_issue(issue_key, transition_id)
  local data = {
    transition = {
      id = transition_id,
    },
  }

  local result, err = curl_request("POST", "/rest/api/3/issue/" .. issue_key .. "/transitions", data)
  if err then
    return nil, err
  end

  return true, nil
end

-- Add worklog to an issue
function M.add_worklog(issue_key, time_spent)
  local data = {
    timeSpent = time_spent,
  }

  local result, err = curl_request("POST", "/rest/api/3/issue/" .. issue_key .. "/worklog", data)
  if err then
    return nil, err
  end

  return true, nil
end

-- Get issue details
function M.get_issue(issue_key)
  local result, err = curl_request("GET", "/rest/api/3/issue/" .. issue_key)
  if err then
    return nil, err
  end

  return result, nil
end

-- Get statuses for a project
function M.get_project_statuses(project)
  local result, err = curl_request("GET", "/rest/api/3/project/" .. project .. "/statuses")
  if err then
    return nil, err
  end

  return result, nil
end

return M
