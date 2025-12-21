local state = {
  buf = nil,
  win = nil,
  ns = vim.api.nvim_create_namespace("Jira"),

  config = {}
}

return state
