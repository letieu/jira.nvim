-- sprint.lua: Sprint queries and task grouping
local api = require("jira.jira-api.api")
local config = require("jira.common.config")

-- Sprint cache with configurable TTL (default 2 weeks)
local sprint_cache = {}
local cache_file = vim.fn.stdpath("data") .. "/jira_sprint_cache.json"

-- Load cache from file on startup
local function load_cache_from_file()
  local f = io.open(cache_file, "r")
  if f then
    local content = f:read("*all")
    f:close()
    local ok, data = pcall(vim.json.decode, content)
    if ok and type(data) == "table" then
      sprint_cache = data
    end
  end
end

-- Save cache to file
local function save_cache_to_file()
  local ok, json = pcall(vim.json.encode, sprint_cache)
  if ok then
    local f = io.open(cache_file, "w")
    if f then
      f:write(json)
      f:close()
    end
  end
end

-- Initialize cache from file
load_cache_from_file()

-- Get sprint cache TTL from config
local function get_cache_ttl()
  return config.options.jira.sprint_cache_ttl or 1209600 -- 2 weeks default
end

-- Get cached sprint data for a project
local function get_cached_sprint(project)
  local cached = sprint_cache[project]
  if cached and (os.time() - cached.timestamp) < get_cache_ttl() then
    return cached
  end
  return nil
end

-- Save sprint data to cache
local function cache_sprint(project, board_id, sprint_id)
  sprint_cache[project] = {
    board_id = board_id,
    sprint_id = sprint_id,
    timestamp = os.time(),
  }
  save_cache_to_file()
end

-- Clear sprint cache for a project
local function clear_sprint_cache(project)
  if project then
    sprint_cache[project] = nil
  else
    sprint_cache = {}
  end
  save_cache_to_file()
end

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

---@param page_token string
---@param project string
---@param jql string
---@param limit integer
---@param callback? fun(all_issues?: table, err?: string)
local function fetch_page(page_token, project, all_issues, story_point_field, jql, limit, callback)
  ---@param result? { issues?: table, nextPageToken?: string }
  ---@param err? string
  api.search_issues(jql, page_token, 100, nil, function(result, err)
    if err then
      if callback and vim.is_callable(callback) then
        callback(nil, err)
      end
      return
    end

    if not result or not result.issues then
      if callback and vim.is_callable(callback) then
        callback(all_issues, nil)
      end
      return
    end

    for _, issue in ipairs(result.issues) do
      if not issue or not issue.key then
        goto continue
      end

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

      ::continue::
    end

    if not result.nextPageToken or #all_issues >= limit then
      if callback and vim.is_callable(callback) then
        callback(all_issues, nil)
      end
      return
    end

    fetch_page(result.nextPageToken, project, all_issues, story_point_field, jql, limit, callback)
  end, project)
end

---@param project string
---@param jql string
---@param callback fun(all_issues?: table, err?: string)
local function fetch_issues_recursive(project, jql, callback)
  fetch_page(
    "",
    project,
    {},
    config.get_project_config(project).story_point_field,
    jql,
    config.options.jira.limit or 200,
    callback
  )
end

---@class Jira.API.Sprint
local M = {}

-- Get current active sprint issues
---@param project string
---@param callback? fun(all_issues?: table, err?: string)
---@param force_refresh? boolean Force refresh sprint data
function M.get_active_sprint_issues(project, callback, force_refresh)
  if not project then
    if callback and vim.is_callable(callback) then
      callback(nil, "Project Key is required")
    end
    return
  end

  -- Check sprint cache first
  local cached_sprint = not force_refresh and get_cached_sprint(project)
  if cached_sprint then
    -- Use cached board_id and sprint_id directly
    local board_id = cached_sprint.board_id
    local sprint_id = cached_sprint.sprint_id
    local story_point_field = config.get_project_config(project).story_point_field
    local all_issues = {}
    local limit = config.options.jira.limit or 200
    local fields = "summary,status,parent,priority,assignee,timespent,timeoriginalestimate,issuetype," .. story_point_field

    local function fetch_sprint_issues(start_at)
      local page_size = math.min(100, limit - #all_issues)
      if page_size <= 0 then
        if callback and vim.is_callable(callback) then
          callback(all_issues, nil)
        end
        return
      end

      api.get_sprint_issues(board_id, sprint_id, start_at, page_size, fields, function(result, issue_err)
        if issue_err then
          if callback and vim.is_callable(callback) then
            callback(nil, "Failed to get sprint issues: " .. issue_err)
          end
          return
        end

        if result and result.issues then
          for _, issue in ipairs(result.issues) do
            table.insert(all_issues, issue)
          end
        end

        if result and result.total and #all_issues < result.total and #all_issues < limit then
          fetch_sprint_issues(#all_issues)
        else
          if callback and vim.is_callable(callback) then
            callback(all_issues, nil)
          end
        end
      end)
    end

    fetch_sprint_issues(0)
    return
  end

  -- If not cached, fetch board and sprint info
  api.get_boards_cached(project, function(board_result, err)
    if err then
      if callback and vim.is_callable(callback) then
        callback(nil, "Failed to get boards: " .. err)
      end
      return
    end

    if not board_result or not board_result.values or #board_result.values == 0 then
      if callback and vim.is_callable(callback) then
        callback(nil, "No boards found for project " .. project)
      end
      return
    end

    local board_id = board_result.values[1].id

    -- Use cached sprint lookup for faster subsequent requests
    api.get_active_sprints_cached(board_id, function(sprint_result, err)
      if err then
        if callback and vim.is_callable(callback) then
          callback(nil, "Failed to get active sprints: " .. err)
        end
        return
      end

      if not sprint_result or not sprint_result.values or #sprint_result.values == 0 then
        if callback and vim.is_callable(callback) then
          callback({}, nil) -- No active sprint, return empty
        end
        return
      end

      local sprint_id = sprint_result.values[1].id
      
      -- Cache the sprint info for faster future requests
      cache_sprint(project, board_id, sprint_id)
      
      local story_point_field = config.get_project_config(project).story_point_field
      local all_issues = {}
      local limit = config.options.jira.limit or 200

      -- Build field list for API request
      local fields = "summary,status,parent,priority,assignee,timespent,timeoriginalestimate,issuetype," .. story_point_field

      -- Fetch issues with optimized pagination (larger page size)
      local function fetch_sprint_issues(start_at)
        local page_size = math.min(100, limit - #all_issues)
        if page_size <= 0 then
          if callback and vim.is_callable(callback) then
            callback(all_issues, nil)
          end
          return
        end

        api.get_sprint_issues(sprint_id, start_at, page_size, fields, function(issues_result, err)
          if err then
            if callback and vim.is_callable(callback) then
              callback(nil, "Failed to get sprint issues: " .. err)
            end
            return
          end

          if not issues_result or not issues_result.issues then
            if callback and vim.is_callable(callback) then
              callback(all_issues, nil)
            end
            return
          end

          -- Process issues
          for _, issue in ipairs(issues_result.issues) do
            if not issue or not issue.key then
              goto continue
            end

            local fields = issue.fields
            local status = safe_get(fields, "status", "name") or "Unknown"
            local parent_key = safe_get(fields, "parent", "key")
            local priority = safe_get(fields, "priority", "name") or "None"
            local assignee = safe_get(fields, "assignee", "displayName") or "Unassigned"
            local issue_type = safe_get(fields, "issuetype", "name") or "Task"
            local time_spent = is_valid(fields.timespent) and fields.timespent or nil
            local time_estimate = is_valid(fields.timeoriginalestimate) and fields.timeoriginalestimate or nil
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

            ::continue::
          end

          -- Check if there are more issues
          local total = issues_result.total or 0
          local next_start = start_at + #issues_result.issues
          if next_start < total and #all_issues < limit then
            fetch_sprint_issues(next_start)
          else
            if callback and vim.is_callable(callback) then
              callback(all_issues, nil)
            end
          end
        end)
      end

      fetch_sprint_issues(0)
    end)
  end)
end

-- Get backlog issues
---@param project string
---@param callback? fun(all_issues?: table, err?: string)
function M.get_backlog_issues(project, callback)
  if not project then
    if callback and vim.is_callable(callback) then
      callback(nil, "Project Key is required")
    end
    return
  end

  local jql = ("project = '%s' AND (sprint is EMPTY OR sprint not in openSprints()) AND issuetype not in (Epic) AND statusCategory != Done ORDER BY Rank ASC"):format(
    project
  )

  fetch_issues_recursive(project, jql, callback)
end

-- Get issues by custom JQL
---@param project? string
---@param jql string
---@param callback? fun(c?: any, err?: string)
function M.get_issues_by_jql(project, jql, callback)
  if not project then
    if callback and vim.is_callable(callback) then
      callback(nil, "Project Key is required")
    end
    return
  end

  -- Resolve currentUser() if needed
  api.resolve_jql_current_user(jql, function(resolved_jql, err)
    if err then
      if callback and vim.is_callable(callback) then
        callback(nil, "Failed to resolve JQL: " .. err)
      end
      return
    end
    
    fetch_issues_recursive(project, resolved_jql, callback)
  end)
end

-- Export cache clear function
M.clear_sprint_cache = clear_sprint_cache

return M
-- vim: set ts=2 sts=2 sw=2 et ai si sta:
