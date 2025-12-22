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
  if not seconds or seconds <= 0 then
    return "0"
  end

  local hours = seconds / 3600
  -- If it's an integer, don't show .0
  if hours % 1 == 0 then
    return string.format("%d", hours)
  end
  -- Otherwise show 1 decimal place
  return string.format("%.1f", hours)
end

---@param node table
---@return string
local function parse_adf(node)
  if not node or node == vim.NIL then return "" end
  if node.type == "text" then
    local text = node.text or ""
    if node.marks then
      for _, mark in ipairs(node.marks) do
        if mark.type == "strong" then text = "**" .. text .. "**" end
        if mark.type == "em" then text = "_" .. text .. "_" end
        if mark.type == "code" then text = "`" .. text .. "`" end
        if mark.type == "strike" then text = "~~" .. text .. "~~" end
        if mark.type == "link" then text = string.format("[%s](%s)", text, mark.attrs.href) end
      end
    end
    return text
  elseif node.type == "hardBreak" then
    return "\n"
  elseif node.content then
    local parts = {}
    for _, child in ipairs(node.content) do
      table.insert(parts, parse_adf(child))
    end
    local joined = table.concat(parts, "")

    if node.type == "paragraph" then
      return joined .. "\n\n"
    elseif node.type == "heading" then
      local level = node.attrs and node.attrs.level or 1
      return string.rep("#", level) .. " " .. joined .. "\n\n"
    elseif node.type == "listItem" then
      return joined
    elseif node.type == "bulletList" then
      local list_parts = {}
      for _, child in ipairs(node.content) do
        table.insert(list_parts, "- " .. parse_adf(child))
      end
      return table.concat(list_parts, "") .. "\n"
    elseif node.type == "orderedList" then
      local list_parts = {}
      for i, child in ipairs(node.content) do
        table.insert(list_parts, i .. ". " .. parse_adf(child))
      end
      return table.concat(list_parts, "") .. "\n"
    elseif node.type == "codeBlock" then
      local lang = node.attrs and node.attrs.language or ""
      return "```" .. lang .. "\n" .. joined .. "\n```\n\n"
    elseif node.type == "blockquote" then
      return "> " .. joined:gsub("\n", "> ") .. "\n\n"
    elseif node.type == "rule" then
      return "---\n\n"
    end
    return joined
  end
  return ""
end

---@param adf table?
---@return string
M.adf_to_markdown = function(adf)
  if not adf then return "" end
  return parse_adf(adf)
end

return M