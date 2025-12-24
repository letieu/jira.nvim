> [!CAUTION]
> **Still in early development, will have breaking changes!**

# jira.nvim

A Neovim plugin for managing JIRA tasks with a beautiful UI.

![Showcase](https://github.com/user-attachments/assets/611cdfb4-29ed-4d59-8362-74c142e81257)

> [!NOTE]
> Disucssion: How do you want to create, edit the jira ticket in this plugin?
> https://github.com/letieu/jira.nvim/discussions/1

## Features (AI generated)

- 📋 View active sprint tasks
- 👥 Query tasks by custom JQL
- 📝 Read task as markdown
- 🔄 Change task status
- ⏱️ Log time on tasks
- 👤 Assign tasks
- 🎨 Git integration
- 🎨 Edit task
- 🎨 Comment
- ⏱️ Work report

---

## Configuration

```lua
require('jira').setup({
  -- Jira connection settings
  jira = {
    base = "https://your-domain.atlassian.net", -- Base URL of your Jira instance
    email = "your-email@example.com",           -- Your Jira email
    token = "your-api-token",                   -- Your Jira API token
    limit = 200,                                -- Global limit of tasks per view
  },

  -- Saved JQL queries for the JQL tab
  -- Use %s as a placeholder for the project key
  queries = {
    ["Backlog"] = "project = '%s' AND (sprint is EMPTY OR sprint not in openSprints()) AND statusCategory != Done ORDER BY Rank ASC",
    ["My Tasks"] = "assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC",
  },

  -- Project-specific overrides
  -- Still think about this config, maybe not good enough
  projects = {
    ["DEV"] = {
      story_point_field = "customfield_10035",      -- Custom field ID for story points
      custom_fields = { -- Custom field to display in markdown view
        { key = "customfield_10016", label = "Acceptance Criteria" }
      },
    }
  }
})
```

---

## Usage

Run the following command to open the Jira board:

```vim
:Jira <PROJECT_KEY>
```

If you don't provide a project key, you will be prompted to enter one.

### Keybindings (Normal Mode)

| Key  | Action    |
|------|-----------|
| `H`  | Show help |

---

## Tips

- How to get custom field list -> go to `https://your-domain.atlassian.net/rest/api/3/field`

---

## TODO
- [x] Jira sprint board
- [x] Config
- [x] Expand, Collapse
- [x] Read task (Markdown)
- [x] Format time
- [x] Backlog (via JQL Dashboard)
- [x] Custom JQL & Saved Queries
- [x] Change status
- [x] Change assignee
- [x] Log time
- [ ] **WORKING ON**: Task info view mode
- [ ] Comment
- [ ] Edit task
- [ ] Update UI when terminal size change
...

---

## Thanks

Big thanks for `gemini` CLI free tier.

---

## License

MIT © Tieu Le
