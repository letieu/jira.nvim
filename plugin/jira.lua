vim.api.nvim_create_user_command("Jira", function(opts)
  require("jira").open(opts.args)
end, { nargs = "*" })
-- vim: set ts=2 sts=2 sw=2 et ai si sta:
