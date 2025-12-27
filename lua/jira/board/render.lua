local state = require("jira.board.state")
local util = require("jira.common.util")
local ui = require("jira.board.ui")

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

---@param width integer
local function render_progress_bar(spent, estimate, width)
  local total = math.max(estimate, spent)
  if total <= 0 then
    return ("▰"):rep(width), 0
  end

  local ratio = spent / total
  local filled_len = math.floor(ratio * width)
  filled_len = math.min(width, math.max(0, filled_len))

  local bar = ("▰"):rep(filled_len) .. ("▱"):rep(width - filled_len)
  return bar, filled_len
end

local function add_hl(hls, start_col, text, hl)
  local width = text:len()
  table.insert(hls, {
    start_col = start_col,
    end_col = start_col + width,
    hl = hl,
  })
end

-- ---------------------------------------------
-- Helpers
-- ---------------------------------------------
---@param node JiraIssueNode
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
    col1_str = ("%s"):format(util.format_time(spent))
    col1_hl = "WarningMsg"
  elseif estimate > 0 then
    col1_str = ("%s/%s"):format(util.format_time(spent), util.format_time(estimate))

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
---@param bar_width integer
---@return string col1_str
---@return string col1_hl
---@return string col2_str
---@return string bar_str
---@return integer bar_filled_len
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
    time_str, time_hl = get_time_display_info(spent, estimate)
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
---@param depth integer
---@param row integer
---@return string, table[]
local function render_issue_line(node, depth, row)
  local indent = ("    "):rep(depth - 1)
  local icon, icon_hl = get_issue_icon(node)

  local expand_icon = " "
  if node.children and #node.children > 0 then
    expand_icon = node.expanded and "" or ""
  end

  local is_root = depth == 1

  local key = node.key or ""
  local title = truncate(node.summary or "", MAX.TITLE)
  ---@type string|integer
  local points = node.story_points
  if not points or points == vim.NIL then
    points = "?"
  end
  local pts = is_root and (" 󰫢 %s"):format(points) or ""

  local status = truncate(node.status or "Unknown", MAX.STATUS)

  local highlights = {}
  local col = #indent

  -- LEFT --------------------------------------------------
  local left = ("%s%s %s %s %s %s"):format(indent, expand_icon, icon, key, title, pts)

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
    bar_display = (" "):rep(bar_width)
  end

  local time_pad = (" "):rep(MAX.TIME - vim.fn.strdisplaywidth(time_str))
  local ass_pad = (" "):rep(MAX.ASSIGNEE - vim.fn.strdisplaywidth(assignee_str))
  local status_pad = (" "):rep(MAX.STATUS - vim.fn.strdisplaywidth(status))
  local status_str = " " .. status .. status_pad .. " "

  local right_part = ("%s  %s%s  %s%s  %s"):format(bar_display, time_str, time_pad, assignee_str, ass_pad, status_str)

  local total_width = vim.api.nvim_win_get_width(state.win or 0)
  local left_width = vim.fn.strdisplaywidth(left)
  local padding = (" "):rep(math.max(1, total_width - left_width - vim.fn.strdisplaywidth(right_part) - 1))

  local full_line = left .. padding .. right_part

  local right_col_start = #left + #padding

  -- Highlight Progress Bar
  if is_root then
    local filled_bytes = bar_filled_len * 3
    local empty_bytes = (bar_width - bar_filled_len) * 3
    add_hl(highlights, right_col_start, bar_display:sub(1, filled_bytes), "JiraProgressBar")
    add_hl(
      highlights,
      right_col_start + filled_bytes,
      bar_display:sub(filled_bytes + 1, filled_bytes + empty_bytes),
      "linenr"
    )
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

  vim.api.nvim_set_option_value("modifiable", true, { buf = state.buf })
  vim.api.nvim_buf_set_lines(state.buf, row, row + 1, false, { full_line })
  vim.api.nvim_set_option_value("modifiable", false, { buf = state.buf })

  for _, h in ipairs(highlights) do
    vim.api.nvim_buf_set_extmark(state.buf, state.ns, row, h.start_col, {
      end_col = h.end_col,
      hl_group = h.hl,
    })
  end

  return full_line, highlights
end

local function render_header(view)
  local tabs = {
    { name = "Active Sprint", key = "1" },
    { name = "JQL", key = "2" },
    { name = "Help", key = "3" },
  }

  local header = "  "
  local hls = {}
  local tab_ranges = {} -- Store tab click ranges

  for i, tab in ipairs(tabs) do
    local is_active = (view == tab.name)
    local tab_str = (" %s (%s) "):format(tab.name, tab.key)
    local start_col = #header
    header = header .. tab_str .. "  "

    -- Store tab range for click handling
    table.insert(tab_ranges, {
      start_col = start_col,
      end_col = start_col + #tab_str,
      view_name = tab.name,
    })

    table.insert(hls, {
      row = 0,
      start_col = start_col,
      end_col = start_col + #tab_str,
      hl = is_active and "JiraTabActive" or "JiraTabInactive",
    })
  end

  -- Store tab ranges in state for click handling
  state.tab_ranges = tab_ranges

  local header_lines = { header, "" }

  if view == "JQL" then
    -- JQL Input Line
    local jql_display = state.custom_jql or ""
    local jql_line = "    󰭎 JQL Query: " .. jql_display
    table.insert(header_lines, jql_line)
    state.jql_line = #header_lines - 1
    table.insert(hls, { row = state.jql_line, start_col = 4, end_col = 18, hl = "Keyword" })
    table.insert(hls, { row = state.jql_line, start_col = 19, end_col = -1, hl = "String" })

    -- Border for JQL line
    table.insert(
      hls,
      { row = state.jql_line, start_col = 2, virt_text = { { "│", "Comment" } }, virt_text_pos = "overlay" }
    )

    -- Virtual text hint for JQL input
    table.insert(hls, {
      row = state.jql_line,
      start_col = 0,
      virt_text = {
        { "󰋖 Press ", "JiraHelp" },
        { "<CR>", "JiraKey" },
        { " to edit query ", "JiraHelp" },
      },
      virt_text_pos = "right_align",
    })
    table.insert(header_lines, "    ")
    -- Border for empty line
    table.insert(
      hls,
      { row = #header_lines - 1, start_col = 2, virt_text = { { "│", "Comment" } }, virt_text_pos = "overlay" }
    )

    -- Saved Queries Header
    local sq_line = "    󱔗 Saved Queries:"
    table.insert(header_lines, sq_line)
    local sq_row = #header_lines - 1
    table.insert(hls, { row = sq_row, start_col = 4, end_col = -1, hl = "Title" })
    -- Border for SQ header
    table.insert(hls, { row = sq_row, start_col = 2, virt_text = { { "│", "Comment" } }, virt_text_pos = "overlay" })

    -- Virtual text hint for Saved Queries
    table.insert(hls, {
      row = sq_row,
      start_col = 0,
      virt_text = {
        { "(Press ", "JiraHelp" },
        { "<CR>", "JiraKey" },
        { " to apply) ", "JiraHelp" },
      },
      virt_text_pos = "right_align",
    })

    -- Saved Queries List
    local config = require("jira.common.config")
    local queries = config.options.queries or {}
    local query_names = {}
    for name, _ in pairs(queries) do
      table.insert(query_names, name)
    end
    table.sort(query_names)

    state.query_map = {}
    for _, name in ipairs(query_names) do
      local is_active = (state.current_query == name)
      local line = ("      %s"):format(name)
      local row = #header_lines
      table.insert(header_lines, line)
      state.query_map[row] = name

      -- Border for item
      table.insert(hls, { row = row, start_col = 2, virt_text = { { "│", "Comment" } }, virt_text_pos = "overlay" })

      table.insert(hls, { row = row, start_col = 6, end_col = -1, hl = is_active and "JiraSubTabActive" or "Comment" })
    end
    table.insert(header_lines, "    ")
  end

  vim.api.nvim_set_option_value("modifiable", true, { buf = state.buf })
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, header_lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = state.buf })

  for _, h in ipairs(hls) do
    local opts = {}
    if h.hl then
      opts.hl_group = h.hl
    end
    if h.end_col and h.end_col ~= -1 then
      opts.end_col = h.end_col
    end
    if h.virt_text then
      opts.virt_text = h.virt_text
      opts.virt_text_pos = h.virt_text_pos
    end
    vim.api.nvim_buf_set_extmark(state.buf, state.ns, h.row, h.start_col, opts)
  end
end

function M.render_help(view)
  render_header(view)
  local help_content = {
    { section = "Navigation & View" },
    { k = "<CR>", d = "Open Issue / Toggle Node" },
    { k = "<Tab>", d = "Toggle Node (Expand/Collapse)" },
    { k = "1, 2, 3", d = "Switch View (Sprint, JQL, Help)" },
    { k = "q", d = "Close Board" },
    { k = "r", d = "Refresh current view" },

    { section = "Issue Actions" },
    { k = "i", d = "Create Issue / Sub-task (under cursor)" },
    { k = "K", d = "Quick Issue Details (Popup)" },
    { k = "gd", d = "Read Task as info" },
    { k = "ge", d = "Edit Task" },
    { k = "gx", d = "Open Task in Browser" },
    { k = "gs", d = "Update Status" },
    { k = "ga", d = "Change Assignee" },
    { k = "gw", d = "Add time" },
    { k = "gb", d = "Checkout/Create Branch" },
    { k = "go", d = "Show Child Issues (Sub-tasks)" },
  }

  local lines = { "" }
  local hls = {}

  -- Calculate start row based on header size
  local query_count = 0
  if view == "JQL" then
    local config = require("jira.common.config")
    for _ in pairs(config.options.queries or {}) do
      query_count = query_count + 1
    end
  end
  local start_row = (view == "JQL") and (6 + query_count) or 2

  for _, item in ipairs(help_content) do
    if item.section then
      table.insert(lines, "")
      table.insert(lines, "  " .. item.section .. ":")
      table.insert(hls, { row = start_row + #lines - 1, start_col = 2, hl = "Title" })
    else
      local line = ("    %-18s %s"):format(item.k, item.d)
      table.insert(lines, line)
      local buf_row = start_row + #lines - 1

      table.insert(hls, {
        row = buf_row,
        start_col = 4,
        end_col = 4 + #item.k,
        hl = "Special",
      })
    end
  end

  vim.api.nvim_set_option_value("modifiable", true, { buf = state.buf })
  vim.api.nvim_buf_set_lines(state.buf, start_row, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = state.buf })

  for _, h in ipairs(hls) do
    local opts = { hl_group = h.hl }
    if h.end_col and h.end_col ~= -1 then
      opts.end_col = h.end_col
    end
    vim.api.nvim_buf_set_extmark(state.buf, state.ns, h.row, h.start_col, opts)
  end
end

-- ---------------------------------------------
-- Render TREE into buffer
-- ---------------------------------------------
---@param issues JiraIssueNode[]
---@param view? string
---@param depth? number
---@param row? integer
---@return integer
function M.render_issue_tree(issues, view, depth, row)
  depth = depth or 1
  if not row then
    local query_count = 0
    if view == "JQL" then
      local config = require("jira.common.config")
      for _ in pairs(config.options.queries or {}) do
        query_count = query_count + 1
      end
    end
    row = (view == "JQL") and (6 + query_count) or 2
  end

  if depth == 1 then
    state.line_map = {}
    if view then
      render_header(view)
    end
  end

  for i, node in ipairs(issues) do
    if depth == 1 and i > 1 then
      vim.api.nvim_set_option_value("modifiable", true, { buf = state.buf })
      vim.api.nvim_buf_set_lines(state.buf, row, row + 1, false, { "" })
      vim.api.nvim_set_option_value("modifiable", false, { buf = state.buf })
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
---@param buf integer
function M.clear(buf)
  vim.api.nvim_buf_clear_namespace(buf, state.ns, 0, -1)
  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
end

return M
-- vim: set ts=2 sts=2 sw=2 et ai si sta:
