local state = require("jira.issue.state")
local render = require("jira.issue.render")
local jira_api = require("jira.jira-api.api")
local common_ui = require("jira.common.ui")
local util = require("jira.common.util")

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

  -- Switch Tabs
  vim.keymap.set("n", "<Tab>", function()
    local next_tab = { description = "comments", comments = "help", help = "description" }
    state.active_tab = next_tab[state.active_tab] or "description"
    render.render_content()
  end, opts)

  vim.keymap.set("n", "D", function()
    state.active_tab = "description"
    render.render_content()
  end, opts)

  vim.keymap.set("n", "C", function()
    state.active_tab = "comments"
    render.render_content()
  end, opts)

  vim.keymap.set("n", "H", function()
    state.active_tab = "help"
    render.render_content()
  end, opts)

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

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })

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
      title = " Add Comment (Press <C-s> to submit, <Esc> to cancel) ",
      title_pos = "center",
    })

    vim.cmd("startinsert")

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
      common_ui.start_loading("Adding comment...")
      jira_api.add_comment(state.issue.key, input, function(_, err)
        vim.schedule(function()
          common_ui.stop_loading()
          if err then
            vim.notify("Error adding comment: " .. err, vim.log.levels.ERROR)
            return
          end

          -- Refresh comments
          common_ui.start_loading("Refreshing comments...")
          jira_api.get_comments(state.issue.key, function(comments, c_err)
            vim.schedule(function()
              common_ui.stop_loading()
              if not c_err then
                state.comments = comments
                render.render_content()
                vim.notify("Comment added.", vim.log.levels.INFO)
              end
            end)
          end)
        end)
      end)
    end, { buffer = buf })

    vim.keymap.set("n", "<Esc>", function()
      vim.cmd("stopinsert")
      vim.api.nvim_win_close(win, true)
    end, { buffer = buf })
  end, opts)

  -- Edit Comment
  vim.keymap.set("n", "r", function()
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

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })

    local current_md = util.adf_to_markdown(target_comment.body)
    local current_lines = vim.split(current_md, "\n")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, current_lines)

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
      title = " Edit Comment (Press <C-s> to submit, <Esc> to cancel) ",
      title_pos = "center",
    })

    vim.keymap.set({ "n", "i" }, "<C-s>", function()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local input = table.concat(lines, "\n")

      vim.cmd("stopinsert")
      vim.api.nvim_win_close(win, true)
      common_ui.start_loading("Updating comment...")
      jira_api.edit_comment(state.issue.key, target_comment.id, input, function(_, err)
        vim.schedule(function()
          common_ui.stop_loading()
          if err then
            vim.notify("Error updating comment: " .. err, vim.log.levels.ERROR)
            return
          end

          -- Refresh comments
          common_ui.start_loading("Refreshing comments...")
          jira_api.get_comments(state.issue.key, function(comments, c_err)
            vim.schedule(function()
              common_ui.stop_loading()
              if not c_err then
                state.comments = comments
                render.render_content()
                vim.notify("Comment updated.", vim.log.levels.INFO)
              end
            end)
          end)
        end)
      end)
    end, { buffer = buf })

    vim.keymap.set("n", "<Esc>", function()
      vim.cmd("stopinsert")
      vim.api.nvim_win_close(win, true)
    end, { buffer = buf })
  end, opts)
end

---@class Jira.Issue
local M = {}

---@param issue_key string
---@param initial_tab? string
function M.open(issue_key, initial_tab)
  local prev_win = vim.api.nvim_get_current_win()
  util.setup_static_highlights()
  common_ui.start_loading("Fetching task " .. issue_key .. "...")

  -- Reset state
  state.issue = nil
  state.comments = {}
  state.active_tab = initial_tab or "description"
  state.buf = nil
  state.win = nil
  state.prev_win = prev_win

  jira_api.get_issue(issue_key, function(issue, err)
    if err then
      vim.schedule(function()
        common_ui.stop_loading()
        vim.notify("Error fetching issue: " .. err, vim.log.levels.ERROR)
      end)
      return
    end

    jira_api.get_comments(issue_key, function(comments, c_err)
      vim.schedule(function()
        common_ui.stop_loading()
        if c_err then
          vim.notify("Error fetching comments: " .. c_err, vim.log.levels.WARN)
        end

        state.issue = issue
        state.comments = comments or {}

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

return M
-- vim: set ts=2 sts=2 sw=2 et ai si sta:
