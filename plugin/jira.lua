vim.api.nvim_create_user_command("Jira", function()
  require("jira").open()
end, {})

vim.api.nvim_create_user_command("JiraClose", function()
  require("jira").close()
end, {})
