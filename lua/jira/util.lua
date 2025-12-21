local M = {}

---@class JiraIssue
---@field key string
---@field summary string
---@field status string
---@field parent? string
---@field assignee? string
---@field priority? string
---@field time_spent? number
---@field time_estimate? number
---@field story_points? number

---@class JiraIssueNode : JiraIssue
---@field children JiraIssueNode[]
---@field expanded boolean

---@param issues JiraIssue[]
---@return JiraIssueNode[]
M.build_issue_tree = function(issues)
  ---@type table<string, JiraIssueNode>
  local key_to_issue = {}

  for _, issue in ipairs(issues) do
    ---@type JiraIssueNode
    local node = vim.tbl_extend("force", issue, {
      children = {},
      expanded = true
    })

    key_to_issue[node.key] = node
  end

  ---@type JiraIssueNode[]
  local roots = {}

  -- Use original list order to ensure stability
  for _, issue in ipairs(issues) do
    local node = key_to_issue[issue.key]
    -- Only process if not already processed (though key_to_issue is unique by key)
    -- We just need to check if it's a child or root
    if node then
      if node.parent and key_to_issue[node.parent] then
        table.insert(key_to_issue[node.parent].children, node)
      else
        table.insert(roots, node)
      end
    end
  end

  return roots
end

---@param seconds number?
---@return string
M.format_time = function(seconds)
  if not seconds or seconds == 0 then
    return "-"
  end

  local hours = math.floor(seconds / 3600)
  local mins = math.floor((seconds % 3600) / 60)

  if hours > 0 then
    if mins > 0 then
      return string.format("%dh %dm", hours, mins)
    else
      return string.format("%dh", hours)
    end
  else
    return string.format("%dm", mins)
  end
end

return M
