local common_util = require("jira.common.util")
local common_ui = require("jira.common.ui")
local config = require("jira.common.config")
local state = require("jira.edit.state")
local jira_api = require("jira.jira-api.api")

local M = {}

local function render_issue_as_md(issue)
  local fields = issue.fields
  local lines = {}
  table.insert(lines, ("# %s"):format(fields.summary))
  table.insert(lines, "")

  -- Metadata
  local priority = fields.priority and fields.priority.name or "None"
  table.insert(lines, ("**Priority**: %s"):format(priority))

  local assignee = "Unassigned"
  if fields.assignee and fields.assignee ~= vim.NIL then
    assignee = fields.assignee.displayName or fields.assignee.name or "Unassigned"
  end
  table.insert(lines, ("**Assignee**: %s"):format(assignee))

  local project_key = fields.project and fields.project.key
  local sp_field = config.get_project_config(project_key).story_point_field
  local points = fields[sp_field]
  if points and points ~= vim.NIL then
    table.insert(lines, ("**Story Points**: %s"):format(points))
  else
    table.insert(lines, "**Story Points**: ")
  end

  local estimate = ""
  if fields.timeoriginalestimate and fields.timeoriginalestimate ~= vim.NIL then
    local formatted = common_util.format_time(fields.timeoriginalestimate)
    if formatted ~= "0" then
      estimate = formatted .. "h"
    end
  elseif fields.timetracking and fields.timetracking.originalEstimate then
    estimate = fields.timetracking.originalEstimate
  end
  table.insert(lines, ("**Estimate**: %s"):format(estimate))

  -- Display labels if they exist
  if fields.labels and type(fields.labels) == "table" and #fields.labels > 0 then
    table.insert(lines, ("**Labels**: %s"):format(table.concat(fields.labels, ", ")))
  else
    table.insert(lines, "**Labels**: ")
  end

  table.insert(lines, "")
  table.insert(lines, "---")

  if fields.description and fields.description ~= vim.NIL then
    local md = common_util.adf_to_markdown(fields.description)
    for line in md:gmatch("[^\r\n]+") do
      table.insert(lines, line)
    end
  end

  return lines
end

local function render()
  local buf = state.buf
  if not buf then
    return
  end

  local lines = render_issue_as_md(state.issue)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Add virtual text for instructions
  local ns = vim.api.nvim_create_namespace("JiraEdit")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
    virt_text = { { "  Summary after '#'", "Comment" } },
    virt_text_pos = "eol",
  })
  vim.api.nvim_buf_set_extmark(buf, ns, 2, 0, {
    virt_text = { { "  Metadata - edit values", "Comment" } },
    virt_text_pos = "eol",
  })
  vim.api.nvim_buf_set_extmark(buf, ns, 7, 0, {
    virt_text = { { "  Description bellow '---'", "Comment" } },
    virt_text_pos = "eol",
  })

  vim.bo[buf].modified = false
end

local function on_save()
  if not state.issue or not state.buf then
    return
  end

  common_ui.start_loading("Saving issue " .. state.issue.key .. "...")

  -- Get buffer content
  local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)

  local summary = nil
  local priority = nil
  local story_points = nil
  local estimate = nil
  local assignee_text = nil
  local labels = nil

  local desc_lines = {}
  local in_description = false

  for i, line in ipairs(lines) do
    if i == 1 and line:match("^# ") then
      summary = line:sub(3)
    elseif not in_description and line == "---" then
      in_description = true
    elseif not in_description then
      -- Parse metadata
      local p_val = line:match("^%*%*Priority%*%*:?%s*(.*)")
      if p_val then
        priority = common_util.strim(p_val)
      end

      local a_val = line:match("^%*%*Assignee%*%*:?%s*(.*)")
      if a_val then
        assignee_text = common_util.strim(a_val)
      end

      local sp_val = line:match("^%*%*Story Points%*%*:?%s*(.*)")
      if sp_val then
        story_points = common_util.strim(sp_val)
      end

      local est_val = line:match("^%*%*Estimate%*%*:?%s*(.*)")
      if est_val then
        estimate = common_util.strim(est_val)
      end

      local labels_val = line:match("^%*%*Labels%*%*:?%s*(.*)")
      if labels_val then
        labels = common_util.strim(labels_val)
      end
    elseif in_description then
      table.insert(desc_lines, line)
    end
  end

  local fields = {}

  if summary then
    fields.summary = summary
  end

  if priority and priority ~= "" and priority ~= "None" then
    fields.priority = { name = priority }
  end

  -- We don't update assignee here because it usually needs accountId
  -- and names can be ambiguous. Keeping it read-only or adding a
  -- check for "Unassigned" to clear it.
  if assignee_text and assignee_text:lower() == "unassigned" then
    fields.assignee = { accountId = nil }
  end

  local project_key = state.issue.fields.project and state.issue.fields.project.key
  local sp_field = config.get_project_config(project_key).story_point_field
  if story_points and story_points ~= "" then
    fields[sp_field] = tonumber(story_points)
  end

  if estimate and estimate ~= "" then
    fields.timetracking = { originalEstimate = estimate }
  end

  if labels and labels ~= "" then
    -- Split labels by comma and trim whitespace
    local label_list = {}
    for label in labels:gmatch("[^,]+") do
      label = common_util.strim(label)
      if label ~= "" then
        -- Validate label doesn't contain spaces
        if label:match("%s") then
          common_ui.stop_loading()
          vim.notify("Label '" .. label .. "' contains spaces. Labels cannot contain spaces.", vim.log.levels.ERROR)
          return
        end
        table.insert(label_list, label)
      end
    end
    fields.labels = label_list
  end

  if in_description then
    local description_text = table.concat(desc_lines, "\n")
    description_text = common_util.strim(description_text)
    local version = require("jira.jira-api.version")
    if version.is_v2() then
      fields.description = description_text
    else
      fields.description = common_util.markdown_to_adf(description_text)
    end
  end

  jira_api.update_issue(state.issue.key, fields, function(_, err)
    common_ui.stop_loading()
    if err then
      vim.notify("Save failed: " .. err, vim.log.levels.ERROR)
    else
      vim.notify("Jira issue saved ✓")
      if vim.api.nvim_buf_is_valid(state.buf) then
        vim.bo[state.buf].modified = false
      end

      -- Update local state
      state.issue.fields = vim.tbl_deep_extend("force", state.issue.fields, fields)
      -- For fields that don't deep extend well (like setting to nil)
      if fields.assignee and fields.assignee.accountId == nil then
        state.issue.fields.assignee = nil
      end
      if fields.timetracking and fields.timetracking.originalEstimate then
        state.issue.fields.timeoriginalestimate = nil
        state.issue.fields.aggregatetimeoriginalestimate = nil
      end

      -- Refresh board if available
      vim.defer_fn(function()
        pcall(function()
          require("jira.board").refresh_view()
        end)
      end, 1000)

      -- Refresh issue detail window if open
      vim.defer_fn(function()
        pcall(function()
          require("jira.issue").refresh()
        end)
      end, 500)
    end
  end)
end

---@param issue_key string
function M.open(issue_key)
  common_util.setup_static_highlights()
  common_ui.start_loading("Fetching issue " .. issue_key .. "...")

  -- Reset state
  state.issue = nil
  state.buf = nil
  state.win = nil

  jira_api.get_issue(issue_key, function(issue, err)
    common_ui.stop_loading()

    if err then
      vim.notify("Error fetching issue: " .. err, vim.log.levels.ERROR)
      return
    end

    state.issue = issue

    -- Create UI
    local buf_name = "Jira Edit: " .. issue.key
    local existing_buf = vim.fn.bufnr("^" .. vim.pesc(buf_name) .. "$")
    if existing_buf ~= -1 and vim.api.nvim_buf_is_valid(existing_buf) then
      vim.api.nvim_buf_delete(existing_buf, { force = true })
    end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
    vim.api.nvim_set_option_value("buftype", "acwrite", { buf = buf })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
    vim.api.nvim_buf_set_name(buf, buf_name)

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
      title = " Edit Issue: " .. issue.key .. " (Save to update) ",
      title_pos = "center",
    })

    state.buf = buf
    state.win = win

    render()

    vim.api.nvim_create_autocmd("BufWriteCmd", {
      buffer = buf,
      callback = function()
        on_save()
      end,
    })
  end)
end

return M
