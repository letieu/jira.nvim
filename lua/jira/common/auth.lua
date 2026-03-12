local M = {}

local AUTH_FILE = vim.fn.stdpath("data") .. "/jira_nvim_auth.json"

---@class JiraAuth
---@field base string
---@field email? string
---@field token string
---@field type "basic"|"pat"

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

---Prompt user for login details
function M.login()
  local current = M.load() or {}
  
  vim.ui.input({ prompt = "Jira Base URL: ", default = current.base or "" }, function(base)
    if not base or base == "" then return end
    
    vim.ui.select({ "basic (default)", "pat" }, { prompt = "Auth Type: " }, function(choice)
      -- Default to basic if user doesn't choose (e.g. cancels selection)
      local auth_type = "basic"
      if choice then
        auth_type = choice:match("^%s*(%w+)")
      end
      
      if auth_type == "basic" then
        vim.ui.input({ prompt = "Jira Email: ", default = current.email or "" }, function(email)
          if not email or email == "" then return end
          vim.ui.input({ prompt = "Jira API Token: " }, function(token)
            if not token or token == "" then return end
            M.save({ base = base, email = email, token = token, type = "basic" })
          end)
        end)
      else
        vim.ui.input({ prompt = "Jira PAT: ", default = (current.type == "pat" and current.token) or "" }, function(token)
          if not token or token == "" then return end
          M.save({ base = base, token = token, type = "pat" })
        end)
      end
    end)
  end)
end

---Show current auth info
function M.show_info()
  local auth = M.load()
  if not auth then
    vim.notify("Not logged in to Jira\nAuth file: " .. AUTH_FILE, vim.log.levels.WARN)
    return
  end
  
  local info = {
    "Jira Auth Info:",
    "Base URL: " .. auth.base,
    "Auth Type: " .. auth.type,
  }
  if auth.email then
    table.insert(info, "Email: " .. auth.email)
  end
  table.insert(info, "Token: " .. string.rep("*", 8))
  table.insert(info, "Stored at: " .. AUTH_FILE)
  
  vim.notify(table.concat(info, "\n"), vim.log.levels.INFO)
end

return M
