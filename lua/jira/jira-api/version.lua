-- version.lua: API version abstraction layer
local config = require("jira.common.config")

---@class Jira.API.Version
local M = {}

-- Get API version from config/env
function M.get_api_version()
  local auth = require("jira.common.auth").get_auth()
  local ver = (auth and auth.api_version)
    or (config.options and config.options.jira and config.options.jira.api_version)
    or os.getenv("JIRA_API_VERSION")
  if ver == nil then
    return "3"
  end
  ver = tostring(ver):lower():gsub("^v", "")
  if ver == "2" then
    return "2"
  end
  return "3"
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
  if type(result) ~= "table" then
    return { issues = {}, nextPageToken = nil }
  end

  local version = M.get_api_version()

  local transformed
  if version == "2" then
    local next_token = nil
    local start_at = tonumber(result.startAt) or 0
    local max_results = tonumber(result.maxResults) or 0
    local total = tonumber(result.total) or 0

    if total > 0 and (start_at + max_results < total) then
      next_token = tostring(start_at + max_results)
    end

    transformed = {
      issues = result.issues or {},
      nextPageToken = next_token,
    }
  else
    transformed = {
      issues = result.issues or {},
      nextPageToken = result.nextPageToken,
    }
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
