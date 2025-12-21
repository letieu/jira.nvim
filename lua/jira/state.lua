local state = {
  buf = nil,
  win = nil,
  dim_win = nil,
  ns = vim.api.nvim_create_namespace("Jira"),
  status_hls = {},

  config = {
    jira = {
      base = os.getenv("JIRA_BASE"),
      email = os.getenv("JIRA_EMAIL"),
      token = os.getenv("JIRA_TOKEN"),
      project = os.getenv("JIRA_PROJECT"),
      story_point_field = os.getenv("JIRA_STORY_POINT_FIELD") or "customfield_10023",
    }
  }
}

return state
