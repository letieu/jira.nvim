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

  -- Add Comment / Edit Description
  vim.keymap.set("n", "i", function()
    if state.active_tab == "description" then
      require("jira.edit").open(state.issue.key)
      return
    end

    if state.active_tab ~= "comments" then
      vim.notify("Switch to Comments tab to add a comment or Description tab to edit.", vim.log.levels.WARN)
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

  -- Open Attachment
  vim.keymap.set("n", "gx", function()
    local cursor_row = vim.api.nvim_win_get_cursor(0)[1] - 1
    local target_url = nil
    local target_filename = nil
    for _, range in ipairs(state.attachment_ranges) do
      if cursor_row >= range.start_line and cursor_row <= range.end_line then
        target_url = range.url
        target_filename = range.filename
        break
      end
    end

    if not target_url then
      vim.notify("No attachment found at cursor", vim.log.levels.WARN)
      return
    end

    -- Download and open attachment in Neovim
    common_ui.start_loading("Downloading attachment...")
    
    local config_mod = require("jira.common.config")
    local env = config_mod.options.jira
    local auth_type = env.auth_type or "basic"
    
    local auth_header
    if auth_type == "basic" then
      local base64_auth = vim.fn.system("echo -n '" .. env.email .. ":" .. env.token .. "' | base64"):gsub("\n", "")
      auth_header = "Authorization: Basic " .. base64_auth
    else
      auth_header = "Authorization: Bearer " .. env.token
    end

    -- Determine file extension for proper handling
    local extension = target_filename and target_filename:match("%.([^%.]+)$") or ""
    local is_image = extension:lower():match("^(png|jpg|jpeg|gif|bmp|webp|svg)$")
    
    -- For images, save with proper extension for image.nvim detection
    local tmpfile = is_image and (vim.fn.tempname() .. "." .. extension) or vim.fn.tempname()
    
    local curl_cmd = {
      "curl",
      "-s",
      "-H", auth_header,
      "-o", tmpfile,
      target_url
    }

    vim.fn.jobstart(curl_cmd, {
      on_exit = function(_, exit_code)
        vim.schedule(function()
          common_ui.stop_loading()
          if exit_code ~= 0 then
            vim.notify("Failed to download attachment", vim.log.levels.ERROR)
            return
          end

          -- Open the file in a new floating window
          local attach_buf = vim.api.nvim_create_buf(false, true)
          vim.api.nvim_buf_set_option(attach_buf, "bufhidden", "wipe")
          vim.api.nvim_buf_set_option(attach_buf, "buflisted", false)
          
          -- Create a centered floating window
          local width = math.floor(vim.o.columns * 0.8)
          local height = math.floor(vim.o.lines * 0.8)
          local attach_win = vim.api.nvim_open_win(attach_buf, true, {
            relative = "editor",
            width = width,
            height = height,
            row = math.floor((vim.o.lines - height) / 2),
            col = math.floor((vim.o.columns - width) / 2),
            style = "minimal",
            border = "rounded",
            title = " " .. (target_filename or "Attachment") .. " ",
            title_pos = "center",
          })
          
          -- Load the file content
          vim.cmd("edit " .. vim.fn.fnameescape(tmpfile))
          
          -- Rename buffer to show actual filename
          if target_filename then
            vim.api.nvim_buf_set_name(0, target_filename)
          end
          
          -- Set up keymap to close the attachment viewer
          vim.keymap.set("n", "q", function()
            if vim.api.nvim_win_is_valid(attach_win) then
              vim.api.nvim_win_close(attach_win, true)
            end
            -- Explicitly delete the buffer to clean up
            if vim.api.nvim_buf_is_valid(attach_buf) then
              vim.api.nvim_buf_delete(attach_buf, { force = true })
            end
            -- Clean up the temp file
            vim.fn.delete(tmpfile)
          end, { buffer = attach_buf, noremap = true, silent = true })
          
          vim.keymap.set("n", "<Esc>", function()
            if vim.api.nvim_win_is_valid(attach_win) then
              vim.api.nvim_win_close(attach_win, true)
            end
            -- Explicitly delete the buffer to clean up
            if vim.api.nvim_buf_is_valid(attach_buf) then
              vim.api.nvim_buf_delete(attach_buf, { force = true })
            end
            -- Clean up the temp file
            vim.fn.delete(tmpfile)
          end, { buffer = attach_buf, noremap = true, silent = true })
          
          -- Add keymap to open attachment in browser
          vim.keymap.set("n", "gb", function()
            vim.ui.open(target_url)
            vim.notify("Opening attachment in browser...", vim.log.levels.INFO)
          end, { buffer = attach_buf, noremap = true, silent = true })
          
          -- For images, try to use image.nvim if available
          if is_image then
            local ok, image = pcall(require, "image")
            if ok then
              -- image.nvim will automatically detect and render the image
              vim.notify("Image opened: " .. (target_filename or "attachment"), vim.log.levels.INFO)
            else
              vim.notify("Attachment opened: " .. (target_filename or "attachment") .. " (install 3rd/image.nvim for image preview)", vim.log.levels.INFO)
            end
          else
            vim.notify("Attachment opened: " .. (target_filename or "attachment"), vim.log.levels.INFO)
          end
        end)
      end
    })
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
          title = " " .. issue.key .. " ",
          title_pos = "center",
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

function M.refresh()
  if not state.issue or not state.issue.key then
    return
  end

  common_ui.start_loading("Refreshing issue " .. state.issue.key .. "...")

  jira_api.get_issue(state.issue.key, function(updated_issue, err)
    if err then
      vim.schedule(function()
        common_ui.stop_loading()
        vim.notify("Error refreshing issue: " .. err, vim.log.levels.ERROR)
      end)
      return
    end

    jira_api.get_comments(state.issue.key, function(comments, c_err)
      vim.schedule(function()
        common_ui.stop_loading()
        if not c_err then
          state.comments = comments or {}
        end

        state.issue = updated_issue
        render.render_content()
        vim.notify("Issue refreshed", vim.log.levels.INFO)
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

