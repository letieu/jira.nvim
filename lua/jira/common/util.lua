---@class Jira.Common.Util
local M = {}

---@class JiraIssue
---@field key string
---@field summary string
---@field status string
---@field type string
---@field parent? string
---@field assignee? string
---@field priority? string
---@field time_spent? number
---@field time_estimate? number
---@field story_points? number

---@class JiraIssueNode : JiraIssue
---@field children JiraIssueNode[]
---@field expanded boolean
---@field points? integer
---@field type? string

---@param issues JiraIssue[]
---@return JiraIssueNode[]
function M.build_issue_tree(issues)
  ---@type table<string, JiraIssueNode>
  local key_to_issue = {}

  for _, issue in ipairs(issues) do
    ---@type JiraIssueNode
    local node = vim.tbl_extend("force", issue, {
      children = {},
      expanded = true,
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

---@param seconds? number
---@return string time
M.format_time = function(seconds)
  if not seconds or seconds <= 0 then
    return "0"
  end

  local hours = seconds / 3600
  -- If it's an integer, don't show .0
  if hours % 1 == 0 then
    return ("%d"):format(hours)
  end
  -- Otherwise show 1 decimal place
  return ("%.1f"):format(hours)
end

---@param node table
---@return string parsed_adf
local function parse_adf(node)
  if not node or vim.tbl_isempty(node) then
    return ""
  end
  if node.type == "hardBreak" then
    return "\n"
  end

  if node.type == "text" then
    local text = node.text or ""
    if not node.marks then
      return text
    end

    for _, mark in ipairs(node.marks) do
      ---@class ValidMarks
      ---@field strong string
      ---@field em string
      ---@field code string
      ---@field strike string
      ---@field link string
      local valid_marks = {
        strong = "**" .. text .. "**",
        em = "_" .. text .. "_",
        code = "`" .. text .. "`",
        strike = "~~" .. text .. "~~",
        link = ("[%s](%s)"):format(text, mark.attrs and mark.attrs.href or "")
      }

      if vim.list_contains(vim.tbl_keys(valid_marks), mark.type) then
        text = valid_marks[mark.type]
      end
    end
    return text
  end

  if not node.content then
    return ""
  end

  local parts = {}
  for _, child in ipairs(node.content) do
    table.insert(parts, parse_adf(child))
  end
  local joined = table.concat(parts, "")

  if node.type == "paragraph" then
    return joined .. "\n\n"
  end
  if node.type == "heading" then
    return ("#"):rep(node.attrs and node.attrs.level or 1) .. " " .. joined .. "\n\n"
  end
  if node.type == "listItem" then
    return joined
  end
  if node.type == "bulletList" then
    local list_parts = {}
    for _, child in ipairs(node.content) do
      table.insert(list_parts, "- " .. parse_adf(child))
    end
    return table.concat(list_parts, "") .. "\n"
  end
  if node.type == "orderedList" then
    local list_parts = {}
    for i, child in ipairs(node.content) do
      table.insert(list_parts, i .. ". " .. parse_adf(child))
    end
    return table.concat(list_parts, "") .. "\n"
  end
  if node.type == "codeBlock" then
    return "```" .. (node.attrs and node.attrs.language or "") .. "\n" .. joined .. "\n```\n\n"
  end
  if node.type == "blockquote" then
    return "> " .. joined:gsub("\n", "> ") .. "\n\n"
  end
  if node.type == "rule" then
    return "---\n\n"
  end

  return joined
end

---@param adf? table
---@return string
function M.adf_to_markdown(adf)
  if not adf or adf == vim.NIL then
    return ""
  end
  return parse_adf(adf)
end

function M.strim(s)
  -- Remove leading whitespace
  s = s:gsub("^%s+", "")
  -- Remove trailing whitespace
  s = s:gsub("%s+$", "")
  return s
end

function M.parse_inline_markdown(text)
  local nodes = {}
  local pos = 1
  while pos <= #text do
    -- Find next marker: ** (bold) or [ (link)
    local s_bold, e_bold = text:find("%*%*.-%*%*", pos)
    local s_link, e_link = text:find("%[.-%]%(.-%)", pos)

    local type = nil
    local start_idx, end_idx

    if s_bold and (not s_link or s_bold < s_link) then
      type = "bold"
      start_idx = s_bold
      end_idx = e_bold
    elseif s_link then
      type = "link"
      start_idx = s_link
      end_idx = e_link
    end

    if not type then
      -- No more matches, add rest of text
      table.insert(nodes, { type = "text", text = text:sub(pos) })
      break
    end

    -- Add text before match
    if start_idx > pos then
      table.insert(nodes, { type = "text", text = text:sub(pos, start_idx - 1) })
    end

    if type == "bold" then
      local content = text:sub(start_idx + 2, end_idx - 2)
      table.insert(nodes, { type = "text", text = content, marks = { { type = "strong" } } })
    elseif type == "link" then
      local match = text:sub(start_idx, end_idx)
      local link_text = match:match("%[(.-)%]")
      local link_url = match:match("%((.-)%)")
      table.insert(nodes, { type = "text", text = link_text, marks = { { type = "link", attrs = { href = link_url } } } })
    end

    pos = end_idx + 1
  end

  if #nodes == 0 then
    table.insert(nodes, { type = "text", text = "" })
  end

  return nodes
end

---@param text string
---@return table adf
function M.markdown_to_adf(text)
  local doc = {
    type = "doc",
    version = 1,
    content = {}
  }

  local lines = vim.split(text, "\n")
  local current_paragraph = nil

  local function flush_paragraph()
    if current_paragraph then
      table.insert(doc.content, current_paragraph)
      current_paragraph = nil
    end
  end

  for _, line in ipairs(lines) do
    if line == "" then
      flush_paragraph()
    else
      if not current_paragraph then
        current_paragraph = { type = "paragraph", content = {} }
      else
        -- Add space between lines in the same paragraph
        table.insert(current_paragraph.content, { type = "text", text = " " })
      end

      local nodes = M.parse_inline_markdown(line)
      for _, node in ipairs(nodes) do
        table.insert(current_paragraph.content, node)
      end
    end
  end
  flush_paragraph()

  return doc
end

return M
-- vim: set ts=2 sts=2 sw=2 et ai si sta:
