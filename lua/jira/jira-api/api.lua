-- api.lua: Jira REST API client using curl
local config = require("jira.config")
local M = {}

-- Get environment variables
local function get_env()
  return config.options.jira
end

-- Validate environment variables
local function validate_env()
  local env = get_env()
  if not env.base or not env.email or not env.token then
    vim.notify(
      "Missing Jira environment variables. Please check your setup.",
      vim.log.levels.ERROR
    )
    return false
  end
  return true
end

-- Execute curl command asynchronously
local function curl_request(method, endpoint, data, callback)
  if not validate_env() then
    if callback then callback(nil, "Missing environment variables") end
    return
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

  local stdout = {}
  local stderr = {}

  vim.fn.jobstart(cmd, {
    on_stdout = function(_, d, _)
      for _, chunk in ipairs(d) do
        if chunk ~= "" then table.insert(stdout, chunk) end
      end
    end,
    on_stderr = function(_, d, _)
      for _, chunk in ipairs(d) do
        if chunk ~= "" then table.insert(stderr, chunk) end
      end
    end,
    on_exit = function(_, code, _)
      if code ~= 0 then
        if callback then callback(nil, "Curl failed: " .. table.concat(stderr, "\n")) end
        return
      end

      local response = table.concat(stdout, "")
      if not response or response == "" then
        -- Return empty table for success with no content (e.g. 204 No Content)
        if callback then callback({}, nil) end
        return
      end

      -- Parse JSON
      local ok, result = pcall(vim.json.decode, response)
      if not ok then
        if callback then callback(nil, "Failed to parse JSON: " .. tostring(result) .. " | Resp: " .. response) end
        return
      end

      if callback then callback(result, nil) end
    end,
  })
end

-- Search for issues using JQL
function M.search_issues(jql, page_token, max_results, fields, callback, project_key)
  local p_config = config.get_project_config(project_key)
  local story_point_field = p_config.story_point_field
  fields = fields or
  { "summary", "status", "parent", "priority", "assignee", "timespent", "timeoriginalestimate", "issuetype",
    story_point_field }

  local data = {
    jql = jql,
    fields = fields,
    nextPageToken = page_token or "",
    maxResults = max_results or 100,
  }

  curl_request("POST", "/rest/api/3/search/jql", data, callback)
end

-- Get available transitions for an issue
function M.get_transitions(issue_key, callback)
  curl_request("GET", "/rest/api/3/issue/" .. issue_key .. "/transitions", nil, function(result, err)
    if err then
      if callback then callback(nil, err) end
      return
    end
    if callback then callback(result.transitions or {}, nil) end
  end)
end

-- Transition an issue to a new status
function M.transition_issue(issue_key, transition_id, callback)
  local data = {
    transition = {
      id = transition_id,
    },
  }

  curl_request("POST", "/rest/api/3/issue/" .. issue_key .. "/transitions", data, function(result, err)
    if err then
      if callback then callback(nil, err) end
      return
    end
    if callback then callback(true, nil) end
  end)
end

-- Add worklog to an issue
function M.add_worklog(issue_key, time_spent, callback)
  local data = {
    timeSpent = time_spent,
  }

  curl_request("POST", "/rest/api/3/issue/" .. issue_key .. "/worklog", data, function(result, err)
    if err then
      if callback then callback(nil, err) end
      return
    end
    if callback then callback(true, nil) end
  end)
end

-- Assign an issue to a user
function M.assign_issue(issue_key, account_id, callback)
  local data = {
    accountId = account_id,
  }

  curl_request("PUT", "/rest/api/3/issue/" .. issue_key .. "/assignee", data, function(result, err)
    if err then
      if callback then callback(nil, err) end
      return
    end
    if callback then callback(true, nil) end
  end)
end

-- Get current user details
function M.get_myself(callback)
  curl_request("GET", "/rest/api/3/myself", nil, callback)
end

-- Get issue details
function M.get_issue(issue_key, callback)
  curl_request("GET", "/rest/api/3/issue/" .. issue_key, nil, callback)
end

-- Get statuses for a project
function M.get_project_statuses(project, callback)
  curl_request("GET", "/rest/api/3/project/" .. project .. "/statuses", nil, callback)
end

return M

