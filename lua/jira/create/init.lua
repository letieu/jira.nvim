local common_util = require("jira.common.util")
local common_ui = require("jira.common.ui")
local config = require("jira.common.config")
local jira_api = require("jira.jira-api.api")

local M = {}

local state = {
  buf = nil,
  win = nil,
  project_key = nil,
  parent_key = nil,
  valid_issue_types = {},
}

local function update_type_line(type_name)
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
  for i, line in ipairs(lines) do
    if line:match("^%*%*Type%*%*:") then
      local new_line = "**Type**: " .. type_name
      vim.api.nvim_buf_set_lines(state.buf, i - 1, i, false, { new_line })

      local ns = vim.api.nvim_create_namespace("JiraCreateTypes")
      -- Clear existing marks for this namespace in the entire buffer
      vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
      vim.api.nvim_buf_set_extmark(state.buf, ns, i - 1, 0, {
        virt_text = { { "  Press <Enter> to select", "Comment" } },
        virt_text_pos = "eol",
      })

      vim.bo[state.buf].modified = false
      break
    end
  end
end

local function select_issue_type()
  if not state.valid_issue_types or #state.valid_issue_types == 0 then
    vim.notify("No issue types available", vim.log.levels.WARN)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local line = vim.api.nvim_buf_get_lines(state.buf, row, row + 1, false)[1]

  if line and line:match("^%*%*Type%*%*:") then
    vim.ui.select(state.valid_issue_types, {
      prompt = "Select Issue Type:",
    }, function(choice)
      if choice then
        update_type_line(choice)
      end
    end)
  end
end

local function render_template()
  local lines = {}
  table.insert(lines, "# Summary")
  table.insert(lines, "")

  local type_default = "Task"
  if state.parent_key then
    type_default = "Sub-task"
  end

  table.insert(lines, "**Type**: " .. type_default)
  table.insert(lines, "**Priority**: Medium")

  if state.parent_key then
    table.insert(lines, "**Parent**: " .. state.parent_key)
  else
    table.insert(lines, "**Parent**: ")
  end

  local project_key = state.project_key
  local sp_field = config.get_project_config(project_key).story_point_field
  if sp_field then
    table.insert(lines, "**Story Points**: ")
  end

  table.insert(lines, "**Estimate**: ")
  table.insert(lines, "**Labels**: ")
  table.insert(lines, "")
  table.insert(lines, "---")
  table.insert(lines, "")
  table.insert(lines, "Description")

  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
    vim.bo[state.buf].modified = false

    -- Add instructions
    local ns = vim.api.nvim_create_namespace("JiraCreate")
    vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
    vim.api.nvim_buf_set_extmark(state.buf, ns, 0, 0, {
      virt_text = { { "  Summary after '#'", "Comment" } },
      virt_text_pos = "eol",
    })
    vim.api.nvim_buf_set_extmark(state.buf, ns, 2, 0, {
      virt_text = { { "  Metadata - edit values", "Comment" } },
      virt_text_pos = "eol",
    })
    vim.api.nvim_buf_set_extmark(state.buf, ns, 8, 0, {
      virt_text = { { "  Description bellow '---'", "Comment" } },
      virt_text_pos = "eol",
    })
  end
end

local function on_save()
  if not state.buf or not state.project_key then
    return
  end

  common_ui.start_loading("Creating issue in " .. state.project_key .. "...")

  local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)

  local summary = nil
  local issue_type = "Task"
  local priority = "Medium"
  local parent_key = nil
  local story_points = nil
  local estimate = nil
  local labels = nil

  local desc_lines = {}
  local in_description = false

  for i, line in ipairs(lines) do
    if i == 1 and line:match("^# ") then
      summary = line:sub(3)
      if summary == "Summary" then
        summary = nil
      end
    elseif not in_description and line == "---" then
      in_description = true
    elseif not in_description then
      local t_val = line:match("^%*%*Type%*%*:?%s*(.*)")
      if t_val then
        issue_type = common_util.strim(t_val)
      end

      local p_val = line:match("^%*%*Priority%*%*:?%s*(.*)")
      if p_val then
        priority = common_util.strim(p_val)
      end

      local parent_val = line:match("^%*%*Parent%*%*:?%s*(.*)")
      if parent_val then
        parent_key = common_util.strim(parent_val)
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

  if not summary or summary == "" then
    common_ui.stop_loading()
    vim.notify("Summary is required", vim.log.levels.ERROR)
    return
  end

  local fields = {
    project = { key = state.project_key },
    summary = summary,
    issuetype = { name = issue_type },
    priority = { name = priority },
  }

  if parent_key and parent_key ~= "" then
    fields.parent = { key = parent_key }
  end

  local sp_field = config.get_project_config(state.project_key).story_point_field
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
    -- Remove placeholder
    if description_text:find("Description") then
      description_text = description_text:gsub("Description", "")
    end
    description_text = common_util.strim(description_text)
    if description_text ~= "" then
      local version = require("jira.jira-api.version")
      if version.is_v2() then
        fields.description = description_text
      else
        fields.description = common_util.markdown_to_adf(description_text)
      end
    end
  end

  jira_api.create_issue(fields, function(result, err)
    common_ui.stop_loading()
    if err then
      vim.notify("Creation failed: " .. err, vim.log.levels.ERROR)
    else
      vim.notify("Issue created: " .. (result.key or "Unknown"), vim.log.levels.INFO)
      if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
        vim.api.nvim_set_option_value("modified", false, { buf = state.buf })
        vim.api.nvim_buf_delete(state.buf, { force = true })
      end
      -- Close window if valid
      if state.win and vim.api.nvim_win_is_valid(state.win) then
        vim.api.nvim_win_close(state.win, true)
      end

      -- Refresh board if available
      vim.defer_fn(function()
        pcall(function()
          require("jira.board").refresh_view()
        end)
      end, 1200)
    end
  end)
end

function M.open(project_key, parent_key)
  if not project_key or project_key == "" then
    project_key = vim.fn.input("Project Key: ")
  end

  if not project_key or project_key == "" then
    vim.notify("Project key required", vim.log.levels.ERROR)
    return
  end

  state.project_key = project_key
  state.parent_key = parent_key

  common_util.setup_static_highlights()

  local buf_name = "Jira Create: " .. project_key
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
    title = " Create Issue: " .. project_key .. " (Save to create) ",
    title_pos = "center",
  })

  state.buf = buf
  state.win = win

  render_template()

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      on_save()
    end,
  })

  -- Keymap for selection
  vim.keymap.set("n", "<CR>", select_issue_type, { buffer = buf, silent = true })

  -- Fetch valid issue types
  jira_api.get_create_meta(project_key, function(issue_types, err)
    if not err and issue_types and #issue_types > 0 then
      local valid_types = {}
      for _, t in ipairs(issue_types) do
        -- Filter based on context
        if state.parent_key then
          if t.subtask then
            table.insert(valid_types, t.name)
          end
        else
          if not t.subtask then
            table.insert(valid_types, t.name)
          end
        end
      end

      state.valid_issue_types = valid_types

      if #valid_types > 0 then
        vim.schedule(function()
          if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
            return
          end

          local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
          for i, line in ipairs(lines) do
            if line:match("^%*%*Type%*%*:") then
              local current = common_util.strim(line:match("^%*%*Type%*%*:?%s*(.*)") or "")
              -- Update default if it's the generic fallback
              if current == "Task" or current == "Sub-task" then
                update_type_line(valid_types[1])
              else
                update_type_line(current)
              end
              break
            end
          end
        end)
      end
    end
  end)
end

return M
