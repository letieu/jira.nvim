local state = require("jira.state")
local api = vim.api

local MAX = {
  TITLE = 60,
  ASSIGNEE = 20,
  TIME = 15,
  STATUS = 14,
}

local M = {}

local function truncate(str, max)
  if vim.fn.strdisplaywidth(str) <= max then
    return str
  end
  return vim.fn.strcharpart(str, 0, max - 1) .. "…"
end

local function get_totals(node)
  local spent = node.time_spent or 0
  local estimate = node.time_estimate or 0

  for _, child in ipairs(node.children or {}) do
    local s, e = get_totals(child)
    spent = spent + s
    estimate = estimate + e
  end

  return spent, estimate
end

local function render_progress_bar(spent, estimate, width)
  local total = math.max(estimate, spent)
  if total <= 0 then
    return string.rep("┃", width), 0
  end

  local ratio = spent / total
  local filled_len = math.floor(ratio * width)
  filled_len = math.min(width, math.max(0, filled_len))

  local bar = string.rep("┃", filled_len) .. string.rep("┃", width - filled_len)
  return bar, filled_len
end

local function add_hl(hls, start_col, text, hl)
  local width = string.len(text)
  table.insert(hls, {
    start_col = start_col,
    end_col = start_col + width,
    hl = hl,
  })
end

-- ---------------------------------------------
-- Helpers
-- ---------------------------------------------
local function get_issue_icon(node)
  local type = node.type or ""
  if type == "Bug" then
    return "", "JiraIconBug"
  elseif type == "Story" then
    return "󱜿", "JiraIconStory"
  elseif type == "Task" then
    return "", "JiraIconTask"
  elseif type == "Sub-task" or type == "Subtask" then
    return "󰙅", "JiraIconSubTask"
  elseif type == "Sub-Test" or type == "Sub Test Execution" then
    return "󰙨", "JiraIconTest"
  elseif type == "Sub Design" then
    return "󰟶", "JiraIconDesign"
  elseif type == "Sub Overhead" then
    return "󱖫", "JiraIconOverhead"
  elseif type == "Sub-Imp" then
    return "", "JiraIconImp"
  end

  return "●", "JiraIconStory"
end

-- ---------------------------------------------
-- Render ONE issue line
-- ---------------------------------------------
---@param node JiraIssueNode
---@param depth number
---@param row number
---@return string, table[]
local function render_issue_line(node, depth, row)
  local indent = string.rep("    ", depth - 1)
  local icon, icon_hl = get_issue_icon(node)

  local is_root = depth == 1

  local key = node.key or ""
  local title = truncate(node.summary or "", MAX.TITLE)
  local points = node.story_points or node.points
  if points == nil or points == vim.NIL then
    points = "?"
  end
  local pts = is_root and string.format("  %s", points) or ""

  local status = truncate(node.status or "Unknown", MAX.STATUS)

  local highlights = {}
  local col = #indent

  -- LEFT --------------------------------------------------
  local left = string.format("%s%s %s %s %s", indent, icon, key, title, pts)

  add_hl(highlights, col, icon, icon_hl)
  col = col + #icon + 1

  add_hl(highlights, col, key, depth == 1 and "Title" or "LineNr")
  col = col + #key + 1

  add_hl(highlights, col, title, depth == 1 and "JiraTopLevel" or "Comment")
  col = col + #title + 1

  add_hl(highlights, col, pts, "JiraStoryPoint")

  -- RIGHT -------------------------------------------------
  local col1_str = "" -- Time Info
  local col2_str = "" -- Assignee or Progress Bar
  local bar_filled_len = 0
  local bar_width = 20

  if is_root then
    local spent, estimate = get_totals(node)
    local bar, filled = render_progress_bar(spent, estimate, bar_width)
    bar_filled_len = filled
    col1_str = string.format("󱎫 %gh/%gh", spent, math.max(estimate, spent))
    col2_str = bar
  else
    local spent = node.time_spent or 0
    local estimate = node.time_estimate or 0
    local remaining = math.max(0, estimate - spent)
    if estimate > 0 then
      if remaining > 0 then
        col1_str = string.format("󱎫 %gh left", remaining)
      else
        col1_str = "󱎫 done"
      end
    end

    local ass = truncate(node.assignee or "Unassigned", MAX.ASSIGNEE - 2)
    col2_str = " " .. ass
  end

  local col1_pad = string.rep(" ", MAX.TIME - vim.fn.strdisplaywidth(col1_str))
  local col2_pad = string.rep(" ", MAX.ASSIGNEE - vim.fn.strdisplaywidth(col2_str))
  local status_pad = string.rep(" ", MAX.STATUS - vim.fn.strdisplaywidth(status))
  local status_str = " " .. status .. status_pad .. " "

  local right_part = string.format("%s%s  %s%s  %s", col1_str, col1_pad, col2_str, col2_pad, status_str)

  local total_width = api.nvim_win_get_width(state.win or 0)
  local left_width = vim.fn.strdisplaywidth(left)
  local padding = string.rep(" ", math.max(1, total_width - left_width - vim.fn.strdisplaywidth(right_part) - 1))

  local full_line = left .. padding .. right_part

  local right_col_start = #left + #padding

  -- Highlight Column 1 (Time Info)
  if col1_str ~= "" then
    add_hl(highlights, right_col_start, col1_str, "Comment")
  end

  -- Highlight Column 2 (Assignee or Progress Bar)
  local right_col2_start = right_col_start + #col1_str + #col1_pad + 2
  if is_root then
    local filled_bytes = bar_filled_len * 3
    local empty_bytes = (bar_width - bar_filled_len) * 3
    add_hl(highlights, right_col2_start, string.sub(col2_str, 1, filled_bytes), "exgreen")
    add_hl(highlights, right_col2_start + filled_bytes,
      string.sub(col2_str, filled_bytes + 1, filled_bytes + empty_bytes), "linenr")
  else
    local hl = (node.assignee == nil or node.assignee == "Unassigned") and "JiraAssigneeUnassigned" or "JiraAssignee"
    add_hl(highlights, right_col2_start, col2_str, hl)
  end

  -- Highlight Status
  local right_status_start = right_col2_start + #col2_str + #col2_pad + 2
  local status_hl = state.status_hls[node.status] or (is_root and "JiraStatusRoot" or "JiraStatus")
  add_hl(highlights, right_status_start, status_str, status_hl)

  api.nvim_buf_set_lines(state.buf, row, row + 1, false, { full_line })

  for _, h in ipairs(highlights) do
    api.nvim_buf_set_extmark(state.buf, state.ns, row, h.start_col, {
      end_col = h.end_col,
      hl_group = h.hl,
    })
  end

  return full_line, highlights
end

-- ---------------------------------------------
-- Render TREE into buffer
-- ---------------------------------------------
---@param issues JiraIssueNode[]
---@param depth number?
---@param row number?
---@return number
function M.render_issue_tree(issues, depth, row)
  depth = depth or 1
  row = row or 0

  for i, node in ipairs(issues) do
    if depth == 1 and i > 1 then
      api.nvim_buf_set_lines(state.buf, row, row + 1, false, { "" })
      row = row + 1
    end

    render_issue_line(node, depth, row)
    row = row + 1

    if node.children and #node.children > 0 then
      row = M.render_issue_tree(node.children, depth + 1, row)
    end
  end

  return row
end

-- ---------------------------------------------
-- Clear buffer
-- ---------------------------------------------
function M.clear(buf)
  api.nvim_buf_clear_namespace(buf, state.ns, 0, -1)
  api.nvim_buf_set_lines(buf, 0, -1, false, {})
end

return M
