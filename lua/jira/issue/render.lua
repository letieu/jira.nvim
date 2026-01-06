local state = require("jira.issue.state")
local util = require("jira.common.util")
local config = require("jira.common.config")

---@class Jira.Issue.Render
local M = {}

function M.render_header()
  local tabs = {
    { name = "Description", key = "D", id = "description" },
    { name = "Comments", key = "C", id = "comments" },
    { name = "Help", key = "H", id = "help" },
  }

  local header = "  "
  local hls = {}

  for _, tab in ipairs(tabs) do
    local is_active = (state.active_tab == tab.id)
    local tab_str = (" %s (%s) "):format(tab.name, tab.key)
    local start_col = header:len()
    header = header .. tab_str .. "  "

    table.insert(hls, {
      row = 0,
      start_col = start_col,
      end_col = start_col + #tab_str,
      hl = is_active and "JiraTabActive" or "JiraTabInactive",
    })
  end

  local lines = { header, "" }

  -- Add issue summary header
  local fields = state.issue.fields or {}
  table.insert(lines, "# " .. state.issue.key .. ": " .. (fields.summary or ""))
  table.insert(lines, "")

  vim.api.nvim_set_option_value("modifiable", true, { buf = state.buf })
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = state.buf })

  local ns = vim.api.nvim_create_namespace("JiraTaskView")
  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)

  for _, h in ipairs(hls) do
    vim.api.nvim_buf_set_extmark(state.buf, ns, h.row, h.start_col, {
      end_col = h.end_col,
      hl_group = h.hl,
    })
  end

  return #lines
end

function M.render_content()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end

  vim.api.nvim_set_option_value("modifiable", true, { buf = state.buf })
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, {})
  vim.api.nvim_set_option_value("modifiable", false, { buf = state.buf })

  local start_row = M.render_header()
  local lines = {}
  local hls = {}
  state.comment_ranges = {}

  local fields = state.issue.fields or {}

  if state.active_tab == "description" then
    table.insert(lines, "**Type**: " .. (fields.issuetype and fields.issuetype.name or "Unknown"))
    table.insert(lines, "**Status**: " .. (fields.status and fields.status.name or "Unknown"))

    local assignee_name = "Unassigned"
    if fields.assignee and fields.assignee ~= vim.NIL and fields.assignee.displayName then
      assignee_name = fields.assignee.displayName
    end
    table.insert(lines, "**Assignee**: " .. assignee_name)
    table.insert(lines, "**Priority**: " .. (fields.priority and fields.priority.name or "None"))
    
    -- Display labels if they exist
    if fields.labels and type(fields.labels) == "table" and #fields.labels > 0 then
      table.insert(lines, "**Labels**: " .. table.concat(fields.labels, ", "))
    end
    
    table.insert(lines, "")
    table.insert(lines, "## Description")
    table.insert(lines, "")

    if fields.description then
      local md = util.adf_to_markdown(fields.description)
      for line in md:gmatch("[^\r\n]+") do
        table.insert(lines, line)
      end
    else
      table.insert(lines, "_No description_")
    end

    local p_config = config.get_project_config(state.issue.fields.project.key)
    local custom_fields = p_config.custom_fields or {}
    for _, cf in ipairs(custom_fields) do
      if cf.key and cf.label and fields[cf.key] then
        table.insert(lines, "")
        table.insert(lines, "## " .. cf.label)
        table.insert(lines, "")
        local cf_md = util.adf_to_markdown(fields[cf.key])
        for line in cf_md:gmatch("[^\r\n]+") do
          table.insert(lines, line)
        end
      end
    end
  elseif state.active_tab == "comments" then
    if #state.comments == 0 then
      table.insert(lines, "_No comments_")
      table.insert(lines, "")
      table.insert(lines, "Press 'i' to add a comment.")
    else
      for i, comment in ipairs(state.comments) do
        local comment_start_line = start_row + #lines
        if i > 1 then
          table.insert(lines, "")
          table.insert(lines, string.rep("─", 40))
          table.insert(hls, {
            row = start_row + #lines - 1,
            start_col = 0,
            end_col = 40,
            hl = "NonText",
          })
          comment_start_line = start_row + #lines
        end

        local author = comment.author and comment.author.displayName or "Unknown"
        local created = comment.created or ""
        local ymd, hm = created:match("^(%d+-%d+-%d+)T(%d+:%d+)")
        if ymd and hm then
          created = ymd .. " " .. hm
        end

        table.insert(lines, author .. "  " .. created)
        table.insert(hls, {
          row = start_row + #lines - 1,
          start_col = 0,
          end_col = #author,
          hl = "Title",
        })
        table.insert(hls, {
          row = start_row + #lines - 1,
          start_col = #author + 2,
          end_col = #author + 2 + #created,
          hl = "Comment",
        })

        if comment.body then
          local c_md = util.adf_to_markdown(comment.body)
          local body_lines = vim.split(c_md, "\n")
          while #body_lines > 0 and body_lines[#body_lines] == "" do
            table.remove(body_lines)
          end
          for _, line in ipairs(body_lines) do
            table.insert(lines, line)
          end
        end

        table.insert(state.comment_ranges, {
          id = comment.id,
          start_line = comment_start_line,
          end_line = start_row + #lines - 1,
          comment = comment,
        })
      end
    end
  elseif state.active_tab == "help" then
    local help_content = {
      { section = "Navigation" },
      { k = "D", d = "Switch to Description" },
      { k = "C", d = "Switch to Comments" },
      { k = "H", d = "Switch to Help" },
      { k = "q", d = "Close Window" },

      { section = "Actions" },
      { k = "i", d = "Edit Description (in Description tab)" },
      { k = "i", d = "Add Comment (in Comments tab)" },
      { k = "r", d = "Edit Comment (in Comments tab)" },
    }

    for _, item in ipairs(help_content) do
      if item.section then
        table.insert(lines, "")
        table.insert(lines, "  " .. item.section .. ":")
        table.insert(hls, { row = start_row + #lines - 1, start_col = 2, hl = "Title" })
      else
        table.insert(lines, ("    %-6s %s"):format(item.k, item.d))
        local buf_row = start_row + #lines - 1

        table.insert(hls, {
          row = buf_row,
          start_col = 4,
          end_col = 4 + #item.k,
          hl = "Special",
        })
      end
    end
  end

  vim.api.nvim_set_option_value("modifiable", true, { buf = state.buf })
  vim.api.nvim_buf_set_lines(state.buf, start_row, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = state.buf })

  local ns = vim.api.nvim_create_namespace("JiraTaskView")
  for _, h in ipairs(hls) do
    local opts = { hl_group = h.hl }
    if h.end_col then
      opts.end_col = h.end_col
    end
    vim.api.nvim_buf_set_extmark(state.buf, ns, h.row, h.start_col, opts)
  end
end

return M
-- vim: set ts=2 sts=2 sw=2 et ai si sta:
