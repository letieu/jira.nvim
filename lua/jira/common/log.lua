-- Simple file logger for debugging Jira API requests
local M = {}

local config = require("jira.common.config")

local log_path = vim.fn.stdpath("state") .. "/jira_nvim.log"

---Redact sensitive auth information from a string
---@param str string
---@return string
local function redact_auth(str)
  -- Redact Bearer tokens: "Bearer XXXX" -> "Bearer [REDACTED]"
  str = str:gsub('(Bearer%s+)[^"]+', "%1[REDACTED]")
  -- Redact Basic auth in -u flag: -u "email:token" -> -u "[REDACTED]"
  str = str:gsub('(-u%s+")[^"]+(")', "%1[REDACTED]%2")
  return str
end

---Write a log entry to the file
---@param level string
---@param msg string
local function write(level, msg)
  if not config.options.jira.logging then
    return
  end
  local timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
  local line = string.format("[%s] %s %s\n", timestamp, level, msg)
  local f = io.open(log_path, "a")
  if f then
    f:write(line)
    f:close()
  end
end

---Log an info message
---@param msg string
function M.info(msg)
  write("INFO", msg)
end

---Log an error message
---@param msg string
function M.error(msg)
  write("ERROR", msg)
end

---Log an outgoing HTTP request
---@param method string
---@param url string
---@param auth_header string
---@param body? string
function M.request(method, url, auth_header, body)
  local parts = { method .. " " .. url }
  table.insert(parts, "  Auth: " .. redact_auth(auth_header))
  if body then
    table.insert(parts, "  Body: " .. body)
  end
  write("REQUEST", table.concat(parts, "\n"))
end

---Log an HTTP response
---@param method string
---@param url string
---@param elapsed_ms number
---@param body? string
---@param stderr? string
---@param exit_code number
function M.response(method, url, elapsed_ms, body, stderr, exit_code)
  local status = exit_code == 0 and "OK" or ("FAILED exit=" .. exit_code)
  local parts = { string.format("(%dms) %s %s", elapsed_ms, status, method .. " " .. url) }
  if stderr and stderr ~= "" then
    table.insert(parts, "  Stderr: " .. stderr)
  end
  if body then
    table.insert(parts, "  Body: " .. body)
  end
  write("RESPONSE", table.concat(parts, "\n"))
end

---Get the log file path
---@return string
function M.get_path()
  return log_path
end

return M
