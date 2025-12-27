---@class JiraData
---@field jql string
---@field fields string[]
---@field nextPageToken string
---@field maxResults integer

-- api.lua: Jira REST API client using curl
local config = require("jira.common.config")
local util = require("jira.common.util")

-- Get environment variables
---@return JiraAuthOptions auth_opts
local function get_env()
  local env = {}

  -- Check environment variables first, fall back to config
  env.base = os.getenv("JIRA_BASE_URL") or config.options.jira.base
  env.email = os.getenv("JIRA_EMAIL") or config.options.jira.email
  env.token = os.getenv("JIRA_TOKEN") or config.options.jira.token
  env.limit = config.options.jira.limit

  return env
end

-- Validate environment variables
---@return boolean valid
local function validate_env()
  local env = get_env()
  if not env.base then
    vim.notify("Missing Jira base URL. Please check your setup.", vim.log.levels.ERROR)
    return false
  end
  
  if not env.token or env.token == "" then
    vim.notify("Missing Jira token. Please check your setup.", vim.log.levels.ERROR)
    return false
  end
  
  local auth_type = env.auth_type or "basic"
  if auth_type == "basic" and (not env.email or env.email == "") then
    vim.notify("Missing Jira email. Required for basic auth type.", vim.log.levels.ERROR)
    return false
  end
  
  return true
end

---Execute curl command asynchronously
---@param method string
---@param endpoint string
---@param data? table
---@param callback? fun(T?: table, err?: string)
local function curl_request(method, endpoint, data, callback)
  if not validate_env() then
    if callback and vim.is_callable(callback) then
      callback(nil, "Missing environment variables")
    end
    return
  end

  local env = get_env()
  local url = env.base .. endpoint
  local auth_type = env.auth_type or "basic"
  local debug = env.debug or false

  -- Build curl command with authentication
  local cmd
  if auth_type == "bearer" then
    -- Use bearer token authentication
    cmd = ('curl -s -X %s -H "Content-Type: application/json" -H "Accept: application/json" -H "Authorization: Bearer %s" '):format(
      method,
      env.token
    )
    if debug then
      vim.notify(string.format("[Jira Debug] Using bearer token auth for %s %s", method, endpoint), vim.log.levels.INFO)
    end
  else
    -- Use basic authentication (email + token)
    local auth = env.email .. ":" .. env.token
    cmd = ('curl -s -X %s -H "Content-Type: application/json" -H "Accept: application/json" -u "%s" '):format(
      method,
      auth
    )
    if debug then
      vim.notify(string.format("[Jira Debug] Using basic auth for %s %s", method, endpoint), vim.log.levels.INFO)
    end
  end

  local temp_file = nil
  if data then
    local json_data = vim.json.encode(data)
    if debug then
      vim.notify(string.format("[Jira Debug] Request data: %s", json_data), vim.log.levels.INFO)
    end
    -- Escape quotes for shell
    json_data = json_data:gsub('"', '\\"')
    cmd = ('%s-d "%s" '):format(cmd, json_data)
  end

  cmd = ('%s"%s"'):format(cmd, url)
  
  if debug then
    -- Print sanitized command (mask auth details)
    local debug_cmd = cmd:gsub("Bearer [^%s]+", "Bearer ***")
    debug_cmd = debug_cmd:gsub("-u %\"[^\"]+\"", "-u \"***\"")
    vim.notify(string.format("[Jira Debug] Full URL: %s", url), vim.log.levels.INFO)
  end

  local stdout = {}
  local stderr = {}

  vim.fn.jobstart(cmd, {
    on_stdout = function(_, d, _)
      for _, chunk in ipairs(d) do
        if chunk ~= "" then
          table.insert(stdout, chunk)
        end
      end
    end,
    on_stderr = function(_, d, _)
      for _, chunk in ipairs(d) do
        if chunk ~= "" then
          table.insert(stderr, chunk)
        end
      end
    end,
    on_exit = function(_, code, _)
      if temp_file then
        os.remove(temp_file)
      end

      if code ~= 0 then
        local error_msg = table.concat(stderr, "\n")
        if error_msg == "" then
          error_msg = "Curl failed with exit code " .. code
        end
        if debug then
          vim.notify(string.format("[Jira Debug] Request failed: %s", error_msg), vim.log.levels.ERROR)
        end
        if callback then
          callback(nil, "Curl failed: " .. error_msg)
        end
        return
      end

      local response = table.concat(stdout, "")
      if debug then
        local preview = response:sub(1, 500)
        if #response > 500 then preview = preview .. "..." end
        vim.notify(string.format("[Jira Debug] Response (%d bytes): %s", #response, preview), vim.log.levels.INFO)
      end
      
      if not response or response == "" then
        -- Return empty table for success with no content (e.g. 204 No Content)
        if debug then
          vim.notify("[Jira Debug] Empty response (success)", vim.log.levels.INFO)
        end
        if callback and vim.is_callable(callback) then
          callback({}, nil)
        end
        return
      end

      -- Parse JSON
      local ok, result = pcall(vim.json.decode, response)
      if not ok then
        if debug then
          vim.notify(string.format("[Jira Debug] JSON parse failed: %s", tostring(result)), vim.log.levels.ERROR)
        end
        if callback and vim.is_callable(callback) then
          callback(nil, "Failed to parse JSON: " .. tostring(result) .. " | Resp: " .. response)
        end
        return
      end

      if callback and vim.is_callable(callback) then
        callback(result, nil)
      end
    end,
  })
end

---@class Jira.API
local M = {}

-- Search for issues using JQL
---@param jql string
---@param fields? string[]
---@param page_token? string
---@param max_results? integer
---@param callback? fun(T?: table, err?: string)
---@param project_key? string
function M.search_issues(jql, page_token, max_results, fields, callback, project_key)
  local story_point_field = config.get_project_config(project_key).story_point_field
  fields = fields
    or {
      "summary",
      "status",
      "parent",
      "priority",
      "assignee",
      "timespent",
      "timeoriginalestimate",
      "issuetype",
      story_point_field,
    }

  local env = config.options.jira
  local use_jql_post = env.use_jql_post ~= false -- default to true

  if use_jql_post then
    -- Use POST /search/jql endpoint (newer API)
    local data = {
      jql = jql,
      fields = fields,
      nextPageToken = page_token or "",
      maxResults = max_results or 100,
    }
    curl_request("POST", "/rest/api/3/search/jql", data, callback)
  else
    -- Use standard POST /search endpoint
    local start_at = 0
    if page_token and page_token ~= "" then
      start_at = tonumber(page_token) or 0
    end
    
    local data = {
      jql = jql,
      fields = fields,
      startAt = start_at,
      maxResults = max_results or 100,
    }
    
    curl_request("POST", "/rest/api/3/search", data, function(result, err)
      if err then
        if callback then callback(nil, err) end
        return
      end
      
      -- Convert standard search response to match /search/jql format
      if result and result.issues then
        local converted = {
          issues = result.issues,
          total = result.total,
        }
        
        -- Add nextPageToken if there are more results
        local next_start = result.startAt + #result.issues
        if next_start < result.total then
          converted.nextPageToken = tostring(next_start)
        end
        
        if callback then callback(converted, nil) end
      else
        if callback then callback(result, nil) end
      end
    end)
  end
end

-- Get available transitions for an issue
function M.get_transitions(issue_key, callback)
  curl_request("GET", "/rest/api/3/issue/" .. issue_key .. "/transitions", nil, function(result, err)
    local is_fun = (callback and vim.is_callable(callback))
    if err then
      if callback and is_fun then
        callback(nil, err)
      end
      return
    end
    if callback and is_fun then
      callback(result.transitions or {}, nil)
    end
  end)
end

---Transition an issue to a new status
---@param issue_key string
---@param callback? fun(cond?: boolean, err?: string)
function M.transition_issue(issue_key, transition_id, callback)
  local data = { transition = { id = transition_id } }
  curl_request("POST", "/rest/api/3/issue/" .. issue_key .. "/transitions", data, function(_, err)
    if err then
      if callback and vim.is_callable(callback) then
        callback(nil, err)
      end
      return
    end
    if callback and vim.is_callable(callback) then
      callback(true, nil)
    end
  end)
end

-- Add worklog to an issue
---@param comment? string|fun(cond?: boolean, err?: string)
---@param callback? fun(cond?: boolean, err?: string)
function M.add_worklog(issue_key, time_spent, comment, callback)
  -- Support previous signature: (issue_key, time_spent, callback)
  if type(comment) == "function" and vim.is_callable(comment) then
    callback = comment
    comment = nil
  end

  local data = {
    timeSpent = time_spent,
  }

  if comment and comment ~= "" then
    data.comment = {
      type = "doc",
      version = 1,
      content = {
        {
          type = "paragraph",
          content = {
            {
              type = "text",
              text = comment,
            },
          },
        },
      },
    }
  end

  curl_request("POST", "/rest/api/3/issue/" .. issue_key .. "/worklog", data, function(_, err)
    if err then
      if callback and vim.is_callable(callback) then
        callback(nil, err)
      end
      return
    end
    if callback and vim.is_callable(callback) then
      callback(true, nil)
    end
  end)
end

-- Assign an issue to a user
---@param callback? fun(cond?: boolean, err?: string)
function M.assign_issue(issue_key, account_id, callback)
  local data = {
    accountId = account_id,
  }

  curl_request("PUT", "/rest/api/3/issue/" .. issue_key .. "/assignee", data, function(_, err)
    if err then
      if callback and vim.is_callable(callback) then
        callback(nil, err)
      end
      return
    end
    if callback and vim.is_callable(callback) then
      callback(true, nil)
    end
  end)
end

-- Get current user details
function M.get_myself(callback)
  curl_request("GET", "/rest/api/3/myself", nil, callback)
end

-- Get issue details
---@param issue_key string
---@param callback function
function M.get_issue(issue_key, callback)
  curl_request("GET", "/rest/api/3/issue/" .. issue_key, nil, callback)
end

-- Get statuses for a project
function M.get_project_statuses(project, callback)
  curl_request("GET", "/rest/api/3/project/" .. project .. "/statuses", nil, callback)
end

-- Get comments for an issue
function M.get_comments(issue_key, callback)
  curl_request("GET", "/rest/api/3/issue/" .. issue_key .. "/comment", nil, function(result, err)
    if err then
      if callback then
        callback(nil, err)
      end
      return
    end
    if callback then
      callback(result.comments or {}, nil)
    end
  end)
end

-- Add comment to an issue
function M.add_comment(issue_key, comment, callback)
  local body
  if type(comment) == "string" then
    body = util.markdown_to_adf(comment)
  else
    body = comment
  end

  local data = {
    body = body,
  }

  curl_request("POST", "/rest/api/3/issue/" .. issue_key .. "/comment", data, function(_, err)
    if err then
      if callback then
        callback(nil, err)
      end
      return
    end
    if callback then
      callback(true, nil)
    end
  end)
end

-- Edit a comment
function M.edit_comment(issue_key, comment_id, comment, callback)
  local body
  if type(comment) == "string" then
    body = util.markdown_to_adf(comment)
  else
    body = comment
  end

  local data = {
    body = body,
  }

  curl_request("PUT", "/rest/api/3/issue/" .. issue_key .. "/comment/" .. comment_id, data, function(_, err)
    if err then
      if callback then
        callback(nil, err)
      end
      return
    end
    if callback then
      callback(true, nil)
    end
  end)
end

-- Update issue
---@param issue_key string
---@param fields table
---@param callback? fun(result?: table, err?: string)
function M.update_issue(issue_key, fields, callback)
  local data = {
    fields = fields,
  }

  curl_request("PUT", "/rest/api/3/issue/" .. issue_key, data, function(result, err)
    if err then
      if callback and vim.is_callable(callback) then
        callback(nil, err)
      end
      return
    end
    if callback and vim.is_callable(callback) then
      callback(result, nil)
    end
  end)
end

-- Create issue
---@param fields table
---@param callback? fun(result?: table, err?: string)
function M.create_issue(fields, callback)
  local data = {
    fields = fields,
  }

  curl_request("POST", "/rest/api/3/issue", data, function(result, err)
    if err then
      if callback and vim.is_callable(callback) then
        callback(nil, err)
      end
      return
    end

    if result and (result.errorMessages or result.errors) then
      local errors = {}
      if result.errorMessages then
        for _, msg in ipairs(result.errorMessages) do
          table.insert(errors, msg)
        end
      end
      if result.errors then
        for k, v in pairs(result.errors) do
          table.insert(errors, k .. ": " .. v)
        end
      end

      if #errors > 0 then
        if callback and vim.is_callable(callback) then
          callback(nil, table.concat(errors, "\n"))
        end
        return
      end
    end

    if callback and vim.is_callable(callback) then
      callback(result, nil)
    end
  end)
end

-- Get create metadata (issue types) for a project
function M.get_create_meta(project_key, callback)
  curl_request("GET", "/rest/api/3/issue/createmeta?projectKeys=" .. project_key, nil, function(result, err)
    if err then
      if callback and vim.is_callable(callback) then
        callback(nil, err)
      end
      return
    end
    if callback and vim.is_callable(callback) then
      -- Result structure: { projects: [ { key: "PROJ", issuetypes: [ ... ] } ] }
      local project_data = result.projects and result.projects[1]
      if project_data then
        callback(project_data.issuetypes, nil)
      else
        callback({}, nil)
      end
    end
  end)
end

-- Get boards for a project (Agile API)
function M.get_boards(project_key, callback)
  local endpoint = "/rest/agile/1.0/board?projectKeyOrId=" .. project_key
  curl_request("GET", endpoint, nil, callback)
end

-- Get active sprints for a board (Agile API)
function M.get_active_sprints(board_id, callback)
  local endpoint = "/rest/agile/1.0/board/" .. board_id .. "/sprint?state=active"
  curl_request("GET", endpoint, nil, callback)
end

-- Get issues in a sprint (Agile API)
function M.get_sprint_issues(sprint_id, start_at, max_results, callback)
  local endpoint = ("/rest/agile/1.0/sprint/%s/issue?startAt=%d&maxResults=%d"):format(
    sprint_id,
    start_at or 0,
    max_results or 100
  )
  curl_request("GET", endpoint, nil, callback)
end

return M
-- vim: set ts=2 sts=2 sw=2 et ai si sta:
