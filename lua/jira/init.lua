local M = {}

local api = vim.api

local state = require "jira.state"
local config = require "jira.config"
local render = require "jira.render"
local util = require "jira.util"
local sprint = require("jira.jira-api.sprint")
local ui = require("jira.ui")

M.setup = function(opts)
  config.setup(opts)
end

M.toggle_node = function()
  local cursor = api.nvim_win_get_cursor(state.win)
  local row = cursor[1] - 1
  local node = state.line_map[row]

  if node and node.children and #node.children > 0 then
    node.expanded = not node.expanded
    render.clear(state.buf)
    render.render_issue_tree(state.tree, state.current_view)

    local line_count = api.nvim_buf_line_count(state.buf)
    if cursor[1] > line_count then
      cursor[1] = line_count
    end
    api.nvim_win_set_cursor(state.win, cursor)
  end
end

local function get_cache_key(project_key, view_name)
  local key = project_key .. ":" .. view_name
  if view_name == "JQL" then
    key = key .. ":" .. (state.current_query or "Custom JQL")
    if state.current_query == "Custom JQL" then
      key = key .. ":" .. (state.custom_jql or "")
    end
  end
  return key
end

M.get_query_names = function()
  local queries = config.options.queries or {}
  local names = {}
  for name, _ in pairs(queries) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

M.handle_cr = function()
  local cursor = api.nvim_win_get_cursor(state.win)
  local row = cursor[1] - 1

  if state.current_view == "JQL" then
    if row == state.jql_line then
      M.prompt_jql()
      return
    end

    local query_name = state.query_map[row]
    if query_name then
      M.switch_query(query_name)
      return
    end
  end

  -- Fallback to toggle node if it's an issue line
  M.toggle_node()
end

M.prompt_jql = function()
  ui.open_jql_input(state.custom_jql or "", function(input)
    state.custom_jql = input
    state.current_query = "Custom JQL"
    M.load_view(state.project_key, "JQL")
  end)
end

M.switch_query = function(query_name)
  local queries = config.options.queries or {}
  state.current_query = query_name

  local jql = queries[query_name]
  state.custom_jql = string.format(jql, state.project_key)

  M.load_view(state.project_key, "JQL")
end

M.setup_keymaps = function()
  local opts = { noremap = true, silent = true, buffer = state.buf }

  -- Clear existing buffer keymaps
  local keys_to_clear = { "o", "S", "B", "J", "H", "K", "m", "gx", "r", "q", "a", "s", "c", "l", "e", "i", "<Esc>" }
  for _, k in ipairs(keys_to_clear) do
    pcall(vim.api.nvim_buf_del_keymap, state.buf, "n", k)
  end

  -- General
  vim.keymap.set("n", "q", function()
    if state.win and api.nvim_win_is_valid(state.win) then
      api.nvim_win_close(state.win, true)
    end
  end, opts)
  vim.keymap.set("n", "r", function()
    local cache_key = get_cache_key(state.project_key, state.current_view)
    state.cache[cache_key] = nil
    require("jira").load_view(state.project_key, state.current_view)
  end, opts)

  -- Navigation
  vim.keymap.set("n", "<Tab>", function() require("jira").toggle_node() end, opts)
  vim.keymap.set("n", "<CR>", function() require("jira").handle_cr() end, opts)

  -- View switching
  vim.keymap.set("n", "S", function() require("jira").load_view(state.project_key, "Active Sprint") end, opts)
  vim.keymap.set("n", "J", function()
    if state.current_view == "JQL" then
      require("jira").cycle_jql_query()
    else
      require("jira").load_view(state.project_key, "JQL")
    end
  end, opts)
  vim.keymap.set("n", "H", function() require("jira").load_view(state.project_key, "Help") end, opts)

  -- Issue Actions
  vim.keymap.set("n", "K", function() require("jira").show_issue_details() end, opts)
  vim.keymap.set("n", "m", function() require("jira").read_task() end, opts)
  vim.keymap.set("n", "gx", function() require("jira").open_in_browser() end, opts)
  vim.keymap.set("n", "s", function() require("jira").change_status() end, opts)
  vim.keymap.set("n", "a", function() require("jira").change_assignee() end, opts)
end

M.load_view = function(project_key, view_name)
  state.project_key = project_key
  state.current_view = view_name

  if view_name == "Help" then
    vim.schedule(function()
      if not state.win or not api.nvim_win_is_valid(state.win) then
        ui.create_window()
        ui.setup_static_highlights()
      end
      state.tree = {}
      state.line_map = {}
      render.clear(state.buf)
      render.render_help(view_name)
      M.setup_keymaps()
    end)
    return
  end

  if view_name == "JQL" and not state.current_query then
    local query_names = M.get_query_names()
    if #query_names > 0 then
      state.current_query = query_names[1]
      local queries = config.options.queries or {}
      state.custom_jql = string.format(queries[state.current_query], project_key)
    else
      state.current_query = "Custom JQL"
    end
  end

  local cache_key = get_cache_key(project_key, view_name)
  local cached_issues = state.cache[cache_key]

  local function process_issues(issues)
    vim.schedule(function()
      ui.stop_loading()

      -- Setup UI if not already created
      if not state.win or not api.nvim_win_is_valid(state.win) then
        ui.create_window()
        ui.setup_static_highlights()
      end

      if not issues or #issues == 0 then
        state.tree = {}
        render.clear(state.buf)
        render.render_issue_tree(state.tree, state.current_view)
        vim.notify("No issues found in " .. view_name .. ".", vim.log.levels.WARN)
      else
        state.tree = util.build_issue_tree(issues)
        render.clear(state.buf)
        render.render_issue_tree(state.tree, state.current_view)
        if not cached_issues then
          vim.notify("Loaded " .. view_name .. " for " .. project_key, vim.log.levels.INFO)
        end
      end

      M.setup_keymaps()
    end)
  end

  if cached_issues then
    process_issues(cached_issues)
    return
  end

  ui.start_loading("Loading " .. view_name .. " for " .. project_key .. "...")

  local fetch_fn
  if view_name == "Active Sprint" then
    fetch_fn = function(pk, cb) sprint.get_active_sprint_issues(pk, cb) end
  elseif view_name == "JQL" then
    fetch_fn = function(pk, cb) sprint.get_issues_by_jql(pk, state.custom_jql, cb) end
  end

  fetch_fn(project_key, function(issues, err)
    if err then
      vim.schedule(function()
        ui.stop_loading()
        vim.notify("Error: " .. err, vim.log.levels.ERROR)
      end)
      return
    end

    state.cache[cache_key] = issues
    process_issues(issues)
  end)
end

M.show_issue_details = function()
  local cursor = api.nvim_win_get_cursor(state.win)
  local row = cursor[1] - 1
  local node = state.line_map[row]
  if not node then return end

  ui.show_issue_details_popup(node)
end

M.change_status = function()
  local cursor = api.nvim_win_get_cursor(state.win)
  local row = cursor[1] - 1
  local node = state.line_map[row]
  if not node or not node.key then return end

  ui.start_loading("Fetching transitions for " .. node.key .. "...")
  local jira_api = require("jira.jira-api.api")
  jira_api.get_transitions(node.key, function(transitions, err)
    vim.schedule(function()
      ui.stop_loading()
      if err then
        vim.notify("Error fetching transitions: " .. err, vim.log.levels.ERROR)
        return
      end

      if #transitions == 0 then
        vim.notify("No available transitions for " .. node.key, vim.log.levels.WARN)
        return
      end

      local choices = {}
      local id_map = {}
      for _, t in ipairs(transitions) do
        table.insert(choices, t.name)
        id_map[t.name] = t.id
      end

      vim.ui.select(choices, { prompt = "Select Status for " .. node.key .. ":" }, function(choice)
        if not choice then return end
        local transition_id = id_map[choice]

        ui.start_loading("Updating status to " .. choice .. "...")
        jira_api.transition_issue(node.key, transition_id, function(success, t_err)
          vim.schedule(function()
            ui.stop_loading()
            if t_err then
              vim.notify("Error updating status: " .. t_err, vim.log.levels.ERROR)
              return
            end

            vim.notify("Updated " .. node.key .. " to " .. choice, vim.log.levels.INFO)
            -- Clear cache and reload view
            local cache_key = get_cache_key(state.project_key, state.current_view)
            state.cache[cache_key] = nil
            M.load_view(state.project_key, state.current_view)
          end)
        end)
      end)
    end)
  end)
end

M.change_assignee = function()
  local cursor = api.nvim_win_get_cursor(state.win)
  local row = cursor[1] - 1
  local node = state.line_map[row]
  if not node or not node.key then return end

  local jira_api = require("jira.jira-api.api")
  local choices = { "Assign to Me", "Unassign" }

  vim.ui.select(choices, { prompt = "Change Assignee for " .. node.key .. ":" }, function(choice)
    if not choice then return end

    if choice == "Assign to Me" then
      ui.start_loading("Fetching your account info...")
      jira_api.get_myself(function(me, m_err)
        vim.schedule(function()
          ui.stop_loading()
          if m_err or not me or not me.accountId then
            vim.notify("Error fetching account info: " .. (m_err or "Unknown error"), vim.log.levels.ERROR)
            return
          end

          ui.start_loading("Assigning " .. node.key .. " to you...")
          jira_api.assign_issue(node.key, me.accountId, function(success, a_err)
            vim.schedule(function()
              ui.stop_loading()
              if a_err then
                vim.notify("Error assigning issue: " .. a_err, vim.log.levels.ERROR)
                return
              end
              vim.notify("Assigned " .. node.key .. " to you", vim.log.levels.INFO)
              local cache_key = get_cache_key(state.project_key, state.current_view)
              state.cache[cache_key] = nil
              M.load_view(state.project_key, state.current_view)
            end)
          end)
        end)
      end)
    elseif choice == "Unassign" then
      ui.start_loading("Unassigning " .. node.key .. "...")
      jira_api.assign_issue(node.key, "-1", function(success, a_err)
        vim.schedule(function()
          ui.stop_loading()
          if a_err then
            vim.notify("Error unassigning issue: " .. a_err, vim.log.levels.ERROR)
            return
          end
          vim.notify("Unassigned " .. node.key, vim.log.levels.INFO)
          local cache_key = get_cache_key(state.project_key, state.current_view)
          state.cache[cache_key] = nil
          M.load_view(state.project_key, state.current_view)
        end)
      end)
    end
  end)
end

M.read_task = function()
  local cursor = api.nvim_win_get_cursor(state.win)
  local row = cursor[1] - 1
  local node = state.line_map[row]
  if not node or not node.key then return end

  ui.start_loading("Fetching full details for " .. node.key .. "...")
  local jira_api = require("jira.jira-api.api")
  jira_api.get_issue(node.key, function(issue, err)
    vim.schedule(function()
      ui.stop_loading()
      if err then
        vim.notify("Error: " .. err, vim.log.levels.ERROR)
        return
      end

      local fields = issue.fields or {}
      local lines = {}
      table.insert(lines, "# " .. issue.key .. ": " .. (fields.summary or ""))
      table.insert(lines, "")
      table.insert(lines, "**Status**: " .. (fields.status and fields.status.name or "Unknown"))
      table.insert(lines, "**Assignee**: " .. (fields.assignee and fields.assignee.displayName or "Unassigned"))
      table.insert(lines, "**Priority**: " .. (fields.priority and fields.priority.name or "None"))
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

      local p_config = config.get_project_config(state.project_key)
      local ac_field = p_config.acceptance_criteria_field
      if ac_field and fields[ac_field] then
        table.insert(lines, "")
        table.insert(lines, "## Acceptance Criteria")
        table.insert(lines, "")
        local ac_md = util.adf_to_markdown(fields[ac_field])
        for line in ac_md:gmatch("[^\r\n]+") do
          table.insert(lines, line)
        end
      end

      ui.open_markdown_view("Jira: " .. issue.key, lines)
    end)
  end)
end

M.open_in_browser = function()
  local cursor = api.nvim_win_get_cursor(state.win)
  local row = cursor[1] - 1
  local node = state.line_map[row]
  if not node or not node.key then return end

  local base = config.options.jira.base
  if not base or base == "" then
    vim.notify("Jira base URL is not configured", vim.log.levels.ERROR)
    return
  end

  if not base:match("/$") then
    base = base .. "/"
  end

  local url = base .. "browse/" .. node.key
  vim.ui.open(url)
end

M.open = function(project_key)
  -- If already open, just focus
  if state.win and api.nvim_win_is_valid(state.win) then
    api.nvim_set_current_win(state.win)
    return
  end

  -- Validate Config
  local jc = config.options.jira
  if not jc.base or jc.base == "" or not jc.email or jc.email == "" or not jc.token or jc.token == "" then
    vim.notify("Jira configuration is missing. Please run setup() with base, email, and token.", vim.log.levels.ERROR)
    return
  end

  if not project_key then
    project_key = vim.fn.input("Jira Project Key: ")
  end

  if not project_key or project_key == "" then
    vim.notify("Project key is required", vim.log.levels.ERROR)
    return
  end

  M.load_view(project_key, "Active Sprint")
end

return M

