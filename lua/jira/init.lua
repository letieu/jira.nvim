local M = {}

local api = vim.api

local state = require "jira.state"
local render = require "jira.render"
local util = require "jira.util"
local mock_data = require("jira.data")

M.setup = function(opts)
  state.config = vim.tbl_deep_extend("force", state.config, opts or {})
end

M.open = function()
  state.buf = api.nvim_create_buf(false, true)

  local height = 42
  local width = 160

  state.win = api.nvim_open_win(state.buf, true, {
    width = width,
    height = height,
    col = (vim.o.columns - width) / 2,
    row = (vim.o.lines - height) / 2 - 1,

    relative = 'editor',
    style = "minimal",
    border = { " ", " ", " ", " ", " ", " ", " ", " " },
    title = { { " 󱥚 Jira Board ", "StatusLineTerm" } },
    title_pos = "center",
  })

  api.nvim_win_set_hl_ns(state.win, state.ns)
  api.nvim_win_set_option(state.win, "cursorline", true)

  vim.api.nvim_set_hl(0, "JiraTopLevel", {
    link = "CursorLineNr",
    bold = true,
  })

  vim.api.nvim_set_hl(0, "JiraStoryPoint", {
    link = "Error",
    bold = true,
  })

  vim.api.nvim_set_hl(0, "JiraAssignee", {
    link = "MoreMsg",
  })

  vim.api.nvim_set_hl(0, "JiraAssigneeUnassigned", {
    link = "Comment",
    italic = true,
  })

  vim.api.nvim_set_hl(0, "exgreen", {
    fg = "#a6e3a1", -- Green-ish
  })

  vim.api.nvim_set_hl(0, "JiraStatus", {
    link = "lualine_a_insert",
  })

  vim.api.nvim_set_hl(0, "JiraStatusRoot", {
    link = "lualine_a_insert",
    bold = true,
  })

  api.nvim_set_current_win(state.win)

  local tree = util.build_issue_tree(mock_data)
  render.render_issue_tree(tree)
end

M.open()

return M
