-- version.lua: API version abstraction layer
local config = require("jira.common.config")

---@class Jira.API.Version
local M = {}

-- Get API version from config/env
function M.get_api_version()
  return os.getenv("JIRA_API_VERSION") or config.options.jira.api_version or "3"
end

-- Check if using API v2
function M.is_v2()
  return M.get_api_version() == "2"
end

-- Get base API path for version
function M.get_api_path()
  local version = M.get_api_version()
  return "/rest/api/" .. version
end

-- Get search endpoint based on version
function M.get_search_endpoint()
  local version = M.get_api_version()
  if version == "2" then
    return M.get_api_path() .. "/search"
  else
    return M.get_api_path() .. "/search/jql"
  end
end

-- Transform search request data based on version
function M.transform_search_data(jql, page_token, max_results, fields)
  local version = M.get_api_version()

  local data
  if version == "2" then
    data = {
      jql = jql,
      fields = fields,
      startAt = tonumber(page_token) or 0,
      maxResults = max_results or 100,
    }
  else
    data = {
      jql = jql,
      fields = fields,
      nextPageToken = page_token or "",
      maxResults = max_results or 100,
    }
  end
  return data
end

-- Transform search response based on version
function M.transform_search_response(result)
  local version = M.get_api_version()

  local transformed
  if version == "2" then
    local next_token = nil
    if result.startAt + result.maxResults < result.total then
      next_token = tostring(result.startAt + result.maxResults)
    end

    transformed = {
      issues = result.issues,
      nextPageToken = next_token,
    }
  else
    transformed = result
  end
  return transformed
end

-- Transform comment data based on version
function M.transform_comment_data(comment)
  if M.is_v2() then
    -- v2 uses plain text
    if type(comment) == "string" then
      return { body = comment }
    else
      return comment
    end
  else
    -- v3 uses ADF format (current implementation)
    local util = require("jira.common.util")
    if type(comment) == "string" then
      return { body = util.markdown_to_adf(comment) }
    else
      return { body = comment }
    end
  end
end

return M
