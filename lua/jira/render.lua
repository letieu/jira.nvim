local state = require("jira.state")
local util = require("jira.util")
local ui = require("jira.ui")
local api = vim.api

local MAX = {
  TITLE = 60,
  ASSIGNEE = 10,
  TIME = 7,
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
    return string.rep("▰", width), 0
  end

  local ratio = spent / total
  local filled_len = math.floor(ratio * width)
  filled_len = math.min(width, math.max(0, filled_len))

  local bar = string.rep("▰", filled_len) .. string.rep("▱", width - filled_len)
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
    return "", "JiraIconStory"
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

---@param spent number
---@param estimate number
---@return string col1_str
---@return string col1_hl
local function get_time_display_info(spent, estimate)
  local col1_str = ""
  local col1_hl = "Comment"
  local remaining = math.max(0, estimate - spent)

  if estimate == 0 and spent > 0 then
    col1_str = string.format("%s", util.format_time(spent))
    col1_hl = "WarningMsg"
  elseif estimate > 0 then
    col1_str = string.format("%s/%s", util.format_time(spent), util.format_time(estimate))

    if remaining > 0 then
      col1_hl = "Comment"
    else
      local overdue = spent - estimate
      if overdue > 0 then
        col1_hl = "Error"
      else
        col1_str = util.format_time(spent) .. " "
        col1_hl = "exgreen"
      end
    end
  elseif spent == 0 and estimate == 0 then
    col1_str = "-"
    col1_hl = "Comment"
  end

  return col1_str, col1_hl
end

---@param node JiraIssueNode
---@param is_root boolean
---@param bar_width number
---@return string col1_str
---@return string col1_hl
---@return string col2_str
---@return number bar_filled_len
local function get_right_part_info(node, is_root, bar_width)
  local time_str = ""
  local time_hl = "Comment"
  local assignee_str = ""
  local bar_str = ""
  local bar_filled_len = 0

  if is_root then
    local spent, estimate = get_totals(node)
    local bar, filled = render_progress_bar(spent, estimate, bar_width)
    bar_str = bar
    bar_filled_len = filled
    time_str = string.format("%s/%s", util.format_time(spent), util.format_time(math.max(estimate, spent)))
  else
    local spent = node.time_spent or 0
    local estimate = node.time_estimate or 0
    time_str, time_hl = get_time_display_info(spent, estimate)
  end

  local ass = truncate(node.assignee or "Unassigned", MAX.ASSIGNEE - 2)
  assignee_str = " " .. ass

  return time_str, time_hl, assignee_str, bar_str, bar_filled_len
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

  local expand_icon = " "
  if node.children and #node.children > 0 then
    expand_icon = node.expanded and "" or ""
  end

  local is_root = depth == 1

  local key = node.key or ""
  local title = truncate(node.summary or "", MAX.TITLE)
  local points = node.story_points or node.points
  if points == nil or points == vim.NIL then
    points = "?"
  end
  local pts = is_root and string.format(" 󰫢 %s", points) or ""

  local status = truncate(node.status or "Unknown", MAX.STATUS)

  local highlights = {}
  local col = #indent

  -- LEFT --------------------------------------------------
  local left = string.format("%s%s %s %s %s %s", indent, expand_icon, icon, key, title, pts)

  add_hl(highlights, col, expand_icon, "Comment")
  col = col + #expand_icon + 1

  add_hl(highlights, col, icon, icon_hl)
  col = col + #icon + 1

  add_hl(highlights, col, key, depth == 1 and "Title" or "LineNr")
  col = col + #key + 1

  add_hl(highlights, col, title, depth == 1 and "JiraTopLevel" or "Comment")
  col = col + #title + 1

  add_hl(highlights, col, pts, "JiraStoryPoint")

  -- RIGHT -------------------------------------------------
  local bar_width = 8
  local time_str, time_hl, assignee_str, bar_str, bar_filled_len = get_right_part_info(node, is_root, bar_width)

  local bar_display = bar_str
  if bar_display == "" then
    bar_display = string.rep(" ", bar_width)
  end

  local time_pad = string.rep(" ", MAX.TIME - vim.fn.strdisplaywidth(time_str))
  local ass_pad = string.rep(" ", MAX.ASSIGNEE - vim.fn.strdisplaywidth(assignee_str))
  local status_pad = string.rep(" ", MAX.STATUS - vim.fn.strdisplaywidth(status))
  local status_str = " " .. status .. status_pad .. " "

  local right_part = string.format("%s  %s%s  %s%s  %s", bar_display, time_str, time_pad, assignee_str, ass_pad, status_str)

  local total_width = api.nvim_win_get_width(state.win or 0)
  local left_width = vim.fn.strdisplaywidth(left)
  local padding = string.rep(" ", math.max(1, total_width - left_width - vim.fn.strdisplaywidth(right_part) - 1))

  local full_line = left .. padding .. right_part

  local right_col_start = #left + #padding

  -- Highlight Progress Bar
  if is_root then
    local filled_bytes = bar_filled_len * 3
    local empty_bytes = (bar_width - bar_filled_len) * 3
    add_hl(highlights, right_col_start, string.sub(bar_display, 1, filled_bytes), "JiraProgressBar")
    add_hl(highlights, right_col_start + filled_bytes,
      string.sub(bar_display, filled_bytes + 1, filled_bytes + empty_bytes), "linenr")
  end

  local current_col = right_col_start + #bar_display + 2

  -- Highlight Time
  if time_str ~= "" then
    add_hl(highlights, current_col, time_str, time_hl)
  end
  current_col = current_col + #time_str + #time_pad + 2

  -- Highlight Assignee
  local ass_hl = (node.assignee == nil or node.assignee == "Unassigned") and "JiraAssigneeUnassigned" or "JiraAssignee"
  add_hl(highlights, current_col, assignee_str, ass_hl)

  -- Highlight Status
  local right_status_start = current_col + #assignee_str + #ass_pad + 2
  local status_hl = ui.get_status_hl(node.status)
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

local function render_header(view)
  local tabs = {
    { name = "Active Sprint", key = "S" },
    { name = "Backlog", key = "B" },
    { name = "JQL", key = "J" },
    { name = "Help", key = "H" },
  }

  local header = "  "
  local hls = {}

  for _, tab in ipairs(tabs) do
    local is_active = (view == tab.name)
    local tab_str = string.format(" %s (%s) ", tab.name, tab.key)
    local start_col = #header
    header = header .. tab_str .. "  "

    table.insert(hls, {
      start_col = start_col,
      end_col = start_col + #tab_str,
      hl = is_active and "JiraTabActive" or "JiraTabInactive",
    })
  end

  api.nvim_buf_set_lines(state.buf, 0, -1, false, { header, "" })
  for _, h in ipairs(hls) do
    api.nvim_buf_set_extmark(state.buf, state.ns, 0, h.start_col, {
      end_col = h.end_col,
      hl_group = h.hl,
    })
  end
end

function M.render_help(view)
  render_header(view)
  local help_content = {
    { k = "o, <CR>, <Tab>", d = "Toggle Node (Expand/Collapse)" },
    { k = "S", d = "Switch to Active Sprint" },
    { k = "B", d = "Switch to Backlog" },
    { k = "J", d = "Custom JQL Search" },
    { k = "K", d = "Show Issue Details (Popup)" },
    { k = "m", d = "Read Task as Markdown" },
    { k = "gx", d = "Open Task in Browser" },
    { k = "r", d = "Refresh current view" },
    { k = "H", d = "Show this Help" },
    { k = "q", d = "Close Board" },
  }

  local lines = { "" }
  local hls = {}

  table.insert(lines, "  Keymaps:")
  table.insert(lines, "")

  for _, item in ipairs(help_content) do
    local line = string.format("    %-18s %s", item.k, item.d)
    table.insert(lines, line)
    local buf_row = 2 + #lines - 1

    table.insert(hls, {
      row = buf_row,
      start_col = 4,
      end_col = 4 + #item.k,
      hl = "Special",
    })
  end

  api.nvim_buf_set_lines(state.buf, 2, -1, false, lines)
  for _, h in ipairs(hls) do
    api.nvim_buf_set_extmark(state.buf, state.ns, h.row, h.start_col, {
      end_col = h.end_col,
      hl_group = h.hl,
    })
  end
end

-- ---------------------------------------------
-- Render TREE into buffer
-- ---------------------------------------------
---@param issues JiraIssueNode[]
---@param view string?
---@param depth number?
---@param row number?
---@return number
function M.render_issue_tree(issues, view, depth, row)
  depth = depth or 1
  row = row or 2

  if depth == 1 then
    state.line_map = {}
    if view then
      render_header(view)
    end
  end

  for i, node in ipairs(issues) do
    if depth == 1 and i > 1 then
      api.nvim_buf_set_lines(state.buf, row, row + 1, false, { "" })
      row = row + 1
    end

    state.line_map[row] = node
    render_issue_line(node, depth, row)
    row = row + 1

    if node.children and #node.children > 0 and node.expanded then
      row = M.render_issue_tree(node.children, view, depth + 1, row)
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
