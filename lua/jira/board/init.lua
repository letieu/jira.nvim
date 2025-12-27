local M = {}

local api = vim.api
local state = require("jira.board.state")
local config = require("jira.common.config")
local render = require("jira.board.render")
local util = require("jira.common.util")
local helper = require("jira.board.helper")
local sprint = require("jira.jira-api.sprint")
local common_ui = require("jira.common.ui")
local board_ui = require("jira.board.ui")

function M.refresh_view()
  local cache_key = helper.get_cache_key(state.project_key, state.current_view)
  state.cache[cache_key] = nil
  
  -- Clear sprint cache for this project if in Active Sprint view
  if state.current_view == "Active Sprint" and state.project_key then
    sprint.clear_sprint_cache(state.project_key)
  end
  
  M.load_view(state.project_key, state.current_view)
end

function M.toggle_node()
  local cursor = api.nvim_win_get_cursor(state.win)
  local node = helper.get_node_at_cursor()

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

function M.get_query_names()
  local queries = config.options.queries or {}
  local names = {}
  for name, _ in pairs(queries) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

function M.handle_cr()
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

  -- Try to open issue if on an issue line
  local node = helper.get_node_at_cursor()
  if node and node.key then
    -- If node has children and is collapsed, expand it
    if node.children and #node.children > 0 and not node.expanded then
      M.toggle_node()
      return
    end
    
    -- Otherwise open the issue
    require("jira.issue").open(node.key)
    return
  end

  -- Fallback to toggle node if it's an issue line
  M.toggle_node()
end

function M.prompt_jql()
  board_ui.open_jql_input(state.custom_jql or "", function(input)
    state.custom_jql = input
    state.current_query = "Custom JQL"
    M.load_view(state.project_key, "JQL")
  end)
end

function M.switch_query(query_name)
  local queries = config.options.queries or {}
  state.current_query = query_name

  local jql = queries[query_name]
  state.custom_jql = jql:format(state.project_key)

  M.load_view(state.project_key, "JQL")
end

function M.cycle_jql_query()
  local query_names = M.get_query_names()
  if #query_names == 0 then
    return
  end

  local current_idx = 0
  for i, name in ipairs(query_names) do
    if name == state.current_query then
      current_idx = i
      break
    end
  end

  local next_idx = (current_idx % #query_names) + 1
  M.switch_query(query_names[next_idx])
end

function M.setup_keymaps()
  local opts = { noremap = true, silent = true, buffer = state.buf }

  -- Clear existing buffer keymaps
  local keys_to_clear =
    { "o", "S", "B", "J", "H", "K", "m", "gx", "r", "q", "gs", "ga", "gw", "gb", "<Esc>", "s", "a", "t", "co" }
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
    require("jira.board").refresh_view()
  end, opts)

  -- Navigation
  vim.keymap.set("n", "<Tab>", function()
    require("jira.board").toggle_node()
  end, opts)
  vim.keymap.set("n", "<CR>", function()
    require("jira.board").handle_cr()
  end, opts)

  -- View switching
  local tabs = require("jira.common.tabs")
  tabs.setup_tab_keymaps({
    tabs = {
      { key = "1", id = "Active Sprint" },
      { key = "2", id = "JQL" },
      { key = "3", id = "Help" },
    },
    state = state,
    on_switch = function(view_name)
      if view_name == "JQL" and state.current_view == "JQL" then
        require("jira.board").cycle_jql_query()
      else
        require("jira.board").load_view(state.project_key, view_name)
      end
    end,
    buffer = state.buf,
  })
  
  -- Special handling for key 2 to cycle JQL
  vim.keymap.set("n", "2", function()
    if state.current_view == "JQL" then
      require("jira.board").cycle_jql_query()
    else
      require("jira.board").load_view(state.project_key, "JQL")
    end
  end, opts)

  -- Issue Actions
  vim.keymap.set("n", "K", function()
    require("jira.board").show_issue_details()
  end, opts)
  vim.keymap.set("n", "gd", function()
    require("jira.board").read_task()
  end, opts)
  vim.keymap.set("n", "gf", function()
    vim.ui.input({ prompt = "Issue Key: " }, function(input)
      if not input or input == "" then
        return
      end
      require("jira.issue").open(input)
    end)
  end, opts)
  vim.keymap.set("n", "gx", function()
    require("jira.board").open_in_browser()
  end, opts)
  vim.keymap.set("n", "gs", function()
    require("jira.board").change_status()
  end, opts)
  vim.keymap.set("n", "ga", function()
    require("jira.board").change_assignee()
  end, opts)
  vim.keymap.set("n", "gw", function()
    require("jira.board").log_time()
  end, opts)
  vim.keymap.set("n", "gb", function()
    require("jira.board").checkout_branch()
  end, opts)
end

function M.load_view(project_key, view_name)
  local old_cursor = nil
  if state.win and api.nvim_win_is_valid(state.win) and state.current_view == view_name then
    old_cursor = api.nvim_win_get_cursor(state.win)
  end

  state.project_key = project_key
  state.current_view = view_name

  if view_name == "Help" then
    vim.schedule(function()
      if not state.win or not api.nvim_win_is_valid(state.win) then
        board_ui.create_window()
        util.setup_static_highlights()
      end
      state.tree = {}
      state.line_map = {}
      render.clear(state.buf)
      render.render_help(view_name)
      if old_cursor and state.win and api.nvim_win_is_valid(state.win) then
        local line_count = api.nvim_buf_line_count(state.buf)
        if old_cursor[1] > line_count then
          old_cursor[1] = line_count
        end
        api.nvim_win_set_cursor(state.win, old_cursor)
      end
      M.setup_keymaps()
    end)
    return
  end

  if view_name == "JQL" and not state.current_query then
    local query_names = M.get_query_names()
    if #query_names > 0 then
      state.current_query = query_names[1]
      local queries = config.options.queries or {}
      state.custom_jql = queries[state.current_query]:format(project_key)
    else
      state.current_query = "Custom JQL"
    end
  end

  local cache_key = helper.get_cache_key(project_key, view_name)
  local cached_issues = state.cache[cache_key]

  local function process_issues(issues)
    vim.schedule(function()
      common_ui.stop_loading()

      -- Setup UI if not already created
      if not state.win or not api.nvim_win_is_valid(state.win) then
        board_ui.create_window()
        util.setup_static_highlights()
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

      if old_cursor and state.win and api.nvim_win_is_valid(state.win) then
        local line_count = api.nvim_buf_line_count(state.buf)
        if old_cursor[1] > line_count then
          old_cursor[1] = line_count
        end
        api.nvim_win_set_cursor(state.win, old_cursor)
      end

      M.setup_keymaps()
    end)
  end

  if cached_issues then
    process_issues(cached_issues)
    return
  end

  common_ui.start_loading("Loading " .. view_name .. " for " .. project_key .. "...")

  local fetch_fn
  if view_name == "Active Sprint" then
    fetch_fn = function(pk, cb)
      -- Don't force refresh sprint cache just because issues aren't cached
      sprint.get_active_sprint_issues(pk, cb, false)
    end
  elseif view_name == "JQL" then
    fetch_fn = function(pk, cb)
      sprint.get_issues_by_jql(pk, state.custom_jql, cb)
    end
  end

  fetch_fn(project_key, function(issues, err)
    if err then
      vim.schedule(function()
        common_ui.stop_loading()
        vim.notify("Error: " .. err, vim.log.levels.ERROR)
      end)
      return
    end

    state.cache[cache_key] = issues
    process_issues(issues)
  end)
end

function M.show_issue_details()
  local node = helper.get_node_at_cursor()
  if not node then
    return
  end

  board_ui.show_issue_details_popup(node)
end

function M.change_status()
  local node = helper.get_node_at_cursor()
  if not node or not node.key then
    return
  end

  common_ui.start_loading("Fetching transitions for " .. node.key .. "...")
  local jira_api = require("jira.jira-api.api")
  jira_api.get_transitions(node.key, function(transitions, err)
    vim.schedule(function()
      common_ui.stop_loading()
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
        if not choice then
          return
        end
        local transition_id = id_map[choice]

        common_ui.start_loading("Updating status to " .. choice .. "...")
        jira_api.transition_issue(node.key, transition_id, function(_, t_err)
          vim.schedule(function()
            common_ui.stop_loading()
            if t_err then
              vim.notify("Error updating status: " .. t_err, vim.log.levels.ERROR)
              return
            end

            vim.notify("Updated " .. node.key .. " to " .. choice, vim.log.levels.INFO)
            M.refresh_view()
          end)
        end)
      end)
    end)
  end)
end

function M.change_assignee()
  local node = helper.get_node_at_cursor()
  if not node or not node.key then
    return
  end

  local jira_api = require("jira.jira-api.api")
  local choices = { "Assign to Me", "Unassign" }

  vim.ui.select(choices, { prompt = "Change Assignee for " .. node.key .. ":" }, function(choice)
    if not choice then
      return
    end

    if choice == "Assign to Me" then
      common_ui.start_loading("Fetching your account info...")
      jira_api.get_myself(function(me, m_err)
        vim.schedule(function()
          common_ui.stop_loading()
          if m_err or not me or not me.accountId then
            vim.notify("Error fetching account info: " .. (m_err or "Unknown error"), vim.log.levels.ERROR)
            return
          end

          common_ui.start_loading("Assigning " .. node.key .. " to you...")
          jira_api.assign_issue(node.key, me.accountId, function(_, a_err)
            vim.schedule(function()
              common_ui.stop_loading()
              if a_err then
                vim.notify("Error assigning issue: " .. a_err, vim.log.levels.ERROR)
                return
              end
              vim.notify("Assigned " .. node.key .. " to you", vim.log.levels.INFO)
              M.refresh_view()
            end)
          end)
        end)
      end)
    elseif choice == "Unassign" then
      common_ui.start_loading("Unassigning " .. node.key .. "...")
      jira_api.assign_issue(node.key, "-1", function(_, a_err)
        vim.schedule(function()
          common_ui.stop_loading()
          if a_err then
            vim.notify("Error unassigning issue: " .. a_err, vim.log.levels.ERROR)
            return
          end
          vim.notify("Unassigned " .. node.key, vim.log.levels.INFO)
          M.refresh_view()
        end)
      end)
    end
  end)
end

function M.read_task()
  local node = helper.get_node_at_cursor()
  if not node or not node.key then
    return
  end

  require("jira.issue").open(node.key)
end

function M.log_time()
  local node = helper.get_node_at_cursor()
  if not node or not node.key then
    return
  end

  local jira_api = require("jira.jira-api.api")

  vim.ui.input({ prompt = "Add time for " .. node.key .. " (h):" }, function(value)
    if not value then
      return
    end
    value = util.strim(value)
    if value == "" then
      return
    end
    if value == "0" then
      return
    end

    local time_string = value .. "h"

    vim.ui.input({ prompt = "Comment (optional): " }, function(comment)
      common_ui.start_loading("Updating time log...")
      jira_api.add_worklog(node.key, time_string, comment, function(_, err)
        vim.schedule(function()
          common_ui.stop_loading()
          if err then
            vim.notify("Error logging time: " .. err, vim.log.levels.ERROR)
            return
          end
          vim.notify("Updated " .. node.key .. " time ", vim.log.levels.INFO)
          M.refresh_view()
        end)
      end)
    end)
  end)
end

function M.checkout_branch()
  local node = helper.get_node_at_cursor()
  if not node or not node.key then
    return
  end

  local cmd = string.format('git branch --list "*%s*"', node.key)
  local output = vim.fn.system(cmd)
  local branches = {}
  for s in output:gmatch("[^\r\n]+") do
    local branch = s:gsub("^[*%s]+", ""):gsub("%s+$", "")
    table.insert(branches, branch)
  end

  if #branches == 0 then
    local slug = (node.summary or ""):gsub("%s+", "-"):gsub("[^%w%-]", ""):lower()
    local prefix = "feature/"
    if node.type then
      local t = node.type:lower()
      if t:find("bug") then
        prefix = "bugfix/"
      elseif t:find("hotfix") then
        prefix = "hotfix/"
      end
    end
    local suggested_name = prefix .. node.key .. "-" .. slug
    vim.ui.input({ prompt = "Create branch: ", default = suggested_name }, function(input)
      if not input or input == "" then
        return
      end
      local out = vim.fn.system("git checkout -b " .. input)
      if vim.v.shell_error ~= 0 then
        vim.notify("Error creating branch: " .. out, vim.log.levels.ERROR)
      else
        vim.notify("Created and checked out " .. input, vim.log.levels.INFO)
      end
    end)
  elseif #branches == 1 then
    local branch = branches[1]
    vim.ui.select({ "Yes", "No" }, { prompt = "Checkout " .. branch .. "?" }, function(choice)
      if choice == "Yes" then
        local out = vim.fn.system("git checkout " .. branch)
        if vim.v.shell_error ~= 0 then
          vim.notify("Error checking out branch: " .. out, vim.log.levels.ERROR)
        else
          vim.notify("Checked out " .. branch, vim.log.levels.INFO)
        end
      end
    end)
  else
    vim.ui.select(branches, { prompt = "Select branch to checkout:" }, function(choice)
      if not choice then
        return
      end
      local out = vim.fn.system("git checkout " .. choice)
      if vim.v.shell_error ~= 0 then
        vim.notify("Error checking out branch: " .. out, vim.log.levels.ERROR)
      else
        vim.notify("Checked out " .. choice, vim.log.levels.INFO)
      end
    end)
  end
end

function M.open_in_browser()
  local node = helper.get_node_at_cursor()
  if not node or not node.key then
    return
  end

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

function M.open(project_key)
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
-- vim: set ts=2 sts=2 sw=2 et ai si sta:
