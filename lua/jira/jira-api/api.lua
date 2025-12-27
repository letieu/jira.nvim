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
  return config.options.jira
end

-- Build API path with correct version
---@param path string The API path without version (e.g. "/issue/KEY-123")
---@return string The full path with version (e.g. "/rest/api/3/issue/KEY-123")
local function api_path(path)
  local env = get_env()
  local version = env.api_version or "3"
  return "/rest/api/" .. version .. path
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

-- Cache for current user info
local current_user_cache = nil

-- Get current user with caching
---@param callback fun(user?: table, err?: string)
function M.get_current_user(callback)
  if current_user_cache then
    if callback then callback(current_user_cache, nil) end
    return
  end
  
  M.get_myself(function(user, err)
    if not err and user then
      current_user_cache = user
    end
    if callback then callback(user, err) end
  end)
end

-- Resolve JQL with currentUser() function
---@param jql string
---@param callback fun(resolved_jql?: string, err?: string)
function M.resolve_jql_current_user(jql, callback)
  -- If JQL doesn't contain currentUser(), return as-is
  if not jql:find("currentUser%(%)") then
    if callback then callback(jql, nil) end
    return
  end
  
  -- Try to use currentUser() as-is first (works in most cases)
  -- Only replace if explicitly needed based on config
  local env = config.options.jira
  if not env.resolve_current_user then
    if callback then callback(jql, nil) end
    return
  end
  
  -- Fetch current user and replace currentUser() with accountId
  M.get_current_user(function(user, err)
    if err or not user or not user.accountId then
      -- Fallback to original JQL if we can't get user info
      if callback then callback(jql, nil) end
      return
    end
    
    -- Replace currentUser() with accountId
    local resolved = jql:gsub("currentUser%(%)", '"' .. user.accountId .. '"')
    if callback then callback(resolved, nil) end
  end)
end

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
    curl_request("POST", api_path("/search/jql"), data, callback)
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
    
    curl_request("POST", api_path("/search"), data, function(result, err)
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
  curl_request("GET", api_path("/issue/" .. issue_key .. "/transitions"), nil, function(result, err)
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
  curl_request("POST", api_path("/issue/" .. issue_key .. "/transitions"), data, function(_, err)
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

  curl_request("POST", api_path("/issue/" .. issue_key .. "/worklog"), data, function(_, err)
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

  curl_request("PUT", api_path("/issue/" .. issue_key .. "/assignee"), data, function(_, err)
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
  curl_request("GET", api_path("/myself"), nil, callback)
end

-- Get issue details
---@param issue_key string
---@param callback function
function M.get_issue(issue_key, callback)
  curl_request("GET", api_path("/issue/" .. issue_key), nil, callback)
end

-- Get statuses for a project
function M.get_project_statuses(project, callback)
  curl_request("GET", api_path("/project/" .. project .. "/statuses"), nil, callback)
end

-- Get comments for an issue
function M.get_comments(issue_key, callback)
  curl_request("GET", api_path("/issue/" .. issue_key .. "/comment"), nil, function(result, err)
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

  curl_request("POST", api_path("/issue/" .. issue_key .. "/comment"), data, function(_, err)
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

  curl_request("PUT", api_path("/issue/" .. issue_key .. "/comment/" .. comment_id), data, function(_, err)
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
function M.get_sprint_issues(sprint_id, start_at, max_results, fields, callback)
  local field_list = fields or "summary,status,parent,priority,assignee,timespent,timeoriginalestimate,issuetype"
  local endpoint = ("/rest/agile/1.0/sprint/%s/issue?startAt=%d&maxResults=%d&fields=%s"):format(
    sprint_id,
    start_at or 0,
    max_results or 100,
    field_list
  )
  curl_request("GET", endpoint, nil, callback)
end

-- Cache for board/sprint lookups
local board_cache = {}
local sprint_cache = {}

-- Get boards with caching
function M.get_boards_cached(project_key, callback)
  if board_cache[project_key] then
    if callback then callback(board_cache[project_key], nil) end
    return
  end
  
  M.get_boards(project_key, function(result, err)
    if not err and result then
      board_cache[project_key] = result
    end
    if callback then callback(result, err) end
  end)
end

-- Get active sprints with caching
function M.get_active_sprints_cached(board_id, callback)
  local cache_key = tostring(board_id)
  local cached = sprint_cache[cache_key]
  
  -- Cache for 30 seconds
  if cached and (os.time() - cached.time) < 30 then
    if callback then callback(cached.data, nil) end
    return
  end
  
  M.get_active_sprints(board_id, function(result, err)
    if not err and result then
      sprint_cache[cache_key] = {
        data = result,
        time = os.time()
      }
    end
    if callback then callback(result, err) end
  end)
end

return M
-- vim: set ts=2 sts=2 sw=2 et ai si sta:
