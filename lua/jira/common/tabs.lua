local M = {}

---Setup tab keymaps for a buffer
---@param opts table Options containing:
---  - tabs: array of {key: string, id: string|table} - key is the number key, id is tab identifier
---  - state: table - state object with active_tab and tab_ranges
---  - on_switch: function(tab_id) - callback when tab is switched
---  - buffer: number - buffer to set keymaps on
function M.setup_tab_keymaps(opts)
  local keymap_opts = { noremap = true, silent = true, buffer = opts.buffer }
  
  -- Number key shortcuts
  for _, tab in ipairs(opts.tabs) do
    vim.keymap.set("n", tab.key, function()
      opts.on_switch(tab.id)
    end, keymap_opts)
  end
  
  -- Mouse click handler
  vim.keymap.set("n", "<LeftMouse>", function()
    local mouse = vim.fn.getmousepos()
    if mouse.line == 1 and opts.state.tab_ranges then
      for _, range in ipairs(opts.state.tab_ranges) do
        local tab_id = range.tab_id or range.view_name
        if mouse.column >= range.start_col and mouse.column <= range.end_col then
          opts.on_switch(tab_id)
          return
        end
      end
    end
  end, keymap_opts)
end

return M
