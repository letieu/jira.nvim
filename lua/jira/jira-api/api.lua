---@class JiraData
---@field jql string
---@field fields string[]
---@field nextPageToken string
---@field maxResults integer

-- api.lua: Jira REST API client using curl
local config = require("jira.common.config")
local util = require("jira.common.util")
local version = require("jira.jira-api.version")

-- Get environment variables
---@return JiraAuthOptions auth_opts
local function get_env()
  local env = {}

  -- Check environment variables first, fall back to config
  env.base = os.getenv("JIRA_BASE_URL") or config.options.jira.base
  env.email = os.getenv("JIRA_EMAIL") or config.options.jira.email
  env.token = os.getenv("JIRA_TOKEN") or config.options.jira.token
  env.type = (os.getenv("JIRA_AUTH_TYPE") or config.options.jira.type or "basic"):lower()
  env.api_version = os.getenv("JIRA_API_VERSION") or config.options.jira.api_version or "3"
  env.limit = config.options.jira.limit

  return env
end

-- Validate environment variables
---@return boolean valid
local function validate_env()
  local env = get_env()
  local is_pat = env.type == "pat"
  if not env.base or (not is_pat and not env.email) or not env.token then
    vim.notify("Missing Jira environment variables. Please check your setup.", vim.log.levels.ERROR)
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

  -- Build curl command
  local auth_header = ""
  if env.type == "pat" then
    auth_header = ('-H "Authorization: Bearer %s"'):format(env.token)
  else
    auth_header = ('-u "%s:%s"'):format(env.email, env.token)
  end

  local cmd = ('curl -s -X %s -H "Content-Type: application/json" -H "Accept: application/json" %s '):format(
    method,
    auth_header
  )

  local temp_file = nil
  if data then
    local json_data = vim.json.encode(data)
    temp_file = vim.fn.tempname()
    local f = io.open(temp_file, "w")
    if f then
      f:write(json_data)
      f:close()
      cmd = ("%s-d @%s "):format(cmd, temp_file)
    else
      if callback and vim.is_callable(callback) then
        callback(nil, "Failed to create temp file")
      end
      return
    end
  end

  cmd = ('%s"%s"'):format(cmd, url)

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
        if callback then
          callback(nil, "Curl failed: " .. table.concat(stderr, "\n"))
        end
        return
      end

      local response = table.concat(stdout, "")
      if not response or response == "" then
        -- Return empty table for success with no content (e.g. 204 No Content)
        if callback and vim.is_callable(callback) then
          callback({}, nil)
        end
        return
      end

      -- Parse JSON
      local ok, result = pcall(vim.json.decode, response)
      if not ok then
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

  local data = version.transform_search_data(jql, page_token, max_results, fields)
  local endpoint = version.get_search_endpoint()

  curl_request("POST", endpoint, data, function(result, err)
    if err then
      if callback and vim.is_callable(callback) then
        callback(nil, err)
      end
      return
    end

    local transformed_result = version.transform_search_response(result)
    if callback and vim.is_callable(callback) then
      callback(transformed_result, nil)
    end
  end)
end

-- Get available transitions for an issue
function M.get_transitions(issue_key, callback)
  local endpoint = version.get_api_path() .. "/issue/" .. issue_key .. "/transitions"
  curl_request("GET", endpoint, nil, function(result, err)
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
  local endpoint = version.get_api_path() .. "/issue/" .. issue_key .. "/transitions"
  curl_request("POST", endpoint, data, function(_, err)
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
    data.comment = version.transform_comment_data(comment).body
  end

  local endpoint = version.get_api_path() .. "/issue/" .. issue_key .. "/worklog"
  curl_request("POST", endpoint, data, function(_, err)
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

  local endpoint = version.get_api_path() .. "/issue/" .. issue_key .. "/assignee"
  curl_request("PUT", endpoint, data, function(_, err)
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
  local endpoint = version.get_api_path() .. "/myself"
  curl_request("GET", endpoint, nil, callback)
end

-- Get issue details
---@param issue_key string
---@param callback function
function M.get_issue(issue_key, callback)
  local endpoint = version.get_api_path() .. "/issue/" .. issue_key
  curl_request("GET", endpoint, nil, function(result, err)
    if err then
      if callback and vim.is_callable(callback) then
        callback(nil, err)
      end
      return
    end

    -- Ensure the response has the expected structure
    if result and not result.key then
      result.key = issue_key
    end

    if callback and vim.is_callable(callback) then
      callback(result, nil)
    end
  end)
end

-- Get statuses for a project
function M.get_project_statuses(project, callback)
  local endpoint = version.get_api_path() .. "/project/" .. project .. "/statuses"
  curl_request("GET", endpoint, nil, callback)
end

-- Get comments for an issue
function M.get_comments(issue_key, callback)
  local endpoint = version.get_api_path() .. "/issue/" .. issue_key .. "/comment"
  curl_request("GET", endpoint, nil, function(result, err)
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
  local data = version.transform_comment_data(comment)
  local endpoint = version.get_api_path() .. "/issue/" .. issue_key .. "/comment"

  curl_request("POST", endpoint, data, function(_, err)
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
  local data = version.transform_comment_data(comment)
  local endpoint = version.get_api_path() .. "/issue/" .. issue_key .. "/comment/" .. comment_id

  curl_request("PUT", endpoint, data, function(_, err)
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

  local endpoint = version.get_api_path() .. "/issue/" .. issue_key
  curl_request("PUT", endpoint, data, function(result, err)
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

  local endpoint = version.get_api_path() .. "/issue"
  curl_request("POST", endpoint, data, function(result, err)
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

    -- Ensure result has key field for both v2 and v3
    if result and not result.key and result.id then
      -- For some responses, we might need to fetch the issue to get the key
      M.get_issue(result.id, callback)
      return
    end

    if callback and vim.is_callable(callback) then
      callback(result, nil)
    end
  end)
end

-- Get create metadata (issue types) for a project
function M.get_create_meta(project_key, callback)
  local endpoint = version.get_api_path() .. "/issue/createmeta?projectKeys=" .. project_key
  curl_request("GET", endpoint, nil, function(result, err)
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

return M
-- vim: set ts=2 sts=2 sw=2 et ai si sta:
