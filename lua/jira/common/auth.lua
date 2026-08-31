local M = {}

local AUTH_FILE = vim.fn.stdpath("data") .. "/jira_nvim_auth.json"

---@class JiraAuth
---@field base string
---@field email? string
---@field username? string
---@field token string
---@field type? "basic"|"pat"|"bearer"
---@field auth_type? "basic"|"pat"|"bearer"
---@field api_version? "2"|"3"|string|number

---Check if auth type is Bearer / PAT token based
---@param auth_type? string
---@return boolean
function M.is_bearer(auth_type)
  if not auth_type then
    return false
  end
  local t = tostring(auth_type):lower():gsub("^%s*(.-)%s*$", "%1")
  return t == "pat" or t == "bearer" or t == "token"
end
---Save auth data to disk
---@param data JiraAuth
function M.save(data)
  local f = io.open(AUTH_FILE, "w")
  if f then
    f:write(vim.json.encode(data))
    f:close()
    vim.notify("Jira credentials saved to " .. AUTH_FILE, vim.log.levels.INFO)
  else
    vim.notify("Failed to save Jira credentials", vim.log.levels.ERROR)
  end
end

---Load auth data from disk
---@return JiraAuth|nil
function M.load()
  local f = io.open(AUTH_FILE, "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, content)
  if ok then
    return data
  end
  return nil
end

---Delete auth data from disk
function M.logout()
  os.remove(AUTH_FILE)
  vim.notify("Logged out from Jira", vim.log.levels.INFO)
end

---Get resolved Jira auth configuration (merges saved file, config.options.jira, and env vars)
---@return JiraAuth
function M.get_auth()
  local config = require("jira.common.config")
  local file_auth = M.load() or {}
  local cfg = (config.options and config.options.jira) or {}
  local auth = {}

  local base = file_auth.base or cfg.base or os.getenv("JIRA_BASE_URL") or os.getenv("JIRA_SERVER") or ""
  if type(base) == "string" then
    base = base:gsub("/+$", "")
  end
  auth.base = base

  auth.email = file_auth.email
    or file_auth.username
    or cfg.email
    or cfg.username
    or os.getenv("JIRA_EMAIL")
    or os.getenv("JIRA_USER")
    or os.getenv("JIRA_USERNAME")

  auth.token = file_auth.token
    or cfg.token
    or os.getenv("JIRA_API_TOKEN")
    or os.getenv("JIRA_TOKEN")
    or os.getenv("JIRA_PAT")
    or ""

  local raw_type = file_auth.type
    or file_auth.auth_type
    or cfg.type
    or cfg.auth_type
    or os.getenv("JIRA_AUTH_TYPE")
    or "basic"

  if type(raw_type) == "string" then
    raw_type = raw_type:lower():gsub("^%s*(.-)%s*$", "%1")
  else
    raw_type = "basic"
  end
  auth.type = raw_type
  auth.auth_type = raw_type

  auth.api_version = file_auth.api_version
    or os.getenv("JIRA_API_VERSION")
    or cfg.api_version

  return auth
end

---Prompt user for login details
function M.login()
  local current = M.get_auth()
  vim.ui.input({ prompt = "Jira Base URL: ", default = current.base or "" }, function(base)
    if not base or base == "" then
      return
    end
    base = base:gsub("/+$", "")
    vim.ui.select({ "basic (default)", "bearer / pat" }, { prompt = "Auth Type: " }, function(choice)
      local is_bearer = false
      if choice then
        local lower_choice = choice:lower()
        if lower_choice:find("bearer") or lower_choice:find("pat") then
          is_bearer = true
        end
      end

      if not is_bearer then
        vim.ui.input(
          { prompt = "Jira Email / Username: ", default = current.email or "" },
          function(email)
            if not email or email == "" then
              return
            end
            vim.ui.input({ prompt = "Jira API Token / Password: " }, function(token)
              if not token or token == "" then
                return
              end
              M.save({ base = base, email = email, token = token, type = "basic" })
            end)
          end
        )
      else
        vim.ui.input(
          {
            prompt = "Jira Bearer Token / PAT: ",
            default = (M.is_bearer(current.type) and current.token) or "",
          },
          function(token)
            if not token or token == "" then
              return
            end
            M.save({ base = base, token = token, type = "bearer" })
          end
        )
      end
    end)
  end)
end

---Show current auth info
function M.show_info()
  local file_auth = M.load()
  local auth = M.get_auth()
  if (not auth.base or auth.base == "") and (not auth.token or auth.token == "") then
    vim.notify("Not logged in to Jira\nAuth file: " .. AUTH_FILE, vim.log.levels.WARN)
    return
  end

  local info = {
    "Jira Auth Info:",
    "Base URL: " .. (auth.base or ""),
    "Auth Type: " .. (auth.type or "basic"),
  }
  if auth.email and not M.is_bearer(auth.type) then
    table.insert(info, "Email/Username: " .. auth.email)
  end
  if auth.token and auth.token ~= "" then
    table.insert(info, "Token: " .. string.rep("*", 8))
  end
  if file_auth then
    table.insert(info, "Stored at: " .. AUTH_FILE)
  else
    table.insert(info, "Source: Config / Environment")
  end

  vim.notify(table.concat(info, "\n"), vim.log.levels.INFO)
end
return M
