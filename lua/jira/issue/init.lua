local state = require("jira.issue.state")
local render = require("jira.issue.render")
local jira_api = require("jira.jira-api.api")
local common_ui = require("jira.common.ui")
local util = require("jira.common.util")

---@class Jira.Issue
local M = {}

-- Helper to refresh comments
local function refresh_comments(message)
  common_ui.start_loading("Refreshing comments...")
  jira_api.get_comments(state.issue.key, function(comments, err)
    vim.schedule(function()
      common_ui.stop_loading()
      if err then
        vim.notify("Error refreshing comments: " .. err, vim.log.levels.WARN)
        return
      end
      state.comments = comments
      
      -- Update cache with new comments
      if state.cache[state.issue.key] then
        state.cache[state.issue.key].comments = comments
        state.cache[state.issue.key].timestamp = os.time()
      end
      
      render.render_content()
      if message then
        vim.notify(message, vim.log.levels.INFO)
      end
    end)
  end)
end

-- Helper to create comment input window
local function create_comment_window(title, initial_content, on_submit)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })

  if initial_content then
    local lines = vim.split(initial_content, "\n")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end

  local width = math.floor(vim.o.columns * 0.6)
  local height = math.floor(vim.o.lines * 0.4)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = (vim.o.lines - height) / 2,
    col = (vim.o.columns - width) / 2,
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "center",
  })

  if not initial_content then
    vim.cmd("startinsert")
  end

  -- Submit handler
  vim.keymap.set({ "n", "i" }, "<C-s>", function()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local input = table.concat(lines, "\n")
    
    if input == "" then
      vim.cmd("stopinsert")
      vim.api.nvim_win_close(win, true)
      return
    end

    vim.cmd("stopinsert")
    vim.api.nvim_win_close(win, true)
    on_submit(input)
  end, { buffer = buf })

  -- Cancel handler
  vim.keymap.set("n", "<Esc>", function()
    vim.cmd("stopinsert")
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf })
end

local function setup_keymaps()
  local opts = { noremap = true, silent = true, buffer = state.buf }

  -- Quit
  vim.keymap.set("n", "q", function()
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_win_close(state.win, true)
      if state.prev_win and vim.api.nvim_win_is_valid(state.prev_win) then
        vim.api.nvim_set_current_win(state.prev_win)
      end
    end
  end, opts)

  vim.keymap.set("n", "<Esc>", function()
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_win_close(state.win, true)
      if state.prev_win and vim.api.nvim_win_is_valid(state.prev_win) then
        vim.api.nvim_set_current_win(state.prev_win)
      end
    end
  end, opts)

  -- Refetch issue (always goes to description tab)
  vim.keymap.set("n", "r", function()
    local issue_key = state.issue and state.issue.key
    if not issue_key then
      return
    end
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_win_close(state.win, true)
    end
    M.open(issue_key, "description", true) -- force_refresh = true, go to description
  end, opts)

  -- Edit Comment
  vim.keymap.set("n", "E", function()
    if state.active_tab ~= "comments" then
      return
    end

    local cursor_row = vim.api.nvim_win_get_cursor(0)[1] - 1
    local target_comment = nil
    for _, range in ipairs(state.comment_ranges) do
      if cursor_row >= range.start_line and cursor_row <= range.end_line then
        target_comment = range.comment
        break
      end
    end

    if not target_comment then
      return
    end

    local current_md = util.adf_to_markdown(target_comment.body)
    create_comment_window(" Edit Comment (Press <C-s> to submit, <Esc> to cancel) ", current_md, function(input)
      common_ui.start_loading("Updating comment...")
      jira_api.edit_comment(state.issue.key, target_comment.id, input, function(_, err)
        vim.schedule(function()
          common_ui.stop_loading()
          if err then
            vim.notify("Error updating comment: " .. err, vim.log.levels.ERROR)
            return
          end
          refresh_comments("Comment updated.")
        end)
      end)
    end)
  end, opts)

  -- Switch Tabs
  vim.keymap.set("n", "<Tab>", function()
    local next_tab = { description = "comments", comments = "help", help = "description" }
    state.active_tab = next_tab[state.active_tab] or "description"
    render.render_content()
  end, opts)

  local tabs = require("jira.common.tabs")
  tabs.setup_tab_keymaps({
    tabs = {
      { key = "1", id = "description" },
      { key = "2", id = "comments" },
      { key = "3", id = "help" },
    },
    state = state,
    on_switch = function(tab_id)
      state.active_tab = tab_id
      render.render_content()
    end,
    buffer = state.buf,
  })

  -- Add Comment
  vim.keymap.set("n", "i", function()
    if state.active_tab ~= "comments" then
      vim.notify("Switch to Comments tab to add a comment.", vim.log.levels.WARN)
      return
    end

    create_comment_window(" Add Comment (Press <C-s> to submit, <Esc> to cancel) ", nil, function(input)
      common_ui.start_loading("Adding comment...")
      jira_api.add_comment(state.issue.key, input, function(_, err)
        vim.schedule(function()
          common_ui.stop_loading()
          if err then
            vim.notify("Error adding comment: " .. err, vim.log.levels.ERROR)
            return
          end
          refresh_comments("Comment added.")
        end)
      end)
    end)
  end, opts)
end

---@param issue_key string
---@param initial_tab? string
---@param force_refresh? boolean
function M.open(issue_key, initial_tab, force_refresh)
  local prev_win = vim.api.nvim_get_current_win()
  util.setup_static_highlights()

  -- Reset state
  state.active_tab = initial_tab or "description"
  state.buf = nil
  state.win = nil
  state.prev_win = prev_win

  -- Check cache first (cache expires after 5 minutes)
  local cached = state.cache[issue_key]
  local cache_valid = cached and not force_refresh and (os.time() - cached.timestamp) < 300

  if cache_valid then
    vim.schedule(function()
      state.issue = cached.issue
      state.comments = cached.comments or {}

      -- Create UI
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
      vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
      vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
      vim.api.nvim_buf_set_name(buf, "Jira: " .. issue_key)

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

      state.buf = buf
      state.win = win

      vim.api.nvim_set_option_value("wrap", true, { win = win })
      vim.api.nvim_set_option_value("linebreak", true, { win = win })

      render.render_content()
      setup_keymaps()
    end)
    return
  end

  -- Fetch from API
  common_ui.start_loading("Fetching task " .. issue_key .. "...")
  state.issue = nil
  state.comments = {}

  jira_api.get_issue(issue_key, function(issue, err)
    if err then
      vim.schedule(function()
        common_ui.stop_loading()
        vim.notify("Error fetching issue: " .. err, vim.log.levels.ERROR)
      end)
      return
    end

    if not issue or not issue.key then
      vim.schedule(function()
        common_ui.stop_loading()
        vim.notify("Error: Invalid issue data received (missing key field)", vim.log.levels.ERROR)
      end)
      return
    end

    jira_api.get_comments(issue.key, function(comments, c_err)
      vim.schedule(function()
        common_ui.stop_loading()
        if c_err then
          vim.notify("Error fetching comments: " .. c_err, vim.log.levels.WARN)
        end

        state.issue = issue
        state.comments = comments or {}

        -- Update cache
        state.cache[issue.key] = {
          issue = issue,
          comments = comments or {},
          timestamp = os.time(),
        }

        -- Create UI
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
        vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
        vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
        vim.api.nvim_buf_set_name(buf, "Jira: " .. issue.key)

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

        state.buf = buf
        state.win = win

        -- Set window options
        vim.api.nvim_set_option_value("wrap", true, { win = win })
        vim.api.nvim_set_option_value("linebreak", true, { win = win })

        render.render_content()
        setup_keymaps()
      end)
    end)
  end)
end

--- Clear issue cache (all or specific issue)
---@param issue_key? string Optional issue key. If not provided, clears all cache
function M.clear_cache(issue_key)
  if issue_key then
    state.cache[issue_key] = nil
  else
    state.cache = {}
  end
end

return M
-- vim: set ts=2 sts=2 sw=2 et ai si sta:
