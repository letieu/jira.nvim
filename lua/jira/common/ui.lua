local uv = vim.uv or vim.loop
local state = require("jira.board.state")

---@param groups string[]
---@param attr string
---@return string|nil color
local function get_theme_color(groups, attr)
  for _, g in ipairs(groups) do
    local hl = vim.api.nvim_get_hl(0, { name = g, link = false })
    if hl and hl[attr] then
      return ("#%06x"):format(hl[attr])
    end
  end
end

local function get_palette()
  return {
    get_theme_color({ "DiagnosticOk", "String", "DiffAdd" }, "fg") or "#a6e3a1", -- Green
    get_theme_color({ "DiagnosticInfo", "Function", "DiffChange" }, "fg") or "#89b4fa", -- Blue
    get_theme_color({ "DiagnosticWarn", "WarningMsg", "Todo" }, "fg") or "#f9e2af", -- Yellow
    get_theme_color({ "DiagnosticError", "ErrorMsg", "DiffDelete" }, "fg") or "#f38ba8", -- Red
    get_theme_color({ "Special", "Constant" }, "fg") or "#cba6f7", -- Magenta
    get_theme_color({ "Identifier", "PreProc" }, "fg") or "#89dceb", -- Cyan
    get_theme_color({ "Cursor", "CursorIM" }, "fg") or "#524f67", -- Grey
  }
end

---@class Jira.Common.UI
local M = {}

---@param status_name string|nil
---@return string name
function M.get_status_hl(status_name)
  if not status_name or status_name == "" then
    return "JiraStatus"
  end

  local hl_name = "JiraStatus_" .. status_name:gsub("%s+", "_"):gsub("[^%w_]", "")
  if state.status_hls[status_name] then
    return hl_name
  end

  local palette = get_palette()
  local bg_base = get_theme_color({ "Normal" }, "bg") or "#1e1e2e"

  local name_upper = status_name:upper()
  local color
  if name_upper:find("READY FOR DEV") or name_upper:find("READY FOR TEST") then
    color = palette[7] -- Grey
  elseif
    name_upper:find("DONE")
    or name_upper:find("RESOLVED")
    or name_upper:find("CLOSED")
    or name_upper:find("FINISHED")
  then
    color = palette[1] -- Green
  elseif
    name_upper:find("PROGRESS")
    or name_upper:find("DEVELOPMENT")
    or name_upper:find("BUILDING")
    or name_upper:find("WORKING")
  then
    color = palette[3] -- Yellow
  elseif name_upper:find("TODO") or name_upper:find("OPEN") or name_upper:find("BACKLOG") then
    color = palette[2] -- Blue
  elseif
    name_upper:find("BLOCK")
    or name_upper:find("REJECT")
    or name_upper:find("BUG")
    or name_upper:find("ERROR")
  then
    color = palette[4] -- Red
  elseif name_upper:find("REVIEW") or name_upper:find("QA") or name_upper:find("TEST") then
    color = palette[5] -- Magenta
  else
    -- Hash
    local hash = 0
    for i = 1, #status_name do
      hash = (hash * 31 + (status_name):byte(i)) % #palette
    end
    color = palette[hash + 1]
  end

  vim.api.nvim_set_hl(0, hl_name, {
    fg = bg_base,
    bg = color,
    bold = true,
  })

  state.status_hls[status_name] = hl_name
  return hl_name
end

function M.setup_static_highlights()
  ---@type table<string, vim.api.keyset.highlight>
  local hl = {
    JiraTopLevel = { link = "CursorLineNr", bold = true },
    JiraSubTask = { link = "Identifier" },
    JiraStoryPoint = { link = "Error", bold = true },
    JiraAssignee = { link = "MoreMsg" },
    JiraAssigneeUnassigned = { link = "Comment", italic = true },
    exgreen = { fg = "#a6e3a1" },
    JiraProgressBar = { link = "Function" },
    JiraStatus = { link = "lualine_a_insert" },
    JiraStatusRoot = { link = "lualine_a_insert", bold = true },
    JiraTabActive = { link = "CurSearch", bold = true },
    JiraTabInactive = { link = "Search" },
    JiraSubTabActive = { link = "Visual", bold = true },
    JiraSubTabInactive = { link = "StatusLineNC" },
    JiraHelp = { link = "Comment", italic = true },
    JiraKey = { link = "Special", bold = true },
    JiraIconBug = { fg = "#f38ba8" },
    JiraIconStory = { fg = "#a6e3a1" },
    JiraIconTask = { fg = "#89b4fa" },
    JiraIconSubTask = { fg = "#94e2d5" },
    JiraIconTest = { fg = "#fab387" },
    JiraIconDesign = { fg = "#cba6f7" },
    JiraIconOverhead = { fg = "#9399b2" },
    JiraIconImp = { fg = "#89dceb" },
  }

  for name, opts in pairs(hl) do
    vim.api.nvim_set_hl(0, name, opts)
  end
end

function M.create_window()
  -- Backdrop
  local dim_buf = vim.api.nvim_create_buf(false, true)
  state.dim_win = vim.api.nvim_open_win(dim_buf, false, {
    relative = "editor",
    width = vim.o.columns,
    height = vim.o.lines,
    row = 0,
    col = 0,
    style = "minimal",
    focusable = false,
    zindex = 44,
  })
  vim.api.nvim_set_option_value("winblend", 50, { win = state.dim_win })
  vim.api.nvim_set_option_value("winhighlight", "Normal:JiraDim", { win = state.dim_win })
  vim.api.nvim_set_hl(0, "JiraDim", { bg = "#000000" })

  state.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = state.buf })
  vim.api.nvim_set_option_value("modifiable", false, { buf = state.buf })

  local height = 42
  local width = 160

  state.win = vim.api.nvim_open_win(state.buf, true, {
    width = width,
    height = height,
    col = (vim.o.columns - width) / 2,
    row = (vim.o.lines - height) / 2 - 1,

    relative = "editor",
    style = "minimal",
    border = { " ", " ", " ", " ", " ", " ", " ", " " },
    title = { { "  Jira Board ", "StatusLineTerm" } },
    title_pos = "center",
    zindex = 45,
  })

  vim.api.nvim_win_set_hl_ns(state.win, state.ns)
  vim.api.nvim_set_option_value("cursorline", true, { win = state.win })

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = state.buf,
    callback = function()
      if state.dim_win and vim.api.nvim_win_is_valid(state.dim_win) then
        vim.api.nvim_win_close(state.dim_win, true)
        state.dim_win = nil
      end
    end,
  })

  vim.api.nvim_set_current_win(state.win)
end

local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local spinner_timer = nil
local spinner_win = nil
local spinner_buf = nil

---@param msg? string
function M.start_loading(msg)
  msg = msg or "Loading..."

  if spinner_win and vim.api.nvim_win_is_valid(spinner_win) then
    return
  end

  spinner_buf = vim.api.nvim_create_buf(false, true)
  local width = #msg + 4
  local height = 1
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  spinner_win = vim.api.nvim_open_win(spinner_buf, false, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    zindex = 200,
  })

  local idx = 1
  spinner_timer = uv.new_timer()
  if not spinner_timer then
    return
  end

  spinner_timer:start(
    0,
    100,
    vim.schedule_wrap(function()
      if not spinner_buf or not vim.api.nvim_buf_is_valid(spinner_buf) then
        return
      end
      local frame = spinner_frames[idx]
      vim.api.nvim_buf_set_lines(spinner_buf, 0, -1, false, { " " .. frame .. " " .. msg })
      idx = (idx % #spinner_frames) + 1
    end)
  )
end

function M.stop_loading()
  if spinner_timer then
    spinner_timer:stop()
    spinner_timer:close()
    spinner_timer = nil
  end
  if spinner_win and vim.api.nvim_win_is_valid(spinner_win) then
    vim.api.nvim_win_close(spinner_win, true)
    spinner_win = nil
  end
  if spinner_buf and vim.api.nvim_buf_is_valid(spinner_buf) then
    vim.api.nvim_buf_delete(spinner_buf, { force = true })
    spinner_buf = nil
  end
end

function M.show_issue_details_popup(node)
  local util = require("jira.common.util")
  local lines = {
    " " .. node.key .. ": " .. (node.summary or ""),
    " " .. ("━"):rep(math.min(60, #node.key + #(node.summary or "") + 2)),
    (" Status:   %s"):format(node.status or "Unknown"),
    (" Priority: %s"):format(node.priority or "None"),
    (" Assignee: %s"):format(node.assignee or "Unassigned"),
  }

  local hls = {}
  -- Header highlight
  table.insert(hls, { row = 0, col = 1, end_col = 1 + #node.key, hl = "Title" })
  table.insert(hls, { row = 1, col = 0, end_col = -1, hl = "Comment" })

  local next_row = 2
  -- Status
  table.insert(hls, { row = next_row, col = 1, end_col = 10, hl = "Label" })
  table.insert(hls, { row = next_row, col = 11, end_col = -1, hl = M.get_status_hl(node.status) })
  next_row = next_row + 1

  -- Priority
  table.insert(hls, { row = next_row, col = 1, end_col = 10, hl = "Label" })
  table.insert(hls, { row = next_row, col = 11, end_col = -1, hl = "Special" })
  next_row = next_row + 1

  -- Assignee
  table.insert(hls, { row = next_row, col = 1, end_col = 10, hl = "Label" })
  local ass_hl = (node.assignee == nil or node.assignee == "Unassigned") and "JiraAssigneeUnassigned" or "JiraAssignee"
  table.insert(hls, { row = next_row, col = 11, end_col = -1, hl = ass_hl })
  next_row = next_row + 1

  if node.story_points then
    table.insert(lines, (" Points:   %s"):format(node.story_points))
    table.insert(hls, { row = next_row, col = 1, end_col = 10, hl = "Label" })
    table.insert(hls, { row = next_row, col = 11, end_col = -1, hl = "JiraStoryPoint" })
    next_row = next_row + 1
  end

  local spent = node.time_spent or 0
  local estimate = node.time_estimate or 0
  if spent > 0 or estimate > 0 then
    table.insert(lines, (" Time:     %s / %s"):format(util.format_time(spent), util.format_time(estimate)))
    table.insert(hls, { row = next_row, col = 1, end_col = 10, hl = "Label" })
    table.insert(hls, { row = next_row, col = 11, end_col = -1, hl = "Number" })
    next_row = next_row + 1
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })

  -- Apply highlights
  for _, h in ipairs(hls) do
    local end_col = h.end_col
    if end_col == -1 then
      end_col = #lines[h.row + 1]
    end
    vim.api.nvim_buf_set_extmark(buf, state.ns, h.row, h.col, {
      end_col = end_col,
      hl_group = h.hl,
    })
  end

  local width = 0
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  width = width + 2
  local height = #lines

  local win = vim.api.nvim_open_win(buf, false, {
    relative = "cursor",
    width = width,
    height = height,
    row = 1,
    col = 0,
    style = "minimal",
    border = "rounded",
    focusable = false,
  })

  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufLeave" }, {
    buffer = state.buf,
    once = true,
    callback = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end,
  })
end

function M.open_markdown_view(title, lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_buf_set_name(buf, title)

  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = (vim.o.lines - height) / 2,
    col = (vim.o.columns - width) / 2,
    style = "minimal",
    border = "rounded",
  })

  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, silent = true })
end

function M.open_jql_input(default, callback)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { default or "" })

  local width = 80
  local height = 3
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = (vim.o.lines - height) / 2,
    col = (vim.o.columns - width) / 2,
    style = "minimal",
    border = "rounded",
    title = " Enter Custom JQL (Press <CR> to submit, q to cancel) ",
    title_pos = "center",
  })

  vim.api.nvim_command("startinsert!")

  local function submit()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local input = table.concat(lines, " "):gsub("^%s*(.-)%s*$", "%1")
    vim.api.nvim_win_close(win, true)
    vim.api.nvim_command("stopinsert")
    if input ~= "" then
      callback(input)
    end
  end

  vim.keymap.set({ "n", "i" }, "<CR>", submit, { buffer = buf, silent = true })
  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, silent = true })
  vim.keymap.set("n", "<Esc>", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, silent = true })
end

return M
-- vim: set ts=2 sts=2 sw=2 et ai si sta:
